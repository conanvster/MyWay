extends RefCounted
## Мережа й файли апдейтера. Усі `job_*` блокують і йдуть у фоновому
## потоці (`updater.gd` стежить за ним); стан для смуги прогресу — у
## полях під `_mutex`.
##
## Кожна функція вертає словник: успіх — дані, збій — {"why": "…"} з
## поясненням людською мовою. Мовчазних збоїв немає (P3).

const CHUNK := 1 << 20
const CONNECT_WAIT_MS := 6000
## Скільки сервер може мовчати посеред файла, доки не скажемо «замовк».
const STALL_MS := 30000
## Стан установленого клієнта: випуск і версія. Пишеться лише після
## ПОВНОГО оновлення; на час завантаження стирається.
const STATE_FILE := ".myway-installed.json"
## Кеш хешів: {шлях: [розмір, час зміни, sha256]}, щоб не рахувати
## 1,6 ГБ на кожному старті.
const HASH_CACHE := ".myway-hashes.json"
## Мітка «тека наша»: зайве з неї апдейтер прибирає сам.
const MARK_FILE := ".myway-client"
const OWN_FILES := [STATE_FILE, HASH_CACHE, MARK_FILE]

var host := ""
var port := 24600
## linux, macos або windows: чий маніфест і чиї файли.
var platform := ""
## Тека клієнта (абсолютний шлях).
var install := ""

var _mutex := Mutex.new()
var _done := 0
var _total := 0
var _what := ""
var _stop := false
## Для проби: обірвати завантаження, коли за цей запуск прийшло стільки
## байтів (імітація обриву зв'язку). −1 — ні.
var abort_after := -1
## Що завантажено останнім `job_update` (для проби й журналу) і звідки
## докачано: [[шлях, з якого байта], …].
var fetched: Array[String] = []
var resumed: Array = []


func progress() -> Dictionary:
	_mutex.lock()
	var out := {"done": _done, "total": _total, "what": _what}
	_mutex.unlock()
	return out


func stop() -> void:
	_mutex.lock()
	_stop = true
	_mutex.unlock()


func _stopped() -> bool:
	_mutex.lock()
	var out := _stop
	_mutex.unlock()
	return out


func _put(done: int, total: int, what: String) -> void:
	_mutex.lock()
	_done = done
	_total = total
	_what = what
	_mutex.unlock()


func _add(bytes: int) -> void:
	_mutex.lock()
	_done += bytes
	_mutex.unlock()


# ── адреса ─────────────────────────────────────────────────────────────

## «192.168.1.48» або «192.168.1.48:24600» → {"host", "port"} або {"why"}.
static func parse_address(text: String, default_port: int) -> Dictionary:
	var line := text.strip_edges()
	if line == "":
		return {"why": "введи IP сервера, наприклад 192.168.1.48"}
	if " " in line:
		return {"why": "в адресі не має бути пробілів: «%s»" % line}
	if line.begins_with("http://") or line.begins_with("https://"):
		return {"why": "лише IP, без «http://»: наприклад 192.168.1.48"}
	var where := line
	var number := default_port
	if line.count(":") == 1:
		where = line.get_slice(":", 0)
		var tail := line.get_slice(":", 1)
		if not tail.is_valid_int() or int(tail) < 1 or int(tail) > 65535:
			return {"why": "порт «%s» — має бути число від 1 до 65535" % tail}
		number = int(tail)
	elif line.count(":") > 1:
		return {"why": "IPv6 не підтримується — введи IPv4, як 192.168.1.48"}
	if where == "" or "/" in where:
		return {"why": "незрозуміла адреса «%s»" % line}
	return {"host": where, "port": number}


## Шлях із маніфесту безпечний: відносний, без «..», без «\», без «:».
## Сервер міг би (зламаний чи чужий) підсунути «../../.bashrc».
static func safe_relative(path: String) -> bool:
	if path == "" or path.begins_with("/") or "\\" in path or ":" in path:
		return false
	for part in path.split("/"):
		if part == "" or part == "." or part == "..":
			return false
	return true


# ── HTTP ───────────────────────────────────────────────────────────────

func _where() -> String:
	return "%s:%d" % [host, port]


