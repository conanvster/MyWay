extends Control
## Апдейтер-лаунчер MyWay (spec/апдейтер.md).
##
## Людина вводить IP сервера (за потреби з «:порт» сервісу оновлень,
## типово 24600) — і апдейтер одразу питає config.json, показує
## параметри сервера, звіряє клієнт у теці встановлення з маніфестом за
## SHA-256, завантажує лише змінене й запускає гру з
## `-- --host IP:ігровий-порт`.
##
## Тека встановлення — видима й на вибір людини («Змінити…»). Типово:
##   Linux   ~/Games/MyWay
##   macOS   ~/Applications/MyWay   (там і MyWay.app; адмін не потрібен)
##   Windows %LOCALAPPDATA%\Programs\MyWay   (звичне місце програм
##           «для себе», без прав адміністратора)
## Вибір пам'ятається в `user://налаштування.cfg`.
##
## Аргументи (після `--`), здебільшого для проб:
##   --тека <шлях>            тека клієнта на цей запуск (не запам'ятовується)
##   --стара-тека <шлях>      де шукати клієнт старого апдейтера
##                            (типово user://client/<платформа>)
##   --клієнту-рушій "<арг>"  аргументи рушію клієнта, перед `--`
##                            (проба: "--headless", щоб не брати GPU)
##   --клієнту "<арг>"        додаткові аргументи гри після `--host`

const SYNC := preload("res://scripts/sync.gd")
const HTTP_PORT := 24600
const SETTINGS_FILE := "user://налаштування.cfg"
## Тут адресу тримала перша версія — читаємо, якщо нової ще немає.
const OLD_ADDRESS_FILE := "user://адреса.cfg"
const DEBOUNCE := 0.8
const RED := Color(1.0, 0.45, 0.4)
const YELLOW := Color(1.0, 0.85, 0.4)

var platform := ""
## Тека встановлення (абсолютний шлях).
var install := ""
## Клієнт, поставлений першою версією апдейтера (у user://).
var legacy_dir := ""
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
## Питання, що чекає відповіді: "" | "move" (змінили теку, а гра вже
## стоїть у старій) | "legacy" (знайдено клієнт першої версії).
var pending_kind := ""
var pending_from := ""
var pending_to := ""

var _sync: RefCounted
var _thread: Thread
var _job := ""
var _check_again := false
var _wait := 0.0
## Куди переносимо (поки йде `move`).
var _move_to := ""

var _address: LineEdit
var _check_button: Button
var _server: Label
var _warn: Label
var _self_button: Button
var _dir: LineEdit
var _dir_button: Button
var _dir_info: Label
var _status: Label
var _error: Label
var _bar: ProgressBar
var _bar_text: Label
var _installed_label: Label
var _open_button: Button
var _update: Button
var _play: Button
var _where: Label
var _picker: FileDialog
var _ask: ConfirmationDialog


func _ready() -> void:
	platform = {"Linux": "linux", "macOS": "macos", "Windows": "windows"} \
			.get(OS.get_name(), "")
	var once := _arg("--тека")
	var saved := setting("клієнт", "тека")
	install = once if once != "" else (saved if saved != "" else default_dir())
	var old := _arg("--стара-тека")
	legacy_dir = old if old != "" else ProjectSettings.globalize_path(
			"user://client").path_join(platform)
	_fit_window()
	clean_self_update()
	_build()
	if platform == "":
		_fail("ця система (%s) не підтримується: є клієнт лише для Linux, "
				% OS.get_name() + "macOS і Windows")
		return
	var address := last_address()
	# Для скриптів і проби: `-- --адреса ip[:порт]` (не зберігається, доки
	# сервер не відповів) і `--оновити-себе` — самооновитись без кліку.
	if _arg("--адреса") != "":
		address = _arg("--адреса")
	print("[апдейтер] v%d, збережена адреса: «%s», тека: %s" % [own_version(),
			address, install])
	if once == "" and saved == "":
		offer_legacy()
	if address != "":
		_address.text = address
		start_check()
	else:
		_status.text = "Введи IP сервера — той, що дав власник."
	_refresh()


