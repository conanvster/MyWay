extends Node
## Хутро шарами (`scripts/fur_shell.gdshader`) на власній моделі — знімками,
## без світу, мережі й сервера (слово замовника 23.09.2026 про зайця:
## «навіть хутро не промальовується, не бачу волосинок»).
##
##     godot --path game res://scenes/fur_look.tscn -- --знімок <основа>
##
## Три знімки: `<основа>-поруч.png` — той самий вид без хутра (ліворуч) і
## з хутром (праворуч) у стійці Idle; `<основа>-зблизька.png` — ворс
## упритул; `<основа>-вікі.png` — квадрат 1024 з одним хутряним звіром
## збоку, готовий у `wiki/img/monstry/<назва>-модель.png`. Вид і хутро —
## з `data/mobs.json`, як у грі. Інший вид: `-- --вид <назва>`.

const KIND := "заєць"      ## типово, якщо не дали `--вид`


func _ready() -> void:
	_go()


func _go() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var kind_at := args.find("--вид")
	var kind := args[kind_at + 1] if kind_at >= 0 \
			and kind_at + 1 < args.size() else KIND
	var look := _look(kind)
	if look.is_empty():
		print("‼ немає виду «%s» у data/mobs.json" % kind)
		get_tree().quit(1)
		return
	var world := Node3D.new()
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	world.add_child(sun)
	var air := Environment.new()
	air.background_mode = Environment.BG_COLOR
	air.background_color = Color(0.36, 0.4, 0.44)
	air.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	air.ambient_light_color = Color(0.7, 0.72, 0.75)
	air.ambient_light_energy = 0.6
	air.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var holder := WorldEnvironment.new()
	holder.environment = air
	world.add_child(holder)

	var size := float(look.get("зріст", 1.0))
	var bare: Node3D = null
	var furry: Node3D = null
	for i in 2:
		var skin := SkinnedModel.new()
		skin.path = str(look.get("модель", ""))
		skin.height = size
		if i == 1:
			skin.fur = look.get("хутро", {})
		world.add_child(skin)
		skin.build()
		skin.position = Vector3((i - 0.5) * size * 1.3, 0, 0)
		skin.rotation_degrees.y = 60
		if i == 0:
			bare = skin
		else:
			furry = skin

	var eye := Camera3D.new()
	eye.fov = 35
	world.add_child(eye)
	eye.current = true
	get_window().size = Vector2i(1920, 1080)
	var at := args.find("--знімок")
	var stem := args[at + 1] if at >= 0 and at + 1 < args.size() \
			else "user://хутро"
	var ok := true
	eye.position = Vector3(0, size * 0.7, size * 2.6)
	eye.look_at(Vector3(0, size * 0.35, 0))
	ok = await _shot(stem + "-поруч.png") and ok
	eye.position = Vector3(size * 0.65 + size * 0.35, size * 0.55, size * 0.6)
	eye.look_at(Vector3(size * 0.65, size * 0.5, 0))
	ok = await _shot(stem + "-зблизька.png") and ok
	# Вікі: лише хутряний, строго збоку, квадрат.
	bare.visible = false
	furry.rotation_degrees.y = 90
	get_window().size = Vector2i(1024, 1024)
	var middle := Vector3(size * 0.65, size * 0.5, 0)
	eye.position = middle + Vector3(0, size * 0.05, size * 2.4)
	eye.look_at(middle)
	ok = await _shot(stem + "-вікі.png") and ok
	get_tree().quit(0 if ok else 1)


func _shot(path: String) -> bool:
	for f in 30:
		await get_tree().process_frame
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("[знімок] %s%s" % [path, "" if err == OK
			else " ‼ " + error_string(err)])
	return err == OK


func _look(kind: String) -> Dictionary:
	var data: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/mobs.json"))
	for key in data:
		var row = data[key]
		if row is Dictionary and str(row.get("назва", "")) == kind:
			return row.get("вигляд", {})
	return {}
