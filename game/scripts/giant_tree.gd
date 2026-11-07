class_name GiantTree
extends Node3D
## Дерево-велет із поверхами (слово замовника 07.11.2026, `data/dereva.json`).
##
## «Додаткові локації — прив'язані до дерев»: на місці орієнтира
## «дерево-велет» мапи стоїть справжній стовбур, усередині — поверхи один
## над одним. Перший поверх — сама земля під деревом (двері в стовбурі,
## рельєф лишається рельєфом); вище — круглі підлоги, кожна вужча за
## попередню (діаметр — з даних: 100 → 50 м у найслабшого, 200 → 100 у
## найсильнішого). Найвищий поверх — без стелі, під кроною.
##
## Між поверхами — драбина, сходи або портал (слово замовника: «може
## бути драбина або портал або сходи»). Усі три — те саме для правил:
## точка внизу й точка вгорі на одній вертикалі; підійшов — запрошення
## «піднятися?» / «спуститися?», як у колі підземелля. Самі драбина й
## сходи — картинка, тіла не мають.
##
## Будується однаково на сервері й у клієнта з тих самих даних і рельєфу
## (випадковості немає зовсім): серверові потрібні стіни й підлоги як
## тіла та точки переходів, клієнтові — ще й вигляд.
##
## Вигляд (слово замовника 07.11.2026: «хочу щоб вони були унікальні,
## використай зображення та намагайся відтворити зовнішній вигляд як на
## фото … в середині стилізація та вигляд повинні бути схожими на ці»):
## три баобаби з фото — пузата «пляшка», сивий із голим гіллям і
## зрощений із кількох стовбурів; кора й листя — з тих самих фото.
## Усередині — дупло: горбкувата деревина, мох понизу, коріння через
## підлогу, папороть, овальні дупла-вікна, тепле зелене світло.
##
## Монстри: кожен поверх — свій рівень (+2 або +3 до попереднього) і
## множник усіх статів і дропу від ×2 на першому до ×4 на найвищому
## (уточнення замовника того ж дня). Зони появи робить `zones()`;
## підсилення — `boosted()`, його кличе спавнер.

const PATH := "res://data/dereva.json"
## Двері в стовбурі першого поверху, метрів.
const DOOR_WIDE := 9.0
const DOOR_HIGH := 11.0
## Товщина підлоги поверху.
const SLAB := 1.5
## Скільки відрізків на коло стіни. 96 на 200 м — по 6,5 м: на такій
## відстані від камери граней не видно.
const SEGMENTS := 96
## Точка переходу — коло такого радіуса на підлозі; по висоті — не далі
## за `STEP_HIGH` від підлоги (поверхи на одній вертикалі).
const STEP_RING := 2.6
const STEP_HIGH := 3.5
## Куди ставити після переходу: стільки метрів від точки до середини,
## щоб одразу не вискочило зворотне запрошення.
const STEP_AWAY := 4.5
## Відступ точок переходу від стіни поверху над ними.
const STEP_FROM_WALL := 6.0
## Точка телепорту з міста — стільки метрів від кори, перед дверима.
const PORT_FROM_BARK := 18.0
## Золотий кут: переходи сусідніх поверхів не стають один над одним.
const STEP_TURN := 2.39996
## Наскільки пузо баобаба ширше за потрібне поверхам (найбільше з форм) —
## для запасу довкола: там не ростуть дерева, звідти міряють землю.
const BELLY := 1.5
## Текстури з фото замовника (07.11.2026, `assets/baobab/`): кора трьох
## баобабів, деревина й мох дупла, папороть, листя крони без неба.
const BARK_DEFAULT := "res://assets/baobab/kora-2.jpg"
const INSIDE_WOOD := "res://assets/baobab/duplo.jpg"
const INSIDE_BARK := "res://assets/baobab/duplo-kora.jpg"
const MOSS := "res://assets/baobab/moh.jpg"
const FERN := "res://assets/baobab/paporot.png"
## Листя — пучки з фото крони з круглими краями (2×2 у текстурі).
const LEAVES := "res://assets/baobab/krona-puchky.png"
## Висота стовбура до ширини (з фото): пляшка вища за ширину, зрощений —
## нижчий. Стовбур вищий за поверхи — над верхнім поверхом порожня шия
## дупла до неба, як у справжнього дуплистого дерева.
const TALL := {"пляшка": 1.2, "сивий": 1.1, "зрощений": 0.85}
## Скільки метрів кори на одну текстуру.
const BARK_TILE := 14.0
const INSIDE_TILE := 7.0

static var _rules: Dictionary = {}

var spec: Dictionary = {}
var title := ""
## Підлога кожного поверху (поверх 0 — земля посередині) і ще одна —
## верх стін найвищого. Розмір — поверхів + 1.
var floors: Array[float] = []
## Внутрішній радіус кожного поверху.
var radii: Array[float] = []
var wall := 3.0
var storey := 14.0
var base_y := 0.0
var door_angle := 0.0
## [{"вид", "з", "низ": Vector3, "верх": Vector3}] — перехід з поверху
## «з» на «з»+1.
var steps: Array = []
## Рівень і множник кожного поверху.
var levels: Array[int] = []
var boosts: Array[float] = []
## Куди переносить майстер магії (x, z).
var port_spot := Vector2.ZERO
## Форма з фото: «пляшка», «сивий», «зрощений».
var shape := "пляшка"
## Земля біля дверей — від неї міряється дупло-вхід.
var door_ground := 0.0
## Верх стовбура (вище за верхній поверх — шия дупла).
var trunk_top := 0.0
## Дупла: [{"a", "y", "w", "h", "двері"}] — кут, висота середини, півосі.
var openings: Array = []
var _noise: FastNoiseLite


# ── дані ────────────────────────────────────────────────────────────────


