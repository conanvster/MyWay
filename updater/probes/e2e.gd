extends Node
## Наскрізна проба апдейтера (26.11.2026): шлях гравця від порожньої теки
## до запущеної гри, руками проби. Окремі сервери піднімає
## `updater/probe.sh` (він і пояснює, як ганяти).
##
##   0. розбір адреси й безпечні шляхи маніфесту;
##   1. адреса, де ніхто не слухає, — помилка текстом, «Грати» заблоковано;
##   2. 127.0.0.1 — config підтягнувся, треба завантажити все;
##   3. обрив посеред .pck → «Оновити» вдруге докачує з того місця (Range),
##      хеші збігаються;
##   4. у публікації замінили один файл → завантажується лише він;
##  4б. файл у публікації не збігається з маніфестом → «хеш не зійшовся»;
##      тека без права запису → сказано про права; потім усе гаразд;
##   5. LAN-IP — той самий сервер, качати нічого;
##   6. мінімальний випуск вищий за наш — «Грати» заблоковано;
##   7. «Грати» → клієнт із `--host IP:ігровий-порт` заходить на сервер.
##
## Аргументи (після `--`): --тека, --адреса, --lan, --мертвий,
## --порт-гри, --обрив-мб, --зміна <скрипт>, --псування <скрипт>,
## --журнал-сервера <файл>,
## і для самого апдейтера --клієнту-рушій / --клієнту.

const UPDATER := preload("res://scenes/updater.tscn")
const PAGE := preload("res://scripts/updater.gd")
const SYNC := preload("res://scripts/sync.gd")
## Збереження зібраного клієнта: проба його вертає як було.
const CLIENT_ADDRESS := "~/.local/share/godot/app_userdata/MyWay/" \
		+ "адреса-сервера.cfg"

var _failed := 0
var _kept := ""
var _client_kept := ""
var _client_had := false
var _page: Node


func _ready() -> void:
	_go.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("  %s %s" % ["✓" if ok else "✗", what])
	if not ok:
		_failed += 1


func _arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	var at := args.find(name)
	return args[at + 1] if at != -1 and at + 1 < args.size() else fallback


func _until(test: Callable, seconds: float) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < seconds * 1000.0:
		if test.call():
			return true
		await get_tree().process_frame
	return false


## Ввести адресу так, як людина: текст і Enter.
func _type(address: String) -> void:
	_page._address.text = address
	_page._address.text_submitted.emit(address)
	await get_tree().process_frame
	await _until(func() -> bool: return not _page.busy(), 600.0)


func _press_update() -> void:
	_page._update.pressed.emit()
	await get_tree().process_frame
	await _until(func() -> bool: return not _page.busy(), 1800.0)


