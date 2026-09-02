class_name BarCell
extends Control
## Одна комірка панелі 1–7: приймає скіл, який на неї тягнуть, і сама
## дає себе перетягнути — так дві комірки міняються місцями.
##
## Натиск теж тут: відколи комірка ловить мишу, клік по ній мусить щось
## робити, інакше панель виглядає зламаною.

## Кинули щось на цю комірку: куди, що, і звідки взяли (-1 — з вікна).
signal dropped(where: int, action: String, from: int)
## Клацнули по комірці — застосувати те, що в ній.
signal pressed(where: int)

var slot := 0
var action := ""


func setup(of_slot: int, side: float) -> void:
	slot = of_slot
	size = Vector2(side, side)
	custom_minimum_size = size
	mouse_filter = Control.MOUSE_FILTER_STOP


func _get_drag_data(_at: Vector2) -> Variant:
	if action == "":
		return null
	var ghost := Label.new()
	ghost.text = action
	ghost.add_theme_font_size_override("font_size", 12)
	ghost.modulate = Color(1, 0.92, 0.7)
	# Тільки під час справжнього перетягування: проба кличе цю саму
	# функцію напряму, і без перевірки Godot сварився б помилкою.
	if get_viewport() != null and get_viewport().gui_is_dragging():
		set_drag_preview(ghost)
	return {"дія": action, "звідки": slot}


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("дія")


func _drop_data(_at: Vector2, data: Variant) -> void:
	dropped.emit(slot, str(data["дія"]), int(data.get("звідки", -1)))


## Клік по комірці. Беремо ВІДПУСКАННЯ, а не натиск: натиском
## починається перетягування, і на ньому дія спрацьовувала б щоразу, коли
## комірку просто тягнуть.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(slot)
