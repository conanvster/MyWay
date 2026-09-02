class_name Landscape
extends Node3D
## Краєвид: земля, місто з будинками й мешканцями, ліс, гори.
##
## Будується кодом за числами з `data/map.json`. Чому не руками в
## редакторі: сімдесят дерев і п'ять будинків — це сімдесят п'ять вузлів,
## які потім не посунути одним рухом. А так гора переїжджає правкою
## одного рядка, і видно її одразу.
##
## Зони появи монстрів навмисно лишаються вузлами в сцені: їхні межі
## зручніше тягнути мишею, і саме про це просив замовник.
##
## Розкид дерев випадковий, але з **однаковим зерном**: ліс має бути той
## самий і на сервері, і в кожного клієнта, інакше дерево росло б у
## різних місцях у різних людей.
const SEED := 20260902

var data: Dictionary = {}


func build(from_data: Dictionary) -> void:
	data = from_data
	seed(SEED)
	_counts.clear()
	_sky()
	_ground()
	_city()
	_forest()
	_mountains()


## Небо й розсіяне світло. Без цього все, чого не торкнувся промінь
## сонця, лишається майже чорним — на першому знімку міста тінь від
## будинку була суцільною плямою.
func _sky() -> void:
	var sky := Sky.new()
	var painted := ProceduralSkyMaterial.new()
	painted.sky_top_color = Color("#3f6ea8")
	painted.sky_horizon_color = Color("#9fb6c4")
	painted.ground_bottom_color = Color("#3b4432")
	painted.ground_horizon_color = Color("#7d8a76")
	sky.sky_material = painted

	var air := Environment.new()
	air.background_mode = Environment.BG_SKY
	air.sky = sky
	air.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	air.ambient_light_sky_contribution = 0.65
	air.ambient_light_energy = 1.1
	# Легкий туман удалині: гори на краю світу мають танути, а не стояти
	# картонкою. Справжній туман зони бачення — П-65, це не він.
	air.fog_enabled = true
	air.fog_mode = Environment.FOG_MODE_DEPTH
	air.fog_depth_begin = 40.0
	air.fog_depth_end = 130.0
	air.fog_sky_affect = 0.25
	air.fog_light_color = Color(str(data.get("туман", {})
			.get("колір", "#a8b6c2")))
	air.fog_density = 0.0025
	_air = air

	var holder := WorldEnvironment.new()
	holder.name = "Небо"
	holder.environment = air
	add_child(holder)


func _paint(color: String) -> StandardMaterial3D:
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(color)
	paint.roughness = 0.95
	return paint


## Godot стирає ім'я, якщо таке вже є в батька: другий «Будинок» стає
## «@StaticBody3D@8». Тому нумеруємо самі — у редакторі має бути видно,
## де що, а не сорок однакових значків.
var _counts: Dictionary = {}


func _named(word: String) -> String:
	_counts[word] = int(_counts.get(word, 0)) + 1
	return "%s-%d" % [word, _counts[word]]


