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
## Уся суша (не море) піднята на стільки за словом замовника 03.09.2026
## (П-140, число зменшено з 5 на 3 того ж вечора). Додається останнім,
## до вже готової форми рельєфу — самі числа шуму, підлоги над морем
## (П-138) і насипів (Cave, Forest) не чіпалися.
const LAND_LIFT := 3.0

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
	# Довкілля НЕ з неба (АРГБ синього #3f6ea8), а свій нейтральний колір:
	# земля в тіні дерев не бачить прямого сонця взагалі, і при небесному
	# джерелі вся тінь ставала синьо-сірою — зелений ґрунт (яким кольором
	# його не пофарбуй) тонув у синяві (П-138, тест у лісі 03.09.2026).
	air.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	air.ambient_light_color = Color("#c9cdb8")
	air.ambient_light_energy = 0.9
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


## Поверхня з крапом — замість текстури, якої в нас немає.
##
## У наборі є стіни, дахи й камінь, а землі й трави немає. Рівний колір
## без нічого читається саме так, як сказав замовник: «тіні від
## ландшафту є, а текстури немає» — бо її й справді немає, є заливка.
##
## Тому робимо свою: шум трипланарно поверх кольору. Трипланарно — щоб не
## розгортати UV на рельєфі, який будується кодом; `size` задає, через
## скільки метрів візерунок повторюється.
func _speckled(color: String, size: float, strength: float
		) -> StandardMaterial3D:
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(color)
	paint.roughness = 0.95
	var noise := FastNoiseLite.new()
	noise.seed = SEED
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	# Частота — у пікселях текстури, не в метрах. При 0,9 кожен піксель
	# уже незалежний, і з двох кроків це зливається в рівний тон — саме
	# так і вийшло з першої спроби. Потрібні плями на пів текстури.
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var grain := NoiseTexture2D.new()
	grain.noise = noise
	grain.width = 256
	grain.height = 256
	grain.seamless = true
	# Крап не має ставати плямами: зводимо його до вузької смуги біля
	# одиниці, інакше земля рябіє, як шкура далматинця.
	grain.color_ramp = Gradient.new()
	grain.color_ramp.set_color(0, Color(1, 1, 1) * (1.0 - strength))
	grain.color_ramp.set_color(1, Color(1, 1, 1))
	paint.albedo_texture = grain
	paint.uv1_triplanar = true
	paint.uv1_scale = Vector3.ONE / maxf(0.5, size)
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
		return LAND_LIFT
	# М'який перехід від міста до пагорбів: інакше на межі стіна.
	var edge: float = float(data.get("земля", {}).get("поле", 14))
	if far < _city_flat + edge:
		high *= (far - _city_flat) / edge

	# Підлога НАД морем, не РІВНО на морі (П-116, П-138): суша острова
	# ніколи не пірнає нижче моря сама собою — шум на розмаху 7,0 проти
	# моря −2,20 топив випадкові латки де завгодно (7% лісу, ціла гора), а
	# латання зона за зоною ганялось за краєм власного ж насипу (тест
	# 03.09.2026: за межею «поле» ефект згасає до нуля, латка вилазить
	# знову — «на обрії»). Запас 0,5 м навмисний: рівно на рівні моря
	# земля й вода лежать в одній площині, і напівпрозора вода поверх
	# співпадаючого ґрунту сама стає тією ж плямою, що й топлення (той
	# самий знімок лісу 03.09.2026 підтвердив — річка лишалась видна й
	# після підлоги рівно на -2,20). Справжнє море лишається морем — це
	# не зачіпає ні його, ні відкриту воду за краєм сітки 240×240 (там
	# `height_at` не рахує взагалі, землі там немає, лише сама площина).
	high = maxf(high, sea_level() + 0.5)

	# Підняті ділянки (П-116, П-138): де самої підлоги мало — окремий
	# майданчик чи насип поверх неї. Два способи: «до» — пласке плато на
	# фіксованій висоті (дно печери), «додати» — природний насип, що
	# зберігає хвилі шуму (лука має лишитись горбистою). Обидва плавно
	# згасають до звичайного рельєфу (уже не нижче моря) за межею «поле».
	for mound: Dictionary in earth.get("підняти", []):
		var center := Vector2(float(mound["де"][0]), float(mound["де"][2]))
		var r: float = float(mound.get("радіус", 10.0))
		var mound_edge: float = float(mound.get("поле", 6.0))
		var d: float = Vector2(x, z).distance_to(center)
		if d >= r + mound_edge:
			continue
		var t: float = 1.0 if d < r else 1.0 - (d - r) / mound_edge
		if mound.has("додати"):
			high += float(mound["додати"]) * t
		else:
			high = maxf(high, lerp(high, float(mound.get("до", 0.0)), t))
	return high + LAND_LIFT


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
	# Земля — найбільша поверхня у грі, і саме на ній рівний колір
	# найпомітніший. Візерунок через 12 метрів: дрібніше рябіє здалеку.
	view.set_surface_override_material(0,
			_speckled(str(earth.get("колір", "#4a5c3a")), 12.0, 0.22))
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
##
## Не нижче моря: шум рельєфу подекуди пірнає під рівень моря й поза
## пляжами (де сама земля цього не показує — вирівнювання діє тільки в
## місті), і все, що ставиться цією функцією, там просто тонуло б —
## заміряно 7% дерев лісу нижче -2,20 м і одну з чотирьох гір, чия основа
## опинялась під водою (той самий клас вади, що П-116, тільки для лісу й
## гір, а не для монстрів).
func _on_ground(point: Vector3) -> Vector3:
	var ground: float = maxf(height_at(point.x, point.z), sea_level())
	return Vector3(point.x, ground + point.y, point.z)


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
	# Брук — камінь, і візерунок на ньому має бути дрібніший за земляний.
	stone.set_surface_override_material(0,
			_speckled(str(city.get("колір бруку", "#6e6459")), 4.0, 0.30))
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

	var dwellers: Array = city.get("мешканці", [])
	for i in dwellers.size():
		_dweller(dwellers[i], i)

	_fence(_on_ground(center), float(city.get("радіус", 20)))


