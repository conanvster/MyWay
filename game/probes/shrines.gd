extends Node
## Святині й портали (П-153) — ТЕСТОВИЙ ВАРІАНТ, щоб було на що
## подивитись і що відхилити, перш ніж писати підземелля.
##
## Ганяти так (через сцену, не `--script`):
##     ./run.sh --святині
##
## Дві половини:
##
## 1. ПАРАД. П'ять форм зі слів замовника (обеліск · велике дерево ·
##    камінь · скеля · руїни) × три стани (під охороною · зачищена ·
##    активована). Плюс окремий ряд: та сама форма в усіх семи грейдах,
##    щоб було видно, чи взагалі розрізняються кольори здалеку.
##
## 2. АНАЛІЗ МАПИ. Скільки святинь узагалі влазить у теперішній світ і
##    де саме — рахується на СПРАВЖНЬОМУ краєвиді (`height_at`,
##    `_sector_at` з `landscape.gd`), а не на око.
##
## Чому сценою. Проба піднімає `main.tscn`, щоб рахувати на СПРАВЖНЬОМУ
## краєвиді, а в режимі `--script` немає автозавантажень — `world.gd` не
## компілюється через `Net`, і журнал повниться помилками, хоча числа
## однаково виходять. Той самий прийом, що в лінтера й вітрини.
##
## Esc — вийти, пробіл — знімок, колесо миші — ближче/далі.

const MAIN := preload("res://scenes/main.tscn")

const STEP_X := 13.0
const STEP_Z := 15.0
const LABEL_HEIGHT := 9.0
const ZOOM_STEP := 3.0
const ZOOM_MIN := 8.0

## Скільки точок кидати, шукаючи місця під святині.
const TRIES := 4000
## Скільки метрів між двома святинями щонайменше: кожну оточує
## скупчення монстрів, і два скупчення не мають зливатись в одне.
const APART := 34.0
## Не ближче до центру міста, ніж це: у місті б'ються не всі, а святиня
## тягне за собою монстрів.
const CITY_KEEP := 40.0
## Запас над рівнем моря, щоб святиня не стояла по коліна у воді.
const DRY := 1.0


class InputCatcher extends Node:
	var zoom := 0.0

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				zoom -= ZOOM_STEP
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				zoom += ZOOM_STEP


@onready var root: Window = get_tree().root


func _ready() -> void:
	_go()