## Тіло, яке видно й крізь яке не пройти.
func _solid(where: Vector3, mesh: Mesh, shape: Shape3D, color: String,
		name_of: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = _named(name_of)
	body.position = where
	add_child(body)
	var view := MeshInstance3D.new()
	view.name = "Меш"
	view.mesh = mesh
	view.set_surface_override_material(0, _paint(color))
	body.add_child(view)
	var wall := CollisionShape3D.new()
	wall.name = "Стіна"
	wall.shape = shape
	body.add_child(wall)
	return body


## Висота землі в точці. Шум двома шарами: великі пагорби плюс дрібні
## нерівності. Місто вирівнюється до нуля — на схилі не постоїш.
## Небо й туман: тримаємо, щоб міняти дальність тумана під зону бачення.
var _air: Environment
var _noise: FastNoiseLite
var _city_at := Vector3.ZERO
var _city_flat := 0.0


func height_at(x: float, z: float) -> float:
	if _noise == null:
		return 0.0
	var earth: Dictionary = data.get("земля", {})
	var high := _noise.get_noise_2d(x, z) * float(earth.get("розмах", 7.0))
	# Дрібні нерівності, щоб схили не були гладкі, як стіл.
	high += _noise.get_noise_2d(x * 3.1, z * 3.1) * 0.8
	var far: float = Vector2(x - _city_at.x, z - _city_at.z).length()
	if far < _city_flat:
		return 0.0
	# М'який перехід від міста до пагорбів: інакше на межі стіна.
	var edge: float = float(data.get("земля", {}).get("поле", 14))
	if far < _city_flat + edge:
		high *= (far - _city_flat) / edge
	return high


## Земля з рельєфом: сітка вершин, висота з шуму, і та сама висота —
## у форму зіткнення. `HeightMapShape3D` бере рівно ті самі числа, тож
## картинка й те, по чому ходять, не розходяться.
func _ground() -> void:
	var earth: Dictionary = data.get("земля", {})
	var side: float = float(earth.get("сторона", 240))
	var step: float = float(earth.get("крок", 4))
	var city: Dictionary = data.get("місто", {})
	_city_at = _point(city.get("центр", [0, 0, 0]))
	_city_flat = float(city.get("радіус", 26))

	_noise = FastNoiseLite.new()
	_noise.seed = SEED
	_noise.frequency = float(earth.get("частота", 0.012))

	var points := int(side / step) + 1
	var heights := PackedFloat32Array()
	heights.resize(points * points)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in points:
		for ix in points:
			var x := -side * 0.5 + ix * step
			var z := -side * 0.5 + iz * step
			heights[iz * points + ix] = height_at(x, z)
	# Дві трикутні грані на кожну клітинку сітки.
	for iz in points - 1:
		for ix in points - 1:
			var a := Vector3(-side * 0.5 + ix * step,
					heights[iz * points + ix], -side * 0.5 + iz * step)
			var b := Vector3(a.x + step, heights[iz * points + ix + 1], a.z)
			var c := Vector3(a.x, heights[(iz + 1) * points + ix], a.z + step)
			var d := Vector3(a.x + step,
					heights[(iz + 1) * points + ix + 1], a.z + step)
			for corner: Vector3 in [a, c, b, b, c, d]:
				surface.add_vertex(corner)
	surface.generate_normals()

	var body := StaticBody3D.new()
	body.name = "Земля"
	add_child(body)
	var view := MeshInstance3D.new()
	view.name = "Меш"
	view.mesh = surface.commit()
	view.set_surface_override_material(0,
			_paint(str(earth.get("колір", "#4a5c3a"))))
	body.add_child(view)

	var shape := HeightMapShape3D.new()
	shape.map_width = points
	shape.map_depth = points
	shape.map_data = heights
	var wall := CollisionShape3D.new()
	wall.name = "Рельєф"
	wall.shape = shape
	# Форма міряє в клітинках по одиниці, а наша клітинка — `крок`.
	wall.scale = Vector3(step, 1.0, step)
	body.add_child(wall)

	_sea()


## Море: рівна вода на своєму рівні. Усе, що нижче, — під водою (П-61).
func _sea() -> void:
	var sea: Dictionary = data.get("море", {})
	if sea.is_empty():
		return
	var side: float = float(data.get("земля", {}).get("сторона", 240))
	var water := PlaneMesh.new()
	water.size = Vector2(side * 1.4, side * 1.4)
	var top := MeshInstance3D.new()
	top.name = "Море"
	top.mesh = water
	var paint := _paint(str(sea.get("колір", "#25506b")))
	paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	paint.albedo_color.a = 0.72
	paint.metallic = 0.3
	paint.roughness = 0.15
	top.set_surface_override_material(0, paint)
	top.position = Vector3(0, float(sea.get("рівень", -2.2)), 0)
	add_child(top)


## Поставити точку на землю: висота береться з того самого рельєфу, по
## якому ходять. Без цього дерева на схилі висіли б у повітрі.
func _on_ground(point: Vector3) -> Vector3:
	return Vector3(point.x, height_at(point.x, point.z) + point.y, point.z)


func sea_level() -> float:
	return float(data.get("море", {}).get("рівень", -2.2))


## Місто: брук, будинки з дахами й мешканці.
func _city() -> void:
	var city: Dictionary = data.get("місто", {})
	if city.is_empty():
		return
	var center := _point(city.get("центр", [0, 0, 0]))

	# Брук — тонкий круг, щоб місто було видно згори.
	var road := CylinderMesh.new()
	road.top_radius = float(city.get("радіус", 20))
	road.bottom_radius = road.top_radius
	road.height = 0.2
	var stone := MeshInstance3D.new()
	stone.name = "Брук"
	stone.mesh = road
	stone.set_surface_override_material(0,
			_paint(str(city.get("колір бруку", "#6e6459"))))
	stone.position = _on_ground(center) + Vector3(0, 0.06, 0)
	add_child(stone)

	for house: Dictionary in city.get("будинки", []):
		var at := _on_ground(_point(house["де"]))
		if house.has("модулі") and ResourceLoader.exists(WALL % "Plaster_Straight"):
			_kit_house(at, house)
		else:
			_house(at, _point(house.get("розмір", [6, 4, 6])),
					str(house.get("колір", "#8a6a4a")),
					str(house.get("дах", "#6b3f2f")))

	for who: Dictionary in city.get("мешканці", []):
		_dweller(who)


func _house(where: Vector3, size: Vector3, walls: String, roof: String) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var shape := BoxShape3D.new()
	shape.size = size
	_solid(where + Vector3(0, size.y * 0.5, 0), mesh, shape, walls, "Будинок")

	# Дах — чотиригранна піраміда: циліндр із нулем угорі й чотирма гранями.
	var cap := CylinderMesh.new()
	cap.top_radius = 0.0
	cap.bottom_radius = maxf(size.x, size.z) * 0.78
	cap.height = size.y * 0.55
	cap.radial_segments = 4
	var top := MeshInstance3D.new()
	top.name = _named("Дах")
	top.mesh = cap
	top.set_surface_override_material(0, _paint(roof))
	top.position = where + Vector3(0, size.y + cap.height * 0.5, 0)
	top.rotation.y = PI * 0.25
	add_child(top)


## Деталі набору Medieval Village MegaKit (Quaternius, CC0). Сітка в
## наборі стала: стіна 2 метри завширшки й 3,12 заввишки, підлога 2×2,
## дах на 4×4. Тому будинок описується в МОДУЛЯХ — «два на два», — а не
## в метрах: інакше довелось би підганяти числа руками під кожну деталь.
const WALL := "res://models/village/Wall_%s.gltf"
const ROOF_4X4 := "res://models/village/Roof_RoundTiles_4x4.gltf"
const FLOOR := "res://models/village/Floor_Brick.gltf"
const MODULE := 2.0        ## ширина однієї деталі, метрів
const WALL_HEIGHT := 3.12


## Будинок, зібраний із деталей набору.
##
## Стіни ставляться по колу: кожна дивиться назовні, бо в деталі
## зовнішній бік — це -Z. Одна зі стін спереду — з дверима, ще кілька —
## з вікнами; решта глухі.
func _kit_house(where: Vector3, house: Dictionary) -> void:
	var modules: Vector2 = _pair(house.get("модулі", [2, 2]))
	var wide := int(maxf(1.0, modules.x))
	var deep := int(maxf(1.0, modules.y))
	var stone: bool = bool(house.get("цегла", false))
	var straight := WALL % ("UnevenBrick_Straight" if stone else "Plaster_Straight")
	var window := WALL % ("UnevenBrick_Window_Wide_Round" if stone
			else "Plaster_Window_Wide_Round")
	var door := WALL % "Plaster_Door_Round"

	var body := StaticBody3D.new()
	body.name = _named("Будинок")
	body.position = where
	body.rotation.y = deg_to_rad(float(house.get("поворот", 0.0)))
	add_child(body)

	var half_x := (wide - 1) * MODULE * 0.5
	var half_z := (deep - 1) * MODULE * 0.5
	var edge_z := deep * MODULE * 0.5
	var edge_x := wide * MODULE * 0.5

	# Двері — посередині ближньої стіни; вікна — через одну деталь.
	var door_at := wide / 2
	for i in wide:
		var x := -half_x + i * MODULE
		_piece(body, door if i == door_at else (window if i % 2 == 0
				else straight), Vector3(x, 0, edge_z), 180.0)
		_piece(body, window if i % 2 == 1 else straight,
				Vector3(x, 0, -edge_z), 0.0)
	for i in deep:
		var z := -half_z + i * MODULE
		_piece(body, window if i % 2 == 0 else straight,
				Vector3(-edge_x, 0, z), 270.0)
		_piece(body, straight, Vector3(edge_x, 0, z), 90.0)

	# Підлога всередині.
	for ix in wide:
		for iz in deep:
			_piece(body, FLOOR, Vector3(-half_x + ix * MODULE, 0.02,
					-half_z + iz * MODULE), 0.0)

	# Дах: одна деталь на кожні 2×2 модулі.
	for ix in range(0, wide, 2):
		for iz in range(0, deep, 2):
			var at := Vector3(-half_x + (ix + minf(1, wide - ix - 1)) * MODULE * 0.5,
					WALL_HEIGHT + 0.5, -half_z + (iz + minf(1, deep - iz - 1)) * MODULE * 0.5)
			_piece(body, ROOF_4X4, at, 0.0)

	# Крізь будинок не пускає одна коробка на весь обрис.
	var shape := BoxShape3D.new()
	shape.size = Vector3(wide * MODULE, WALL_HEIGHT, deep * MODULE)
	var wall := CollisionShape3D.new()
	wall.name = "Стіна"
	wall.shape = shape
	wall.position = Vector3(0, WALL_HEIGHT * 0.5, 0)
	body.add_child(wall)


## Одна деталь на своєму місці.
func _piece(parent: Node3D, path: String, at: Vector3, turn: float) -> void:
	if not ResourceLoader.exists(path):
		return
	var scene: PackedScene = load(path)
	if scene == null:
		return
	var part: Node3D = scene.instantiate()
	part.position = at
	part.rotation.y = deg_to_rad(turn)
	parent.add_child(part)


static func _pair(from: Variant) -> Vector2:
	var list: Array = from
	return Vector2(float(list[0]), float(list[1]))


## Будинок із готової моделі (крок 6, П-15).
##
## Модель дає лише вигляд; крізь що не пройти — окрема коробка за її
## розміром. Так зроблено навмисно: у гарних моделях геометрія дрібна, і
## зіткнення по ній коштувало б дорожче за саму картинку, а гравцеві
## однаково важливо тільки те, що всередину не зайти.
##
## Якщо моделі немає на диску, будинок лишається коробкою: гра має
## запускатися й без завантажених паків.
func _model_house(where: Vector3, path: String, house: Dictionary) -> void:
	var scene: PackedScene = load(path)
	if scene == null:
		_house(where, _point(house.get("розмір", [6, 4, 6])),
				str(house.get("колір", "#8a6a4a")),
				str(house.get("дах", "#6b3f2f")))
		return
	var body := StaticBody3D.new()
	body.name = _named("Будинок")
	body.position = where
	body.rotation.y = deg_to_rad(float(house.get("поворот", 0.0)))
	add_child(body)

	var view: Node3D = scene.instantiate()
	view.name = "Модель"
	var scale := float(house.get("масштаб", 1.0))
	view.scale = Vector3(scale, scale, scale)
	body.add_child(view)

	# Коробка за розміром самої моделі: не треба вгадувати числа руками.
	var box := _size_of(view) * scale
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(box.x, 0.5), maxf(box.y, 0.5), maxf(box.z, 0.5))
	var wall := CollisionShape3D.new()
	wall.name = "Стіна"
	wall.shape = shape
	wall.position = Vector3(0, shape.size.y * 0.5, 0)
	body.add_child(wall)


