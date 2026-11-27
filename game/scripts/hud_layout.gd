class_name HudLayout
extends Node
## Рухливі блоки показу: здоров'я, ціль, панель 1-7, координати, меню…
## (слово замовника 27.11.2026: «елементи інтерфейсу зробити рухливими з
## можливістю згорнути та пересунути»).
##
## Вікна (`WindowBox`) тягались і раніше — за свій заголовок. У блоків
## заголовка немає і не треба: він їв би місце на екрані постійно. Тому
## смужка-ручка з'являється лише тоді, коли мишу потримали над блоком:
## «≡ Назва  —». За назву тягнуть, «—» згортає. Згорнутий блок лишає
## на своєму місці саму смужку «+ Назва» — нею ж і розгортають.
##
## Кожен блок сидить у «тримачі» нульового розміру, поставленому в ту саму
## точку якоря (кут, середина низу…), що й сам блок. Вміст свої відступи
## зберігає як були, а тягнемо ми тримач. Тож блок, відсунутий від правого
## нижнього кута, там і лишається, коли вікно гри стає більшим.
##
## Зсув від рідного місця й згорнутість пишуться в налаштування
## (`GameSettings`, розділ «розкладка»).

signal changed

const GRIP_H := 18.0
const HOVER_PAD := 8.0
## Скільки потримати мишу над блоком, поки з'явиться ручка: інакше вона
## блимала б щоразу, коли курсор пробігає повз панель.
const HOVER_WAIT := 0.35
const HOVER_LEAVE := 0.6
## Скільки блоку мусить лишитись на екрані, коли його витягли за край.
const KEEP := 40.0
const GRIP_BACK := Color(0.15, 0.15, 0.18, 0.92)
const GRIP_EDGE := Color(0.34, 0.35, 0.32, 0.85)
const SECTION := "розкладка"

## Закріплено — ручки не з'являються (згорнуті блоки розгорнути можна).
var locked := false

var _root: Control
var _grips: Control
var _blocks: Array[Dictionary] = []
var _dragging: Dictionary = {}
## Межі блоків міряємо не щокадру: у панелі сотні вузлів.
const MEASURE_EVERY := 0.15
var _measure_left := 0.0
var _started := false


func setup(root: Control) -> void:
	_root = root
	locked = bool(GameSettings.get_value(SECTION, "закріплено", false))


## Узяти вже зібрані вузли `parts` (діти `_root` з одним і тим самим
## якорем `preset`) у новий рухливий блок.
func add(key: String, title: String, preset: int, parts: Array) -> Control:
	var holder := Control.new()
	holder.name = "Блок_" + key
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var first := (parts[0] as Control).get_index()
	_root.add_child(holder)
	_root.move_child(holder, first)
	holder.set_anchors_preset(preset)
	holder.offset_left = 0.0
	holder.offset_top = 0.0
	holder.offset_right = 0.0
	holder.offset_bottom = 0.0
	for part: Control in parts:
		_root.remove_child(part)
		holder.add_child(part)

	var grip := Control.new()
	grip.name = "Ручка_" + key
	grip.mouse_filter = Control.MOUSE_FILTER_STOP
	grip.visible = false
	var back := ColorRect.new()
	back.color = GRIP_BACK
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grip.add_child(back)
	var edge := ReferenceRect.new()
	edge.border_color = GRIP_EDGE
	edge.editor_only = false
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grip.add_child(edge)
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 12)
	label.position = Vector2(6, 0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grip.add_child(label)
	var fold := Button.new()
	fold.name = "Згорнути"
	fold.flat = true
	fold.focus_mode = Control.FOCUS_NONE
	fold.tooltip_text = "згорнути / розгорнути"
	fold.add_theme_font_size_override("font_size", 12)
	fold.custom_minimum_size = Vector2(22, GRIP_H)
	fold.size = fold.custom_minimum_size
	grip.add_child(fold)

	var block := {"key": key, "title": title, "holder": holder,
			"grip": grip, "back": back, "edge": edge, "label": label,
			"fold": fold, "rect": Rect2(), "folded": false,
			"hover": 0.0, "away": 0.0}
	fold.pressed.connect(func() -> void: set_folded(block, not block.folded))
	grip.gui_input.connect(func(event: InputEvent) -> void:
			_on_grip_input(block, event))
	_blocks.append(block)

	var shift: Variant = GameSettings.get_value(SECTION, key, Vector2.ZERO)
	if shift is Vector2:
		_set_shift(holder, shift)
	_dress(block)
	return holder


## Ручки — поверх усього показу. Кличе HUD, коли все вже зібрано.
func finish() -> void:
	_grips = Control.new()
	_grips.name = "Ручки"
	_grips.set_anchors_preset(Control.PRESET_FULL_RECT)
	_grips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_grips)
	for block in _blocks:
		_grips.add_child(block.grip)
	# HUD збирають ще поза деревом (`world.gd`), а екрана без дерева нема.
	if is_inside_tree():
		_start()


