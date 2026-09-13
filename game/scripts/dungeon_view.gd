class_name DungeonView
extends Node3D
## Намальоване підземелля (П-190) з плану `DungeonPlan`: підлога, стіни,
## склепіння, вода, світло й оздоба — за фото, які дав замовник
## 13.09.2026 (склепи з кістками, цегляні склепіння льохів, колектори з
## водою й свічками, цегляний хід під костелом).
##
## Як будується форма. Сітка плану — клітинки по 1 м, і стіна по краю
## клітинки дала б «сходинки» на кожному косому ході. Тому межа береться
## як ізолінія 0,5 між центрами клітинок («marching squares») на сітці
## вершин через 0,5 м: косий хід стає рівною косою стіною, колона — гранчастим
## стовпом, ніша — заглибиною.
##
## Склепіння — не окремі арки, а висота стелі від ВІДСТАНІ до стіни:
## біля стіни — висота стіни, до середини ходу — підйом по колу. У ході
## завширшки 3 м це й дає ту півкруглу трубу, що на фото колекторів; у
## залі стеля над серединою пласка, як у льоху.
##
## Грані дивляться лише всередину. Звідси дві речі одразу: зсередини
## склепіння видно, а камера гри, що дивиться згори під 50°, бачить
## крізь стелю підлогу й бій — ні стелю, ні зовнішній бік стін
## рушій не малює взагалі.
##
## Текстури — фото ambientCG (CC0), накладені з трьох боків у координатах
## світу: розгортки не треба, і шов на склепінні не видно.

## Крок сітки вершин, метрів.
const SUB := 0.5
const TEX_DIR := "res://models/dungeon/"

var plan: DungeonPlan
var style: Dictionary = {}
## Скільки поставлено — для проби й звіту.
var lights_made := 0
var props_made := 0
var triangles := 0
## Перевірка стін (P2): скільки всього, скільки лицем у камінь за полем
## плану, скільки лицем не туди, куди просили.
var walls_total := 0
var walls_into_rock := 0
var walls_against_want := 0
var wall_samples: Array[Vector3] = []

var _n := 0
var _val := PackedFloat32Array()
var _dist := PackedFloat32Array()
var _base := PackedFloat32Array()
var _fy := PackedFloat32Array()
var _cy := PackedFloat32Array()
var _wet := PackedFloat32Array()
var _noise := FastNoiseLite.new()
var _mats: Dictionary = {}
var _faces := PackedVector3Array()
var _rng := RandomNumberGenerator.new()
var _opened := PackedFloat32Array()


## Скільки «прохідності» в точці (0 — камінь, 1 — хід) за полем плану.
func value_at(p: Vector3) -> float:
	return _bilinear(_opened, p.x / DungeonPlan.CELL + plan.size * 0.5 - 0.5,
			p.z / DungeonPlan.CELL + plan.size * 0.5 - 0.5)


func build(from_plan: DungeonPlan, from_style: Dictionary) -> void:
	plan = from_plan
	style = from_style
	_noise.seed = hash(plan.id)
	_noise.frequency = 0.3
	_rng.seed = hash(plan.id) + 17
	_fields()
	_mesh()
	_lights()
	_props()


## Повітря підземелля: чорне тло, ледь тепле розсіяне світло, імла, у
## якій видно світло свічок (фото колектора зі свічками), і відблиски на
## воді.
static func environment(from_style: Dictionary) -> Environment:
	var air := Environment.new()
	air.background_mode = Environment.BG_COLOR
	air.background_color = Color.BLACK
	air.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	air.ambient_light_color = Color(0.62, 0.54, 0.45)
	air.ambient_light_energy = float(from_style.get("темрява", 0.1))
	air.tonemap_mode = Environment.TONE_MAPPER_ACES
	air.tonemap_exposure = float(from_style.get("експозиція", 1.0))
	air.ssao_enabled = true
	air.ssao_radius = 1.2
	air.ssr_enabled = true
	air.glow_enabled = true
	air.glow_intensity = 0.5
	air.volumetric_fog_enabled = true
	air.volumetric_fog_density = float(from_style.get("імла", 0.02))
	var tone: Array = from_style.get("колір_імли", [0.6, 0.55, 0.5])
	air.volumetric_fog_albedo = Color(tone[0], tone[1], tone[2])
	air.volumetric_fog_length = 48.0
	return air