## Розмір моделі: збираємо межі всіх мешів усередині.
static func _size_of(node: Node) -> Vector3:
	var box := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = child
		if mesh.mesh == null:
			continue
		var part := mesh.transform * mesh.mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box.size if not first else Vector3(4, 3, 4)


## Мешканець: капсула на своєму місці. Говорити він поки не вміє (П-113).
func _dweller(who: Dictionary) -> void:
	var body := NPC.new()
	body.name = "Мешканець-" + str(who.get("хто", "мешканець"))
	body.who = str(who.get("хто", "мешканець"))
	body.craft = str(who.get("ремесло", ""))
	body.tint = Color(str(who.get("колір", "#75706a")))
	body.position = _on_ground(_point(who["де"])) + Vector3(0, 1.0, 0)
	# Шар «мешканці» (третій, тобто 4): промінь миші шукає і його теж,
	# інакше клік по мешканцеві пролітає крізь нього — на цьому й
	# спіймався замовник під час першої ж проби.
	body.collision_layer = 4
	add_child(body)

	# Мешканці мають таке саме тіло, як гравці й монстри: голова, руки,
	# ноги. Стоять вони нерухомо, тож анімація в них лише «дихає».
	var figure := CreatureModel.new()
	figure.name = "Mesh"
	figure.tint = body.tint
	body.add_child(figure)
	figure.build()
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	shape.position = Vector3(0, 0.1, 0)
	body.add_child(shape)


