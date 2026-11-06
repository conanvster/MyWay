class_name TownLook
## Міста й села світу 2 як на мапі (план §3г, П-271).
##
## Слово замовника 17.10.2026: «зібрати міста та села як це зображено на
## мапі»; 18.10.2026: «приймаю рекомендацію по П-271 (П-142 було для світу
## 1), збирай міста». Розкладку — мур, брами, вулиці, донжон, доми — пише
## `tools/svit2.py --поселення` у `map2.json`; тут лише будується.
##
## - мур — ланки між кутами з зубцями, башта в кожному куті, брама без
##   стулок там, де підходить дорога (прохід вільний, П-271);
## - вулиці й площа — бруківка; донжон — між вулицями;
## - доми — модулі Quaternius, але з фото-текстурами (Poly Haven, CC0,
##   `models/town/`, `tools/mista_aseti.py`) за назвою матеріалу модуля,
##   трипланарно у світових координатах — UV модулів під фото не годяться;
##   дах один на весь дім, фронтони закриті, у вікнах рами;
## - села — хати під стріхою вздовж стежки, тин за хатою.
##
## Серверові — лише зіткнення: мур, башти, брами, донжон, коробки домів.

const TOWN := "res://models/town/"
const KIT := "res://models/village/%s.gltf"
const MODULE := 2.0
const WALL_HEIGHT := 3.12
## Дах стоїть на цій висоті (як у `Landscape._kit_house`).
const ROOF_AT := WALL_HEIGHT + 0.5
const WALL_HIGH := 6.0
const WALL_THICK := 1.6
const GATE_WIDE := 6.0
## Ширина бруківки: фасади вздовж вулиць стоять за 3,7 м від її осі
## (`svit2.py --поселення`), тож 5 м лишали смугу трави 1,2 м під стіною
## (заміряно 06.11.2026 по Стільній і Крайній Брамі).
const STREET_WIDE := 7.6
const TOWER_R := 2.8
const TOWER_HIGH := 10.0
const KEEP_HIGH := 18.0
## Далі цього місто не малюється: туман однаково ховає, а домів сотні.
const SEEN := 650.0

## Фото-текстура за роллю.
const WALLS := {
	"штукатурка": "plastered_wall_02", "фахверк": "plastered_wall_02",
	"цегла": "medieval_red_brick", "стара": "worn_mossy_plasterwall",
	"мазанка": "clay_plaster",
}
const ROOFS := {
	"черепиця": "clay_roof_tiles_02", "сланець": "roof_slates_03",
	"стріха": "thatch_roof_angled", "очерет": "reed_roof_04",
}

static var _paints: Dictionary = {}
static var _roof_boxes: Dictionary = {}


static func build(land: Landscape, place: Dictionary) -> void:
	var shown := DisplayServer.get_name() != "headless"
	var holder := Node3D.new()
	holder.name = land._named("Поселення")
	land.add_child(holder)
	if place.has("мур"):
		_wall(land, holder, place, shown)
		_keep(land, holder, place, shown)
		if shown:
			_streets(land, holder, place)
	elif shown and place.has("стежка"):
		var line: Array = place["стежка"]
		_strip(land, holder, Vector2(line[0][0], line[0][1]),
				Vector2(line[1][0], line[1][1]), 3.0, _dirt())
	for house: Dictionary in place.get("будинки", []):
		_house(land, holder, house, shown)
	if shown:
		_far(holder)


## Фото-матеріал: ORM — це `arm` Poly Haven (AO, шорсткість, метал).
static func paint(name: String, tile: float = 2.5) -> ORMMaterial3D:
	var key := "%s:%.1f" % [name, tile]
	if not _paints.has(key):
		var made := ORMMaterial3D.new()
		made.albedo_texture = load(TOWN + name + "_diff.jpg")
		made.normal_enabled = true
		made.normal_texture = load(TOWN + name + "_nor_gl.jpg")
		made.orm_texture = load(TOWN + name + "_arm.jpg")
		made.uv1_triplanar = true
		made.uv1_world_triplanar = true
		made.uv1_scale = Vector3.ONE / tile
		_paints[key] = made
	return _paints[key]


## Ґрунт стежки села — той самий шар, що й стежки землі (Ground039).
static func _dirt() -> StandardMaterial3D:
	if not _paints.has("стежка"):
		var made := StandardMaterial3D.new()
		made.albedo_texture = load("res://models/ground/Ground039_Color.jpg")
		made.normal_enabled = true
		made.normal_texture = load("res://models/ground/Ground039_Normal.jpg")
		made.roughness = 0.95
		made.uv1_triplanar = true
		made.uv1_world_triplanar = true
		made.uv1_scale = Vector3.ONE / 3.0
		_paints["стежка"] = made
	return _paints["стежка"]


static func _far(node: Node) -> void:
	for child in node.find_children("*", "GeometryInstance3D", true, false):
		(child as GeometryInstance3D).visibility_range_end = SEEN


# ───────────────────────────── мур ──────────────────────────────────

