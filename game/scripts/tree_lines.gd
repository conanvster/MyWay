class_name TreeLines
extends Control
## Лінії передумов у дереві скілів (П-150).
##
## `Line2D` — вузол 2D, не Control: усередині вікна це означало б інший
## відлік координат і своя система шарів. Простіше самим намалювати
## відрізки в `_draw()` — той самий `CanvasItem`, що й решта вікна.

## Кожен запис: {"a": Vector2, "b": Vector2, "color": Color}.
var segments: Array = []


func _draw() -> void:
	for seg: Dictionary in segments:
		draw_line(seg["a"], seg["b"], seg["color"], 2.0, true)


func set_segments(list: Array) -> void:
	segments = list
	queue_redraw()
