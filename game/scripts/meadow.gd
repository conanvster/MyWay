class_name Meadow
extends Node3D
## Різнотрав'я довкола камери: травинки, колоски, квіти, низьке листя.
##
## Слово замовника 11.09.2026: «щоб світ 2 виглядав більш реалістично з
## невеличким вітерцем, який колихає різнотрав'я та дерева».
##
## Так це робив і Lineage 2: у Unreal Engine 2 трава — окремий шар
## декору (foliage layer), розкиданий по землі випадково, без зіткнення,
## і він зникає за кілька десятків метрів. Тут те саме:
## - трава лише довкола камери — клітинки по `CELL` метрів у радіусі
##   `RADIUS`, далі туман однаково ховає все (П-65);
## - клітинка — чотири MultiMesh (купка трави, колоски, квіти, листя),
##   тобто чотири малювання замість сотень вузлів;
## - де скільки трави й наскільки вона суха — з ваг землі
##   (`GroundPaint.cover`): на луці густо, на щебені рідко, на скелі й
##   снігу нічого, під ялинами майже нічого;
## - квіти ростуть плямами одного кольору, як на справжній луці, а не
##   конфеті по всьому полю.
##
## Тільки клієнт: серверові трава ні до чого, об неї не спотикаються.

const GRASS := preload("res://scripts/grass.gdshader")
const CELL := 12.0
const RADIUS := 50.0
## Крок сітки, по якій кидаються купки, метрів.
const STEP := 0.45
## Скільки нових клітинок будувати за кадр, коли йдеш: більше — смикає.
const PER_FRAME := 2

## Колір пелюсток (sRGB): ромашка, жовтець, волошка, дзвоник, мак,
## конюшина.
const PETALS := [
	Color(0.95, 0.95, 0.90), Color(0.96, 0.80, 0.16),
	Color(0.36, 0.48, 0.92), Color(0.58, 0.40, 0.80),
	Color(0.86, 0.16, 0.10), Color(0.88, 0.52, 0.70),
]
## Колір травинок (sRGB): соковита, темна, жовтувата, сизувата.
## Світліші за землю під ними: з камери гравця трава мала читатись
## травою, а не темними волосинками на світлому килимі (знімок 11.09.2026).
const BLADES := [
	Color(0.40, 0.50, 0.16), Color(0.30, 0.42, 0.12),
	Color(0.52, 0.54, 0.22), Color(0.36, 0.47, 0.20),
]
const STRAW := Color(0.62, 0.56, 0.34)

var _land: Landscape
var _paint: ShaderMaterial
var _shapes: Array[ArrayMesh] = []
var _cells: Dictionary = {}          # Vector2i -> Array[MultiMeshInstance3D]
var _queue: Array[Vector2i] = []
var _last := Vector2(INF, INF)
var _flowers: FastNoiseLite
var _sea := 0.0


func setup(land: Landscape) -> void:
	_land = land
	_sea = land.sea_level()
	_paint = ShaderMaterial.new()
	_paint.shader = GRASS
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260911
	_shapes = [_tuft(rng), _spikes(rng), _blossoms(rng), _leaves(rng)]
	_flowers = FastNoiseLite.new()
	_flowers.seed = Landscape.SEED + 911
	_flowers.frequency = 0.035
	var tris := 0
	for shape: ArrayMesh in _shapes:
		tris += shape.get_faces().size() / 3
	print("[трава] купок 4 види, трикутників у чотирьох разом %d" % tris)


func _process(_delta: float) -> void:
	if _land == null:
		return
	var eye := get_viewport().get_camera_3d()
	if eye == null:
		return
	var at := Vector2(eye.global_position.x, eye.global_position.z)
	var moved := at.distance_to(_last)
	if moved > 2.0:
		# Перенесло далеко (вхід, оживлення, скіл додому) — будуємо все
		# одразу, інакше гравець стоїть на голій землі півсекунди.
		_plan(at, moved > CELL * 3.0)
		_last = at
	var budget := PER_FRAME
	while budget > 0 and not _queue.is_empty():
		var key: Vector2i = _queue.pop_front()
		if not _cells.has(key):
			_build(key, at)
		budget -= 1


## Скільки зараз купок і клітинок — для рядка кадрів і проб.
func counts() -> Vector2i:
	var clumps := 0
	for key: Vector2i in _cells:
		for view: MultiMeshInstance3D in _cells[key]:
			clumps += view.multimesh.instance_count
	return Vector2i(_cells.size(), clumps)