func _arg(name: String) -> String:
	var args := OS.get_cmdline_user_args()
	var at := args.find(name)
	return args[at + 1] if at != -1 and at + 1 < args.size() else ""


## Типова тека встановлення: видима, у домашній теці, без прав адміна.
static func default_dir() -> String:
	var home := OS.get_environment("HOME")
	match OS.get_name():
		"Linux":
			if home != "":
				return home.path_join("Games/MyWay")
		"macOS":
			if home != "":
				return home.path_join("Applications/MyWay")
		"Windows":
			var local := OS.get_environment("LOCALAPPDATA").replace("\\", "/")
			if local != "":
				return local.path_join("Programs/MyWay")
	return ProjectSettings.globalize_path("user://client")


## Вікно під щільність екрана. Слово замовника 27.11.2026 (знімок з Mac):
## «в порівнянні з іншим інтерфейсом маленький — збільши і шрифт і розмір».
## На Retina рушій малює в справжніх пікселях, тож без множника все вдвічі
## дрібніше. Розтяжка `canvas_items` (project.godot) масштабує весь
## інтерфейс від BASE_SIZE: тут лише ставимо розмір вікна = BASE_SIZE ×
## множник екрана (macOS/Wayland — screen_get_scale, Windows — DPI/96).
## Більше вікно мишею — більший інтерфейс.
const BASE_SIZE := Vector2i(900, 640)
const BASE_FONT := 19


func _fit_window() -> void:
	var look := Theme.new()
	look.default_font_size = BASE_FONT
	theme = look
	if DisplayServer.get_name() == "headless":
		return
	var screen := DisplayServer.window_get_current_screen()
	var factor := DisplayServer.screen_get_scale(screen)
	if OS.get_name() == "Windows":
		factor = DisplayServer.screen_get_dpi(screen) / 96.0
	factor = clampf(snappedf(factor, 0.25), 1.0, 3.0)
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var want := Vector2(BASE_SIZE) * factor
	# Не більше 90 % екрана — на маленькому ноутбуці вікно не вилізе за край.
	var fit := minf(1.0, minf(usable.size.x * 0.9 / want.x, usable.size.y * 0.9 / want.y))
	var win_size := Vector2i(want * fit)
	var win := get_window()
	win.min_size = Vector2i(Vector2(win_size) * 0.7)
	win.size = win_size
	win.position = usable.position + (usable.size - win_size) / 2
	print("[апдейтер] екран ×%.2f → вікно %s" % [factor, win_size])


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var title := Label.new()
	title.text = "MyWay — оновлення й запуск"
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)

	var row := HBoxContainer.new()
	box.add_child(row)
	row.add_child(_caption("IP сервера:"))
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
	_self_button = Button.new()
	_self_button.text = "Оновити апдейтер"
	_self_button.custom_minimum_size = Vector2(240, 44)
	_self_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_self_button.pressed.connect(_self_update)
	_self_button.visible = false
	box.add_child(_self_button)

	var dir_row := HBoxContainer.new()
	box.add_child(dir_row)
	dir_row.add_child(_caption("Куди встановити гру:"))
	_dir = LineEdit.new()
	_dir.editable = false
	_dir.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dir_row.add_child(_dir)
	_dir_button = Button.new()
	_dir_button.text = "Змінити…"
	_dir_button.pressed.connect(_pick_dir)
	dir_row.add_child(_dir_button)
	_dir_info = _label(box)
	_dir_info.add_theme_font_size_override("font_size", 16)
	_dir_info.modulate = Color(1, 1, 1, 0.75)

	_status = _label(box)
	_error = _label(box)
	_error.add_theme_color_override("font_color", RED)

	_bar = ProgressBar.new()
	_bar.show_percentage = true
	box.add_child(_bar)
	_bar_text = _label(box)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	var here := HBoxContainer.new()
	box.add_child(here)
	_installed_label = Label.new()
	_installed_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_installed_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	here.add_child(_installed_label)
	_open_button = Button.new()
	_open_button.text = "Відкрити теку"
	_open_button.pressed.connect(open_folder)
	here.add_child(_open_button)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	_update = Button.new()
	_update.text = "Оновити"
	_update.custom_minimum_size = Vector2(200, 52)
	_update.pressed.connect(_on_update)
	buttons.add_child(_update)
	_play = Button.new()
	_play.text = "Грати"
	_play.custom_minimum_size = Vector2(200, 52)
	_play.pressed.connect(play)
	buttons.add_child(_play)

	_where = _label(box)
	_where.add_theme_font_size_override("font_size", 15)
	_where.modulate = Color(1, 1, 1, 0.5)
	_where.text = "апдейтер v%d" % own_version()

	_picker = FileDialog.new()
	_picker.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_picker.access = FileDialog.ACCESS_FILESYSTEM
	# На Mac і Windows — системний діалог; на Linux — теж, якщо є портал.
	_picker.use_native_dialog = true
	_picker.title = "Куди встановити MyWay"
	_picker.dir_selected.connect(choose_dir)
	add_child(_picker)

	_ask = ConfirmationDialog.new()
	_ask.title = "Тека гри"
	_ask.dialog_autowrap = true
	_ask.min_size = Vector2i(520, 160)
	_ask.confirmed.connect(answer.bind("move"))
	_ask.canceled.connect(answer.bind("cancel"))
	_ask.add_button("Завантажити наново", true, "fresh")
	_ask.custom_action.connect(func(action: StringName) -> void:
			_ask.hide()
			answer(str(action)))
	add_child(_ask)


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _label(box: Container) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(label)
	return label


