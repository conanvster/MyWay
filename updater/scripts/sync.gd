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
## Стан установленого клієнта: випуск, версія і `files` — які файли
## поставив сам апдейтер (лише їх він колись прибере чи перенесе; чужого
## в теці не чіпає). Випуск ставиться лише після ПОВНОГО оновлення; на час
## завантаження він 0.
const STATE_FILE := ".myway-installed.json"
## Кеш хешів: {шлях: [розмір, час зміни, sha256]}, щоб не рахувати
## 1,6 ГБ на кожному старті.
const HASH_CACHE := ".myway-hashes.json"
## Мітка: у цій теці стоїть клієнт, поставлений апдейтером.
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
		if int(state.get("release", -1)) != installed \
				or not state.has("files"):
			_write_json(install.path_join(STATE_FILE), {"release": installed,
					"version": manifest.get("version", ""),
					"files": paths_of(manifest)})
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
	var free := space_left(install)
	# Запас 64 МБ: файл замінюється ПІСЛЯ перевірки, і обидва якийсь час
	# лежать поруч.
	if free >= 0 and free < left + (64 << 20):
		return {"why": "немає місця на диску: треба %s, вільно %s (тека %s)"
				% [_mb(left + (64 << 20)), _mb(free), install]}
	# Оновлення почалось — старий випуск уже не правда: перерване посеред
	# дороги не пустить грати старим, наполовину заміненим клієнтом. Список
	# файлів — і старі, і нові: усе це тепер наше.
	var state := _read_json(install.path_join(STATE_FILE))
	var before: Array = state.get("files", [])
	var ours := {}
	for name: Variant in before + paths_of(manifest):
		ours[str(name)] = true
	_write_json(install.path_join(STATE_FILE), {"release": 0,
			"files": ours.keys()})
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
	_prune(before, manifest)
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
			return "не створити теку %s: %s — обери іншу («Змінити…»)" \
					% [install, error_string(err)]
	var why := writable_problem(install)
	if why != "":
		return why
	if not FileAccess.file_exists(install.path_join(MARK_FILE)):
		var mark := FileAccess.open(install.path_join(MARK_FILE),
				FileAccess.WRITE)
		if mark != null:
			mark.store_line("Тут клієнт MyWay, яким керує апдейтер.")
	return ""


## Чому в теку не можна писати; порожньо — можна. Пробуємо по-справжньому:
## створити й стерти файл (права, тека лише для читання, диск без запису).
static func writable_problem(dir: String) -> String:
	if not DirAccess.dir_exists_absolute(dir):
		return "теки %s немає" % dir
	var probe := dir.path_join(".myway-write-test")
	var file := FileAccess.open(probe, FileAccess.WRITE)
	if file == null:
		return ("у теку %s не можна писати (%s): немає прав або диск лише " \
				+ "для читання — обери іншу теку («Змінити…»)") % [dir,
				error_string(FileAccess.get_open_error())]
	file.close()
	DirAccess.remove_absolute(probe)
	return ""


## Вільне місце там, де ляже тека (якщо її ще немає — на найближчій
## наявній теці вище). −1 — система не каже.
static func space_left(path: String) -> int:
	var at := path
	while at != "" and not DirAccess.dir_exists_absolute(at):
		var up := at.get_base_dir()
		if up == at:
			break
		at = up
	var dir := DirAccess.open(at) if at != "" else null
	return dir.get_space_left() if dir != null else -1


static func paths_of(manifest: Dictionary) -> Array:
	var out: Array = []
	for entry: Variant in manifest.get("files", []):
		if entry is Dictionary:
			out.append(str(entry.get("path", "")))
	return out


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


## Прибрати файли, які апдейтер ставив раніше, а в новому маніфесті їх
## немає (на Mac зайвий файл у бандлі ламає підпис). ЧУЖОГО не чіпаємо:
## лише те, що записано в стані як наше. Теки, що спорожніли, — теж геть.
func _prune(before: Array, manifest: Dictionary) -> void:
	var keep := {}
	for name: Variant in paths_of(manifest):
		keep[str(name)] = true
	for name: Variant in before:
		var relative := str(name)
		if keep.has(relative) or not safe_relative(relative):
			continue
		var path := install.path_join(relative)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
			_drop_empty(install, path.get_base_dir())


## Стерти порожні теки від `dir` угору, але не вище `top`.
static func _drop_empty(top: String, dir: String) -> void:
	var at := dir
	while at.length() > top.length() and at.begins_with(top):
		var opened := DirAccess.open(at)
		if opened == null:
			return
		opened.include_hidden = true
		if not (opened.get_files().is_empty()
				and opened.get_directories().is_empty()):
			return
		DirAccess.remove_absolute(at)
		at = at.get_base_dir()


# ── перенесення в іншу теку ─────────────────────────────────────────────