## Ліс: дерева з розкидом по колу, кожне трохи іншої висоти.
func _forest() -> void:
	var wood: Dictionary = data.get("ліс", {})
	if wood.is_empty():
		return
	var center := _point(wood.get("центр", [0, 0, 0]))
	var radius := float(wood.get("радіус", 20))
	var heights: Array = wood.get("висота", [4.0, 8.0])
	for i in int(wood.get("дерев", 40)):
		var angle := randf() * TAU
		var far := radius * sqrt(randf())
		var at := _on_ground(center + Vector3(cos(angle) * far, 0.0,
				sin(angle) * far))
		_tree(at, randf_range(float(heights[0]), float(heights[1])),
				str(wood.get("стовбур", "#5b4632")),
				str(wood.get("крона", "#2f5e33")))


func _tree(where: Vector3, height: float, bark: String, leaves: String) -> void:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.22
	trunk.bottom_radius = 0.32
	trunk.height = height
	var shape := CylinderShape3D.new()
	shape.radius = 0.32
	shape.height = height
	_solid(where + Vector3(0, height * 0.5, 0), trunk, shape, bark, "Дерево")

	var crown := CylinderMesh.new()
	crown.top_radius = 0.0
	crown.bottom_radius = height * 0.42
	crown.height = height * 0.9
	var green := MeshInstance3D.new()
	green.name = _named("Крона")
	green.mesh = crown
	green.set_surface_override_material(0, _paint(leaves))
	green.position = where + Vector3(0, height + crown.height * 0.35, 0)
	add_child(green)