static func rules() -> Dictionary:
	if _rules.is_empty():
		var parsed: Variant = JSON.parse_string(
				FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			_rules = parsed
		else:
			print("[дерева] ‼ %s не прочитався — дерев-велетів не буде" % PATH)
			_rules = {"дерева": []}
	return _rules


## Дерево з даних, що стоїть на цьому місці мапи; порожньо — немає.
static func spec_near(x: float, z: float, reach := 40.0) -> Dictionary:
	for one: Dictionary in rules().get("дерева", []):
		var at: Array = one.get("де", [0, 0])
		if Vector2(float(at[0]) - x, float(at[1]) - z).length() <= reach:
			return one
	return {}


## Чи точка під стовбуром якогось дерева (з запасом) — там не ростуть
## звичайні дерева й кущі. Рахується з самих даних, ще до побудови.
static func blocks(x: float, z: float, pad := 6.0) -> bool:
	var thick := float(rules().get("стіна", 3.0))
	for one: Dictionary in rules().get("дерева", []):
		var at: Array = one.get("де", [0, 0])
		var wide := float((one.get("діаметр", [0, 0]) as Array)[0]) * 0.5
		if Vector2(float(at[0]) - x, float(at[1]) - z).length() \
				<= (wide + thick) * BELLY + pad:
			return true
	return false


## Числа виду, підсилені під поверх: рівень, усі стати й кількість дропу.
## Шанс дропу не множиться — множиться те, скільки випадає.
static func boosted(tuning: Dictionary, level: int, boost: float) -> Dictionary:
	var out := tuning.duplicate(true)
	if level > 0:
		out["рівень"] = level
	if boost == 1.0:
		return out
	var stats: Dictionary = out.get("стати", {})
	for key: String in stats:
		stats[key] = int(round(float(stats[key]) * boost))
	var drops: Array = out.get("дроп", [])
	for row: Variant in drops:
		if row is Dictionary:
			for key: String in ["від", "до"]:
				if (row as Dictionary).has(key):
					row[key] = maxi(1, int(round(float(row[key]) * boost)))
	return out


# ── побудова ────────────────────────────────────────────────────────────


## `land` — краєвид (висота землі, фарби, дороги). `visual` — чи
## будувати вигляд (сервер без вікна будує лише тіла).
func build(from: Dictionary, land: Node, visual: bool) -> void:
	spec = from
	title = str(spec.get("назва", "Дерево"))
	name = "ДеревоВелет_" + title.replace(" ", "_")
	shape = str(spec.get("форма", "пляшка"))
	var r := rules()
	storey = float(r.get("висота поверху", 14.0))
	wall = float(r.get("стіна", 3.0))
	var n := maxi(2, int(spec.get("поверхів", 3)))
	var wide: Array = spec.get("діаметр", [100.0, 50.0])
	radii.clear()
	for k in n:
		var t := float(k) / float(n - 1)
		radii.append(lerpf(float(wide[0]), float(wide[1]), t) * 0.5)
	_noise = FastNoiseLite.new()
	_noise.seed = absi(hash(title)) % 100000
	_noise.frequency = 1.0
	_measure(land, n)
	_numbers(n)
	_place_steps(land, n)
	_place_openings()
	_build_bodies()
	if visual:
		_build_look(land)


## Земля під деревом: де підлога першого поверху, де низ кори і куди
## дивляться двері (на найближчу дорогу — туди, звідки прийдуть).
func _measure(land: Node, n: int) -> void:
	var r0: float = radii[0]
	var mid: float = land.height_at(position.x, position.z)
	var top_in := mid
	var low_rim := mid
	var step := 6.0
	var x := -r0
	while x <= r0:
		var z := -r0
		while z <= r0:
			if x * x + z * z <= r0 * r0:
				top_in = maxf(top_in, land.height_at(position.x + x,
						position.z + z))
			z += step
		x += step
	# Кора баобаба пузата — низ шукаємо під найширшим місцем.
	for i in 72:
		var a := TAU * float(i) / 72.0
		for far: float in [r0 + wall, (r0 + wall) * BELLY]:
			low_rim = minf(low_rim, land.height_at(position.x + cos(a) * far,
					position.z + sin(a) * far))
	base_y = low_rim - 2.0
	floors.clear()
	floors.append(mid)
	floors.append(top_in + storey)
	for k in range(2, n + 1):
		floors.append(floors[1] + float(k - 1) * storey)
	trunk_top = maxf(floors[n] + storey, base_y + float(TALL.get(shape, 1.0))
			* (radii[0] + wall) * 2.0)
	door_angle = _toward_road(land)
	door_ground = land.height_at(position.x + cos(door_angle) * r0,
			position.z + sin(door_angle) * r0)
	var out := outer_r(door_angle, door_ground + 2.0) + PORT_FROM_BARK
	port_spot = Vector2(position.x + cos(door_angle) * out,
			position.z + sin(door_angle) * out)



func _toward_road(land: Node) -> float:
	var best := INF
	var angle := 0.0
	var data: Dictionary = land.get("data") if land.get("data") is Dictionary \
			else {}
	for road: Variant in data.get("дороги", []):
		if not road is Dictionary:
			continue
		for p: Variant in (road as Dictionary).get("точки", []):
			var px := float(p[0])
			var pz := float(p[p.size() - 1]) if (p as Array).size() == 2 \
					else float(p[2])
			var far := Vector2(px - position.x, pz - position.z).length()
			if far < best:
				best = far
				angle = atan2(pz - position.z, px - position.x)
	return angle


func _numbers(n: int) -> void:
	levels.clear()
	boosts.clear()
	var level := int(spec.get("рівень першого", 1))
	var jumps: Array = spec.get("крок рівня", [2, 3])
	var mult: Array = spec.get("множник", [2.0, 4.0])
	for k in n:
		if k > 0:
			level += int(jumps[(k - 1) % jumps.size()])
		levels.append(level)
		boosts.append(lerpf(float(mult[0]), float(mult[1]),
				float(k) / float(n - 1)))


func _place_steps(land: Node, n: int) -> void:
	steps.clear()
	var kinds: Array = rules().get("переходи", ["драбина", "сходи", "портал"])
	var turn0 := absi(hash(title)) % kinds.size()
	for k in n - 1:
		var a := door_angle + PI + float(k) * STEP_TURN
		var far: float = radii[k + 1] - STEP_FROM_WALL
		var x := position.x + cos(a) * far
		var z := position.z + sin(a) * far
		var low_y: float = land.height_at(x, z) if k == 0 else floors[k]
		steps.append({"вид": str(kinds[(turn0 + k) % kinds.size()]),
				"з": k, "кут": a,
				"низ": Vector3(x, low_y, z),
				"верх": Vector3(x, floors[k + 1], z)})


# ── правила (сервер і клієнт однаково) ──────────────────────────────────


## На якому поверсі точка (за висотою) — або -1, якщо вона поза деревом.
func storey_of(at: Vector3) -> int:
	var flat := Vector2(at.x - position.x, at.z - position.z).length()
	if flat > radii[0] + 1.0:
		return -1
	for k in range(radii.size() - 1, 0, -1):
		if at.y >= floors[k] - 1.0:
			return k if flat <= radii[k] + 1.0 else -1
	return 0


## Біля якого переходу стоїть: [номер переходу, вгору?] або [].
func step_at(at: Vector3) -> Array:
	for i in steps.size():
		var s: Dictionary = steps[i]
		for up: bool in [true, false]:
			var spot: Vector3 = s["низ"] if up else s["верх"]
			if Vector2(at.x - spot.x, at.z - spot.z).length() <= STEP_RING \
					and absf(at.y - spot.y) <= STEP_HIGH:
				return [i, up]
	return []


## Куди ставити після переходу `i`: трохи до середини від точки прибуття.
func arrival(i: int, up: bool) -> Vector3:
	var s: Dictionary = steps[i]
	var spot: Vector3 = s["верх"] if up else s["низ"]
	var inward := Vector2(position.x - spot.x, position.z - spot.z).normalized()
	return Vector3(spot.x + inward.x * STEP_AWAY, spot.y + 1.0,
			spot.z + inward.y * STEP_AWAY)


## Зони появи на кожному поверсі. Види — найближчі за рівнем до рівня
## поверху (до трьох різних), зграями по «у зграї».
func zones(mobs: Dictionary) -> Array:
	var r := rules()
	var dense := float(r.get("монстрів на 1000 м²", 1.6))
	var most := int(r.get("найбільше на поверх", 48))
	var least := int(r.get("найменше на поверх", 10))
	var pack := maxi(1, int(r.get("у зграї", 5)))
	var back := float(r.get("респавн", 45.0))
	var made: Array = []
	for k in radii.size():
		var area: float = PI * radii[k] * radii[k]
		var total := clampi(int(round(area / 1000.0 * dense)), least, most)
		var packs := ceili(float(total) / float(pack))
		var kinds := _kinds_near(mobs, levels[k], 3)
		if kinds.is_empty():
			continue
		for p in packs:
			var a := door_angle + TAU * (float(p) + 0.5) / float(packs) \
					+ float(k) * 0.7
			var far: float = radii[k] * (0.55 if p % 2 == 0 else 0.3)
			var zone := MobZone.new()
			zone.name = "%s_поверх%d_зграя%d" % [title.replace(" ", "_"),
					k + 1, p + 1]
			zone.kind = int(kinds[p % kinds.size()])
			zone.count = mini(pack, total - p * pack)
			zone.aggressive = true
			zone.respawn_after = back
			zone.respawn_spread = back * 0.3
			zone.level_set = levels[k]
			zone.boost = boosts[k]
			zone.floor_y = floors[k] if k > 0 else base_y
			zone.ceil_y = floors[k + 1] - SLAB
			zone.on_floor = k > 0
			var shape := CollisionShape3D.new()
			var ring := CylinderShape3D.new()
			ring.radius = minf(12.0, radii[k] * 0.22)
			ring.height = 2.0
			shape.shape = ring
			zone.add_child(shape)
			add_child(zone)
			zone.global_position = Vector3(position.x + cos(a) * far,
					floors[k] if k > 0 else floors[0],
					position.z + sin(a) * far)
			made.append(zone)
	return made


static func _kinds_near(mobs: Dictionary, level: int, many: int) -> Array:
	var rows: Array = []
	for key: String in mobs:
		var row: Variant = mobs[key]
		if not row is Dictionary or not key.is_valid_int():
			continue
		rows.append([absi(int((row as Dictionary).get("рівень", 0)) - level),
				int(key)])
	rows.sort()
	var out: Array = []
	for row: Array in rows.slice(0, many):
		out.append(row[1])
	return out


# ── форма баобаба ───────────────────────────────────────────────────────


## Радіус кори зовні в куті `a` на висоті `y`. Спершу — найменший, що
## вміщає поверхи з товщею стіни (циліндр першого поверху, далі конус до
## верху); далі — форма з фото замовника:
##
## «пляшка» — пузатий стовбур, найширший посередині (фото 2);
## «сивий» — товстий стовбур, що розширюється до коріння (фото 3);
## «зрощений» — кілька стовбурів, зрослих в один, із глибокими жолобами
## між ними (фото 1).
##
## Ніколи не менший за потрібний поверхам — нутро завжди вміщається.
func outer_r(a: float, y: float) -> float:
	var n := radii.size()
	var need: float = radii[0] + wall
	if y > floors[1]:
		need = lerpf(radii[0] + wall, radii[n - 1] + wall,
				clampf((y - floors[1]) / (floors[n] - floors[1]), 0.0, 1.0))
	var t := clampf((y - base_y) / (trunk_top - base_y), 0.0, 1.0)
	var grow := 1.0
	var lobe := 1.0
	match shape:
		"пляшка":
			grow = 1.0 + 0.32 * pow(sin(PI * clampf(t * 1.06, 0.0, 1.0)), 1.3) \
					+ 0.12 * exp(-t * 14.0)
			lobe = 1.0 + 0.03 * sin(5.0 * a + y * 0.03) + 0.02 * sin(11.0 * a)
		"сивий":
			grow = 1.0 + 0.42 * exp(-t * 6.0) + 0.06 * sin(PI * t)
			lobe = 1.0 + 0.05 * sin(4.0 * a + y * 0.02) + 0.03 * sin(9.0 * a - y * 0.05)
		_:
			grow = 1.06 + 0.24 * exp(-t * 5.0)
			lobe = 1.0 + 0.18 * pow(0.5 + 0.5 * cos(7.0 * a + 0.5 * sin(y * 0.035)), 0.55)
	var p := Vector3(cos(a), 0.0, sin(a)) * need + Vector3(0.0, y, 0.0)
	var r := need * grow * lobe
	r += _noise.get_noise_3dv(p * 0.03) * need * 0.05 \
			+ _noise.get_noise_3dv(p * 0.14) * 1.1
	return maxf(r, need + 0.4)


## Скільки нутра «вгризається» в стіну поверху — горбкувата деревина
## дупла. Лише назовні від стіни тіла: ходити це не заважає.
func inner_bump(a: float, y: float, r: float) -> float:
	var p := Vector3(cos(a) * r, y * 1.3, sin(a) * r)
	return 0.55 + 0.55 * _noise.get_noise_3dv(p * 0.09) \
			+ 0.25 * _noise.get_noise_3dv(p * 0.4)


## Дупла: двері першого поверху й «вікна» на поверхах — овальні, як на
## фото замовника. Двері — прохід; вікна — лише світло й вигляд (тіло
## стіни за ними суцільне).
func _place_openings() -> void:
	openings.clear()
	openings.append({"a": door_angle, "y": door_ground + DOOR_HIGH * 0.42,
			"w": DOOR_WIDE * 0.58, "h": DOOR_HIGH * 0.6, "двері": true})
	var n := radii.size()
	for k in range(1, n - 1):
		for j in 2:
			var a := door_angle + PI * 0.5 + float(k) * 1.31 + float(j) * PI
			for _try in 8:
				if _clear_of_steps(a, k):
					break
				a += 0.45
			openings.append({"a": a, "y": floors[k] + 6.0, "w": 3.4,
					"h": 4.2, "двері": false})


func _clear_of_steps(a: float, k: int) -> bool:
	for s: Dictionary in steps:
		if int(s["з"]) == k or int(s["з"]) + 1 == k:
			if absf(wrapf(a - float(s["кут"]), -PI, PI)) < 0.45:
				return false
	return true


## Чи точка (кут, висота) на поверхні радіуса `r` у якомусь дуплі.
## `doors_only` — лише прохід (для тіл).
func in_opening(a: float, y: float, r: float, doors_only := false) -> bool:
	for op: Dictionary in openings:
		if doors_only and not op["двері"]:
			continue
		var du := wrapf(a - float(op["a"]), -PI, PI) * r / float(op["w"])
		var dv := (y - float(op["y"])) / float(op["h"])
		if du * du + dv * dv < 1.0:
			return true
	return false


## Точка краю дупла: `s` — кут по овалу, `r` — на якій поверхні.
func _rim_point(op: Dictionary, s: float, r: float) -> Vector2:
	return Vector2(float(op["a"]) + float(op["w"]) * cos(s) / r,
			float(op["y"]) + float(op["h"]) * sin(s))


# ── тіла ────────────────────────────────────────────────────────────────


func _build_bodies() -> void:
	var body := StaticBody3D.new()
	body.name = "Тіло"
	add_child(body)
	var faces := PackedVector3Array()
	var n := radii.size()
	# Кора зовні — грубіше, ніж видно, з проходом дверей.
	var bark_r := func(a: float, y: float) -> float: return outer_r(a, y)
	_lathe_faces(faces, 48, 4.0, base_y, trunk_top, bark_r, true)
	# Нутро першого поверху — з проходом; вище — гладкі стіни.
	var first_r: float = radii[0]
	var flat0 := func(_a: float, _y: float) -> float: return first_r
	_lathe_faces(faces, 96, 2.0, base_y, floors[1] - SLAB, flat0, true)
	for k in range(1, n):
		var rk: float = radii[k]
		var flat := func(_a: float, _y: float) -> float: return rk
		_lathe_faces(faces, 96, floors[k + 1] - floors[k], floors[k],
				floors[k + 1] - SLAB if k < n - 1 else trunk_top, flat, false)
		var floor_body := CollisionShape3D.new()
		var slab := CylinderShape3D.new()
		slab.radius = radii[k - 1]
		slab.height = SLAB
		floor_body.shape = slab
		floor_body.position = Vector3(0, floors[k] - SLAB * 0.5, 0)
		body.add_child(floor_body)
	# Прохід дверей крізь товщу — овальна труба.
	for op: Dictionary in openings:
		if op["двері"]:
			var tube := _Mesh.new()
			_tunnel(tube, op, 20)
			faces.append_array(tube.faces())
	var shape_faces := ConcavePolygonShape3D.new()
	shape_faces.backface_collision = true
	shape_faces.set_faces(faces)
	var holder := CollisionShape3D.new()
	holder.shape = shape_faces
	body.add_child(holder)


## Поверхня обертання для тіла: `sides` по колу, крок `dy` по висоті,
## `radius(a, y)`. З `cut` — без клітинок, що в проході дверей.
func _lathe_faces(faces: PackedVector3Array, sides: int, dy: float, y0: float,
		y1: float, radius: Callable, cut: bool) -> void:
	var rows := maxi(1, ceili((y1 - y0) / dy))
	for j in rows:
		var ya := lerpf(y0, y1, float(j) / float(rows))
		var yb := lerpf(y0, y1, float(j + 1) / float(rows))
		for i in sides:
			var a0 := TAU * float(i) / float(sides)
			var a1 := TAU * float(i + 1) / float(sides)
			var mid_a := (a0 + a1) * 0.5
			var ra: float = radius.call(a0, ya)
			var rb: float = radius.call(a1, ya)
			var rc: float = radius.call(a1, yb)
			var rd: float = radius.call(a0, yb)
			if cut and in_opening(mid_a, (ya + yb) * 0.5, (ra + rc) * 0.5, true):
				continue
			_quad(faces, _on(ra, a0, ya), _on(rb, a1, ya), _on(rc, a1, yb),
					_on(rd, a0, yb))


func _on(r: float, a: float, y: float) -> Vector3:
	return Vector3(cos(a) * r, y, sin(a) * r)


static func _quad(faces: PackedVector3Array, a: Vector3, b: Vector3,
		c: Vector3, d: Vector3) -> void:
	faces.append_array([a, b, c, a, c, d])


## Овальна труба крізь товщу кори: від нутра поверху до кори зовні.
func _tunnel(m: _Mesh, op: Dictionary, sides: int) -> void:
	var k := storey_of(Vector3(position.x, float(op["y"]), position.z))
	var r_in: float = radii[maxi(0, k)]
	for i in sides:
		var s0 := TAU * float(i) / float(sides)
		var s1 := TAU * float(i + 1) / float(sides)
		var a0 := _rim_point(op, s0, r_in)
		var a1 := _rim_point(op, s1, r_in)
		var o0 := _rim_point(op, s0, r_in + wall * 2.0)
		var o1 := _rim_point(op, s1, r_in + wall * 2.0)
		var p0 := _on(r_in, a0.x, a0.y)
		var p1 := _on(r_in, a1.x, a1.y)
		var q1 := _on(outer_r(o1.x, o1.y) - 0.3, o1.x, o1.y)
		var q0 := _on(outer_r(o0.x, o0.y) - 0.3, o0.x, o0.y)
		var centre := _on(r_in, float(op["a"]), float(op["y"]))
		var face := (centre - (p0 + p1) * 0.5).normalized()
		var deep := p0.distance_to(q0) / INSIDE_TILE
		var round_u := float(op["w"]) * 2.4 / INSIDE_TILE
		m.quad(p0, p1, q1, q0, face, Vector2(s0 / TAU * round_u, 0),
				Vector2(s1 / TAU * round_u, 0), Vector2(s1 / TAU * round_u, deep),
				Vector2(s0 / TAU * round_u, deep), 0.0 if op["двері"] else 99.0)


# ── вигляд ──────────────────────────────────────────────────────────────


func _build_look(land: Node) -> void:
	var n := radii.size()
	var bark := bark_material()
	var inside := ShaderMaterial.new()
	inside.shader = load("res://scripts/baobab_inside.gdshader")
	if ResourceLoader.exists(INSIDE_WOOD):
		inside.set_shader_parameter("wood", load(INSIDE_WOOD))
	if ResourceLoader.exists(MOSS):
		inside.set_shader_parameter("moss", load(MOSS))
	var lip_mat := bark
	# Кора зовні: щільна поверхня обертання, дупла вирізані.
	var outside := _Mesh.new()
	var bark_r := func(a: float, y: float) -> float: return outer_r(a, y)
	_lathe_look(outside, 144, 2.5, base_y, trunk_top, bark_r, true, true,
			BARK_TILE)
	# Верх стовбура: кільце від кори до стіни шиї дупла.
	_lid(outside, trunk_top)
	# Тінь кидає: усередині дупла має бути присмерк, а світло — з дупел
	# і згори шиєю.
	_add_mesh("Кора", outside.commit(), bark, true)
	# Нутро: стіни поверхів горбкуваті, мох понизу (висота над підлогою —
	# UV2), підлоги — мох, стелі — деревина.
	var wood := _Mesh.new()
	for k in n:
		var y0: float = base_y if k == 0 else floors[k]
		var y1: float = floors[k + 1] - SLAB if k < n - 1 else trunk_top
		var rk: float = radii[k]
		var floor_at: float = floors[k]
		var bumpy := func(a: float, y: float) -> float:
			return rk + inner_bump(a, y, rk)
		var ground_k := k
		var above := func(a: float, y: float) -> float:
			return y - (_ground_near(land, a, rk) if ground_k == 0 else floor_at)
		_lathe_look(wood, 120, 2.0, y0, y1, bumpy, false, true, INSIDE_TILE,
				above)
	for k in range(1, n):
		wood.disc(radii[k - 1] + 1.5, floors[k], true, INSIDE_TILE, 1.0)
		wood.disc(radii[k - 1] + 1.5, floors[k] - SLAB, false, INSIDE_TILE, 99.0)
	for op: Dictionary in openings:
		_tunnel(wood, op, 28)
	_add_mesh("Нутро", wood.commit(), inside, true)
	# Губа дупел зовні — товстий валик кори довкола овалу (фото 5).
	var lips := _Mesh.new()
	for op: Dictionary in openings:
		_lip(lips, op)
	_add_mesh("Губи дупел", lips.commit(), lip_mat)
	_build_steps()
	_build_hollow(land)
	_build_crown()
	var sign := Label3D.new()
	sign.text = "%s\nрівні %d–%d" % [title, levels[0], levels[n - 1]]
	sign.font_size = 128
	sign.pixel_size = 0.03
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.modulate = Color(0.95, 0.9, 0.7)
	sign.outline_size = 24
	sign.position = _on(outer_r(door_angle, door_ground + DOOR_HIGH) + 3.0,
			door_angle, door_ground + DOOR_HIGH + 7.0)
	add_child(sign)
	_build_port_mark()


## Кора з фото цього дерева (`кора`), з відтінком (`відтінок`).
func bark_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://scripts/baobab_bark.gdshader")
	var path := str(spec.get("кора", BARK_DEFAULT))
	if ResourceLoader.exists(path):
		m.set_shader_parameter("bark", load(path))
	var tone: Array = spec.get("відтінок", [1.0, 1.0, 1.0])
	m.set_shader_parameter("tint", Vector3(float(tone[0]), float(tone[1]),
			float(tone[2])))
	m.set_shader_parameter("ground_y", base_y + 2.0)
	return m


func _ground_near(land: Node, a: float, r: float) -> float:
	return land.height_at(position.x + cos(a) * r, position.z + sin(a) * r)


## Поверхня обертання для вигляду: індексована, з гладкими нормалями.
## `outward` — лицем назовні; `cut` — вирізати всі дупла; `above(a, y)` —
## висота над підлогою для моху (UV2.y).
func _lathe_look(m: _Mesh, sides: int, dy: float, y0: float, y1: float,
		radius: Callable, outward: bool, cut: bool, tile: float,
		above: Callable = Callable()) -> void:
	var rows := maxi(1, ceili((y1 - y0) / dy))
	var first := m.verts.size()
	for j in rows + 1:
		var y := lerpf(y0, y1, float(j) / float(rows))
		for i in sides + 1:
			var a := TAU * float(i) / float(sides)
			var r: float = radius.call(a, y)
			m.verts.append(_on(r, a, y))
			m.uvs.append(Vector2(a * r / tile, -y / tile))
			m.uv2s.append(Vector2(0.0, above.call(a, y) if above.is_valid()
					else 0.0))
	for j in rows:
		for i in sides:
			var v00 := first + j * (sides + 1) + i
			var v10 := v00 + 1
			var v01 := v00 + sides + 1
			var v11 := v01 + 1
			if cut:
				var mid := m.verts[v00].lerp(m.verts[v11], 0.5)
				var mid_a := atan2(mid.z, mid.x)
				if in_opening(mid_a, mid.y, Vector2(mid.x, mid.z).length()):
					continue
			var mid_v := m.verts[v00].lerp(m.verts[v11], 0.5)
			var face := Vector3(mid_v.x, 0, mid_v.z).normalized()
			if not outward:
				face = -face
			m.tri_idx(v00, v10, v11, face)
			m.tri_idx(v00, v11, v01, face)


## Обідок верху стовбура: від кори до стіни верхнього поверху.
func _lid(m: _Mesh, y: float) -> void:
	var n := radii.size()
	var sides := 144
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var r_in: float = radii[n - 1] + 0.8
		m.quad(_on(r_in, a0, y), _on(r_in, a1, y), _on(outer_r(a1, y), a1, y),
				_on(outer_r(a0, y), a0, y), Vector3.UP,
				Vector2(a0 * r_in / BARK_TILE, 0), Vector2(a1 * r_in / BARK_TILE, 0),
				Vector2(a1 * r_in / BARK_TILE, 1), Vector2(a0 * r_in / BARK_TILE, 1),
				0.0)


## Губа дупла: товстий валик кори вздовж краю овалу зовні.
func _lip(m: _Mesh, op: Dictionary) -> void:
	var sides := 40
	var ring := 8
	var thick := clampf(float(op["w"]) * 0.22, 0.6, 1.6)
	var pts: Array[Vector3] = []
	for i in sides + 1:
		var s := TAU * float(i) / float(sides)
		var guess := _rim_point(op, s, outer_r(float(op["a"]), float(op["y"])))
		pts.append(_on(outer_r(guess.x, guess.y) - thick * 0.3, guess.x, guess.y))
	var r_ring: Array[float] = []
	for i in sides + 1:
		r_ring.append(thick * (0.8 + 0.4 * absf(sin(float(i) * 0.7))))
	m.tube(pts, r_ring, ring, 3.0)


# ── нутро: коріння, папороть, світло ───────────────────────────────────


## «Всередині — як на фото»: коріння з-під стін через підлогу, папороть
## біля стін, тепле зелене світло на кожному поверсі.
func _build_hollow(land: Node) -> void:
	var n := radii.size()
	var roots := _Mesh.new()
	var ferns := _Mesh.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(hash(title + "нутро"))
	for k in n:
		var rk: float = radii[k]
		var many := clampi(int(rk / 5.0), 6, 18)
		for i in many:
			var a := door_angle + TAU * (float(i) + rng.randf_range(0.1, 0.9)) \
					/ float(many)
			if not _clear_of_steps(a, k) or (k == 0 and absf(wrapf(a
					- door_angle, -PI, PI)) < 0.35):
				continue
			var floor_y := _floor_y(land, k, a, rk * 0.6)
			var high := rng.randf_range(3.0, 7.0)
			var reach := rng.randf_range(0.35, 0.7)
			var twist := rng.randf_range(-0.25, 0.25)
			var pts: Array[Vector3] = []
			var widths: Array[float] = []
			var scale := clampf(rk / 40.0, 0.7, 2.0)
			for j in 12:
				var t := float(j) / 11.0
				var r := lerpf(rk + 0.3, rk * (1.0 - reach), t)
				var y := floor_y + high * pow(1.0 - t, 2.2) - 0.25 * t
				if k == 0:
					y = _ground_near(land, a + twist * t, r) + high \
							* pow(1.0 - t, 2.2) - 0.25 * t
				pts.append(_on(r, a + twist * t, y))
				widths.append(lerpf(1.3, 0.25, t) * scale)
			roots.tube(pts, widths, 7, 4.0)
		var bushes := clampi(int(rk * 1.3), 24, 120)
		for i in bushes:
			var a := rng.randf() * TAU
			if not _clear_of_steps(a, k):
				continue
			var r := rk * rng.randf_range(0.72, 0.97)
			var at := _on(r, a, _floor_y(land, k, a, r))
			var size := rng.randf_range(2.2, 4.8)
			for turn: float in [0.0, PI * 0.5]:
				var side := Vector3(cos(a + turn + 0.4), 0, sin(a + turn + 0.4)) \
						* size * 0.6
				var up := Vector3(0, size * 0.85, 0)
				ferns.quad(at - side, at + side, at + side + up, at - side + up,
						Vector3(cos(a), 0.3, sin(a)).normalized(),
						Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0),
						0.0)
		var lamp := OmniLight3D.new()
		lamp.name = "Світло%d" % (k + 1)
		lamp.light_color = Color(0.85, 0.95, 0.6)
		lamp.light_energy = 0.9
		lamp.omni_range = rk * 1.15
		lamp.omni_attenuation = 0.8
		lamp.shadow_enabled = false
		lamp.position = Vector3(0, (floors[k] if k > 0 else floors[0])
				+ storey * 0.6, 0)
		add_child(lamp)
	var root_mat := ShaderMaterial.new()
	root_mat.shader = load("res://scripts/baobab_inside.gdshader")
	if ResourceLoader.exists(INSIDE_BARK):
		root_mat.set_shader_parameter("wood", load(INSIDE_BARK))
	if ResourceLoader.exists(MOSS):
		root_mat.set_shader_parameter("moss", load(MOSS))
	root_mat.set_shader_parameter("tint", Vector3(0.75, 0.68, 0.6))
	root_mat.set_shader_parameter("moss_high", 0.5)
	_add_mesh("Коріння", roots.commit(), root_mat)
	var fern_mat := StandardMaterial3D.new()
	if ResourceLoader.exists(FERN):
		fern_mat.albedo_texture = load(FERN)
	fern_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	fern_mat.alpha_scissor_threshold = 0.45
	fern_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fern_mat.albedo_color = Color(0.75, 0.85, 0.65)
	fern_mat.roughness = 0.8
	_add_mesh("Папороть", ferns.commit(), fern_mat)