## З'єднатись. {"client": HTTPClient} або {"why"}.
func _connect() -> Dictionary:
	var http := HTTPClient.new()
	http.blocking_mode_enabled = true
	http.read_chunk_size = CHUNK
	var err := http.connect_to_host(host, port)
	if err != OK:
		return {"why": "до %s не з'єднатись: %s" % [_where(),
				error_string(err)]}
	var deadline := Time.get_ticks_msec() + CONNECT_WAIT_MS
	while http.get_status() in [HTTPClient.STATUS_RESOLVING,
			HTTPClient.STATUS_CONNECTING]:
		http.poll()
		if Time.get_ticks_msec() > deadline:
			return {"why": ("сервер оновлень %s не відповів за %d с: " \
					+ "невірний IP, сервіс не запущений (./run-updates.sh) " \
					+ "або брандмауер не пускає TCP %d")
					% [_where(), CONNECT_WAIT_MS / 1000, port]}
		OS.delay_msec(10)
	match http.get_status():
		HTTPClient.STATUS_CONNECTED:
			return {"client": http}
		HTTPClient.STATUS_CANT_RESOLVE:
			return {"why": "адресу «%s» не знайдено" % host}
		_:
			return {"why": ("сервер оновлень %s відхилив з'єднання: " \
					+ "сервіс не запущений (./run-updates.sh), не той порт " \
					+ "або брандмауер не пускає TCP %d") % [_where(), port]}


## Надіслати запит і дочекатись заголовків. {"client", "code",
## "headers"} або {"why"}.
func _request(path: String, headers: PackedStringArray) -> Dictionary:
	var opened := _connect()
	if opened.has("why"):
		return opened
	var http: HTTPClient = opened["client"]
	var encoded := PackedStringArray()
	for part in path.split("/"):
		encoded.append(part.uri_encode())
	var err := http.request(HTTPClient.METHOD_GET, "/".join(encoded),
			headers)
	if err != OK:
		return {"why": "запит %s не пішов: %s" % [path, error_string(err)]}
	var deadline := Time.get_ticks_msec() + STALL_MS
	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		http.poll()
		if Time.get_ticks_msec() > deadline:
			return {"why": "сервер %s прийняв запит %s і замовк"
					% [_where(), path]}
		OS.delay_msec(5)
	if not http.has_response():
		return {"why": "сервер %s обірвав з'єднання на запиті %s"
				% [_where(), path]}
	return {"client": http, "code": http.get_response_code(),
			"headers": http.get_response_headers_as_dictionary()}


## Невеликий текст (config, маніфест). {"text"} або {"why"}.
func get_text(path: String) -> Dictionary:
	var asked := _request(path, PackedStringArray())
	if asked.has("why"):
		return asked
	var http: HTTPClient = asked["client"]
	var body := PackedByteArray()
	while http.get_status() == HTTPClient.STATUS_BODY:
		http.poll()
		body.append_array(http.read_response_body_chunk())
	http.close()
	if asked["code"] != 200:
		return {"why": "сервер %s на %s відповів кодом %d: %s" % [_where(),
				path, asked["code"],
				body.get_string_from_utf8().strip_edges()]}
	return {"text": body.get_string_from_utf8()}


func get_json(path: String) -> Dictionary:
	var got := get_text(path)
	if got.has("why"):
		return got
	var parsed: Variant = JSON.parse_string(got["text"])
	if parsed is not Dictionary:
		return {"why": "сервер %s віддав на %s не JSON-об'єкт" % [_where(),
				path]}
	return {"data": parsed}


# ── завдання (у фоновому потоці) ─────────────────────────────────────────

## config.json + маніфест своєї платформи + звірка локальних файлів.
func job_check(platform: String) -> Dictionary:
	_put(0, 0, "питаю сервер оновлень %s" % _where())
	var config := get_json("/config.json")
	if config.has("why"):
		return config
	var out := {"config": config["data"]}
	var manifest := get_json("/manifest/%s.json" % platform)
	if manifest.has("why"):
		out["why"] = "на сервері немає клієнта для %s: %s" % [platform,
				manifest["why"]]
		return out
	var why := _manifest_problem(manifest["data"])
	if why != "":
		out["why"] = why
		return out
	out["manifest"] = manifest["data"]
	out.merge(verify(manifest["data"]))
	return out


func _manifest_problem(manifest: Dictionary) -> String:
	var files: Variant = manifest.get("files")
	if files is not Array or str(manifest.get("launch", "")) == "":
		return "маніфест пошкоджений: немає files або launch"
	if not safe_relative(str(manifest["launch"])):
		return "маніфест: небезпечний шлях запуску «%s»" % manifest["launch"]
	for entry: Variant in files:
		if entry is not Dictionary or not safe_relative(
				str(entry.get("path", ""))):
			return "маніфест: небезпечний шлях «%s» — відмовляюсь" \
					% str(entry.get("path", "") if entry is Dictionary
					else entry)
		if entry.has("link"):
			var target := str(entry["link"])
			var joined := str(entry["path"]).get_base_dir().path_join(
					target).simplify_path()
			if target.begins_with("/") or not safe_relative(joined):
				return "маніфест: посилання «%s» веде за межі клієнта" \
						% entry["path"]
	return ""


