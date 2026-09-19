class_name DungeonPlan
extends RefCounted
## План низькорівневого підземелля (П-190): де хід, де палата, яка
## висота підлоги, де вхід і де бос.
##
## Слово замовника 13.09.2026: «до 10 штук різних підземель із складним
## ландшафтом у вигляді тунелів… з різними складностями» + мапи «Forge of
## the Gods» і фото льохів, склепів і колекторів. Родина форми та сама,
## що в схваленій 05.09.2026 печері (`cave.gd`): палати, з'єднані кривими
## ходами. Нове проти печери:
##   · палата буває «клякса» (печера) або «зала» — з прямими стінами й
##     колонами, як на фото льохів;
##   · ходи довгі й звивисті, з петлями й тупиками — скільки, каже шаблон;
##   · підлога не пласка: палати на різній глибині, ходи — схили між ними;
##   · ніші в стінах (склеп) і вода в ходах (колектор).
##
## Тут лише числа, без вузлів: план однаково годиться серверу без вікна і
## показу. Намальоване будує `DungeonView`, монстрів ставить `DungeonBook`.

## Метрів на клітинку. Було 1 м (хід 3 м, як на фото); слово замовника
## 19.09.2026: «підземелля дуже малі… зроби в 2 рази більше в масштабі».
## Тепер хід 6 м. Висоти стін і склепінь `DungeonView` множить на цей
## самий крок; перепад підлоги лишився в метрах — схили вдвічі
## пологіші, а `STEEP` так і лишився мірою на клітинку.
const CELL := 2.0
## Скільки клітинок від краю сітки не копаємо: стіна мусить мати товщину.
const MARGIN := 3
## Крутіше за це гравець уже не зійде: 0,6 м на метр — 31°.
const STEEP := 0.6

var id := ""
var title := ""
var style := ""
var tier := 1
var size := 0
## 1 — можна ходити. Рядками: z * size + x.
var open := PackedByteArray()
## 1 — клітинка належить ходу, а не палаті: там вода в колекторі й
## інша кладка в цегляному ході.
var tunnel := PackedByteArray()
## Чия палата: індекс у `rooms`, -1 — хід або камінь.
var room_of := PackedInt32Array()
## Висота підлоги в клітинці, метри.
var floor_y := PackedFloat32Array()
## {"c": Vector2i, "r": float, "shape": "клякса"|"зала", "w", "h",
##  "reach": float, "y": float}
var rooms: Array[Dictionary] = []
## Ніші в стінах: {"cell": Vector2i, "dir": Vector2i — куди відкрита}.
var niches: Array[Dictionary] = []
var pillars: Array[Vector2i] = []
var water := false
var exit_room := 0
var boss_room := 0
var dead_ends := 0
## Найкоротший шлях від входу до боса, клітинками.
var main_path: Array[Vector2i] = []

var _rng := RandomNumberGenerator.new()
var _t: Dictionary = {}


static func make(template_id: String, template: Dictionary,
		with_seed: int) -> DungeonPlan:
	var plan := DungeonPlan.new()
	plan._build(template_id, template, with_seed)
	return plan


func _build(template_id: String, t: Dictionary, with_seed: int) -> void:
	id = template_id
	_t = t
	title = str(t.get("назва", template_id))
	style = str(t.get("стиль", "печера"))
	tier = int(t.get("складність", 1))
	size = int(t.get("розмір", 80))
	water = bool(t.get("вода", false))
	_rng.seed = with_seed

	var cells := size * size
	open.resize(cells)
	open.fill(0)
	tunnel.resize(cells)
	tunnel.fill(0)
	room_of.resize(cells)
	room_of.fill(-1)
	floor_y.resize(cells)
	floor_y.fill(0.0)

	_place_rooms()
	_carve_rooms()
	# ПОРЯДОК ВАЖИТЬ, як і в `cave.gd`: згладжуємо палати, а ходи
	# копаємо ПІСЛЯ — інакше автомат з'їдає вузькі ходи разом зі
	# зв'язністю (спіймано пробою печер 05.09.2026).
	for i in int(t.get("згладжування", 2)):
		_smooth()
	_pick_boss()
	_connect()
	_dead_ends()
	if bool(t.get("колони", false)):
		_pillars()
	if bool(t.get("ніші", false)):
		_niches()
	_seal_edge()
	_blend_heights(10)
	_ease_slopes()
	_spread_into_rock()
	_pick_exit()
	main_path = path(room_cell(exit_room), room_cell(boss_room))