## Перенести встановлений клієнт із `from` у `install`. Переносимо лише
## НАШЕ: файли зі стану (або, у старому встановленні без списку, — усе в
## теці з міткою, бо тоді апдейтер ставив лише в порожню свою теку).
## Спершу `rename` (той самий диск — миттєво); не вийшло — копія з
## перевіркою SHA-256 і лише потім стирання джерела.
func job_move(from: String) -> Dictionary:
	var state := _read_json(from.path_join(STATE_FILE))
	var names: Array = []
	if state.has("files"):
		for name: Variant in state["files"]:
			if safe_relative(str(name)):
				names.append(str(name))
	elif FileAccess.file_exists(from.path_join(MARK_FILE)):
		_list_all(from, "", names)
	else:
		return {"why": "у %s немає клієнта, поставленого апдейтером" % from}
	for own in OWN_FILES:
		if not names.has(own):
			names.append(own)
	# Mac: печатка, поставлена тут же (`_fix_macos`), у маніфесті не
	# значиться, але без неї перенесений бандл лишився б непідписаним.
	var apps := {}
	for name: String in names:
		if ".app/" in name:
			apps[name.left(name.find(".app/") + 4)] = true
	for app: String in apps:
		var seal := app.path_join("Contents/_CodeSignature")
		for name in DirAccess.get_files_at(from.path_join(seal)):
			if not names.has(seal.path_join(name)):
				names.append(seal.path_join(name))
	var moving: Array = []
	var total := 0
	for name: String in names:
		for one in [name, name + ".part"]:
			var path := from.path_join(one)
			if FileAccess.file_exists(path):
				moving.append(one)
				total += _size_of(path)
	if not DirAccess.dir_exists_absolute(install):
		var err := DirAccess.make_dir_recursive_absolute(install)
		if err != OK:
			return {"why": "не створити теку %s: %s" % [install,
					error_string(err)]}
	var why := writable_problem(install)
	if why != "":
		return {"why": why}
	_put(0, total, "переношу")
	# Той самий диск — `rename`, миттєво. Інший — своя копія з перевіркою:
	# `DirAccess.rename_absolute` між дисками сам тихо копіює, без звірки
	# хешу і губить біт виконання (заміряно 26.11.2026).
	var same := same_disk(from, install)
	var cache := _read_json(from.path_join(HASH_CACHE))
	var copied := 0
	for name: String in moving:
		if _stopped():
			return {"why": "перенесення зупинено — частина файлів уже в %s" \
					% install}
		var source := from.path_join(name)
		var target := install.path_join(name)
		_mutex.lock()
		_what = name
		_mutex.unlock()
		var size := _size_of(source)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(target)
		if same and DirAccess.rename_absolute(source, target) == OK:
			_add(size)
		else:
			var failed := _copy_checked(source, target)
			if failed != "":
				return {"why": failed}
			copied += 1
			# Час зміни в копії новий; вміст той самий (звірено) — кеш
			# переносимо, інакше на Mac підписаний на місці рушій
			# здавався б зіпсованим і качався знову.
			var known: Variant = cache.get(name)
			if known is Array and known.size() == 3:
				cache[name] = [size, FileAccess.get_modified_time(target),
						known[2]]
		_drop_empty(from, source.get_base_dir())
	if copied > 0:
		_write_json(install.path_join(HASH_CACHE), cache)
	_drop_empty(from.get_base_dir(), from)
	return {"ok": true, "moved": moving.size(), "copied": copied}


## Чи дві теки на одному диску (тоді перенесення — перейменуванням).
## Сумнів — «ні»: копія з перевіркою повільніша, але не зіпсує.
static func same_disk(a: String, b: String) -> bool:
	if OS.get_name() == "Windows":
		return a.left(2).to_upper() == b.left(2).to_upper()
	var flag := "-f" if OS.get_name() == "macOS" else "-c"
	var ids: Array[String] = []
	for path in [a, b]:
		var out: Array = []
		if OS.execute("stat", [flag, "%d", path], out) != 0 or out.is_empty():
			return false
		ids.append(str(out[0]).strip_edges())
	return ids[0] == ids[1] and ids[0] != ""


func _list_all(base: String, prefix: String, out: Array) -> void:
	var dir := DirAccess.open(base.path_join(prefix))
	if dir == null:
		return
	dir.include_hidden = true
	for name in dir.get_files():
		out.append(prefix.path_join(name) if prefix != "" else name)
	for name in dir.get_directories():
		_list_all(base, prefix.path_join(name) if prefix != "" else name, out)


## Копія з перевіркою: SHA-256 джерела, записане, і SHA-256 копії з диска.
func _copy_checked(source: String, target: String) -> String:
	var input := FileAccess.open(source, FileAccess.READ)
	if input == null:
		return "не прочитати %s: %s" % [source, error_string(
				FileAccess.get_open_error())]
	var output := FileAccess.open(target + ".part", FileAccess.WRITE)
	if output == null:
		return "не записати %s: %s (немає прав або місця)" % [target,
				error_string(FileAccess.get_open_error())]
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	while true:
		var block := input.get_buffer(CHUNK)
		if block.is_empty():
			break
		if not output.store_buffer(block):
			output.close()
			DirAccess.remove_absolute(target + ".part")
			return "не записалось у %s — найімовірніше, скінчилось місце" \
					% target
		hashing.update(block)
		_add(block.size())
	output.close()
	var want := hashing.finish().hex_encode()
	if FileAccess.get_sha256(target + ".part") != want:
		DirAccess.remove_absolute(target + ".part")
		return "копія %s не збіглась із джерелом за SHA-256 — джерело " \
				% target + "лишив на місці"
	if DirAccess.rename_absolute(target + ".part", target) != OK:
		return "не перейменувати копію %s" % target
	var mode := FileAccess.get_unix_permissions(source)
	if mode != 0 and OS.get_name() != "Windows":
		FileAccess.set_unix_permissions(target, mode)
	DirAccess.remove_absolute(source)
	return ""


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
