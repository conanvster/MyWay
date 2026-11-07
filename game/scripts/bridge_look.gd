class_name BridgeLook
extends RefCounted
## Мости світу 2 (П-174, слово замовника 06.11.2026: «для кожного переходу
## я б хотів обирати вручну дизайни мостів»).
##
## Місце — перетин дороги, ЯК ЇЇ НАМАЛЬОВАНО (згладжена `Landscape._trail`
## з тим самим шумом), з руслом; із кількох перетинів — найближчий до точки
## `мости[i].де` (вона груба: сітка генератора 32 м, до русла 16–22 м).
## Проліт — ширина річки там + береги; настил лежить від берега до берега
## похило, якщо береги різні, — по ньому ходять (`move_and_slide`).
##
## Дизайн кожного переходу — у `data/svit2/мости-вибір.json` (руками,
## генератор його не чіпає). Немає запису — «колоди».

const CHOICE_PATH := "res://data/svit2/мости-вибір.json"
const DESIGNS := ["колоди", "критий", "арка", "опори", "мотузковий",
		"кладка", "зруби", "плити", "бутова арка"]
## Старіші на вигляд (слово замовника 06.11.2026 про переходи 0 і 1: «має
## вигляд дуже сучасних переходів — спробуй щось старіше»): кора замість
## тесаних дощок, бут і плити замість цегли, жердини замість поруч.
const OLD_DESIGNS := ["кладка", "зруби", "плити", "бутова арка"]
const DESIGN_NAMES := {
	"колоди": "дерев'яний на палях",
	"критий": "критий дерев'яний",
	"арка": "кам'яна арка",
	"опори": "кам'яні опори, дерев'яний настил",
	"мотузковий": "мотузковий",
	"кладка": "кладка з колод",
	"зруби": "колоди на зрубах",
	"плити": "кам'яні плити на бутових стовпах",
	"бутова арка": "бутова арка",
}
const DEFAULT := "колоди"
const DECK_WIDE := 3.6
const BANK := 2.5           ## скільки настилу лягає на сухий берег, м
const CLEAR := 0.9          ## настил над водою щонайменше, м
const CLEAR_ARCH := 3.8     ## те саме для кам'яної арки (2,4 → 3,8 07.11: склепіння виднілись на метр)
const RAMP_SLOPE := 4.0     ## насип: метрів довжини на метр висоти


## Усі мости світу (і сервер, і клієнт: настил — тверде тіло).
static func build_all(land: Landscape) -> void:
	var bridges: Array = land.data.get("мости", [])
	if bridges.is_empty():
		return
	var chosen := choices()
	for i in bridges.size():
		build_one(land, i, str(chosen.get(str(i), DEFAULT)))


static func choices() -> Dictionary:
	if not FileAccess.file_exists(CHOICE_PATH):
		return {}
	var read: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(CHOICE_PATH))
	return read if read is Dictionary else {}


