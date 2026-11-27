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

## Другий вигляд, «камінь і золото» (П-150) — темний камінь замість
## однотонного сірого, золоті рамка й ріжки замість тонкої лінії. Просить
## лише «Стати» й «Гільдія» (замовник дав приклад саме з них); решта
## вікон лишається на старому вигляді — це параметр, не заміна.
const GOTHIC_BACK := Color(0.075, 0.065, 0.055, 0.97)
const GOTHIC_INSET := Color(0.11, 0.095, 0.075, 0.9)
const GOTHIC_TITLE := Color(0.045, 0.038, 0.03, 0.99)
const GOTHIC_GOLD := Color(0.72, 0.58, 0.28)
const GOTHIC_GOLD_DIM := Color(0.5, 0.4, 0.2)
const STUD := 6.0
static var _gothic_font: FontVariation

## Вікно відпустили після перетягування — щоб запам'ятати, де воно.
signal moved
signal folded_changed(on: bool)

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
## Кнопка «згорнути» — лише у вікон, що її попросили (`add_fold`).
var _fold: Button
## Розмір вмісту розгорнутого вікна: до нього вертаємось із згорнутого.
var _inner := Vector2.ZERO
## Згорнуте до самої смуги заголовка.
var folded := false


var _gothic := false


## Шрифт «камінь і золото»: Cinzel, ліцензія SIL OFL (game/assets/fonts/
## OFL.txt) — не Diablo 2, схожий римський капітель того самого духу.
## Один екземпляр на всю гру: завантажувати шрифт на кожне вікно дорого.
## Вага змінного шрифту йде через OpenType-вісь `wght` (число 2003265652
## — це чотири літери «wght», прочитані як 32-бітне число: власного
## імені стать для осі Godot не дає, тільки тег).
const WGHT_AXIS := 2003265652

static func _font() -> FontVariation:
	if _gothic_font == null:
		var base: FontFile = load("res://assets/fonts/Cinzel-Variable.ttf")
		_gothic_font = FontVariation.new()
		_gothic_font.base_font = base
		_gothic_font.set_variation_opentype({WGHT_AXIS: 700.0})
	return _gothic_font


func setup(caption: String, inner: Vector2, gothic: bool = false) -> void:
	_gothic = gothic
	_inner = inner
	size = Vector2(inner.x + PAD * 2.0, inner.y + PAD * 2.0 + TITLE_H)
	custom_minimum_size = size
	# Вікно ловить мишу цілком: інакше клік по ньому проходить крізь у
	# світ і персонаж біжить туди, куди ти просто хотів натиснути річ.
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	_plate = ColorRect.new()
	_plate.color = GOTHIC_BACK if gothic else BACK
	_plate.size = size
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_plate)

	if gothic:
		# Тонша плашка всередині рамки — вдає заглиблений камінь без
		# справжньої текстури, якої в грі немає (П-150: чужу графіку
		# Diablo 2 брати не можна, лише той самий дух).
		var inset := ColorRect.new()
		inset.color = GOTHIC_INSET
		inset.position = Vector2(3, TITLE_H + 3)
		inset.size = Vector2(size.x - 6, size.y - TITLE_H - 6)
		inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(inset)

	_title_bar = Control.new()
	_title_bar.size = Vector2(size.x, TITLE_H)
	_title_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_title_bar.gui_input.connect(_on_title_input)
	add_child(_title_bar)

	_title_plate = ColorRect.new()
	_title_plate.color = GOTHIC_TITLE if gothic else TITLE_BACK
	_title_plate.size = _title_bar.size
	_title_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_bar.add_child(_title_plate)

	var caption_text := Label.new()
	caption_text.text = caption
	caption_text.position = Vector2(PAD, 3.0 if gothic else 5.0)
	caption_text.add_theme_font_size_override(
			"font_size", 18 if gothic else 15)
	caption_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if gothic:
		caption_text.add_theme_font_override("font", _font())
		caption_text.add_theme_color_override("font_color", GOTHIC_GOLD)
		caption_text.add_theme_constant_override("outline_size", 0)
		caption_text.size = Vector2(size.x - PAD * 2.0, 24)
		caption_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
	if gothic:
		_shut.add_theme_color_override("font_color", GOTHIC_GOLD)
	_shut.pressed.connect(func() -> void: visible = false)
	_title_bar.add_child(_shut)

	body = Control.new()
	body.name = "Вміст"
	body.position = Vector2(PAD, TITLE_H + PAD)
	body.size = inner
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body)

	# Обрис малюємо самі: чотири тонкі смуги дешевші за стиль кнопки й
	# не залежать від теми, якої в проєкті немає. У «камені» рамка
	# товща й золота, а по кутах — чотири «заклепки».
	var line_w := 2.0 if gothic else 1.0
	var line_color := GOTHIC_GOLD if gothic else EDGE
	for edge: Array in [[Vector2.ZERO, Vector2(size.x, line_w)],
			[Vector2(0, size.y - line_w), Vector2(size.x, line_w)],
			[Vector2.ZERO, Vector2(line_w, size.y)],
			[Vector2(size.x - line_w, 0), Vector2(line_w, size.y)]]:
		var line := ColorRect.new()
		line.color = line_color
		line.position = edge[0]
		line.size = edge[1]
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(line)
		_edges.append(line)

	if gothic:
		var far := size - Vector2(STUD, STUD)
		for corner: Vector2 in [Vector2.ZERO, Vector2(far.x, 0),
				Vector2(0, far.y), far]:
			var stud := ColorRect.new()
			stud.color = GOTHIC_GOLD_DIM
			stud.position = corner + Vector2(1, 1)
			stud.size = Vector2(STUD - 2.0, STUD - 2.0)
			stud.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(stud)


