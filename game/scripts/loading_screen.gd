class_name LoadingScreen
extends CanvasLayer
## Екран «Завантаження світу» при вході (слово замовника 27.11.2026 після
## журналу з iMac: перші 30–50 с гри — паузи 0,8…11 с на побудові ділянок і
## компіляції шейдерів → «так» на екран завантаження).
##
## Поки він зверху, світ позаду вже малюється: будуються ділянки довкола
## гравця (з великим бюджетом на кадр), а камера один раз обертається на
## чотири боки — відеокарта готує шейдери землі, лісу, неба й моделей, які
## інакше збиралися б посеред гри. Сам він нічого не рахує: стадії веде
## `world._tick_loading`.

var _title: Label
var _line: Label
var _bar: ProgressBar


func _ready() -> void:
	layer = 100
	var back := ColorRect.new()
	back.color = Color(0.07, 0.08, 0.08)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(back)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(520, 0)
	box.position = -box.custom_minimum_size * 0.5
	box.add_theme_constant_override("separation", 12)
	back.add_child(box)
	_title = Label.new()
	_title.text = "Завантаження світу…"
	_title.add_theme_font_size_override("font_size", 30)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(520, 18)
	_bar.show_percentage = false
	box.add_child(_bar)
	_line = Label.new()
	_line.add_theme_font_size_override("font_size", 16)
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.modulate = Color(0.8, 0.82, 0.78)
	box.add_child(_line)


func show_step(text: String, part: float) -> void:
	if _line != null:
		_line.text = text
		_bar.value = clampf(part, 0.0, 1.0) * 100.0
