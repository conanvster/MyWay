extends SceneTree
## Проба до кроку 1.1: world.gd розібрано на модулі.
##
## Ганяти так:
##     godot --headless --path game --script res://probes/крок1.gd
##
## Головне, що тут доводиться: бій, черга, зона бачення й поклик на
## поміч тепер працюють БЕЗ мережі й без вузла світу. Досі удар не
## викликати було окремо (DECISIONS.md, «Зроблено одразу після ревізії»),
## і надбавку за удар зі спини доводилось перевіряти по частинах.
##
## Числа друкуються, а не ховаються за «пройдено».

const MOB := preload("res://scenes/mob.tscn")
const AVATAR := preload("res://scenes/avatar.tscn")


## Гонець, який нічого не шле, а записує. Саме заради нього розсилку
## винесено з `world.gd` в окремий клас.
class Recorder extends Messenger:
	var sent: Array = []

	func _init(vision: Vision = null) -> void:
		super(null, vision)

	func to_one(peer: int, method: StringName, args: Array = []) -> void:
		sent.append({"peer": peer, "method": String(method), "args": args})

	func last() -> String:
		if sent.is_empty():
			return "(нічого)"
		var m: Dictionary = sent[-1]
		return "%s -> %d %s" % [m["method"], m["peer"], m["args"]]

	func to(peer: int) -> Array:
		var only: Array = []
		for m in sent:
			if m["peer"] == peer:
				only.append(m["method"])
		return only


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	await _combat_without_network()
	await _queue()
	await _vision_hysteresis()
	await _help_call()
	await _only_watchers()
	quit()


## Двоє в світі: гравець 1 і монстр -1. Повертає [creatures, гравець, монстр].
func _pair() -> Array:
	var hero: Node3D = AVATAR.instantiate()
	var mob: Node3D = MOB.instantiate()
	root.add_child(hero)
	root.add_child(mob)
	await process_frame
	mob.setup(Vector3.ZERO, 1, false)
	mob.place_at(Vector3(0, 1.5, 0), 0.0)   # дивиться на -Z
	hero.place_at(Vector3(0, 1.5, -2), 0.0)
	hero.target_id = -1
	return [{1: hero, -1: mob}, hero, mob]


## Удар викликається сам по собі — ось те, чого не можна було зробити.
func _combat_without_network() -> void:
	print("\n— удар без мережі (крок 1.1) —")
	var made: Array = await _pair()
	var creatures: Dictionary = made[0]
	var hero: Node3D = made[1]
	var mob: Node3D = made[2]

	var vision := Vision.new(creatures)
	vision.watch(1)
	vision.update(1)
	var link := Recorder.new(vision)
	var combat := Combat.new(creatures, link)

	var full: int = mob.hp
	print("  здоров'я монстра %d, атака гравця %.1f, захист монстра %.1f"
			% [full, hero.stats.physical_attack(), mob.stats.physical_defence()])

	# Спереду.
	hero.place_at(Vector3(0, 1.5, -2), 0.0)
	mob.place_at(Vector3(0, 1.5, 0), 0.0)
	hero.attack_ready_in = 0.0
	var ok_front: bool = combat.attack(1)
	var front: int = full - mob.hp
	print("  спереду: удар %s, шкода %d, %s" % [ok_front, front, link.last()])

	# Ззаду: жертва дивиться так само, нападник заходить із +Z.
	mob.hp = full
	hero.place_at(Vector3(0, 1.5, 2), 0.0)
	mob.place_at(Vector3(0, 1.5, 0), 0.0)
	hero.attack_ready_in = 0.0
	combat.attack(1)
	var back: int = full - mob.hp
	print("  ззаду:   шкода %d, різниця %+d (надбавка %.0f%% при Чутті %d)"
			% [back, back - front,
			   Stats.back_bonus_against(mob.stats) * 100.0, mob.stats.sense])

	# Задалеко й немає цілі — повідомлення, а не удар.
	hero.place_at(Vector3(0, 1.5, 20), 0.0)
	hero.attack_ready_in = 0.0
	print("  задалеко: удар %s, %s" % [combat.attack(1), link.last()])
	hero.target_id = 0
	hero.attack_ready_in = 0.0
	print("  без цілі: удар %s, %s" % [combat.attack(1), link.last()])

	hero.queue_free()
	mob.queue_free()


