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


func _init(creatures: Dictionary = {}, world: Object = null,
		data: GameData = null) -> void:
	_creatures = creatures
	_world = world
	_data = data if data != null else GameData.new()


## Перше заселення: у кожному гнізді одразу стоїть монстр.
func start(zones: Array) -> void:
	for zone in zones:
		for i in maxi(1, zone.count):
			_slots.append({"zone": zone, "id": 0, "in": 0.0})
			respawn(_slots.size() - 1)
	print("[світ] зон появи %d, монстрів %d" % [zones.size(), _slots.size()])


func tick(delta: float) -> void:
	for i in _slots.size():
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


## Монстр з'являється у випадковій точці своєї зони (П-66).
func respawn(slot: int) -> int:
	var zone: MobZone = _slots[slot]["zone"]
	_last_mob_id += 1
	var id := -_last_mob_id
	var at := zone.random_point()
	# Поставити НАД землею, не рівно на ній: зона намальована в редакторі
	# площиною, а земля під нею горбкувата (крок 6), і меш ліпить трикутники
	# лінійно між вершинами кожні 4 м, тоді як `ground_at` рахує шум у самій
	# точці — на схилі між вершинами вони не завжди збігаються день у день.
	# 6 м запасу (П-141, зменшено з 10 того ж вечора) гарантовано вище
	# будь-якого розходження; монстр падає вниз сам (гравітація вже є в
	# `server_step`) і сідає точно на видиму поверхню, а не в ґрунт чи над
	# ним.
	if _world != null and _world.has_method("ground_at"):
		at.y = _world.ground_at(at.x, at.z) + 6.0
	var m: Node = _world.spawn(id, at)
	m.setup(at, zone.kind, zone.aggressive, _data.for_kind(zone.kind))
	_slots[slot]["id"] = id
	_slots[slot]["in"] = 0.0
	return id


## Роздати живим монстрам перечитані числа (крок 1.2: баланс на ходу).
func apply_tuning() -> int:
	var touched := 0
	for id in _creatures:
		if id >= 0:
			continue
		var m: Node = _creatures[id]
		m.apply_tuning(_data.for_kind(m.kind))
		touched += 1
	return touched
