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

var _server_alive := false
var _db_alive := false
var _server_pid := -1

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
	if Net.is_server or OS.get_cmdline_user_args().has("--демо"):
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


func _check() -> void:
	# Сервер: пробуємо просто з'єднатись із його портом. Відповів —
	# значить, він уже слухає, а не «ось-ось почне».
	var probe := StreamPeerTCP.new()
	var err := probe.connect_to_host("127.0.0.1", SERVER_PORT)
	if err == OK:
		probe.poll()
		var status := probe.get_status()
		# Одного кадру мало: спершу з'єднання «в дорозі».
		if status == StreamPeerTCP.STATUS_CONNECTING:
			probe.poll()
			status = probe.get_status()
		_server_alive = status == StreamPeerTCP.STATUS_CONNECTED
	probe.disconnect_from_host()
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
	_server_light.text = "сервер: %s" % ("працює" if _server_alive
			else "не запущений")
	_server_light.add_theme_color_override("font_color",
			Color(0.5, 0.85, 0.5) if _server_alive else Color(0.85, 0.5, 0.45))
	_play.disabled = not _server_alive
	_play.text = "Зайти в гру" if _server_alive \
			else "Зайти в гру (спершу сервер)"
	_server_button.disabled = _server_alive
	_db_button.disabled = _db_alive


# ── запуск ────────────────────────────────────────────────────────────

func _start_server() -> void:
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--", "--server"]
	if _db_alive:
		args.append("--база")
		args.append(DB_URL)
	_server_pid = OS.create_process(OS.get_executable_path(), args)
	_log.text = "сервер запущено, номер %d%s" % [_server_pid,
			"" if _db_alive else " — без бази"]
	_since = CHECK_EVERY          # перевірити одразу наступним кадром


func _stop_server() -> void:
	if _server_pid > 0:
		OS.kill(_server_pid)
		_log.text = "сервер зупинено"
		_server_pid = -1
	else:
		_log.text = "цю сторінку сервер не запускала — зупини його там, де запустив"
	_server_alive = false
	_paint()


func _start_db() -> void:
	var binary := OS.get_environment("HOME") + "/.local/bin/postgrest"
	if not FileAccess.file_exists(binary):
		_log.text = "PostgREST не встановлено — див. db/HOW-TO-RUN.md"
		return
	var root := ProjectSettings.globalize_path("res://").path_join("../db")
	OS.create_process(binary, [root.path_join("postgrest.conf")])
	_log.text = "базу піднято, чекаю відповіді…"


func _enter_world() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
