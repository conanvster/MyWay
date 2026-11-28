extends SceneTree
## Показ пілоту П-297 (28.11.2026, слово замовника: «чи можна їх подивитись у демо режимі?»).
## Перший ряд — нові моделі з `models/own/<вид>.glb` (зі зброєю, пружинами, новими вагами),
## другий — колишні копії (до П-297); кожна
## модель по черзі грає свої рухи (підпис над головою), усі тим самим зростом. Усі одночасно міняють рух,
## тож видно, що той самий рух у різних видів різний.
##
##     ./run.sh --пілот-монстрів            Esc — вийти, ←/→ — обертати, колесо — ближче/далі,
##                                          пробіл — пауза на поточному русі, S — знімок
##     ./run.sh --пілот-монстрів --знімок <файл.png>   (сам зробить знімок на 4-й секунді й вийде)

const DIR := "res://models/own/"
const PILOT := [
	["кабанолюд-громила", 2.2, "res://models/own/гнол-мисливець.glb"],
	["драконід-воїн", 2.0, "res://models/own/імп.glb"],
	["гнол-шаман", 2.42, "res://models/own/гнол-мисливець.glb"],
]
const MOVES := ["Idle", "Walk", "Run", "Attack", "Attack2", "Cast", "Hit", "Hit2", "Death", "Death2"]
const LOOP_SHOW := 3.0     ## скільки показувати рух, що повторюється (стоїть, іде, біжить, каст)
const STEP_X := 4.2

var _new: Array = []       ## [SkinnedModel, Label3D]
var _old: Array = []
var _cam: Camera3D
var _turn := 0.0
var _dist := 15.0
var _move_i := 0
var _left := 0.0
var _paused := false
var _shot := ""
var _shot_at := 4.0
var _hud: Label


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if "--знімок" in args:
		_shot = args[args.find("--знімок") + 1]
	call_deferred("_go")


func _model(path: String, at: Vector3, height: float) -> SkinnedModel:
	var m := SkinnedModel.new()
	m.path = path
	root.add_child(m)
	m.build()
	m.position = at
	# зріст — як у бестіарії (нові вже такі; старі копії — масштабом)
	var lo := INF
	var hi := -INF
	for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
		if mi.name.begins_with("Тримає-") or mi.get_parent().name.begins_with("Тримає-"):
			continue
		var b := mi.global_transform * mi.get_aabb()
		lo = minf(lo, b.position.y)
		hi = maxf(hi, b.end.y)
	if hi > lo:
		m.scale *= height / (hi - lo)
	return m


func _label(text: String, at: Vector3, size := 48) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.outline_size = 10
	l.position = at
	root.add_child(l)
	return l


func _go() -> void:
	await process_frame
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	root.add_child(sun)
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var air := Environment.new()
	air.background_mode = Environment.BG_SKY
	air.sky = sky
	air.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	air.ambient_light_energy = 1.0
	air.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = air
	root.add_child(we)
	var ground := MeshInstance3D.new()
	var plate := PlaneMesh.new()
	plate.size = Vector2(30, 30)
	ground.mesh = plate
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("#4a5c3a")
	ground.set_surface_override_material(0, paint)
	root.add_child(ground)

	for i in PILOT.size():
		var x := (i - 1) * STEP_X
		var name: String = PILOT[i][0]
		var h: float = PILOT[i][1]
		var m := _model(DIR + name + ".glb", Vector3(x, 0, 0), h)
		var l := _label(name, Vector3(x, h + 0.45, 0))
		_new.append([m, l])
		var o := _model(PILOT[i][2], Vector3(x, 0, 6.0), h)
		_label("було: копія «%s»" % PILOT[i][2].get_file().get_basename(),
				Vector3(x, h + 0.3, 6.0), 32)
		_old.append(o)
	_cam = Camera3D.new()
	root.add_child(_cam)
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 22)
	_hud.text = "Пілот П-297 · нові (передній ряд) · колишні копії (задній)\n" \
			+ "←/→ обертати · колесо ближче/далі · пробіл пауза · S знімок · Esc вийти"
	var layer := CanvasLayer.new()
	root.add_child(layer)
	layer.add_child(_hud)
	_show_move()
	process_frame.connect(_tick)


func _show_move() -> void:
	var mv: String = MOVES[_move_i]
	var longest := 0.0
	for pair: Array in _new:
		var m: SkinnedModel = pair[0]
		var l: Label3D = pair[1]
		match mv:
			"Idle":
				m.animate(0.0)
			"Walk":
				m.show_move("Walk")
			"Run":
				m.animate(5.0)
			_:
				m.show_move(mv, false, true)
		l.text = "%s\n%s" % [l.text.split("\n")[0], mv]
		longest = maxf(longest, m.move_length(mv))
	for o: SkinnedModel in _old:
		if mv in ["Walk", "Run"]:
			o.animate(4.0)
		elif mv.begins_with("Attack"):
			o.swing()
		else:
			o.animate(0.0)
	_left = LOOP_SHOW if mv in ["Idle", "Walk", "Run", "Cast"] else longest + 0.8


func _tick() -> void:
	var dt := 1.0 / 60.0
	if Input.is_key_pressed(KEY_ESCAPE):
		quit()
	if Input.is_key_pressed(KEY_LEFT):
		_turn -= dt * 1.2
	if Input.is_key_pressed(KEY_RIGHT):
		_turn += dt * 1.2
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_WHEEL_UP):
		_dist = maxf(4.0, _dist - 0.4)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_WHEEL_DOWN):
		_dist = minf(20.0, _dist + 0.4)
	# моделі дивляться в −Z: камера спереду (−Z), трохи збоку й згори
	var a := deg_to_rad(-25.0) + _turn
	_cam.position = Vector3(sin(a) * _dist, 3.2, -cos(a) * _dist) + Vector3(0, 0, 3.0)
	_cam.look_at(Vector3(0, 1.1, 3.0))
	if not _paused:
		_left -= dt
		if _left <= 0.0:
			_move_i = (_move_i + 1) % MOVES.size()
			_show_move()
	if Input.is_key_pressed(KEY_SPACE):
		_paused = not _paused
		await create_timer(0.3).timeout
	if Input.is_key_pressed(KEY_S) or (_shot != "" and _shot_at <= 0.0):
		var p := _shot if _shot != "" else "user://пілот-%d.png" % Time.get_ticks_msec()
		root.get_viewport().get_texture().get_image().save_png(p)
		print("знімок → ", p)
		if _shot != "":
			quit()
		await create_timer(0.5).timeout
	if _shot != "":
		_shot_at -= dt
