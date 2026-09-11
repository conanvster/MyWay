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
var _since := 0.0
var _probe: HTTPRequest


func _ready() -> void:
	# Сервер запускається тим самим виконуваним файлом, тільки без вікна:
	# він не має бачити цієї сторінки.
	#
	# `Net` беремо з дерева, а не по імені. У режимі `--script`
	# автозавантажень немає (пастка з CONTEXT.md), і сама згадка імені не
	# дає пробі навіть скомпілювати цей файл — а сторінку треба перевіряти.
	var net := get_node_or_null("/root/Net")
	if (net != null and net.is_server) \
			or OS.get_cmdline_user_args().has("--демо"):
		_enter_world()
		return
	_build()
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

	_db_light = _line(box, "база: перевіряю…")
	_db_button = _button(box, "Підняти базу", _start_db)
	_server_light = _line(box, "сервер: перевіряю…")
	_server_button = _button(box, "Підняти сервер", _start_server)
	_play = _button(box, "Зайти в гру", _enter_world)
	_play.disabled = true
	_button(box, "Зупинити сервер", _stop_server)

	_log = _line(box, "")
	_log.add_theme_font_size_override("font_size", 12)


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

func _start_server() -> void:
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--", "--server"]
	# Сервер — у тому самому світі, що й ця сторінка. Доти сторінка
	# піднімала його БЕЗ `--світ2`, навіть коли сама відкрита з ним: сервер
	# будував світ версії 1, клієнт — версії 2, і персонаж з'являвся під
	# землею (слово замовника 11.09.2026: «персонаж з'являється під землею,
	# немає змоги навіть зробити телепорт в місто»).
	if OS.get_cmdline_user_args().has("--світ2"):
		args.append("--світ2")
	if _db_alive:
		args.append("--база")
		args.append(DB_URL)
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
