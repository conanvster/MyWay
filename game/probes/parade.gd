extends SceneTree
## Парад істот: усі види в ряд, щоб бачити, хто на кого схожий.
##
## Ганяти так:
##     ./run.sh --парад
##
## Вікно лишається відкритим, камера сама обходить ряд. Esc — вийти,
## пробіл — ще один знімок.
##
## Кожна істота сама по колу стоїть → йде → б'є (П-150): без цього
## парад лише ряд поз спокою, а саме рух і показує, чи набір із
## анімаціями (`SkinnedModel._play_if_has`), чи без них (гойдання
## кістками) — на місці все виглядає однаково.
##
## Знімок лягає в user://; шлях друкується.

const MOB := preload("res://scenes/mob.tscn")
## Секунд на повне коло стій-іди-вдар; зсунуте на істоту, щоб рухались
## не строєм, а кожна своїм ритмом — так парад читається, а не блимає.
const CYCLE := 4.0
const WALK_SPEED := 3.0


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	var data := GameData.new()
	data.load_all()

	var world := Node3D.new()
	root.add_child(world)

	# Земля, щоб істоти не висіли в порожнечі.
	var ground := MeshInstance3D.new()
	var plate := BoxMesh.new()
	plate.size = Vector3(60, 1, 20)
	ground.mesh = plate
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("#4a5c3a")
	ground.set_surface_override_material(0, paint)
	ground.position = Vector3(0, -0.5, 0)
	world.add_child(ground)

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

	var kinds: Array = []
	for key in data.mobs:
		kinds.append(int(key))
	kinds.sort()

	var step := 3.4
	var from := -step * (kinds.size() - 1) * 0.5
	# Кожен запис: mob, model, at (позиція в ряду), swung (чи вже
	# вдарив у цьому колі).
	var parade: Array = []
	for i in kinds.size():
		var mob: Node3D = MOB.instantiate()
		world.add_child(mob)
		await process_frame
		mob.setup(Vector3.ZERO, kinds[i], false, data.for_kind(kinds[i]))
		var at := Vector3(from + i * step, 0.0, 0.0)
		mob.place_at(at, PI)
		print("  %2d %-10s %s" % [kinds[i],
				data.for_kind(kinds[i]).get("назва", "?"),
				data.for_kind(kinds[i]).get("вигляд", {}).get("модель",
						"фігурка з примітивів")])
		parade.append({"mob": mob, "model": mob.model(), "at": at,
				"swung": false})

	var eye := Camera3D.new()
	eye.position = Vector3(0, 3.4, 15.0)
	eye.rotation_degrees = Vector3(-9, 0, 0)
	eye.fov = 62
	world.add_child(eye)
	eye.current = true

	# Двом кадрам треба дати намалюватись, інакше моделі ще без поз.
	for i in 8:
		await process_frame
	Shot.take(world)

	# Далі вікно лишається відкритим: парад для того й потрібен, щоб на
	# істот ДИВИТИСЯ. Камера повільно обходить ряд; вийти — Esc або
	# хрестик, знімок — пробіл.
	print("\n  Esc — вийти · пробіл — знімок · камера обходить сама")
	print("  кожна істота сама: стоїть → йде → б'є, по колу %.0f с" % CYCLE)
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
		angle += 0.0035
		var far := 17.0
		eye.position = Vector3(sin(angle) * far, 3.6, cos(angle) * far)
		eye.look_at(Vector3(0, 1.0, 0))

		var now := Time.get_ticks_msec() / 1000.0
		var delta := now - last
		last = now
		clock += delta
		for i in parade.size():
			var row: Dictionary = parade[i]
			var model = row["model"]
			if model == null:
				continue
			var mob: Node3D = row["mob"]
			var phase := fmod(clock + i * 0.6, CYCLE) / CYCLE
			if phase < 0.35:
				model.animate(0.0)
				mob.place_at(row["at"], PI)
				row["swung"] = false
			elif phase < 0.75:
				model.animate(WALK_SPEED)
				# Крок уперед-назад: сам рух і вмикає ходу в статі
				# (`_speed` рахує саме зміщення, не намір).
				var walk := sin((phase - 0.35) / 0.4 * PI) * 1.2
				mob.place_at(row["at"] + Vector3(0, 0, walk), PI)
			else:
				model.animate(0.0)
				if not row["swung"]:
					model.swing()
					row["swung"] = true
	quit()