# --- сітка --------------------------------------------------------------

func index(x: int, z: int) -> int:
	return z * size + x


func is_open(x: int, z: int) -> bool:
	if x < 0 or z < 0 or x >= size or z >= size:
		return false
	return open[z * size + x] == 1


func height(x: int, z: int) -> float:
	x = clampi(x, 0, size - 1)
	z = clampi(z, 0, size - 1)
	return floor_y[z * size + x]


## Клітинка -> місцеві метри (центр клітинки, на підлозі).
func at(cell: Vector2i) -> Vector3:
	return Vector3((float(cell.x) + 0.5 - size * 0.5) * CELL,
			height(cell.x, cell.y),
			(float(cell.y) + 0.5 - size * 0.5) * CELL)


## Прохідна клітинка, найближча до центру палати. Центр зали може
## влучити в колону, тож центр як є брати не можна.
func room_cell(room: int) -> Vector2i:
	var c: Vector2i = rooms[room]["c"]
	for ring in 6:
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if is_open(c.x + dx, c.y + dz):
					return Vector2i(c.x + dx, c.y + dz)
	return c


# --- палати -------------------------------------------------------------

func _place_rooms() -> void:
	var want := int(_t.get("палати", 6))
	var r_min := float(_t.get("палата_від", 4))
	var r_max := float(_t.get("палата_до", 8))
	var shape_of := str(_t.get("форма", "клякса"))
	var tries := 0
	while rooms.size() < want and tries < 3000:
		tries += 1
		var r := _rng.randf_range(r_min, r_max)
		var shape := shape_of
		if shape == "мішана":
			shape = "зала" if _rng.randf() < 0.5 else "клякса"
		var w := 0
		var h := 0
		# Клякса на `cave.gd`-формулі сягає до 1,22 радіуса.
		var reach := r * 1.25
		if shape == "зала":
			w = maxi(3, roundi(r * _rng.randf_range(1.2, 2.2)))
			h = maxi(3, roundi(r * _rng.randf_range(1.2, 2.2)))
			reach = maxf(w, h) * 0.5 + 1.0
		var edge := MARGIN + ceili(reach) + 1
		if edge * 2 >= size:
			continue
		var c := Vector2i(_rng.randi_range(edge, size - 1 - edge),
				_rng.randi_range(edge, size - 1 - edge))
		var fits := true
		for was: Dictionary in rooms:
			var wc: Vector2i = was["c"]
			# 5 клітинок між краями — щоб палати не злились в одну пляму і
			# між ними лишилось місце на хід, який видно як хід.
			if Vector2(c - wc).length() < reach + float(was["reach"]) + 5.0:
				fits = false
				break
		if fits:
			rooms.append({"c": c, "r": r, "shape": shape, "w": w, "h": h,
					"reach": reach, "y": 0.0})


func _carve_rooms() -> void:
	for i in rooms.size():
		var room := rooms[i]
		var c: Vector2i = room["c"]
		if room["shape"] == "зала":
			var w: int = room["w"]
			var h: int = room["h"]
			for z in range(c.y - h / 2, c.y - h / 2 + h):
				for x in range(c.x - w / 2, c.x - w / 2 + w):
					_open_room(x, z, i)
		else:
			_blob(c, float(room["r"]), i)