# --- поля на сітці вершин -------------------------------------------------

func _local(u: float, v: float) -> Vector3:
	return Vector3((u + 0.5 - plan.size * 0.5) * DungeonPlan.CELL, 0.0,
			(v + 0.5 - plan.size * 0.5) * DungeonPlan.CELL)


func _bilinear(field: PackedFloat32Array, u: float, v: float) -> float:
	var s := plan.size
	var x0 := clampi(floori(u), 0, s - 2)
	var z0 := clampi(floori(v), 0, s - 2)
	var fx := u - x0
	var fz := v - z0
	var top := lerpf(field[z0 * s + x0], field[z0 * s + x0 + 1], fx)
	var low := lerpf(field[(z0 + 1) * s + x0], field[(z0 + 1) * s + x0 + 1],
			fx)
	return lerpf(top, low, fz)


func _fields() -> void:
	var s := plan.size
	var opened := PackedFloat32Array()
	opened.resize(s * s)
	var tun := PackedFloat32Array()
	tun.resize(s * s)
	for i in s * s:
		opened[i] = float(plan.open[i])
		tun[i] = 1.0 if plan.open[i] == 1 and plan.tunnel[i] == 1 else 0.0
	_opened = opened

	_n = (s - 1) * 2 + 1
	var count := _n * _n
	for field: PackedFloat32Array in [_val, _base, _wet, _dist, _fy, _cy]:
		field.resize(count)
	for j in _n:
		for i in _n:
			var k := j * _n + i
			_val[k] = _bilinear(opened, i * SUB, j * SUB)
			_base[k] = _bilinear(plan.floor_y, i * SUB, j * SUB)
			_wet[k] = _bilinear(tun, i * SUB, j * SUB)
	_distance()

	var wall_h := float(style.get("висота_стін", 2.0))
	var rise := float(style.get("підйом", 1.3))
	var span := float(style.get("проліт", 1.5))
	var rough := float(style.get("шорсткість", 0.0))
	var channel := float(style.get("русло", 0.0)) if plan.water else 0.0
	for j in _n:
		for i in _n:
			var k := j * _n + i
			var p := _local(i * SUB, j * SUB)
			var d := _dist[k]
			var bump := _noise.get_noise_2d(p.x, p.z) * rough
			var fy := _base[k] + bump * 0.3
			# Русло колектора: посередині ходу вода, по боках — бровка.
			if channel > 0.0 and _wet[k] > 0.5:
				fy -= channel * smoothstep(0.55, 1.05, d)
			_fy[k] = fy
			_cy[k] = _base[k] + wall_h + rise * sqrt(clampf(d / span, 0.0,
					1.0)) + bump * 1.4


## Відстань кожної вершини всередині до стіни: спершу точно для
## вершин біля межі (до точки перетину), потім двома проходами по сітці.
func _distance() -> void:
	for k in _n * _n:
		_dist[k] = 1e6 if _val[k] >= 0.5 else 0.0
	for j in _n:
		for i in _n:
			var k := j * _n + i
			if _val[k] < 0.5:
				continue
			for s: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0),
					Vector2i(0, 1), Vector2i(0, -1)]:
				var ii := i + s.x
				var jj := j + s.y
				if ii < 0 or jj < 0 or ii >= _n or jj >= _n:
					continue
				var o := _val[jj * _n + ii]
				if o < 0.5:
					var t := (_val[k] - 0.5) / maxf(_val[k] - o, 0.0001)
					_dist[k] = minf(_dist[k], t * SUB)
	var diag := SUB * 1.4142
	for j in _n:
		for i in _n:
			var k := j * _n + i
			if _val[k] < 0.5:
				continue
			var d := _dist[k]
			if i > 0:
				d = minf(d, _dist[k - 1] + SUB)
			if j > 0:
				d = minf(d, _dist[k - _n] + SUB)
				if i > 0:
					d = minf(d, _dist[k - _n - 1] + diag)
				if i < _n - 1:
					d = minf(d, _dist[k - _n + 1] + diag)
			_dist[k] = d
	for j in range(_n - 1, -1, -1):
		for i in range(_n - 1, -1, -1):
			var k := j * _n + i
			if _val[k] < 0.5:
				continue
			var d := _dist[k]
			if i < _n - 1:
				d = minf(d, _dist[k + 1] + SUB)
			if j < _n - 1:
				d = minf(d, _dist[k + _n] + SUB)
				if i < _n - 1:
					d = minf(d, _dist[k + _n + 1] + diag)
				if i > 0:
					d = minf(d, _dist[k + _n - 1] + diag)
			_dist[k] = d


