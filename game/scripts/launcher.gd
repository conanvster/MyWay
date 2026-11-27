extends Control
## Стартова сторінка: підняти базу, підняти сервер, і аж потім зайти.
##
## Навіщо вона. Один скрипт, який піднімає все підряд, дає перегони:
## клієнт стукає до сервера, поки той ще читає дані, а сервер стукає до
## бази, поки та ще не відповідає. Тоді видно тільки «код 0», і не
## зрозуміло, хто саме не встиг.
##
## Тут кожен крок окремо, і **кнопка «Зайти в гру» не працює, доки сервер
## не відповів**. Це не прикраса: це те, що прибирає цілий клас вад.
##
## Сервер в іншій машині (клієнт для Mac, 26.11.2026): поле «IP сервера» і
## «Підключитися». У зібраному клієнті (`template`) лишається ЛИШЕ воно:
## базу й сервер там підняти нічим, і кнопки, що не можуть спрацювати,
## тільки плутали б гравця. Те саме вдома — `-- --лише-мережа`.

const NET := preload("res://scripts/net.gd")

const SERVER_PORT := 24565
const DB_URL := "http://127.0.0.1:3000"
const CHECK_EVERY := 0.7
## Мітку кладе сам сервер, коли світ уже збудовано (`world.gd`).
const READY_MARK := "user://сервер.json"
## Світ сервера, якщо він не той, що в сторінки (з мітки); порожньо — збіг
## або мітка ще без світу.
var _clash := ""

## Порт зайнято: мережа сервера піднята.
var _port_busy := false
## Порт зайнято І світ збудовано — аж тоді пускаємо в гру.
var _server_alive := false
var _db_alive := false
var _server_pid := -1
## Чи сказали в консоль хоч раз, який стан сервера.
var _said := false

var _db_light: Label
var _server_light: Label
var _play: Button
var _db_button: Button
var _server_button: Button
var _log: Label
## Вибір світу (П-204): персонажі в кожному світі свої.
var _world_pick: OptionButton
var _since := 0.0
var _probe: HTTPRequest
## Адреса сервера в мережі й кнопка до нього.
var _address: LineEdit
var _connect: Button
## Чи вже підключались самі за `--host` — лише раз за життя процесу.
static var _auto_used := false


## Чи лише клієнт до чужого сервера: зібраний застосунок або прапорець.
static func remote_only() -> bool:
	return OS.has_feature("template") \
			or OS.get_cmdline_user_args().has("--лише-мережа")


func _ready() -> void:
	# Сервер запускається тим самим виконуваним файлом, тільки без вікна:
	# він не має бачити цієї сторінки.
	#
	# `Net` беремо з дерева, а не по імені. У режимі `--script`
	# автозавантажень немає (пастка з CONTEXT.md), і сама згадка імені не
	# дає пробі навіть скомпілювати цей файл — а сторінку треба перевіряти.
	var net := get_node_or_null("/root/Net")
	# Повернулись сюди з причиною (сервер зник) — у `--демо` не стукаємо
	# знову по колу, а лишаємось на сторінці й показуємо причину.
	var why := str(net.why_left) if net != null else ""
	if (net != null and net.is_server) \
			or (OS.get_cmdline_user_args().has("--демо") and why == ""):
		_enter_world()
		return
	# Тут сторінку бачить живий гравець — і лише тут ставимо його розмір
	# вікна й масштаб (проби й сервер сюди не доходять, див. вище).
	if not GameSettings.active:
		GameSettings.apply_saved(get_window())
	_build()
	# Чому повернулись сюди зі світу — сервер не відповів, обірвалось.
	if net != null and str(net.why_left) != "":
		_say(str(net.why_left), true)
		net.why_left = ""
	if remote_only():
		# Апдейтер дав `--host`: підключаємось самі, раз. Після невдачі
		# лишаємось на сторінці з причиною — інакше стукали б по колу.
		if net != null and str(net.host_given) != "" and not _auto_used \
				and why == "":
			_auto_used = true
			_connect_remote.call_deferred()
		return
	_probe = HTTPRequest.new()
	add_child(_probe)
	_probe.request_completed.connect(_db_answered)
	_check()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var back := ColorRect.new()
	back.color = Color(0.05, 0.06, 0.08)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-210, -170)
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	var head := Label.new()
	head.text = "MyWay"
	head.add_theme_font_size_override("font_size", 34)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)

	_world_pick = _worlds(box)
	if not remote_only():
		_db_light = _line(box, "база: перевіряю…")
		_db_button = _button(box, "Підняти базу", _start_db)
		_server_light = _line(box, "сервер: перевіряю…")
		_server_button = _button(box, "Підняти сервер", _start_server)
		_play = _button(box, "Зайти в гру", _enter_local)
		_play.disabled = true
		_button(box, "Зупинити сервер", _stop_server)
	_remote(box)

	_log = _line(box, "")
	_log.add_theme_font_size_override("font_size", 12)
	var version := _line(box, "версія: " + NET.build_version())
	version.add_theme_font_size_override("font_size", 11)
	version.add_theme_color_override("font_color", Color(0.55, 0.57, 0.6))
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.custom_minimum_size = Vector2(420, 0)


