extends SceneTree
## Парад щойно завантажених персонажів (05.09.2026): RPG Character Pack
## (6 класів) + Ultimate Animated Character Pack (50 людей/тварин) —
## жоден із них ще НЕ скопійований у репозиторій (разом 112 МБ, зашироко
## для «лише потрібні файли», П-15). Читає напряму з `~/assets/` через
## `GLTFDocument` — офіційний спосіб завантажити glTF поза `res://` без
## імпорту в проєкт.
##
## Одна постать = один файл (різні персонажі, не один спільний набір
## рухів, як у людини-гравця) — кожна сама по колу програє ВЕСЬ свій
## список рухів, підпис показує, який зараз.
##
## Ганяти так:
##     ./run.sh --нові-моделі
##
## Esc — вийти, пробіл — знімок, колесо миші — ближче/далі.

const RPG_DIR := "/home/alex/assets/rpg-characters"
const ULTIMATE_DIR := "/home/alex/assets/ultimate-characters"
const COLUMNS := 8
const STEP_X := 2.4
const STEP_Z := 3.2
const LABEL_HEIGHT := 2.1
const ZOOM_STEP := 2.0
const ZOOM_MIN := 6.0
## Секунд на кожен рух, перш ніж перемкнутись на наступний.
const MOVE_HOLD := 2.5


class InputCatcher extends Node:
	var zoom := 0.0

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				zoom -= ZOOM_STEP
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				zoom += ZOOM_STEP


func _init() -> void:
	call_deferred("_go")


## Завантажити .gltf поза res:// — GLTFDocument, не load().
func _load_external(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		return null
	return doc.generate_scene(state)


func _go() -> void:
	await process_frame

	var world := Node3D.new()
	root.add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.light_energy = 1.2
	world.add_child(sun)
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var air := Environment.new()
	air.background_mode = Environment.BG_SKY
	air.sky = sky
	air.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	air.ambient_light_energy = 1.2
	var holder := WorldEnvironment.new()
	holder.environment = air
	world.add_child(holder)

	var files: Array = []
	for dir_path in [RPG_DIR, ULTIMATE_DIR]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			print("‼ немає теки: ", dir_path)
			continue
		var names := dir.get_files()
		names.sort()
		for f: String in names:
			if f.get_extension() == "gltf":
				files.append(dir_path + "/" + f)

	print("файлів знайдено: %d" % files.size())

	var ground := MeshInstance3D.new()
	var plate := BoxMesh.new()
	var rows := ceili(float(files.size()) / COLUMNS)
	plate.size = Vector3(COLUMNS * STEP_X + 6.0, 1, rows * STEP_Z + 6.0)
	ground.mesh = plate
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("#4a5c3a")
	ground.set_surface_override_material(0, paint)
	ground.position = Vector3(0, -0.5, 0)
	world.add_child(ground)

	var from_x := -STEP_X * (COLUMNS - 1) * 0.5
	var from_z := -STEP_Z * (rows - 1) * 0.5
	var lineup: Array = []   # {body, player, moves, tag, at, phase}

	for i in files.size():
		var path: String = files[i]
		var title: String = path.get_file().get_basename()
		var body := _load_external(path)
		if body == null:
			print("  ‼ не завантажилось: ", path)
			continue
		var col := i % COLUMNS
		var at_row := i / COLUMNS
		var at := Vector3(from_x + col * STEP_X, 0.0, from_z + at_row * STEP_Z)
		world.add_child(body)
		body.position = at
		await process_frame

		var player: AnimationPlayer = \
				body.find_child("AnimationPlayer", true, false)
		var moves: Array = []
		if player != null:
			moves = Array(player.get_animation_list())
			moves.sort()

		var tag := Label3D.new()
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.font_size = 36
		tag.outline_size = 12
		tag.outline_modulate = Color(0, 0, 0, 0.9)
		tag.pixel_size = 0.0055
		tag.position = at + Vector3(0, LABEL_HEIGHT, 0)
		world.add_child(tag)

		print("  %-24s рухів %d: %s" % [title, moves.size(), moves])
		lineup.append({"body": body, "player": player, "moves": moves,
				"tag": tag, "title": title, "phase": 0.0, "shown": -1})

	var catcher := InputCatcher.new()
	world.add_child(catcher)

	var full_radius: float = maxf(COLUMNS * STEP_X, rows * STEP_Z) * 0.9 + 8.0
	var radius: float = ZOOM_MIN + 8.0
	var height: float = radius * 0.55
	var eye := Camera3D.new()
	eye.fov = 70
	world.add_child(eye)
	eye.current = true
	eye.position = Vector3(0, height, radius)
	eye.look_at(Vector3(0, 1.0, 0))

	for i in 8:
		await process_frame
	Shot.take(world)

	print("\n  Esc — вийти · пробіл — знімок · колесо — ближче/далі")
	print("  %d персонажів, кожен сам по колу програє свої рухи"
			% lineup.size())
	root.close_requested.connect(quit)
	var angle := 0.0
	var shot_held := false
	var last := Time.get_ticks_msec() / 1000.0
	while true:
		await process_frame
		if Input.is_key_pressed(KEY_ESCAPE):
			break
		if Input.is_key_pressed(KEY_SPACE):
			if not shot_held:
				Shot.take(world)
			shot_held = true
		else:
			shot_held = false
		if catcher.zoom != 0.0:
			radius = clampf(radius + catcher.zoom, ZOOM_MIN, full_radius * 1.6)
			height = radius * 0.55
			catcher.zoom = 0.0
		angle += 0.0025
		eye.position = Vector3(sin(angle) * radius, height,
				cos(angle) * radius)
		eye.look_at(Vector3(0, 1.0, 0))

		var now := Time.get_ticks_msec() / 1000.0
		var delta := now - last
		last = now
		for row: Dictionary in lineup:
			if row["moves"].is_empty():
				continue
			row["phase"] += delta
			var at_index: int = int(row["phase"] / MOVE_HOLD) \
					% row["moves"].size()
			if at_index != row["shown"]:
				row["shown"] = at_index
				var name: String = row["moves"][at_index]
				var player: AnimationPlayer = row["player"]
				if player.has_animation(name):
					player.get_animation(name).loop_mode = \
						Animation.LOOP_LINEAR
					player.play(name)
				row["tag"].text = "%s: %s" % [row["title"], name]
	quit()