func _go() -> void:
	await get_tree().process_frame
	var data := GameData.new()
	data.load_all()

	# Саме `await`: без нього краєвид з аналізу лишається жити поруч із
	# парадом, і на знімку видно тільки величезну зелену площину замість
	# святинь (спіймано знімком 05.09.2026).
	await _report_map(data)

	var world := Node3D.new()
	root.add_child(world)
	_light(world)

	var ground := MeshInstance3D.new()
	var plate := BoxMesh.new()
	plate.size = Vector3(5 * STEP_X + 20.0, 1, 4 * STEP_Z + 20.0)
	ground.mesh = plate
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("#4a5c3a")
	ground.set_surface_override_material(0, paint)
	ground.position = Vector3(0, -0.5, 0)
	world.add_child(ground)

	# Ряди 1-3: форма × стан.
	var stages := [Shrine.Stage.ПІД_ОХОРОНОЮ, Shrine.Stage.ЗАЧИЩЕНА,
			Shrine.Stage.АКТИВОВАНА]
	var stage_names := ["під охороною", "зачищена", "активована"]
	var from_x := -STEP_X * 2.0
	print("\n— парад форм —")
	for row in stages.size():
		for col in Shrine.FORMS.size():
			var form: String = Shrine.FORMS[col]
			var at := Vector3(from_x + col * STEP_X, 0.0,
					-STEP_Z + row * STEP_Z)
			var shrine := Shrine.new()
			shrine.form = form
			shrine.grade = "C"
			shrine.shard_red = col % 2 == 1
			world.add_child(shrine)
			shrine.position = at
			shrine.set_stage(stages[row])
			# Портал стоїть поруч, а не замість святині — окрема сутність
			# (П-153), і саме тому його видно лише в третьому ряду.
			if stages[row] == Shrine.Stage.АКТИВОВАНА:
				var gate := Portal.new()
				gate.grade = "C"
				world.add_child(gate)
				gate.position = at + Vector3(4.5, 0.0, 2.5)
			_tag(world, at + Vector3(0, LABEL_HEIGHT, 0),
					"%s · %s" % [form, stage_names[row]])
		print("  ряд %d: %s" % [row + 1, stage_names[row]])

	# Ряд 4: усі сім грейдів однією формою — чи розрізняються кольори.
	var grades: Array = ItemBook.GRADES
	print("\n— грейди (кольори ті самі, що на значках речей) —")
	for i in grades.size():
		var grade: String = str(grades[i])
		var at := Vector3(from_x + (i - 1) * (STEP_X * 0.72), 0.0,
				2.0 * STEP_Z)
		var shrine := Shrine.new()
		shrine.form = "обеліск"
		shrine.grade = grade
		world.add_child(shrine)
		shrine.position = at
		shrine.set_stage(Shrine.Stage.ЗАЧИЩЕНА)
		_tag(world, at + Vector3(0, LABEL_HEIGHT * 0.85, 0), grade)
		var tone: Color = ItemIcon.grade_color(grade)
		print("  %-2s  #%02x%02x%02x" % [grade, int(tone.r * 255),
				int(tone.g * 255), int(tone.b * 255)])

	_report_portal()

	var catcher := InputCatcher.new()
	world.add_child(catcher)
	var radius := 46.0
	var eye := Camera3D.new()
	eye.fov = 70
	world.add_child(eye)
	eye.current = true
	# Поставити ДО першого знімка, а не тільки в циклі: інакше камера в
	# мить знімка ще в нулі — тобто всередині землі, і на знімку сама
	# зелена площина (спіймано знімком 05.09.2026).
	eye.position = Vector3(0, radius * 0.5, radius)
	eye.look_at(Vector3(0, 2.0, 0))

	for i in 8:
		await get_tree().process_frame
	Shot.take(world)

	print("\n  Esc — вийти · пробіл — знімок · колесо — ближче/далі")
	root.close_requested.connect(get_tree().quit)
	var angle := 0.0
	var shot_held := false
	while true:
		await get_tree().process_frame
		if Input.is_key_pressed(KEY_ESCAPE):
			break
		if Input.is_key_pressed(KEY_SPACE):
			if not shot_held:
				Shot.take(world)
			shot_held = true
		else:
			shot_held = false
		if catcher.zoom != 0.0:
			radius = clampf(radius + catcher.zoom, ZOOM_MIN, 140.0)
			catcher.zoom = 0.0
		angle += 0.0022
		eye.position = Vector3(sin(angle) * radius, radius * 0.5,
				cos(angle) * radius)
		eye.look_at(Vector3(0, 2.0, 0))
	get_tree().quit()