func _floor_y(land: Node, k: int, a: float, r: float) -> float:
	return _ground_near(land, a, r) if k == 0 else floors[k]


# ── крона ───────────────────────────────────────────────────────────────


## Гілля з верху стовбура: гладкі товсті гілки, що діляться, і листя
## пучками з фото (`krona.png`). Як на фото: «пляшка» — короткі товсті
## гілки й густа шапка; «сивий» — голе розлоге гілля; «зрощений» — довгі
## майже горизонтальні руки й широка крона.
func _build_crown() -> void:
	var n := radii.size()
	var top: float = trunk_top
	var rim: float = radii[n - 1] + wall
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(hash(title + "крона"))
	var limbs := 8
	var length := rim * 0.6
	var thick := rim * 0.14
	var rise := 0.6
	var depth := 3
	var kids := 3
	var leafy := 1.0
	match shape:
		"сивий":
			limbs = 9
			length = rim * 0.95
			thick = rim * 0.13
			rise = 0.85
			depth = 4
			kids = 2
			leafy = 0.0
		"зрощений":
			limbs = 7
			length = rim * 1.25
			thick = rim * 0.15
			rise = 0.3
			depth = 3
			kids = 3
			leafy = 1.0
	var wood := _Mesh.new()
	var leaves := _Mesh.new()
	for i in limbs:
		var a := TAU * (float(i) + rng.randf_range(0.0, 0.6)) / float(limbs)
		var from := _on(rim * 0.78, a, top - thick * 0.6)
		var dir := (Vector3(cos(a), rise, sin(a))).normalized()
		_branch(wood, leaves, rng, from, dir, length, thick, depth, kids, leafy,
				rim)
	_add_mesh("Гілля", wood.commit(), bark_material(), true)
	if leafy > 0.0:
		var leaf_mat := StandardMaterial3D.new()
		if ResourceLoader.exists(LEAVES):
			leaf_mat.albedo_texture = load(LEAVES)
		leaf_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		leaf_mat.alpha_scissor_threshold = 0.5
		leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		leaf_mat.roughness = 0.85
		_add_mesh("Листя", leaves.commit(), leaf_mat)