## Гори: конуси на краю світу. Через них не пройти — вони й є межа.
func _mountains() -> void:
	for hill: Dictionary in data.get("гори", []):
		var height := float(hill.get("висота", 20))
		var radius := float(hill.get("радіус", 15))
		var mesh := CylinderMesh.new()
		mesh.top_radius = radius * 0.06
		mesh.bottom_radius = radius
		mesh.height = height
		mesh.radial_segments = 12
		var shape := CylinderShape3D.new()
		shape.radius = radius * 0.7
		shape.height = height
		_solid(_on_ground(_point(hill["де"])) + Vector3(0, height * 0.5, 0),
				mesh, shape,
				str(hill.get("колір", "#6a6f74")), "Гора")


static func _point(from: Variant) -> Vector3:
	var list: Array = from
	return Vector3(float(list[0]), float(list[1]), float(list[2]))


## Туман по зоні бачення (П-65).
##
## Сервер шле лише те, що гравець бачить, — за межею просто порожнеча.
## Туман має ховати рівно цю межу: інакше або видно, як істоти
## з'являються з нізвідки, або туман з'їдає те, що ще видно.
func fog_to_vision(radius: float) -> void:
	if _air == null:
		return
	var spare: float = float(data.get("туман", {}).get("запас", 1.15))
	# Туман ЗА ВІДСТАННЮ, а не за щільністю: у нього є початок і кінець,
	# і кінець можна поставити рівно на межу бачення. Щільнісний туман
	# такого не вміє — перша спроба з ним залила все молоком уже за
	# п'ять кроків.
	_air.fog_mode = Environment.FOG_MODE_DEPTH
	_air.fog_depth_end = radius * spare
	_air.fog_depth_begin = _air.fog_depth_end * 0.45
	_air.fog_depth_curve = 1.4
	# Небо туман не чіпає: інакше зникає обрій, і світ стає коробкою.
	_air.fog_sky_affect = 0.25