func _ready() -> void:
	if _grips != null:
		_start()


## Згорнуте з минулого разу — згортаємо, коли вже відомо, де блок.
func _start() -> void:
	if _started:
		return
	_started = true
	get_viewport().size_changed.connect(_keep_all.bind(false))
	(func() -> void:
		for block in _blocks:
			block.rect = _bounds(block)
			if bool(GameSettings.get_value(SECTION, block.key + "_згорнуто",
					false)):
				set_folded(block, true)
		_keep_all(false)).call_deferred()


func block_named(key: String) -> Dictionary:
	for block in _blocks:
		if block.key == key:
			return block
	return {}


func set_locked(on: bool) -> void:
	locked = on
	GameSettings.set_value(SECTION, "закріплено", on)


func set_folded(block: Dictionary, on: bool) -> void:
	if not on:
		block.holder.visible = true
	elif block.holder.visible:
		block.rect = _bounds(block)
		if block.rect.size == Vector2.ZERO:
			# Порожній зараз блок (ціль не вибрана) — смужка там, де він
			# стоїть, а не в лівому верхньому куті.
			block.rect = Rect2(block.holder.global_position, Vector2(120, 20))
		block.holder.visible = false
	block.folded = on
	block.hover = 0.0
	_dress(block)
	GameSettings.set_value(SECTION, block.key + "_згорнуто", on)
	changed.emit()


## Усе на рідні місця й розгорнути.
func reset() -> void:
	for block in _blocks:
		_set_shift(block.holder, Vector2.ZERO)
		if block.folded:
			set_folded(block, false)
	GameSettings.forget(SECTION)
	GameSettings.set_value(SECTION, "закріплено", locked)
	changed.emit()


func _dress(block: Dictionary) -> void:
	var label: Label = block.label
	label.text = ("+ " if block.folded else "≡ ") + str(block.title)
	var wide := label.get_minimum_size().x + 12.0
	var fold: Button = block.fold
	fold.text = "□" if block.folded else "—"
	fold.position = Vector2(wide, 0)
	var whole := Vector2(wide + fold.size.x + 2.0, GRIP_H)
	block.grip.size = whole
	block.back.size = whole
	block.edge.size = whole
	label.size = Vector2(wide - 6.0, GRIP_H)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	block.grip.visible = block.folded
	_place_grip(block)


## Межі блоку на екрані — об'єднання видимих шматків. Порожній блок
## (немає цілі, немає повідомлень) дає нульові межі, і ручки в нього нема.
func _bounds(block: Dictionary) -> Rect2:
	var out := Rect2()
	var holder: Control = block.holder
	if not holder.is_visible_in_tree():
		return block.rect
	for node in holder.find_children("*", "Control", true, false):
		var part := node as Control
		if not part.is_visible_in_tree() or part.size.x < 1.0 \
				or part.size.y < 1.0:
			continue
		var one := part.get_global_rect()
		out = one if out.size == Vector2.ZERO else out.merge(one)
	return out