# --- сітка ----------------------------------------------------------------

## Точка многокутника клітинки: вершина сітки або перетин ізолінії з
## ребром. Висоти на перетині — лінійно між двома вершинами ребра, тож
## стіна й стеля сусідніх клітинок сходяться без щілини.
func _point(grid: Vector2, ka: int, kb: int, t: float,
		edge: bool) -> Dictionary:
	var p := _local(grid.x * SUB, grid.y * SUB)
	var rough := float(style.get("шорсткість", 0.0))
	if rough > 0.0:
		p.x += _noise.get_noise_2d(p.x + 91.0, p.z) * rough * 0.35
		p.z += _noise.get_noise_2d(p.x, p.z + 57.0) * rough * 0.35
	p.y = lerpf(_fy[ka], _fy[kb], t)
	return {"p": p, "top": lerpf(_cy[ka], _cy[kb], t), "edge": edge,
			"g": grid}


## Куди зростає «прохідність» у точці квадрата (fx, fz від 0 до 1) —
## точна похідна білінійного поля. Туди й дивиться стіна.
func _grad(ks: Array[int], fx: float, fz: float) -> Vector2:
	var v0 := _val[ks[0]]
	var v1 := _val[ks[1]]
	var v2 := _val[ks[2]]
	var v3 := _val[ks[3]]
	return Vector2((v1 - v0) * (1.0 - fz) + (v2 - v3) * fz,
			(v3 - v0) * (1.0 - fx) + (v2 - v1) * fx)