func _go() -> void:
	var address := _arg("--адреса", "127.0.0.1:24600")
	var lan := _arg("--lan", "")
	var dead := _arg("--мертвий", "127.0.0.1:24609")
	var game_port := int(_arg("--порт-гри", "24601"))
	var cut := int(_arg("--обрив-мб", "300")) << 20
	var change := _arg("--зміна", "")
	var server_log := _arg("--журнал-сервера", "")
	_kept = PAGE.last_address()
	var client_file := CLIENT_ADDRESS.replace("~", OS.get_environment("HOME"))
	_client_had = FileAccess.file_exists(client_file)
	if _client_had:
		_client_kept = FileAccess.get_file_as_string(client_file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(
			"user://адреса.cfg"))

	print("\n— 0. розбір адреси й шляхів —")
	var plain: Dictionary = SYNC.parse_address(" 10.0.0.5 ", 24600)
	_check(plain.get("host") == "10.0.0.5" and plain.get("port") == 24600,
			"без порту — HTTP 24600")
	_check(SYNC.parse_address("10.0.0.5:24610", 24600).get("port") == 24610,
			"з портом — 24610")
	for bad in ["", "1.2.3.4:0", "::1", "http://1.2.3.4", "a b"]:
		_check(SYNC.parse_address(bad, 24600).has("why"),
				"«%s» — пояснення: %s" % [bad, SYNC.parse_address(bad,
				24600).get("why", "—")])
	for bad in ["../x", "/etc/passwd", "a/../../b", "a\\b", "C:/x", "a//b",
			""]:
		_check(not SYNC.safe_relative(bad), "шлях «%s» відкинуто" % bad)
	_check(SYNC.safe_relative("MyWay.app/Contents/MacOS/MyWay"),
			"шлях у бандлі прийнято")

	_page = UPDATER.instantiate()
	get_tree().root.add_child(_page)
	await get_tree().process_frame
	var install: String = _page.install
	print("  тека клієнта: %s" % install)

	print("\n— 1. ніхто не слухає (%s) —" % dead)
	await _type(dead)
	_check(_page.error_text.contains("сервер оновлень"),
			"помилка текстом: «%s»" % _page.error_text)
	_check(_page._play.disabled, "«Грати» заблоковано: %s"
			% _page._play.tooltip_text)

	print("\n— 2. %s —" % address)
	await _type(address)
	var config: Dictionary = _page.config
	_check(str(config.get("name", "")) != "", "config: «%s», гра UDP %d, " \
			% [config.get("name", ""), int(config.get("game_port", 0))]
			+ "випуск %d, мінімальний %d" % [int(config.get("client", {})
			.get("release", 0)), int(config.get("min_client_release", 0))])
	_check(int(config.get("game_port", 0)) == game_port,
			"ігровий порт з config — %d" % game_port)
	_check(_page._server.text.contains(str(config.get("name", "?"))),
			"параметри сервера на екрані: %s" % _page._server.text
			.replace("\n", " / "))
	var files: Array = _page.manifest.get("files", [])
	_check(_page.need.size() == files.size() and files.size() > 0,
			"порожня тека — треба всі %d файли, %s" % [files.size(),
			SYNC._mb(_page.need_bytes)])
	_check(_page._play.disabled and _page.play_blocker().contains(
			"не завантажено"), "«Грати» заблоковано: %s"
			% _page.play_blocker())
	_check(PAGE.last_address() == address,
			"адресу запам'ятовано")

	print("\n— 3. обрив на %s і докачування —" % SYNC._mb(cut))
	_page.abort_after = cut
	await _press_update()
	_check(_page.error_text.contains("обрив"), "обрив показано: «%s»"
			% _page.error_text)
	var biggest := ""
	var biggest_size := 0
	for entry: Dictionary in files:
		if int(entry.get("size", 0)) > biggest_size:
			biggest_size = int(entry["size"])
			biggest = str(entry["path"])
	var part := install.path_join(biggest) + ".part"
	var part_size: int = SYNC._size_of(part) if FileAccess.file_exists(part) \
			else 0
	_check(part_size >= cut and part_size < biggest_size,
			"недокачаний %s.part: %s з %s" % [biggest, SYNC._mb(part_size),
			SYNC._mb(biggest_size)])
	_check(_page._play.disabled, "посеред оновлення «Грати» заблоковано: %s"
			% _page.play_blocker())
	_page.abort_after = -1
	await _press_update()
	var resumed: Array = _page._sync.resumed
	_check(_page.error_text == "" and _page.need.is_empty(),
			"оновлено без помилок: %s" % _page._status.text)
	_check(resumed.size() == 1 and resumed[0][0] == biggest
			and int(resumed[0][1]) == part_size,
			"докачано %s з байта %d" % [biggest, part_size]
			if not resumed.is_empty() else "докачування не було: %s" % [
			resumed])
	_check(_same_as_manifest(install, files), "SHA-256 усіх %d файлів " \
			% files.size() + "збігаються з маніфестом (перераховано пробою)")
	_check(_page.installed == int(_page.manifest.get("release", -1)),
			"установлено випуск %d" % _page.installed)

	if change != "":
		print("\n— 4. у публікації змінено один файл —")
		var out: Array = []
		var code := OS.execute("bash", [change], out, true)
		var changed := str(out[0]).strip_edges().split("\n")[-1] \
				if not out.is_empty() else ""
		_check(code == 0 and changed != "", "скрипт зміни: %s" % changed)
		await _type(address)
		_check(_page.need.size() == 1 and str(_page.need[0]["path"])
				== changed, "треба лише %s: %s" % [changed,
				_page.need.map(func(e: Dictionary) -> String:
				return str(e["path"]))])
		await _press_update()
		var got: Array = _page._sync.fetched
		_check(got.size() == 1 and got[0] == changed,
				"завантажено лише %s" % [_page._sync.fetched])
		_check(_same_as_manifest(install, _page.manifest["files"]),
				"хеші знову збігаються")

	var spoil := _arg("--псування", "")
	if spoil != "" and change != "":
		print("\n— 4б. хеш не зійшовся; немає права писати —")
		var local := install.path_join("versiia.json")
		var file := FileAccess.open(local, FileAccess.WRITE)
		file.store_string("зіпсовано локально")
		file.close()
		OS.execute("bash", [spoil])
		await _type(address)
		_check(_page.need.size() == 1, "локально зіпсований файл помічено")
		await _press_update()
		_check(_page.error_text.contains("хеш") and not FileAccess.file_exists(
				local + ".part"), "хеш не зійшовся — сказано, недокачане " \
				+ "стерто: «%s»" % _page.error_text)
		_check(_page._play.disabled, "«Грати» заблоковано: %s"
				% _page.play_blocker())
		OS.execute("bash", [change])
		await _type(address)
		OS.execute("chmod", ["555", install])
		await _press_update()
		OS.execute("chmod", ["755", install])
		_check(_page.error_text.contains("прав"), "тека без права запису — " \
				+ "сказано: «%s»" % _page.error_text)
		await _press_update()
		_check(_page.error_text == "" and _page.need.is_empty(),
				"після збоїв оновлення пройшло: %s" % _page._status.text)

	if lan != "":
		print("\n— 5. LAN-IP %s —" % lan)
		await _type(lan)
		_check(_page.error_text == "" and not _page.config.is_empty(),
				"config через LAN: «%s»" % _page.config.get("name", "—"))
		_check(_page.need.is_empty(), "качати нічого: %s" % _page._status.text)

	print("\n— 6. мінімальний випуск вищий за наш —")
	var least: int = _page.config["min_client_release"]
	_page.config["min_client_release"] = _page.installed + 1
	_page._refresh()
	_check(_page._play.disabled and _page.play_blocker().contains("застарий"),
			"«Грати» заблоковано: %s" % _page.play_blocker())
	_page.config["min_client_release"] = least
	_page._refresh()
	_check(not _page._play.disabled, "з чинним мінімумом — можна")

	print("\n— 7. «Грати» —")
	var before := _count_in(server_log, "[акаунт]")
	_page._play.pressed.emit()
	var pid: int = _page.client_pid
	_check(pid > 0, "клієнт запущено, pid %d" % pid)
	var expected_host := "%s:%d" % [_page.host, game_port]
	_check(OS.is_process_running(pid), "живий, --host %s" % expected_host)
	if server_log != "":
		var joined := await _until(func() -> bool:
				return _count_in(server_log, "[акаунт]") > before, 120.0)
		_check(joined, "сервер бачить вхід клієнта: %s" % _last_in(
				server_log, "[акаунт]"))
		var spawned := await _until(func() -> bool:
				return _last_in(server_log, "[світ] приєднався") != "", 60.0)
		_check(spawned, "персонаж у світі: %s" % _last_in(server_log,
				"[світ] приєднався"))
	if pid > 0:
		OS.kill(pid)
	_finish(client_file)


func _same_as_manifest(install: String, files: Array) -> bool:
	for entry: Dictionary in files:
		if entry.has("link"):
			continue
		var path := install.path_join(str(entry["path"]))
		if FileAccess.get_sha256(path) != str(entry["sha256"]):
			print("    ≠ %s" % path)
			return false
	return true


func _count_in(path: String, mark: String) -> int:
	if path == "" or not FileAccess.file_exists(path):
		return 0
	return FileAccess.get_file_as_string(path).count(mark)


func _last_in(path: String, mark: String) -> String:
	if path == "" or not FileAccess.file_exists(path):
		return ""
	var found := ""
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.contains(mark):
			found = line.strip_edges()
	return found


func _finish(client_file: String) -> void:
	if _kept != "":
		PAGE.remember_address(_kept)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(
				"user://адреса.cfg"))
	if _client_had:
		var file := FileAccess.open(client_file, FileAccess.WRITE)
		file.store_string(_client_kept)
	else:
		DirAccess.remove_absolute(client_file)
	print("\nпроба апдейтера: %s, провалено %d" % ["ПРОЙДЕНО"
			if _failed == 0 else "НЕ ПРОЙДЕНО", _failed])
	get_tree().quit(1 if _failed > 0 else 0)