static func _wall(land: Landscape, holder: Node3D, place: Dictionary,
		shown: bool) -> void:
	var corners: Array[Vector2] = []
	for p: Array in place["мур"]:
		corners.append(Vector2(float(p[0]), float(p[1])))
	var stone := paint("castle_wall_slates" if str(place.get("мур камінь",
			"")) == "сланець" else "castle_wall_varriation", 3.0)
	var gates_on := {}
	for gate: Dictionary in place.get("брами", []):
		var at: Array = gate["де"]
		gates_on.get_or_add(int(gate["ребро"]), []).append(
				Vector2(float(at[0]), float(at[1])))
	var teeth: Array[Transform3D] = []
	for k in corners.size():
		var a := corners[k]
		var b := corners[(k + 1) % corners.size()]
		var along := (b - a).normalized()
		# Ланки між брамами цього ребра, від башти до башти (без їхнього тіла).
		var cuts: Array[float] = [TOWER_R * 0.8]
		var gates: Array = gates_on.get(k, [])
		gates.sort_custom(func(p: Vector2, q: Vector2) -> bool:
			return a.distance_to(p) < a.distance_to(q))
		for g: Vector2 in gates:
			var t := a.distance_to(g)
			cuts.append(t - GATE_WIDE * 0.5 - 0.7)
			cuts.append(t + GATE_WIDE * 0.5 + 0.7)
			_gate(land, holder, g, along, shown)
		cuts.append(a.distance_to(b) - TOWER_R * 0.8)
		for i in range(0, cuts.size(), 2):
			if cuts[i + 1] - cuts[i] > 0.5:
				_wall_piece(land, holder, a + along * cuts[i],
						a + along * cuts[i + 1], stone, shown, teeth)
		_tower(land, holder, a, stone, shown)
	if shown and not teeth.is_empty():
		var tooth := BoxMesh.new()
		tooth.size = Vector3(0.9, 0.9, WALL_THICK * 0.35)
		var many := MultiMesh.new()
		many.transform_format = MultiMesh.TRANSFORM_3D
		many.mesh = tooth
		many.instance_count = teeth.size()
		for i in teeth.size():
			many.set_instance_transform(i, teeth[i])
		var view := MultiMeshInstance3D.new()
		view.name = "Зубці"
		view.multimesh = many
		view.material_override = stone
		holder.add_child(view)


## Земля під відрізком: нижча й вища з трьох точок.
static func _ground_span(land: Landscape, a: Vector2, b: Vector2) -> Vector2:
	var low := INF
	var high := -INF
	for t: float in [0.0, 0.5, 1.0]:
		var p := a.lerp(b, t)
		var y := land.surface_y(p.x, p.y)
		low = minf(low, y)
		high = maxf(high, y)
	return Vector2(low, high)


static func _wall_piece(land: Landscape, holder: Node3D, a: Vector2,
		b: Vector2, stone: Material, shown: bool,
		teeth: Array[Transform3D]) -> void:
	var span := _ground_span(land, a, b)
	var base := span.x - 0.6
	var top := span.y + WALL_HIGH
	var long := a.distance_to(b)
	var mid := (a + b) * 0.5
	var turn := -atan2(b.y - a.y, b.x - a.x)
	var size := Vector3(long, top - base, WALL_THICK)
	var body := _solid(holder, "Мур", Vector3(mid.x, base + size.y * 0.5,
			mid.y), turn, size, stone if shown else null)
	if not shown:
		return
	# Зубці по зовнішньому й внутрішньому краю, через один.
	var count := int(long / 1.8)
	for i in count:
		if i % 2 == 1:
			continue
		var t := (i + 0.5) / count - 0.5
		for side: float in [-1.0, 1.0]:
			var local := Vector3(t * long, size.y * 0.5 + 0.45,
					side * WALL_THICK * 0.32)
			teeth.append(body.global_transform * Transform3D(Basis(), local))


static func _tower(land: Landscape, holder: Node3D, at: Vector2,
		stone: Material, shown: bool) -> void:
	var ground := land.surface_y(at.x, at.y)
	var body := StaticBody3D.new()
	body.name = land._named("Башта")
	body.position = Vector3(at.x, ground - 0.6, at.y)
	holder.add_child(body)
	var round := CylinderShape3D.new()
	round.radius = TOWER_R
	round.height = TOWER_HIGH
	var wall := CollisionShape3D.new()
	wall.shape = round
	wall.position.y = TOWER_HIGH * 0.5
	body.add_child(wall)
	if not shown:
		return
	var tube := CylinderMesh.new()
	tube.top_radius = TOWER_R * 0.94
	tube.bottom_radius = TOWER_R
	tube.height = TOWER_HIGH
	tube.radial_segments = 16
	var view := MeshInstance3D.new()
	view.mesh = tube
	view.material_override = stone
	view.position.y = TOWER_HIGH * 0.5
	body.add_child(view)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = TOWER_R * 1.18
	cone.height = 4.2
	cone.radial_segments = 16
	var cap := MeshInstance3D.new()
	cap.mesh = cone
	cap.material_override = paint("roof_slates_03", 2.0)
	cap.position.y = TOWER_HIGH + 2.1
	body.add_child(cap)


