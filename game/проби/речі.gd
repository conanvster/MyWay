extends SceneTree
## Проба до кроку 4: речі, афікси, вдягання, витратне.
##
## Ганяти так:
##     godot --headless --path game --script res://проби/речі.gd

const AVATAR := preload("res://scenes/avatar.tscn")
const MOB := preload("res://scenes/mob.tscn")


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
	var data := GameData.new()
	data.load_all()
	_affixes(data)
	await _wearing(data)
	await _crystals(data)
	await _drop(data)
	await _death_loss(data)
	await _sanctuary()
	quit()


## Афікси кидаються, і те, що випало, справді додається до статів.
func _affixes(data: GameData) -> void:
	print("\n— афікси (П-83) —")
	seed(3)
	for i in 6:
		var item: Item = data.items.make("меч з кори дуба")
		var line := "  %-46s" % item.title()
		for stat in item.stats:
			line += " %s +%d" % [stat, item.stats[stat]]
		print(line)
	var d_only: Item = data.items.make("амулет учня")
	print("  афікс «мудрий» просить D грейду, а річ E: %s"
			% ["не випав" if not str(d_only.title()).contains("мудрий")
			   else "випав — а не мав"])


## Вдягання міняє чинні стати, зняття вертає назад.
func _wearing(data: GameData) -> void:
	print("\n— вдягання —")
	var hero: Node3D = AVATAR.instantiate()
	root.add_child(hero)
	await process_frame
	print("  без нічого: сила %d, витривалість %d, здоров'я %d, атака %.1f"
			% [hero.stats.strength, hero.stats.stamina, hero.stats.max_hp(),
			   hero.stats.physical_attack()])
	seed(11)
	var sword: Item = data.items.make("меч з кори дуба")
	var coat: Item = data.items.make("куртка з кори дуба")
	# Рід перевіряємо тут-таки: меч чоловічого роду, куртка жіночого.
	var at_sword: int = hero.add_thing(sword)
	var at_coat: int = hero.add_thing(coat)
	hero.equip(at_sword)
	hero.equip(at_coat)
	print("  вдягнено «%s» і «%s»" % [sword.title(), coat.title()])
	print("  стало: сила %d, витривалість %d, здоров'я %d, атака %.1f"
			% [hero.stats.strength, hero.stats.stamina, hero.stats.max_hp(),
			   hero.stats.physical_attack()])
	print("  базові не зіпсовані: сила %d, витривалість %d"
			% [hero.base_stats.strength, hero.base_stats.stamina])
	# Спорядження додає, стан множить — і саме в такому порядку.
	hero.add_state(State.new("лють", "strength", 1.5, 10.0))
	print("  плюс баф сили +50%%: сила %d (спершу додано зброю, тоді множено)"
			% hero.stats.strength)
	hero.states.remove("лють")
	hero.unequip("зброя")
	hero.refresh_stats()
	print("  зняли меч: сила %d, атака %.1f"
			% [hero.stats.strength, hero.stats.physical_attack()])
	hero.queue_free()


## Кристали душі: три різні дії (слова замовника).
func _crystals(data: GameData) -> void:
	print("\n— кристали душі (П-101) —")
	var hero: Node3D = AVATAR.instantiate()
	root.add_child(hero)
	await process_frame
	var creatures := {1: hero}
	var link := Recorder.new()
	var actions := Actions.new(creatures, null, null, link)
	actions.goods = data.items
	for name: String in ["кристал душі", "великий кристал душі",
			"благословенний кристал душі"]:
		hero.mp = 10
		hero.give_item(name)
		actions.use_item(1, name)
		print("  %-30s мана 10 -> %2d (з %d), лишилось штук: %d"
				% [name, hero.mp, hero.stats.max_mp(),
				   int(hero.items.get(name, 0))])
	hero.mp = 10
	print("  без кристала: %s -> %s" % [actions.use_item(1, "кристал душі"),
			link.notices()[-1]])
	hero.queue_free()


