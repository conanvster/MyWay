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
const TALL := {"пляшка": 0.8, "сивий": 1.1, "зрощений": 0.85,
		"ялівець": 0.75, "секвоя": 1.15}
## Земля під деревом рівняється (`landscape._ground`): майданчик трохи
## ширший за кору, далі стільки метрів переходу до схилу довкола.
const PAD_OVER := 1.16
const PAD_MORE := 14.0
const PAD_EDGE := 60.0
## Зала поверху (слово замовника 13.11.2026: «форму залів наблизити до»
## референсів): стіна прямо вгору на цю частку висоти зали, далі —
## склепіння еліпсом до «ока» посередині стелі (частка радіуса зали), з
## якого падає світло. Верхній поверх має справжнє око — у небо.
const WALL_PART := 0.42
const OCULUS := 0.22
const OCULUS_TOP := 0.45
## Текстури порід, намальовані 13.11.2026 (`tools/comfyui/dereva_tekstury.py`).
const GLOW_WARM := Color(1.0, 0.5, 0.15)
const GLOW_COLD := Color(0.7, 1.0, 0.9)
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
## Тема кожного поверху з даних («поверхи»): відтінок стін, світло, мох,
## папороть, «речі» — за референсами 13.11.2026.
var themes: Array = []
## Колони поверхів із темою «колони»: [місце (від дерева), радіус, низ,
## верх] — і тіло, і вигляд.
var columns: Array = []
## Перегородки поверхів (слово замовника 13.11.2026: «перегородки … щоб не
## було пустинно … щоб під час бою з монстрами можна було сховатися або
## втекти»): [{"k", "pts": [Vector3 від дерева], "h", "w"}] — стіни з
## коріння з проходами між ними; і тіло, і вигляд.
var screens: Array = []
## Пні-укриття: [місце (від дерева), радіус, висота].
var stumps: Array = []
## Розмір пучка листя крони (частка верхнього радіуса), своя для породи.
var _puff := 0.42
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


## Радіус майданчика, до якого рівняється земля під деревом.
static func pad_radius(one: Dictionary) -> float:
	var wide := float((one.get("діаметр", [0, 0]) as Array)[0]) * 0.5
	return (wide + float(rules().get("стіна", 3.0))) * PAD_OVER + PAD_MORE