## Брама: два стовпи й перемичка тесаного каменю, прохід вільний.
static func _gate(land: Landscape, holder: Node3D, at: Vector2,
		along: Vector2, shown: bool) -> void:
	var ground := land.surface_y(at.x, at.y)
	var turn := -atan2(along.y, along.x)
	var cut := paint("medieval_blocks_03", 3.0) if shown else null
	var pillar := Vector3(1.4, 8.6, WALL_THICK + 1.0)
	for side: float in [-1.0, 1.0]:
		var p := at + along * side * (GATE_WIDE * 0.5 + pillar.x * 0.5)
		_solid(holder, "Брама", Vector3(p.x, ground - 0.6 + pillar.y * 0.5,
				p.y), turn, pillar, cut)
	_solid(holder, "Брама", Vector3(at.x, ground + 6.6, at.y), turn,
			Vector3(GATE_WIDE + pillar.x * 2.0, 2.2, pillar.z), cut)


## Тіло з коробкою-зіткненням і, якщо є матеріал, коробкою-виглядом.
static func _solid(holder: Node3D, word: String, center: Vector3,
		turn: float, size: Vector3, look: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = word
	body.position = center
	body.rotation.y = turn
	holder.add_child(body)
	var box := BoxShape3D.new()
	box.size = size
	var wall := CollisionShape3D.new()
	wall.shape = box
	body.add_child(wall)
	if look != null:
		var mesh := BoxMesh.new()
		mesh.size = size
		var view := MeshInstance3D.new()
		view.mesh = mesh
		view.material_override = look
		body.add_child(view)
	return body


static func _keep(land: Landscape, holder: Node3D, place: Dictionary,
		shown: bool) -> void:
	var keep: Dictionary = place.get("донжон", {})
	if keep.is_empty():
		return
	var at: Array = keep["де"]
	var p := Vector2(float(at[0]), float(at[1]))
	var side := float(keep.get("бік", 12.0))
	var low := INF
	for dx: float in [-0.5, 0.5]:
		for dz: float in [-0.5, 0.5]:
			low = minf(low, land.surface_y(p.x + dx * side, p.y + dz * side))
	var stone := paint("medieval_blocks_03", 3.5) if shown else null
	var body := _solid(holder, "Донжон", Vector3(p.x, low - 0.6
			+ KEEP_HIGH * 0.5, p.y), deg_to_rad(float(keep.get("поворот",
			0.0))), Vector3(side, KEEP_HIGH, side), stone)
	if not shown:
		return
	for i in 6:
		var t := -side * 0.5 + 0.6 + i * (side - 1.2) / 5.0
		for edge: Vector3 in [Vector3(t, 0, side * 0.5 - 0.4),
				Vector3(t, 0, -side * 0.5 + 0.4),
				Vector3(side * 0.5 - 0.4, 0, t),
				Vector3(-side * 0.5 + 0.4, 0, t)]:
			var tooth := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.9, 1.1, 0.9)
			tooth.mesh = box
			tooth.material_override = stone
			tooth.position = edge + Vector3(0, KEEP_HIGH * 0.5 + 0.55, 0)
			body.add_child(tooth)


# ──────────────────────── вулиці й стежки ───────────────────────────

static func _streets(land: Landscape, holder: Node3D, place: Dictionary) -> void:
	var stones := paint("cobblestone_floor_08", 2.0)
	for line: Array in place.get("вулиці", []):
		_strip(land, holder, Vector2(line[0][0], line[0][1]),
				Vector2(line[1][0], line[1][1]), STREET_WIDE, stones)
	var c: Array = place["центр"]
	# Зламів вулиць (кільце, провулки) — кругла латка бруку, щоб не було
	# щілини між двома смугами.
	var ends := {}
	for line: Array in place.get("вулиці", []):
		for p: Array in line:
			var key := "%.1f:%.1f" % [float(p[0]), float(p[1])]
			ends[key] = int(ends.get(key, 0)) + 1
	for key: String in ends:
		if int(ends[key]) < 2:
			continue
		var xy := key.split(":")
		var joint := CylinderMesh.new()
		joint.top_radius = STREET_WIDE * 0.5
		joint.bottom_radius = joint.top_radius
		joint.height = 0.1
		joint.radial_segments = 16
		var cap := MeshInstance3D.new()
		cap.mesh = joint
		cap.material_override = stones
		var jx := float(xy[0])
		var jz := float(xy[1])
		cap.position = Vector3(jx, land.surface_y(jx, jz) + 0.005, jz)
		cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(cap)
	var reach := float(place.get("площа", 16.0))
	var square: PrimitiveMesh
	if str(place.get("площа форма", "")) == "квадратна":
		var box := BoxMesh.new()
		box.size = Vector3(reach * 1.8, 0.12, reach * 1.8)
		square = box
	else:
		var disc := CylinderMesh.new()
		disc.top_radius = reach
		disc.bottom_radius = reach
		disc.height = 0.12
		disc.radial_segments = 48
		square = disc
	var view := MeshInstance3D.new()
	view.name = "Площа"
	view.mesh = square
	var gates: Array = place.get("брами", [])
	if not gates.is_empty():
		var g: Array = gates[0]["де"]
		view.rotation.y = -atan2(float(g[1]) - float(c[2]),
				float(g[0]) - float(c[0]))
	view.material_override = paint("stone_pathway_02", 3.0)
	view.position = Vector3(float(c[0]), land.surface_y(float(c[0]),
			float(c[2])) + 0.02, float(c[2]))
	holder.add_child(view)