func _mesh() -> void:
	var floors := {}
	var shells := {}
	var water := SurfaceTool.new()
	water.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_water := false
	var up := Vector3.UP
	var water_drop := float(style.get("русло", 0.0)) * 0.45

	for j in _n - 1:
		for i in _n - 1:
			var ks: Array[int] = [j * _n + i, j * _n + i + 1,
					(j + 1) * _n + i + 1, (j + 1) * _n + i]
			var inside := 0
			for k in ks:
				if _val[k] >= 0.5:
					inside += 1
			if inside == 0:
				continue
			var corners: Array[Vector2] = [Vector2(i, j), Vector2(i + 1, j),
					Vector2(i + 1, j + 1), Vector2(i, j + 1)]
			var pts: Array[Dictionary] = []
			for c in 4:
				var ka := ks[c]
				var kb := ks[(c + 1) % 4]
				var a_in := _val[ka] >= 0.5
				if a_in:
					pts.append(_point(corners[c], ka, ka, 0.0, false))
				if a_in != (_val[kb] >= 0.5):
					var t := (0.5 - _val[ka]) / (_val[kb] - _val[ka])
					pts.append(_point(corners[c].lerp(corners[(c + 1) % 4], t),
							ka, kb, t, true))
			if pts.size() < 3:
				continue

			var wet := (_wet[ks[0]] + _wet[ks[1]] + _wet[ks[2]]
					+ _wet[ks[3]]) * 0.25
			var group := "хід" if wet >= 0.5 else "палата"
			if not floors.has(group):
				floors[group] = _tool()
				shells[group] = _tool()
			var fl: SurfaceTool = floors[group]
			var sh: SurfaceTool = shells[group]

			for n in range(1, pts.size() - 1):
				var a: Vector3 = pts[0]["p"]
				var b: Vector3 = pts[n]["p"]
				var c: Vector3 = pts[n + 1]["p"]
				_tri(fl, a, b, c, up, true)
				_tri(sh, _lift(pts[0]), _lift(pts[n]), _lift(pts[n + 1]),
						-up, false)

			for n in pts.size():
				var a: Dictionary = pts[n]
				var b: Dictionary = pts[(n + 1) % pts.size()]
				if not (a["edge"] and b["edge"]):
					continue
				var pa: Vector3 = a["p"]
				var pb: Vector3 = b["p"]
				if pa.distance_squared_to(pb) < 0.000001:
					continue
				var mid := (pa + pb) * 0.5
				# «Всередину» — за похідною поля, НЕ до центру многокутника.
				# На межі між клітинкою ходу й каменю поле рівно 0,5, і
				# многокутник там завтовшки нуль: його центр лежить на самій
				# стіні, напрямок нульовий, і стіна верталась навмання. Так
				# у камінь дивилась половина стін — чорні клапті на знімках
				# 13.09.2026; перевірка `walls_into_rock` показала 248 з 396.
				var at: Vector2 = (a["g"] + b["g"]) * 0.5 - Vector2(i, j)
				var slope := _grad(ks, at.x, at.y)
				var inward := Vector3(slope.x, 0.0, slope.y)
				var front := _tri(sh, pa, pb, _lift(b), inward, true)
				_tri(sh, pa, _lift(b), _lift(a), inward, true)
				walls_total += 1
				var face := Vector3(front.x, 0.0, front.z).normalized()
				if front.dot(inward) < 0.0:
					walls_against_want += 1
				if value_at(mid + face * 0.2) < value_at(mid - face * 0.2):
					walls_into_rock += 1
					if wall_samples.size() < 5:
						wall_samples.append(mid)

			# Вода — лише де весь квадрат усередині русла.
			if water_drop > 0.0 and plan.water and inside == 4 and wet > 0.7:
				var deep := true
				for k in ks:
					if _dist[k] < 0.75:
						deep = false
				if deep:
					var level := 0.0
					for k in ks:
						level += _base[k]
					level = level * 0.25 - water_drop
					var w: Array[Vector3] = []
					for q in pts:
						var wp: Vector3 = q["p"]
						w.append(Vector3(wp.x, level, wp.z))
					for n in range(1, w.size() - 1):
						_tri(water, w[0], w[n], w[n + 1], up, false)
					has_water = true

	var wall_tex: Array = style.get("стіни", ["Bricks042", 2.0])
	var room_tex: Array = style.get("стіни_палат", wall_tex)
	var floor_tex: Array = style.get("підлога", ["PavingStones147", 2.0])
	var wetness := float(style.get("мокрість", 0.0))
	var tint := _tone("тон", Color.WHITE)
	for group: String in floors.keys():
		_commit(floors[group], _material(floor_tex, wetness,
				_tone("тон_підлоги", Color.WHITE)), "Підлога-" + group)
		_commit(shells[group], _material(room_tex if group == "палата"
				else wall_tex, wetness * 0.6, tint), "Склепіння-" + group)
	if has_water:
		var still := StandardMaterial3D.new()
		still.albedo_color = Color(0.09, 0.075, 0.05, 0.82)
		still.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		still.roughness = 0.03
		still.metallic_specular = 0.9
		_commit(water, still, "Вода", false)

	var body := StaticBody3D.new()
	body.name = "Зіткнення"
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(_faces)
	var holder := CollisionShape3D.new()
	holder.shape = shape
	body.add_child(holder)
	add_child(body)


func _tool() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


func _lift(q: Dictionary) -> Vector3:
	var p: Vector3 = q["p"]
	return Vector3(p.x, q["top"], p.z)


## Трикутник лицем туди, куди `want`. У Godot лице трикутника a,b,c
## дивиться в (c−a)×(b−a) — заміряно 13.09.2026 на `generate_normals`.
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		want: Vector3, solid: bool) -> Vector3:
	if (c - a).cross(b - a).dot(want) < 0.0:
		var swap := b
		b = c
		c = swap
	for p: Vector3 in [a, b, c]:
		# Розгортка — від самого положення: однакова в стіни й стелі в
		# спільній точці, тож вершини зливаються й світло не рветься
		# на п'ятах склепіння. Малює все одно трипланар.
		st.set_uv(Vector2(p.x + p.y * 0.3, p.z + p.y * 0.3))
		st.add_vertex(p)
	triangles += 1
	if solid:
		_faces.append(a)
		_faces.append(b)
		_faces.append(c)
	return (c - a).cross(b - a)


func _commit(st: SurfaceTool, material: Material, called: String,
		shadows: bool = true) -> void:
	st.index()
	st.generate_normals()
	st.generate_tangents()
	var mesh := MeshInstance3D.new()
	mesh.name = called
	mesh.mesh = st.commit()
	mesh.material_override = material
	if not shadows:
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)