## Чи зона появи мапи (коло `pad` довкола точки) зачіпає стовбур якогось
## дерева: такі зони не будуються — там поверхи дерева.
static func covers(x: float, z: float, pad := 0.0) -> bool:
	var thick := float(rules().get("стіна", 3.0))
	for one: Dictionary in rules().get("дерева", []):
		var at: Array = one.get("де", [0, 0])
		var wide := float((one.get("діаметр", [0, 0]) as Array)[0]) * 0.5
		if Vector2(float(at[0]) - x, float(at[1]) - z).length() \
				<= (wide + thick) * 1.2 + pad:
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
	themes = spec.get("поверхи", [])
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
	_place_columns()
	_place_screens()
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
	trunk_top = maxf(floors[n] + 10.0, base_y + float(TALL.get(shape, 1.0))
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
		var spots := _pack_spots(k)
		for p in packs:
			var a: float = spots[p].x
			var far: float = spots[p].y
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


## Де стоять зграї поверху `k`: (кут, відстань від середини). Три кільця:
## на зовнішньому зграй найбільше (воно найдовше).
func _pack_spots(k: int) -> Array[Vector2]:
	var r := rules()
	var total := clampi(int(round(PI * radii[k] * radii[k] / 1000.0
			* float(r.get("монстрів на 1000 м²", 1.6)))),
			int(r.get("найменше на поверх", 10)),
			int(r.get("найбільше на поверх", 48)))
	var packs := ceili(float(total) / float(maxi(1, int(r.get("у зграї", 5)))))
	var ring_of := [0, 0, 0, 1, 1, 2]
	var in_ring := [0, 0, 0]
	for p in packs:
		in_ring[ring_of[p % 6]] += 1
	var seen := [0, 0, 0]
	var out: Array[Vector2] = []
	for p in packs:
		var lane: int = ring_of[p % 6]
		var a := door_angle + TAU * (float(seen[lane]) + 0.5) \
				/ float(in_ring[lane]) + float(k) * 0.7 + float(lane) * 0.4
		seen[lane] += 1
		var far: float = radii[k] * [0.78, 0.52, 0.26][lane]
		# Не на переході: щойно піднявся — і вже в зграї.
		for _try in 6:
			if _far_from_steps(k, a, far, 26.0):
				break
			a += 0.22
		out.append(Vector2(a, far))
	return out


## Перегородки й пні кожного поверху. Дуги на двох кільцях МІЖ кільцями
## зграй, спиці від стіни (кишені, де можна сховатись) і між дугами, пні
## врозкид. Усюди проходи: шматок перегородки не ставиться в колі зграї
## (монстр не з'явиться в стіні), біля переходу, на стежці від дверей і
## посередині під оком.
func _place_screens() -> void:
	screens.clear()
	stumps.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(hash(title + "перегородки"))
	for k in radii.size():
		var rk: float = radii[k]
		var spots := _pack_spots(k)
		if not has_thing(k, "колони"):
			for ring in 2:
				var far: float = rk * (0.65 if ring == 0 else 0.39)
				var many := clampi(int(round(TAU * far / 60.0)), 3, 12)
				for i in many:
					var a0 := door_angle + TAU * (float(i) + 0.2 + 0.5 * float(ring)) \
							/ float(many)
					var a1 := a0 + TAU / float(many) * rng.randf_range(0.5, 0.68)
					var line: Array[Vector3] = []
					var parts := maxi(2, ceili((a1 - a0) * far / 6.0))
					for j in parts + 1:
						var a := lerpf(a0, a1, float(j) / float(parts))
						line.append(_on(far + 3.0 * sin(a * 7.0 + float(k)), a,
								floors[k]))
					_add_screen(k, line, rng.randf_range(8.0, 14.0), spots)
		var spokes := clampi(int(rk / 20.0), 3, 9)
		for i in spokes:
			var a := door_angle + TAU * (float(i) + 0.5) / float(spokes) \
					+ rng.randf_range(-0.1, 0.1)
			for inner: bool in [false, true]:
				if inner and i % 2 == 0:
					continue
				var from: float = rk * (0.44 if inner else 0.72)
				var to: float = rk * (0.6 if inner else 0.97)
				var line: Array[Vector3] = []
				var parts := maxi(2, ceili((to - from) / 6.0))
				var lean := rng.randf_range(-0.12, 0.12)
				for j in parts + 1:
					var t := float(j) / float(parts)
					line.append(_on(lerpf(from, to, t), a + (0.08 if inner else 0.0)
							+ lean * t, floors[k]))
				_add_screen(k, line, rng.randf_range(7.0, 12.0), spots)
		for i in int(rk / 5.0):
			var at := _on(rk * sqrt(rng.randf()) * 0.9, rng.randf() * TAU, floors[k])
			var thick := rng.randf_range(2.0, 4.5)
			if _screen_free(k, at, spots, thick + 1.0):
				stumps.append([at, thick, rng.randf_range(3.0, 7.0)])


## Чи можна тут ставити перегородку чи пень: `pad` — півтовщини речі.
func _screen_free(k: int, at: Vector3, spots: Array[Vector2], pad: float) -> bool:
	var rk: float = radii[k]
	var flat := Vector2(at.x, at.z)
	if flat.length() < maxf(rk * 0.14, 10.0):
		return false
	var zone_r := minf(12.0, rk * 0.22)
	for spot: Vector2 in spots:
		if flat.distance_to(Vector2(cos(spot.x), sin(spot.x)) * spot.y) \
				< zone_r + pad + 0.3:
			return false
	for s: Dictionary in steps:
		if int(s["з"]) != k and int(s["з"]) + 1 != k:
			continue
		var spot: Vector3 = s["низ"] if int(s["з"]) == k else s["верх"]
		if flat.distance_to(Vector2(spot.x - position.x, spot.z - position.z)) \
				< 16.0 + pad:
			return false
	if k == 0:
		var door := Vector2(cos(door_angle), sin(door_angle))
		if flat.dot(door) > 0.0 and absf(flat.dot(Vector2(-door.y, door.x))) \
				< 9.0 + pad:
			return false
	for col: Array in columns:
		if is_equal_approx(float(col[2]), floors[k]) and flat.distance_to(
				Vector2((col[0] as Vector3).x, (col[0] as Vector3).z)) \
				< float(col[1]) + pad + 2.0:
			return false
	return true


## Лінію перегородки розбити на шматки там, де ставити не можна (проходи).
func _add_screen(k: int, line: Array[Vector3], high: float,
		spots: Array[Vector2]) -> void:
	var wide := 2.6
	var run: Array[Vector3] = []
	for j in line.size() + 1:
		if j < line.size() and _screen_free(k, line[j], spots, wide * 0.5):
			run.append(line[j])
			continue
		if run.size() >= 3:
			screens.append({"k": k, "pts": run, "h": high, "w": wide})
		run = []


## Чи точка поверху `k` (кут, відстань від середини) далі за `least`
## від обох кінців переходів цього поверху.
func _far_from_steps(k: int, a: float, far: float, least: float) -> bool:
	var at := Vector2(position.x + cos(a) * far, position.z + sin(a) * far)
	for s: Dictionary in steps:
		var spot: Vector3 = s["низ"] if int(s["з"]) == k else s["верх"]
		if int(s["з"]) != k and int(s["з"]) + 1 != k:
			continue
		if at.distance_to(Vector2(spot.x, spot.z)) < least:
			return false
	return true


## Вершина склепіння зали поверху `k`.
func hall_top(k: int) -> float:
	return floors[k + 1] - SLAB - 0.3


## Де стіна зали переходить у склепіння.
func wall_top(k: int) -> float:
	return floors[k] + (hall_top(k) - floors[k]) * WALL_PART


func oculus(k: int) -> float:
	return OCULUS_TOP if k == radii.size() - 1 else OCULUS


## Висота стелі зали поверху `k` на відстані `r` від середини.
func ceil_at(k: int, r: float) -> float:
	var part := clampf(r / radii[k], 0.0, 1.0)
	return wall_top(k) + (hall_top(k) - wall_top(k)) * sqrt(1.0 - part * part)


## Тема поверху `k` (порожня — якщо в даних немає).
func theme(k: int) -> Dictionary:
	if k < themes.size() and themes[k] is Dictionary:
		return themes[k]
	return {}


func has_thing(k: int, thing: String) -> bool:
	return (theme(k).get("речі", []) as Array).has(thing)


static func _tone(row: Dictionary, key: String, fallback: Color) -> Color:
	var v: Variant = row.get(key)
	if v is Array and (v as Array).size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]))
	return fallback


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
		"ялівець":
			# Кілька зрощених стовбурів, скручених гвинтом (фото замовника).
			grow = 1.0 + 0.10 * exp(-t * 7.0) + 0.04 * sin(PI * t)
			lobe = 1.0 + 0.10 * pow(0.5 + 0.5 * cos(6.0 * a + (y - base_y) * 0.045),
					0.6) + 0.025 * sin(13.0 * a - (y - base_y) * 0.09)
		"секвоя":
			# Рівна колона з контрфорсами коріння при землі («Генерал Шерман»).
			grow = 1.0 + 0.06 * exp(-t * 10.0)
			lobe = 1.0 + 0.07 * exp(-t * 9.0) * pow(0.5 + 0.5 * cos(11.0 * a), 0.7) \
					+ 0.01 * sin(24.0 * a + 0.3 * sin(y * 0.05))
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
			openings.append({"a": a, "y": floors[k] + storey * 0.2,
					"w": storey * 0.09, "h": storey * 0.12, "двері": false})
	# «Кора тріснула — видно небо крізь щілини»: високі вузькі просвіти.
	for k in range(1, n):
		if not has_thing(k, "щілини"):
			continue
		for j in 7:
			var a := door_angle + 0.6 + TAU * float(j) / 7.0
			for _try in 8:
				if _clear_of_steps(a, k):
					break
				a += 0.3
			openings.append({"a": a, "y": floors[k] + storey * 0.2,
					"w": 1.3 + 0.5 * float(j % 3), "h": storey * 0.17,
					"двері": false})