## Сервер в іншій машині: адреса й «Підключитися». Остання введена адреса
## вже стоїть у полі — щоразу її не вводять.
func _remote(box: VBoxContainer) -> void:
	var head := _line(box, "сервер у мережі:" if not remote_only()
			else "IP сервера:")
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_address = LineEdit.new()
	_address.placeholder_text = "наприклад 192.168.1.48 або 192.168.1.48:%d" \
			% NET.PORT
	_address.custom_minimum_size = Vector2(420, 38)
	var net := get_node_or_null("/root/Net")
	_address.text = str(net.host_given) if net != null \
			and str(net.host_given) != "" else NET.last_address()
	_address.text_submitted.connect(func(_t: String) -> void:
			_connect_remote())
	box.add_child(_address)
	_connect = _button(box, "Підключитися", _connect_remote)


## Рядок під кнопками: що сталося. Помилка — червоним.
func _say(text: String, bad: bool) -> void:
	_log.text = text
	_log.add_theme_color_override("font_color",
			Color(0.95, 0.5, 0.45) if bad else Color(0.8, 0.8, 0.8))


## «Підключитися»: розібрати адресу, запам'ятати, зайти. Чи сервер живий,
## скаже сам світ: не відповів за `CONNECT_WAIT` — поверне сюди з причиною.
func _connect_remote() -> void:
	var asked := NET.parse_address(_address.text)
	if asked.has("why"):
		_say(str(asked["why"]), true)
		return
	var net := get_node_or_null("/root/Net")
	if net == null:
		_say("‼ немає мережі (Net): клієнт зібрано без автозавантаження",
				true)
		return
	net.host = str(asked["host"])
	net.port = int(asked["port"])
	NET.remember_address(_address.text)
	_say("з'єднуюсь із %s:%d…" % [net.host, net.port], false)
	_connect.disabled = true
	print("[сторінка] підключаюсь до %s:%d" % [net.host, net.port])
	_enter_world()


## «Зайти в гру» на свій сервер: адреса з рядка запуску, а не та, що
## лишилась від спроби підключитись деінде.
func _enter_local() -> void:
	var net := get_node_or_null("/root/Net")
	if net != null:
		net.address_from_args()
	_enter_world()


## Вибір світу (П-204). Персонажі в кожному світі свої, тож світ треба
## обрати ДО входу — саме тут, а не прапорцем у командному рядку.
##
## Змінюємо не аргументи процесу, а `GameData.chosen_map`: сторінка й
## гра живуть в одному процесі, і цього досить. Серверові світ іде
## прапорцем, бо він процес окремий.
func _worlds(box: VBoxContainer) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var title := Label.new()
	title.text = "світ:"
	row.add_child(title)
	var pick := OptionButton.new()
	pick.custom_minimum_size = Vector2(340, 34)
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Основний перший (П-205): світ 600 м лишився для проб.
	pick.add_item("Світ 2 — 5632 м, основний")
	pick.set_item_metadata(0, GameData.MAP2_PATH)
	pick.add_item("Світ 1 — 600 м, тестовий")
	pick.set_item_metadata(1, GameData.MAP_PATH)
	pick.selected = 1 if GameData.map_path() == GameData.MAP_PATH else 0
	pick.item_selected.connect(func(at: int) -> void:
			GameData.chosen_map = str(pick.get_item_metadata(at))
			_log.text = "світ: %s. Якщо сервер уже стоїть в іншому — " \
					% GameData.world_key() + "зупини й підніми знову"
			_said = false
			_since = CHECK_EVERY)
	row.add_child(pick)
	return pick


func _line(box: VBoxContainer, text: String) -> Label:
	var line := Label.new()
	line.text = text
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(line)
	return line


func _button(box: VBoxContainer, text: String, action: Callable) -> Button:
	var press := Button.new()
	press.text = text
	press.custom_minimum_size = Vector2(420, 38)
	press.pressed.connect(action)
	box.add_child(press)
	return press


# ── перевірки ─────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _play == null:
		return
	_since += delta
	if _since < CHECK_EVERY:
		return
	_since = 0.0
	_check()


