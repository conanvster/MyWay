extends SceneTree
## Проба до кроку 2.2: скіл як ресурс.
##
## Ганяти так:
##     godot --headless --path game --script res://проби/скіли.gd
##
## Перевіряє: скіли читаються з файлу, рівні всередині грейду міняють
## числа, мана справді витрачається й тримає («не вистачає — неактивний»),
## вибух б'є всіх поруч, а промінь одного й на відстані.

const MOB := preload("res://scenes/mob.tscn")
const AVATAR := preload("res://scenes/avatar.tscn")


class Recorder extends Messenger:
	var sent: Array = []

	func _init(vision: Vision = null) -> void:
		super(null, vision)

	func to_one(peer: int, method: StringName, args: Array = []) -> void:
		sent.append({"peer": peer, "method": String(method), "args": args})

	func notices() -> Array:
		var out: Array = []
		for m in sent:
			if m["method"] == "client_notice":
				out.append(m["args"][0])
		return out


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	_from_file()
	await _ray()
	await _burst()
	await _mana()
	await _casting()
	quit()


## Скіли читаються з дані/скіли.json, а не з коду.
func _from_file() -> void:
	print("\n— скіли з файлу (крок 2.2) —")
	var data := GameData.new()
	data.load_all()
	for key: String in data.skills.keys():
		var s: Skill = data.skills.get_skill(key)
		print("  %-22s грейд %s, ціль %-9s з рівня %d, каст %.0f п, відкат %.0f п, рівнів %d"
				% [s.name, s.grade, s.target, s.from_level, s.cast_points,
				   s.cooldown_points, s.max_level()])
		for level in range(1, s.max_level() + 1):
			print("      рівень %d: мана %2d, дальність %4.1f, шкода %.0f%% магічної атаки"
					% [level, s.mana(level), s.range_at(level),
					   s.power_share(level) * 100.0])
	var hero := Stats.new()
	print("  магічна атака при Інтелекті 10: %.1f (фізична при Силі 10: %.1f)"
			% [hero.magical_attack(), hero.physical_attack()])
	var beam: Skill = data.skills.get_skill("енергетичний-промінь")
	print("  промінь у секундах: каст %.2f с, відкат %.2f с"
			% [hero.skill_cast(beam.cast_points),
			   hero.skill_cooldown(beam.cooldown_points)])


func _world(mobs: int, apart: float) -> Array:
	var data := GameData.new()
	data.load_all()
	var hero: Node3D = AVATAR.instantiate()
	root.add_child(hero)
	await process_frame
	# На y = 1,5, як усі істоти: інакше відстань до монстра рахується по
	# діагоналі, і моб рівно на межі дальності до неї не потрапляє.
	hero.place_at(Vector3(0, 1.5, 0), 0.0)
	var creatures := {1: hero}
	for i in mobs:
		var m: Node3D = MOB.instantiate()
		root.add_child(m)
		await process_frame
		m.setup(Vector3.ZERO, 1, false)
		m.place_at(Vector3(apart * (i + 1), 1.5, 0), 0.0)
		creatures[-(i + 1)] = m
	var vision := Vision.new(creatures)
	vision.watch(1)
	vision.update(1)
	var link := Recorder.new(vision)
	var combat := Combat.new(creatures, link)
	combat.skills = data.skills
	return [creatures, hero, combat, link, data]


## Промінь: одна ціль, здалеку.
func _ray() -> void:
	print("\n— енергетичний промінь —")
	var w: Array = await _world(2, 8.0)
	var hero: Node3D = w[1]
	var combat: Combat = w[2]
	var link: Recorder = w[3]
	var mob: Node3D = w[0][-1]

	print("  не вивчений: %s -> %s" % [combat.cast(1, "енергетичний-промінь"),
			link.notices()])
	hero.learn("енергетичний-промінь", 1)
	hero.target_id = -1
	var full: int = mob.hp
	print("  ціль за 8,0 (дальність 12,0): %s, шкода %d, мани лишилось %d"
			% [combat.cast(1, "енергетичний-промінь"), full - mob.hp, hero.mp])
	print("  одразу вдруге (відкат %.1f с): %s"
			% [hero.skill_ready_in.get("енергетичний-промінь", 0.0),
			   combat.cast(1, "енергетичний-промінь")])
	# Другий монстр стоїть за 16 — задалеко навіть для променя.
	hero.skill_ready_in.clear()
	hero.target_id = -2
	print("  ціль за 16,0: %s -> %s"
			% [combat.cast(1, "енергетичний-промінь"), link.notices()[-1]])
	# Вищий рівень б'є сильніше по тій самій цілі.
	hero.skill_ready_in.clear()
	hero.target_id = -1
	hero.learn("енергетичний-промінь", 4)
	hero.mp = 70
	var before: int = mob.hp
	var ok: bool = combat.cast(1, "енергетичний-промінь")
	print("  рівень 4 по тій самій цілі: %s, шкода %d (було 9 на першому), мани %d"
			% [ok, before - mob.hp, hero.mp])
	for id in w[0]:
		w[0][id].queue_free()


