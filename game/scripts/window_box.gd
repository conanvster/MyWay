class_name WindowBox
extends Control
## Спільна оболонка для вікон гри: «Речі», «Стати», «Скіли».
##
## Замовник обрав три окремі вікна зі спільним виглядом (03.09.2026), і
## сенс саме в спільному: доти кожне вікно мало свій відступ, свій шрифт
## заголовка і своє місце на екрані, а закрити його можна було лише тією
## самою кнопкою в куті, якою відкрив. Тепер у кожного є заголовок,
## хрестик і перетягування мишею — і додати четверте вікно коштує рядок.
##
## Вміст кладеться в `body`. Оболонка про нього не знає нічого, крім
## розміру, який їй сказали.

const TITLE_H := 30.0     ## смуга заголовка; за неї ж і тягнуть
const PAD := 12.0         ## поле навколо вмісту
const BACK := Color(0.07, 0.07, 0.09, 0.94)
const TITLE_BACK := Color(0.15, 0.15, 0.18, 0.98)
const EDGE := Color(0.34, 0.35, 0.32, 0.85)
const CLOSE := Vector2(24, 20)

## Куди класти вміст. Координати всередині — від нуля, тож вміст не знає
## ні про заголовок, ні про поля.
var body: Control

var _dragging := false
var _grabbed := Vector2.ZERO
var _title_bar: Control
## Що росте разом із вікном: тло, обрис, смуга заголовка, хрестик.
var _plate: ColorRect
var _title_plate: ColorRect
var _shut: Button
var _edges: Array = []


func setup(caption: String, inner: Vector2) -> void:
	size = Vector2(inner.x + PAD * 2.0, inner.y + PAD * 2.0 + TITLE_H)
	custom_minimum_size = size
	# Вікно ловить мишу цілком: інакше клік по ньому проходить крізь у
	# світ і персонаж біжить туди, куди ти просто хотів натиснути річ.
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	_plate = ColorRect.new()
	_plate.color = BACK
	_plate.size = size
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_plate)

	_title_bar = Control.new()
	_title_bar.size = Vector2(size.x, TITLE_H)
	_title_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_title_bar.gui_input.connect(_on_title_input)
	add_child(_title_bar)

	_title_plate = ColorRect.new()
	_title_plate.color = TITLE_BACK
	_title_plate.size = _title_bar.size
	_title_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_bar.add_child(_title_plate)

	var caption_text := Label.new()
	caption_text.text = caption
	caption_text.position = Vector2(PAD, 5)
	caption_text.add_theme_font_size_override("font_size", 15)
	caption_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_bar.add_child(caption_text)

	# Хрестик. Стоїть у смузі заголовка, але окремою кнопкою: інакше
	# натиск по ньому почав би тягнути вікно.
	_shut = Button.new()
	_shut.name = "Закрити"
	_shut.text = "✕"
	_shut.position = Vector2(size.x - CLOSE.x - 6, 5)
	_shut.size = CLOSE
	_shut.custom_minimum_size = CLOSE
	_shut.flat = true
	_shut.add_theme_font_size_override("font_size", 14)
	_shut.pressed.connect(func() -> void: visible = false)
	_title_bar.add_child(_shut)

	body = Control.new()
	body.name = "Вміст"
	body.position = Vector2(PAD, TITLE_H + PAD)
	body.size = inner
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body)

	# Обрис малюємо самі: чотири тонкі смуги дешевші за стиль кнопки й
	# не залежать від теми, якої в проєкті немає.
	for edge: Array in [[Vector2.ZERO, Vector2(size.x, 1)],
			[Vector2(0, size.y - 1), Vector2(size.x, 1)],
			[Vector2.ZERO, Vector2(1, size.y)],
			[Vector2(size.x - 1, 0), Vector2(1, size.y)]]:
		var line := ColorRect.new()
		line.color = EDGE
		line.position = edge[0]
		line.size = edge[1]
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(line)
		_edges.append(line)


## Змінити розмір уже зібраного вікна. Потрібно «Скілам»: їхня висота
## залежить від того, скільки вивчено, а це відомо лише від сервера.
func resize(inner: Vector2) -> void:
	size = Vector2(inner.x + PAD * 2.0, inner.y + PAD * 2.0 + TITLE_H)
	custom_minimum_size = size
	_plate.size = size
	_title_bar.size = Vector2(size.x, TITLE_H)
	_title_plate.size = _title_bar.size
	_shut.position = Vector2(size.x - CLOSE.x - 6, 5)
	body.size = inner
	var shapes: Array = [Vector2(size.x, 1), Vector2(size.x, 1),
			Vector2(1, size.y), Vector2(1, size.y)]
	var spots: Array = [Vector2.ZERO, Vector2(0, size.y - 1),
			Vector2.ZERO, Vector2(size.x - 1, 0)]
	for i in _edges.size():
		_edges[i].position = spots[i]
		_edges[i].size = shapes[i]


func toggle() -> void:
	visible = not visible
	if visible:
		_keep_on_screen()


## Перетягування за заголовок.
##
## Позиція лишається ВІДНОСНОЮ до якоря: тоді вікно, поставлене праворуч
## унизу, там і лишається, коли гру розгорнули на весь екран. Тягнемо
## самі відступи, а межі міряємо по `global_position`.
func _on_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_grabbed = event.position
	elif event is InputEventMouseMotion and _dragging:
		position += event.position - _grabbed
		_keep_on_screen()


## Вікно, витягнуте за край, уже не повернути — заголовка, за який тягти,
## там немає. Тому смуга заголовка завжди лишається на екрані хоча б
## кутом у 80 точок.
func _keep_on_screen() -> void:
	var screen: Vector2 = get_viewport_rect().size
	var want: Vector2 = global_position.clamp(
			Vector2(80.0 - size.x, 0.0),
			Vector2(screen.x - 80.0, screen.y - TITLE_H))
	position += want - global_position
