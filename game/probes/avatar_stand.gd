extends Node
## Стенд оцінки аватарів (11.11.2026, `spec/якість-аватарів-і-монстрів.md` §3).
## Слово замовника: «туманний ліс — зайве, простий фон».
##
##     ./run.sh --стенд [-- ключі]
##
## Один запуск — один аркуш: кадр вікі | портрет | три чверті | профіль |
## зріст спереду | зріст ззаду | ігрова камера | у русі. Тло — рівне сіре,
## світло студійне (ключове, заповнювальне, контрове), тонмапер AgX, SSAO.
## Модель збирає той самий `SkinnedModel`, що й гра.
##
## Лише Forward+ (Vulkan): підповерхневе розсіювання шкіри й TAA в
## `opengl3`/llvmpipe не працюють. Поки NVIDIA зайнята — `AMD=1 ./run.sh --стенд`.
##
## Ключі:
##   --модель <res://… або частина шляху в models/own/avatary>
##   --зріст <м>            (типово 1.75)
##   --вікі <файл у wiki/img/rasy, напр. людина-жінка-v1.png>
##   --вигляд "зачіска=коса;колір_волосся=#5a3520"   — як у переглядачі
##   --вдягти "тіло=сталевий нагрудник;…"
##   --рух <назва>          рух для кадрів стоячи (типово Idle_Loop)
##   --аркуш <файл.png>     куди зберегти (типово user://стенд.png)
##   --кадри <тека>         ще й кожен кадр окремим файлом
##   --лише портрет,зріст   — лише названі кадри (швидка проба)
##   --без-волосся         сховати зачіску (оцінити обличчя й шкіру)
##   --кліп 1 / --погляд 0.02,0   застиглий вираз для перевірки (без живого руху)
##   --жити                 не виходити після аркуша (дивитись руками)

const AVATARY := "res://models/own/avatary/"
const TYPOVA := "res://models/own/avatary/pilot-b-zhinka/людина-жінка.glb"
const AVATAR_ANIM := "res://models/player/animations/UAL1_Standard.glb"
const PLYTKA := Vector2i(720, 900)
const TLO := Color(0.16, 0.165, 0.175)
## назва, відстань від цілі, кут (0 — спереду), нахил, ціль: «голова»/«тіло»,
## кут огляду, рух (порожньо — спокій), час у русі
const KADRY := [
	["обличчя", 0.6, 12.0, -2.0, "голова", 28.0, "", 0.0],
	["портрет", 0.95, 8.0, -2.0, "голова", 28.0, "", 0.0],
	["три чверті", 0.95, 42.0, -2.0, "голова", 28.0, "", 0.0],
	["профіль", 0.95, 90.0, 0.0, "голова", 28.0, "", 0.0],
	["потилиця", 1.0, 180.0, -4.0, "голова", 28.0, "", 0.0],
	["зріст", 3.6, 15.0, -3.0, "тіло", 30.0, "", 0.0],
	["зріст ззаду", 3.6, 195.0, -3.0, "тіло", 30.0, "", 0.0],
	["ігрова", 5.0, 205.0, -22.0, "тіло", 60.0, "Sprint_Loop", 0.35],
	["у русі", 2.6, 35.0, -4.0, "тіло", 34.0, "Sprint_Loop", 0.35],
]

var _world: Node3D
var _cam: Camera3D
var _model: SkinnedModel
var _pidpys: Label
var _zrist := 1.75
var _knyha: ItemBook


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	get_window().size = PLYTKA
	Engine.max_fps = 60          # час іде рівно й без vsync (пружини волосся)
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_4X
	vp.use_taa = true
	_scena()
	_zibraty(args)
	if "--вигляд" in args:
		var look := {}
		for pair: String in _arg(args, "--вигляд", "").split(";"):
			var kv := pair.split("=")
			if kv.size() == 2:
				look[kv[0]] = Color(kv[1]) if kv[1].begins_with("#") else \
						(float(kv[1]) if kv[1].is_valid_float() else kv[1])
		_model.customize(look)
	if "--вдягти" in args:
		var na_sobi := {}
		for pair: String in _arg(args, "--вдягти", "").split(";"):
			var kv := pair.split("=")
			if kv.size() == 2:
				na_sobi[kv[0]] = kv[1]
		_model.wear(na_sobi, _rechi())
	if "--без-волосся" in args:
		for m: MeshInstance3D in _model.find_children("Волосся*", "MeshInstance3D", true, false):
			m.visible = false
	# перевірка руху обличчя: `--кліп 1` — очі заплющені, `--погляд x,y` — зсув погляду
	if "--кліп" in args or "--погляд" in args:
		_model.face_alive = false
		if "--кліп" in args:
			_model.set_blink(float(_arg(args, "--кліп", "1")))
		if "--погляд" in args and _model._eye_mat != null:
			var g := _arg(args, "--погляд", "0,0").split(",")
			_model._eye_mat.set_shader_parameter("gaze", Vector2(float(g[0]), float(g[1])))
	await _arkush(args)
	if not "--жити" in args:
		get_tree().quit()