static func own_version() -> int:
	return int(ProjectSettings.get_setting("application/config/version",
			"0"))


# ── тека встановлення ────────────────────────────────────────────────────

## Чи стоїть у теці клієнт, поставлений апдейтером.
static func installed_in(dir: String) -> bool:
	return dir != "" and (FileAccess.file_exists(dir.path_join(
			SYNC.STATE_FILE)) or FileAccess.file_exists(dir.path_join(
			SYNC.MARK_FILE)))


func _pick_dir() -> void:
	var start := install
	while start != "" and not DirAccess.dir_exists_absolute(start):
		start = start.get_base_dir()
	_picker.current_dir = start
	_picker.popup_centered_ratio(0.7)


## Людина обрала теку (діалог або проба). Якщо гра вже стоїть у старій —
## питаємо: перенести чи завантажити наново.
func choose_dir(path: String) -> void:
	var target := path.replace("\\", "/").strip_edges().trim_suffix("/")
	if target == "" or not target.is_absolute_path():
		_fail("тека має бути повним шляхом: «%s»" % path)
		return
	if target == install:
		return
	if busy():
		_fail("зачекай, доки скінчиться %s" % ("оновлення"
				if _job == "update" else "поточна дія"))
		return
	if DirAccess.dir_exists_absolute(target):
		var why: String = SYNC.writable_problem(target)
		if why != "":
			_fail(why)
			return
	if installed_in(install):
		if target.begins_with(install + "/") or install.begins_with(
				target + "/"):
			_fail("нова тека не може лежати всередині старої чи навпаки: " \
					+ "%s і %s" % [target, install])
			return
		_question("move", install, target, ("Гра вже встановлена в\n%s\n\n" \
				+ "Перенести її в\n%s?\n\n«Завантажити наново» — стара " \
				+ "тека лишиться як є, у нову все завантажиться з сервера.")
				% [install, target])
		return
	_switch_to(target)


## Клієнт першої версії апдейтера лежить у user:// — запропонувати
## перенести, щоб не качати 1,65 ГБ ще раз.
func offer_legacy() -> void:
	if legacy_dir == "" or legacy_dir == install \
			or not installed_in(legacy_dir):
		return
	_question("legacy", legacy_dir, install, ("Знайдено вже " \
			+ "встановлену " \
			+ "гру в старому місці:\n%s\n\nПеренести її в\n%s?\n\n" \
			+ "Тоді нічого не доведеться " \
			+ "качати знову.") % [legacy_dir, install])


