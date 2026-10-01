extends SceneTree
## Проба скопійованих моделей (П-248): 183 види на чужій моделі — у грі,
## справжньою сценою монстра, з їхнім зростом.
##
## Ганяти так:
##     godot --path game --script res://probes/kopii.gd
##     godot --headless --path game --script res://probes/kopii.gd  (лише числа)
##
## Що міряє на кожному виді (P2 — числа, не «на око»):
##   - висоту сітки в позі спокою проти `вигляд.зріст` із даних;
##   - де ноги: найнижча точка сітки має бути на землі (|y| ≤ 10 %
##     зросту), а не під нею й не в повітрі;
##   - чи модель узагалі завантажилась (сітка є).
## З вікном — ще аркуші знімків по 12 видів, від нижчих до вищих, з
## підписами: подивитись, чи не стоїть королева зимових міражів
## гнолом-мисливцем у три метри так, що це смішно.

const MOB := preload("res://scenes/mob.tscn")
const OWN := "res://models/own/"
const PER_SHEET := 12
## Скільки відхилення терпимо. Зріст підганяє `SkinnedModel._fit` за
## власною висотою моделі, тож різниця — це те, що змінила поза чи хутро.
const HEIGHT_SLACK := 0.15
const FEET_SLACK := 0.10

var _bad := 0


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	# Заблокований екран Wayland тримає синхронізацію на 1 кадр/с — без
	# цього аркуш знімався б хвилинами.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await process_frame
	var data := GameData.new()
	data.load_all()
	var world := Node3D.new()
	root.add_child(world)
	_stage(world)

	var kinds: Array = []
	for key in data.mobs:
		if not str(key).is_valid_int():
			continue
		var row: Dictionary = data.for_kind(int(key))
		var path: String = str(row.get("вигляд", {}).get("модель", ""))
		var own: String = OWN + str(row.get("назва", "")) + ".glb"
		# Скопійована — своя тека, але чужий файл. Набірні (Dragon, Slime)
		# теж чужі, якщо вид не дракон і не слиз.
		if path != "" and path != own and not (path.begins_with(OWN)
				and data.for_kind(int(key)).get("шаблон", false)):
			if path.get_file().get_basename() != str(row.get("назва", "")):
				kinds.append(int(key))
	print("— скопійовані моделі: %d —" % kinds.size())

	var rows: Array = []
	for kind: int in kinds:
		var row: Dictionary = data.for_kind(kind)
		var mob: Node3D = MOB.instantiate()
		world.add_child(mob)
		await process_frame
		mob.setup(Vector3.ZERO, kind, false, row)
		# Вузол монстра — центр капсули; земля в нього на `foot_drop`
		# нижче. Так і ставимо: ноги мають стати рівно на y = 0.
		mob.place_at(Vector3(0, mob.foot_drop(), 0), PI)
		await process_frame
		var box := _box(mob)
		var want: float = float(row.get("вигляд", {}).get("зріст", 1.0))
		var line := {"вид": kind, "назва": str(row.get("назва", "?")),
				"модель": str(row["вигляд"]["модель"]).get_file().get_basename(),
				"зріст": want, "mob": mob}
		var why := PackedStringArray()
		if box.size == Vector3.ZERO:
			why.append("сітки немає")
		else:
			line["висота"] = box.size.y
			line["ноги"] = box.position.y
			if absf(box.size.y - want) > want * HEIGHT_SLACK:
				why.append("висота %.2f м замість %.2f" % [box.size.y, want])
			if absf(box.position.y) > want * FEET_SLACK:
				why.append("ноги на %+.2f м" % box.position.y)
		line["вади"] = why
		if not why.is_empty():
			_bad += 1
		rows.append(line)
		mob.visible = false

	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["зріст"]) < float(b["зріст"]))
	for line: Dictionary in rows:
		print("  %3d %-38s ← %-24s зріст %.2f  висота %s  ноги %s%s" % [
				line["вид"], line["назва"], line["модель"], line["зріст"],
				"%.2f" % line["висота"] if line.has("висота") else "—",
				"%+.2f" % line["ноги"] if line.has("ноги") else "—",
				"  ‼ " + ", ".join(line["вади"]) if not line["вади"].is_empty()
						else ""])
	print("\nвидів із вадами: %d із %d" % [_bad, rows.size()])

	if DisplayServer.get_name() != "headless":
		await _sheets(world, rows)
	quit()