## Смуга на землі: вулиця чи стежка. Без зіткнення — по ній ходять.
static func _strip(land: Landscape, holder: Node3D, a: Vector2, b: Vector2,
		wide: float, look: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(a.distance_to(b), 0.1, wide)
	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.material_override = look
	var mid := (a + b) * 0.5
	view.position = Vector3(mid.x, land.surface_y(mid.x, mid.y) + 0.0, mid.y)
	view.rotation.y = -atan2(b.y - a.y, b.x - a.x)
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(view)


# ───────────────────────────── доми ─────────────────────────────────

## Дім із модулів: стіни за стилем, один дах, фронтони, рами, комин.
## `модулі` — [уздовж фасаду (x), углиб (z)]; перед — локальне +z.
static func _house(land: Landscape, holder: Node3D, house: Dictionary,
		shown: bool) -> void:
	var at: Array = house["де"]
	var where := Vector3(float(at[0]), 0, float(at[2]))
	where.y = land.surface_y(where.x, where.z)
	var body := StaticBody3D.new()
	body.name = land._named("Будинок")
	body.position = where
	body.rotation.y = deg_to_rad(float(house.get("поворот", 0.0)))
	holder.add_child(body)
	if house.has("вид"):
		civic_body(body, house, shown)
	else:
		house_body(body, house, shown)


## Сам дім у власних координатах (перед — +z): без землі й світу, щоб
## проба `town_house` могла зняти його окремо.
static func house_body(body: Node3D, house: Dictionary, shown: bool) -> void:
	var size: Array = house.get("модулі", [2, 2])
	var wide := int(size[0])
	var deep := int(size[1])
	var across := mini(wide, deep)
	var lengthwise := maxi(wide, deep)
	var roof_path := KIT % ("Roof_RoundTiles_%dx%d" % [across * 2,
			lengthwise * 2])
	var roof_box := _roof_box(roof_path)
	# Поверхи (ратуша, гільдія, дзвіниця): ті самі модулі ще раз згори.
	var floors := maxi(1, int(house.get("поверхи", 1)))
	var lift := (floors - 1) * WALL_HEIGHT
	var open_front := bool(house.get("відкрито", false))
	var peak := ROOF_AT + lift + roof_box.end.y
	var shape := BoxShape3D.new()
	shape.size = Vector3(wide * MODULE + 1.2, peak, deep * MODULE + 1.2)
	var wall := CollisionShape3D.new()
	wall.shape = shape
	wall.position.y = peak * 0.5
	body.add_child(wall)
	if not shown:
		return
	var style := str(house.get("стіни", "штукатурка"))
	var brick := style == "цегла"
	var kind := "UnevenBrick" if brick else "Plaster"
	var straight := KIT % ("Wall_%s_Straight" % kind)
	if style == "фахверк":
		straight = KIT % "Wall_Plaster_WoodGrid"
	var window := KIT % ("Wall_%s_Window_Wide_Round" % kind)
	var door := KIT % ("Wall_%s_Door_Round" % kind)
	var frame := KIT % "Window_Wide_Round1"
	var half_x := (wide - 1) * MODULE * 0.5
	var half_z := (deep - 1) * MODULE * 0.5
	var edge_x := wide * MODULE * 0.5
	var edge_z := deep * MODULE * 0.5
	# Лице модуля набору — його +z (цоколь, балки, рами); зворот — гладка
	# штукатурка. Перед стояв на 180°, зад на 0° — обидва лицем усередину,
	# і з вулиці було видно голу внутрішню стіну (знайдено 06.11.2026).
	var pieces: Array = []
	var no_door := bool(house.get("без дверей", false))
	for f in floors:
		var y := f * WALL_HEIGHT
		for i in wide:
			var x := -half_x + i * MODULE
			var front := door if i == wide / 2 and f == 0 and not no_door \
					else window
			if not open_front:
				pieces.append([front, Vector3(x, y, edge_z), 0.0])
			pieces.append([window if i % 2 == 1 else straight,
					Vector3(x, y, -edge_z), 180.0])
		if open_front:
			continue
		for i in deep:
			var z := -half_z + i * MODULE
			pieces.append([window if i % 2 == 0 else straight,
					Vector3(-edge_x, y, z), 270.0])
			pieces.append([straight, Vector3(edge_x, y, z), 90.0])
	# Віконниці й двері — від місця дому, щоб сусіди різнились, а той
	# самий дім виглядав однаково в кожного гравця.
	var luck := hash(house.get("де", [0, 0, 0]))
	var door_leaf: String = KIT % ["Door_1_Round", "Door_2_Round",
			"Door_4_Round"][absi(luck) % 3]
	var shutters: String = ["", "WindowShutters_Wide_Round_Open",
			"WindowShutters_Wide_Round_Closed"][absi(luck >> 3) % 3]
	var k := 0
	for one: Array in pieces:
		_piece(body, one[0], one[1], one[2])
		if one[0] == window:
			_piece(body, frame, one[1], one[2])
			k += 1
			if shutters != "" and (k + absi(luck)) % 2 == 0:
				_piece(body, KIT % shutters, one[1], one[2])
		elif one[0] == door:
			# Стулка на завісі зліва від отвору, у товщі стіни.
			_piece(body, door_leaf, one[1] + Vector3(-0.535, 0, -0.08),
					one[2])
			_piece(body, KIT % "DoorFrame_Round_WoodDark", one[1], one[2])
			_doorstep(body, one[1])
	# Кути: між торцями модулів лишалась щілина на товщину лиця.
	for f in floors:
		for cx: float in [-edge_x, edge_x]:
			for cz: float in [-edge_z, edge_z]:
				_piece(body, KIT % "Corner_Exterior_Wood",
						Vector3(cx, f * WALL_HEIGHT, cz), 0.0)
	if open_front:
		# Навіс: передні стовпи до самого даху.
		for cx: float in [-edge_x, edge_x]:
			_post(body, Vector3(cx, 0, edge_z), WALL_HEIGHT + 0.6)
	# Дах: гребінь уздовж довшого боку (у наборі — уздовж z).
	var roof_turn := 90.0 if wide > deep else 0.0
	_piece(body, roof_path, Vector3(0, ROOF_AT + lift, 0), roof_turn)
	var wall_paint := paint(WALLS.get(style, "plastered_wall_02"), 2.0)
	if not open_front:
		_gables(body, roof_box, across, lengthwise, roof_turn, wall_paint,
				lift)
	if bool(house.get("комин", false)):
		var x := across * MODULE * 0.25
		var roof_y := ROOF_AT + lift + roof_box.end.y \
				- roof_box.size.y * (x / (roof_box.size.x * 0.5))
		var spot := Vector3(x, roof_y - 2.2, lengthwise * MODULE * 0.2)
		if roof_turn != 0.0:
			spot = Vector3(spot.z, spot.y, -spot.x)
		_piece(body, KIT % "Prop_Chimney", spot, 0.0)
	_swap(body, style, str(house.get("дах", "черепиця")))
	if bool(house.get("тин", false)):
		_wattle(body, Vector3(0, 0, -edge_z - 2.6), wide * MODULE + 5.0)
	for child in body.find_children("*", "MeshInstance3D", true, false):
		(child as MeshInstance3D).cast_shadow = \
				GeometryInstance3D.SHADOW_CASTING_SETTING_OFF \
				if child.name.begins_with("Тин") else \
				GeometryInstance3D.SHADOW_CASTING_SETTING_ON


static func _piece(parent: Node3D, path: String, at: Vector3,
		turn: float) -> void:
	if not ResourceLoader.exists(path):
		push_warning("[місто] нема деталі %s" % path)
		return
	var part: Node3D = (load(path) as PackedScene).instantiate()
	part.position = at
	part.rotation.y = deg_to_rad(turn)
	parent.add_child(part)


## Коробка даху в його власних координатах (заміряна раз на деталь).
static func _roof_box(path: String) -> AABB:
	if _roof_boxes.has(path):
		return _roof_boxes[path]
	var box := AABB(Vector3(-2.76, -0.52, -2.74), Vector3(5.51, 4.25, 5.56))
	if ResourceLoader.exists(path):
		var made: Node3D = (load(path) as PackedScene).instantiate()
		var first := true
		for child in made.find_children("*", "MeshInstance3D", true, false):
			var view: MeshInstance3D = child
			var part := view.transform * view.mesh.get_aabb()
			box = part if first else box.merge(part)
			first = false
		made.free()
	_roof_boxes[path] = box
	return box


## Фронтони: п'ятикутник під дахом на обох торцях — у наборі торець
## даху відкритий, і крізь нього видно небо.
static func _gables(body: Node3D, roof: AABB, across: int, lengthwise: int,
		turn: float, look: Material, lift: float = 0.0) -> void:
	var a := across * MODULE * 0.5
	var half := roof.size.x * 0.5
	var top := WALL_HEIGHT + lift
	var eave := ROOF_AT + lift + roof.position.y
	var peak := ROOF_AT + lift + roof.end.y - 0.4
	var side_y := maxf(top, peak - (peak + 0.4 - eave) * (a / half))
	var outline: Array[Vector2] = [Vector2(-a, top - 0.05),
			Vector2(a, top - 0.05), Vector2(a, side_y),
			Vector2(0, peak), Vector2(-a, side_y)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for end: float in [-1.0, 1.0]:
		var z := end * (lengthwise * MODULE * 0.5 - 0.12)
		for i in range(1, outline.size() - 1):
			var tri := [outline[0], outline[i], outline[i + 1]]
			# Обидва боки: зсередини теж не має світитись.
			for order: Array in [[0, 1, 2], [0, 2, 1]]:
				for k: int in order:
					st.add_vertex(Vector3(tri[k].x, tri[k].y, z))
	st.generate_normals()
	var view := MeshInstance3D.new()
	view.name = "Фронтони"
	view.mesh = st.commit()
	view.material_override = look
	view.rotation.y = deg_to_rad(turn)
	body.add_child(view)


## Підміна мультяшних текстур набору фото за назвою матеріалу.
static func _swap(body: Node3D, style: String, roof: String) -> void:
	var wall_paint := paint(WALLS.get(style, "plastered_wall_02"), 2.0)
	var table := {
		"MI_Plaster": wall_paint if style != "цегла"
				else paint("plastered_wall_02", 2.0),
		"MI_UnevenBrick": paint("medieval_red_brick", 2.0),
		"MI_Brick": paint("medieval_red_brick", 1.5),
		"MI_RedBrick": paint("medieval_red_brick", 1.5),
		"MI_RockTrim": paint("medieval_blocks_03", 2.0),
		"MI_WoodTrim": paint("dark_wooden_planks", 1.5),
		"MI_WoodTrim_Wear": paint("weathered_planks", 1.5),
		"MI_MetalOrnaments": _iron(),
		"MI_RoundTiles": paint(ROOFS.get(roof, "clay_roof_tiles_02"),
				3.0 if roof in ["черепиця", "сланець"] else 4.0),
	}
	for child in body.find_children("*", "MeshInstance3D", true, false):
		var view: MeshInstance3D = child
		if view.name == "Фронтони":
			continue
		for s in view.mesh.get_surface_count():
			var was: Material = view.mesh.surface_get_material(s)
			if was != null and table.has(was.resource_name):
				view.set_surface_override_material(s, table[was.resource_name])


# ──────────────────── будівлі площі (06.11.2026) ─────────────────────
# Слово замовника 06.11.2026: «міста повинні мати ратушу та церкву, а також
# невеличку площу, кузню, магазин з прилавком та гільдію, біля яких будуть
# відповідні npc». Місця й мешканців ставить `tools/svit2.py --поселення`;
# тут — лише вигляд. Перед будівлі — локальне +z, до площі.

const RECHI := "res://models/town/rechi/%s/%s_1k.gltf"
## Кольори корогв: міські (ратуша) і цехові (гільдія).
const BANNER_TOWN := Color(0.55, 0.12, 0.1)
const BANNER_GUILD := Color(0.12, 0.22, 0.45)


static func civic_body(body: Node3D, house: Dictionary, shown: bool) -> void:
	var kind := str(house.get("вид", ""))
	var size: Array = house.get("модулі", [3, 3])
	var edge_x := int(size[0]) * MODULE * 0.5
	var edge_z := int(size[1]) * MODULE * 0.5
	match kind:
		"ратуша":
			var hall := house.duplicate()
			hall["поверхи"] = 2
			hall["стіни"] = "цегла"
			house_body(body, hall, shown)
			if shown:
				for side: float in [-1.0, 1.0]:
					_banner(body, Vector3(side * (edge_x - 1.2), 5.4,
							edge_z + 0.25), BANNER_TOWN)
				_lamp(body, Vector3(0, 2.9, edge_z + 0.35))
		"гільдія":
			var hall := house.duplicate()
			hall["поверхи"] = 2
			house_body(body, hall, shown)
			if shown:
				_banner(body, Vector3(0, 5.4, edge_z + 0.25), BANNER_GUILD)
		"церква":
			# Нава [ш, г-1] позаду, дзвіниця 2×2 на три поверхи — спереду,
			# наполовину поза навою.
			var nave_part := StaticBody3D.new()
			nave_part.position = Vector3(0, 0, -MODULE * 0.5)
			body.add_child(nave_part)
			house_body(nave_part, {"модулі": [int(size[0]), int(size[1]) - 1],
					"стіни": "цегла", "дах": "сланець", "без дверей": true,
					"де": house.get("де")}, shown)
			var tower := StaticBody3D.new()
			tower.position = Vector3(0, 0, edge_z - MODULE)
			body.add_child(tower)
			_bell_tower(tower, house, shown)
		"кузня":
			var shed := house.duplicate()
			shed["відкрито"] = true
			shed["стіни"] = "цегла"
			house_body(body, shed, shown)
			if shown:
				_forge(body, Vector3(-edge_x + 1.3, 0, -edge_z + 1.3))
				_anvil(body, Vector3(0.6, 0, edge_z - 1.2))
				_prop(body, "wooden_bucket_01", Vector3(1.7, 0, edge_z - 0.6))
				_prop(body, "wine_barrel_01", Vector3(edge_x - 0.8, 0,
						-edge_z + 0.9))
		"крамниця":
			house_body(body, house, shown)
			if shown:
				_counter(body, Vector3(0, 0, edge_z + 1.9), edge_x * 1.4)
				_prop(body, "wooden_crate_01", Vector3(-edge_x + 0.6, 0,
						edge_z + 1.1))
				_prop(body, "wine_barrel_01", Vector3(edge_x - 0.5, 0,
						edge_z + 1.0))
		_:
			house_body(body, house, shown)
			if shown and kind == "комора":
				_prop(body, "wooden_crate_02", Vector3(-edge_x + 0.6, 0,
						edge_z + 0.8))
				_prop(body, "wooden_crate_01", Vector3(-edge_x + 1.5, 0,
						edge_z + 0.7))


## Дзвіниця: три поверхи модулів 2×2, шатро зі сланцю і хрест.
static func _bell_tower(tower: Node3D, house: Dictionary, shown: bool) -> void:
	var floors := 3
	var top := floors * WALL_HEIGHT
	var shape := BoxShape3D.new()
	shape.size = Vector3(2 * MODULE + 0.6, top, 2 * MODULE + 0.6)
	var hit := CollisionShape3D.new()
	hit.shape = shape
	hit.position.y = top * 0.5
	tower.add_child(hit)
	if not shown:
		return
	var straight := KIT % "Wall_UnevenBrick_Straight"
	var window := KIT % "Wall_UnevenBrick_Window_Wide_Round"
	var door := KIT % "Wall_UnevenBrick_Door_Round"
	for f in floors:
		var y := f * WALL_HEIGHT
		for i in 2:
			var t := -MODULE * 0.5 + i * MODULE
			var front := door if f == 0 and i == 0 else (
					window if f > 0 else straight)
			_piece(tower, front, Vector3(t, y, MODULE), 0.0)
			_piece(tower, window if f == 2 else straight,
					Vector3(t, y, -MODULE), 180.0)
			_piece(tower, window if f == 2 else straight,
					Vector3(-MODULE, y, t), 270.0)
			_piece(tower, window if f == 2 else straight,
					Vector3(MODULE, y, t), 90.0)
		for cx: float in [-MODULE, MODULE]:
			for cz: float in [-MODULE, MODULE]:
				_piece(tower, KIT % "Corner_Exterior_Wood",
						Vector3(cx, y, cz), 0.0)
	_piece(tower, KIT % "Door_4_Round", Vector3(-MODULE * 0.5 - 0.535, 0,
			MODULE - 0.08), 0.0)
	_piece(tower, KIT % "DoorFrame_Round_WoodDark",
			Vector3(-MODULE * 0.5, 0, MODULE), 0.0)
	_doorstep(tower, Vector3(-MODULE * 0.5, 0, MODULE))
	var roof := CylinderMesh.new()
	roof.top_radius = 0.0
	roof.bottom_radius = MODULE * 1.55
	roof.height = 5.5
	roof.radial_segments = 4
	var cap := MeshInstance3D.new()
	cap.name = "Шатро"
	cap.mesh = roof
	cap.material_override = paint("roof_slates_03", 2.0)
	cap.position.y = top + 2.75
	cap.rotation.y = PI / 4.0
	tower.add_child(cap)
	var iron := _iron()
	for bar: Vector3 in [Vector3(0.12, 1.6, 0.12), Vector3(0.9, 0.12, 0.12)]:
		var piece := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = bar
		piece.mesh = box
		piece.material_override = iron
		piece.position.y = top + 5.5 + (0.75 if bar.y > 1.0 else 1.05)
		tower.add_child(piece)
	_swap(tower, "цегла", "сланець")


## Стовп навісу — тесаний брус.
static func _post(body: Node3D, at: Vector3, high: float) -> void:
	var view := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.28, high, 0.28)
	view.mesh = box
	view.material_override = paint("dark_wooden_planks", 1.5)
	view.position = at + Vector3(0, high * 0.5, 0)
	body.add_child(view)


## Корогва: полотнище на жердині, звисає перед фасадом.
static func _banner(body: Node3D, at: Vector3, tone: Color) -> void:
	var cloth := MeshInstance3D.new()
	cloth.name = "Корогва"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 2.2)
	cloth.mesh = quad
	var paint_cloth := StandardMaterial3D.new()
	paint_cloth.albedo_color = tone
	paint_cloth.roughness = 0.9
	paint_cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	cloth.material_override = paint_cloth
	cloth.position = at
	body.add_child(cloth)
	var bar := MeshInstance3D.new()
	var rod := BoxMesh.new()
	rod.size = Vector3(1.3, 0.08, 0.08)
	bar.mesh = rod
	bar.material_override = _iron()
	bar.position = at + Vector3(0, 1.12, 0)
	body.add_child(bar)