## Палата неправильної форми — та сама формула, що в схваленій печері,
## плюс «лопаті» з шаблону: 1 — як у печері (палата-трилисник), 0,5 —
## майже кругла. На мапах «Forge of the Gods», що дав замовник, палати
## округлі, а трилисник на великій сітці читався як тріщина (мапа
## «Кузні глибин», 13.09.2026).
func _blob(c: Vector2i, r: float, room: int) -> void:
	var wobble := _rng.randf() * TAU
	var lobes := float(_t.get("лопаті", 1.0))
	var reach := ceili(r * 1.6)
	for z in range(c.y - reach, c.y + reach + 1):
		for x in range(c.x - reach, c.x + reach + 1):
			var d := Vector2(x - c.x, z - c.y)
			var angle := atan2(d.y, d.x)
			var edge: float = r * (1.0 - 0.28 * lobes + lobes
					* (0.34 * sin(angle * 3.0 + wobble)
					+ 0.16 * sin(angle * 5.0 - wobble * 2.0)))
			if d.length() <= edge:
				_open_room(x, z, room)


func _open_room(x: int, z: int, room: int) -> void:
	if x < MARGIN or z < MARGIN or x >= size - MARGIN or z >= size - MARGIN:
		return
	var i := z * size + x
	open[i] = 1
	room_of[i] = room


## Клітинний автомат лише для кляксових палат: зала мусить лишитись із
## прямими стінами, як на фото льохів.
func _smooth() -> void:
	var was := open.duplicate()
	var owner := room_of.duplicate()
	for z in range(MARGIN, size - MARGIN):
		for x in range(MARGIN, size - MARGIN):
			var i := z * size + x
			if owner[i] >= 0 and rooms[owner[i]]["shape"] == "зала":
				continue
			var around := 0
			var near_room := -1
			for dz in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if dx == 0 and dz == 0:
						continue
					var j: int = (z + dz) * size + x + dx
					if was[j] == 1:
						around += 1
						if owner[j] >= 0:
							near_room = owner[j]
			if around >= 5 and was[i] == 0 and near_room >= 0 \
					and rooms[near_room]["shape"] != "зала":
				open[i] = 1
				room_of[i] = near_room
			elif around <= 2 and was[i] == 1:
				open[i] = 0
				room_of[i] = -1


func _area(room: Dictionary) -> float:
	if room["shape"] == "зала":
		return float(room["w"] * room["h"])
	return PI * pow(float(room["r"]) * 0.8, 2.0)


func _pick_boss() -> void:
	var best := -1.0
	for i in rooms.size():
		var a := _area(rooms[i])
		if a > best:
			best = a
			boss_room = i


## Палати на різній глибині. Бос — найглибше, і від нього кістяком ходів
## кожна наступна палата вища за попередню — але не більше, ніж дозволяє
## довжина ходу між ними. Випадкова глибина кожної палати окремо давала
## ходи-кручі, якими не зійти: 1,56 м на метр у «Кузні глибин» і
## відрізану половину катакомб (проба 13.09.2026).
func _room_heights(edges: Array[Vector2i]) -> void:
	var drop := float(_t.get("перепад", 2.0))
	var near := {}
	for e in edges:
		near[e.x] = near.get(e.x, []) + [e.y]
		near[e.y] = near.get(e.y, []) + [e.x]
	for i in rooms.size():
		rooms[i]["y"] = 0.0
	if not rooms.is_empty():
		rooms[boss_room]["y"] = -drop
	var seen := {boss_room: true}
	var wave: Array[int] = [boss_room]
	while not wave.is_empty():
		var from: int = wave.pop_front()
		for to: int in near.get(from, []):
			if seen.has(to):
				continue
			seen[to] = true
			var rise := _rng.randf_range(0.0, minf(drop * 0.6,
					_run(from, to) * 0.3))
			rooms[to]["y"] = minf(float(rooms[from]["y"]) + rise, drop * 0.25)
			wave.append(to)
	for i in open.size():
		if room_of[i] >= 0:
			floor_y[i] = float(rooms[room_of[i]]["y"])