## Охоплення всіх сіток істоти у світових осях.
func _box(who: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for child in who.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = child
		if not mesh.is_visible_in_tree() or mesh.mesh == null:
			continue
		var one: AABB = mesh.global_transform * mesh.get_aabb()
		box = one if first else box.merge(one)
		first = false
	return box


func _stage(world: Node3D) -> void:
	var ground := MeshInstance3D.new()
	var plate := BoxMesh.new()
	plate.size = Vector3(200, 1, 60)
	ground.mesh = plate
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("#4a5c3a")
	ground.set_surface_override_material(0, paint)
	ground.position = Vector3(0, -0.5, 0)
	world.add_child(ground)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	sun.light_energy = 1.3
	world.add_child(sun)
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var air := Environment.new()
	air.background_mode = Environment.BG_SKY
	air.sky = sky
	air.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	air.ambient_light_energy = 1.3
	var holder := WorldEnvironment.new()
	holder.environment = air
	world.add_child(holder)


## Аркуші: по 12 видів у ряд, від нижчих до вищих. Поруч із кожним —
## людина-мірка 1,8 м (сірий стовп), щоб зріст читався без цифр.
func _sheets(world: Node3D, rows: Array) -> void:
	var eye := Camera3D.new()
	eye.fov = 50
	world.add_child(eye)
	eye.current = true
	var marks: Array = []
	var sheet := 0
	for from in range(0, rows.size(), PER_SHEET):
		for node: Node in marks:
			node.queue_free()
		marks.clear()
		var chunk: Array = rows.slice(from, from + PER_SHEET)
		var tallest := 1.8
		for line: Dictionary in chunk:
			tallest = maxf(tallest, float(line["зріст"]))
		var step := maxf(1.6, tallest * 0.75)
		var left := -step * (chunk.size() - 1) * 0.5
		for i in chunk.size():
			var line: Dictionary = chunk[i]
			var mob: Node3D = line["mob"]
			mob.visible = true
			mob.place_at(Vector3(left + i * step, mob.foot_drop(), 0), PI - 0.4)
			var tag := Label3D.new()
			tag.text = "%s\n← %s\n%.1f м" % [line["назва"], line["модель"],
					line["зріст"]]
			tag.font_size = 40
			tag.pixel_size = 0.0055 * maxf(1.0, step / 1.6)
			tag.outline_size = 10
			tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			# Підписи над головами, сходинкою: сусідні не налазять.
			tag.position = Vector3(left + i * step,
					tallest * (1.12 + 0.22 * (i % 2)), 0)
			if not line["вади"].is_empty():
				tag.modulate = Color(1, 0.5, 0.4)
			world.add_child(tag)
			marks.append(tag)
		var ruler := MeshInstance3D.new()
		var stick := BoxMesh.new()
		stick.size = Vector3(0.12, 1.8, 0.12)
		ruler.mesh = stick
		ruler.position = Vector3(left - step * 0.6, 0.9, 0)
		world.add_child(ruler)
		marks.append(ruler)
		var wide := step * chunk.size() + step
		var far := maxf(wide * 0.62, tallest * 2.0)
		eye.position = Vector3(0, tallest * 0.7, far)
		eye.look_at(Vector3(0, tallest * 0.65, 0))
		for i in 10:
			await process_frame
		sheet += 1
		print("[аркуш %d] %d–%d" % [sheet, from + 1, from + chunk.size()])
		# Свої імена й своя тека: `Shot` іменує знімок секундою, і
		# паралельний `check.sh` затирав аркуші своїми кадрами.
		await RenderingServer.frame_post_draw
		var image := world.get_viewport().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(
				ProjectSettings.globalize_path("user://kopii"))
		var path := "user://kopii/аркуш-%02d.png" % sheet
		image.save_png(path)
		print("[знімок] ", ProjectSettings.globalize_path(path))
		for line: Dictionary in chunk:
			line["mob"].visible = false