## Що з маніфесту не збігається локально: {"need": [записи],
## "need_bytes", "installed": випуск або 0}.
func verify(manifest: Dictionary) -> Dictionary:
	var cache := _read_json(install.path_join(HASH_CACHE))
	var fresh := {}
	var need: Array = []
	var need_bytes := 0
	var total := 0
	for entry: Dictionary in manifest["files"]:
		total += int(entry.get("size", 0))
	_put(0, total, "звіряю файли")
	for entry: Dictionary in manifest["files"]:
		if _stopped():
			return {"why": "звірку зупинено"}
		var path := install.path_join(str(entry["path"]))
		if entry.has("link"):
			if not (DirAccess.dir_exists_absolute(path.get_base_dir())
					and DirAccess.open(path.get_base_dir()).is_link(path)
					and DirAccess.open(path.get_base_dir()).read_link(path)
					== str(entry["link"])):
				need.append(entry)
			continue
		var size := int(entry["size"])
		var sha := ""
		if FileAccess.file_exists(path):
			var have_size := _size_of(path)
			var stamp := FileAccess.get_modified_time(path)
			var known: Variant = cache.get(entry["path"])
			if known is Array and known.size() == 3 \
					and int(known[0]) == have_size and int(known[1]) == stamp:
				sha = str(known[2])
				_add(have_size)
			elif have_size == size:
				sha = _hash_file(path)
			else:
				_add(size)
			if sha != "":
				fresh[entry["path"]] = [have_size, stamp, sha]
		else:
			_add(size)
		if sha != str(entry["sha256"]):
			need.append(entry)
			need_bytes += size
	if DirAccess.dir_exists_absolute(install):
		_write_json(install.path_join(HASH_CACHE), fresh)
	var state := _read_json(install.path_join(STATE_FILE))
	var installed := int(state.get("release", 0))
	var present := FileAccess.file_exists(install.path_join(
			str(manifest["launch"])))
	if need.is_empty():
		installed = int(manifest.get("release", 0))
		if int(state.get("release", -1)) != installed:
			_write_json(install.path_join(STATE_FILE), {"release": installed,
					"version": manifest.get("version", "")})
	return {"need": need, "need_bytes": need_bytes,
			"installed": installed if present else 0, "present": present}


## Завантажити записи `need`. {"ok": true} або {"why"}.
func job_update(manifest: Dictionary, need: Array) -> Dictionary:
	fetched.clear()
	resumed.clear()
	var prepared := _prepare_dir()
	if prepared != "":
		return {"why": prepared}
	var total := 0
	var left := 0
	for entry: Dictionary in need:
		if entry.has("link"):
			continue
		total += int(entry["size"])
		var part := install.path_join(str(entry["path"])) + ".part"
		left += int(entry["size"]) - (_size_of(part)
				if FileAccess.file_exists(part) else 0)
	var free := DirAccess.open(install).get_space_left()
	# Запас 64 МБ: файл замінюється ПІСЛЯ перевірки, і обидва якийсь час
	# лежать поруч.
	if free >= 0 and free < left + (64 << 20):
		return {"why": "немає місця на диску: треба %s, вільно %s (тека %s)"
				% [_mb(left + (64 << 20)), _mb(free), install]}
	# Оновлення почалось — старий стан уже не правда: перерване посеред
	# дороги не пустить грати старим, наполовину заміненим клієнтом.
	DirAccess.remove_absolute(install.path_join(STATE_FILE))
	_put(0, total, "")
	var got_bytes := [0]
	for entry: Dictionary in need:
		if _stopped():
			return {"why": "оновлення зупинено — натисни «Оновити», щоб " \
					+ "докачати"}
		var why := _link(entry) if entry.has("link") \
				else _download(entry, got_bytes)
		if why != "":
			return {"why": why}
	_prune(manifest)
	var checked := verify(manifest)
	if not checked.get("need", [1]).is_empty():
		return {"why": "після оновлення %d файлів досі не збігаються з " \
				% checked["need"].size() + "маніфестом — спробуй ще раз"}
	if OS.get_name() == "macOS" and str(manifest.get("app", "")) != "":
		var note := _fix_macos(manifest)
		if note != "":
			checked["note"] = note
	return {"ok": true, "checked": checked}


