extends Node
## Проба ефектів бою (П-33, П-272): кожен ефект `Fx` — окремим знімком, без
## світу, мережі й сервера (як `portal_look.gd`: `main.tscn` стукав би в
## живу гру замовника).
##
##     godot --path game res://scenes/fx_look.tscn -- --тека <каталог>
##
## Ліворуч — кастер (орчиха s1303), праворуч — дві цілі (вовки). Знімки:
## 1 каст атаки посередині читання · 2 згусток у польоті · 3 хвиля
## «усі-поруч» · 4 баф · 5 лік · 6 звичайний удар · 7 пил смерті.
## Друкує, скільки вузлів ефектів живе після всього (має бути 0) і
## середній час кадру під час ефектів.

const AVATARS := "res://models/own/avatary/"
const CASTER := AVATARS + "ork-s1303-mixamo/ork-s1303-mixamo.glb"
const BEAST := "res://models/own/вовк.glb"

var _fx: Fx
var _dir := "user://fx"
var _shots: Array = []
var _frame_ms: Array = []
## Знімки — зі своєї сцени сталого розміру: віконний менеджер міняв
## розмір вікна посеред прогону, і кадри 6–7 виходили іншими.
var _screen: SubViewport


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var args := OS.get_cmdline_user_args()
	var at := args.find("--тека")
	if at >= 0 and at + 1 < args.size():
		_dir = args[at + 1]
	DirAccess.make_dir_recursive_absolute(_dir)
	_go()


func _process(delta: float) -> void:
	_frame_ms.append(delta * 1000.0)


func _go() -> void:
	await get_tree().process_frame
	_screen = SubViewport.new()
	_screen.size = Vector2i(1280, 720)
	_screen.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_screen.msaa_3d = Viewport.MSAA_2X
	add_child(_screen)
	var world := Node3D.new()
	_screen.add_child(world)
	_stage(world)

	var book := SkillBook.new()
	var raw: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/skills.json"))
	book.load_from(raw)
	_fx = Fx.new()
	_fx.skills = book
	world.add_child(_fx)

	var caster := _figure(world, CASTER, Vector3(-2.5, 0, 0), 1.85)
	var wolf_a := _figure(world, BEAST, Vector3(2.5, 0, -1.2), 0.9)
	var wolf_b := _figure(world, BEAST, Vector3(3.0, 0, 1.2), 0.9)
	caster.look_at(Vector3(3, 0, 0))
	caster.rotate_y(PI)
	_fx.creatures = {1: caster, 2: wolf_a, 3: wolf_b}

	var attack := _key(book, "жива", true)
	var blast := _key(book, "усі-поруч", true)
	var buff := _key(book, "себе", false)
	var heal := _heal_key(book)
	print("[fx] скіли: атака %s · вибух %s · баф %s · лік %s"
			% [attack, blast, buff, heal])

	_frame_ms.clear()
	_fx.cast_start(1, book.get_skill(attack).name, 2.0)
	await _wait(1.2)
	await _shot("1-каст")
	_fx.cast_end(1, true)
	_fx.skill_landed(1, attack, [2])
	_fx.hit(2, 120, false)   # має промовчати: це число від скіла
	await _wait(0.14)
	await _shot("2-згусток")
	await _wait(0.9)
	_fx.skill_landed(1, blast, [2, 3])
	await _wait(0.2)
	await _shot("3-хвиля")
	await _wait(1.0)
	_fx.skill_landed(1, buff, [1])
	await _wait(0.45)
	await _shot("4-баф")
	await _wait(1.2)
	_fx.skill_landed(1, heal, [1])
	await _wait(0.45)
	await _shot("5-лік")
	await _wait(1.2)
	_fx.hit(3, 80, false)
	await _wait(0.12)
	await _shot("6-удар")
	await _wait(0.8)
	_fx.death(3)
	await _wait(0.35)
	await _shot("7-смерть")

	var ms := 0.0
	for v: float in _frame_ms:
		ms += v
	ms /= maxf(1.0, _frame_ms.size())
	await _wait(2.5)
	print("[fx] живих вузлів ефектів після всього: %d (лічильник %d)"
			% [_fx.get_child_count(), _fx._live])
	print("[fx] кадр під час ефектів: %.2f мс у середньому, кадрів %d"
			% [ms, _frame_ms.size()])
	print("[fx] знімки: %s" % ", ".join(_shots))
	get_tree().quit(0 if _fx.get_child_count() == 0 and _fx._live == 0 else 1)


func _stage(world: Node3D) -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 0.7
	sun.shadow_enabled = true
	world.add_child(sun)
	var air := Environment.new()
	air.background_mode = Environment.BG_COLOR
	air.background_color = Color(0.22, 0.26, 0.3)
	air.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	air.ambient_light_color = Color(0.6, 0.62, 0.65)
	air.ambient_light_energy = 0.45
	air.glow_enabled = true
	air.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var holder := WorldEnvironment.new()
	holder.environment = air
	world.add_child(holder)
	var ground := MeshInstance3D.new()
	var plate := PlaneMesh.new()
	plate.size = Vector2(60, 60)
	ground.mesh = plate
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("#4a5c3a")
	ground.material_override = paint
	world.add_child(ground)
	var eye := Camera3D.new()
	eye.fov = 50
	world.add_child(eye)
	eye.current = true
	eye.position = Vector3(0.0, 4.5, 7.5)
	eye.look_at(Vector3(0.0, 0.8, 0.0))


func _figure(world: Node3D, path: String, at: Vector3,
		tall: float) -> Node3D:
	var holder := Node3D.new()
	holder.set_script(_stand_in())
	holder.set("tall", tall)
	world.add_child(holder)
	holder.position = at
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("[fx] немає моделі %s" % path)
		return holder
	var body := scene.instantiate() as Node3D
	holder.add_child(body)
	var box := AABB()
	var first := true
	for m: Node in body.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if not first and box.size.y > 0.0:
		body.scale = Vector3.ONE * (tall / box.size.y)
	return holder


## Замість `creature.gd`: Fx питає в істоти лише зріст і модель.
static func _stand_in() -> GDScript:
	var s := GDScript.new()
	s.source_code = "extends Node3D\nvar tall := 1.75\n" \
			+ "func body_height() -> float:\n\treturn tall\n" \
			+ "func model() -> Node3D:\n\treturn get_child(0)\n"
	s.reload()
	return s


func _key(book: SkillBook, target: String, harm: bool) -> String:
	for key: String in book.keys():
		var s := book.get_skill(key)
		if s.target == target and Fx._harms(s) == harm and not s.heals():
			return key
	return ""


func _heal_key(book: SkillBook) -> String:
	for key: String in book.keys():
		if book.get_skill(key).heals():
			return key
	return ""


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [_dir, label]
	var err := _screen.get_texture().get_image().save_png(path)
	_shots.append(label if err == OK else label + " ‼")