## Колони від підлоги до стелі на поверхах із темою «колони» — між
## кільцями зон появи, щоб монстр не з'явився всередині колони.
func _place_columns() -> void:
	columns.clear()
	var n := radii.size()
	for k in range(1, n - 1):
		if not has_thing(k, "колони"):
			continue
		for ring in 2:
			var many := 9 if ring == 0 else 6
			var far: float = radii[k] * (0.65 if ring == 0 else 0.39)
			for i in many:
				var a := door_angle + TAU * (float(i) + 0.5 * float(ring)) / float(many)
				for _try in 6:
					if _far_from_steps(k, a, far, 14.0):
						break
					a += 0.2
				columns.append([Vector3(cos(a) * far, 0.0, sin(a) * far),
						3.0 + 1.2 * float((i * 7 + ring * 3) % 4) / 3.0,
						floors[k], floors[k + 1] - SLAB])


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
	for col: Array in columns:
		var post_body := CollisionShape3D.new()
		var post := CylinderShape3D.new()
		post.radius = float(col[1])
		post.height = float(col[3]) - float(col[2])
		post_body.shape = post
		post_body.position = (col[0] as Vector3) + Vector3(0,
				(float(col[2]) + float(col[3])) * 0.5, 0)
		body.add_child(post_body)
	for sc: Dictionary in screens:
		var pts: Array = sc["pts"]
		var tall: float = float(sc["h"]) * 0.85
		for i in pts.size() - 1:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			var wall_body := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(a.distance_to(b) + 0.6, tall + 1.0, float(sc["w"]))
			wall_body.shape = box
			wall_body.position = (a + b) * 0.5 + Vector3(0, tall * 0.5 - 0.5, 0)
			wall_body.rotation.y = -atan2(b.z - a.z, b.x - a.x)
			body.add_child(wall_body)
	for st: Array in stumps:
		var stump_body := CollisionShape3D.new()
		var round_body := CylinderShape3D.new()
		round_body.radius = float(st[1])
		round_body.height = float(st[2]) + 1.0
		stump_body.shape = round_body
		stump_body.position = (st[0] as Vector3) + Vector3(0, float(st[2]) * 0.5
				- 0.5, 0)
		body.add_child(stump_body)
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
##
## Біля дверей сітка густа (DOOR_CELL м і по куту, і по висоті), а
## клітинка вилітає, коли в овалі дверей будь-яка її точка. Була вада
## (14.11.2026, замовник не зміг зайти): після збільшення дерев 13.11
## клітинка кори завширшки 15–25 м стала ширша за двері (~10 м), середина
## жодної в овал не влучала — на вигляд двері є, а тіло суцільне.
const DOOR_CELL := 1.5


func _lathe_faces(faces: PackedVector3Array, sides: int, dy: float, y0: float,
		y1: float, radius: Callable, cut: bool) -> void:
	var angles: Array[float] = []
	for i in sides + 1:
		angles.append(TAU * float(i) / float(sides))
	var heights: Array[float] = []
	var rows := maxi(1, ceili((y1 - y0) / dy))
	for j in rows + 1:
		heights.append(lerpf(y0, y1, float(j) / float(rows)))
	if cut:
		for op: Dictionary in openings:
			if not op["двері"]:
				continue
			var r_ref: float = radius.call(float(op["a"]), float(op["y"]))
			var half := (float(op["w"]) * 1.6 + 3.0) / maxf(r_ref, 1.0)
			var many := ceili(half * 2.0 * r_ref / DOOR_CELL)
			for i in many + 1:
				angles.append(fposmod(float(op["a"]) - half
						+ 2.0 * half * float(i) / float(many), TAU))
			var low := float(op["y"]) - float(op["h"]) - 2.0
			var high := float(op["y"]) + float(op["h"]) + 2.0
			var y := low
			while y <= high:
				if y > y0 and y < y1:
					heights.append(y)
				y += DOOR_CELL
		angles.sort()
		heights.sort()
	for j in heights.size() - 1:
		var ya := heights[j]
		var yb := heights[j + 1]
		if yb - ya < 0.01:
			continue
		for i in angles.size() - 1:
			var a0 := angles[i]
			var a1 := angles[i + 1]
			if a1 - a0 < 1e-5:
				continue
			var ra: float = radius.call(a0, ya)
			var rb: float = radius.call(a1, ya)
			var rc: float = radius.call(a1, yb)
			var rd: float = radius.call(a0, yb)
			if cut and _cell_in_door(a0, a1, ya, yb, (ra + rc) * 0.5):
				continue
			_quad(faces, _on(ra, a0, ya), _on(rb, a1, ya), _on(rc, a1, yb),
					_on(rd, a0, yb))


## Чи зачіпає клітинка овал дверей: середина або будь-який кут.
func _cell_in_door(a0: float, a1: float, ya: float, yb: float, r: float) -> bool:
	for p: Vector2 in [Vector2((a0 + a1) * 0.5, (ya + yb) * 0.5), Vector2(a0, ya),
			Vector2(a1, ya), Vector2(a0, yb), Vector2(a1, yb)]:
		if in_opening(p.x, p.y, r, true):
			return true
	return false


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
	var lip_mat := bark
	# Кора зовні: щільна поверхня обертання, дупла вирізані.
	var outside := _Mesh.new()
	var bark_r := func(a: float, y: float) -> float: return outer_r(a, y)
	_lathe_look(outside, 192, 2.5, base_y, trunk_top, bark_r, true, true,
			BARK_TILE)
	# Верх стовбура: кільце від кори до стіни шиї дупла.
	_lid(outside, trunk_top)
	# Тінь кидає: усередині дупла має бути присмерк, а світло — з дупел
	# і згори шиєю.
	_add_mesh("Кора", outside.commit(), bark, true)
	# Нутро: стіни поверхів горбкуваті, мох понизу (висота над підлогою —
	# UV2), підлоги — мох, стелі — деревина. Кожен поверх — своя сітка й
	# свій матеріал: відтінок стін і мох — з теми поверху.
	for k in n:
		var wood := _Mesh.new()
		var y0: float = base_y if k == 0 else floors[k]
		var y1: float = wall_top(k)
		var rk: float = radii[k]
		var floor_at: float = floors[k]
		var bumpy := func(a: float, y: float) -> float:
			return rk + inner_bump(a, y, rk)
		var ground_k := k
		var above := func(a: float, y: float) -> float:
			return y - (_ground_near(land, a, rk) if ground_k == 0 else floor_at)
		_lathe_look(wood, clampi(int(TAU * rk / 4.0), 120, 300), 2.0, y0, y1,
				bumpy, false, true, INSIDE_TILE, above)
		if k > 0:
			wood.disc(radii[k - 1] + 1.5, floors[k], true, INSIDE_TILE, 1.0)
		_dome(wood, k)
		if k == n - 1:
			# Шия дупла над оком верхнього поверху — до неба.
			var neck: float = rk * OCULUS_TOP
			var straight := func(_a: float, _y: float) -> float: return neck
			_lathe_look(wood, 96, 4.0, ceil_at(k, neck), trunk_top, straight,
					false, false, INSIDE_TILE)
		for op: Dictionary in openings:
			if maxi(0, storey_of(Vector3(position.x, float(op["y"]),
					position.z))) == k:
				_tunnel(wood, op, 28)
		_add_mesh("Нутро%d" % (k + 1), wood.commit(), inside_material(k), true)
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