func _prepare_dir() -> String:
	if not DirAccess.dir_exists_absolute(install):
		var err := DirAccess.make_dir_recursive_absolute(install)
		if err != OK:
			return "не створити теку клієнта %s: %s" % [install,
					error_string(err)]
	if not FileAccess.file_exists(install.path_join(MARK_FILE)):
		var dir := DirAccess.open(install)
		if dir == null:
			return "тека клієнта %s не відкривається" % install
		if not (dir.get_files().is_empty()
				and dir.get_directories().is_empty()):
			return "тека %s не порожня й не створена апдейтером — " % install \
					+ "не чіпаю її; обери іншу або спорожни"
		var mark := FileAccess.open(install.path_join(MARK_FILE),
				FileAccess.WRITE)
		if mark == null:
			return "немає права писати в %s: %s" % [install, error_string(
					FileAccess.get_open_error())]
		mark.store_line("Тут клієнт MyWay, яким керує апдейтер.")
	return ""


## Один файл: у `<шлях>.part` з докачуванням, перевірка SHA-256,
## заміна перейменуванням. Порожній рядок — усе гаразд.
func _download(entry: Dictionary, got_bytes: Array) -> String:
	var name := str(entry["path"])
	var final := install.path_join(name)
	var part := final + ".part"
	var size := int(entry["size"])
	var want := str(entry["sha256"])
	var err := DirAccess.make_dir_recursive_absolute(final.get_base_dir())
	if err != OK:
		return "не створити теку %s: %s" % [final.get_base_dir(),
				error_string(err)]
	_mutex.lock()
	_what = name
	_mutex.unlock()
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	var have := _size_of(part) if FileAccess.file_exists(part) else 0
	if have > size:
		DirAccess.remove_absolute(part)
		have = 0
	if have > 0:
		# Докачування: хеш уже скачаного рахуємо з диска.
		var hashed := _hash_into(part, hashing, have)
		if hashed != "":
			return hashed
		resumed.append([name, have])
	if have < size:
		var why := _fetch_into(entry, part, have, hashing, got_bytes)
		if why != "":
			return why
	var sha := hashing.finish().hex_encode()
	if sha != want:
		DirAccess.remove_absolute(part)
		return ("хеш %s не зійшовся з маніфестом (є %s…, треба %s…): файл " \
				+ "пошкоджено в дорозі або публікацію саме міняють; " \
				+ "недокачане стерто — натисни «Оновити» ще раз") \
				% [name, sha.left(12), want.left(12)]
	if FileAccess.file_exists(final):
		err = DirAccess.remove_absolute(final)
		if err != OK:
			return "файл %s зайнятий (гра запущена?) або немає прав: %s" \
					% [final, error_string(err)]
	err = DirAccess.rename_absolute(part, final)
	if err != OK:
		return "не замінити %s (файл зайнятий або немає прав): %s" \
				% [final, error_string(err)]
	if bool(entry.get("exec", false)) and OS.get_name() != "Windows":
		err = FileAccess.set_unix_permissions(final, 493)  # 0755
		if err != OK:
			return "не поставити біт виконання на %s: %s" % [final,
					error_string(err)]
	fetched.append(name)
	return ""