## Скільки ходу між краями двох палат, приблизно.
func _run(a: int, b: int) -> float:
	var centers := Vector2(rooms[a]["c"] - rooms[b]["c"]).length()
	return maxf(centers - float(rooms[a]["reach"])
			- float(rooms[b]["reach"]), 3.0)


# --- ходи ---------------------------------------------------------------

## Кістяк — дерево (кожна палата до найближчої вже з'єднаної), потім
## петлі між сусідами: на зразку «Forge of the Gods: Upper Level» теж є
## кільця, по яких можна обійти.
func _connect() -> void:
	var edges: Array[Vector2i] = []
	if rooms.size() < 2:
		_room_heights(edges)
		return
	var joined: Array[int] = [0]
	var pairs := {}
	var lengths: Array[float] = []
	while joined.size() < rooms.size():
		var best_a := -1
		var best_b := -1
		var best := 1e9
		for a: int in joined:
			for b in rooms.size():
				if b in joined:
					continue
				var far := Vector2(rooms[a]["c"] - rooms[b]["c"]).length()
				if far < best:
					best = far
					best_a = a
					best_b = b
		edges.append(Vector2i(best_a, best_b))
		pairs[Vector2i(mini(best_a, best_b), maxi(best_a, best_b))] = true
		lengths.append(best)
		joined.append(best_b)
	# Висоти — до копання: хід бере їх із палат на обох кінцях.
	_room_heights(edges)
	for e in edges:
		_tunnel(e.x, e.y)

	var usual := 0.0
	for l in lengths:
		usual += l
	usual /= float(lengths.size())
	var loops := int(_t.get("петлі", 0))
	var tries := 0
	while loops > 0 and tries < 200:
		tries += 1
		var a := _rng.randi_range(0, rooms.size() - 1)
		var b := _rng.randi_range(0, rooms.size() - 1)
		var key := Vector2i(mini(a, b), maxi(a, b))
		if a == b or pairs.has(key):
			continue
		# Петля — між сусідами, а не через усю мапу: інакше хід-хорда
		# розрізає підземелля навпіл і обхід втрачає сенс.
		if Vector2(rooms[a]["c"] - rooms[b]["c"]).length() > usual * 1.8:
			continue
		# І не між палатами на надто різній глибині — була б круча.
		if absf(float(rooms[a]["y"]) - float(rooms[b]["y"])) \
				> _run(a, b) * 0.3:
			continue
		_tunnel(a, b)
		pairs[key] = true
		loops -= 1


func _tunnel(a: int, b: int) -> void:
	var from := Vector2(rooms[a]["c"])
	var to := Vector2(rooms[b]["c"])
	_dig_line(_wiggle(from, to), float(rooms[a]["y"]), float(rooms[b]["y"]))


## Кривий хід: середину відрізка зсуваємо вбік, і так тричі. Звивистість
## шаблону — наскільки сильно.
func _wiggle(from: Vector2, to: Vector2) -> PackedVector2Array:
	var winding := float(_t.get("звивистість", 0.4))
	var points := PackedVector2Array([from, to])
	for depth in 3:
		var next := PackedVector2Array()
		for i in points.size() - 1:
			var p := points[i]
			var q := points[i + 1]
			var along := q - p
			var side := Vector2(-along.y, along.x).normalized()
			var mid := (p + q) * 0.5 \
					+ side * along.length() * winding * 0.35 \
					* _rng.randf_range(-1.0, 1.0)
			var lo := float(MARGIN + 2)
			var hi := float(size - MARGIN - 3)
			mid = Vector2(clampf(mid.x, lo, hi), clampf(mid.y, lo, hi))
			next.append(p)
			next.append(mid)
		next.append(points[points.size() - 1])
		points = next
	return points


