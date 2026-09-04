class_name SkillCell
extends Control
## Один рядок у вікні «Скіли»: скіл або, на закладці «Дії» (П-155), голе
## уміння. Звідси тягнуть мишею на панель.
##
## Уся робота — віддати дані перетягування. Куди його покладуть і чи
## можна, вирішують комірка панелі й СЕРВЕР: клієнт не має права
## покласти собі скіл, якого не вчив (перевірка в `world.set_slot`).

## Рядок, а не квадратик: назви на кшталт «енергетичний промінь» у
## квадратик 74×74 не влазять і ріжуться посеред слова — перевірено
## знімком. Значок (`assets/icons/skills/`, коли є) стоїть зліва, текст
## — праворуч від нього; немає малюнка — текст займає весь рядок, як і
## раніше.
const WIDE := 236.0
const HIGH := 44.0
const ICON_SIDE := 36.0
const TEXT_X := 8.0
const ICON_TEXT_X := ICON_SIDE + 12.0

var key := ""
var title := ""
var note := ""
## Що летить у чергу дій, коли комірку кинули на панель. Порожнє —
## скіл, і `_get_drag_data` сама додає `Actions.SKILL_PREFIX`.
var _drag_action := ""


## `of_action` — повний код дії без префікса скіла (П-155, закладка
## «Дії»: наприклад «attack»); порожній рядок лишає давню поведінку —
## скіл, узятий з `key`. `of_icon` дає малюнок напряму (голі уміння
## беруть його з `ActionIcons`, не `SkillIcons`). `of_tooltip_extra` —
## додаткові рядки підказки (П-154: тип/вартість/сила/стихія/опис).
func setup(of_key: String, of_title: String, of_note: String,
		of_action := "", of_icon: Texture2D = null,
		of_tooltip_extra := "") -> void:
	key = of_key
	title = of_title
	note = of_note
	_drag_action = of_action
	size = Vector2(WIDE, HIGH)
	custom_minimum_size = size
	# Ловимо мишу: без цього перетягування не почнеться взагалі.
	mouse_filter = Control.MOUSE_FILTER_STOP
	var extra := "\n" + of_tooltip_extra if of_tooltip_extra != "" else ""
	tooltip_text = "%s\n%s%s\nтягни на комірку панелі" % [title, note, extra]

	var plate := ColorRect.new()
	plate.color = Color(0.09, 0.09, 0.11, 0.92)
	plate.size = size
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plate)

	var text_x := TEXT_X
	var tex := of_icon if of_icon != null else SkillIcons.of(of_key)
	if tex != null:
		var icon := TextureRect.new()
		icon.texture = tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.position = Vector2(4, (HIGH - ICON_SIDE) * 0.5)
		icon.size = Vector2(ICON_SIDE, ICON_SIDE)
		icon.custom_minimum_size = icon.size
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(icon)
		text_x = ICON_TEXT_X

	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	label.position = Vector2(text_x, 3)
	label.size = Vector2(WIDE - 8 - text_x, 18)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)

	var under := Label.new()
	under.text = note
	under.add_theme_font_size_override("font_size", 11)
	under.modulate = Color(0.72, 0.75, 0.68)
	under.position = Vector2(text_x, 23)
	under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(under)


func _get_drag_data(_at: Vector2) -> Variant:
	if key == "":
		return null
	var ghost := Label.new()
	ghost.text = title
	ghost.add_theme_font_size_override("font_size", 12)
	ghost.modulate = Color(1, 0.92, 0.7)
	# Тільки під час справжнього перетягування: проба кличе цю саму
	# функцію напряму, і без перевірки Godot сварився б помилкою.
	if get_viewport() != null and get_viewport().gui_is_dragging():
		set_drag_preview(ghost)
	# «звідки» = -1: узяли з вікна, а не з панелі, тож міняти місцями
	# нема з чим.
	var action := _drag_action if _drag_action != "" \
			else Actions.SKILL_PREFIX + key
	return {"дія": action, "звідки": -1}
