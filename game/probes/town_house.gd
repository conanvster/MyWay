extends Node
## Доми міст світу 2 (`TownLook.house_body`) окремо від світу: щоб бачити
## кути, двері, вікна й фронтони зблизька, а не з камери вулиці.
##
##     godot --path game res://scenes/town_house.tscn -- --тека <каталог>
##
## Три доми (штукатурка 3×2, цегла 2×3, фахверк 3×2) і чотири ракурси:
## перед навскіс, кут ззаду, бік зблизька, згори. Без `main.tscn` — нічого
## не стукає в живу гру.

const HOUSES := [
	{"модулі": [3, 2], "стіни": "штукатурка", "дах": "черепиця",
		"комин": true},
	{"модулі": [2, 3], "стіни": "цегла", "дах": "сланець"},
	{"модулі": [3, 2], "стіни": "фахверк", "дах": "стріха", "тин": true},
]
const VIEWS := [
	["1-перед", Vector3(4, 2.2, 13), Vector3(0, 2, 0)],
	["2-кут-ззаду", Vector3(-12, 2.2, -10), Vector3(-4, 2, 0)],
	["3-бік", Vector3(-17, 1.8, 2), Vector3(-10, 1.8, 0)],
	["4-згори", Vector3(2, 18, 14), Vector3(0, 0, 0)],
]

var _screen: SubViewport
var _dir := "user://town_house"


func _ready() -> void:
	# Помилка в скрипті, що його кличе проба, лишає `await` без кінця —
	# і вікно висить. Аварійний вихід.
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("‼ проба не скінчилась за 90 с")
		get_tree().quit(1))
	var args := OS.get_cmdline_user_args()
	var at := args.find("--тека")
	if at >= 0 and at + 1 < args.size():
		_dir = args[at + 1]
	DirAccess.make_dir_recursive_absolute(_dir)
	_go()


func _go() -> void:
	await get_tree().process_frame
	_screen = SubViewport.new()
	_screen.size = Vector2i(1280, 720)
	_screen.msaa_3d = Viewport.MSAA_2X
	_screen.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_screen)
	var world := Node3D.new()
	_screen.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -40, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	world.add_child(sun)
	var air := Environment.new()
	air.background_mode = Environment.BG_COLOR
	air.background_color = Color(0.62, 0.7, 0.78)
	air.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	air.ambient_light_color = Color("#c9cdb8")
	air.ambient_light_energy = 0.6
	air.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	air.ssao_enabled = true
	var holder := WorldEnvironment.new()
	holder.environment = air
	world.add_child(holder)
	var ground := MeshInstance3D.new()
	var plate := PlaneMesh.new()
	plate.size = Vector2(80, 80)
	ground.mesh = plate
	var green := StandardMaterial3D.new()
	green.albedo_color = Color("#5d6b45")
	ground.material_override = green
	world.add_child(ground)
	for i in HOUSES.size():
		var body := StaticBody3D.new()
		body.position = Vector3(-10.0 + i * 10.0, 0, 0)
		world.add_child(body)
		TownLook.house_body(body, HOUSES[i], true)
	var eye := Camera3D.new()
	eye.fov = 60
	world.add_child(eye)
	eye.current = true
	for view: Array in VIEWS:
		eye.position = view[1]
		eye.look_at(view[2])
		for f in 12:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := "%s/%s.png" % [_dir, view[0]]
		var err := _screen.get_texture().get_image().save_png(path)
		print("[дім] %s%s" % [path, "" if err == OK else " ‼"])
	get_tree().quit()