## П-38 і П-62: перша готова дія виконується, застаріле перед нею гине.
func _queue() -> void:
	print("\n— черга дій (П-38, П-62) —")
	var made: Array = await _pair()
	var creatures: Dictionary = made[0]
	var hero: Node3D = made[1]
	var mob: Node3D = made[2]

	var vision := Vision.new(creatures)
	vision.watch(1)
	vision.update(1)
	var link := Recorder.new(vision)
	var actions := Actions.new(creatures, vision, Combat.new(creatures, link), link)

	hero.queue.assign(["attack", "attack"])
	actions.pump(1)
	print("  два удари підряд: у черзі лишилось %d, відкат %.2f с, замах %.2f с"
			% [hero.queue.size(), hero.attack_ready_in, hero.busy_in])

	# «удар · удар · агресія» на відкаті: обидва удари гинуть, агресія йде.
	hero.busy_in = 0.0
	hero.queue.assign(["attack", "attack", "taunt"])
	var was: float = mob.threat.get(1, 0.0)
	actions.pump(1)
	print("  удар·удар·агресія на відкаті: у черзі %d, загроза %.0f -> %.0f"
			% [hero.queue.size(), was, mob.threat.get(1, 0.0)])

	# Переповнення: понад QUEUE_MAX натискання просто гине.
	hero.queue.clear()
	for i in 8:
		actions.enqueue(1, "attack")
	print("  вісім натискань при QUEUE_MAX %d: у черзі %d"
			% [hero.QUEUE_MAX, hero.queue.size()])

	hero.queue_free()
	mob.queue_free()


## Гістерезис 12%: з'являється ближче, ніж зникає (П-43).
func _vision_hysteresis() -> void:
	print("\n— зона бачення й гістерезис (П-43) —")
	var made: Array = await _pair()
	var creatures: Dictionary = made[0]
	var hero: Node3D = made[1]
	var mob: Node3D = made[2]

	var vision := Vision.new(creatures)
	vision.watch(1)
	hero.place_at(Vector3(0, 1.5, 0), 0.0)
	var near: float = hero.vision_radius()
	print("  межа появи %.1f, межа зникнення %.2f (×%.2f)"
			% [near, near * hero.VISION_HYSTERESIS, hero.VISION_HYSTERESIS])
	for d: float in [17.9, 18.1, 20.1, 20.3, 17.9]:
		mob.place_at(Vector3(d, 1.5, 0), 0.0)
		var diff: Dictionary = vision.update(1)
		print("  відстань %5.1f  бачить: %-5s  поява %s  зникнення %s"
				% [d, vision.sees(1, -1), diff["appeared"], diff["gone"]])
	hero.queue_free()
	mob.queue_free()


## Поклик на поміч через модуль: свої поблизу, і тільки вони (вада 1).
func _help_call() -> void:
	print("\n— поклик на поміч через mob_ai (вада 1) —")
	var caller: Node3D = MOB.instantiate()
	var near: Node3D = MOB.instantiate()
	var far: Node3D = MOB.instantiate()
	var other: Node3D = MOB.instantiate()
	for m in [caller, near, far, other]:
		root.add_child(m)
	await process_frame
	caller.setup(Vector3.ZERO, 1, true)
	near.setup(Vector3.ZERO, 1, true)
	far.setup(Vector3.ZERO, 1, true)
	other.setup(Vector3.ZERO, 2, true)
	caller.place_at(Vector3(0, 1.5, 0), 0.0)
	near.place_at(Vector3(5, 1.5, 0), 0.0)
	far.place_at(Vector3(30, 1.5, 0), 0.0)
	other.place_at(Vector3(1, 1.5, 0), 0.0)

	var creatures := {1: null, -1: caller, -2: near, -3: far, -4: other}
	creatures.erase(1)
	var mobs := MobAI.new(creatures, Combat.new(creatures))
	var called: int = mobs.call_for_help(-1, 1)
	print("  поклик %.0f: збіглося %d" % [caller.help_range, called])
	print("  свій за 5,0: загроза %.0f | свій за 30,0: %.0f | чужий вид за 1,0: %.0f"
			% [near.threat.get(1, 0.0), far.threat.get(1, 0.0),
			   other.threat.get(1, 0.0)])
	for m in [caller, near, far, other]:
		m.queue_free()


## П-43 у бою: про шкоду дізнається лише той, хто бачить постраждалого.
func _only_watchers() -> void:
	print("\n— адресність розсилки (П-43) —")
	var made: Array = await _pair()
	var creatures: Dictionary = made[0]
	var hero: Node3D = made[1]
	var mob: Node3D = made[2]
	# Другий глядач стоїть далеко й монстра не бачить.
	var watcher: Node3D = AVATAR.instantiate()
	root.add_child(watcher)
	await process_frame
	watcher.place_at(Vector3(100, 1.5, 100), 0.0)
	creatures[2] = watcher

	var vision := Vision.new(creatures)
	vision.watch(1)
	vision.watch(2)
	vision.update(1)
	vision.update(2)
	var link := Recorder.new(vision)
	var combat := Combat.new(creatures, link)
	hero.place_at(Vector3(0, 1.5, -2), 0.0)
	hero.target_id = -1
	hero.attack_ready_in = 0.0
	combat.attack(1)
	print("  1 бачить монстра: %s, 2 бачить: %s"
			% [vision.sees(1, -1), vision.sees(2, -1)])
	print("  надіслано гравцеві 1: %s" % [link.to(1)])
	print("  надіслано гравцеві 2: %s (має бути порожньо)" % [link.to(2)])
	hero.queue_free()
	mob.queue_free()
	watcher.queue_free()
