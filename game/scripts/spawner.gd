class_name Spawner
extends RefCounted
## Заселення мапи: скільки монстрів, де і як швидко вертаються (П-66).
##
## Де саме — питає в зон (`mob_zone.gd`), тобто в того, що намальовано в
## редакторі. Числа вдачі — у `data/mobs.json`. У самому спавнері не
## лишилось жодного числа про світ: він тільки веде облік гнізд.
##
## Гніздо — це одне місце в зоні: живий монстр або відлік до наступного.
## Зона з `count = 3` дає три гнізда.

var _creatures: Dictionary
## Хто вміє створювати істот у сцені: `spawn(id, pos) -> Node3D`.
var _world: Object
var _data: GameData
var _slots: Array = []
var _last_mob_id := 0

## Сплячі зони (12.09.2026). Світ версії 2 заселено по всій суші — 360
## зон, понад тисячу гнізд, — бо замовник «зовсім не зустрічав
## монстрів»: вони стояли лише до 900 м від столиці. Тримати тисячу
## живих монстрів серверові не під силу: заміряно 2992 МіБ пам'яті й
## 20 мс на кадр (бюджет 16,7). Тож зона порожня, доки поруч немає
## гравця, — як у MMO: гравець підходить ближче за `WAKE_RANGE`, і всі
## гнізда зони заповнюються одразу (бачить він на 18-36 м, появи не
## помітить); усі пішли далі за `SLEEP_RANGE` на `SLEEP_AFTER` секунд і
## ніхто в зоні не б'ється — монстрів прибрано.
## Вмикає світ лише для зон із даних (світ 2); світ версії 1 як був.
var dormant := false
const WAKE_RANGE := 150.0
const SLEEP_RANGE := 220.0
const SLEEP_AFTER := 20.0
const LOOK_EVERY := 0.5
var _zones: Array = []
var _slots_of := {}          # зона -> [номери гнізд]
var _awake := {}             # зона -> true, поки прокинута
var _quiet := {}             # зона -> скільки секунд нікого поруч
var _look_in := 0.0


func _init(creatures: Dictionary = {}, world: Object = null,
		data: GameData = null) -> void:
	_creatures = creatures
	_world = world
	_data = data if data != null else GameData.new()


## Перше заселення: у кожному гнізді одразу стоїть монстр.
func start(zones: Array) -> void:
	_zones = zones
	for zone in zones:
		for i in maxi(1, zone.count):
			_slots.append({"zone": zone, "id": 0, "in": 0.0})
			_slots_of.get_or_add(zone, []).append(_slots.size() - 1)
			if not dormant:
				respawn(_slots.size() - 1)
	if dormant:
		print("[світ] зон появи %d, гнізд %d — зона спить, доки поруч "
				% [zones.size(), _slots.size()] + "немає гравця")
	else:
		print("[світ] зон появи %d, монстрів %d" % [zones.size(), _slots.size()])


## Зони, що з'являються вже під час гри — підземелля за порталом (П-190).
## Те саме, що `start`, тільки до наявних гнізд, а не замість них.
func add_zones(zones: Array) -> void:
	for zone in zones:
		_zones.append(zone)
		for i in maxi(1, zone.count):
			_slots.append({"zone": zone, "id": 0, "in": 0.0})
			_slots_of.get_or_add(zone, []).append(_slots.size() - 1)
			if not dormant:
				respawn(_slots.size() - 1)


## Прибрати зони разом із їхніми монстрами — підземелля закрилось (Ф7).
## Гнізда інших зон переіндексовуються: `_slots_of` тримає номери.
func drop_zones(zones: Array) -> void:
	var kept: Array = []
	for slot: Dictionary in _slots:
		if not zones.has(slot["zone"]):
			kept.append(slot)
			continue
		var id: int = slot["id"]
		if id != 0 and _creatures.has(id):
			_world.remove(id)
	_slots = kept
	for zone: Variant in zones:
		_zones.erase(zone)
		_awake.erase(zone)
		_quiet.erase(zone)
	_slots_of.clear()
	for i in _slots.size():
		_slots_of.get_or_add(_slots[i]["zone"], []).append(i)


