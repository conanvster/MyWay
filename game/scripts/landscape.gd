class_name Landscape
extends Node3D
## Краєвид: земля, місто з будинками й мешканцями, ліс, гори.
##
## Будується кодом за числами з `дані/мапа.json`. Чому не руками в
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
	air.fog_light_color = Color("#a8b6c2")
	air.fog_density = 0.0025

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


func _ground() -> void:
	var side: float = float(data.get("земля", {}).get("сторона", 240))
	var mesh := BoxMesh.new()
	mesh.size = Vector3(side, 1, side)
	var shape := BoxShape3D.new()
	shape.size = mesh.size
	_solid(Vector3(0, -0.5, 0), mesh, shape,
			str(data.get("земля", {}).get("колір", "#4a5c3a")), "Земля")


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
	stone.position = center + Vector3(0, 0.06, 0)
	add_child(stone)

	for house: Dictionary in city.get("будинки", []):
		_house(_point(house["де"]), _point(house["розмір"]),
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


## Мешканець: капсула на своєму місці. Говорити він поки не вміє (П-113).
func _dweller(who: Dictionary) -> void:
	var body := NPC.new()
	body.name = "Мешканець-" + str(who.get("хто", "мешканець"))
	body.who = str(who.get("хто", "мешканець"))
	body.craft = str(who.get("ремесло", ""))
	body.tint = Color(str(who.get("колір", "#75706a")))
	body.position = _point(who["де"]) + Vector3(0, 1.0, 0)
	# Шар «мешканці» (третій, тобто 4): промінь миші шукає і його теж,
	# інакше клік по мешканцеві пролітає крізь нього — на цьому й
	# спіймався замовник під час першої ж проби.
	body.collision_layer = 4
	add_child(body)

	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = CapsuleMesh.new()
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	body.add_child(shape)
	body.repaint()


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
		var at := center + Vector3(cos(angle) * far, 0.0, sin(angle) * far)
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
		_solid(_point(hill["де"]) + Vector3(0, height * 0.5, 0), mesh, shape,
				str(hill.get("колір", "#6a6f74")), "Гора")


static func _point(from: Variant) -> Vector3:
	var list: Array = from
	return Vector3(float(list[0]), float(list[1]), float(list[2]))