func _mid(key: Vector2i) -> Vector2:
	return Vector2((key.x + 0.5) * CELL, (key.y + 0.5) * CELL)


func _plan(at: Vector2, all_now: bool) -> void:
	var reach := ceili(RADIUS / CELL)
	var cx := floori(at.x / CELL)
	var cz := floori(at.y / CELL)
	var want := {}
	var fresh: Array = []
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var key := Vector2i(cx + dx, cz + dz)
			var far := _mid(key).distance_to(at)
			if far > RADIUS + CELL * 0.71:
				continue
			want[key] = true
			if _cells.has(key):
				_lod(key, far)
			else:
				fresh.append([far, key])
	for key: Vector2i in _cells.keys():
		if not want.has(key):
			for view: Node in _cells[key]:
				view.queue_free()
			_cells.erase(key)
	fresh.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	_queue.clear()
	for one: Array in fresh:
		_queue.append(one[1])
	if all_now:
		var started := Time.get_ticks_msec()
		var built := _queue.size()
		while not _queue.is_empty():
			_build(_queue.pop_front(), at)
		print("[трава] перенесло — %d клітинок за %d мс"
				% [built, Time.get_ticks_msec() - started])


## Рідшання вдалині — лише в шейдері, по купці (`grass.gdshader`).
##
## Спершу тут ще й відрізалась частка купок цілою клітинкою за її
## відстанню. Знімок із камери гравця (11.09.2026) показав, чим це
## обертається: полем ішли смуги густої й рідкої трави рівно по межах
## клітинок. Запас кадрів великий (543 без трави проти 1409 — див.
## CONTEXT.md), тож від цього заощадження відмовились.
func _lod(_key: Vector2i, _far: float) -> void:
	pass