func _branch(wood: _Mesh, leaves: _Mesh, rng: RandomNumberGenerator,
		from: Vector3, dir: Vector3, length: float, thick: float, depth: int,
		kids: int, leafy: float, rim: float) -> void:
	var sag := Vector3(0, -length * 0.08 * (1.0 if dir.y < 0.5 else 0.3), 0)
	var to := from + dir * length + sag
	var bend := from + dir * length * 0.5 + sag * 0.3 + Vector3(rng.randf_range(
			-1, 1), rng.randf_range(0, 0.6), rng.randf_range(-1, 1)) * length * 0.08
	var pts: Array[Vector3] = []
	var widths: Array[float] = []
	for j in 7:
		var t := float(j) / 6.0
		var p := from.lerp(bend, t).lerp(bend.lerp(to, t), t)
		pts.append(p)
		widths.append(lerpf(thick, thick * 0.62, t))
	wood.tube(pts, widths, 8 if depth > 1 else 6, BARK_TILE)
	if depth <= 1:
		if leafy > 0.0:
			_leaf_puff(leaves, rng, to, rim * 0.42)
		return
	for c in kids:
		var turn := TAU * (float(c) + rng.randf()) / float(kids)
		var side := dir.cross(Vector3.UP).normalized()
		if side.length() < 0.1:
			side = Vector3.RIGHT
		var up := side.cross(dir).normalized()
		var spread := rng.randf_range(0.45, 0.8)
		var nd := (dir + (side * cos(turn) + up * sin(turn)) * spread \
				+ Vector3(0, 0.15, 0)).normalized()
		_branch(wood, leaves, rng, to, nd, length * rng.randf_range(0.6, 0.75),
				thick * 0.58, depth - 1, kids, leafy, rim)
	if leafy > 0.0 and depth == 2:
		_leaf_puff(leaves, rng, to, rim * 0.5)


