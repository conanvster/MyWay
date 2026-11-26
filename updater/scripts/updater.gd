extends Control
## Апдейтер-лаунчер MyWay (spec/апдейтер.md).
##
## Людина вводить IP сервера (за потреби з «:порт» сервісу оновлень,
## типово 24600) — і апдейтер одразу питає config.json, показує
## параметри сервера, звіряє локальний клієнт із маніфестом за SHA-256,
## завантажує лише змінене й запускає гру з `-- --host IP:ігровий-порт`.
##
## Клієнт живе в `user://client/<платформа>/` апдейтера:
##   Linux   ~/.local/share/MyWay-Updater/client/linux/
##   macOS   ~/Library/Application Support/MyWay-Updater/client/macos/
##   Windows %APPDATA%\MyWay-Updater\client\windows\
## Там завжди можна писати (на відміну від теки поруч із апдейтером: на
## Mac його .app часто лежить у /Applications або запускається з
## «транслокованої» копії лише для читання).
##
## Аргументи (після `--`), здебільшого для проб:
##   --тека <шлях>            інша тека клієнта
##   --клієнту-рушій "<арг>"  аргументи рушію клієнта, перед `--`
##                            (проба: "--headless", щоб не брати GPU)
##   --клієнту "<арг>"        додаткові аргументи гри після `--host`

const SYNC := preload("res://scripts/sync.gd")
const HTTP_PORT := 24600
const ADDRESS_FILE := "user://адреса.cfg"
const DEBOUNCE := 0.8
const RED := Color(1.0, 0.45, 0.4)
const YELLOW := Color(1.0, 0.85, 0.4)
const GREEN := Color(0.55, 0.95, 0.55)

var platform := ""
var install := ""
var config: Dictionary = {}
var manifest: Dictionary = {}
var need: Array = []
var need_bytes := 0
var installed := 0
## Адреса, з якої взято `config` — розібрана.
var host := ""
var http_port := HTTP_PORT
var client_pid := -1
## Остання ПОМИЛКА (червоним), окремо від стану: повторна звірка після
## збою не має її затирати.
var error_text := ""
## Для проби: обірвати завантаження після стількох байтів (−1 — ні).
var abort_after := -1

var _sync: RefCounted
var _thread: Thread
var _job := ""
var _check_again := false
var _wait := 0.0

var _address: LineEdit
var _check_button: Button
var _server: Label
var _warn: Label
var _status: Label
var _error: Label
var _bar: ProgressBar
var _bar_text: Label
var _update: Button
var _play: Button
var _where: Label


func _ready() -> void:
	platform = {"Linux": "linux", "macOS": "macos", "Windows": "windows"} \
			.get(OS.get_name(), "")
	var asked := _arg("--тека")
	install = asked if asked != "" else ProjectSettings.globalize_path(
			"user://client").path_join(platform)
	_build()
	if platform == "":
		_fail("ця система (%s) не підтримується: є клієнт лише для Linux, "
				% OS.get_name() + "macOS і Windows")
		return
	var saved := last_address()
	print("[апдейтер] v%d, збережена адреса: «%s»" % [own_version(), saved])
	if saved != "":
		_address.text = saved
		start_check()
	else:
		_status.text = "Введи IP сервера — той, що дав власник."
	_refresh()


func _arg(name: String) -> String:
	var args := OS.get_cmdline_user_args()
	var at := args.find(name)
	return args[at + 1] if at != -1 and at + 1 < args.size() else ""


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var title := Label.new()
	title.text = "MyWay — оновлення й запуск"
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)

	var row := HBoxContainer.new()
	box.add_child(row)
	var caption := Label.new()
	caption.text = "IP сервера:"
	row.add_child(caption)
	_address = LineEdit.new()
	_address.placeholder_text = "192.168.1.48  (або 192.168.1.48:24600)"
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address.text_changed.connect(func(_t: String) -> void:
			_wait = DEBOUNCE)
	_address.text_submitted.connect(func(_t: String) -> void:
			start_check())
	row.add_child(_address)
	_check_button = Button.new()
	_check_button.text = "Перевірити"
	_check_button.pressed.connect(start_check)
	row.add_child(_check_button)

	_server = _label(box)
	_warn = _label(box)
	_warn.add_theme_color_override("font_color", YELLOW)
	_status = _label(box)
	_error = _label(box)
	_error.add_theme_color_override("font_color", RED)

	_bar = ProgressBar.new()
	_bar.show_percentage = true
	box.add_child(_bar)
	_bar_text = _label(box)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	_update = Button.new()
	_update.text = "Оновити"
	_update.custom_minimum_size = Vector2(160, 40)
	_update.pressed.connect(_on_update)
	buttons.add_child(_update)
	_play = Button.new()
	_play.text = "Грати"
	_play.custom_minimum_size = Vector2(160, 40)
	_play.pressed.connect(play)
	buttons.add_child(_play)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	_where = _label(box)
	_where.add_theme_font_size_override("font_size", 12)
	_where.modulate = Color(1, 1, 1, 0.6)
	_where.text = "апдейтер v%s · клієнт у %s" % [own_version(), install]


