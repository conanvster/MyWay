extends SceneTree
## Чи застрягає гравець у точці підземелля (скарга замовника 19.09.2026,
## знімок 19-57-38: x 4170,7 y 40,7 z −8931,2 у «Кузні глибин»).
## Відтворює підземелля з тим самим шаблоном і зерном, ставить гравця
## в точку й пробує рушити в 8 боків — по 2,5 с на бік: запобіжник
## `Creature._unwedge` рятує після 1 с заклинювання.
##
##     godot --headless --path game --script res://probes/stuck.gd -- \
##         <шаблон> <зерно> <святиня> <x> <y> <z>

const AVATAR := preload("res://scenes/avatar.tscn")


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var template := a[0]
	var with_seed := int(a[1])
	var shrine := int(a[2])
	var at := Vector3(float(a[3]), float(a[4]), float(a[5]))
	var dungeons := Dungeons.new()
	root.add_child(dungeons)
	await process_frame
	var key := Dungeons.key(shrine, 0)
	dungeons.raise(key, template, with_seed, "E")
	await physics_frame
	var plan: DungeonPlan = dungeons.open[key]["plan"]
	var spot := Dungeons.spot_for(key)
	var cx := floori((at.x - spot.x) / DungeonPlan.CELL + plan.size * 0.5)
	var cz := floori((at.z - spot.z) / DungeonPlan.CELL + plan.size * 0.5)
	print("клітинка (%d, %d): прохідна %s, підлога %.2f, гравець на %.2f"
			% [cx, cz, plan.is_open(cx, cz), dungeons.floor_at(at.x, at.z),
			   at.y])
	var view: DungeonView = dungeons.open[key]["view"]
	print("поле прохідності в точці: %.2f (0 — камінь, 1 — хід)"
			% view.value_at(at - spot))
	var near := ""
	for dz in range(-2, 3):
		var row := ""
		for dx in range(-2, 3):
			row += "█" if not plan.is_open(cx + dx, cz + dz) else "·"
		near += row + "\n"
	print("довкола (5×5, центр — гравець):\n" + near)
	var hero: Node3D = AVATAR.instantiate()
	root.add_child(hero)
	await process_frame
	for turn in 8:
		var dir := Vector2.from_angle(TAU * turn / 8.0)
		hero.place_at(at, 0.0)
		for i in 5:
			await physics_frame
			hero.server_step(1.0 / 60.0)
		var from: Vector3 = hero.global_position
		for i in 150:
			hero.wanted = dir
			await physics_frame
			hero.server_step(1.0 / 60.0)
		var moved: float = Vector2(hero.global_position.x - from.x,
				hero.global_position.z - from.z).length()
		print("  бік %d (%.0f°): зрушив на %.2f м, висота %.2f → %.2f"
				% [turn, rad_to_deg(dir.angle()), moved, from.y,
				   hero.global_position.y])
	quit()