## Копає хід уздовж ламаної; висота йде від `from_y` до `to_y` за
## пройденою довжиною — так і виходить схил між палатами.
func _dig_line(points: PackedVector2Array, from_y: float,
		to_y: float) -> void:
	var total := 0.0
	for i in points.size() - 1:
		total += points[i].distance_to(points[i + 1])
	if total <= 0.0:
		return
	# Радіус 1,5 дає хід у 3 клітинки, і сусідні клітинки завжди мають
	# спільну сторону — «сходинок», якими не пройти (пастка печер
	# 05.09.2026), тут не буває за побудовою.
	var radius := float(_t.get("хід_ширина", 3)) * 0.5
	var walked := 0.0
	for i in points.size() - 1:
		var p := points[i]
		var q := points[i + 1]
		var piece := p.distance_to(q)
		var steps := maxi(1, ceili(piece / 0.4))
		for s in steps + 1:
			var here := p.lerp(q, float(s) / float(steps))
			var y := lerpf(from_y, to_y, (walked + piece * s / steps) / total)
			_dig_disc(here, radius, y)
		walked += piece


func _dig_disc(center: Vector2, radius: float, y: float) -> void:
	var reach := ceili(radius)
	var cx := floori(center.x)
	var cz := floori(center.y)
	for z in range(cz - reach, cz + reach + 1):
		for x in range(cx - reach, cx + reach + 1):
			if x < MARGIN or z < MARGIN or x >= size - MARGIN \
					or z >= size - MARGIN:
				continue
			var d := Vector2(x + 0.5, z + 0.5).distance_to(center)
			if d > radius:
				continue
			var i := z * size + x
			if open[i] == 1:
				continue
			open[i] = 1
			tunnel[i] = 1
			floor_y[i] = y


## Тупики: відгалуження від палати в нікуди, іноді з закапелком на
## кінці. Саме вони роблять хід складним, а не просто довгим.
func _dead_ends() -> void:
	var want := int(_t.get("тупики", 0))
	var tries := 0
	while dead_ends < want and tries < 300:
		tries += 1
		var from := _rng.randi_range(0, rooms.size() - 1)
		if from == boss_room:
			continue
		var room := rooms[from]
		var dir := Vector2.from_angle(_rng.randf() * TAU)
		var start := Vector2(room["c"]) + dir * float(room["reach"])
		var finish := start + dir * _rng.randf_range(10.0, 24.0)
		var lo := float(MARGIN + 4)
		var hi := float(size - MARGIN - 5)
		if finish.x < lo or finish.y < lo or finish.x > hi or finish.y > hi:
			continue
		var y := float(room["y"])
		_dig_line(_wiggle(Vector2(room["c"]), finish), y,
				y + _rng.randf_range(-1.0, 0.6))
		if _rng.randf() < 0.5:
			var end_y := height(roundi(finish.x), roundi(finish.y))
			var r := _rng.randf_range(1.8, 2.8)
			for z in range(floori(finish.y - r), ceili(finish.y + r) + 1):
				for x in range(floori(finish.x - r), ceili(finish.x + r) + 1):
					if Vector2(x + 0.5, z + 0.5).distance_to(finish) <= r \
							and not is_open(x, z) and x >= MARGIN \
							and z >= MARGIN and x < size - MARGIN \
							and z < size - MARGIN:
						open[z * size + x] = 1
						tunnel[z * size + x] = 1
						floor_y[z * size + x] = end_y
		dead_ends += 1


# --- оздоба сітки ---------------------------------------------------------

## Колони в залах: клітинка каменю через кожні 4, не ближче 2 до стіни.
## Одинока клітинка каменю зв'язності не рве — навколо неї завжди обхід.
func _pillars() -> void:
	for i in rooms.size():
		var room := rooms[i]
		if room["shape"] != "зала" or room["w"] < 8 or room["h"] < 8:
			continue
		var c: Vector2i = room["c"]
		var x0: int = c.x - int(room["w"]) / 2
		var z0: int = c.y - int(room["h"]) / 2
		for z in range(z0 + 2, z0 + int(room["h"]) - 2, 4):
			for x in range(x0 + 2, x0 + int(room["w"]) - 2, 4):
				if is_open(x, z):
					open[z * size + x] = 0
					pillars.append(Vector2i(x, z))