## Дроп: складані рахуються кількістю, поодинокі падають зі своїми афіксами.
func _drop(data: GameData) -> void:
	print("\n— що падає з монстра (крок 4) —")
	var hero: Node3D = AVATAR.instantiate()
	var mob: Node3D = MOB.instantiate()
	root.add_child(hero)
	root.add_child(mob)
	await process_frame
	hero.place_at(Vector3(0, 1.5, 0), 0.0)
	mob.setup(Vector3.ZERO, 1, false, data.for_kind(1))
	mob.place_at(Vector3(1.5, 1.5, 0), 0.0)
	hero.target_id = -1
	var creatures := {1: hero, -1: mob}
	var link := Recorder.new()
	var combat := Combat.new(creatures, link)
	combat.skills = data.skills
	combat.progress = Progress.new(data.levels)
	combat.goods = data.items
	seed(5)
	for i in 200:
		mob.hp = 1
		hero.attack_ready_in = 0.0
		# Рівень тримаємо на 1: інакше гравець переростає вовка, множник
		# за різницю рівнів падає в нуль, і дроп припиняється зовсім —
		# саме так у першому прогоні не випало жодної речі.
		hero.level = 1
		hero.respect = 0
		combat.attack(1)
		mob.hp = mob.stats.max_hp()
		mob.corpse_left = 0.0
	print("  складані: %s" % [hero.items])
	print("  поодинокі: %d штук" % hero.things.size())
	for item: Item in hero.things:
		print("    %-44s %s" % [item.title(), item.stats])
	print("  вдягнене: %s" % [hero.gear])
	hero.queue_free()
	mob.queue_free()


## Друга половина П-27: частина речей губиться за смерть.
func _death_loss(data: GameData) -> void:
	print("\n— втрата речей за смерть (П-27, числа П-112) —")
	var progress := Progress.new(data.levels)
	print("  шанси на кожну річ: %s" % [data.levels.get("втрата речей")])
	var kept := {"ресурси": 0, "лут": 0, "вдягнене": 0}
	var runs := 200
	for i in runs:
		var hero: Node3D = AVATAR.instantiate()
		root.add_child(hero)
		await process_frame
		hero.give_item("кора дуба", 4)
		hero.give_item("гроші", 100)
		var worn: int = hero.add_thing(data.items.make("куртка з кори дуба"))
		hero.equip(worn)
		hero.add_thing(data.items.make("меч з кори дуба"))
		progress.lose_items(hero, data.items)
		kept["ресурси"] += int(hero.items.get("кора дуба", 0))
		kept["вдягнене"] += 1 if hero.gear.has("тіло") else 0
		kept["лут"] += 1 if hero.things.size() > (1 if hero.gear.has("тіло") else 0) else 0
		if int(hero.items.get("гроші", 0)) != 100:
			print("  ‼ гроші не мали губитись, а зникли")
		hero.queue_free()
	print("  із %d смертей лишилось:" % runs)
	print("    ресурсів  %d з %d (%.0f%% вижило, чекали 75%%)"
			% [kept["ресурси"], runs * 4, 100.0 * kept["ресурси"] / (runs * 4)])
	print("    луту      %d з %d (%.0f%% вижило, чекали 90%%)"
			% [kept["лут"], runs, 100.0 * kept["лут"] / runs])
	print("    вдягненого %d з %d (%.0f%% вижило, чекали 98%%)"
			% [kept["вдягнене"], runs, 100.0 * kept["вдягнене"] / runs])
	print("  гроші не губляться жодного разу")


## Святиня (П-113): місце, де відновлюють швидко.
func _sanctuary() -> void:
	print("\n— святиня (П-113) —")
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var places := main.find_children("*", "Sanctuary", true, false)
	print("  святинь у сцені: %d" % places.size())
	if places.is_empty():
		main.queue_free()
		return
	var place: Node3D = places[0]
	print("  відновлює %.0f%% максимуму за секунду, у бою: %s"
			% [place.restore * 100.0, place.in_fight])
	print("  центр %s: усередині %s" % [place.global_position,
			place.has_point(place.global_position)])
	print("  за 20 кроків убік: усередині %s"
			% place.has_point(place.global_position + Vector3(20, 0, 0)))

	var hero: Node3D = AVATAR.instantiate()
	root.add_child(hero)
	await process_frame
	hero.hp = 20
	hero.mp = 5
	hero.in_sanctuary = place.restore
	for i in 60 * 3:
		hero.global_position = Vector3(0, 1.5, 0)
		hero.server_step(1.0 / 60.0)
	print("  три секунди в святині: здоров'я 20 -> %d, мана 5 -> %d"
			% [hero.hp, hero.mp])
	hero.queue_free()
	main.queue_free()