## Ліхтар над дверима — тепле світло без тіні.
static func _lamp(body: Node3D, at: Vector3) -> void:
	_prop(body, "wooden_lantern_01", at - Vector3(0, 0.3, 0))
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.72, 0.4)
	light.light_energy = 0.8
	light.omni_range = 5.0
	light.position = at
	body.add_child(light)


## Горн: цегляна скриня з жаром, світлом і димом.
static func _forge(body: Node3D, at: Vector3) -> void:
	var brick := paint("medieval_red_brick", 1.5)
	var base := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.8, 1.0, 1.6)
	base.mesh = box
	base.material_override = brick
	base.position = at + Vector3(0, 0.5, 0)
	body.add_child(base)
	var hood := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.35
	cone.bottom_radius = 1.0
	cone.height = 1.4
	cone.radial_segments = 4
	hood.mesh = cone
	hood.material_override = brick
	hood.position = at + Vector3(0, 2.6, 0)
	hood.rotation.y = PI / 4.0
	body.add_child(hood)
	var coals := MeshInstance3D.new()
	var bed := BoxMesh.new()
	bed.size = Vector3(1.2, 0.08, 1.0)
	coals.mesh = bed
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.25, 0.05, 0.0)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.35, 0.05)
	glow.emission_energy_multiplier = 2.5
	coals.material_override = glow
	coals.position = at + Vector3(0, 1.04, 0)
	body.add_child(coals)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.45, 0.15)
	light.light_energy = 1.6
	light.omni_range = 6.0
	light.position = at + Vector3(0, 1.5, 0)
	body.add_child(light)
	var smoke := GPUParticles3D.new()
	smoke.name = "Дим"
	smoke.amount = 24
	smoke.lifetime = 4.0
	var motion := ParticleProcessMaterial.new()
	motion.direction = Vector3.UP
	motion.spread = 12.0
	motion.initial_velocity_min = 0.4
	motion.initial_velocity_max = 0.8
	motion.gravity = Vector3(0.15, 0.25, 0)
	motion.scale_min = 0.8
	motion.scale_max = 1.6
	smoke.process_material = motion
	var puff := QuadMesh.new()
	puff.size = Vector2(0.9, 0.9)
	var grey := StandardMaterial3D.new()
	grey.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grey.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	grey.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	grey.albedo_color = Color(0.35, 0.33, 0.31, 0.25)
	grey.albedo_texture = Fx._soft_dot()
	puff.material = grey
	smoke.draw_pass_1 = puff
	smoke.position = at + Vector3(0, 3.4, 0)
	smoke.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 12, 6))
	body.add_child(smoke)


