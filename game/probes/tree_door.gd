extends SceneTree
## Чи можна зайти в дерево-велет дверима (14.11.2026: замовник після
## переносу майстром магії стояв перед дверима Пузатого Баобаба й не міг
## зайти).
##
##     godot --headless --path game --script res://probes/tree_door.gd
##
## Для кожного дерева: гравець стає на точку переносу (`port_spot`) і йде
## прямо до середини дерева 25 с, як ходить справжній — `wanted` щокроку,
## `server_step`, фізика рушія. Мусить опинитись усередині першого
## поверху. Не дійшов — друкує, де став і в що вперся.

const AVATAR := preload("res://scenes/avatar.tscn")
const MAIN := preload("res://scenes/main.tscn")
const STEP := 1.0 / 60.0
const SECONDS := 25.0

var _bad := 0


func _init() -> void:
	call_deferred("_go")


func _expect(what: String, ok: bool) -> void:
	if not ok:
		_bad += 1
	print("  %s %s" % ["✓" if ok else "✗", what])


func _go() -> void:
	await process_frame
	var net: Node = root.get_node_or_null("Net")
	if net != null:
		net.joined = true
	GameData.chosen_map = GameData.MAP2_PATH
	var data := GameData.new()
	data.load_all()
	var world: Node3D = MAIN.instantiate()
	root.add_child(world)
	await process_frame
	var land: Landscape = world.get_node("Landscape")
	land.build(data.map, false)
	await physics_frame
	await physics_frame
	var space := root.get_world_3d().direct_space_state
	for tree: GiantTree in land.giant_trees():
		print("\n— %s —" % tree.title)
		var start := Vector3(tree.port_spot.x, 0.0, tree.port_spot.y)
		start.y = land.height_at(start.x, start.z) + 1.2
		var hero: Node3D = AVATAR.instantiate()
		root.add_child(hero)
		hero.place_at(start, 0.0)
		await physics_frame
		var goal := Vector3(tree.position.x, tree.floors[0], tree.position.z)
		print("    старт %s, двері на висоті %.1f, підлога 1 поверху %.1f, земля під стартом %.1f"
				% [str(start.snapped(Vector3.ONE * 0.1)), tree.door_ground,
				tree.floors[0], land.height_at(start.x, start.z)])
		var t := 0.0
		var inside := false
		var last := hero.global_position
		var still := 0.0
		while t < SECONDS:
			var d := goal - hero.global_position
			d.y = 0.0
			hero.wanted = Vector2(d.x, d.z).normalized()
			await physics_frame
			hero.server_step(STEP)
			t += STEP
			var flat := Vector2(hero.global_position.x - tree.position.x,
					hero.global_position.z - tree.position.z).length()
			if flat < tree.radii[0] - 6.0:
				inside = true
				break
			if hero.global_position.distance_to(last) < 0.02:
				still += STEP
			else:
				still = 0.0
			last = hero.global_position
			if still > 3.0:
				break
		var at := hero.global_position
		var flat_now := Vector2(at.x - tree.position.x, at.z - tree.position.z).length()
		var why := ""
		if not inside:
			var dir := goal - at
			dir.y = 0.0
			dir = dir.normalized()
			for high: float in [0.0, 0.6, 1.5]:
				var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * (high - 0.5),
						at + Vector3.UP * (high - 0.5) + dir * 3.0)
				q.exclude = [hero.get_rid()]
				var hit := space.intersect_ray(q)
				if not hit.is_empty():
					why += " | на висоті %.1f: %s за %.2f м, нормаль %s" % [high,
							(hit["collider"] as Node).get_path(),
							(hit["position"] as Vector3).distance_to(at + Vector3.UP * (high - 0.5)),
							str((hit["normal"] as Vector3).snapped(Vector3.ONE * 0.01))]
		_expect("зайшов на 1 поверх за %.1f с (став у %s, %.1f м від середини, радіус %.0f)%s"
				% [t, str(at.snapped(Vector3.ONE * 0.1)), flat_now, tree.radii[0], why],
				inside)
		hero.queue_free()
		await physics_frame
	print("\n%s" % ("усе гаразд" if _bad == 0 else "вад: %d" % _bad))
	quit(0 if _bad == 0 else 1)
