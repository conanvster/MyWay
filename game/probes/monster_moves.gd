extends SceneTree
## Парад рухів монстрів: на відміну від людини (`human_moves.gd`), тут
## немає ОДНІЄЇ спільної бібліотеки — у кожної готової моделі свій
## невеликий набір. Тому одиниця тут — пара «вид + рух»: одна фігура на
## кожен рух кожного виду з готовою моделлю, підписана «вид: рух», сама
## грає його по колу. Види без готової моделі (вовк, заєць, ведмідь —
## і досі фігурки з примітивів, П-15) ідуть окремим рядком — стій→іди→бий
## по колу, той самий принцип, що й parade.gd.
##
## Ганяти так:
##     ./run.sh --рухи-монстрів
##
## Esc — вийти, пробіл — знімок, колесо миші — ближче/далі.

const MOB := preload("res://scenes/mob.tscn")
## Моделі, які вже лежать у репозиторії, але ще не заведені видом у
## data/mobs.json — без "kind" `Mob.setup()` їх не підняти, тож ідуть
## окремим шляхом: гола модель, без Creature/AI навколо (05.09.2026,
## замовник попросив показати щойно доданого орка; 05.09.2026 —
## тварини з Farm Animals Pack були вже скопійовані в репозиторій
## раніше цієї сесії, але ніде не показувались, замовник це помітив).
const CREATURES := "res://models/creatures/"
const MONSTERS := "res://models/monsters/"
const EXTRA_PREVIEWS := [
	{"title": "орк (ще не в грі)", "path": MONSTERS + "Orc.glb"},
	{"title": "корова (ще не в грі)", "path": CREATURES + "Cow.fbx"},
	{"title": "кінь (ще не в грі)", "path": CREATURES + "Horse.fbx"},
	{"title": "лама (ще не в грі)", "path": CREATURES + "Llama.fbx"},
	{"title": "мопс (ще не в грі)", "path": CREATURES + "Pug.fbx"},
	{"title": "вівця (ще не в грі)", "path": CREATURES + "Sheep.fbx"},
	{"title": "зебра (ще не в грі)", "path": CREATURES + "Zebra.fbx"},
]
const COLUMNS := 6
const STEP_X := 2.6
const STEP_Z := 3.4
const LABEL_HEIGHT := 1.55
const ZOOM_STEP := 2.0
const ZOOM_MIN := 5.0
const CYCLE := 4.0          ## для фігурок-примітивів: секунд на стій→іди→бий
const WALK_SPEED := 3.0


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