func _question(kind: String, from: String, to: String, text: String) -> void:
	pending_kind = kind
	pending_from = from
	pending_to = to
	_ask.dialog_text = text
	_ask.ok_button_text = "Перенести"
	_ask.cancel_button_text = "Скасувати"
	print("[апдейтер] питаю: %s → %s (%s)" % [from, to, kind])
	if is_inside_tree() and DisplayServer.get_name() != "headless":
		_ask.popup_centered()
	_refresh()


## Відповідь на питання: "move", "fresh" або "cancel".
func answer(choice: String) -> void:
	if pending_kind == "":
		return
	var kind := pending_kind
	var from := pending_from
	var to := pending_to
	pending_kind = ""
	if choice == "move":
		_start_move(from, to)
	elif choice == "fresh":
		_switch_to(to)
	elif kind == "legacy":
		# «Скасувати» на старому клієнті — більше не питати.
		remember_setting("клієнт", "тека", install)
	_refresh()


func _switch_to(target: String) -> void:
	install = target
	remember_setting("клієнт", "тека", install)
	print("[апдейтер] тека встановлення: %s" % install)
	need = []
	installed = 0
	if not config.is_empty():
		start_check()
	_refresh()


func _start_move(from: String, to: String) -> void:
	if busy():
		_fail("зачекай, доки скінчиться поточна дія")
		return
	error_text = ""
	_move_to = to
	_sync = SYNC.new()
	_sync.install = to
	_sync.platform = platform
	_job = "move"
	_thread = Thread.new()
	_thread.start(_sync.job_move.bind(from))
	_refresh()


func _moved(result: Dictionary) -> void:
	if result.has("why"):
		_fail("перенести не вдалось: %s" % result["why"])
		return
	print("[апдейтер] перенесено файлів %d (з них скопійовано %d) у %s"
			% [result["moved"], result["copied"], _move_to])
	_status.text = "Гру перенесено в %s." % _move_to
	_switch_to(_move_to)