## Чи зайнято порт сервера.
##
## Пробуємо стати на нього самі. Стали — значить, порт вільний і сервера
## немає; не пустило (`ERR_UNAVAILABLE`) — там уже хтось слухає.
##
## Чому не з'єднанням, як було досі: ENet ходить по **UDP**, а сторінка
## стукала `StreamPeerTCP`. На TCP-порт 24565 не слухає ніхто й ніколи,
## тож рядок «сервер: не запущений» горів навіть тоді, коли сервер працює
## й пише в журнал «сервер чекає гравців». Заміряно 02.09.2026:
## `ss -ltn` на 24565 порожній, `ss -lun` показує сервер.
func _port_taken() -> bool:
	var socket := PacketPeerUDP.new()
	var err := socket.bind(SERVER_PORT, "127.0.0.1")
	socket.close()
	return err != OK


## Мітка від сервера: світ збудовано. Читаємо її лише при зайнятому
## порті — після вбитого сервера мітка лишається на диску.
func _ready_mark() -> Dictionary:
	if not FileAccess.file_exists(READY_MARK):
		return {}
	var text := FileAccess.get_file_as_string(READY_MARK)
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


func _check() -> void:
	var was := _server_alive
	var was_busy := _port_busy
	# Свій сервер питаємо про життя прямо (`OS.is_process_running` працює
	# лише для власних дітей), чужий — портом. Так наша проба не намагається
	# стати на порт у ту саму мить, коли на нього стає щойно запущений
	# нами ж сервер: вікно між `bind` і `close` мале, але не нульове.
	if _server_pid > 0 and OS.is_process_running(_server_pid):
		_port_busy = true
	else:
		_server_pid = -1
		_port_busy = _port_taken()
	# Зелене — тільки коли світ уже стоїть. Порт займається раніше, ніж
	# сервер прочитав дані й розставив монстрів.
	_server_alive = _port_busy and not _ready_mark().is_empty()
	# У якому світі сервер — з його ж мітки. Не той, що в сторінки, —
	# у гру не пускаємо: там гравець опиниться під землею.
	var theirs := str(_ready_mark().get("світ", "")) if _server_alive else ""
	_clash = theirs if not theirs.is_empty() \
			and theirs != GameData.map_path().get_file() else ""
	# У консоль — при першому питанні й далі лише при зміні: сторінка
	# питає щосемидесятих секунди, і рівний рядок щоразу перетворив би
	# журнал на стрічку. Перший рядок потрібен, щоб людина, яка дивиться
	# в термінал, бачила стан, а не мовчання.
	if not _said or was != _server_alive or was_busy != _port_busy:
		_said = true
		print("[сторінка] сервер: %s" % ("працює" if _server_alive
				else ("підіймається" if _port_busy else "не запущений")))
	_paint()
	# Питаємо базу, лише коли попереднє питання вже відповіло: інакше
	# HTTPRequest свариться, що зайнятий.
	if _probe != null and _probe.get_http_client_status() \
			== HTTPClient.STATUS_DISCONNECTED:
		_probe.request(DB_URL + "/characters")


func _db_answered(_result: int, code: int, _headers: PackedStringArray,
		_body: PackedByteArray) -> void:
	_db_alive = code == 200
	_paint()


func _paint() -> void:
	_db_light.text = "база: %s" % ("працює" if _db_alive
			else "не відповідає — гра піде без збереження")
	_db_light.add_theme_color_override("font_color",
			Color(0.5, 0.85, 0.5) if _db_alive else Color(0.9, 0.75, 0.4))
	# Три стани, а не два: між «немає» і «працює» є секунда, коли порт уже
	# зайнято, а світ ще будується. Мовчати про неї — це знову вчити
	# людину тикати в кнопку, яка не спрацює.
	var state := "не запущений"
	var tint := Color(0.85, 0.5, 0.45)
	if _server_alive:
		state = "працює"
		tint = Color(0.5, 0.85, 0.5)
	elif _port_busy:
		state = "підіймається…"
		tint = Color(0.9, 0.75, 0.4)
	if _server_alive and not _clash.is_empty():
		state = "працює, але в іншому світі (%s) — зупини й підніми знову" \
				% _clash
		tint = Color(0.9, 0.45, 0.4)
	_server_light.text = "сервер: %s" % state
	_server_light.add_theme_color_override("font_color", tint)
	_play.disabled = not _server_alive or not _clash.is_empty()
	_play.text = "Зайти в гру" if _server_alive \
			else "Зайти в гру (спершу сервер)"
	if not _clash.is_empty():
		_play.text = "Зайти в гру (сервер в іншому світі)"
	# Поки порт зайнято, другий сервер підіймати нічим: він однаково не
	# візьме порт, зате з'їсть під гігабайт пам'яті (пастка з CONTEXT.md).
	_server_button.disabled = _port_busy
	_db_button.disabled = _db_alive