## Змінити розмір уже зібраного вікна. Потрібно «Скілам»: їхня висота
## залежить від того, скільки вивчено, а це відомо лише від сервера.
func resize(inner: Vector2) -> void:
	_inner = inner
	body.size = inner
	_lay_out(Vector2(inner.x + PAD * 2.0,
			TITLE_H if folded else inner.y + PAD * 2.0 + TITLE_H))


## Кнопка «згорнути / розгорнути» поруч із хрестиком. Перше таке вікно —
## «Лог» (11.10.2026): його тримають на екрані постійно, і заважати
## світові воно не мусить.
func add_fold() -> void:
	_fold = Button.new()
	_fold.name = "Згорнути"
	_fold.text = "—"
	_fold.tooltip_text = "згорнути / розгорнути"
	_fold.size = CLOSE
	_fold.custom_minimum_size = CLOSE
	_fold.flat = true
	_fold.add_theme_font_size_override("font_size", 14)
	_fold.pressed.connect(func() -> void: set_folded(not folded))
	_title_bar.add_child(_fold)
	_lay_out(size)


## Сховати хрестик: вікно, яке не закривають, а лише згортають. Інакше
## закрите вже нічим не відкрити — кнопки в меню в нього немає.
func no_close() -> void:
	_shut.visible = false
	_lay_out(size)


## Згорнути до смуги заголовка або розгорнути назад. Вікно в нижній
## половині екрана тримає НИЖНІЙ край: інакше згорнутий «Лог» у кутку
## висів би смужкою посеред екрана, а розгорнутий ліз би за низ.
func set_folded(on: bool) -> void:
	if on == folded:
		return
	var keep_bottom: bool = global_position.y + size.y * 0.5 \
			> get_viewport_rect().size.y * 0.5
	var was := size.y
	folded = on
	body.visible = not on
	var open_h := _inner.y + PAD * 2.0 + TITLE_H
	_lay_out(Vector2(size.x, TITLE_H if on else open_h))
	if keep_bottom:
		position.y += was - size.y
	_keep_on_screen()
	folded_changed.emit(on)


## Розкласти тло, заголовок, кнопки й обрис під розмір `whole`.
func _lay_out(whole: Vector2) -> void:
	# Спершу мінімум, тоді розмір: менший за старий мінімум розмір
	# Control мовчки підняв би назад, і вікно не згорнулось би.
	custom_minimum_size = whole
	size = whole
	_plate.size = size
	_title_bar.size = Vector2(size.x, TITLE_H)
	_title_plate.size = _title_bar.size
	_shut.position = Vector2(size.x - CLOSE.x - 6, 5)
	if _fold != null:
		# Без хрестика кнопка стає в кут, на його місце.
		_fold.position = _shut.position - Vector2(
				CLOSE.x + 4 if _shut.visible else 0.0, 0)
		_fold.text = "□" if folded else "—"
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
		if _dragging and not event.pressed:
			moved.emit()
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
