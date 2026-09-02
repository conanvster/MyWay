class_name Shot
extends RefCounted
## Знімок екрана зсередини Godot.
##
## Потрібен і грі (F12), і стартовій сторінці, тож живе окремо. Знімати
## можна лише ПІСЛЯ того, як кадр намальовано, інакше в текстурі
## порожнеча — звідси одноразове під'єднання до `frame_post_draw`.
##
## Зовнішні знімалки під цим композитором не працюють: `grim` каже
## «compositor doesn't support wlr-screencopy».
##
## Без вікна знімати нічого: `frame_post_draw` там не настає ніколи, тож
## одноразове під'єднання не знімається, а наступний виклик натикається на
## «Signal is already connected». У безвіконній перевірці бою цей рядок
## сипався щокадру й ховав усе інше — тому мовчки виходимо.

static func take(from: Node) -> void:
	if DisplayServer.get_name() == "headless":
		return
	RenderingServer.frame_post_draw.connect(_save.bind(from),
			CONNECT_ONE_SHOT)


static func _save(from: Node) -> void:
	if not is_instance_valid(from):
		return
	var image := from.get_viewport().get_texture().get_image()
	var path := "user://знімок-%s.png" % Time.get_datetime_string_from_system(
			false, true).replace(":", "-").replace(" ", "_")
	var err := image.save_png(path)
	if err != OK:
		push_error("[знімок] не зберігся: %s" % error_string(err))
		print("[знімок] ‼ не зберігся: %s" % error_string(err))
		return
	print("[знімок] ", ProjectSettings.globalize_path(path))