func _tone(key: String, fallback: Color) -> Color:
	var raw: Variant = style.get(key)
	if raw is Array and raw.size() >= 3:
		return Color(raw[0], raw[1], raw[2])
	return fallback


func _material(tex: Array, wetness: float, tint: Color) -> Material:
	var key := "%s|%s|%s|%s" % [tex[0], tex[1], wetness, tint]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	var base := TEX_DIR + str(tex[0])
	m.albedo_texture = _texture(base + "_Color.jpg")
	# Мокре — темніше й блискучіше: так на фото колекторів.
	m.albedo_color = tint * lerpf(1.0, 0.62, wetness)
	m.normal_enabled = true
	m.normal_texture = _texture(base + "_NormalGL.jpg")
	m.roughness_texture = _texture(base + "_Roughness.jpg")
	m.roughness = lerpf(1.0, 0.35, wetness)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = 6.0
	m.uv1_scale = Vector3.ONE / float(tex[1])
	m.texture_filter = \
			BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m


## Помилку не ковтаємо (P3): нема файлу — кажемо, котрого, і малюємо
## без нього, а не падаємо.
func _texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		push_warning("[підземелля] немає текстури %s" % path)
		print("[підземелля] ‼ немає текстури ", path)
		return null
	return load(path)


# --- світло ---------------------------------------------------------------

## Куди від клітинки стіна (перший сусід-камінь), або нуль.
func _wall_side(c: Vector2i) -> Vector2i:
	for s: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1),
			Vector2i(0, -1)]:
		if not plan.is_open(c.x + s.x, c.y + s.y):
			return s
	return Vector2i.ZERO