# ── запуск ────────────────────────────────────────────────────────────

## З чим піднімати сервер. Окремою функцією, щоб її перевіряла проба:
## сам запуск процесу в пробі не поставиш.
func _server_args() -> Array:
	var args := ["--headless", "--path",
			ProjectSettings.globalize_path("res://"), "--", "--server"]
	# Сервер — у тому самому світі, що й ця сторінка. Доти сторінка
	# піднімала його БЕЗ `--світ2`, навіть коли сама відкрита з ним:
	# сервер будував світ версії 1, клієнт — версії 2, і персонаж
	# з'являвся під землею (слово замовника 11.09.2026).
	#
	# Світ тепер беремо з вибору на сторінці (П-204), а не лише з
	# прапорця: прапорець задає те, що вибрано СПОЧАТКУ, далі вирішує
	# людина. Сервер — процес окремий, і світ йому йде так само
	# прапорцем.
	# Прапорець даємо ЗАВЖДИ, обидва — і той, що збігається з
	# замовчуванням. Інакше вибір «світ 1» на сторінці не доїхав би до
	# сервера: він процес окремий, замовчування в нього своє (П-205,
	# основний світ — другий), і сторінка опинилась би в одному світі,
	# а сервер у другому.
	args.append("--світ1" if GameData.map_path() == GameData.MAP_PATH
			else "--світ2")
	if _db_alive:
		args.append("--база")
		args.append(DB_URL)
	return args


func _start_server() -> void:
	var args := _server_args()
	_server_pid = OS.create_process(OS.get_executable_path(), args)
	_log.text = "сервер запущено, номер %d%s" % [_server_pid,
			"" if _db_alive else " — без бази"]
	_since = CHECK_EVERY          # перевірити одразу наступним кадром


## Зупинити сервер — і той, якого сторінка не піднімала.
##
## Свій номер ми знаємо з `create_process`. Чужий (з `./run-server.sh`)
## лежить у мітці, яку сервер кладе, збудувавши світ. Номер із мітки
## беремо ЛИШЕ при зайнятому порті: після вбитого сервера мітка лишається,
## а її номер за той час може дістатись комусь іншому.
## Кого зупиняти. Окремою функцією, щоб її перевіряла проба.
func _pid_to_stop() -> int:
	if _server_pid > 0:
		return _server_pid
	if _port_busy:
		return int(_ready_mark().get("номер", -1))
	return -1


func _stop_server() -> void:
	var pid := _pid_to_stop()
	if pid <= 0:
		_log.text = "сервер не знайдено — якщо він десь є, зупини ./play.sh --stop"
		_paint()
		return
	var err := OS.kill(pid)
	_server_pid = -1
	DirAccess.remove_absolute(ProjectSettings.globalize_path(READY_MARK))
	# Порт звільняється не в ту саму мить, тому не брешемо «зупинено», а
	# кажемо, що зробили; наступна перевірка через 0,7 с покаже правду.
	_log.text = "сервер %d зупинено" % pid if err == OK \
			else "не вдалось зупинити %d: %s" % [pid, error_string(err)]
	_since = CHECK_EVERY
	_paint()


func _start_db() -> void:
	var binary := OS.get_environment("HOME") + "/.local/bin/postgrest"
	if not FileAccess.file_exists(binary):
		_log.text = "PostgREST не встановлено — див. db/HOW-TO-RUN.md"
		return
	var root := ProjectSettings.globalize_path("res://").path_join("../db")
	OS.create_process(binary, [root.path_join("postgrest.conf")])
	_log.text = "базу піднято, чекаю відповіді…"


## Зайти у світ.
##
## `change_scene_to_file` тут не годиться: він звільняє поточну сцену
## просто в мить виклику, а ми — усередині `_ready` або сигналу, коли
## дерево саме додає вузли. Godot тоді каже «Parent node is busy
## adding/removing children», і ні відкладений виклик, ні очікування
## кадру цього не рятують.
##
## Тому світ **додається** в корінь сам, а сторінка прибирає себе
## `queue_free` — він відкладений за побудовою й безпечний завжди.
func _enter_world() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	if scene == null:
		return
	var world: Node = scene.instantiate()
	world.tree_entered.connect(func() -> void:
			get_tree().current_scene = world
			queue_free(), CONNECT_ONE_SHOT)
	get_tree().root.add_child.call_deferred(world)