## Вибух: усі поруч.
func _burst() -> void:
	print("\n— енергетичний вибух —")
	var w: Array = await _world(3, 2.0)
	var hero: Node3D = w[1]
	var combat: Combat = w[2]
	var link: Recorder = w[3]
	hero.learn("енергетичний-вибух", 1)
	# Монстри стоять за 2,0 · 4,0 · 6,0; дальність вибуху 4,0.
	var was := {}
	for id in w[0]:
		if id < 0:
			was[id] = w[0][id].hp
	print("  застосував: %s" % combat.cast(1, "енергетичний-вибух"))
	for id in [-1, -2, -3]:
		var m: Node3D = w[0][id]
		print("    монстр за %4.1f: шкода %d" % [m.global_position.x,
				was[id] - m.hp])
	for id in w[0]:
		w[0][id].queue_free()


## Мана: витрачається й тримає.
func _mana() -> void:
	print("\n— мана (П-93: не вистачає — скіл неактивний) —")
	var w: Array = await _world(1, 3.0)
	var hero: Node3D = w[1]
	var combat: Combat = w[2]
	var link: Recorder = w[3]
	hero.learn("енергетичний-промінь", 1)
	hero.target_id = -1
	print("  мани на початку %d, промінь коштує 15" % hero.mp)
	var casts := 0
	while combat.cast(1, "енергетичний-промінь"):
		casts += 1
		hero.skill_ready_in.clear()
		w[0][-1].hp = 999            # ціль безсмертна, щоб рахувати саму ману
	print("  застосувань підряд: %d, мани лишилось %d" % [casts, hero.mp])
	print("  остання відмова: %s" % link.notices()[-1])
	for id in w[0]:
		w[0][id].queue_free()


## Крок 2.3: каст читається, і його можна збити (П-111).
func _casting() -> void:
	print("\n— читання й перервання (П-111) —")
	var w: Array = await _world(1, 3.0)
	var hero: Node3D = w[1]
	var combat: Combat = w[2]
	var link: Recorder = w[3]
	var mob: Node3D = w[0][-1]
	hero.learn("енергетичний-промінь", 1)
	hero.target_id = -1

	var full: int = mob.hp
	print("  почав читати: %s" % combat.cast(1, "енергетичний-промінь"))
	print("    читає %s, лишилось %.2f с, шкоди ще немає: %d"
			% [hero.casting_key, hero.casting_left, full - mob.hp])
	combat.tick_casts(0.8)
	print("    через 0,8 с: лишилось %.2f с, шкода %d"
			% [hero.casting_left, full - mob.hp])
	combat.tick_casts(0.8)
	print("    через 1,6 с: читає %s, шкода %d, відкат %.1f с"
			% [hero.is_casting(), full - mob.hp,
			   hero.skill_ready_in.get("енергетичний-промінь", 0.0)])

	print("  шанс збити каст при опорі 35 (концентрація 20 + маг. захист 15):")
	for hit: int in [3, 7, 12, 20, 40]:
		print("    удар %2d -> %.0f%%" % [hit,
				Stats.interrupt_chance(hit, 35.0) * 100.0])
	var tough := Stats.new()
	tough.sense = 30
	tough.stamina = 20
	print("  маг зі Чуттям 30 і Витривалістю 20: концентрація %.0f, маг. захист %.0f -> удар 7 збиває на %.0f%%"
			% [tough.concentration(), tough.magical_defence(),
			   Stats.interrupt_chance(7, tough.concentration()
					   + tough.magical_defence()) * 100.0])
	tough.concentration_bonus = 0.5
	print("  з бафом «концентрація уваги» (+50%%): концентрація %.0f -> %.0f%%"
			% [tough.concentration(), Stats.interrupt_chance(7,
					tough.concentration() + tough.magical_defence()) * 100.0])

	# Збиваємо напевно: удар 40 по слабкому магові.
	hero.skill_ready_in.clear()
	hero.mp = 70
	combat.cast(1, "енергетичний-промінь")
	var before_mp: int = hero.mp
	seed(7)
	combat._try_interrupt(hero, 1, 60)
	print("  сильний удар по тому, хто читає: читає %s, мана %d (не вернулась), відкату немає: %s"
			% [hero.is_casting(), hero.mp,
			   not hero.skill_ready_in.has("енергетичний-промінь")])
	print("  повідомлення: %s" % [link.notices()])
	for id in w[0]:
		w[0][id].queue_free()