## Пучок листя: три великі картки навхрест (одна майже лежить) з
## випадкового шматка фото крони.
func _leaf_puff(m: _Mesh, rng: RandomNumberGenerator, at: Vector3,
		size: float) -> void:
	var s := size * rng.randf_range(0.8, 1.25)
	var q := rng.randi() % 4
	var u0 := 0.5 * float(q % 2)
	var v0 := 0.5 * float(q / 2)
	var uv := [Vector2(u0, v0 + 0.5), Vector2(u0 + 0.5, v0 + 0.5),
			Vector2(u0 + 0.5, v0), Vector2(u0, v0)]
	for c in 3:
		var turn := rng.randf() * TAU
		var side := Vector3(cos(turn), 0, sin(turn)) * s * 0.5
		var up := Vector3(0, s * 0.42, 0)
		if c == 0:
			up = Vector3(-sin(turn), 0.25, cos(turn)).normalized() * s * 0.45
		var base := at - up * 0.5
		m.quad(base - side, base + side, base + side + up * 2.0,
				base - side + up * 2.0, Vector3.UP, uv[0], uv[1], uv[2], uv[3],
				0.0)

func _add_mesh(label: String, mesh: ArrayMesh, mat: Material,
		shadow := false) -> void:
	if mesh == null:
		return
	var view := MeshInstance3D.new()
	view.name = label
	view.mesh = mesh
	view.material_override = mat
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(view)