## Скільки святинь влазить у теперішній світ і де. Рахуємо на справжньому
## краєвиді: тільки так число значить хоч щось.
func _report_map(data: GameData) -> void:
	var world: Node3D = MAIN.instantiate()
	root.add_child(world)
	await get_tree().process_frame
	var land: Node = world.get_node("Landscape")
	land.build(data.map)
	await get_tree().process_frame

	var earth: Dictionary = data.map.get("земля", {})
	var side := float(earth.get("сторона", 240))
	var half := side * 0.5
	var sea: float = land.sea_level()
	var town: Dictionary = data.map.get("місто", {})
	var city: Vector3 = _point(town.get("центр", [0, 0, 0]))
	var mountains: Array = data.map.get("гори", [])

	print("\n— мапа: чи є де ставити святині —")
	print("  світ %d×%d, море на %.1f, місто в (%.0f, %.0f)"
			% [int(side), int(side), sea, city.x, city.z])
	print("  правила добору: суходіл із запасом %.1f м над морем · не"
			% DRY)
	print("  ближче за %.0f м до центру міста · не ближче за %.0f м"
			% [CITY_KEEP, APART])
	print("  одна до одної · не всередині гори")

	var taken: Array[Vector3] = []
	var by_sector: Dictionary = {}
	var wet := 0
	var too_close_city := 0
	var in_mountain := 0
	var too_close_each := 0
	# Сітка, а не випадок: розкид має бути повторюваним, інакше числа
	# стрибають від запуску до запуску й порівнювати їх нема з чим.
	var seed_was := RandomNumberGenerator.new()
	seed_was.seed = 20260906
	for i in TRIES:
		var x := seed_was.randf_range(-half + 6.0, half - 6.0)
		var z := seed_was.randf_range(-half + 6.0, half - 6.0)
		var y: float = land.height_at(x, z)
		if y < sea + DRY:
			wet += 1
			continue
		var flat := Vector2(x - city.x, z - city.z)
		if flat.length() < CITY_KEEP:
			too_close_city += 1
			continue
		var hit_hill := false
		for hill: Dictionary in mountains:
			var where: Vector3 = _point(hill.get("де", [0, 0, 0]))
			if Vector2(x - where.x, z - where.z).length() \
					< float(hill.get("радіус", 15)) * 0.9:
				hit_hill = true
				break
		if hit_hill:
			in_mountain += 1
			continue
		var crowded := false
		for was: Vector3 in taken:
			if Vector2(x - was.x, z - was.z).length() < APART:
				crowded = true
				break
		if crowded:
			too_close_each += 1
			continue
		taken.append(Vector3(x, y, z))
		var key: String = Landscape._sector_at(x, z)
		by_sector[key] = int(by_sector.get(key, 0)) + 1

	print("  з %d кинутих точок підійшло: %d" % [TRIES, taken.size()])
	print("    відсіяно: під водою %d · надто близько до міста %d ·"
			% [wet, too_close_city])
	print("    у горі %d · надто близько до сусідньої святині %d"
			% [in_mountain, too_close_each])
	var order: Array = by_sector.keys()
	order.sort()
	for key: String in order:
		print("    сектор %-8s %d" % [key, int(by_sector[key])])
	if taken.size() >= 20:
		print("  → «десятки святинь» (П-153) теперішній світ витримує")
	else:
		print("  → ‼ на «десятки святинь» місця НЕ вистачає: %d"
				% taken.size())
		print("    світ треба або більший, або святині щільніше")

	# Спершу забрати з дерева, тоді звільнити: `queue_free()` відкладене,
	# і краєвид устигав потрапити в кадр параду (та сама пастка, що вже
	# ловила проєкт на вічному циклі з `get_child_count`).
	root.remove_child(world)
	world.queue_free()
	await get_tree().process_frame


## Портал: чи справді запрошення показується один раз на захід.
func _report_portal() -> void:
	var gate := Portal.new()
	root.add_child(gate)
	gate.position = Vector3.ZERO
	var here := Vector3(0.5, 0, 0.5)
	var far := Vector3(9, 0, 9)
	print("\n— портал: запрошення один раз на захід (П-153) —")
	print("  зайшов у коло:        %s (треба так)"
			% gate.entered(7, here))
	print("  стоїть далі в колі:   %s (треба ні — інакше вікно щокадру)"
			% gate.entered(7, here))
	print("  вийшов і зайшов знову: %s (треба так)"
			% [_re_enter(gate, far, here)])
	print("  чужий гравець поруч:  %s (треба так — свій лічильник)"
			% gate.entered(8, here))
	gate.queue_free()


func _re_enter(gate: Portal, out: Vector3, back: Vector3) -> bool:
	gate.entered(7, out)
	return gate.entered(7, back)


func _tag(world: Node3D, at: Vector3, text: String) -> void:
	var tag := Label3D.new()
	tag.text = text
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 44
	tag.outline_size = 14
	tag.outline_modulate = Color(0, 0, 0, 0.9)
	tag.pixel_size = 0.012
	tag.position = at
	world.add_child(tag)


func _light(world: Node3D) -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_energy = 0.9
	world.add_child(sun)
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var air := Environment.new()
	air.background_mode = Environment.BG_SKY
	air.sky = sky
	air.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	air.ambient_light_energy = 0.7
	# Світіння грейду має бути видно — без цього емісія тоне в сонці.
	air.glow_enabled = true
	var holder := WorldEnvironment.new()
	holder.environment = air
	world.add_child(holder)


static func _point(from: Variant) -> Vector3:
	var list: Array = from as Array
	if list == null or list.size() < 3:
		return Vector3.ZERO
	return Vector3(float(list[0]), float(list[1]), float(list[2]))
