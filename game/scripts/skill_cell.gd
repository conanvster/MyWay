class_name SkillCell
extends Control
## Один скіл у вікні «Скіли». Звідси його тягнуть мишею на панель.
##
## Уся робота — віддати дані перетягування. Куди його покладуть і чи
## можна, вирішують комірка панелі й СЕРВЕР: клієнт не має права
## покласти собі скіл, якого не вчив (перевірка в `world.set_slot`).

## Рядок, а не квадратик: назви на кшталт «енергетичний промінь» у
## квадратик 74×74 не влазять і ріжуться посеред слова — перевірено
## знімком. Іконок у нас немає, тож читабельність важить більше за вигляд.
const WIDE := 236.0
const HIGH := 44.0

var key := ""
var title := ""
var note := ""


func setup(of_key: String, of_title: String, of_note: String) -> void:
	key = of_key
	title = of_title
	note = of_note
	size = Vector2(WIDE, HIGH)
	custom_minimum_size = size
	# Ловимо мишу: без цього перетягування не почнеться взагалі.
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "%s\n%s\nтягни на комірку панелі" % [title, note]

	var plate := ColorRect.new()
	plate.color = Color(0.09, 0.09, 0.11, 0.92)
	plate.size = size
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plate)

	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	label.position = Vector2(8, 3)
	label.size = Vector2(WIDE - 16, 18)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)

	var under := Label.new()
	under.text = note
	under.add_theme_font_size_override("font_size", 11)
	under.modulate = Color(0.72, 0.75, 0.68)
	under.position = Vector2(8, 23)
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
	return {"дія": Actions.SKILL_PREFIX + key, "звідки": -1}