## Деревина нутра поверху `k`: текстура породи («нутро»), відтінок стін і
## мох — із теми поверху.
func inside_material(k: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://scripts/baobab_inside.gdshader")
	var path := str(spec.get("нутро", INSIDE_WOOD))
	if not ResourceLoader.exists(path):
		path = INSIDE_WOOD
	if ResourceLoader.exists(path):
		m.set_shader_parameter("wood", load(path))
	if ResourceLoader.exists(MOSS):
		m.set_shader_parameter("moss", load(MOSS))
	var row := theme(k)
	var walls := _tone(row, "стіни", Color.WHITE)
	m.set_shader_parameter("tint", Vector3(walls.r, walls.g, walls.b))
	m.set_shader_parameter("moss_high", float(row.get("мох", 2.6)))
	var green := _tone(row, "мох колір", Color.WHITE)
	m.set_shader_parameter("moss_tint", Vector3(green.r, green.g, green.b))
	return m


## Кора з фото цього дерева (`кора`), з відтінком (`відтінок`).
func bark_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://scripts/baobab_bark.gdshader")
	var path := str(spec.get("кора", BARK_DEFAULT))
	if not ResourceLoader.exists(path):
		path = BARK_DEFAULT
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
		# U — кут на СЕРЕДНІЙ радіус ряду, а не на свій. При `a * r` похідна
		# по куту r + a·dr/da: на горбах ялівця й контрфорсах секвої вона
		# ставала від'ємною вже за пів обороту, текстура йшла назад і кора
		# біля дверей складалась зигзагами-гармошкою (14.11.2026).
		var row_r: Array[float] = []
		var mean := 0.0
		for i in sides + 1:
			var r: float = radius.call(TAU * float(i) / float(sides), y)
			row_r.append(r)
			mean += r
		mean /= float(sides + 1)
		for i in sides + 1:
			var a := TAU * float(i) / float(sides)
			var r: float = row_r[i]
			m.verts.append(_on(r, a, y))
			m.uvs.append(Vector2(a * mean / tile, -y / tile))
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


## Склепіння зали: від верху стіни еліпсом до ока посередині.
func _dome(m: _Mesh, k: int) -> void:
	var rk: float = radii[k]
	var sides := clampi(int(TAU * rk / 5.0), 96, 240)
	var rows := 14
	var low := wall_top(k)
	var high := hall_top(k)
	var end := acos(oculus(k))
	var first := m.verts.size()
	for j in rows + 1:
		var th := end * float(j) / float(rows)
		for i in sides + 1:
			var a := TAU * float(i) / float(sides)
			var r := (rk + inner_bump(a, low + th * 20.0, rk)) * cos(th)
			m.verts.append(_on(r, a, low + (high - low) * sin(th)))
			m.uvs.append(Vector2(a * rk / INSIDE_TILE, -(low + th * rk)
					/ INSIDE_TILE))
			m.uv2s.append(Vector2(0.0, 99.0))
	var centre := Vector3(0, floors[k], 0)
	for j in rows:
		for i in sides:
			var v00 := first + j * (sides + 1) + i
			var v10 := v00 + 1
			var v01 := v00 + sides + 1
			var v11 := v01 + 1
			var face := centre - m.verts[v00].lerp(m.verts[v11], 0.5)
			m.tri_idx(v00, v10, v11, face)
			m.tri_idx(v00, v11, v01, face)


## Обідок верху стовбура: від кори до стіни верхнього поверху.
func _lid(m: _Mesh, y: float) -> void:
	var n := radii.size()
	var sides := 144
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var r_in: float = radii[n - 1] * OCULUS_TOP
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
	var bag := {"коріння": roots}
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(hash(title + "нутро"))
	for k in n:
		var rk: float = radii[k]
		var row := theme(k)
		var many := clampi(int(rk / 5.0), 6, 40)
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
			var scale := clampf(rk / 40.0, 0.7, 3.0)
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
		var bushes := int(float(clampi(int(rk * 1.3), 24, 260))
				* float(row.get("папороть", 1.0)))
		var lush := 1.0 + 0.35 * (float(row.get("папороть", 1.0)) - 1.0)
		for i in bushes:
			var a := rng.randf() * TAU
			if not _clear_of_steps(a, k):
				continue
			var r := rk * rng.randf_range(0.72 if lush <= 1.0 else 0.25, 0.97)
			var at := _on(r, a, _floor_y(land, k, a, r))
			var size := rng.randf_range(2.2, 4.8) * maxf(lush, 0.6)
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
		lamp.light_color = _tone(row, "світло", Color(0.85, 0.95, 0.6))
		# Зала не залежить від пори доби надворі: світло з ока сильне, і
		# ще одне, слабше, знизу посередині — щоб було видно ребра стін.
		lamp.light_energy = float(row.get("сила", 0.9)) * 2.2
		lamp.omni_range = rk * 1.8 + storey
		lamp.omni_attenuation = 0.5
		var fill := OmniLight3D.new()
		fill.name = "Відсвіт%d" % (k + 1)
		fill.light_color = lamp.light_color.lerp(Color.WHITE, 0.3)
		fill.light_energy = float(row.get("сила", 0.9)) * 0.9
		fill.omni_range = rk * 1.5
		fill.omni_attenuation = 0.4
		fill.shadow_enabled = false
		fill.position = Vector3(0, floors[k] + 9.0, 0)
		add_child(fill)
		lamp.shadow_enabled = false
		lamp.position = Vector3(0, ceil_at(k, rk * oculus(k)) - 5.0, 0)
		add_child(lamp)
		_build_ribs(land, roots, k, rng)
		_build_skylight(k, lamp.light_color)
		_build_things(land, bag, k, rng)
	for col: Array in columns:
		var at: Vector3 = col[0]
		var pts: Array[Vector3] = []
		var widths: Array[float] = []
		for j in 9:
			var t := float(j) / 8.0
			pts.append(at + Vector3(sin(t * 5.0 + at.x) * 0.8, lerpf(float(col[2])
					- 0.5, float(col[3]) + 0.5, t), cos(t * 4.0 + at.z) * 0.8))
			widths.append(float(col[1]) * (1.0 + 0.5 * pow(absf(2.0 * t - 1.0),
					2.5)))
		roots.tube(pts, widths, 12, 5.0)
	_build_screens(roots)
	var root_mat := ShaderMaterial.new()
	root_mat.shader = load("res://scripts/baobab_inside.gdshader")
	var root_wood := str(spec.get("кора", INSIDE_BARK)) if shape != "пляшка" \
			else INSIDE_BARK
	if not ResourceLoader.exists(root_wood):
		root_wood = INSIDE_BARK
	if ResourceLoader.exists(root_wood):
		root_mat.set_shader_parameter("wood", load(root_wood))
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
	_add_things(bag)


## Ребра зали, як на референсах: товсте коріння з підлоги вгору стіною й
## склепінням до ока, між сусідніми ребрами — арка (ніша). Картинка, без
## тіл.
func _build_ribs(land: Node, roots: _Mesh, k: int,
		rng: RandomNumberGenerator) -> void:
	var rk: float = radii[k]
	var many := clampi(int(rk / 6.0), 12, 28)
	var big := clampf(rk / 60.0, 0.8, 1.8)
	var low := wall_top(k)
	var twist := 0.5 if shape == "ялівець" else 0.12
	var end := acos(oculus(k))
	var at: Array[float] = []
	for i in many:
		at.append(door_angle + TAU * (float(i) + 0.5 + rng.randf_range(-0.18, 0.18))
				/ float(many))
	for i in many:
		var a: float = at[i]
		if k == 0 and absf(wrapf(a - door_angle, -PI, PI)) < 0.2:
			continue
		var bend := twist * rng.randf_range(0.5, 1.0) * (1.0 if i % 2 == 0 else -0.4)
		var pts: Array[Vector3] = []
		var widths: Array[float] = []
		# Палець кореня на підлозі → до стіни.
		for j in 4:
			var t := float(j) / 3.0
			var r := lerpf(rk * 0.78, rk + 0.2, t)
			pts.append(_on(r, a - bend * 0.3 * (1.0 - t), _floor_y(land, k, a, r)
					+ 0.2 + 5.0 * t * t))
			widths.append(lerpf(0.9, 3.0, t) * big)
		# Стіною вгору.
		for j in range(1, 5):
			var t := float(j) / 4.0
			pts.append(_on(rk + 0.2, a + bend * 0.25 * t, lerpf(floors[k] + 5.2,
					low, t)))
			widths.append(lerpf(3.0, 2.3, t) * big)
		# Склепінням до ока.
		for j in range(1, 11):
			var th := end * float(j) / 10.0
			pts.append(_on(rk * cos(th) + 0.2, a + bend * (0.25 + th), low
					+ (hall_top(k) - low) * sin(th) - 0.4))
			widths.append(lerpf(2.3, 1.2, float(j) / 10.0) * big)
		roots.tube(pts, widths, 8, 5.0)
		# Арка-ніша до наступного ребра.
		var b: float = at[(i + 1) % many]
		if b < a:
			b += TAU
		var arch: Array[Vector3] = []
		var arch_w: Array[float] = []
		for j in 9:
			var t := float(j) / 8.0
			arch.append(_on(rk + 0.3, lerpf(a, b, t), floors[k] + (low - floors[k])
					* (0.55 + 0.4 * sin(PI * t))))
			arch_w.append((1.0 + 0.6 * absf(cos(PI * t))) * big)
		roots.tube(arch, arch_w, 6, 5.0)
	# Обід ока.
	var rim: Array[Vector3] = []
	var rim_w: Array[float] = []
	var hole: float = rk * oculus(k)
	for j in 33:
		rim.append(_on(hole + 0.6, TAU * float(j) / 32.0, ceil_at(k, hole) - 0.3))
		rim_w.append(1.5 * big)
	roots.tube(rim, rim_w, 8, 5.0)


## Світло з ока склепіння: світлий диск «неба» в оці (на верхньому поверсі
## небо справжнє) і напівпрозорий сніп променів до підлоги.
func _build_skylight(k: int, tone: Color) -> void:
	var rk: float = radii[k]
	var hole: float = rk * oculus(k)
	var top := ceil_at(k, hole)
	var pale := tone.lerp(Color.WHITE, 0.55)
	if k < radii.size() - 1:
		var sky := _Mesh.new()
		sky.disc_at(Vector3(0, top + 0.5, 0), hole + 1.0, 40)
		var sky_mat := StandardMaterial3D.new()
		sky_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sky_mat.albedo_color = pale
		sky_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		sky_mat.disable_fog = true
		_add_mesh("Око%d" % (k + 1), sky.commit(), sky_mat)
	var rays := _Mesh.new()
	# Чотири снопи один в одному — край променів м'який, а не «абажур».
	for layer in 4:
		var part := 1.0 - 0.22 * float(layer)
		var wide := rk * 0.36 * part
		for i in 32:
			var a0 := TAU * float(i) / 32.0
			var a1 := TAU * float(i + 1) / 32.0
			rays.quad(_on(hole * part, a0, top), _on(hole * part, a1, top),
					_on(wide, a1, floors[k] + 0.3), _on(wide, a0, floors[k] + 0.3),
					Vector3(cos(a0), 0, sin(a0)), Vector2(0, 0), Vector2(1, 0),
					Vector2(1, 1), Vector2(0, 1), 0.0)
	var ray_mat := StandardMaterial3D.new()
	ray_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ray_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ray_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ray_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ray_mat.albedo_color = Color(pale.r, pale.g, pale.b, 0.012)
	ray_mat.disable_fog = true
	_add_mesh("Промені%d" % (k + 1), rays.commit(), ray_mat)


## Вигляд перегородок і пнів: стіна з кори, ширша при підлозі, з нерівним
## верхом, товстим коренем по гребеню і стовбурцями на кінцях.
func _build_screens(roots: _Mesh) -> void:
	for sc: Dictionary in screens:
		var pts: Array = sc["pts"]
		var high: float = sc["h"]
		var wide: float = sc["w"]
		var tops: Array[float] = []
		var crest: Array[Vector3] = []
		var crest_w: Array[float] = []
		for p: Vector3 in pts:
			tops.append(high * (0.9 + 0.35 * _noise.get_noise_3dv(p * 0.11)))
			crest.append(p + Vector3.UP * tops[-1])
			crest_w.append(wide * 0.45)
		var along := 0.0
		for i in pts.size() - 1:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			var step := a.distance_to(b)
			var side := (b - a).cross(Vector3.UP).normalized()
			var u0 := along / 5.0
			var u1 := (along + step) / 5.0
			along += step
			for way: float in [-1.0, 1.0]:
				var out := side * way
				var a0 := a + out * wide * 0.8 - Vector3.UP
				var b0 := b + out * wide * 0.8 - Vector3.UP
				var a1 := a + out * wide * 0.5 + Vector3.UP * tops[i] * 0.45
				var b1 := b + out * wide * 0.5 + Vector3.UP * tops[i + 1] * 0.45
				var a2 := a + out * wide * 0.28 + Vector3.UP * tops[i]
				var b2 := b + out * wide * 0.28 + Vector3.UP * tops[i + 1]
				roots.quad(a0, b0, b1, a1, out, Vector2(u0, 0), Vector2(u1, 0),
						Vector2(u1, -tops[i + 1] * 0.09), Vector2(u0, -tops[i] * 0.09),
						0.3)
				roots.quad(a1, b1, b2, a2, out, Vector2(u0, -tops[i] * 0.09),
						Vector2(u1, -tops[i + 1] * 0.09), Vector2(u1, -tops[i + 1]
						* 0.2), Vector2(u0, -tops[i] * 0.2), 99.0)
		roots.tube(crest, crest_w, 7, 5.0)
		for end: int in [0, pts.size() - 1]:
			var foot: Vector3 = pts[end]
			var post: Array[Vector3] = [foot - Vector3.UP, foot + Vector3.UP
					* tops[end] * 0.5, foot + Vector3.UP * tops[end] * 1.08]
			var post_w: Array[float] = [wide * 1.0, wide * 0.7, wide * 0.5]
			roots.tube(post, post_w, 8, 5.0)
	for st: Array in stumps:
		var foot: Vector3 = st[0]
		var thick: float = st[1]
		var tall: float = st[2]
		var trunk: Array[Vector3] = [foot - Vector3.UP, foot + Vector3.UP * tall
				* 0.3, foot + Vector3.UP * tall]
		var trunk_w: Array[float] = [thick * 1.3, thick * 1.0, thick * 0.92]
		roots.tube(trunk, trunk_w, 10, 5.0)
		roots.blob(foot + Vector3.UP * tall, Vector3(thick * 0.92, 0.5,
				thick * 0.92), 10, 4)


## Сітка «речей» за назвою матеріалу (одна на все дерево).
func _of(bag: Dictionary, label: String) -> _Mesh:
	if not bag.has(label):
		bag[label] = _Mesh.new()
	return bag[label]


## «Речі» поверху з його референсу: трутовики, світні гриби, вода,
## струмок, коріння-мости, бурштин, кокони, тотеми, кістки, гнізда, сніг,
## завіси лишайнику, сухі квіти. Усе — картинка, тіл не має (тіла мають
## лише колони, `_place_columns`).
func _build_things(land: Node, bag: Dictionary, k: int,
		rng: RandomNumberGenerator) -> void:
	var n := radii.size()
	var rk: float = radii[k]
	var floor_y: float = floors[k]
	var open_top := k == n - 1
	var ceil_y: float = hall_top(k)
	var glow := GLOW_WARM if shape == "секвоя" else GLOW_COLD
	for thing: String in theme(k).get("речі", []):
		match thing:
			"трутовики":
				for i in int(rk * 0.5):
					var a := rng.randf() * TAU
					for j in rng.randi_range(2, 6):
						var y := floor_y + 2.0 + float(j) * rng.randf_range(2.5, 4.0)
						if y > wall_top(k) - 1.0:
							break
						var size := rng.randf_range(1.5, 4.5)
						_of(bag, "трутовик").blob(_on(rk + 0.3, a + float(j) * 0.05,
								y), Vector3(size, size * 0.22, size), 10, 5)
			"світні гриби":
				for i in int(rk * 0.45):
					var a := rng.randf() * TAU
					var r := rk * (rng.randf_range(0.82, 0.97) if i % 3 > 0
							else rng.randf_range(0.2, 0.8))
					if not _far_from_steps(k, a, r, 8.0):
						continue
					for j in rng.randi_range(2, 6):
						var aa := a + rng.randf_range(-0.03, 0.03)
						var rr := minf(r + rng.randf_range(-3.0, 3.0), rk - 0.5)
						var at := _on(rr, aa, _floor_y(land, k, aa, rr) - 0.1)
						var high := rng.randf_range(0.8, 4.5)
						var cap := high * rng.randf_range(0.45, 0.8)
						var stem: Array[Vector3] = [at, at + Vector3.UP * high]
						var thick: Array[float] = [high * 0.09, high * 0.06]
						_of(bag, "ніжка").tube(stem, thick, 6, 2.0)
						_of(bag, "шапка").blob(at + Vector3.UP * high,
								Vector3(cap, cap * 0.4, cap), 10, 5)
				_glow_lamps(k, glow, 6, 1.6, 0.6)
			"вода":
				var a := door_angle + 2.0
				_of(bag, "вода").disc_at(Vector3(cos(a) * rk * 0.12, floor_y + 0.12,
						sin(a) * rk * 0.12), rk * 0.62, 48)
			"струмок":
				var a0 := door_angle + 1.1
				var from := _on(rk * 0.96, a0, floor_y + 0.12)
				var to := _on(rk * 0.96, a0 + PI * 0.9, floor_y + 0.12)
				var across := (to - from).cross(Vector3.UP).normalized()
				var last := from
				for j in range(1, 41):
					var t := float(j) / 40.0
					var p := from.lerp(to, t) + across * sin(t * 9.0) * rk * 0.07
					var side := (p - last).cross(Vector3.UP).normalized() \
							* (2.2 + 0.8 * sin(t * 17.0))
					_of(bag, "вода").quad(last - side, last + side, p + side,
							p - side, Vector3.UP, Vector2(0, t), Vector2(1, t),
							Vector2(1, t), Vector2(0, t), 0.0)
					last = p
			"коріння-мости":
				for i in 6:
					var a := door_angle + TAU * float(i) / 6.0 + 0.3
					var b := a + PI + rng.randf_range(-0.5, 0.5)
					var from := _on(rk + 0.5, a, floor_y + rng.randf_range(2.0, 6.0))
					var to := _on(rk + 0.5, b, floor_y + rng.randf_range(2.0, 6.0))
					var high := rng.randf_range(0.35, 0.7) * (ceil_y - floor_y)
					var side := (to - from).cross(Vector3.UP).normalized()
					var pts: Array[Vector3] = []
					var widths: Array[float] = []
					for j in 17:
						var t := float(j) / 16.0
						pts.append(from.lerp(to, t) + Vector3.UP * sin(PI * t) * high
								+ side * sin(TAU * t) * rk * 0.05)
						widths.append(1.6 + 1.2 * absf(cos(PI * t)))
					_of(bag, "коріння").tube(pts, widths, 8, 4.0)
			"бурштин":
				for i in int(rk * 0.8):
					var a := rng.randf() * TAU
					var r := rk * (0.3 + 0.65 * sqrt(rng.randf()))
					var long := rng.randf_range(3.0, 12.0)
					var top := _on(r, a, ceil_at(k, r) + 0.3)
					var pts: Array[Vector3] = [top, top - Vector3.UP * long * 0.5,
							top - Vector3.UP * long]
					var widths: Array[float] = [long * 0.12, long * 0.06, 0.03]
					_of(bag, "бурштин").tube(pts, widths, 6, 2.0)
				for i in int(rk * 0.4):
					var a := rng.randf() * TAU
					_of(bag, "бурштин").blob(_on(rk + 0.3, a, rng.randf_range(
							floor_y + 4.0, wall_top(k))), Vector3(1.2,
							rng.randf_range(2.0, 6.0), 1.2), 8, 6)
				for i in int(rk * 0.25):
					var a := rng.randf() * TAU
					var r := rk * sqrt(rng.randf()) * 0.9
					_of(bag, "бурштин").disc_at(_on(r, a, floor_y + 0.06
							+ float(i) * 0.002), rng.randf_range(2.0, 6.0), 14)
				_glow_lamps(k, Color(1.0, 0.55, 0.15), 5, 2.2, 0.55)
			"кокони":
				for i in int(rk * 0.5):
					var a := rng.randf() * TAU
					var r := rk * sqrt(rng.randf()) * 0.9
					var long := rng.randf_range(3.0, 7.0)
					var drop := rng.randf_range(2.0, 10.0)
					var top := _on(r, a, ceil_at(k, r) + 0.2)
					var line: Array[Vector3] = [top, top - Vector3.UP * drop]
					var thin: Array[float] = [0.08, 0.08]
					_of(bag, "кокон").tube(line, thin, 4, 1.0)
					_of(bag, "кокон").blob(top - Vector3.UP * (drop + long * 0.5),
							Vector3(long * 0.32, long * 0.5, long * 0.32), 8, 6)
				for i in 16:
					var a := rng.randf() * TAU
					var low := floor_y + rng.randf_range(0.0, 4.0)
					_of(bag, "павутина").quad(_on(rk, a, low), _on(rk, a + 0.22, low),
							_on(rk * 0.72, a + 0.18, ceil_at(k, rk * 0.72)),
							_on(rk * 0.8, a, ceil_at(k, rk * 0.8)),
							Vector3.UP, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1),
							Vector2(0, 1), 0.0)
			"тотеми":
				var ring := maxf(14.0, rk * 0.16)
				for i in 9:
					var a := door_angle + TAU * float(i) / 9.0
					var base := _on(ring, a, floor_y - 0.3)
					var high := rng.randf_range(10.0, 16.0)
					var top := base + Vector3.UP * high
					var pole: Array[Vector3] = [base, top]
					var thick: Array[float] = [0.55, 0.4]
					_of(bag, "кістка").tube(pole, thick, 7, 2.0)
					for j in 3:
						_of(bag, "кістка").blob(base + Vector3.UP * high
								* (0.45 + 0.25 * float(j)), Vector3(1.0, 1.1, 1.2)
								* rng.randf_range(0.9, 1.3), 8, 6)
					var out := Vector3(cos(a), 0, sin(a))
					var across := Vector3(-out.z, 0, out.x)
					for way: float in [-1.0, 1.0]:
						var horn: Array[Vector3] = [top, top + across * way * 2.0
								+ Vector3.UP * 1.5, top + across * way * 3.5
								+ Vector3.UP * 4.0]
						var taper: Array[float] = [0.25, 0.18, 0.05]
						_of(bag, "кістка").tube(horn, taper, 5, 1.0)
					var bar: Array[Vector3] = [base + Vector3.UP * high * 0.7
							- across * 2.2, base + Vector3.UP * high * 0.7
							+ across * 2.2]
					var bar_w: Array[float] = [0.2, 0.2]
					_of(bag, "кістка").tube(bar, bar_w, 5, 1.0)
			"кістки":
				for i in int(rk * 0.6):
					var a := rng.randf() * TAU
					var r := rk * sqrt(rng.randf()) * 0.92
					var at := _on(r, a, _floor_y(land, k, a, r) + 0.3)
					var big := rng.randf_range(0.8, 2.0)
					if i % 3 == 0:
						_of(bag, "кістка").blob(at + Vector3.UP * 0.3 * big,
								Vector3(0.7, 0.6, 0.9) * big, 8, 6)
					else:
						var turn := rng.randf() * TAU
						var dir := Vector3(cos(turn), 0, sin(turn)) * 1.4 * big
						var bone: Array[Vector3] = [at - dir, at + dir]
						var bone_w: Array[float] = [0.16 * big, 0.16 * big]
						_of(bag, "кістка").tube(bone, bone_w, 5, 1.0)
						for end: Vector3 in [at - dir, at + dir]:
							_of(bag, "кістка").blob(end, Vector3.ONE * 0.3 * big, 6, 4)
			"гнізда":
				for i in 9:
					var a := door_angle + TAU * float(i) / 9.0 + rng.randf_range(0, 0.4)
					var r := rk * rng.randf_range(0.3, 0.85)
					var c := _on(r, a, floor_y)
					var wide := rng.randf_range(3.5, 7.0)
					for j in 30:
						var t := TAU * float(j) / 30.0 + rng.randf_range(0, 0.2)
						var out := Vector3(cos(t), 0, sin(t))
						var p := c + out * wide * rng.randf_range(0.8, 1.1) \
								+ Vector3.UP * rng.randf_range(0.2, wide * 0.35)
						var dir := (Vector3(-out.z, 0, out.x) + Vector3.UP
								* rng.randf_range(-0.3, 0.3) + out
								* rng.randf_range(-0.4, 0.4)).normalized() \
								* rng.randf_range(1.0, 2.2)
						var stick: Array[Vector3] = [p - dir, p + dir]
						var stick_w: Array[float] = [0.14, 0.1]
						_of(bag, "гніздо").tube(stick, stick_w, 4, 1.0)
					for j in rng.randi_range(1, 3):
						_of(bag, "кістка").blob(c + Vector3(rng.randf_range(-1, 1),
								0.7, rng.randf_range(-1, 1)), Vector3(0.6, 0.8, 0.6),
								8, 6)
			"сніг":
				for i in int(rk * 0.5):
					var a := rng.randf() * TAU
					var r := rk * sqrt(rng.randf()) * 0.95
					_of(bag, "сніг").disc_at(_on(r, a, floor_y + 0.05
							+ float(i) * 0.002), rng.randf_range(3.0, 10.0), 14)
			"завіси":
				if open_top:
					continue
				for i in int(rk * 1.6):
					var a := rng.randf() * TAU
					var r := rk * sqrt(rng.randf()) * 0.97
					var top := _on(r, a, ceil_at(k, r))
					var turn := rng.randf() * TAU
					var side := Vector3(cos(turn), 0, sin(turn)) \
							* rng.randf_range(1.0, 2.5)
					var down := Vector3.UP * rng.randf_range(5.0, 14.0)
					_of(bag, "завіса").quad(top - side - down, top + side - down,
							top + side, top - side, Vector3(-sin(turn), 0, cos(turn)),
							Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1),
							0.0)
			"сухі квіти":
				for i in int(rk * 3.0):
					var a := rng.randf() * TAU
					var r := rk * sqrt(rng.randf()) * 0.96
					var at := _on(r, a, _floor_y(land, k, a, r))
					var size := rng.randf_range(0.8, 1.8)
					for turn: float in [0.0, PI * 0.5]:
						var side := Vector3(cos(a + turn), 0, sin(a + turn)) * size * 0.6
						var up := Vector3(0, size, 0)
						_of(bag, "сухе").quad(at - side, at + side, at + side + up,
								at - side + up, Vector3(cos(a), 0.3, sin(a)).normalized(),
								Vector2(0, 1), Vector2(1, 1), Vector2(1, 0),
								Vector2(0, 0), 0.0)


