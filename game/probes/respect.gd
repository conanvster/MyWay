extends SceneTree
## Проба до кроку 3: повага, рівні, дроп і втрата за смерть.
##
## Ганяти так:
##     godot --headless --path game --script res://probes/повага.gd
##
## Числа сітки тимчасові (П-99, П-103) — саме тому вони й друкуються
## повністю: щоб було на що дивитись, коли гра дасть відчуття темпу.

const AVATAR := preload("res://scenes/avatar.tscn")
const MOB := preload("res://scenes/mob.tscn")


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	var data := GameData.new()
	data.load_all()
	var progress := Progress.new(data.levels)
	_grid(progress)
	_difference(progress)
	await _example(progress)
	await _kill_reward(data, progress)
	await _spend(progress)
	quit()


## Сітка: скільки поваги на рівень і як її зсуває раса зі статтю.
func _grid(progress: Progress) -> void:
	print("\n— сітка поваги (П-99, числа тимчасові) —")
	print("  рівень | людина-чол | людина-жін |  орк-чол  | ельф-жін")
	for level: int in [1, 2, 3, 5, 10, 20, 40, 69]:
		print("  %6d | %10d | %10d | %9d | %8d"
				% [level,
				   progress.need_for(level, "людина", "чоловік"),
				   progress.need_for(level, "людина", "жінка"),
				   progress.need_for(level, "орк", "чоловік"),
				   progress.need_for(level, "ельф", "жінка")])
	var total := 0
	for level in range(1, 70):
		total += progress.need_for(level)
	print("  разом до 70 рівня: %d поваги" % total)
	print("  це %d вовків по 250 — але ЛИШЕ якщо винагорода не росте з"
			% roundi(total / 250.0))
	print("  рівнем моба. Вона росте (П-103), тож справжнє число менше;")
	print("  саме це замовник і лишив на пробу грою.")


## Множник за різницю рівнів (П-104).
func _difference(progress: Progress) -> void:
	print("\n— різниця рівнів (П-104) —")
	var line := "  моб проти тебе: "
	for diff: int in [-12, -10, -7, -5, -4, -3, -1, 0, 2, 3, 6, 10, 15]:
		line += "%+d:%.2f  " % [diff, progress.reward_multiplier(10 + diff, 10)]
	print(line)


## Приклад замовника, розібраний по кроках.
func _example(progress: Progress) -> void:
	print("\n— приклад замовника: 300 поваги, потім смерть —")
	var hero: Node3D = AVATAR.instantiate()
	root.add_child(hero)
	await process_frame
	var need: int = progress.need_for(1)
	print("  1 рівень, поваги 0, до 2-го треба %d" % need)
	progress.add_respect(hero, 300)
	print("  убив моба, +300: прогрес %d / %d = %.0f%%"
			% [hero.respect, need, progress.share_of_level(hero) * 100.0])
	var lost: int = progress.death_loss(hero)
	print("  загинув, -%d (10%% з %d): прогрес %d / %d = %.0f%%"
			% [lost, need, hero.respect, need,
			   progress.share_of_level(hero) * 100.0])
	print("  рівень не впав: %d" % hero.level)

	# Скільки треба, щоб узяти рівень.
	var kills := 1
	while progress.add_respect(hero, 250) == 0:
		kills += 1
	print("  далі по 250 поваги: рівень %d узято з %d-го вбивства, очок статів %d"
			% [hero.level, kills, hero.stat_points])
	hero.queue_free()
	await _level_rules(progress)