func _label(box: Container) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(label)
	return label


static func own_version() -> int:
	return int(ProjectSettings.get_setting("application/config/version",
			"0"))


# ── завдання ───────────────────────────────────────────────────────────

func busy() -> bool:
	return _thread != null


## Запитати config.json і звірити клієнт. Кличе поле адреси (Enter, пауза
## після набору), кнопка «Перевірити» і старт зі збереженою адресою.
func start_check() -> void:
	_wait = 0.0
	if busy():
		if _job == "check":
			_sync.stop()
			_check_again = true
		return
	var parsed: Dictionary = SYNC.parse_address(_address.text, HTTP_PORT)
	if parsed.has("why"):
		config = {}
		manifest = {}
		_server.text = ""
		_fail(parsed["why"])
		return
	error_text = ""
	host = parsed["host"]
	http_port = parsed["port"]
	print("[апдейтер] питаю %s:%d (%s), клієнт у %s" % [host, http_port,
			platform, install])
	_run("check")


func _on_update() -> void:
	if busy():
		if _job == "update":
			_sync.stop()
		return
	error_text = ""
	_run("update")


func _run(kind: String) -> void:
	_sync = SYNC.new()
	_sync.host = host
	_sync.port = http_port
	_sync.install = install
	_sync.platform = platform
	_sync.abort_after = abort_after
	_job = kind
	_thread = Thread.new()
	if kind == "check":
		_thread.start(_sync.job_check.bind(platform))
	else:
		_thread.start(_sync.job_update.bind(manifest, need))
	_refresh()


func _process(delta: float) -> void:
	if _wait > 0.0:
		_wait -= delta
		if _wait <= 0.0:
			start_check()
	if not busy():
		if client_pid != -1 and not OS.is_process_running(client_pid):
			client_pid = -1
			_refresh()
		return
	var now: Dictionary = _sync.progress()
	if now["total"] > 0:
		_bar.value = 100.0 * now["done"] / now["total"]
		_bar_text.text = "%s — %s з %s" % [now["what"], SYNC._mb(now["done"]),
				SYNC._mb(now["total"])]
	else:
		_bar_text.text = now["what"]
	if _thread.is_alive():
		return
	var result: Dictionary = _thread.wait_to_finish()
	_thread = null
	var kind := _job
	_job = ""
	if kind == "check":
		_checked(result)
	else:
		_updated(result)
	if _check_again:
		_check_again = false
		start_check()


func _checked(result: Dictionary) -> void:
	config = result.get("config", {})
	manifest = result.get("manifest", {})
	need = result.get("need", [])
	need_bytes = int(result.get("need_bytes", 0))
	installed = int(result.get("installed", 0))
	_show_server()
	if not config.is_empty():
		remember_address(_address.text)
	if result.has("why"):
		if result["why"] != "звірку зупинено":
			_fail(result["why"])
		_refresh()
		return
	_bar.value = 100.0 if need.is_empty() else 0.0
	_bar_text.text = ""
	if need.is_empty():
		_status.text = "Клієнт актуальний: випуск %d (%s)." % [installed,
				manifest.get("version", "?")]
	else:
		_status.text = "Треба завантажити %d файл(ів), %s. " \
				% [need.size(), SYNC._mb(need_bytes)] + "Натисни «Оновити»."
	print("[апдейтер] %s:%d → %s; треба файлів %d (%s)" % [host, http_port,
			config.get("name", "?"), need.size(), SYNC._mb(need_bytes)])
	_refresh()


func _updated(result: Dictionary) -> void:
	print("[апдейтер] завантажено: %s; докачано: %s" % [_sync.fetched,
			_sync.resumed])
	if result.has("why"):
		_fail(result["why"])
		# Частину файлів уже замінено — список «треба» застарів.
		_run("check")
		return
	var checked: Dictionary = result["checked"]
	need = checked["need"]
	need_bytes = 0
	installed = int(checked["installed"])
	_bar.value = 100.0
	_bar_text.text = ""
	_status.text = "Оновлено: завантажено %d файл(ів). Клієнт — випуск %d." \
			% [_sync.fetched.size(), installed]
	if checked.has("note"):
		_fail(checked["note"])
	_refresh()