func open_folder() -> void:
	var at := install
	while at != "" and not DirAccess.dir_exists_absolute(at):
		at = at.get_base_dir()
	var err := OS.shell_show_in_file_manager(at)
	if err != OK:
		_fail("не відкрити теку %s: %s" % [at, error_string(err)])


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
		elif _job == "move":
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
	print("[апдейтер] питаю %s:%d (%s), тека %s" % [host, http_port,
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
		_bar_text.text = "%s — %s з %s" % [now["what"],
				SYNC._mb(now["done"]), SYNC._mb(now["total"])]
	else:
		_bar_text.text = now["what"]
	if _thread.is_alive():
		return
	var result: Dictionary = _thread.wait_to_finish()
	_thread = null
	var kind := _job
	_job = ""
	match kind:
		"check":
			_checked(result)
		"update":
			_updated(result)
		"move":
			_moved(result)
		"self":
			_self_updated(result)
	if _check_again and not busy():
		_check_again = false
		start_check()


func _checked(result: Dictionary) -> void:
	config = result.get("config", {})
	manifest = result.get("manifest", {})
	need = result.get("need", [])
	need_bytes = int(result.get("need_bytes", 0))
	installed = int(result.get("installed", 0))
	_show_server()
	if OS.get_cmdline_user_args().has("--оновити-себе") and newer_updater() \
			and not _self_tried:
		_self_tried = true
		print("[апдейтер] --оновити-себе: %s" % (self_update_problem()
				if self_update_problem() != "" else "починаю"))
		if self_update_problem() == "":
			_self_update.call_deferred()
	if not config.is_empty():
		remember_setting("сервер", "адреса", _address.text.strip_edges())
	if result.has("why"):
		_bar_text.text = ""
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
	if newer_updater():
		if self_update_problem() == "":
			warn.append("Є новіший апдейтер (v%d, у тебе v%d) — натисни " \
					% [int(config["updater_version"]), own_version()]
					+ "«Оновити апдейтер»: він оновить себе й перезапуститься.")
		else:
			warn.append("Є новіший апдейтер (v%d, у тебе v%d): %s" \
					% [int(config["updater_version"]), own_version(),
					self_update_problem()])
	if not manifest.is_empty() and int(manifest.get("release", 0)) \
			< int(config.get("min_client_release", 0)):
		warn.append("Для %s на сервері лише випуск %d, а потрібен %d — " \
				% [platform, int(manifest["release"]),
				int(config["min_client_release"])]
				+ "попроси власника опублікувати збірку.")
	_warn.text = "\n".join(warn)
	_self_button.visible = newer_updater() and self_update_problem() == "" \
			and not busy()


# ── самооновлення ───────────────────────────────────────────────────────
## Слово замовника 27.11.2026 (знімок з Mac: «Є новіший апдейтер — попроси
## його в власника»): «як це виправити, чи може апдейтер автоматично
## оновлюватись?». Новий апдейтер сервер роздає так само, як клієнт гри
## (`/manifest/updater-<система>.json`). Качаємо його в теку поруч із собою,
## а тоді: себе → «…old» (запущену програму перейменувати можна навіть на
## Windows), новий → на своє місце, запуск нового, вихід. «…old» прибирає
## наступний запуск.
const SELF_STAGE := ".myway-updater-new"
var _self_tried := false


func newer_updater() -> bool:
	return int(config.get("updater_version", 0)) > own_version()


## Що оновлювати: на Mac — бандл .app, деінде — сам виконуваний файл.
static func self_path() -> String:
	var exe := OS.get_executable_path()
	if OS.get_name() == "macOS":
		var app := exe.get_base_dir().get_base_dir().get_base_dir()
		if app.ends_with(".app"):
			return app
	return exe


## Чому самооновлення неможливе; порожньо — можна.
func self_update_problem() -> String:
	var page := str(config.get("updater_page", ""))
	var manual := " Завантаж новий%s і заміни цей." % (
			" з %s" % page if page != "" else " у власника сервера")
	if not OS.has_feature("template"):
		return "апдейтер запущено не зі збірки — самооновлення лише у " \
				+ "зібраному." + manual
	var here := self_path()
	if here.contains("/AppTranslocation/"):
		return "macOS запустив апдейтер з тимчасової теки лише для читання. " \
				+ "Перенеси «MyWay Updater» у «Програми» (чи будь-яку свою " \
				+ "теку) і запусти звідти — тоді він оновлюватиметься сам."
	var why := SYNC.writable_problem(here.get_base_dir())
	if why != "":
		return "у теку апдейтера не можна писати (%s)." % why + manual
	return ""


func _self_update() -> void:
	if busy():
		return
	var why := self_update_problem()
	if why != "":
		_fail(why)
		return
	error_text = ""
	_sync = SYNC.new()
	_sync.host = host
	_sync.port = http_port
	_sync.install = self_path().get_base_dir().path_join(SELF_STAGE)
	_sync.platform = "updater-" + platform
	_job = "self"
	_thread = Thread.new()
	_thread.start(_sync.job_self_update)
	_refresh()


func _self_updated(result: Dictionary) -> void:
	if result.has("why"):
		_fail("новий апдейтер не завантажено: %s" % result["why"])
		return
	var fresh: Dictionary = result["manifest"]
	var here := self_path()
	var stage := here.get_base_dir().path_join(SELF_STAGE)
	var incoming := stage.path_join(str(fresh.get("app", fresh["launch"])))
	var old := here + ".old"
	remove_tree(old)
	var err := DirAccess.rename_absolute(here, old)
	if err != OK:
		_fail("не вдалось відсунути старий апдейтер %s: %s" % [here,
				error_string(err)])
		return
	err = DirAccess.rename_absolute(incoming, here)
	if err != OK:
		DirAccess.rename_absolute(old, here)
		_fail("не вдалось поставити новий апдейтер на місце %s: %s — лишився "
				% [here, error_string(err)] + "старий, він працює")
		return
	remove_tree(stage)
	print("[апдейтер] оновлено до v%s, перезапускаю %s" % [
			fresh.get("release", "?"), here])
	# Ті самі аргументи, що в цього запуску (--тека тощо), крім самого
	# --оновити-себе: новий не має кинутись оновлюватись знову.
	var again: Array = Array(OS.get_cmdline_args())
	var mine: Array = Array(OS.get_cmdline_user_args())
	mine.erase("--оновити-себе")
	if not mine.is_empty():
		again += ["--"] + mine
	var pid := OS.create_process("open", ["-n", here, "--args"] + again) \
			if OS.get_name() == "macOS" else OS.create_process(here, again)
	if pid == -1:
		_fail("новий апдейтер стоїть на місці, але не запустився — відкрий "
				+ "його сам: %s" % here)
		return
	get_tree().quit()


## Прибрати «…old» після минулого самооновлення (лише у зібраному).
static func clean_self_update() -> void:
	if not OS.has_feature("template"):
		return
	remove_tree(self_path() + ".old")


static func remove_tree(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		return
	if not DirAccess.dir_exists_absolute(path):
		return
	for name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(name))
	for name in DirAccess.get_directories_at(path):
		remove_tree(path.path_join(name))
	DirAccess.remove_absolute(path)


func _fail(why: String) -> void:
	error_text = why
	print("[апдейтер] ‼ ", why)
	_refresh()


## Чому «Грати» не можна; порожньо — можна.
func play_blocker() -> String:
	if busy():
		return "зачекай: %s" % {"update": "оновлюю", "move": "переношу",
				"self": "оновлюю апдейтер"} \
				.get(_job, "перевіряю")
	if pending_kind != "":
		return "дай відповідь на питання про теку"
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
	_warn.visible = _warn.text != ""
	_server.visible = _server.text != ""
	_address.editable = _job != "update" and _job != "move"
	_check_button.disabled = _job == "update" or _job == "move"
	_dir.text = install
	_dir_button.disabled = busy()
	var free: int = SYNC.space_left(install)
	_dir_info.text = "Повний шлях: %s · %s" % [install, ("вільно на диску %s"
			% SYNC._mb(free)) if free >= 0 else "вільне місце невідоме"]
	if installed_in(install) or (not manifest.is_empty()
			and FileAccess.file_exists(install.path_join(str(
			manifest["launch"])))):
		_installed_label.text = "Гра встановлена в: %s" % install
	else:
		_installed_label.text = "Гра ще не встановлена — буде в: %s" % install
	if _job == "update":
		_update.text = "Зупинити"
		_update.disabled = false
	else:
		_update.text = "Оновити"
		_update.disabled = busy() or manifest.is_empty() or need.is_empty() \
				or client_pid != -1 or pending_kind != ""
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


# ── налаштування ─────────────────────────────────────────────────────────

static func setting(section: String, key: String) -> String:
	if not FileAccess.file_exists(SETTINGS_FILE):
		return ""
	var file := ConfigFile.new()
	if file.load(SETTINGS_FILE) != OK:
		print("[апдейтер] ‼ не прочитав %s" % SETTINGS_FILE)
		return ""
	return str(file.get_value(section, key, ""))


static func remember_setting(section: String, key: String,
		value: String) -> void:
	var file := ConfigFile.new()
	if FileAccess.file_exists(SETTINGS_FILE):
		file.load(SETTINGS_FILE)
	file.set_value(section, key, value)
	var err := file.save(SETTINGS_FILE)
	if err != OK:
		print("[апдейтер] ‼ не запам'ятав %s/%s у %s: %s" % [section, key,
				SETTINGS_FILE, error_string(err)])


static func last_address() -> String:
	var address := setting("сервер", "адреса")
	if address == "" and FileAccess.file_exists(OLD_ADDRESS_FILE):
		var file := ConfigFile.new()
		if file.load(OLD_ADDRESS_FILE) == OK:
			address = str(file.get_value("сервер", "адреса", ""))
	return address


static func remember_address(text: String) -> void:
	remember_setting("сервер", "адреса", text.strip_edges())


func _exit_tree() -> void:
	if _thread != null:
		_sync.stop()
		_thread.wait_to_finish()
