extends SceneTree
## Проба до кроку 2.5: руни, грейди, рівні скілів і відновлення.
##
## Ганяти так:
##     godot --headless --path game --script res://проби/руни.gd

const AVATAR := preload("res://scenes/avatar.tscn")
const MOB := preload("res://scenes/mob.tscn")


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	await _learning()
	await _regen()
	quit()


func _hero() -> Node3D:
	var hero: Node3D = AVATAR.instantiate()
	root.add_child(hero)
	await process_frame
	hero.place_at(Vector3(0, 1.5, 0), 0.0)
	return hero


## Вивчення й підняття рівня.
func _learning() -> void:
	print("\n— руни й досвід (крок 2.5) —")
	var data := GameData.new()
	data.load_all()
	var runes := Runes.new(data.skills)
	var hero: Node3D = await _hero()
	hero.learned.clear()          # стартові скіли тут заважають
	var beam: Skill = data.skills.get_skill("енергетичний-промінь")
	print("  промінь: грейд %s, з рівня %d, вивчення = %s + %d досвіду"
			% [beam.grade, beam.from_level, beam.rune, beam.learn_cost])

	print("  без нічого:        %s" % runes.learn(hero, "енергетичний-промінь"))
	hero.level = 3
	print("  3 рівень, без руни: %s" % runes.learn(hero, "енергетичний-промінь"))
	hero.give_item(beam.rune)
	print("  з руною, без досвіду: %s"
			% runes.learn(hero, "енергетичний-промінь"))
	hero.experience = 500
	var why: String = runes.learn(hero, "енергетичний-промінь")
	print("  з руною й досвідом: %s -> рівень %d, руна витрачена: %s, досвіду лишилось %d"
			% ["вивчено" if why == "" else why,
			   hero.learned.get("енергетичний-промінь", 0),
			   not hero.has_item(beam.rune), hero.experience])

	print("  підняття рівня, руна підняття: «%s»"
			% Runes.level_rune_for(beam.grade))
	print("  без руни підняття:  %s" % runes.raise(hero, "енергетичний-промінь"))
	hero.give_item(Runes.level_rune_for(beam.grade), 5)
	for step in 4:
		var level: int = hero.learned["енергетичний-промінь"]
		var cost: int = Runes.raise_cost(beam, level)
		hero.experience = cost
		var out: String = runes.raise(hero, "енергетичний-промінь")
		print("    %d -> %d: коштувало %4d досвіду, %s"
				% [level, hero.learned["енергетичний-промінь"], cost,
				   "піднято" if out == "" else out])
	hero.queue_free()


## Відновлення: у бою, стоячи, сидячи.
func _regen() -> void:
	print("\n— відновлення (П-101) —")
	var hero: Node3D = await _hero()
	print("  здоров'я %d, мана %d; у бою %.0f%%/с, стоячи %.0f%%/с, сидячи %.0f%%/с"
			% [hero.stats.max_hp(), hero.stats.max_mp(),
			   hero.REGEN_FIGHT * 100.0, hero.REGEN_REST * 100.0,
			   hero.REGEN_SIT * 100.0])
	for mode: String in ["у бою", "стоячи", "сидячи"]:
		hero.hp = 50
		hero.mp = 20
		hero.in_fight = 10.0 if mode == "у бою" else 0.0
		hero.sit(mode == "сидячи")
		for i in 60 * 10:                     # десять секунд
			hero.server_step(1.0 / 60.0)
		print("  %-8s за 10 с: здоров'я 50 -> %3d, мана 20 -> %2d"
				% [mode, hero.hp, hero.mp])
	# Справжній удар, а не вдаваний: монстр б'є того, хто сидить.
	#
	# Спершу поставити героя на місце: за тридцять секунд відновлення він
	# провалився в порожнечу (підлоги в пробі немає), і монстр бив би
	# кудись у безодню. Це вже вшосте — «проба ламається частіше за код».
	hero.place_at(Vector3(0, 1.5, 0), 0.0)
	var mob: Node3D = MOB.instantiate()
	root.add_child(mob)
	await process_frame
	mob.setup(Vector3.ZERO, 1, false)
	mob.place_at(Vector3(1.5, 1.5, 0), 0.0)
	mob.target_id = 1
	var creatures := {1: hero, -1: mob}
	var combat := Combat.new(creatures, Messenger.new())
	hero.hp = 50
	hero.sit(true)
	hero.in_fight = 0.0
	print("  сів: сидить %s, здоров'я %d" % [hero.sitting, hero.hp])
	combat.attack(-1)
	print("  монстр ударив: сидить %s, здоров'я %d, у бою ще %.1f с"
			% [hero.sitting, hero.hp, hero.in_fight])
	hero.queue_free()
	mob.queue_free()