## Де саме й як лежить міст `i`: центр, напрям уздовж, довжина, висоти
## кінців, рівень води. Порожньо — перетину дороги з руслом не знайдено.
static func span_of(land: Landscape, i: int,
		design: String = DEFAULT) -> Dictionary:
	var bridge: Dictionary = land.data["мости"][i]
	var near := Vector2(float(bridge["де"][0]), float(bridge["де"][2]))
	var roads: Array = land.data.get("дороги", [])
	var road_at := int(bridge.get("дорога", -1))
	if road_at < 0 or road_at >= roads.size():
		return {}
	var wander := FastNoiseLite.new()
	wander.seed = Landscape.SEED + 777
	wander.frequency = 0.025
	var road := Landscape._trail(roads[road_at].get("точки", []), wander)
	var best := {}
	var best_gap := INF
	for stream: Dictionary in land.data.get("русла", []):
		var pts: Array = stream.get("точки", [])
		for k in range(pts.size() - 1):
			var a := Vector2(float(pts[k][0]), float(pts[k][1]))
			var b := Vector2(float(pts[k + 1][0]), float(pts[k + 1][1]))
			for j in range(road.size() - 1):
				var hit: Variant = Geometry2D.segment_intersects_segment(
						road[j], road[j + 1], a, b)
				if hit == null:
					continue
				var p: Vector2 = hit
				var gap := p.distance_to(near)
				if gap >= best_gap:
					continue
				best_gap = gap
				var t := p.distance_to(a) / maxf(0.01, a.distance_to(b))
				best = {
					"де": p,
					"уздовж": (road[j + 1] - road[j]).normalized(),
					"течія": (b - a).normalized(),
					"ширина": lerpf(float(pts[k][3]), float(pts[k + 1][3]), t),
					"вода": land.river_y(p.x, p.y, lerpf(float(pts[k][2]),
							float(pts[k + 1][2]), t)),
				}
	if best.is_empty():
		return {}
	var along: Vector2 = best["уздовж"]
	var cross: Vector2 = best["де"]
	# Кінці — уздовж дороги до сухого берега (земля вища за воду й море),
	# + BANK на берег. До 07.11.2026 проліт був «ширина з даних + 2×BANK»,
	# а врізане русло ширше (×2,2 ширини) — кінці падали у воду, біля гирла
	# ще й у море.
	var dry := maxf(float(best["вода"]), land.sea_level()) + Landscape.WET_ABOVE
	var most := float(best["ширина"]) * Landscape.WET_BAND * 2.0 + 20.0
	var ends: Array[float] = []
	for side: float in [-1.0, 1.0]:
		var d := 0.0
		while d < most and land.surface_y(cross.x + along.x * side * d,
				cross.y + along.y * side * d) < dry:
			d += 0.5
		ends.append(maxf(d, float(best["ширина"]) * 0.5) + BANK)
	var long := ends[0] + ends[1]
	var at := cross + along * (ends[1] - ends[0]) * 0.5
	best["де"] = at
	var a_end := at - along * long * 0.5
	var b_end := at + along * long * 0.5
	best["довжина"] = long
	var ya := land.surface_y(a_end.x, a_end.y)
	var yb := land.surface_y(b_end.x, b_end.y)
	# Настил — над водою щонайменше на CLEAR; нижчий берег піднімається
	# насипом (`_ramp`), а не настил іде під воду. Майже рівні береги —
	# настил рівний.
	# Під кам'яну арку треба місця — склепіння не має йти під воду.
	var low := float(best["вода"]) + (CLEAR_ARCH if design.ends_with("арка")
			else CLEAR)
	var ha := maxf(ya, low)
	var hb := maxf(yb, low)
	if absf(ha - hb) < 0.6:
		ha = maxf(ha, hb)
		hb = ha
	best["земля_а"] = ya
	best["земля_б"] = yb
	best["висота_а"] = ha
	best["висота_б"] = hb
	return best