func _fetch_into(entry: Dictionary, part: String, have: int,
		hashing: HashingContext, got_bytes: Array) -> String:
	var name := str(entry["path"])
	var headers := PackedStringArray()
	if have > 0:
		headers.append("Range: bytes=%d-" % have)
	var asked := _request("/files/%s/%s" % [platform, name], headers)
	if asked.has("why"):
		return asked["why"]
	var http: HTTPClient = asked["client"]
	var code: int = asked["code"]
	var served := _served_size(code, asked["headers"], have)
	if served >= 0 and served != int(entry["size"]):
		http.close()
		DirAccess.remove_absolute(part)
		return ("файл %s на сервері не збігається з маніфестом (%d байт, " \
				+ "а в маніфесті %d): публікацію, мабуть, саме міняють — " \
				+ "зачекай і натисни «Оновити»") % [name, served,
				int(entry["size"])]
	var file: FileAccess
	if code == 206 and have > 0:
		file = FileAccess.open(part, FileAccess.READ_WRITE)
		if file != null:
			file.seek_end()
	elif code == 200:
		# Сервер не дав докачати — починаємо файл спочатку.
		if have > 0:
			_add(-have)
			hashing.start(HashingContext.HASH_SHA256)
			if not resumed.is_empty() and resumed[-1][0] == name:
				resumed.pop_back()
		file = FileAccess.open(part, FileAccess.WRITE)
	else:
		http.close()
		if code == 416:
			DirAccess.remove_absolute(part)
		return "сервер не віддав %s: код %d" % [name, code]
	if file == null:
		http.close()
		return "не відкрити %s на запис (файл зайнятий, немає прав або " \
				% part + "місця): %s" % error_string(
				FileAccess.get_open_error())
	var last := Time.get_ticks_msec()
	while http.get_status() == HTTPClient.STATUS_BODY:
		if _stopped():
			file.close()
			http.close()
			return "оновлення зупинено — натисни «Оновити», щоб докачати"
		http.poll()
		var chunk := http.read_response_body_chunk()
		if chunk.is_empty():
			if Time.get_ticks_msec() - last > STALL_MS:
				file.close()
				http.close()
				return "сервер %s замовк посеред %s — натисни «Оновити», " \
						% [_where(), name] + "докачає з того місця"
			OS.delay_msec(1)
			continue
		last = Time.get_ticks_msec()
		if not file.store_buffer(chunk) or file.get_error() != OK:
			file.close()
			http.close()
			return "не записалось у %s — найімовірніше, скінчилось місце " \
					% part + "на диску (%s)" % error_string(file.get_error())
		hashing.update(chunk)
		_add(chunk.size())
		got_bytes[0] += chunk.size()
		if abort_after >= 0 and got_bytes[0] >= abort_after:
			file.close()
			http.close()
			return "обрив (проба): завантаження перервано на %s" \
					% _mb(got_bytes[0])
	file.close()
	var status := http.get_status()
	http.close()
	var now := _size_of(part)
	if now != int(entry["size"]):
		return ("з'єднання обірвалось на %s (%s з %s, стан %d) — натисни " \
				+ "«Оновити», докачає") % [name, _mb(now),
				_mb(int(entry["size"])), status]
	return ""


## Повний розмір файла за заголовками: 200 — Content-Length, 206 —
## «/всього» з Content-Range. −1 — сервер не сказав.
static func _served_size(code: int, headers: Dictionary, have: int) -> int:
	var lower := {}
	for key: Variant in headers:
		lower[str(key).to_lower()] = str(headers[key])
	if code == 206 and lower.has("content-range"):
		var total := str(lower["content-range"]).get_slice("/", 1)
		return int(total) if total.is_valid_int() else -1
	if code == 206 and lower.has("content-length"):
		return have + int(lower["content-length"])
	if code == 200 and lower.has("content-length"):
		return int(lower["content-length"])
	return -1


func _link(entry: Dictionary) -> String:
	var path := install.path_join(str(entry["path"]))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return "не відкрити теку %s" % path.get_base_dir()
	if dir.is_link(path) or FileAccess.file_exists(path):
		dir.remove(path)
	var err := dir.create_link(str(entry["link"]), path)
	if err != OK:
		return "не створити посилання %s: %s" % [path, error_string(err)]
	return ""


## Прибрати з теки клієнта все, чого немає в маніфесті (крім службових
## файлів). На Mac це не прикраса: зайвий файл у бандлі ламає підпис.
func _prune(manifest: Dictionary) -> void:
	var keep := {}
	for entry: Dictionary in manifest["files"]:
		keep[str(entry["path"])] = true
	for name in OWN_FILES:
		keep[name] = true
	_prune_dir(install, "", keep)


func _prune_dir(base: String, prefix: String, keep: Dictionary) -> void:
	var dir := DirAccess.open(base.path_join(prefix))
	if dir == null:
		return
	dir.include_hidden = true
	for name in dir.get_files():
		var relative := prefix.path_join(name) if prefix != "" else name
		if not keep.has(relative):
			dir.remove(name)
	for name in dir.get_directories():
		var relative := prefix.path_join(name) if prefix != "" else name
		if name == "_CodeSignature":
			continue
		if dir.is_link(base.path_join(relative)):
			if not keep.has(relative):
				dir.remove(name)
			continue
		_prune_dir(base, relative, keep)
		var inner := DirAccess.open(base.path_join(relative))
		if inner != null:
			inner.include_hidden = true
			if inner.get_files().is_empty() \
					and inner.get_directories().is_empty():
				dir.remove(name)