## Ковадло: підставка-колода й залізне тіло з рогом.
static func _anvil(body: Node3D, at: Vector3) -> void:
	var stump_view := MeshInstance3D.new()
	var stump := CylinderMesh.new()
	stump.top_radius = 0.32
	stump.bottom_radius = 0.36
	stump.height = 0.55
	stump_view.mesh = stump
	stump_view.material_override = paint("dark_wooden_planks", 1.0)
	stump_view.position = at + Vector3(0, 0.275, 0)
	body.add_child(stump_view)
	var iron := _iron()
	for part: Array in [[Vector3(0.75, 0.22, 0.3), Vector3(0, 0.7, 0)],
			[Vector3(0.35, 0.16, 0.22), Vector3(0, 0.6, 0)]]:
		var piece := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = part[0]
		piece.mesh = box
		piece.material_override = iron
		piece.position = at + part[1]
		body.add_child(piece)
	var horn := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.11
	cone.height = 0.4
	horn.mesh = cone
	horn.material_override = iron
	horn.position = at + Vector3(0.55, 0.7, 0)
	horn.rotation.z = -PI / 2.0
	body.add_child(horn)


## Прилавок крамниці: дошка на двох тумбах і піддашок на стовпах.
static func _counter(body: Node3D, at: Vector3, long: float) -> void:
	var wood := paint("brown_planks_05", 1.2)
	var top := MeshInstance3D.new()
	var board := BoxMesh.new()
	board.size = Vector3(long, 0.1, 0.8)
	top.mesh = board
	top.material_override = wood
	top.position = at + Vector3(0, 1.0, 0)
	body.add_child(top)
	for side: float in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.6, 0.95, 0.7)
		leg.mesh = box
		leg.material_override = wood
		leg.position = at + Vector3(side * (long * 0.5 - 0.35), 0.475, 0)
		body.add_child(leg)
		_post(body, at + Vector3(side * (long * 0.5 + 0.1), 0, 0.5), 2.5)
	var awning := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = Vector3(long + 0.6, 0.08, 2.6)
	awning.mesh = slab
	awning.material_override = paint("weathered_planks", 1.5)
	awning.position = at + Vector3(0, 2.75, -0.6)
	awning.rotation.x = deg_to_rad(-14.0)
	body.add_child(awning)
	_prop(body, "wooden_crate_02", at + Vector3(-long * 0.25, 1.05, -0.05))


