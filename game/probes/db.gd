extends SceneTree
## Проба збереження речей у справжній базі (крок 4 + крок 3).
##
## Ганяти так, коли підняті Postgres і PostgREST:
##     godot --headless --path game --script res://probes/база.gd
##
## Перевіряє те, чого не показав живий прогін: що поодинока річ із
## афіксами доїжджає до бази й вертається звідти цілою.

const AVATAR := preload("res://scenes/avatar.tscn")
const WHO := "Проба-речі"


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	var data := GameData.new()
	data.load_all()

	var store := Store.new()
	root.add_child(store)
	store.setup("http://127.0.0.1:3000")
	if not store.works():
		print("‼ адреси бази немає")
		quit()
		return

	# Персонаж із річчю, яка точно має афікси.
	var hero: Node3D = AVATAR.instantiate()
	root.add_child(hero)
	await process_frame
	hero.level = 4
	hero.respect = 777
	hero.experience = 321
	hero.give_item("кора дуба", 3)
	var made: Item = null
	while made == null or made.affixes.is_empty():
		made = data.items.make("куртка з кори дуба")
	hero.equip(hero.add_thing(made))
	print("\n— що зберігаємо —")
	print("  %s, стати речі %s" % [made.title(), made.stats])
	print("  рівень %d, повага %d, досвід %d, вдягнене %s"
			% [hero.level, hero.respect, hero.experience, hero.gear])
	print("  чинна витривалість %d при базовій %d"
			% [hero.stats.stamina, hero.base_stats.stamina])

	store.save_character(WHO, Store.row_of(WHO, hero))
	# Сигнал `saved` несе два доводи; `await` віддає масив лише тоді,
	# коли їх більше одного — тут саме такий випадок.
	var answer_save: Array = await store.saved
	print("  записано: %s" % answer_save[1])

	# Другий персонаж — порожній; накладаємо на нього прочитане.
	var again: Node3D = AVATAR.instantiate()
	root.add_child(again)
	await process_frame
	store.load_character(WHO)
	var answer: Array = await store.loaded
	Store.apply_row(again, answer[1], data.items)
	again.refresh_stats()

	print("\n— що повернулось —")
	print("  рівень %d, повага %d, досвід %d, речей %d, вдягнене %s"
			% [again.level, again.respect, again.experience,
			   again.things.size(), again.gear])
	if again.things.is_empty():
		print("  ‼ річ не повернулась")
	else:
		var back: Item = again.things[0]
		print("  %s, стати речі %s" % [back.title(), back.stats])
		print("  збіглося: назва %s, стати %s"
				% [back.title() == made.title(), back.stats == made.stats])
	print("  чинна витривалість %d — спорядження діє після читання: %s"
			% [again.stats.stamina,
			   again.stats.stamina > again.base_stats.stamina])
	quit()