static func _material(albedo: String, normal: String, tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	if ResourceLoader.exists(albedo):
		m.albedo_texture = load(albedo)
	if normal != "" and ResourceLoader.exists(normal):
		m.normal_enabled = true
		m.normal_texture = load(normal)
	m.roughness = 0.95
	m.texture_repeat = true
	return m


## Драбина, сходи або портал на кожному переході; над драбиною й сходами
## — темний люк у підлозі поверху вище.
func _build_steps() -> void:
	var wood := _material("res://models/nature/Bark_DeadTree.png", "",
			Color(0.5, 0.36, 0.24))
	var hole := StandardMaterial3D.new()
	hole.albedo_color = Color(0.05, 0.04, 0.03)
	hole.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for s: Dictionary in steps:
		var low: Vector3 = s["низ"] - position
		var high: Vector3 = s["верх"] - position
		var holder := Node3D.new()
		holder.name = "Перехід%d_%s" % [int(s["з"]) + 1, s["вид"]]
		add_child(holder)
		match str(s["вид"]):
			"драбина":
				_ladder(holder, low, high, wood)
			"сходи":
				_spiral(holder, low, high, wood)
			_:
				for spot: Vector3 in [low, high]:
					var gate := Portal.new()
					gate.grade = str(spec.get("грейд порталу", "C"))
					holder.add_child(gate)
					gate.position = spot
		if str(s["вид"]) != "портал":
			var lid := MeshInstance3D.new()
			var plate := BoxMesh.new()
			plate.size = Vector3(3.2, 0.06, 3.2)
			lid.mesh = plate
			lid.material_override = hole
			lid.position = high + Vector3(0, 0.04, 0)
			holder.add_child(lid)
			var mark := Label3D.new()
			mark.text = "▲ %d поверх" % (int(s["з"]) + 2)
			mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			mark.font_size = 64
			mark.pixel_size = 0.02
			mark.position = low + Vector3(0, 3.2, 0)
			holder.add_child(mark)
			var back := Label3D.new()
			back.text = "▼ %d поверх" % (int(s["з"]) + 1)
			back.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			back.font_size = 64
			back.pixel_size = 0.02
			back.position = high + Vector3(0, 2.6, 0)
			holder.add_child(back)


func _ladder(holder: Node3D, low: Vector3, high: Vector3, wood: Material) -> void:
	var tall := high.y - low.y
	for side: float in [-0.6, 0.6]:
		var rail := MeshInstance3D.new()
		var stick := BoxMesh.new()
		stick.size = Vector3(0.18, tall, 0.18)
		rail.mesh = stick
		rail.material_override = wood
		rail.position = low + Vector3(side, tall * 0.5, 0)
		holder.add_child(rail)
	var rungs := int(tall / 0.45)
	for i in rungs:
		var rung := MeshInstance3D.new()
		var bar := BoxMesh.new()
		bar.size = Vector3(1.2, 0.1, 0.12)
		rung.mesh = bar
		rung.material_override = wood
		rung.position = low + Vector3(0, 0.3 + float(i) * 0.45, 0)
		holder.add_child(rung)


func _spiral(holder: Node3D, low: Vector3, high: Vector3, wood: Material) -> void:
	var tall := high.y - low.y
	var post := MeshInstance3D.new()
	var pole := CylinderMesh.new()
	pole.top_radius = 0.5
	pole.bottom_radius = 0.6
	pole.height = tall
	post.mesh = pole
	post.material_override = wood
	post.position = low + Vector3(0, tall * 0.5, 0)
	holder.add_child(post)
	var treads := int(tall / 0.35)
	for i in treads:
		var tread := MeshInstance3D.new()
		var plank := BoxMesh.new()
		plank.size = Vector3(2.4, 0.15, 0.8)
		tread.mesh = plank
		tread.material_override = wood
		var a := float(i) * 0.42
		tread.position = low + Vector3(cos(a) * 1.7, 0.2 + float(i) * 0.35,
				sin(a) * 1.7)
		tread.rotation.y = -a
		holder.add_child(tread)


## Коріння довкола підніжжя: широкі клини від кори в землю, щоб стовбур
## не стояв на землі циліндром. Двері лишаються вільними.
func _build_port_mark() -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.55, 0.53, 0.5)
	var at := Vector3(port_spot.x, 0, port_spot.y) - position
	var land_y: float = floors[0]
	var parent := get_parent()
	if parent != null and parent.has_method("height_at"):
		land_y = parent.height_at(port_spot.x, port_spot.y)
	for i in 8:
		var a := TAU * float(i) / 8.0
		var rock := MeshInstance3D.new()
		var block := BoxMesh.new()
		block.size = Vector3(0.8, 1.4, 0.5)
		rock.mesh = block
		rock.material_override = stone
		rock.position = Vector3(at.x + cos(a) * 3.5, land_y + 0.5,
				at.z + sin(a) * 3.5)
		rock.rotation.y = -a
		add_child(rock)



