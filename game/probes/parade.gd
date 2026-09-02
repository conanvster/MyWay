extends SceneTree
## Парад істот: усі види в ряд, щоб бачити, хто на кого схожий.
##
## Ганяти БЕЗ --headless, інакше нема чого знімати:
##     godot --path game --script res://probes/parade.gd
##
## Знімок лягає в user://; шлях друкується.

const MOB := preload("res://scenes/mob.tscn")


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
	for i in kinds.size():
		var mob: Node3D = MOB.instantiate()
		world.add_child(mob)
		await process_frame
		mob.setup(Vector3.ZERO, kinds[i], false, data.for_kind(kinds[i]))
		mob.place_at(Vector3(from + i * step, 0.0, 0.0), PI)
		print("  %2d %-10s %s" % [kinds[i],
				data.for_kind(kinds[i]).get("назва", "?"),
				data.for_kind(kinds[i]).get("вигляд", {}).get("модель",
						"фігурка з примітивів")])

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
	await process_frame
	await process_frame
	quit()
