extends Node
## Зброя в руках (11.10.2026): сім людей у ряд, у кожного свій тип.
##
##     godot --path game res://scenes/held.tscn
##
## Лише з вікном — це знімок для ока: як річ лягла в кисть. Числами —
## що тримання з'явилось на потрібній кістці й зникає, коли зняли.

const AVATAR := preload("res://scenes/avatar.tscn")
const ROW := [["меч з кори дуба", "щит з кори дуба"], ["залізний кинджал", ""],
		["сталева сокира", ""], ["кістяний спис", ""], ["посох з кори дуба", ""],
		["ясеновий лук", ""], ["сталевий меч", "сталевий щит"]]
var _bad := 0


func _ready() -> void:
	_go()


func _expect(what: String, got: Variant, want: Variant) -> void:
	var ok: bool = got == want
	if not ok:
		_bad += 1
	print("  %s %s: %s%s" % ["✓" if ok else "✗", what, str(got),
			"" if ok else " (чекали %s)" % str(want)])


func _go() -> void:
	Net.joined = true
	await get_tree().process_frame
	var data := GameData.new()
	data.load_all()
	var world := Node3D.new()
	get_tree().root.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	world.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.62, 0.7)
	env.environment.ambient_light_color = Color(1, 1, 1)
	env.environment.ambient_light_energy = 0.6
	world.add_child(env)
	var people: Array = []
	for i in ROW.size():
		var a: Node = AVATAR.instantiate()
		world.add_child(a)
		a.set_physics_process(false)
		a.apply_sex("чоловік")
		a.place_at(Vector3((i - 3) * 1.4, 0, 0), PI)
		var look := {"зброя": ROW[i][0]}
		if ROW[i][1] != "":
			look["щит"] = ROW[i][1]
		a.wear(look, data.items)
		a.model().show_move("Sword_Idle")
		people.append(a)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.position = Vector3(0, 1.3, 7.5)
	cam.look_at(Vector3(0, 1.0, 0))
	cam.current = true
	for i in 30:
		await get_tree().process_frame

	print("\n— тримання —")
	var skel: Skeleton3D = people[0].model()._skeleton
	var grips: Array = _held(skel)
	_expect("меч і щит — двоє", grips.size(), 2)
	var bones: Array = []
	for g: Node in grips:
		bones.append(g.bone_name)
	_expect("меч у правій, щит у лівій", bones, ["hand_r", "hand_l"])
	var bow_skel: Skeleton3D = people[5].model()._skeleton
	_expect("лук у лівій", bow_skel.get_node("Тримає-зброя").bone_name, "hand_l")
	Shot.take(get_tree().root)
	await get_tree().create_timer(1.0).timeout
	cam.position = Vector3(2.8, 1.3, 3.2)
	cam.look_at(Vector3(2.8, 1.0, 0))
	await get_tree().process_frame
	Shot.take(get_tree().root)
	await get_tree().create_timer(1.0).timeout

	people[0].wear({}, data.items)
	await get_tree().process_frame
	_expect("зняв — порожні руки", _held(skel).size(), 0)
	print("\nпомилок: %d" % _bad)
	get_tree().quit(1 if _bad > 0 else 0)


func _held(skel: Skeleton3D) -> Array:
	var out: Array = []
	for n: Node in skel.get_children():
		if str(n.name).begins_with("Тримає-"):
			out.append(n)
	return out