## Сітка дерева: вершини з UV й UV2, трикутники з індексами. Лицем
## трикутник повертається сам — туди, куди дивиться дана нормаль (у
## Godot лице — обхід за годинниковою стрілкою; міркувати про порядок
## вершин у кожному місці вручну — та сама вада, що вже була).
class _Mesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var index := PackedInt32Array()

	func add(p: Vector3, uv: Vector2, above: float) -> int:
		verts.append(p)
		uvs.append(uv)
		uv2s.append(Vector2(0.0, above))
		return verts.size() - 1

	func tri_idx(i: int, j: int, k: int, face: Vector3) -> void:
		var cross := (verts[j] - verts[i]).cross(verts[k] - verts[i])
		if cross.dot(face) > 0.0:
			index.append_array([i, k, j])
		else:
			index.append_array([i, j, k])

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, face: Vector3,
			ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2,
			above: float) -> void:
		var i := add(a, ua, above)
		var j := add(b, ub, above)
		var k := add(c, uc, above)
		var l := add(d, ud, above)
		tri_idx(i, j, k, face)
		tri_idx(i, k, l, face)

	func disc(r: float, y: float, up: bool, tile: float, above: float) -> void:
		var sides := 120
		var c := add(Vector3(0, y, 0), Vector2.ZERO, above)
		var first := verts.size()
		for i in sides + 1:
			var a := TAU * float(i) / float(sides)
			var p := Vector3(cos(a) * r, y, sin(a) * r)
			add(p, Vector2(p.x, p.z) / tile, above)
		for i in sides:
			tri_idx(c, first + i, first + i + 1, Vector3.UP if up else Vector3.DOWN)

	## Труба вздовж точок із товщиною в кожній — гілка, корінь, губа дупла.
	func tube(pts: Array[Vector3], widths: Array[float], sides: int,
			tile: float) -> void:
		var first := verts.size()
		var along := 0.0
		for j in pts.size():
			var fwd := (pts[mini(j + 1, pts.size() - 1)]
					- pts[maxi(j - 1, 0)]).normalized()
			var side := fwd.cross(Vector3.UP)
			if side.length() < 0.05:
				side = fwd.cross(Vector3.RIGHT)
			side = side.normalized()
			var up := side.cross(fwd).normalized()
			if j > 0:
				along += pts[j].distance_to(pts[j - 1])
			for i in sides + 1:
				var t := TAU * float(i) / float(sides)
				var p := pts[j] + (side * cos(t) + up * sin(t)) * widths[j]
				add(p, Vector2(float(i) / float(sides) * widths[j] * TAU / tile,
						along / tile), 0.0)
		for j in pts.size() - 1:
			for i in sides:
				var v00 := first + j * (sides + 1) + i
				var v10 := v00 + 1
				var v01 := v00 + sides + 1
				var v11 := v01 + 1
				var face := (verts[v00] + verts[v11]) * 0.5 \
						- (pts[j] + pts[j + 1]) * 0.5
				tri_idx(v00, v10, v11, face)
				tri_idx(v00, v11, v01, face)

	## Трикутники як є — для тіла зіткнення.
	func faces() -> PackedVector3Array:
		var out := PackedVector3Array()
		for i in index:
			out.append(verts[i])
		return out

	func commit() -> ArrayMesh:
		if index.is_empty():
			return null
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in verts.size():
			st.set_uv(uvs[i])
			st.set_uv2(uv2s[i])
			st.add_vertex(verts[i])
		for i in index:
			st.add_index(i)
		st.generate_normals()
		return st.commit()