## Дерев'яний паркан по колу міста (Quaternius Medieval Village MegaKit,
## `models/village/`) — розширення світу 03.09.2026. Не фортеця з вежами
## й ворітьми: замовник просив просто паркан, **без воріт**, і вхід
## лишається вільним на всі чотири сторони світу (проходи по 6 м у
## північ/схід/південь/захід). Якщо моделі паркана немає на диску —
## просто нічого не будуємо: паркан — прикраса, не межа гри.
const FENCE_MODEL := "res://models/village/Prop_WoodenFence_Single.gltf"
## Довжина панелі, заміряно `probes/_measure_nature.gd` (разово): 2,0641 м.
const FENCE_PANEL := 2.0641
const FENCE_GATE_WIDTH := 6.0


func _fence(center: Vector3, radius: float) -> void:
	if not ResourceLoader.exists(FENCE_MODEL):
		return
	var scene: PackedScene = load(FENCE_MODEL)
	var count := int(TAU * radius / FENCE_PANEL)
	var gate_half: float = (FENCE_GATE_WIDTH / radius) * 0.5
	for i in count:
		var angle := TAU * i / count
		var at_gate := false
		for side in 4:
			if absf(wrapf(angle - side * PI * 0.5, -PI, PI)) < gate_half:
				at_gate = true
				break
		if at_gate:
			continue
		var at := center + Vector3(cos(angle), 0, sin(angle)) * radius
		var body := StaticBody3D.new()
		body.name = _named("Паркан")
		body.position = at
		# Панель дивиться вздовж дотичної до кола, тильною стороною назовні.
		body.rotation.y = angle + PI * 0.5
		add_child(body)
		var view: Node3D = scene.instantiate()
		view.name = "Модель"
		body.add_child(view)
		_no_shadows(view)
		var wall := CollisionShape3D.new()
		wall.name = "Стіна"
		var box := BoxShape3D.new()
		box.size = Vector3(FENCE_PANEL, 1.2, 0.3)
		wall.shape = box
		wall.position = Vector3(0, 0.6, 0)
		body.add_child(wall)