## Номери гнізд, які взагалі варто чіпати цього кадру: у сплячому світі
## — лише прокинутих зон, інакше всі.
func _awake_slots() -> Array:
	if not dormant:
		return range(_slots.size())
	var out: Array = []
	for zone: Variant in _awake:
		if _awake[zone]:
			out += _slots_of.get(zone, [])
	return out


func tick(delta: float) -> void:
	if dormant:
		_look_in -= delta
		if _look_in <= 0.0:
			_look_in = LOOK_EVERY
			_wake_or_sleep()
	# Сплячі зони не перебираємо взагалі. Доти цикл щокадру проходив
	# ВСІ гнізда світу (12 974 після скупчень) лише щоб на кожному
	# спитати, чи не спить його зона, — і це при десятку прокинутих.
	for i in _awake_slots():
		var slot: Dictionary = _slots[i]
		if slot["id"] != 0 and _creatures.has(slot["id"]):
			continue
		var zone: MobZone = slot["zone"]
		if slot["in"] <= 0.0:
			slot["in"] = zone.respawn_after + randf() * zone.respawn_spread
			slot["id"] = 0
			continue
		slot["in"] -= delta
		if slot["in"] <= 0.0:
			# За індексом, а не пошуком словника у масиві: `find` шукав
			# за посиланням і зламався б від першої ж копії.
			respawn(i)


## Підсилення поверху дерева-велета на самому монстрі: [рівень, множник].
## Потрібне, щоб перечитані числа виду (`apply_tuning`) не скинули його.
const LIFT := &"giant_boost"


## Монстр з'являється у випадковій точці своєї зони (П-66).
## Новий номер монстра поза зонами — для вартових поселень (П-262):
## номери мусять не перетинатися з тими, що роздає сама поява.
func next_id() -> int:
	_last_mob_id += 1
	return -_last_mob_id


func respawn(slot: int) -> int:
	var zone: MobZone = _slots[slot]["zone"]
	if zone.spent:
		return 0
	_last_mob_id += 1
	var id := -_last_mob_id
	var at := _free_point(zone)
	# Поставити НАД землею, не рівно на ній: зона намальована в редакторі
	# площиною, а земля під нею горбкувата (крок 6), і меш ліпить трикутники
	# лінійно між вершинами кожні 4 м, тоді як `ground_at` рахує шум у самій
	# точці — на схилі між вершинами вони не завжди збігаються день у день.
	# 6 м запасу (П-141, зменшено з 10 того ж вечора) гарантовано вище
	# будь-якого розходження; монстр падає вниз сам (гравітація вже є в
	# `server_step`) і сідає точно на видиму поверхню, а не в ґрунт чи над
	# ним.
	if zone.on_floor:
		# Поверх дерева-велета: рельєф під ним — на десятки метрів нижче.
		at.y = zone.floor_y + 1.0
	elif _world != null and _world.has_method("ground_at"):
		at.y = _world.ground_at(at.x, at.z) + 6.0
	var tuning := _data.for_kind(zone.kind)
	var lifted := zone.level_set > 0 or zone.boost != 1.0
	if lifted:
		tuning = GiantTree.boosted(tuning, zone.level_set, zone.boost)
	var m: Node = _world.spawn(id, at)
	m.setup(at, zone.kind, zone.aggressive, tuning)
	if lifted:
		m.set_meta(LIFT, [zone.level_set, zone.boost])
	m.is_boss = zone.boss
	# Штраф світу за незачищені підземелля (Ф7) — і на тих, хто
	# з'являється вже після нього.
	if _world.has_method("penalize"):
		_world.penalize(m)
	_slots[slot]["id"] = id
	_slots[slot]["in"] = 0.0
	return id


## Скільки метрів між монстрами при появі. Монстри тепер не проходять
## одне крізь одного (шар «монстри»), і поява за 6 м угорі над іншим
## монстром поклала б нового йому на голову. Двоє найбільших (ведмідь,
## капсула 0,8 м) поруч — 1,6.
const SPAWN_GAP := 1.6
const SPAWN_TRIES := 8