func _go() -> void:
	await process_frame
	var data := GameData.new()
	data.load_all()

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

	# Ряд 1: пари «вид+рух» для тих, у кого є готова модель.
	var slots: Array = []   # {kind, title, move, opis}
	var kinds: Array = []
	for key in data.mobs:
		kinds.append(int(key))
	kinds.sort()

	for kind: int in kinds:
		var row: Dictionary = data.for_kind(kind)
		var made: String = str(row.get("вигляд", {}).get("модель", ""))
		var title: String = str(row.get("назва", str(kind)))
		if made == "" or not ResourceLoader.exists(made):
			slots.append({"kind": kind, "title": title, "move": "",
					"opis": "фігурка з примітивів"})
			continue
		var scene: PackedScene = load(made)
		var probe: Node3D = scene.instantiate()
		var player: AnimationPlayer = \
				probe.find_child("AnimationPlayer", true, false)
		var moves: Array = []
		if player != null:
			moves = Array(player.get_animation_list())
		probe.queue_free()
		if moves.is_empty():
			# Готова модель є, вбудованих рухів немає (П-120: Imp/Puglin)
			# — гойдає кістками сама, не примітивна фігурка.
			slots.append({"kind": kind, "title": title, "move": "",
					"opis": "готова модель, гойдання кістками (немає рухів)"})
			continue
		moves.sort()
		for m: String in moves:
			slots.append({"kind": kind, "title": title, "move": m, "opis": ""})

	# Ряд 2: щойно завантажені моделі, ще без "kind" у даних (П-15).
	for extra: Dictionary in EXTRA_PREVIEWS:
		var path: String = extra["path"]
		if not ResourceLoader.exists(path):
			continue
		var scene: PackedScene = load(path)
		var probe: Node3D = scene.instantiate()
		var player: AnimationPlayer = \
				probe.find_child("AnimationPlayer", true, false)
		var moves: Array = []
		if player != null:
			moves = Array(player.get_animation_list())
		probe.queue_free()
		moves.sort()
		for m: String in moves:
			slots.append({"kind": -1, "title": extra["title"], "move": m,
					"opis": "", "extra_path": path})

	var ground := MeshInstance3D.new()
	var plate := BoxMesh.new()
	var rows := ceili(float(slots.size()) / COLUMNS)
	plate.size = Vector3(COLUMNS * STEP_X + 6.0, 1, rows * STEP_Z + 6.0)
	ground.mesh = plate
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("#4a5c3a")
	ground.set_surface_override_material(0, paint)
	ground.position = Vector3(0, -0.5, 0)
	world.add_child(ground)

	var from_x := -STEP_X * (COLUMNS - 1) * 0.5
	var from_z := -STEP_Z * (rows - 1) * 0.5
	var lineup: Array = []
	for i in slots.size():
		var slot: Dictionary = slots[i]
		var col := i % COLUMNS
		var at_row := i / COLUMNS
		var at := Vector3(from_x + col * STEP_X, 0.0, from_z + at_row * STEP_Z)

		var mob: Node3D
		var body: Node3D
		if slot.has("extra_path"):
			# Гола модель, без Mob/Creature навколо — ще не kind, нема
			# чим setup() годувати.
			mob = Node3D.new()
			world.add_child(mob)
			body = load(slot["extra_path"]).instantiate()
			mob.add_child(body)
			mob.position = at
		else:
			mob = MOB.instantiate()
			world.add_child(mob)
			mob.setup(Vector3.ZERO, slot["kind"], false,
					data.for_kind(slot["kind"]))
			mob.place_at(at, 0.0)
			body = mob.model()
		await process_frame

		var label_text: String
		if slot["move"] == "":
			label_text = "%s (%s)" % [slot["title"], slot["opis"]]
		else:
			label_text = "%s: %s" % [slot["title"], slot["move"]]
			var player: AnimationPlayer = \
					body.find_child("AnimationPlayer", true, false) if body != null \
					else null
			if player != null and player.has_animation(slot["move"]):
				player.get_animation(slot["move"]).loop_mode = \
						Animation.LOOP_LINEAR
				player.play(slot["move"])

		var tag := Label3D.new()
		tag.text = label_text
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.font_size = 40
		tag.outline_size = 12
		tag.outline_modulate = Color(0, 0, 0, 0.9)
		tag.pixel_size = 0.0055
		tag.position = at + Vector3(0, LABEL_HEIGHT, 0)
		world.add_child(tag)

		print("  %-28s %s" % [slot["title"],
				slot["move"] if slot["move"] != "" else "(%s)" % slot["opis"]])
		lineup.append({"mob": mob, "at": at, "primitive": slot["move"] == "",
				"swung": false})

	var catcher := InputCatcher.new()
	world.add_child(catcher)

	var full_radius: float = maxf(COLUMNS * STEP_X, rows * STEP_Z) * 0.9 + 8.0
	var radius: float = ZOOM_MIN + 7.0
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
	print("  %d пар «вид+рух», %d видів усього"
			% [lineup.size(), kinds.size()])
	root.close_requested.connect(quit)
	var angle := 0.0
	var shot_held := false
	var clock := 0.0
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
		clock += delta
		for i in lineup.size():
			var row: Dictionary = lineup[i]
			if not row["primitive"]:
				continue
			var mob: Node3D = row["mob"]
			var model: Node3D = mob.model()
			if model == null:
				continue
			var phase := fmod(clock + i * 0.5, CYCLE) / CYCLE
			if phase < 0.35:
				model.animate(0.0)
				mob.place_at(row["at"], 0.0)
				row["swung"] = false
			elif phase < 0.75:
				model.animate(WALK_SPEED)
				var walk := sin((phase - 0.35) / 0.4 * PI) * 1.2
				mob.place_at(row["at"] + Vector3(0, 0, walk), 0.0)
			else:
				model.animate(0.0)
				if not row["swung"]:
					model.swing()
					row["swung"] = true
	quit()