## Одна клітинка. Зерно — з самої клітинки: пішов і вернувся — трава
## та сама, а не новий розкид.
func _build(key: Vector2i, at: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var places: Array = [[], [], [], []]
	var tints: Array = [[], [], [], []]
	var n := int(CELL / STEP)
	var x0 := key.x * CELL
	var z0 := key.y * CELL
	for iz in n:
		for ix in n:
			var x := x0 + (ix + rng.randf()) * STEP
			var z := z0 + (iz + rng.randf()) * STEP
			var roll := rng.randf()
			var what := rng.randf()
			var turn := rng.randf() * TAU
			var grow := rng.randf()
			var hue := rng.randf()
			var keep := rng.randf()
			var cover := _land.cover_at(x, z)
			# Стежка: на ній трави немає, а на узбіччі — найгустіше, з
			# квітами й колосками, як на знімках замовника 11.09.2026.
			var gap := _land.path_gap(x, z)
			if gap < Landscape.PATH_HALF - 0.1:
				continue
			var verge := 1.0 - smoothstep(Landscape.PATH_HALF + 0.2,
					Landscape.PATH_HALF + 3.0, gap)
			if roll > maxf(cover.r, verge * 0.95) * 1.1:
				continue
			var y := _land.surface_y(x, z)
			if y < _sea + 0.35 or _land.in_yard(x, z):
				continue
			# У річці трава не росте (06.11.2026: травинки стирчали з води).
			if _land.in_river(x, z, 0.3):
				continue
			var patch := clampf(_flowers.get_noise_2d(x, z) * 1.6 + 0.35,
					0.0, 1.0)
			var bloom := cover.b * patch * 0.28 + verge * 0.22
			var kind := 0
			if what < bloom:
				kind = 2
			elif what < bloom + 0.06 + verge * 0.08:
				kind = 1
			elif what < bloom + 0.17:
				kind = 3
			var size: float
			match kind:
				0:
					size = lerpf(0.7, 1.2, grow) * (0.55 + 0.45 * cover.r)
				1:
					size = lerpf(0.85, 1.2, grow)
				2:
					size = lerpf(0.8, 1.2, grow)
				_:
					size = lerpf(0.8, 1.3, grow)
			var basis := Basis(Vector3.UP, turn).scaled(Vector3.ONE * size)
			places[kind].append(Transform3D(basis, Vector3(x, y, z)))
			if kind == 2:
				var pick := int(floor((_flowers.get_noise_2d(x + 300.0, z)
						* 0.5 + 0.5) * PETALS.size() + hue * 1.3))
				var petal: Color = PETALS[pick % PETALS.size()]
				var lit := petal.srgb_to_linear()
				tints[kind].append(Color(lit.r, lit.g, lit.b, keep))
			else:
				var dry := cover.g * lerpf(0.55, 1.0, hue)
				tints[kind].append(Color(lerpf(0.82, 1.12, grow), dry, 0.0,
						keep))
	var made: Array[MultiMeshInstance3D] = []
	for kind in 4:
		var list: Array = places[kind]
		if list.is_empty():
			continue
		var many := MultiMesh.new()
		many.transform_format = MultiMesh.TRANSFORM_3D
		many.use_custom_data = true
		many.mesh = _shapes[kind]
		many.instance_count = list.size()
		for i in list.size():
			many.set_instance_transform(i, list[i])
			many.set_instance_custom_data(i, tints[kind][i])
		var view := MultiMeshInstance3D.new()
		view.name = "Трава%d-%d-%d" % [key.x, key.y, kind]
		view.multimesh = many
		view.material_override = _paint
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(view)
		made.append(view)
	_cells[key] = made
	_lod(key, _mid(key).distance_to(at))


# ── Форми купок. Будуються один раз, з одного зерна. ─────────────────


## Купка трави: двадцять шість травинок різної висоти й кольору.
## Перший знімок (11.09.2026) із вісімнадцятьма на 0,18 м показав
## кущики на газоні, а не луку: між купками мала бути трава, а не земля.
func _tuft(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := _begin()
	for b in 26:
		var root := _in_disc(rng, 0.26)
		var tall := rng.randf_range(0.28, 0.62)
		var wide := rng.randf_range(0.014, 0.026)
		var col := _blade_colour(rng)
		_strip(st, root, rng.randf() * TAU, tall,
				rng.randf_range(0.05, 0.30) * tall, [
			[0.0, wide, col * 0.8], [0.35, wide * 0.9, col * 0.9],
			[0.7, wide * 0.6, col], [1.0, 0.0, col * 1.08]],
				Vector2.ZERO)
	return st.commit()


## Колоски: високі тонкі стебла з волоттю на кінці й трохи трави біля
## кореня. Саме вони роблять луку лукою, а не газоном.
func _spikes(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := _begin()
	for b in 7:
		var root := _in_disc(rng, 0.12)
		var tall := rng.randf_range(0.6, 1.0)
		var stalk := _blade_colour(rng).lerp(STRAW.srgb_to_linear(), 0.3)
		var head := STRAW.srgb_to_linear() * rng.randf_range(0.85, 1.1)
		_strip(st, root, rng.randf() * TAU, tall,
				rng.randf_range(0.08, 0.25) * tall, [
			[0.0, 0.008, stalk * 0.8], [0.4, 0.007, stalk],
			[0.8, 0.007, stalk], [0.84, 0.026, head], [0.93, 0.03, head],
			[1.0, 0.0, head]], Vector2.ZERO)
	for b in 5:
		var col := _blade_colour(rng)
		var tall := rng.randf_range(0.2, 0.4)
		_strip(st, _in_disc(rng, 0.12), rng.randf() * TAU, tall,
				0.2 * tall, [[0.0, 0.02, col * 0.8], [0.5, 0.017, col],
				[1.0, 0.0, col * 1.05]], Vector2.ZERO)
	return st.commit()


## Квіти: чотири стебла, на кожному зірочка з п'яти пелюсток. Колір
## пелюсток дає екземпляр, серединка жовта, стебло зелене.
func _blossoms(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := _begin()
	var stem := Color(0.28, 0.38, 0.12).srgb_to_linear()
	var middle := Color(0.90, 0.72, 0.20).srgb_to_linear()
	for b in 4:
		var root := _in_disc(rng, 0.12)
		var tall := rng.randf_range(0.22, 0.55)
		var yaw := rng.randf() * TAU
		var curve := rng.randf_range(0.03, 0.12) * tall
		_strip(st, root, yaw, tall, curve, [
			[0.0, 0.007, stem * 0.8], [0.5, 0.006, stem],
			[1.0, 0.005, stem]], Vector2(0, 1))
		var lean := Vector3(-sin(yaw), 0.0, cos(yaw))
		var top := root + Vector3.UP * tall + lean * curve
		var radius := rng.randf_range(0.04, 0.065)
		var tilt := lean * 0.35 + Vector3.UP
		var across := lean.cross(Vector3.UP).normalized()
		var ahead := tilt.cross(across).normalized()
		var rim: Array[Vector3] = []
		for k in 10:
			var turn := TAU * k / 10.0
			var r: float = radius if k % 2 == 0 else radius * 0.45
			rim.append(top + (across * cos(turn) + ahead * sin(turn)) * r)
		var up := tilt.normalized()
		for k in 10:
			_vertex(st, top, middle, 1.0, up, Vector2(0, 1))
			_vertex(st, rim[k], Color(1, 1, 1) * rng.randf_range(0.85, 1.0),
					1.0, up, Vector2(1, 0))
			_vertex(st, rim[(k + 1) % 10],
					Color(1, 1, 1) * rng.randf_range(0.85, 1.0), 1.0, up,
					Vector2(1, 0))
	for b in 3:
		var col := _blade_colour(rng)
		_leaf(st, _in_disc(rng, 0.08), rng.randf() * TAU,
				rng.randf_range(0.08, 0.15), rng.randf_range(0.4, 0.8), 0.04,
				col, Vector2(0, 1))
	return st.commit()


## Низьке листя біля землі — подорожник, конюшина: закриває землю між
## купками трави.
func _leaves(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := _begin()
	for b in 7:
		var col := _blade_colour(rng) * 0.85
		_leaf(st, _in_disc(rng, 0.06), rng.randf() * TAU,
				rng.randf_range(0.10, 0.22), rng.randf_range(0.25, 0.7),
				rng.randf_range(0.035, 0.06), col, Vector2.ZERO)
	return st.commit()


static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _in_disc(rng: RandomNumberGenerator, radius: float) -> Vector3:
	var turn := rng.randf() * TAU
	var far := radius * sqrt(rng.randf())
	return Vector3(cos(turn) * far, 0.0, sin(turn) * far)


## Колір травинки — уже лінійний: шейдер кладе його в ALBEDO як є.
static func _blade_colour(rng: RandomNumberGenerator) -> Color:
	var pick: Color = BLADES[rng.randi() % BLADES.size()]
	if rng.randf() < 0.06:
		pick = STRAW
	return (pick * rng.randf_range(0.85, 1.15)).srgb_to_linear()


static func _vertex(st: SurfaceTool, at: Vector3, col: Color, high: float,
		normal: Vector3, flag: Vector2) -> void:
	col.a = high
	st.set_color(col)
	st.set_normal(normal)
	st.set_uv(flag)
	st.add_vertex(at)


## Травинка: смужка, що звужується до кінчика й гнеться вбік.
## `rows` — [частка висоти, ширина, колір] від кореня до кінчика.
static func _strip(st: SurfaceTool, root: Vector3, yaw: float, tall: float,
		curve: float, rows: Array, flag: Vector2) -> void:
	var across := Vector3(cos(yaw), 0.0, sin(yaw))
	var lean := Vector3(-sin(yaw), 0.0, cos(yaw))
	var last_l := Vector3.ZERO
	var last_r := Vector3.ZERO
	var last_c := Color.WHITE
	var last_t := 0.0
	for k in rows.size():
		var t: float = rows[k][0]
		var half: float = float(rows[k][1]) * 0.5
		var col: Color = rows[k][2]
		var mid := root + Vector3.UP * tall * t + lean * curve * t * t
		var l := mid - across * half
		var r := mid + across * half
		if k > 0:
			_vertex(st, last_l, last_c, last_t, lean, flag)
			_vertex(st, last_r, last_c, last_t, lean, flag)
			_vertex(st, l, col, t, lean, flag)
			if half > 0.0:
				_vertex(st, last_r, last_c, last_t, lean, flag)
				_vertex(st, r, col, t, lean, flag)
				_vertex(st, l, col, t, lean, flag)
		last_l = l
		last_r = r
		last_c = col
		last_t = t


## Листок: овал від кореня навскіс угору.
static func _leaf(st: SurfaceTool, root: Vector3, yaw: float, length: float,
		rise: float, wide: float, col: Color, flag: Vector2) -> void:
	var out := Vector3(cos(yaw) * cos(rise), sin(rise), sin(yaw) * cos(rise))
	var across := Vector3(-sin(yaw), 0.0, cos(yaw))
	var normal := across.cross(out).normalized()
	if normal.y < 0.0:
		normal = -normal
	var mid := root + out * length * 0.45
	var tip := root + out * length
	var l := mid - across * wide * 0.5
	var r := mid + across * wide * 0.5
	for tri: Array in [[root, l, r], [l, tip, r]]:
		for p: Vector3 in tri:
			var t: float = (p - root).length() / length
			_vertex(st, p, col * lerpf(0.8, 1.05, t), t * 0.4, normal, flag)