func _arg(args: PackedStringArray, key: String, default: String) -> String:
	var at := args.find(key)
	return args[at + 1] if at >= 0 and at + 1 < args.size() else default


func _rechi() -> ItemBook:
	if _knyha == null:
		_knyha = ItemBook.new()
		var f := FileAccess.open("res://data/items.json", FileAccess.READ)
		if f != null:
			_knyha.load_from(JSON.parse_string(f.get_as_text()))
	return _knyha


func _scena() -> void:
	_world = Node3D.new()
	add_child(_world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = TLO
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.66, 0.74)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = true
	env.ssao_radius = 0.35
	env.ssao_intensity = 1.6
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)
	# ключове — спереду-згори-збоку, тепле, з тінню
	_svitlo(Vector3(-38, 32, 0), 1.05, Color(1.0, 0.96, 0.9), true)
	# заповнювальне — з другого боку, холодне, без тіні
	_svitlo(Vector3(-12, -55, 0), 0.38, Color(0.82, 0.88, 1.0), false)
	# контрове — ззаду-згори: край волосся й плечей, просвічування вух
	_svitlo(Vector3(-28, 165, 0), 0.9, Color(1.0, 0.98, 0.95), true)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(800, 800)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = TLO.lightened(0.06)
	gm.roughness = 1.0
	ground.material_override = gm
	_world.add_child(ground)
	_cam = Camera3D.new()
	_world.add_child(_cam)
	var layer := CanvasLayer.new()
	add_child(layer)
	_pidpys = Label.new()
	_pidpys.position = Vector2(14, 10)
	_pidpys.add_theme_font_size_override("font_size", 22)
	_pidpys.add_theme_color_override("font_color", Color(0.92, 0.9, 0.82))
	layer.add_child(_pidpys)


func _svitlo(kut: Vector3, sila: float, kolir: Color, tin: bool) -> void:
	var l := DirectionalLight3D.new()
	l.rotation_degrees = kut
	l.light_energy = sila
	l.light_color = kolir
	l.shadow_enabled = tin
	l.shadow_blur = 1.5
	l.directional_shadow_max_distance = 30.0
	_world.add_child(l)


func _zibraty(args: PackedStringArray) -> void:
	var p := _arg(args, "--модель", TYPOVA)
	if not p.begins_with("res://"):
		p = _znaity(p)
	if p == "" or not ResourceLoader.exists(p):
		push_error("[стенд] немає моделі «%s»" % _arg(args, "--модель", TYPOVA))
		get_tree().quit(1)
		return
	_zrist = float(_arg(args, "--зріст", "1.75"))
	_model = SkinnedModel.new()
	_model.path = p
	_model.height = _zrist
	_model.hair_shader = "--шейдер-волосся" in args      # дослідний, типово вимкнено
	var s: Node = (load(p) as PackedScene).instantiate()
	var ap: AnimationPlayer = s.find_child("AnimationPlayer", true, false)
	if ap == null or ap.get_animation_list().is_empty():
		_model.anim_path = AVATAR_ANIM
	s.free()
	_world.add_child(_model)
	_model.build()
	_model.rotation_degrees.y = 180.0
	print("[стенд] модель ", p)


## Перша модель у теці аватарів, у шляху якої є `chastyna`.
func _znaity(chastyna: String, dir := AVATARY) -> String:
	var d := DirAccess.open(dir)
	if d == null:
		return ""
	var pidteky: Array = []
	for f: String in d.get_files():
		if (f.ends_with(".glb") or f.ends_with(".gltf")) and (dir + f).find(chastyna) >= 0:
			return dir + f
	for sub: String in d.get_directories():
		pidteky.append(sub)
	for sub: String in pidteky:
		var r := _znaity(chastyna, dir + sub + "/")
		if r != "":
			return r
	return ""