## Кілька малих ламп по колу поверху — світіння грибів чи бурштину.
func _glow_lamps(k: int, tone: Color, many: int, power: float,
		ring: float) -> void:
	for i in many:
		var a := door_angle + TAU * (float(i) + 0.5) / float(many)
		var lamp := OmniLight3D.new()
		lamp.light_color = tone
		lamp.light_energy = power
		lamp.omni_range = maxf(28.0, radii[k] * 0.45)
		lamp.omni_attenuation = 1.2
		lamp.shadow_enabled = false
		lamp.position = _on(radii[k] * ring, a, floors[k] + 5.0)
		add_child(lamp)


func _add_things(bag: Dictionary) -> void:
	var glow := GLOW_WARM if shape == "секвоя" else GLOW_COLD
	for label: String in bag:
		if label == "коріння":
			continue
		var mat := StandardMaterial3D.new()
		mat.roughness = 0.85
		match label:
			"трутовик":
				mat.albedo_color = Color(0.8, 0.55, 0.3)
			"ніжка":
				mat.albedo_color = Color(0.85, 0.85, 0.75)
			"шапка":
				mat.albedo_color = glow
				mat.emission_enabled = true
				mat.emission = glow
				mat.emission_energy_multiplier = 1.8
			"вода":
				mat.albedo_color = Color(0.15, 0.35, 0.4, 0.6)
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.roughness = 0.08
				mat.metallic = 0.2
			"бурштин":
				mat.albedo_color = Color(1.0, 0.55, 0.1)
				mat.emission_enabled = true
				mat.emission = Color(1.0, 0.5, 0.1)
				mat.emission_energy_multiplier = 1.2
				mat.roughness = 0.25
			"кокон":
				mat.albedo_color = Color(0.82, 0.8, 0.74)
			"павутина":
				mat.albedo_color = Color(0.9, 0.9, 0.92, 0.3)
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			"кістка":
				mat.albedo_color = Color(0.88, 0.85, 0.76)
			"гніздо":
				mat = _material("res://models/nature/Bark_DeadTree.png", "",
						Color(0.45, 0.35, 0.25))
			"сніг":
				mat.albedo_color = Color(0.95, 0.97, 1.0)
			"завіса", "сухе":
				if ResourceLoader.exists(FERN):
					mat.albedo_texture = load(FERN)
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				mat.alpha_scissor_threshold = 0.45
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				mat.albedo_color = Color(0.55, 0.65, 0.5) if label == "завіса" \
						else Color(0.55, 0.2, 0.15)
		_add_mesh(_named(label), (bag[label] as _Mesh).commit(), mat)


