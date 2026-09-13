extends Node
## Як виглядає активована святиня з порталом і помітка вибору — одним
## знімком, без світу, мережі й сервера (П-190, слово замовника 13.09.2026:
## «портала візуально не побачив… підсвіти його красиво, в кольорі
## грейду», «потрібно додати маркер, щоб розумів, кого вибрав»).
##
## Без `main.tscn` навмисно: той підключається до сервера на 127.0.0.1, і
## якщо замовник саме грає — проба стукала б у його гру.
##
##     godot --path game res://scenes/portal_look.tscn -- --знімок <файл.png>
##
## Два кадри поруч: святиня грейду E (сірий — найблідший колір шкали) і C
## (зелений), обидві активовані, над E — помітка вибору.

const GROUND := Color("#4a5c3a")


func _ready() -> void:
	_go()


func _go() -> void:
	await get_tree().process_frame
	var world := Node3D.new()
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 0.6
	world.add_child(sun)
	var air := Environment.new()
	air.background_mode = Environment.BG_COLOR
	air.background_color = Color(0.25, 0.3, 0.35)
	air.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	air.ambient_light_color = Color(0.6, 0.62, 0.65)
	air.ambient_light_energy = 0.5
	air.glow_enabled = true
	air.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var holder := WorldEnvironment.new()
	holder.environment = air
	world.add_child(holder)

	var ground := MeshInstance3D.new()
	var plate := PlaneMesh.new()
	plate.size = Vector2(80, 80)
	ground.mesh = plate
	var paint := StandardMaterial3D.new()
	paint.albedo_color = GROUND
	ground.material_override = paint
	world.add_child(ground)

	var marked: Shrine = null
	for i in 2:
		var shrine := Shrine.new()
		shrine.form = "обеліск"
		shrine.grade = "E" if i == 0 else "C"
		world.add_child(shrine)
		shrine.position = Vector3(-9.0 + i * 18.0, 0.0, 0.0)
		shrine.set_stage(Shrine.Stage.АКТИВОВАНА)
		if i == 0:
			marked = shrine
	SelectMark.put(marked, 2.2, 4.2)

	# Камера гри: згори під ~50°, як `camera_rig.gd`.
	var eye := Camera3D.new()
	eye.fov = 60
	world.add_child(eye)
	eye.current = true
	eye.position = Vector3(0.0, 17.0, 17.0)
	eye.look_at(Vector3(0.0, 1.5, 1.5))

	get_window().size = Vector2i(1280, 720)
	for f in 90:
		await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var at := args.find("--знімок")
	var path := args[at + 1] if at >= 0 and at + 1 < args.size() \
			else "user://портал.png"
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("[знімок] %s%s" % [path, "" if err == OK
			else " ‼ " + error_string(err)])
	get_tree().quit(0 if err == OK else 1)