func _place_grip(block: Dictionary) -> void:
	var rect: Rect2 = block.rect
	var grip: Control = block.grip
	if _root == null or not _root.is_inside_tree():
		return
	var screen := _root.get_viewport_rect().size
	var at := rect.position - Vector2(0, GRIP_H + 2.0)
	if at.y < 0.0:
		# Немає місця згори (блок під самим верхнім краєм) — під блоком.
		at.y = rect.end.y + 2.0 if not block.folded else rect.position.y
	grip.position = at.clamp(Vector2.ZERO, screen - grip.size)


func _on_grip_input(block: Dictionary, event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = block
		elif not _dragging.is_empty():
			_dragging = {}
			_keep(block, true)
	elif event is InputEventMouseMotion and is_same(_dragging, block):
		var step: Vector2 = event.relative
		_set_shift(block.holder, _shift(block.holder) + step)
		block.rect.position += step
		_place_grip(block)


## Не дати блокові піти за край: щонайменше KEEP точок лишаються на екрані.
func _keep(block: Dictionary, save: bool) -> void:
	var screen := _root.get_viewport_rect().size
	var rect: Rect2 = block.rect if block.folded else _bounds(block)
	if rect.size != Vector2.ZERO:
		var lo := Vector2(KEEP - rect.size.x, 0.0)
		var hi := screen - Vector2(KEEP, KEEP if not block.folded else GRIP_H)
		var want := rect.position.clamp(lo, hi)
		_set_shift(block.holder, _shift(block.holder) + want - rect.position)
		rect.position = want
		block.rect = rect
	_place_grip(block)
	if save:
		GameSettings.set_value(SECTION, block.key, _shift(block.holder))
		changed.emit()


## Зсув тримача від його якоря. Саме відступи, не `position`: позиція
## рахується від лівого верхнього кута батька, і збережена на одному
## розмірі вікна вона на іншому поставила б блок деінде.
static func _shift(holder: Control) -> Vector2:
	return Vector2(holder.offset_left, holder.offset_top)


static func _set_shift(holder: Control, to: Vector2) -> void:
	holder.offset_left = to.x
	holder.offset_right = to.x
	holder.offset_top = to.y
	holder.offset_bottom = to.y


func _keep_all(save: bool) -> void:
	for block in _blocks:
		_keep(block, save)


func _process(delta: float) -> void:
	if _root == null or _grips == null:
		return
	var mouse := _root.get_viewport().get_mouse_position()
	var hovered := _root.get_viewport().gui_get_hovered_control()
	_measure_left -= delta
	var measure := _measure_left <= 0.0
	if measure:
		_measure_left = MEASURE_EVERY
	for block in _blocks:
		var grip: Control = block.grip
		if block.folded:
			grip.visible = true
			continue
		if is_same(_dragging, block):
			continue
		var over_grip := grip.visible \
				and grip.get_global_rect().grow(4.0).has_point(mouse)
		var near := false
		if not locked:
			if measure:
				block.rect = _bounds(block)
			near = block.rect.size != Vector2.ZERO \
					and block.rect.grow(HOVER_PAD).has_point(mouse) \
					and _mine(block, hovered)
		if near or over_grip:
			block.hover += delta
			block.away = 0.0
			if block.hover >= HOVER_WAIT and not grip.visible:
				grip.visible = true
			if grip.visible:
				_place_grip(block)
		else:
			block.hover = 0.0
			block.away += delta
			if grip.visible and block.away >= HOVER_LEAVE:
				grip.visible = false


## Миша над самим блоком чи над порожнім світом, а не над вікном, що
## лежить поверх нього: тоді ручка лізла б на «Речі» чи «Карту».
func _mine(block: Dictionary, hovered: Control) -> bool:
	if hovered == null:
		return true
	return block.holder.is_ancestor_of(hovered) or hovered == block.grip \
			or block.grip.is_ancestor_of(hovered)