func _holova() -> Vector3:
	# очі MPFB — окрема сітка: її середина й є рівень погляду
	for m: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		var n := str(m.name)
		if (n.ends_with("high-poly") or n.ends_with("low-poly")) and m.mesh != null:
			var c := m.global_transform * m.get_aabb().get_center()
			return Vector3(c.x, c.y - 0.055, c.z)
	# модель генератора без окремих очей — від кістки голови (основа черепа) до рівня очей
	var sk: Skeleton3D = _model.find_child("Skeleton3D", true, false)
	if sk != null and sk.find_bone("head") >= 0:
		var t := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("head"))
		var k := _zrist / 1.75
		return t.origin + t.basis.y.normalized() * 0.07 * k + Vector3.RIGHT.cross(t.basis.y).normalized() * 0.09 * k
	return Vector3(0, _zrist * 0.915, 0)


func _nastavyty(k: Array) -> void:
	var aim := _holova() if k[4] == "голова" else Vector3(0, _zrist * 0.52, 0)
	var yaw := deg_to_rad(float(k[2]))
	var pitch := deg_to_rad(float(k[3]))
	var off := Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch)) * float(k[1])
	_cam.fov = float(k[5])
	_cam.position = aim + off
	_cam.look_at(aim, Vector3.UP)
	_pidpys.text = str(k[0])


func _rukh(nazva: String, chas: float) -> void:
	var ap: AnimationPlayer = _model.find_child("AnimationPlayer", true, false)
	if ap == null:
		return
	if ap.has_animation(nazva):
		ap.play(nazva)
	if chas > 0.0:
		ap.seek(chas, true)
		ap.pause()


func _arkush(args: PackedStringArray) -> void:
	var lyshe := _arg(args, "--лише", "").split(",", false)
	var spokii := _arg(args, "--рух", "Idle_Loop")
	var plytky: Array = []
	var viki := _arg(args, "--вікі", "")
	if viki != "":
		var shliakh := ProjectSettings.globalize_path("res://").path_join("../wiki/img/rasy/" + viki)
		var ref := Image.load_from_file(shliakh)
		if ref != null:
			ref.convert(Image.FORMAT_RGB8)
			var k := float(PLYTKA.y) / ref.get_height()
			ref.resize(int(ref.get_width() * k), PLYTKA.y, Image.INTERPOLATE_LANCZOS)
			# середина кадру вікі завширшки з плитку
			var x0 := maxi(0, (ref.get_width() - PLYTKA.x) / 2)
			plytky.append(ref.get_region(Rect2i(x0, 0, mini(PLYTKA.x, ref.get_width()), PLYTKA.y)))
		else:
			print("[стенд] ‼ немає кадру вікі ", shliakh)
	var teka := _arg(args, "--кадри", "")
	if teka != "":
		DirAccess.make_dir_recursive_absolute(teka)
	var ostannii := "?"
	for k: Array in KADRY:
		if not lyshe.is_empty() and not str(k[0]) in lyshe:
			continue
		var rukh := str(k[6]) if str(k[6]) != "" else spokii
		if rukh != ostannii:
			_rukh(rukh, float(k[7]))
			ostannii = rukh
			for i in 50:                 # пружини волосся сідають
				await get_tree().process_frame
		_nastavyty(k)
		for i in 24:                     # TAA сходиться
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		plytky.append(img)
		if teka != "":
			img.save_png(teka.path_join(str(k[0]).replace(" ", "-") + ".png"))
	if plytky.is_empty():
		return
	var u_riad := mini(plytky.size(), 5)
	var riadkiv := int(ceil(plytky.size() / float(u_riad)))
	var ark := Image.create(u_riad * PLYTKA.x, riadkiv * PLYTKA.y, false, Image.FORMAT_RGB8)
	ark.fill(TLO)
	for i in plytky.size():
		var im: Image = plytky[i]
		ark.blit_rect(im, Rect2i(Vector2i.ZERO, im.get_size()),
				Vector2i((i % u_riad) * PLYTKA.x, (i / u_riad) * PLYTKA.y))
	var kudy := _arg(args, "--аркуш", "user://стенд.png")
	ark.save_png(kudy)
	print("[стенд] аркуш ", ProjectSettings.globalize_path(kudy) if kudy.begins_with("user://") else kudy,
			" · кадрів ", plytky.size(), " · кадрів/с ", Engine.get_frames_per_second())