func _house(where: Vector3, size: Vector3, walls: String, roof: String) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var shape := BoxShape3D.new()
	shape.size = size
	var body := _solid(where + Vector3(0, size.y * 0.5, 0), mesh, shape, walls,
			"Будинок")

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

	# Дах теж має зіткнення — інакше камера проходить крізь нього так само,
	# як і в наборі кита (П-121, `ROOF_TOP` вище). Коробка замість піраміди:
	# грубіше за форму, зате камеру напевно не пропустить.
	var cap_shape := BoxShape3D.new()
	cap_shape.size = Vector3(cap.bottom_radius * 2.0, cap.height,
			cap.bottom_radius * 2.0)
	var cap_wall := CollisionShape3D.new()
	cap_wall.name = "Дах-стіна"
	cap_wall.shape = cap_shape
	cap_wall.position = Vector3(0, size.y * 0.5 + cap.height * 0.5, 0)
	body.add_child(cap_wall)


## Деталі набору Medieval Village MegaKit (Quaternius, CC0). Сітка в
## наборі стала: стіна 2 метри завширшки й 3,12 заввишки, підлога 2×2,
## дах на 4×4. Тому будинок описується в МОДУЛЯХ — «два на два», — а не
## в метрах: інакше довелось би підганяти числа руками під кожну деталь.
const WALL := "res://models/village/Wall_%s.gltf"
const ROOF_4X4 := "res://models/village/Roof_RoundTiles_4x4.gltf"
const FLOOR := "res://models/village/Floor_Brick.gltf"
const MODULE := 2.0        ## ширина однієї деталі, метрів
const WALL_HEIGHT := 3.12
## Дах ставиться на `WALL_HEIGHT + 0.5` і сам заміряний 4,25 м угору, дном
## на -0,52 від опорної точки (`probes/_measure_roof.gd`, разово) — тобто
## вершина опиняється на 3,62 + 3,73 = 7,35 м, далеко за стінами. Стара
## коробка зіткнення сягала лише WALL_HEIGHT, і камера проходила крізь дах
## наскрізь (П-121): дах узагалі не мав зіткнення.
const ROOF_TOP := 7.35
## Дах звисає за стіни: заміряно, разова деталь ширша за свою клітину
## модулів приблизно на 1,5 м — по 0,75 з кожного боку.
const ROOF_OVERHANG := 0.8


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

	# Крізь будинок не пускає одна коробка на весь обрис — і вона мусить
	# накривати ДАХ, а не спинятись на стінах (П-121, див. ROOF_TOP).
	var shape := BoxShape3D.new()
	shape.size = Vector3(wide * MODULE + ROOF_OVERHANG * 2.0, ROOF_TOP,
			deep * MODULE + ROOF_OVERHANG * 2.0)
	var wall := CollisionShape3D.new()
	wall.name = "Стіна"
	wall.shape = shape
	wall.position = Vector3(0, ROOF_TOP * 0.5, 0)
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


## Вимкнути тіні на всіх мешах усередині моделі. Заміряно 03.09.2026: із
## тінями від 70 дерев і паркану довкола міста показ ішов 1 кадр за
## секунду; дерева й скелі — прикраса на видноті, а не те, що кидає тінь
## на бій, тож вимикати безпечно.
static func _no_shadows(node: Node) -> void:
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = child
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


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


## Мешканець за номером. Сервер шукає ним того, з ким гравець говорить.
func resident_at(at: int) -> NPC:
	for child in get_children():
		if child is NPC and child.at_index == at:
			return child
	return null


## Мешканець: капсула на своєму місці. Крамар ще й торгує (П-132).
func _dweller(who: Dictionary, at: int) -> void:
	var body := NPC.new()
	body.name = "Мешканець-" + str(who.get("хто", "мешканець"))
	body.who = str(who.get("хто", "мешканець"))
	body.craft = str(who.get("ремесло", ""))
	body.at_index = at
	body.goods = who.get("товар", [])
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


## Справжні моделі (Quaternius Stylized Nature MegaKit, CC0,
## `models/nature/`) — розширення світу 03.09.2026. Якщо паку немає на
## диску, дерево лишається примітивом, як і раніше (той самий принцип,
## що й для будинків: гра має йти на чистій машині).
const TREE_MODELS := [
	"res://models/nature/CommonTree_1.gltf",
	"res://models/nature/CommonTree_2.gltf",
	"res://models/nature/CommonTree_3.gltf",
	"res://models/nature/Pine_1.gltf",
	"res://models/nature/Pine_2.gltf",
	"res://models/nature/Pine_3.gltf",
]
## Висота моделі дерева в наборі, заміряно (7,3…9,4 м) — беремо середню
## як опору для масштабу; свій розкид висот (`map.json`) лишається
## множником поверх неї.
const TREE_MODEL_HEIGHT := 8.0