func _wall_cells() -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for z in plan.size:
		for x in plan.size:
			var i := plan.index(x, z)
			if plan.open[i] == 0:
				continue
			# Ніша — ні хід, ні палата: у ній кістки, не свічки.
			if plan.room_of[i] < 0 and plan.tunnel[i] == 0:
				continue
			if _wall_side(Vector2i(x, z)) != Vector2i.ZERO:
				found.append(Vector2i(x, z))
	for i in range(found.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var keep := found[i]
		found[i] = found[j]
		found[j] = keep
	return found


func _lights() -> void:
	var kind := str(style.get("світло", "смолоскипи"))
	var step := float(style.get("крок_світла", 8.0))
	var placed: Array[Vector3] = []
	var exit := plan.at(plan.room_cell(plan.exit_room))
	var boss := plan.at(plan.room_cell(plan.boss_room))
	for c in _wall_cells():
		var p := plan.at(c)
		var crowded := false
		for q in placed:
			if q.distance_squared_to(p) < step * step:
				crowded = true
				break
		if crowded:
			continue
		placed.append(p)
		var side := _wall_side(c)
		_light_at(kind, p, Vector3(side.x, 0, side.y))

	# Вихід — блідим денним, бос — приглушеним червоним. Було 2,4 на 16 м:
	# заливало червоним усю залу разом із ходом (знімки 13.09.2026).
	_omni(exit + Vector3(0, 2.2, 0), Color(0.95, 0.88, 0.62), 2.0, 12.0, false)
	_omni(boss + Vector3(0, 2.6, 0), Color(0.9, 0.45, 0.3), 1.2, 10.0, true)


func _omni(at_point: Vector3, tone: Color, energy: float, reach: float,
		shadow: bool) -> OmniLight3D:
	var lamp := OmniLight3D.new()
	lamp.light_color = tone
	lamp.light_energy = energy
	lamp.omni_range = reach
	lamp.shadow_enabled = shadow
	lamp.light_volumetric_fog_energy = 1.4
	lamp.position = at_point
	add_child(lamp)
	lights_made += 1
	return lamp


func _glow(tone: Color, strength: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tone
	m.emission_enabled = true
	m.emission = tone
	m.emission_energy_multiplier = strength
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _light_at(kind: String, p: Vector3, wall: Vector3) -> void:
	var along := Vector3(wall.z, 0, -wall.x)
	match kind:
		"свічки":
			var base := p + wall * 0.32
			var wax := StandardMaterial3D.new()
			wax.albedo_color = Color(0.86, 0.8, 0.66)
			wax.roughness = 0.6
			for n in _rng.randi_range(2, 4):
				var h := _rng.randf_range(0.08, 0.2)
				var stick := MeshInstance3D.new()
				var body := CylinderMesh.new()
				body.top_radius = 0.022
				body.bottom_radius = 0.025
				body.height = h
				body.radial_segments = 8
				stick.mesh = body
				stick.material_override = wax
				stick.position = base + along * _rng.randf_range(-0.35, 0.35) \
						+ Vector3(0, h * 0.5, 0)
				add_child(stick)
				var flame := MeshInstance3D.new()
				var drop := SphereMesh.new()
				drop.radius = 0.014
				drop.height = 0.045
				flame.mesh = drop
				flame.material_override = _glow(Color(1.0, 0.72, 0.35), 6.0)
				flame.position = stick.position \
						+ Vector3(0, h * 0.5 + 0.025, 0)
				flame.cast_shadow = \
						GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(flame)
				props_made += 2
			_omni(base + Vector3(0, 0.35, 0), Color(1.0, 0.6, 0.28), 1.3, 5.0,
					false)
		"лампи":
			var at_wall := p + wall * 0.42 + Vector3(0, 1.8, 0)
			var box := MeshInstance3D.new()
			var shade := BoxMesh.new()
			shade.size = Vector3(0.14, 0.09, 0.14)
			box.mesh = shade
			box.material_override = _glow(Color(0.95, 0.95, 1.0), 4.0)
			box.position = at_wall
			add_child(box)
			props_made += 1
			_omni(at_wall - wall * 0.2, Color(0.92, 0.94, 1.0), 2.0, 7.5,
					false)
		_:
			var at_wall := p + wall * 0.4 + Vector3(0, 1.55, 0)
			var wood := StandardMaterial3D.new()
			wood.albedo_color = Color(0.2, 0.13, 0.08)
			var stick := MeshInstance3D.new()
			var pole := CylinderMesh.new()
			pole.top_radius = 0.035
			pole.bottom_radius = 0.02
			pole.height = 0.5
			stick.mesh = pole
			stick.material_override = wood
			stick.position = at_wall
			stick.rotation = Vector3(wall.z, 0, -wall.x) * 0.35
			add_child(stick)
			var fire := MeshInstance3D.new()
			var ball := SphereMesh.new()
			ball.radius = 0.07
			ball.height = 0.2
			fire.mesh = ball
			fire.material_override = _glow(Color(1.0, 0.55, 0.2), 5.0)
			fire.position = at_wall + Vector3(0, 0.3, 0) - wall * 0.08
			fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(fire)
			props_made += 2
			_omni(fire.position - wall * 0.2, Color(1.0, 0.56, 0.24), 2.4, 9.0,
					false)


# --- оздоба ---------------------------------------------------------------

func _props() -> void:
	if bool(style.get("кістки", false)):
		_bones()
	var rubble := float(style.get("сміття", 0.0))
	if rubble > 0.0:
		_rubble(rubble)
	if bool(style.get("сталагміти", false)):
		_stalagmites()


## Купи черепів і кісток — у нішах і попід стінами палат (фото склепів).
## Моделей черепів у жодному наборі на диску немає й на Poly Haven теж —
## тож поки це фігури з куль і капсул. Згори під 50° вони читаються як
## кістки; зблизька — ні, і це записано як відкрите питання.
func _bones() -> void:
	var skulls: Array[Transform3D] = []
	var bones: Array[Transform3D] = []
	var piles: Array[Dictionary] = []
	for n: Dictionary in plan.niches:
		var cell: Vector2i = n["cell"]
		piles.append({"at": plan.at(cell), "reach": 0.35, "count": 1.0})
	var walls := _wall_cells()
	var taken := 0
	for c in walls:
		if plan.room_of[plan.index(c.x, c.y)] < 0:
			continue
		if taken >= plan.rooms.size() * 3:
			break
		var side := _wall_side(c)
		piles.append({"at": plan.at(c) + Vector3(side.x, 0, side.y) * 0.25,
				"reach": 0.6, "count": 2.0})
		taken += 1
	for pile: Dictionary in piles:
		var center: Vector3 = pile["at"]
		var reach: float = pile["reach"]
		var many: float = pile["count"]
		for s in roundi(_rng.randf_range(3, 6) * many):
			var at_p := center + Vector3(_rng.randf_range(-reach, reach),
					_rng.randf_range(0.06, 0.22 * many),
					_rng.randf_range(-reach, reach))
			var basis := Basis.from_euler(Vector3(_rng.randf_range(-0.5, 0.5),
					_rng.randf() * TAU, _rng.randf_range(-0.4, 0.4)))
			skulls.append(Transform3D(basis.scaled(Vector3(1.0, 0.88, 1.18)),
					at_p))
		for b in roundi(_rng.randf_range(6, 12) * many):
			var at_p := center + Vector3(_rng.randf_range(-reach, reach),
					_rng.randf_range(0.02, 0.15 * many),
					_rng.randf_range(-reach, reach))
			var basis := Basis.from_euler(Vector3(PI * 0.5
					+ _rng.randf_range(-0.3, 0.3), _rng.randf() * TAU, 0.0))
			bones.append(Transform3D(basis, at_p))

	var ivory := StandardMaterial3D.new()
	ivory.albedo_color = Color(0.66, 0.56, 0.42)
	ivory.roughness = 0.85
	var skull_mesh := SphereMesh.new()
	skull_mesh.radius = 0.1
	skull_mesh.height = 0.2
	skull_mesh.radial_segments = 12
	skull_mesh.rings = 6
	var bone_mesh := CapsuleMesh.new()
	bone_mesh.radius = 0.024
	bone_mesh.height = 0.38
	bone_mesh.radial_segments = 6
	_scatter(skull_mesh, ivory, skulls, "Черепи")
	_scatter(bone_mesh, ivory, bones, "Кістки")


## Купи щебеню й цегли попід стінами.
func _rubble(share: float) -> void:
	var heaps: Array[Transform3D] = []
	var want := roundi(plan.open_count() * share / 100.0)
	for c in _wall_cells():
		if heaps.size() >= want:
			break
		var side := _wall_side(c)
		var p := plan.at(c) + Vector3(side.x, 0, side.y) * 0.3
		var wide := _rng.randf_range(0.5, 1.2)
		var basis := Basis.from_euler(Vector3(0, _rng.randf() * TAU, 0)) \
				.scaled(Vector3(wide, _rng.randf_range(0.2, 0.42),
				wide * _rng.randf_range(0.6, 1.0)))
		heaps.append(Transform3D(basis, p - Vector3(0, 0.05, 0)))
	var mound := SphereMesh.new()
	mound.radius = 1.0
	mound.height = 2.0
	mound.radial_segments = 10
	mound.rings = 5
	# Ground111 під теплим світлом на кулі розовів — притемнюємо.
	_scatter(mound, _material(style.get("щебінь", ["Ground111", 1.0]), 0.0,
			_tone("тон_щебеню", Color(0.55, 0.5, 0.46))), heaps, "Щебінь")


func _stalagmites() -> void:
	var spikes: Array[Transform3D] = []
	var want := roundi(plan.open_count() / 90.0)
	for c in _wall_cells():
		if spikes.size() >= want:
			break
		var side := _wall_side(c)
		var h := _rng.randf_range(0.6, 2.2)
		var p := plan.at(c) + Vector3(side.x, 0, side.y) * 0.2
		var basis := Basis.from_euler(Vector3(_rng.randf_range(-0.1, 0.1), 0,
				_rng.randf_range(-0.1, 0.1))).scaled(Vector3(h * 0.35, h,
				h * 0.35))
		spikes.append(Transform3D(basis, p + Vector3(0, h * 0.5 - 0.1, 0)))
	var cone := CylinderMesh.new()
	cone.top_radius = 0.04
	cone.bottom_radius = 0.6
	cone.height = 1.0
	cone.radial_segments = 7
	_scatter(cone, _material(style.get("стіни", ["Rock030", 3.0]), 0.2,
			_tone("тон", Color.WHITE)), spikes, "Сталагміти")


func _scatter(mesh: Mesh, material: Material, where: Array[Transform3D],
		called: String) -> void:
	if where.is_empty():
		return
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.mesh = mesh
	many.instance_count = where.size()
	for i in where.size():
		many.set_instance_transform(i, where[i])
	var node := MultiMeshInstance3D.new()
	node.name = called
	node.multimesh = many
	node.material_override = material
	add_child(node)
	props_made += where.size()