## Річ Poly Haven (`models/town/rechi`) у точці.
static func _prop(body: Node3D, name: String, at: Vector3) -> void:
	_piece(body, RECHI % [name, name], at, 0.0)


## Кована оковка дверей: у наборі вона синьо-фіолетова, мультяшна.
static func _iron() -> StandardMaterial3D:
	if not _paints.has("залізо"):
		var made := StandardMaterial3D.new()
		made.albedo_color = Color(0.16, 0.15, 0.14)
		made.metallic = 0.8
		made.roughness = 0.55
		_paints["залізо"] = made
	return _paints["залізо"]


## Утоптаний ґрунт перед дверима: дім углибині кварталу інакше стоїть
## дверима просто в траву.
static func _doorstep(body: Node3D, at: Vector3) -> void:
	var pad := BoxMesh.new()
	pad.size = Vector3(2.4, 0.06, 1.8)
	var view := MeshInstance3D.new()
	view.name = "Поріг"
	view.mesh = pad
	view.material_override = _dirt()
	view.position = at + Vector3(0, 0.01, 1.0)
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(view)


## Тин за хатою: кілки й дві жердини, одна сітка.
static func _wattle(body: Node3D, at: Vector3, long: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stake := BoxMesh.new()
	stake.size = Vector3(0.1, 1.25, 0.1)
	var rail := BoxMesh.new()
	rail.size = Vector3(long, 0.12, 0.07)
	var count := int(long / 1.0)
	for i in count + 1:
		st.append_from(stake, 0, Transform3D(Basis(), at + Vector3(
				-long * 0.5 + i * long / count, 0.6, 0)))
	for h: float in [0.45, 0.95]:
		st.append_from(rail, 0, Transform3D(Basis(), at + Vector3(0, h, 0)))
	var view := MeshInstance3D.new()
	view.name = "Тин"
	view.mesh = st.commit()
	view.material_override = paint("weathered_planks", 1.5)
	body.add_child(view)