## Mac: зняти карантин і, якщо печатка бандла не сходиться, підписати
## його ad-hoc тут же (`codesign` є в кожній macOS, Xcode не треба).
## Порожній рядок — усе гаразд; інакше — попередження для екрана.
##
## Чому підпис доводиться ставити на місці. Godot на Linux підписує
## бандл сам, але для MyWay це не вдається (26.11.2026: «Unsigned nested
## executable file» — бібліотека GDExtension `libTree3D` у
## Contents/Frameworks без підпису x86_64), і в збірці немає
## `_CodeSignature` взагалі. Та й будь-яка заміна `.pck` у
## Contents/Resources печатку ламає: вона хешує кожен ресурс.
##
## Підпис змінює рушій і бібліотеки (у них вписується підпис) і додає
## `_CodeSignature/`. Щоб наступна звірка не вважала їх зіпсованими й не
## качала знову, у кеш хешів кладемо для них нові розмір і час, але хеш
## із маніфесту: «цей файл — підписаний на місці файл маніфесту».
## `_CodeSignature` прибирання не чіпає.
func _fix_macos(manifest: Dictionary) -> String:
	var app := install.path_join(str(manifest["app"]))
	var out: Array = []
	OS.execute("xattr", ["-dr", "com.apple.quarantine", app], out, true)
	out.clear()
	if OS.execute("codesign", ["--verify", "--deep", "--strict", app], out,
			true) == 0:
		return ""
	print("[апдейтер] печатка %s не сходиться (%s) — підписую ad-hoc"
			% [app, "\n".join(out).strip_edges()])
	var nested: Array[String] = []
	var frameworks := app.path_join("Contents/Frameworks")
	if DirAccess.dir_exists_absolute(frameworks):
		for name in DirAccess.get_files_at(frameworks):
			nested.append(frameworks.path_join(name))
		for name in DirAccess.get_directories_at(frameworks):
			nested.append(frameworks.path_join(name))
	nested.append(app)
	for path in nested:
		out.clear()
		var code := OS.execute("codesign", ["--force", "-s", "-", path], out,
				true)
		if code != 0:
			return ("не вдалось підписати %s (код %d): %s. Гра може не " \
					+ "запуститись; тоді в Терміналі: codesign --force " \
					+ "--deep -s - \"%s\"") % [path, code,
					"\n".join(out).strip_edges(), app]
	out.clear()
	if OS.execute("codesign", ["--verify", "--deep", "--strict", app], out,
			true) != 0:
		return "підпис %s і після перепідпису не сходиться: %s" % [app,
				"\n".join(out).strip_edges()]
	var cache := _read_json(install.path_join(HASH_CACHE))
	var prefix := str(manifest["app"]) + "/"
	for entry: Dictionary in manifest["files"]:
		var name := str(entry["path"])
		if entry.has("link") or not name.begins_with(prefix):
			continue
		var path := install.path_join(name)
		cache[name] = [_size_of(path), FileAccess.get_modified_time(path),
				str(entry["sha256"])]
	_write_json(install.path_join(HASH_CACHE), cache)
	return ""


# ── дрібне ──────────────────────────────────────────────────────────────

func _hash_file(path: String) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	if _hash_into(path, hashing, -1) != "":
		return ""
	return hashing.finish().hex_encode()


## Додати до `hashing` перші `limit` байтів файла (−1 — увесь).
func _hash_into(path: String, hashing: HashingContext, limit: int) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "не прочитати %s: %s" % [path, error_string(
				FileAccess.get_open_error())]
	var left := file.get_length() if limit < 0 else limit
	while left > 0:
		if _stopped():
			return "зупинено"
		var block := file.get_buffer(mini(CHUNK, left))
		if block.is_empty():
			break
		hashing.update(block)
		left -= block.size()
		_add(block.size())
	return ""


static func _size_of(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_length() if file != null else 0


static func _mb(bytes: int) -> String:
	if bytes >= 1 << 30:
		return "%.2f ГБ" % (bytes / float(1 << 30))
	return "%.1f МБ" % (bytes / float(1 << 20))


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(
			path))
	return parsed if parsed is Dictionary else {}


static func _write_json(path: String, data: Dictionary) -> void:
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		print("[апдейтер] ‼ не записати %s: %s" % [path, error_string(
				FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(data))
	file.close()
	if DirAccess.rename_absolute(temp, path) != OK:
		# Windows не перейменовує поверх наявного файла.
		DirAccess.remove_absolute(path)
		if DirAccess.rename_absolute(temp, path) != OK:
			print("[апдейтер] ‼ не замінити %s" % path)