func _tree(where: Vector3, height: float, bark: String, leaves: String) -> void:
	var body := StaticBody3D.new()
	body.name = _named("Дерево")
	body.position = where
	add_child(body)
	# Зіткнення — тонкий стовбур незалежно від того, є модель чи ні:
	# крона лишається прохідною, як і завжди.
	var wall := CollisionShape3D.new()
	wall.name = "Стіна"
	var shape := CylinderShape3D.new()
	shape.radius = 0.32
	shape.height = height
	wall.shape = shape
	wall.position = Vector3(0, height * 0.5, 0)
	body.add_child(wall)

	var model_path: String = TREE_MODELS[randi() % TREE_MODELS.size()]
	if ResourceLoader.exists(model_path):
		var view: Node3D = (load(model_path) as PackedScene).instantiate()
		view.name = "Модель"
		var scale := height / TREE_MODEL_HEIGHT
		view.scale = Vector3(scale, scale, scale)
		view.rotation.y = randf() * TAU
		body.add_child(view)
		_no_shadows(view)
		return

	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.22
	trunk.bottom_radius = 0.32
	trunk.height = height
	var trunk_view := MeshInstance3D.new()
	trunk_view.name = "Меш"
	trunk_view.mesh = trunk
	trunk_view.set_surface_override_material(0, _paint(bark))
	trunk_view.position = Vector3(0, height * 0.5, 0)
	body.add_child(trunk_view)

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


## Моделі скель для гір — той самий пак, що й дерева.
const MOUNTAIN_MODELS := [
	"res://models/nature/Rock_Medium_1.gltf",
	"res://models/nature/Rock_Medium_2.gltf",
	"res://models/nature/Rock_Medium_3.gltf",
]
## Висота моделі скелі в наборі, заміряно (1,9…2,3 м).
const ROCK_MODEL_HEIGHT := 2.3


## Гори: скелі на краю світу, підняті до потрібної висоти. Через них не
## пройти — вони й є межа.
func _mountains() -> void:
	for hill: Dictionary in data.get("гори", []):
		var height := float(hill.get("висота", 20))
		var radius := float(hill.get("радіус", 15))
		var body := StaticBody3D.new()
		body.name = _named("Гора")
		body.position = _on_ground(_point(hill["де"]))
		add_child(body)
		var wall := CollisionShape3D.new()
		wall.name = "Стіна"
		var shape := CylinderShape3D.new()
		shape.radius = radius * 0.7
		shape.height = height
		wall.shape = shape
		wall.position = Vector3(0, height * 0.5, 0)
		body.add_child(wall)

		var model_path: String = MOUNTAIN_MODELS[randi() % MOUNTAIN_MODELS.size()]
		if ResourceLoader.exists(model_path):
			var view: Node3D = (load(model_path) as PackedScene).instantiate()
			view.name = "Модель"
			var scale := height / ROCK_MODEL_HEIGHT
			view.scale = Vector3(scale, scale, scale)
			view.rotation.y = randf() * TAU
			body.add_child(view)
			_no_shadows(view)
			continue

		var mesh := CylinderMesh.new()
		mesh.top_radius = radius * 0.06
		mesh.bottom_radius = radius
		mesh.height = height
		mesh.radial_segments = 12
		var mesh_view := MeshInstance3D.new()
		mesh_view.name = "Меш"
		mesh_view.mesh = mesh
		mesh_view.set_surface_override_material(0,
				_paint(str(hill.get("колір", "#6a6f74"))))
		mesh_view.position = Vector3(0, height * 0.5, 0)
		body.add_child(mesh_view)


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
	# Туман починається не з половини відстані, а з двох третин: при 0,45
	# він з'їдав колір землі вже за двадцять чотири метри, і краєвид
	# виглядав як біла пляма з тінями.
	_air.fog_depth_begin = _air.fog_depth_end * 0.66
	_air.fog_depth_curve = 1.4
	# Небо туман не чіпає: інакше зникає обрій, і світ стає коробкою.
	_air.fog_sky_affect = 0.25