## Слово замовника 18.10.2026: новий рівень лікує до повна, а смерть на
## нулі поваги забирає рівень.
func _level_rules(progress: Progress) -> void:
	print("
— рівень лікує; смерть на нулі забирає рівень —")
	var hero: Node3D = AVATAR.instantiate()
	root.add_child(hero)
	await process_frame
	hero.hp = 5
	hero.mp = 1
	progress.add_respect(hero, progress.need_for(1))
	print("  узяв рівень %d: здоров'я %d / %d, мана %d / %d — %s"
			% [hero.level, hero.hp, hero.stats.max_hp(), hero.mp,
			   hero.stats.max_mp(),
			   "до повна" if hero.hp == hero.stats.max_hp()
					and hero.mp == hero.stats.max_mp() else "‼ ні"])
	hero.hp = 0
	progress.add_respect(hero, progress.need_for(2))
	print("  мертвий узяв рівень %d: здоров'я %d — %s"
			% [hero.level, hero.hp,
			   "не ожив" if hero.hp == 0 else "‼ ожив"])
	hero.hp = 10

	# Зараз 3-й рівень, поваги 0, 6 очок статів (2 рівні по 3).
	print("  перед смертю: рівень %d, поваги %d, очок %d"
			% [hero.level, hero.respect, hero.stat_points])
	var lost: int = progress.death_loss(hero)
	var need2: int = progress.need_for(2)
	print("  смерть на нулі: рівень %d (чекаю 2), поваги %d (чекаю %d), "
			% [hero.level, hero.respect, need2 - lost]
			+ "очок %d (чекаю 3)" % hero.stat_points)
	lost = progress.death_loss(hero)
	print("  смерть не на нулі: рівень %d (чекаю 2), поваги %d, -%d"
			% [hero.level, hero.respect, lost])
	hero.respect = 0
	hero.stat_points = 0
	progress.death_loss(hero)
	print("  смерть на нулі без вільних очок: рівень %d, очок %d (борг -3)"
			% [hero.level, hero.stat_points])
	progress.add_respect(hero, progress.need_for(1) - hero.respect)
	print("  знову 2-й рівень: очок %d (борг погашено -> 0)"
			% hero.stat_points)
	hero.level = 1
	hero.respect = 0
	progress.death_loss(hero)
	print("  1-й рівень, поваги 0, смерть: рівень %d (не нижче 1), поваги %d"
			% [hero.level, hero.respect])
	hero.queue_free()


## Справжнє вбивство: повага, досвід і дроп із таблиці.
func _kill_reward(data: GameData, progress: Progress) -> void:
	print("\n— що падає з монстра (П-102) —")
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
	var combat := Combat.new(creatures, Messenger.new())
	combat.skills = data.skills
	combat.progress = progress
	print("  вовк: рівень %d, повага %s, досвід %s, рядків дропу %d"
			% [mob.level, mob.respect_range, mob.experience_range,
			   mob.drop_table.size()])

	# Сто вбивств поспіль: рахуємо, як часто що падає.
	var drops := {}
	var respect := 0
	for i in 100:
		mob.hp = 1
		hero.attack_ready_in = 0.0
		var was: int = hero.respect
		combat.attack(1)
		respect += hero.respect - was + (0 if hero.level == 1 else 0)
		mob.hp = mob.stats.max_hp()
		mob.corpse_left = 0.0
	for name in hero.items:
		drops[name] = hero.items[name]
	print("  зі 100 вбивств: рівень %d, поваги %d, досвіду %d"
			% [hero.level, hero.respect, hero.experience])
	for name in drops:
		print("    %-28s %d" % [name, drops[name]])
	hero.queue_free()
	mob.queue_free()


## Розподіл очок статів (П-147): і успіх, і обидві відмови.
func _spend(progress: Progress) -> void:
	print("\n— розподіл очок статів (П-147) —")
	var hero: Node3D = AVATAR.instantiate()
	root.add_child(hero)
	await process_frame

	var why: String = progress.spend_stat(hero, "витривалість")
	print("  без очок: %s" % ["ПОМИЛКА: пройшло" if why == "" else why])

	hero.stat_points = 2
	var before_hp: int = hero.stats.max_hp()
	var was_hp: int = hero.hp
	why = progress.spend_stat(hero, "витривалість")
	print("  +1 витривалість: %s, здоров'я %d → %d (було %d), очок лишилось %d"
			% ["вийшло" if why == "" else why, before_hp,
			   hero.stats.max_hp(), was_hp, hero.stat_points])
	print("  поточне здоров'я зросло разом із максимумом: %d → %d"
			% [was_hp, hero.hp])

	why = progress.spend_stat(hero, "не стат")
	print("  невідомий стат: %s" % ["ПОМИЛКА: пройшло" if why == "" else why])

	progress.spend_stat(hero, "сила")
	why = progress.spend_stat(hero, "сила")
	print("  очки скінчились: %s" % ["ПОМИЛКА: пройшло" if why == "" else why])
	hero.queue_free()
