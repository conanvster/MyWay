class_name HUD
extends CanvasLayer
## Те, що бачить гравець поверх світу (крок 1.3).
##
## Досі гра не показувала нічого: ні свого здоров'я, ні здоров'я цілі, ні
## відкатів, ні черги, а повідомлення йшли в консоль. Без цього вміння
## (крок 2) не було б на чому ні відчути, ні налагодити.
##
## Будується кодом, а не сценою: .tscn для такої кількості дрібних вузлів
## руками не пишеться, а редактором його однаково довелося б перебирати
## після кожної зміни панелі (П-58).
##
## HUD нічого не вирішує і нікуди не шле — тільки показує те, що надіслав
## сервер (П-08).

const WIDE := 260.0        ## ширина смуг здоров'я
const CELL := 56.0         ## сторона комірки панелі
const GAP := 6.0
const MESSAGES := 5        ## скільки повідомлень тримати на екрані
const MESSAGE_TIME := 6.0
const FLOAT_TIME := 1.1    ## скільки летить число шкоди
const FLOAT_RISE := 46.0

const BACK := Color(0, 0, 0, 0.55)
const HP_COLOR := Color(0.72, 0.21, 0.18)
const MP_COLOR := Color(0.24, 0.42, 0.76)
const TARGET_COLOR := Color(0.78, 0.62, 0.22)

var _world: Node
## Скільки в кого здоров'я всього: сервер шле це, коли істота з'являється.
var _max_hp: Dictionary = {}
var _hp: Dictionary = {}
var _target := 0
var _bar: Array[String] = []

var _root: Control
var _hp_fill: ColorRect
var _mp_fill: ColorRect
var _vitals_text: Label
var _target_box: Control
var _target_name: Label
var _target_fill: ColorRect
var _queue_text: Label
var _messages: VBoxContainer
var _cells: Array = []
var _floats: Array = []


func setup(world: Node) -> void:
	_world = world
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_vitals()
	_build_target()
	_build_panel()
	_build_messages()


# ── збирання ──────────────────────────────────────────────────────────

func _plate(size: Vector2, color: Color, parent: Control) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.size = size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect


func _text(size: int, parent: Control) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


## Свої здоров'я й мана — ліворуч угорі.
func _build_vitals() -> void:
	var box := Control.new()
	box.position = Vector2(16, 16)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)

	_plate(Vector2(WIDE, 18), BACK, box)
	_hp_fill = _plate(Vector2(WIDE, 18), HP_COLOR, box)
	var mp_back := _plate(Vector2(WIDE, 10), BACK, box)
	mp_back.position = Vector2(0, 22)
	_mp_fill = _plate(Vector2(WIDE, 10), MP_COLOR, box)
	_mp_fill.position = Vector2(0, 22)

	_vitals_text = _text(13, box)
	_vitals_text.position = Vector2(6, 0)


## Рамка цілі — угорі посередині. Ховається, коли цілі немає (П-31).
func _build_target() -> void:
	_target_box = Control.new()
	_target_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_target_box.position = Vector2(-WIDE * 0.5, 16)
	_target_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_target_box.visible = false
	_root.add_child(_target_box)

	var frame := _plate(Vector2(WIDE + 8, 44), BACK, _target_box)
	frame.position = Vector2(-4, -4)
	_target_name = _text(14, _target_box)
	_plate(Vector2(WIDE, 14), Color(0.15, 0.05, 0.05, 0.9), _target_box) \
			.position = Vector2(0, 22)
	_target_fill = _plate(Vector2(WIDE, 14), TARGET_COLOR, _target_box)
	_target_fill.position = Vector2(0, 22)


## Панель 1-7 і черга дій — унизу посередині (П-20, П-38, П-58).
func _build_panel() -> void:
	var wide := CELL * 7 + GAP * 6
	var box := Control.new()
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.position = Vector2(-wide * 0.5, -CELL - 16)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)

	for i in 7:
		var at := Vector2(i * (CELL + GAP), 0)
		var cell := Control.new()
		cell.position = at
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(cell)
		_plate(Vector2(CELL, CELL), BACK, cell)
		var name_text := _text(11, cell)
		name_text.position = Vector2(4, CELL - 20)
		name_text.size = Vector2(CELL - 8, 16)
		var key := _text(11, cell)
		key.text = str(i + 1)
		key.position = Vector2(4, 2)
		# Затемнення на відкаті: спадає згори вниз, як пісок.
		var shade := _plate(Vector2(CELL, CELL), Color(0, 0, 0, 0.62), cell)
		shade.visible = false
		var left := _text(16, cell)
		left.position = Vector2(CELL * 0.5 - 10, CELL * 0.5 - 12)
		_cells.append({"name": name_text, "shade": shade, "left": left})

	_queue_text = _text(13, box)
	_queue_text.position = Vector2(0, -24)


## Рядок повідомлень — ліворуч унизу. Старі зникають самі.
func _build_messages() -> void:
	_messages = VBoxContainer.new()
	_messages.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_messages.position = Vector2(16, -140)
	_messages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_messages)


# ── те, що надсилає сервер ────────────────────────────────────────────