## Ніші в прямій стіні: клітинка каменю, відкрита лише в один бік, а
## по боках і позаду — камінь. Не частіше, ніж через дві клітинки.
func _niches() -> void:
	var sides: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0),
			Vector2i(0, 1), Vector2i(0, -1)]
	for z in range(MARGIN + 1, size - MARGIN - 1):
		for x in range(MARGIN + 1, size - MARGIN - 1):
			if is_open(x, z):
				continue
			var opens: Array[Vector2i] = []
			for s in sides:
				if is_open(x + s.x, z + s.y):
					opens.append(s)
			if opens.size() != 1:
				continue
			var dir := opens[0]
			var back := Vector2i(x, z) - dir
			var left := Vector2i(x, z) + Vector2i(dir.y, -dir.x)
			var right := Vector2i(x, z) - Vector2i(dir.y, -dir.x)
			if is_open(back.x, back.y) or is_open(left.x, left.y) \
					or is_open(right.x, right.y):
				continue
			# Стіна мусить бути пряма: сусіди збоку теж стоять над ходом.
			if not is_open(left.x + dir.x, left.y + dir.y) \
					or not is_open(right.x + dir.x, right.y + dir.y):
				continue
			if _rng.randf() > 0.3:
				continue
			var cell := Vector2i(x, z)
			var crowded := false
			for was: Dictionary in niches:
				if Vector2(cell - was["cell"]).length() < 3.0:
					crowded = true
					break
			if crowded:
				continue
			niches.append({"cell": cell, "dir": dir})
	for n: Dictionary in niches:
		var cell: Vector2i = n["cell"]
		var face: Vector2i = cell + n["dir"]
		var i := index(cell.x, cell.y)
		open[i] = 1
		floor_y[i] = height(face.x, face.y) + 0.5


func _seal_edge() -> void:
	for z in size:
		for x in size:
			if x < MARGIN or z < MARGIN or x >= size - MARGIN \
					or z >= size - MARGIN:
				open[z * size + x] = 0


## Висоти ходів згладжуються до сусідів — стик ходу з палатою чи двох
## ходів інакше лишав би сходинку. Палати не рухаються: вони опори.
## Потім висоту розносимо в камінь поруч, щоб показ, який бере висоту
## між клітинками, не тягнув край підлоги до нуля.
func _blend_heights(passes: int) -> void:
	var sides: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0),
			Vector2i(0, 1), Vector2i(0, -1)]
	for p in passes:
		var was := floor_y.duplicate()
		for z in range(MARGIN, size - MARGIN):
			for x in range(MARGIN, size - MARGIN):
				var i := z * size + x
				if open[i] == 0 or room_of[i] >= 0:
					continue
				var sum := was[i]
				var n := 1
				for s in sides:
					if is_open(x + s.x, z + s.y):
						sum += was[(z + s.y) * size + x + s.x]
						n += 1
				floor_y[i] = sum / float(n)



## Жодна сходинка ходу не крутіша за дві третини межі. Хід, що
## перетинає чужу палату чи інший хід на іншій глибині, інакше лишав
## на стику стіну-сходинку. Палати не рухаються — підлаштовуються ходи.
func _ease_slopes() -> void:
	var limit := STEEP * 0.66
	var sides: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0),
			Vector2i(0, 1), Vector2i(0, -1)]
	for p in 400:
		var moved := 0.0
		for z in range(MARGIN, size - MARGIN):
			for x in range(MARGIN, size - MARGIN):
				var i := z * size + x
				if open[i] == 0 or room_of[i] >= 0:
					continue
				var lo := -1e9
				var hi := 1e9
				for s in sides:
					if is_open(x + s.x, z + s.y):
						var h := floor_y[(z + s.y) * size + x + s.x]
						lo = maxf(lo, h - limit)
						hi = minf(hi, h + limit)
				var want := floor_y[i]
				if lo > hi:
					want = (lo + hi) * 0.5
				else:
					want = clampf(want, lo, hi)
				moved = maxf(moved, absf(want - floor_y[i]))
				floor_y[i] = want
		if moved < 0.001:
			break