## Збудувати (або перебудувати) міст `i` дизайном `design`.
static func build_one(land: Landscape, i: int, design: String) -> Node3D:
	var old := land.get_node_or_null("Міст-%d" % i)
	if old != null:
		land.remove_child(old)
		old.queue_free()
	var span := span_of(land, i, design)
	if span.is_empty():
		push_warning("[міст] %d: перетину дороги з руслом не знайдено" % i)
		return null
	var shown := DisplayServer.get_name() != "headless"
	var long := float(span["довжина"])
	var ya := float(span["висота_а"])
	var yb := float(span["висота_б"])
	var along: Vector2 = span["уздовж"]
	var at: Vector2 = span["де"]
	var holder := Node3D.new()
	holder.name = "Міст-%d" % i
	holder.set_meta("design", design)
	land.add_child(holder)
	holder.position = Vector3(at.x, (ya + yb) * 0.5, at.y)
	holder.rotation.y = -atan2(along.y, along.x)
	# Похил настилу: від берега А (−x) до берега Б (+x).
	var tilt := atan2(yb - ya, long)
	var deck := StaticBody3D.new()
	deck.name = "Настил"
	deck.rotation.z = tilt
	holder.add_child(deck)
	var thick := 0.8 if design.ends_with("арка") else 0.3
	var box := BoxShape3D.new()
	box.size = Vector3(long / cos(tilt), thick, DECK_WIDE)
	var hit := CollisionShape3D.new()
	hit.shape = box
	hit.position.y = -thick * 0.5 + 0.05
	deck.add_child(hit)
	# Поруччя — тверді, щоб з моста не зісковзнути збоку.
	for side: float in [-1.0, 1.0]:
		var rail := BoxShape3D.new()
		rail.size = Vector3(long / cos(tilt), 1.0, 0.25)
		var guard := CollisionShape3D.new()
		guard.shape = rail
		guard.position = Vector3(0, 0.55, side * (DECK_WIDE * 0.5 + 0.1))
		deck.add_child(guard)
	for end: float in [-1.0, 1.0]:
		var top := float(span["висота_а" if end < 0 else "висота_б"])
		var ground := float(span["земля_а" if end < 0 else "земля_б"])
		if top - ground > 0.15:
			_ramp(land, holder, end, long * 0.5, top, ground, shown)
	if not shown:
		return holder
	var water := float(span["вода"]) - holder.position.y
	var built := {"довжина": long / cos(tilt), "вода": water, "похил": tilt}
	match design:
		"критий":
			_logs(deck, built, false)
			_covered(deck, built)
		"арка":
			_arch(deck, built)
		"опори":
			_piers(deck, built)
		"мотузковий":
			_rope(deck, built)
		"кладка":
			_footlogs(deck, built)
		"зруби":
			_cribs(deck, built)
		"плити":
			_slabs(deck, built)
		"бутова арка":
			_arch(deck, built, true)
		_:
			_logs(deck, built, true)
	for mesh in holder.find_children("*", "GeometryInstance3D", true, false):
		(mesh as GeometryInstance3D).visibility_range_end = 600.0
	return holder


## Насип від берега до настилу: похилий клин ґрунту з твердим верхом.
static func _ramp(land: Landscape, holder: Node3D, end: float, half: float,
		top: float, ground: float, shown: bool) -> void:
	var rise := top - ground
	var run := rise * RAMP_SLOPE
	var body := StaticBody3D.new()
	body.name = "Насип"
	holder.add_child(body)
	var slope := atan2(rise, run)
	var length := sqrt(run * run + rise * rise)
	var cx := end * (half + run * 0.5)
	var cy := (top + ground) * 0.5 - holder.position.y
	body.position = Vector3(cx, cy, 0)
	body.rotation.z = -end * slope
	var box := BoxShape3D.new()
	box.size = Vector3(length, 0.3, DECK_WIDE + 0.6)
	var hit := CollisionShape3D.new()
	hit.shape = box
	hit.position.y = -0.1
	body.add_child(hit)
	if shown:
		_ramp_look(holder, end, half, run, top - holder.position.y,
				ground - holder.position.y)


## Вигляд насипу: зверху ґрунт дороги, боки — пологі трав'яні укоси до
## землі (раніше — коробка з гострими краями, читалась рожевим клином).
static func _ramp_look(holder: Node3D, end: float, half: float, run: float,
		top: float, ground: float) -> void:
	var w := DECK_WIDE * 0.5 + 0.3
	var base := ground - 0.5
	var x0 := end * (half - 0.2)
	var x1 := end * (half + run + 0.3)
	var s0 := (top - base) * 1.6
	var s1 := (ground - base) * 1.6
	var a0 := Vector3(x0, top, -w)
	var b0 := Vector3(x0, top, w)
	var a1 := Vector3(x1, ground, -w)
	var b1 := Vector3(x1, ground, w)
	var c0 := Vector3(x0, base, -w - s0)
	var d0 := Vector3(x0, base, w + s0)
	var c1 := Vector3(x1, base, -w - s1)
	var d1 := Vector3(x1, base, w + s1)
	var top_mesh := _quads([[a0, a1, b1, b0]])
	var sides := _quads([[c0, c1, a1, a0], [b0, b1, d1, d0],
			[c0, a0, b0, d0]])
	for part: Array in [[top_mesh, TownLook._dirt()], [sides, _grass()]]:
		var view := MeshInstance3D.new()
		view.mesh = part[0]
		view.material_override = part[1]
		holder.add_child(view)