static func _named(label: String) -> String:
	return label.capitalize().replace(" ", "")


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
	# Яруси гілок: частки висоти стовбура нижче верхівки (0 — сама
	# верхівка). Пучок листя — частка `rim`.
	var tiers: Array[float] = [0.0]
	_puff = 0.42
	match shape:
		"пляшка":
			# Баобаб на референсах (13.11.2026): крона — широка пласка
			# парасоля, ширша за стовбур, а не жмут на маківці. Крону
			# міряли від верхнього поверху (він удвічі вужчий за низ), і
			# на стовбурі 200 м вона виходила чубчиком (14.11.2026).
			limbs = 11
			length = rim * 1.0
			thick = rim * 0.17
			rise = 0.42
			kids = 3
			_puff = 0.8
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
		"ялівець":
			# Як на фото: частина гілок — голі вибілені шпичаки, частина —
			# з темною хвоєю; хвоя лежить широкими пласкими «подушками».
			limbs = 9
			length = rim * 1.0
			thick = rim * 0.13
			rise = 0.6
			depth = 3
			kids = 3
			leafy = 1.0
			_puff = 0.7
		"секвоя":
			# Секвоя: гілки ярусами по верхній частині стовбура, ростуть
			# убік і трохи вниз; крона вузька й довга, не парасоля.
			limbs = 13
			length = rim * 0.75
			thick = rim * 0.08
			rise = 0.12
			depth = 3
			kids = 3
			leafy = 1.0
			tiers = [0.0, 0.07, 0.14]
			_puff = 0.5
	var wood := _Mesh.new()
	var leaves := _Mesh.new()
	var tall_part := top - floors[0]
	for tier in tiers.size():
		var y := top - tall_part * tiers[tier]
		var shrink := 1.0 - 0.12 * float(tier)
		var many := limbs - tier * 2
		for i in many:
			var a := TAU * (float(i) + rng.randf_range(0.0, 0.6) + 0.37 * float(tier)) \
					/ float(many)
			var r_here := rim if tier == 0 else outer_r(a, y)
			var from := _on(r_here * (0.78 if tier == 0 else 0.92), a,
					y - thick * 0.6)
			var dir := (Vector3(cos(a), rise, sin(a))).normalized()
			_branch(wood, leaves, rng, from, dir, length * shrink, thick * shrink,
					depth, kids, 0.0 if shape == "ялівець" and i % 3 == 1 else leafy,
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
		if shape == "ялівець" or shape == "секвоя":
			leaf_mat.albedo_color = Color(0.4, 0.55, 0.38)
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
			# Два пучки на кінцеву гілку — на кінці й посередині: одним
			# пучком крона світилася наскрізь.
			_leaf_puff(leaves, rng, to, rim * _puff)
			_leaf_puff(leaves, rng, from.lerp(to, 0.55) + Vector3.UP * length * 0.1,
					rim * _puff * 0.8)
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
		_leaf_puff(leaves, rng, to, rim * _puff * 1.15)


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

	## Диск на висоті `c.y` із серединою `c` (калюжа, сніг, вода).
	func disc_at(c: Vector3, r: float, sides: int) -> void:
		var mid := add(c, Vector2.ZERO, 0.0)
		var first := verts.size()
		for i in sides + 1:
			var a := TAU * float(i) / float(sides)
			add(c + Vector3(cos(a) * r, 0, sin(a) * r), Vector2(cos(a), sin(a)), 0.0)
		for i in sides:
			tri_idx(mid, first + i, first + i + 1, Vector3.UP)

	## Еліпсоїд із півосями `r` — шапка гриба, череп, кокон.
	func blob(c: Vector3, r: Vector3, sides: int, rows: int) -> void:
		var first := verts.size()
		for j in rows + 1:
			var lat := PI * (float(j) / float(rows) - 0.5)
			for i in sides + 1:
				var lon := TAU * float(i) / float(sides)
				add(c + Vector3(cos(lat) * cos(lon) * r.x, sin(lat) * r.y,
						cos(lat) * sin(lon) * r.z), Vector2(float(i) / float(sides),
						float(j) / float(rows)), 0.0)
		for j in rows:
			for i in sides:
				var v00 := first + j * (sides + 1) + i
				var v10 := v00 + 1
				var v01 := v00 + sides + 1
				var v11 := v01 + 1
				var face := (verts[v00] + verts[v11]) * 0.5 - c
				if j > 0:
					tri_idx(v00, v10, v11, face)
				if j < rows - 1:
					tri_idx(v00, v11, v01, face)

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
