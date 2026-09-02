extends SceneTree
## Проба до кроку 6: рельєф, море, туман, і чи потрібне підвантаження.
##
## Ганяти так:
##     godot --headless --path game --script res://проби/світ.gd

const MAIN := preload("res://scenes/main.tscn")
const AVATAR := preload("res://scenes/avatar.tscn")


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	var data := GameData.new()
	data.load_all()
	var world: Node3D = MAIN.instantiate()
	root.add_child(world)
	await process_frame
	var land: Node = world.get_node("Landscape")

	# Скільки коштує збудувати світ — це й є відповідь на П-63.
	var started := Time.get_ticks_msec()
	land.build(data.map)
	var spent := Time.get_ticks_msec() - started
	await process_frame

	print("\n— рельєф —")
	print("  побудовано за %d мс, вузлів у краєвиді %d"
			% [spent, land.get_child_count()])
	var lows := 999.0
	var highs := -999.0
	for i in 400:
		var x := randf_range(-110.0, 110.0)
		var z := randf_range(-110.0, 110.0)
		var y: float = land.height_at(x, z)
		lows = minf(lows, y)
		highs = maxf(highs, y)
	print("  висоти від %.1f до %.1f" % [lows, highs])
	print("  у місті рівно: центр %.2f, за 10 кроків %.2f, за 20 %.2f"
			% [land.height_at(0, 0), land.height_at(10, 0),
			   land.height_at(20, 0)])
	print("  за містом уже ні: за 40 %.2f, за 60 %.2f"
			% [land.height_at(40, 0), land.height_at(60, 0)])

	print("\n— чи стоїть усе на землі —")
	var floating := 0
	# Без типу в циклі: серед вузлів краєвиду є не тільки Node3D (небо —
	# WorldEnvironment), і суворий тип обриває пробу на першому ж такому.
	for child in land.get_children():
		if child is not Node3D:
			continue
		if not (str(child.name).begins_with("Дерево")
				or str(child.name).begins_with("Мешканець")):
			continue
		var ground: float = land.height_at(child.global_position.x,
				child.global_position.z)
		# Дерево стоїть половиною стовбура в землі — це нормально; ловимо
		# тих, хто висить у повітрі або провалився цілком.
		if absf(child.global_position.y - ground) > 6.0:
			floating += 1
	print("  дерев і мешканців не на своїй висоті: %d" % floating)

	print("\n— море й утоплення (П-61) —")
	var sea: Dictionary = data.map.get("море", {})
	print("  рівень моря %.1f, дихання %.0f с, шкода %.0f%% за секунду"
			% [land.sea_level(), sea.get("дихання", 0),
			   float(sea.get("шкода за секунду", 0)) * 100.0])
	var hero: Node3D = AVATAR.instantiate()
	root.add_child(hero)
	await process_frame
	hero.breath = float(sea.get("дихання", 25.0))
	var seconds := 0.0
	var gasped := 0.0
	# Кроками по 1/60 секунди — так само, як тікає сервер: саме на дрібному
	# кроці й спливла вада з округленням шкоди.
	while hero.is_alive() and seconds < 200.0:
		hero.breathe(1.0 / 60.0, true, float(sea.get("дихання", 25.0)),
				float(sea.get("шкода за секунду", 0.04)))
		seconds += 1.0 / 60.0
		if gasped == 0.0 and hero.breath <= 0.0:
			gasped = seconds
	print("  повітря скінчилось на %.1f с, здоров'я скінчилось на %.1f с"
			% [gasped, seconds])
	hero.hp = hero.stats.max_hp()
	hero.breath = 0.0
	hero.breathe(2.0, false, float(sea.get("дихання", 25.0)), 0.04)
	print("  виринув на 2 с: дихання вернулось до %.1f із %.0f"
			% [hero.breath, sea.get("дихання", 25.0)])

	print("\n— туман і зона бачення (П-65) —")
	var spare: float = float(data.map.get("туман", {}).get("запас", 1.0))
	for sense: int in [10, 20, 40]:
		var stats := Stats.new()
		stats.sense = sense
		print("  Чуття %2d: бачить на %.1f, туман суцільний на %.1f"
				% [sense, stats.vision_radius(),
				   stats.vision_radius() * spare])
	hero.queue_free()
	world.queue_free()
	quit()
