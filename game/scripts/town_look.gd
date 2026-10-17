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
				Vector2(line[1][0], line[1][1]), 5.0, stones)
	var c: Array = place["центр"]
	var square := CylinderMesh.new()
	square.top_radius = float(place.get("площа", 16.0))
	square.bottom_radius = square.top_radius
	square.height = 0.12
	square.radial_segments = 48
	var view := MeshInstance3D.new()
	view.name = "Площа"
	view.mesh = square
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
	var size: Array = house.get("модулі", [2, 2])
	var wide := int(size[0])
	var deep := int(size[1])
	var at: Array = house["де"]
	var where := Vector3(float(at[0]), 0, float(at[2]))
	where.y = land.surface_y(where.x, where.z)
	var body := StaticBody3D.new()
	body.name = land._named("Будинок")
	body.position = where
	body.rotation.y = deg_to_rad(float(house.get("поворот", 0.0)))
	holder.add_child(body)
	var across := mini(wide, deep)
	var lengthwise := maxi(wide, deep)
	var roof_path := KIT % ("Roof_RoundTiles_%dx%d" % [across * 2,
			lengthwise * 2])
	var roof_box := _roof_box(roof_path)
	var peak := ROOF_AT + roof_box.end.y
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
	var door := KIT % "Wall_Plaster_Door_Round"
	var frame := KIT % "Window_Wide_Round1"
	var half_x := (wide - 1) * MODULE * 0.5
	var half_z := (deep - 1) * MODULE * 0.5
	var edge_x := wide * MODULE * 0.5
	var edge_z := deep * MODULE * 0.5
	var pieces: Array = []
	for i in wide:
		var x := -half_x + i * MODULE
		var front := door if i == wide / 2 else window
		pieces.append([front, Vector3(x, 0, edge_z), 180.0])
		pieces.append([window if i % 2 == 1 else straight,
				Vector3(x, 0, -edge_z), 0.0])
	for i in deep:
		var z := -half_z + i * MODULE
		pieces.append([window if i % 2 == 0 else straight,
				Vector3(-edge_x, 0, z), 270.0])
		pieces.append([straight, Vector3(edge_x, 0, z), 90.0])
	for one: Array in pieces:
		_piece(body, one[0], one[1], one[2])
		if one[0] == window:
			_piece(body, frame, one[1], one[2])
	# Дах: гребінь уздовж довшого боку (у наборі — уздовж z).
	var roof_turn := 90.0 if wide > deep else 0.0
	_piece(body, roof_path, Vector3(0, ROOF_AT, 0), roof_turn)
	var wall_paint := paint(WALLS.get(style, "plastered_wall_02"), 2.0)
	_gables(body, roof_box, across, lengthwise, roof_turn, wall_paint)
	if bool(house.get("комин", false)):
		var x := across * MODULE * 0.25
		var roof_y := ROOF_AT + roof_box.end.y \
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
		turn: float, look: Material) -> void:
	var a := across * MODULE * 0.5
	var half := roof.size.x * 0.5
	var eave := ROOF_AT + roof.position.y
	var peak := ROOF_AT + roof.end.y - 0.4
	var side_y := maxf(WALL_HEIGHT, peak - (peak + 0.4 - eave) * (a / half))
	var outline: Array[Vector2] = [Vector2(-a, WALL_HEIGHT - 0.05),
			Vector2(a, WALL_HEIGHT - 0.05), Vector2(a, side_y),
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