func set_bar(bar: Array) -> void:
	_bar.assign(bar)
	for i in _cells.size():
		var action: String = _bar[i] if i < _bar.size() else ""
		_cells[i]["name"].text = _title(action)


## Назви дій українською. Уміння з кроку 2 принесуть свої.
func _title(action: String) -> String:
	if action.begins_with("скіл:"):
		# У панелі стоїть ключ скіла; показуємо коротку назву.
		return action.substr(5).replace("енергетичний-", "енерг. ")
	match action:
		"attack": return "удар"
		"next_player": return "гравець"
		"next_mob": return "монстр"
		"corpse_skill": return "труп"
		"taunt": return "агресія"
		"": return ""
	return action


func set_vitals(id: int, hp: int, max_hp: int) -> void:
	_max_hp[id] = max_hp
	_hp[id] = hp


func set_hp(id: int, hp: int) -> void:
	_hp[id] = hp


func set_target(id: int) -> void:
	_target = id
	_target_box.visible = id != 0
	if id != 0:
		_target_name.text = ("монстр %d" % -id) if id < 0 else ("гравець %d" % id)


func forget(id: int) -> void:
	_max_hp.erase(id)
	_hp.erase(id)
	if _target == id:
		set_target(0)


## Свої числа приходять щотіку, разом із відкатами й чергою.
func update_self(hp: int, max_hp: int, mp: int, max_mp: int,
		slots: PackedFloat32Array, busy_in: float, queue: Array) -> void:
	_hp_fill.size.x = WIDE * clampf(float(hp) / maxf(1.0, max_hp), 0.0, 1.0)
	_mp_fill.size.x = WIDE * clampf(float(mp) / maxf(1.0, max_mp), 0.0, 1.0)
	_vitals_text.text = "%d / %d      мана %d / %d" % [hp, max_hp, mp, max_mp]

	for i in _cells.size():
		var action: String = _bar[i] if i < _bar.size() else ""
		# Відкат кожної комірки рахує сервер: в удару свій, у скіла свій.
		var left: float = slots[i] if i < slots.size() else 0.0
		var cell: Dictionary = _cells[i]
		cell["shade"].visible = left > 0.0 or action == ""
		if action == "":
			cell["shade"].color = Color(0, 0, 0, 0.35)
			cell["left"].text = ""
			continue
		cell["shade"].color = Color(0, 0, 0, 0.62)
		cell["left"].text = "%.1f" % left if left > 0.0 else ""

	var names: Array[String] = []
	for action in queue:
		names.append(_title(action))
	var tail := "  ·  замах %.2f" % busy_in if busy_in > 0.0 else ""
	_queue_text.text = ("черга: " + " · ".join(names) + tail) \
			if not names.is_empty() else tail.strip_edges()


func notice(text: String) -> void:
	var line := _text(14, _messages)
	line.text = text
	line.modulate = Color(1, 0.86, 0.6)
	while _messages.get_child_count() > MESSAGES:
		_messages.get_child(0).queue_free()
	var fade := create_tween()
	fade.tween_interval(MESSAGE_TIME)
	fade.tween_property(line, "modulate:a", 0.0, 0.8)
	fade.tween_callback(line.queue_free)


## Число шкоди над істотою. Летить угору й гасне.
func damage(id: int, amount: int, behind: bool) -> void:
	var who: Node3D = _world.creatures.get(id)
	if who == null:
		return
	var label := _text(20 if behind else 17, _root)
	label.text = ("%d у спину" % amount) if behind else str(amount)
	# Своя шкода червона, чужа біла: у бою треба з одного погляду бачити,
	# кому саме прилетіло. Удар зі спини помітний окремо.
	var mine: bool = id == _world.multiplayer.get_unique_id()
	if behind:
		label.modulate = Color(1.0, 0.55, 0.35)
	else:
		label.modulate = Color(1.0, 0.35, 0.3) if mine else Color(1, 1, 1)
	_floats.append({"label": label, "who": who, "left": FLOAT_TIME})


func _process(delta: float) -> void:
	if _target != 0 and _max_hp.has(_target):
		var share := float(_hp.get(_target, 0)) / maxf(1.0, _max_hp[_target])
		_target_fill.size.x = WIDE * clampf(share, 0.0, 1.0)
		_target_name.text = "%s   %d / %d" % [
				("монстр %d" % -_target) if _target < 0 else ("гравець %d" % _target),
				_hp.get(_target, 0), _max_hp[_target]]
	_move_floats(delta)


## Числа шкоди тримаються над головою тієї істоти, якій вони належать.
func _move_floats(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	for item in _floats.duplicate():
		item["left"] -= delta
		var label: Label = item["label"]
		if item["left"] <= 0.0 or camera == null \
				or not is_instance_valid(item["who"]):
			label.queue_free()
			_floats.erase(item)
			continue
		var gone: float = 1.0 - item["left"] / FLOAT_TIME
		var head: Vector3 = item["who"].global_position + Vector3(0, 1.6, 0)
		if camera.is_position_behind(head):
			label.visible = false
			continue
		label.visible = true
		label.position = camera.unproject_position(head) \
				- Vector2(label.size.x * 0.5, gone * FLOAT_RISE)
		label.modulate.a = 1.0 - gone * gone