## Висоту розносимо в камінь поруч: показ бере висоту між клітинками, і
## без цього край підлоги тягнувся б до нуля. Кожен прохід — ще кільце;
## хто вже має висоту, дивимось у знімок до проходу, інакше за прохід
## розлилось би на весь рядок.
func _spread_into_rock() -> void:
	var sides: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0),
			Vector2i(0, 1), Vector2i(0, -1)]
	var filled := open.duplicate()
	for p in 3:
		var was := floor_y.duplicate()
		var had := filled.duplicate()
		for z in range(1, size - 1):
			for x in range(1, size - 1):
				var i := z * size + x
				if had[i] != 0:
					continue
				var sum := 0.0
				var n := 0
				for s in sides:
					var j := (z + s.y) * size + x + s.x
					if had[j] != 0:
						sum += was[j]
						n += 1
				if n > 0:
					floor_y[i] = sum / float(n)
					filled[i] = 1


func _pick_exit() -> void:
	if rooms.size() < 2:
		exit_room = 0
		return
	var far := distances(room_cell(boss_room))
	var best := -1
	for i in rooms.size():
		if i == boss_room:
			continue
		var c := room_cell(i)
		var d: int = far[index(c.x, c.y)]
		if d > best:
			best = d
			exit_room = i


# --- заміри ---------------------------------------------------------------

## Кроків від `from` до кожної клітинки; -1 — не дійти.
func distances(from: Vector2i) -> PackedInt32Array:
	var far := PackedInt32Array()
	far.resize(size * size)
	far.fill(-1)
	if not is_open(from.x, from.y):
		return far
	far[index(from.x, from.y)] = 0
	var wave: Array[Vector2i] = [from]
	var head := 0
	while head < wave.size():
		var c := wave[head]
		head += 1
		var d := far[index(c.x, c.y)] + 1
		for s: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1),
				Vector2i(0, -1)]:
			var n := c + s
			if not is_open(n.x, n.y) or far[index(n.x, n.y)] >= 0:
				continue
			if absf(height(n.x, n.y) - height(c.x, c.y)) > STEEP:
				continue
			far[index(n.x, n.y)] = d
			wave.append(n)
	return far


## Найкоротший шлях клітинками (порожній — не дійти).
func path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var far := distances(to)
	var result: Array[Vector2i] = []
	if far[index(from.x, from.y)] < 0:
		return result
	var c := from
	result.append(c)
	while c != to:
		var here := far[index(c.x, c.y)]
		for s: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1),
				Vector2i(0, -1)]:
			var n := c + s
			if is_open(n.x, n.y) and far[index(n.x, n.y)] == here - 1:
				c = n
				break
		result.append(c)
	return result


func open_count() -> int:
	var n := 0
	for v in open:
		if v == 1:
			n += 1
	return n


func tunnel_count() -> int:
	var n := 0
	for i in open.size():
		if open[i] == 1 and tunnel[i] == 1:
			n += 1
	return n


## Скільки прохідних клітинок досяжні від входу, не лізучи на кручі.
func reachable_count() -> int:
	var n := 0
	for d in distances(room_cell(exit_room)):
		if d >= 0:
			n += 1
	return n


## Найбільший перепад між сусідніми прохідними клітинками, метрів на метр.
func max_slope() -> float:
	var worst := 0.0
	for z in range(size - 1):
		for x in range(size - 1):
			if not is_open(x, z):
				continue
			if is_open(x + 1, z):
				worst = maxf(worst, absf(height(x + 1, z) - height(x, z)))
			if is_open(x, z + 1):
				worst = maxf(worst, absf(height(x, z + 1) - height(x, z)))
	return worst