## Точка зони, де поруч немає живого монстра. Зона тісна (кільце в
## ході підземелля — 0,6 м) — береться найвільніша з кількох спроб.
func _free_point(zone: MobZone) -> Vector3:
	var best := zone.random_point()
	var best_gap := _gap(best)
	for i in SPAWN_TRIES - 1:
		if best_gap >= SPAWN_GAP:
			break
		var at := zone.random_point()
		var gap := _gap(at)
		if gap > best_gap:
			best = at
			best_gap = gap
	return best


## Відстань по горизонталі до найближчого живого монстра.
func _gap(at: Vector3) -> float:
	var near := INF
	for id in _creatures:
		if id >= 0:
			continue
		var m: Node3D = _creatures[id]
		if not m.is_alive():
			continue
		near = minf(near, Vector2(m.global_position.x - at.x,
				m.global_position.z - at.z).length())
	return near


## Розбудити зони, до яких підійшли, і приспати ті, від яких усі пішли.
func _wake_or_sleep() -> void:
	var players: Array[Vector3] = []
	for id in _creatures:
		if id > 0 and _creatures[id].is_alive():
			players.append(_creatures[id].global_position)
	for zone: MobZone in _zones:
		var at := zone.global_position
		var near := INF
		var stacked := not is_nan(zone.floor_y)
		for p: Vector3 in players:
			# Поверх дерева: будить лише той, хто на цьому поверсі.
			if stacked and (p.y < zone.floor_y - 2.0 or p.y > zone.ceil_y):
				continue
			near = minf(near, Vector2(p.x - at.x, p.z - at.z).length())
		if near < WAKE_RANGE:
			_quiet[zone] = 0.0
			if not _awake.get(zone, false):
				_awake[zone] = true
				for i: int in _slots_of.get(zone, []):
					var id: int = _slots[i]["id"]
					if id == 0 or not _creatures.has(id):
						respawn(i)
		elif _awake.get(zone, false) and near > SLEEP_RANGE:
			_quiet[zone] = float(_quiet.get(zone, 0.0)) + LOOK_EVERY
			if _quiet[zone] >= SLEEP_AFTER:
				_put_to_sleep(zone)


## Прибрати монстрів зони. Якщо хтось із них б'ється чи лежить трупом —
## зону не чіпаємо: засне пізніше, коли все вляжеться.
func _put_to_sleep(zone: MobZone) -> void:
	for i: int in _slots_of.get(zone, []):
		var id: int = _slots[i]["id"]
		if id != 0 and _creatures.has(id):
			var m: Node = _creatures[id]
			if not m.is_alive() or m.target_id != 0:
				return
	for i: int in _slots_of.get(zone, []):
		var id: int = _slots[i]["id"]
		if id != 0 and _creatures.has(id):
			_world.remove(id)
		_slots[i]["id"] = 0
		_slots[i]["in"] = 0.0
	_awake[zone] = false
	_quiet[zone] = 0.0


## Скільки живих монстрів лишилось у цій зоні. Потрібне святиням
## (П-153): «зачищено» — це саме нуль живих в її кільці охорони.
## Скільки живих у зоні. Ходимо ЛИШЕ по гніздах цієї зони (`_slots_of`),
## а не по всіх: `world.gd:_tick_shrines` питає це раз на секунду для
## кожної зони кожної святині, а після скупчень (20.09.2026) гнізд стало
## 12 974 і зон охорони 424 — виходило 5,2 мільйона кроків в ОДНОМУ
## кадрі раз на секунду. Саме це замовник і бачив: «якщо вибрати йти по
## прямій, аватар завмирає щосекунди на 1/3 секунди».
func alive_in(zone: Node) -> int:
	var alive := 0
	for at: int in _slots_of.get(zone, []):
		var slot: Dictionary = _slots[at]
		if slot["id"] != 0 and _creatures.has(slot["id"]):
			alive += 1
	return alive


## Роздати живим монстрам перечитані числа (крок 1.2: баланс на ходу).
func apply_tuning() -> int:
	var touched := 0
	for id in _creatures:
		if id >= 0:
			continue
		var m: Node = _creatures[id]
		var tuning := _data.for_kind(m.kind)
		if m.has_meta(LIFT):
			var lift: Array = m.get_meta(LIFT)
			tuning = GiantTree.boosted(tuning, int(lift[0]), float(lift[1]))
		m.apply_tuning(tuning)
		touched += 1
	return touched
