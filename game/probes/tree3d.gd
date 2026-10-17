extends SceneTree
## Дерева Tree3D (план §3в): кожен сорт усіма зернами в ряд — вибирати
## очима, — і числа, з якими вирішувати, скільки таких дерев гра витягне.
##
## Друкує на сорт: час вирощування всіх зерен, трикутники стовбура й
## гілочок, висоту. Поруч — жердина 1,8 м: зріст гравця.
##
## Ганяти так:
##     ./run.sh --дерева3д            вікно, знімки в user://
##     ./run.sh --дерева3д --числа    лише числа, без вікна
##
## Esc — вийти.

const GAP := 9.0
const ROW_GAP := 14.0
## Висота, до якої тягнемо кожне дерево в показі: як у листяних
## моделей світу 1 (7–9 м).
const TALL := 8.0

var _shots_left := 2
var _clock := 0.0
var _page: Node3D


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	if not Tree3DLook.available():
		print("[дерева3д] ‼ пакета Tree3D нема: addons/Tree3D не завантажився")
		quit(1)
		return
	var page := Node3D.new()
	root.add_child(page)
	_page = page
	var row := 0
	for kind: String in Tree3DLook.KINDS:
		var started := Time.get_ticks_usec()
		for seed in Tree3DLook.SEEDS:
			Tree3DLook.grown(kind, seed)
		var spent := (Time.get_ticks_usec() - started) / 1000.0
		var made := Tree3DLook.grown(kind, 0)
		print(("[дерева3д] %-7s %d зерен за %.0f мс · стовбур %d · "
				+ "гілочки %d трикутників · висота %.1f м")
				% [kind, Tree3DLook.SEEDS, spent, _triangles(made[0]),
				_triangles(made[1]), float(made[2])])
		for seed in Tree3DLook.SEEDS:
			var one := Tree3DLook.view(kind, seed, TALL)
			one.position = Vector3(seed * GAP, 0, -row * ROW_GAP)
			page.add_child(one)
		_label(page, kind, Vector3(-6, 0.3, -row * ROW_GAP))
		row += 1
	if "--числа" in OS.get_cmdline_user_args() \
			or DisplayServer.get_name() == "headless":
		quit()
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_stage(page, row)


func _process(delta: float) -> bool:
	_clock += delta
	if _page != null and _shots_left > 0 and _clock > 3.0 * (3 - _shots_left):
		_shots_left -= 1
		Shot.take(_page)
	if Input.is_key_pressed(KEY_ESCAPE):
		quit()
	return false


func _stage(page: Node3D, rows: int) -> void:
	var air := WorldEnvironment.new()
	var sky := Environment.new()
	sky.background_mode = Environment.BG_SKY
	var made := Sky.new()
	made.sky_material = ProceduralSkyMaterial.new()
	sky.sky = made
	sky.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	sky.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	air.environment = sky
	page.add_child(air)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	page.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120, 120)
	ground.mesh = plane
	var soil := StandardMaterial3D.new()
	soil.albedo_color = Color("#4d5b33")
	ground.material_override = soil
	ground.position = Vector3(GAP * 2.5, 0, -ROW_GAP * (rows - 1) * 0.5)
	page.add_child(ground)
	var pole := MeshInstance3D.new()
	var stick := BoxMesh.new()
	stick.size = Vector3(0.4, 1.8, 0.4)
	pole.mesh = stick
	pole.position = Vector3(-2.5, 0.9, 0)
	page.add_child(pole)
	var eye := Camera3D.new()
	page.add_child(eye)
	var middle := Vector3(GAP * 2.5, 3.0, -ROW_GAP * (rows - 1) * 0.5)
	eye.look_at_from_position(middle + Vector3(0, 12, 30), middle)
	root.size = Vector2i(1600, 1000)


func _label(page: Node3D, text: String, at: Vector3) -> void:
	var sign := Label3D.new()
	sign.text = text
	sign.font_size = 160
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.position = at
	page.add_child(sign)


static func _triangles(mesh: Mesh) -> int:
	var all := 0
	for i in mesh.get_surface_count():
		var parts := mesh.surface_get_arrays(i)
		var idx: Variant = parts[Mesh.ARRAY_INDEX]
		var points: PackedVector3Array = parts[Mesh.ARRAY_VERTEX]
		all += (idx as PackedInt32Array).size() / 3 if idx != null \
				else points.size() / 3
	return all