## Чотирикутники обома боками (щоб не залежати від обходу вершин).
static func _quads(list: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for q: Array in list:
		for tri: Array in [[q[0], q[1], q[2]], [q[0], q[2], q[3]]]:
			# Нормаль — на кожен бік своя. `generate_normals()` тут
			# усереднював протилежні нормалі спільних вершин до нуля —
			# темні трикутники на арці й укосах (07.11.2026).
			var n: Vector3 = (tri[2] - tri[0]).cross(tri[1] - tri[0]) \
					.normalized()
			for order: Array in [[0, 1, 2], [0, 2, 1]]:
				var face := n if order[1] == 1 else -n
				for k: int in order:
					st.set_normal(face)
					st.add_vertex(tri[k])
	return st.commit()


static var _grass_paint: StandardMaterial3D = null


static func _grass() -> StandardMaterial3D:
	if _grass_paint == null:
		_grass_paint = StandardMaterial3D.new()
		_grass_paint.albedo_texture = load("res://models/ground/Grass004_Color.jpg")
		_grass_paint.normal_enabled = true
		_grass_paint.normal_texture = load(
				"res://models/ground/Grass004_Normal.jpg")
		_grass_paint.roughness = 1.0
		_grass_paint.uv1_triplanar = true
		_grass_paint.uv1_world_triplanar = true
		_grass_paint.uv1_scale = Vector3.ONE / 2.5
	return _grass_paint


# ─── дизайни ─────────────────────────────────────────────────────────

## Дерев'яний на палях: настил із дощок, дві колоди-балки, палі парами
## до дна, поруччя з колод на стовпцях.
static func _logs(deck: Node3D, b: Dictionary, rails: bool) -> void:
	var long: float = b["довжина"]
	var planks := TownLook.paint("weathered_planks", 1.2)
	var logs := TownLook.paint("dark_wooden_planks", 1.0)
	_box(deck, Vector3(long, 0.14, DECK_WIDE), Vector3(0, -0.02, 0), planks)
	for side: float in [-1.0, 1.0]:
		_rod(deck, Vector3(-long * 0.5, -0.3, side * 1.3),
				Vector3(long * 0.5, -0.3, side * 1.3), 0.22, logs)
	var count := maxi(2, int(long / 3.0))
	for k in range(1, count):
		var x := -long * 0.5 + k * long / count
		for side: float in [-1.0, 1.0]:
			_rod(deck, Vector3(x, -0.3, side * 1.4),
					Vector3(x, b["вода"] - 1.2, side * 1.5), 0.16, logs)
	if rails:
		_wood_rails(deck, long, logs)


static func _wood_rails(deck: Node3D, long: float, wood: Material) -> void:
	var count := maxi(2, int(long / 2.5))
	for side: float in [-1.0, 1.0]:
		var z := side * (DECK_WIDE * 0.5 - 0.1)
		for k in count + 1:
			var x := -long * 0.5 + k * long / count
			_rod(deck, Vector3(x, 0, z), Vector3(x, 1.05, z), 0.07, wood)
		_rod(deck, Vector3(-long * 0.5, 1.0, z), Vector3(long * 0.5, 1.0, z),
				0.06, wood)
		_rod(deck, Vector3(-long * 0.5, 0.55, z), Vector3(long * 0.5, 0.55, z),
				0.05, wood)


## Критий: стіни-ґратки зі стовпців і двосхилий дах із дощок.
static func _covered(deck: Node3D, b: Dictionary) -> void:
	var long: float = b["довжина"]
	var wood := TownLook.paint("dark_wooden_planks", 1.0)
	var roof := TownLook.paint("roof_slates_03", 2.0)
	var count := maxi(2, int(long / 2.0))
	for side: float in [-1.0, 1.0]:
		var z := side * (DECK_WIDE * 0.5 + 0.05)
		for k in count + 1:
			var x := -long * 0.5 + k * long / count
			_rod(deck, Vector3(x, 0, z), Vector3(x, 2.6, z), 0.1, wood)
		_box(deck, Vector3(long, 0.18, 0.18), Vector3(0, 2.6, z), wood)
		_box(deck, Vector3(long, 0.9, 0.06), Vector3(0, 0.5, z), wood)
		var slope := MeshInstance3D.new()
		var slab := BoxMesh.new()
		slab.size = Vector3(long + 0.8, 0.1, DECK_WIDE * 0.62)
		slope.mesh = slab
		slope.material_override = roof
		slope.position = Vector3(0, 3.25, side * DECK_WIDE * 0.27)
		slope.rotation.x = side * deg_to_rad(32.0)
		deck.add_child(slope)


## Кам'яна арка: склепіння з тесаного каменю, товстий настил і парапети
## з цегли. Довгий проліт — кілька склепінь (~12 м) на биках у воді; над
## кожним склепінням заповнення йде по його кривій. До 07.11.2026 тут було
## одне склепіння під суцільною коробкою-«спандрелем» — на 51 м міст
## читався рівною стіною.
const ARCH_SPAN := 12.0
const ARCH_PIER := 1.6


static func _arch(deck: Node3D, b: Dictionary, rubble: bool = false) -> void:
	var long: float = b["довжина"]
	var water: float = b["вода"]
	var stone := TownLook.paint("castle_wall_varriation" if rubble
			else "medieval_blocks_03", 2.5)
	var brick := stone if rubble else TownLook.paint("castle_brick_07", 2.0)
	var under := -0.75
	_box(deck, Vector3(long, 0.8, DECK_WIDE + 0.4), Vector3(0, -0.35, 0), stone)
	var inner := long * 0.5 - BANK
	var count := maxi(1, roundi(inner * 2.0 / ARCH_SPAN))
	var span := (inner * 2.0 - (count - 1) * ARCH_PIER) / count
	# Склепіння спирається трохи над водою; стрілка — не більша за 0,4 прольоту.
	var rise := clampf(under - (water + 0.15), 0.4, span * 0.4)
	var spring := under - rise
	var face := DECK_WIDE * 0.5 + 0.2
	var fill: Array = []
	var pieces := 10
	for i in count:
		var x0 := -inner + i * (span + ARCH_PIER)
		var mid_x := x0 + span * 0.5
		for k in pieces:
			var t0 := -1.0 + 2.0 * k / pieces
			var t1 := -1.0 + 2.0 * (k + 1) / pieces
			var p0 := Vector3(mid_x + t0 * span * 0.5,
					spring + rise * (1.0 - t0 * t0), 0)
			var p1 := Vector3(mid_x + t1 * span * 0.5,
					spring + rise * (1.0 - t1 * t1), 0)
			var seg := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(p0.distance_to(p1) + 0.1, 0.55, face * 2.0)
			seg.mesh = box
			seg.material_override = stone
			seg.position = (p0 + p1) * 0.5 + Vector3(0, -0.2, 0)
			seg.rotation.z = atan2(p1.y - p0.y, p1.x - p0.x)
			deck.add_child(seg)
			for side: float in [-1.0, 1.0]:
				var z := side * face
				fill.append([Vector3(p0.x, p0.y, z), Vector3(p1.x, p1.y, z),
						Vector3(p1.x, under, z), Vector3(p0.x, under, z)])
		# Бик між склепіннями: від дна до настилу, у воді ширший.
		if i < count - 1:
			var px := x0 + span + ARCH_PIER * 0.5
			var low := water - 2.0
			_box(deck, Vector3(ARCH_PIER, under - low, face * 2.0),
					Vector3(px, (under + low) * 0.5, 0), stone)
			_box(deck, Vector3(ARCH_PIER + 0.3, spring - low + 0.3,
					face * 2.0 + 0.8),
					Vector3(px, (spring + 0.3 + low) * 0.5, 0), stone)
	var walls := MeshInstance3D.new()
	walls.mesh = _quads(fill)
	walls.material_override = stone
	deck.add_child(walls)
	for side: float in [-1.0, 1.0]:
		_box(deck, Vector3(long, 0.95, 0.4),
				Vector3(0, 0.5, side * (DECK_WIDE * 0.5 + 0.0)), brick)
	# Устої на берегах: від води до настилу.
	for end: float in [-1.0, 1.0]:
		var low := water - 1.0
		_box(deck, Vector3(BANK, under - low, DECK_WIDE + 0.6),
				Vector3(end * (inner + BANK * 0.5), (under + low) * 0.5, 0),
				stone)


## Кам'яні опори (одна-дві у воді) під дерев'яним настилом.
static func _piers(deck: Node3D, b: Dictionary) -> void:
	var long: float = b["довжина"]
	var stone := TownLook.paint("castle_wall_varriation", 2.5)
	var wood := TownLook.paint("dark_wooden_planks", 1.0)
	_box(deck, Vector3(long, 0.16, DECK_WIDE), Vector3(0, -0.03, 0),
			TownLook.paint("brown_planks_05", 1.2))
	for side: float in [-1.0, 1.0]:
		_box(deck, Vector3(long, 0.3, 0.3), Vector3(0, -0.25, side * 1.4), wood)
	var count := 1 if long < 16.0 else 2
	for k in count:
		var x := -long * 0.5 + (k + 1) * long / (count + 1)
		var high := -float(b["вода"]) + 1.4
		_box(deck, Vector3(1.6, high, DECK_WIDE + 0.8),
				Vector3(x, -0.4 - high * 0.5, 0), stone)
		var nose := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.9
		cone.height = 1.0
		cone.radial_segments = 4
		nose.mesh = cone
		nose.material_override = stone
		nose.position = Vector3(x, -0.4 + 0.1, 0)
		deck.add_child(nose)
	_wood_rails(deck, long, wood)


## Мотузковий: дошки з проміжками, два канати з провисом, стовпи на берегах.
static func _rope(deck: Node3D, b: Dictionary) -> void:
	var long: float = b["довжина"]
	var wood := TownLook.paint("weathered_planks", 1.0)
	var posts := TownLook.paint("dark_wooden_planks", 1.0)
	var rope := StandardMaterial3D.new()
	rope.albedo_color = Color(0.45, 0.36, 0.24)
	rope.roughness = 1.0
	var count := int(long / 0.55)
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	var board := BoxMesh.new()
	board.size = Vector3(0.42, 0.06, DECK_WIDE * 0.75)
	many.mesh = board
	many.instance_count = count
	for k in count:
		var x := -long * 0.5 + (k + 0.5) * long / count
		var sag := -0.35 * (1.0 - pow(2.0 * x / long, 2.0))
		many.set_instance_transform(k, Transform3D(Basis(),
				Vector3(x, sag, 0)))
	var boards := MultiMeshInstance3D.new()
	boards.multimesh = many
	boards.material_override = wood
	deck.add_child(boards)
	for side: float in [-1.0, 1.0]:
		var z := side * DECK_WIDE * 0.42
		for end: float in [-1.0, 1.0]:
			_rod(deck, Vector3(end * long * 0.5, -0.6, z),
					Vector3(end * long * 0.5, 1.5, z), 0.13, posts)
		var steps := 16
		for h: float in [1.25, -0.05]:
			for k in steps:
				var x0 := -long * 0.5 + k * long / steps
				var x1 := -long * 0.5 + (k + 1) * long / steps
				var s0 := -0.55 * (1.0 - pow(2.0 * x0 / long, 2.0))
				var s1 := -0.55 * (1.0 - pow(2.0 * x1 / long, 2.0))
				_rod(deck, Vector3(x0, h + s0, z), Vector3(x1, h + s1, z),
						0.035, rope)


# ─── старіші дизайни ─────────────────────────────────────────────────

static var _bark_paint: StandardMaterial3D = null


## Кора (ambientCG Bark014) — колоди, а не тесані дошки.
static func _bark() -> StandardMaterial3D:
	if _bark_paint == null:
		_bark_paint = StandardMaterial3D.new()
		_bark_paint.albedo_texture = load(
				"res://models/nature/bark/Bark014_Color.jpg")
		_bark_paint.normal_enabled = true
		_bark_paint.normal_texture = load(
				"res://models/nature/bark/Bark014_Normal.jpg")
		_bark_paint.roughness = 0.95
		_bark_paint.uv1_triplanar = true
		_bark_paint.uv1_world_triplanar = true
		_bark_paint.uv1_scale = Vector3.ONE / 1.2
	return _bark_paint


## Кладка: три колоди поруч, жердина-поруччя на рогатках з одного боку.
static func _footlogs(deck: Node3D, b: Dictionary) -> void:
	var long: float = b["довжина"]
	var bark := _bark()
	var wobble := [0.0, 0.07, -0.05]
	for k in 3:
		var z := (k - 1) * 0.5
		_rod(deck, Vector3(-long * 0.5 - 0.4, -0.2 + wobble[k], z),
				Vector3(long * 0.5 + 0.4, -0.2 - wobble[k], z + 0.06),
				0.24 - k * 0.02, bark)
	var z := DECK_WIDE * 0.25 + 0.3
	var count := maxi(2, int(long / 4.0))
	for k in count + 1:
		var x := -long * 0.5 + k * long / count
		_rod(deck, Vector3(x, -0.3, z), Vector3(x + 0.1, 1.0, z + 0.05),
				0.06, bark)
		_rod(deck, Vector3(x + 0.1, 0.85, z), Vector3(x + 0.35, 1.15, z),
				0.04, bark)
	_rod(deck, Vector3(-long * 0.5, 1.0, z), Vector3(long * 0.5, 0.95, z),
			0.055, bark)
	for k in range(1, count):
		var x := -long * 0.5 + k * long / count
		_rod(deck, Vector3(x, -0.25, 0), Vector3(x, b["вода"] - 1.0, 0.1),
				0.17, bark)


## Колоди на зрубах: настил із поперечних кругляків, опори — клітки з
## колод навхрест (у воді), поруччя — жердини на стовпцях.
static func _cribs(deck: Node3D, b: Dictionary) -> void:
	var long: float = b["довжина"]
	var bark := _bark()
	var count := int(long / 0.34)
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	var log_mesh := CylinderMesh.new()
	log_mesh.top_radius = 0.16
	log_mesh.bottom_radius = 0.17
	log_mesh.height = DECK_WIDE
	log_mesh.radial_segments = 8
	many.mesh = log_mesh
	many.instance_count = count
	for k in count:
		var x := -long * 0.5 + (k + 0.5) * long / count
		var turn := Basis(Vector3.RIGHT, PI / 2.0).rotated(Vector3.UP,
				sin(k * 1.7) * 0.03)
		many.set_instance_transform(k, Transform3D(turn,
				Vector3(x, -0.12 + sin(k * 2.3) * 0.02, 0)))
	var deck_logs := MultiMeshInstance3D.new()
	deck_logs.multimesh = many
	deck_logs.material_override = bark
	deck.add_child(deck_logs)
	for side: float in [-1.0, 1.0]:
		_rod(deck, Vector3(-long * 0.5, -0.38, side * 1.2),
				Vector3(long * 0.5, -0.38, side * 1.2), 0.2, bark)
	var piers := 1 if long < 16.0 else 2
	for p in piers:
		var x := -long * 0.5 + (p + 1) * long / (piers + 1)
		var floor_y: float = b["вода"] - 1.2
		var y := -0.6
		var layer := 0
		while y > floor_y:
			if layer % 2 == 0:
				for dz: float in [-1.3, 1.3]:
					_rod(deck, Vector3(x - 1.2, y, dz), Vector3(x + 1.2, y, dz),
							0.17, bark)
			else:
				for dx: float in [-1.0, 1.0]:
					_rod(deck, Vector3(x + dx, y, -1.6),
							Vector3(x + dx, y, 1.6), 0.17, bark)
			y -= 0.3
			layer += 1
	var posts := maxi(2, int(long / 3.0))
	for side: float in [-1.0, 1.0]:
		var z := side * (DECK_WIDE * 0.5 - 0.15)
		for k in posts + 1:
			var x := -long * 0.5 + k * long / posts
			_rod(deck, Vector3(x, -0.1, z), Vector3(x, 1.0, z), 0.08, bark)
		_rod(deck, Vector3(-long * 0.5, 0.95, z), Vector3(long * 0.5, 0.9, z),
				0.06, bark)


## Кам'яні плити на бутових стовпах — найдавніший міст, без поруч.
static func _slabs(deck: Node3D, b: Dictionary) -> void:
	var long: float = b["довжина"]
	var slab := TownLook.paint("castle_wall_slates", 2.0)
	var rubble := TownLook.paint("castle_wall_varriation", 2.0)
	var spans := maxi(2, int(ceil(long / 4.5)))
	var step := long / spans
	for k in spans:
		var x := -long * 0.5 + (k + 0.5) * step
		var lift := sin(k * 2.1) * 0.04
		var piece := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(step + 0.25, 0.32, DECK_WIDE * 0.8 + sin(k) * 0.15)
		piece.mesh = box
		piece.material_override = slab
		piece.position = Vector3(x, -0.16 + lift, sin(k * 1.3) * 0.08)
		piece.rotation.y = sin(k * 3.1) * 0.03
		deck.add_child(piece)
	for k in range(1, spans):
		var x := -long * 0.5 + k * step
		var high := -float(b["вода"]) + 1.0
		_box(deck, Vector3(1.3, high, DECK_WIDE * 0.75),
				Vector3(x, -0.32 - high * 0.5, 0), rubble)
		_box(deck, Vector3(1.6, 0.35, DECK_WIDE * 0.9),
				Vector3(x, b["вода"] + 0.05, 0), rubble)


# ─── цеглинки ────────────────────────────────────────────────────────

static func _box(parent: Node3D, size: Vector3, at: Vector3,
		look: Material) -> void:
	var view := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	view.mesh = box
	view.material_override = look
	view.position = at
	parent.add_child(view)


## Колода/жердина/канат від `a` до `b`.
static func _rod(parent: Node3D, a: Vector3, b: Vector3, radius: float,
		look: Material) -> void:
	var long := a.distance_to(b)
	if long < 0.01:
		return
	var view := MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = radius
	tube.bottom_radius = radius
	tube.height = long
	tube.radial_segments = 8
	tube.rings = 1
	view.mesh = tube
	view.material_override = look
	parent.add_child(view)
	view.position = (a + b) * 0.5
	var up := (b - a).normalized()
	var side := up.cross(Vector3.FORWARD)
	if side.length() < 0.01:
		side = up.cross(Vector3.RIGHT)
	side = side.normalized()
	# Права трійка: x × y = z — циліндр стоїть віссю Y уздовж a→b.
	view.basis = Basis(side, up, side.cross(up))
