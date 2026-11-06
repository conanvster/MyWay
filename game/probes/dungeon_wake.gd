extends Node
## Чи прокидаються зони підземелля, коли в ньому гравець (світ 2 — зони
## сплять, доки поруч немає гравця). Журнал сервера 19.09.2026: гравець
## у відновленому з бази підземеллі, «монстрів живих 0».
##
##     godot --headless --path game res://scenes/dungeon_wake.tscn -- --світ2

const MAIN := preload("res://scenes/main.tscn")


func _ready() -> void:
	_go()


func _go() -> void:
	await get_tree().process_frame
	Net.joined = true
	var world: Node3D = MAIN.instantiate()
	get_tree().root.add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame
	world.spawner.dormant = true
	var land: Node = world.get_node("Landscape")
	world._restore_dungeon(7, {"template": "кузня-глибин", "seed": 701751586,
			"grade": land.shrines()[7].grade, "depth": 1, "cleared": 0,
			"levels": []})
	var key := Dungeons.key(7, 0)
	var me: Node = world.spawn(1, world.dungeons.entry_point(key))
	await get_tree().process_frame
	var zones: Array = world.dungeons.open[key]["zones"]
	print("зон у підземеллі: %d" % zones.size())
	for step in 10:
		world.spawner.tick(0.6)
		await get_tree().physics_frame
	var alive := 0
	for id: int in world.creatures:
		var c: Node3D = world.creatures[id]
		if id < 0 and world.dungeons.index_at(c.global_position.x,
				c.global_position.z) == key:
			alive += 1
	var nearest := INF
	for zone: Node3D in zones:
		nearest = minf(nearest, Vector2(zone.global_position.x
				- me.global_position.x, zone.global_position.z
				- me.global_position.z).length())
	print("гравець у %s; найближча зона за %.1f м; монстрів у підземеллі %d"
			% [me.global_position, nearest, alive])
	get_tree().quit()