func _show_server() -> void:
	if config.is_empty():
		_server.text = ""
		_warn.text = ""
		return
	var client: Dictionary = config.get("client", {})
	_server.text = ("Сервер: «%s» · гра на %s:%d (UDP) · протокол %s\n" \
			+ "Клієнт на сервері: випуск %d (%s) · мінімальний випуск %d") \
			% [config.get("name", "?"), host, int(config.get("game_port", 0)),
			config.get("protocol", "?"), int(client.get("release", 0)),
			client.get("version", "?"), int(config.get("min_client_release",
			0))]
	var warn: Array[String] = []
	if int(config.get("updater_version", 0)) > own_version():
		warn.append("Є новіший апдейтер (v%d, у тебе v%d) — попроси його в " \
				% [int(config["updater_version"]), own_version()]
				+ "власника сервера. Цей працюватиме й далі.")
	if not manifest.is_empty() and int(manifest.get("release", 0)) \
			< int(config.get("min_client_release", 0)):
		warn.append("Для %s на сервері лише випуск %d, а потрібен %d — " \
				% [platform, int(manifest["release"]),
				int(config["min_client_release"])]
				+ "попроси власника опублікувати збірку.")
	_warn.text = "\n".join(warn)


func _fail(why: String) -> void:
	error_text = why
	print("[апдейтер] ‼ ", why)
	_refresh()


## Чому «Грати» не можна; порожньо — можна.
func play_blocker() -> String:
	if busy():
		return "зачекай: %s" % ("оновлюю" if _job == "update" else "перевіряю")
	if config.is_empty() or manifest.is_empty():
		return "немає зв'язку з сервером оновлень"
	if client_pid != -1:
		return "гру вже запущено"
	if not FileAccess.file_exists(install.path_join(str(manifest["launch"]))):
		return "клієнт ще не завантажено — натисни «Оновити»"
	var least := int(config.get("min_client_release", 0))
	if installed < least:
		return "клієнт застарий (випуск %d, сервер пускає з %d) — онови" \
				% [installed, least]
	return ""


func _refresh() -> void:
	_error.text = error_text
	_error.visible = error_text != ""
	_address.editable = _job != "update"
	_check_button.disabled = _job == "update"
	if _job == "update":
		_update.text = "Зупинити"
		_update.disabled = false
	else:
		_update.text = "Оновити"
		_update.disabled = busy() or manifest.is_empty() or need.is_empty() \
				or client_pid != -1
	_update.tooltip_text = "спершу закрий гру" if client_pid != -1 else ""
	var why := play_blocker()
	_play.disabled = why != ""
	_play.tooltip_text = why
	if why != "" and not busy() and not manifest.is_empty() \
			and error_text == "":
		_bar_text.text = "«Грати» недоступно: " + why
	if why == "" and not need.is_empty():
		_bar_text.text = "Є оновлення, але й цим випуском грати можна."


## Запустити клієнт: `<рушій> [аргументи рушію] -- --host IP:порт`.
func play() -> int:
	var why := play_blocker()
	if why != "":
		_fail("«Грати» недоступно: " + why)
		return -1
	var path := install.path_join(str(manifest["launch"]))
	var args := PackedStringArray()
	args.append_array(_arg("--клієнту-рушій").split(" ", false))
	args.append_array(["--", "--host", "%s:%d" % [host,
			int(config["game_port"])]])
	args.append_array(_arg("--клієнту").split(" ", false))
	client_pid = OS.create_process(path, args)
	if client_pid == -1:
		_fail("клієнт не запустився: %s (чи є біт виконання?)" % path)
		return -1
	print("[апдейтер] запущено %s %s (pid %d)" % [path, " ".join(args),
			client_pid])
	_status.text = "Гру запущено: %s:%d." % [host, int(config["game_port"])]
	_refresh()
	return client_pid


# ── збережена адреса ─────────────────────────────────────────────────────

static func last_address() -> String:
	if not FileAccess.file_exists(ADDRESS_FILE):
		return ""
	var file := ConfigFile.new()
	if file.load(ADDRESS_FILE) != OK:
		print("[апдейтер] ‼ не прочитав %s" % ADDRESS_FILE)
		return ""
	return str(file.get_value("сервер", "адреса", ""))


static func remember_address(text: String) -> void:
	var file := ConfigFile.new()
	file.set_value("сервер", "адреса", text.strip_edges())
	var err := file.save(ADDRESS_FILE)
	if err != OK:
		print("[апдейтер] ‼ не запам'ятав адресу в %s: %s" % [ADDRESS_FILE,
				error_string(err)])


func _exit_tree() -> void:
	if _thread != null:
		_sync.stop()
		_thread.wait_to_finish()
