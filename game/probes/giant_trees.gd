extends Node
## Дерева-велети з поверхами (слово замовника 07.11.2026, `data/dereva.json`).
##
##     ./run.sh --дерева [тека]
##
## Світ 2 як є. Для кожного дерева: поверхи, діаметри, рівні й множники;
## промінь згори в кожен поверх мусить сісти на його підлогу; кожен
## перехід — на своєму поверсі й усередині стін; зони й підсилення.
## Знімки: дерево здалеку, перший поверх від дверей, верхній поверх.

const MAIN := preload("res://scenes/main.tscn")
const MAP2 := "res://data/map2.json"

var _dir := "user://дерева"
var _bad := 0


func _ready() -> void:
	get_tree().create_timer(600.0).timeout.connect(func() -> void:
		print("‼ проба не скінчилась за 10 хв")
		get_tree().quit(1))
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and not args[0].begins_with("--"):
		_dir = args[0]
	DirAccess.make_dir_recursive_absolute(_dir)
	call_deferred("_go")


func _expect(what: String, ok: bool) -> void:
	if not ok:
		_bad += 1
	print("  %s %s" % ["✓" if ok else "✗", what])


func _go() -> void:
	await get_tree().process_frame
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var net: Node = get_tree().root.get_node_or_null("Net")
	if net != null:
		net.joined = true
	var world: Node3D = MAIN.instantiate()
	get_tree().root.add_child(world)
	await get_tree().process_frame
	var land: Landscape = world.get_node("Landscape")
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAP2))
	land.build(map, true)
	land.fog_to_vision(160.0)
	var eye := Camera3D.new()
	eye.far = 1500.0
	eye.fov = 60.0
	get_tree().root.add_child(eye)
	eye.make_current()
	var mobs: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/mobs.json"))
	var trees: Array[GiantTree] = land.giant_trees()
	_expect("дерев-велетів збудовано: %d з %d у даних" % [trees.size(),
			GiantTree.rules()["дерева"].size()],
			trees.size() == GiantTree.rules()["дерева"].size())
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := world.get_world_3d().direct_space_state
	for t in trees.size():
		var tree := trees[t]
		var n := tree.radii.size()
		print("\n— %s: поверхів %d, діаметр %.0f → %.0f м, висота %.0f м —"
				% [tree.title, n, tree.radii[0] * 2.0, tree.radii[n - 1] * 2.0,
				tree.floors[n] - tree.floors[0]])
		for k in n:
			print("    поверх %d: підлога %.1f м, діаметр %.0f м, рівень %d, ×%.2f"
					% [k + 1, tree.floors[k], tree.radii[k] * 2.0,
					tree.levels[k], tree.boosts[k]])
		_expect("рівні ростуть на 2 або 3", _steps_ok(tree.levels))
		_expect("множник ×2 → ×4", is_equal_approx(tree.boosts[0], 2.0)
				and is_equal_approx(tree.boosts[n - 1], 4.0))
		# Промінь згори в точку на половині радіуса кожного поверху.
		for k in range(1, n):
			var a := tree.door_angle + 1.0
			var x := tree.position.x + cos(a) * tree.radii[k] * 0.5
			var z := tree.position.z + sin(a) * tree.radii[k] * 0.5
			var top := tree.floors[k + 1] - GiantTree.SLAB - 0.5
			var ray := PhysicsRayQueryParameters3D.create(Vector3(x, top, z),
					Vector3(x, tree.floors[k] - 5.0, z))
			var hit := space.intersect_ray(ray)
			_expect("поверх %d: промінь сів на підлогу (%.2f, чекав %.2f)"
					% [k + 1, float(hit.get("position", Vector3.INF).y)
					if not hit.is_empty() else NAN, tree.floors[k]],
					not hit.is_empty() and absf(hit["position"].y
					- tree.floors[k]) < 0.1)
		for s: Dictionary in tree.steps:
			var k: int = s["з"]
			var low: Vector3 = s["низ"]
			var high: Vector3 = s["верх"]
			_expect("перехід %d→%d (%s): низ на поверсі %d, верх на %d"
					% [k + 1, k + 2, s["вид"], tree.storey_of(low + Vector3.UP)
					+ 1, tree.storey_of(high + Vector3.UP) + 1],
					tree.storey_of(low + Vector3.UP) == k
					and tree.storey_of(high + Vector3.UP) == k + 1)
			var up: Array = tree.step_at(low + Vector3.UP)
			var down: Array = tree.step_at(high + Vector3.UP)
			_expect("    біля низу питає «вгору», біля верху — «вниз»",
					up.size() == 2 and up[1] == true
					and down.size() == 2 and down[1] == false)
			var arrive := tree.arrival(tree.steps.find(s), true)
			_expect("    після підйому стоїть не в колі переходу",
					tree.step_at(arrive).is_empty()
					or tree.step_at(arrive)[1] == true)
		var zones: Array = tree.zones(mobs)
		var per := {}
		var total := 0
		for zone: MobZone in zones:
			var k := tree.storey_of(zone.global_position + Vector3.UP)
			per[k] = int(per.get(k, 0)) + zone.count
			total += zone.count
			if zone.on_floor and not zone.has_point(zone.random_point()):
				_bad += 1
		print("    монстрів по поверхах: %s, усього %d" % [per, total])
		_expect("на кожному поверсі є монстри", per.size() == n
				and not per.has(-1))
		var sample: MobZone = zones[zones.size() - 1]
		var raw: Dictionary = mobs[str(sample.kind)]
		var lifted := GiantTree.boosted(raw, sample.level_set, sample.boost)
		print("    верх: %s рів. %d → %d, стати %s → %s, дроп[0] %s → %s"
				% [raw["назва"], raw["рівень"], lifted["рівень"], raw["стати"],
				lifted["стати"], raw["дроп"][0], lifted["дроп"][0]])
		_expect("підсилення: рівень поверху, стати ×%.1f" % sample.boost,
				int(lifted["рівень"]) == sample.level_set
				and int(lifted["стати"]["сила"]) == int(round(
				float(raw["стати"]["сила"]) * sample.boost)))
		for zone: MobZone in zones:
			zone.queue_free()
		print("    точка телепорту: (%.0f, %.0f), %.0f м від кори"
				% [tree.port_spot.x, tree.port_spot.y,
				tree.port_spot.distance_to(Vector2(tree.position.x,
				tree.position.z)) - tree.radii[0] - tree.wall])
		_expect("під стовбуром немає звичайних дерев",
				_trees_inside(land, tree) == 0)
		_live_check(world, tree, t, mobs)
		await _shots(land, tree, eye, t)
	print("\nзнімки: %s\nпомилок: %d" % [ProjectSettings.globalize_path(_dir),
			_bad])
	get_tree().quit(1 if _bad > 0 else 0)


## Через сам сервер: персонаж біля низу першого переходу просить
## «вгору» — і стоїть на другому поверсі; просить чужий перехід — ні.
## Потім — чи будить він лише зони свого поверху.
func _live_check(world: Node, tree: GiantTree, t: int, mobs: Dictionary) -> void:
	var id := 900 + t
	var low: Vector3 = tree.steps[0]["низ"]
	var a: Node3D = world.spawn(id, low + Vector3.UP)
	a.global_position = low + Vector3.UP
	world.tree_step(id, t, 1, true)
	_expect("чужий перехід не пускає", tree.storey_of(a.global_position) == 0)
	world.tree_step(id, t, 0, true)
	_expect("драбиною вгору: тепер поверх %d (чекав 2)"
			% (tree.storey_of(a.global_position) + 1),
			tree.storey_of(a.global_position) == 1)
	var spawner := Spawner.new(world.creatures, world, world.data)
	spawner.dormant = true
	var zones: Array = tree.zones(mobs)
	spawner.start(zones)
	spawner._wake_or_sleep()
	var woke := {}
	for zone: MobZone in zones:
		if spawner._awake.get(zone, false):
			var k := tree.storey_of(zone.global_position + Vector3.UP)
			woke[k] = true
	_expect("прокинувся лише поверх 2 (прокинулись: %s)" % woke.keys(),
			woke.keys() == [1])
	var any_mob: Node = null
	for cid: int in world.creatures:
		if cid < 0:
			any_mob = world.creatures[cid]
	if any_mob != null:
		_expect("монстр поверху 2 з'явився на підлозі (%.1f, підлога %.1f), "
				% [any_mob.global_position.y, tree.floors[1]]
				+ "рівень %d" % any_mob.level,
				absf(any_mob.global_position.y - tree.floors[1] - 1.0) < 0.5
				and any_mob.level == tree.levels[1])
	for zone: MobZone in zones:
		spawner._put_to_sleep(zone)
		zone.queue_free()
	world.remove(id)


func _steps_ok(levels: Array[int]) -> bool:
	for k in range(1, levels.size()):
		if not (levels[k] - levels[k - 1]) in [2, 3]:
			return false
	return true


func _trees_inside(land: Landscape, tree: GiantTree) -> int:
	var inside := 0
	for list: Array in land._tree_specs.values():
		for spec: Dictionary in list:
			var at: Vector3 = spec["at"]
			if Vector2(at.x - tree.position.x, at.z - tree.position.z).length() \
					< tree.radii[0] + tree.wall:
				inside += 1
	return inside


func _shots(land: Landscape, tree: GiantTree, eye: Camera3D, t: int) -> void:
	var n := tree.radii.size()
	var c := Vector3(tree.position.x, tree.floors[0], tree.position.z)
	var door := Vector3(cos(tree.door_angle), 0, sin(tree.door_angle))
	var side := Vector3(-door.z, 0, door.x)
	var high := tree.trunk_top - tree.floors[0]
	var far := tree.radii[0] * 3.2 + high * 0.6
	var views := [
		["здалеку", c + door * far + side * far * 0.4 + Vector3.UP * high * 0.45,
				c + Vector3.UP * high * 0.45],
		["двері", Vector3(c.x, tree.door_ground, c.z) + door
				* (tree.outer_r(tree.door_angle, tree.door_ground + 5.0) + 28.0)
				+ Vector3.UP * 7.0, Vector3(c.x, tree.door_ground + 5.0, c.z)],
		["поверх-1", c + door * (tree.radii[0] - 6.0) + Vector3.UP * 7.0,
				c - door * tree.radii[0] + Vector3.UP * 2.0],
		["поверх-2", Vector3(c.x, tree.floors[1] + 6.0, c.z)
				+ door * (tree.radii[1] - 5.0),
				Vector3(c.x, tree.floors[1] + 1.0, c.z) - door * tree.radii[1] * 0.6],
		["верх", Vector3(c.x, tree.floors[n - 1] + 8.0, c.z)
				+ door * (tree.radii[n - 1] - 4.0),
				Vector3(c.x, tree.floors[n - 1] + 3.0, c.z)
				- door * tree.radii[n - 1] * 0.5],
	]
	land.fog_to_vision(far * 1.3)
	for v: Array in views:
		land.stream_to(v[1])
		eye.look_at_from_position(v[1], v[2], Vector3.UP)
		for i in 12:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%d-%s.png"
				% [_dir, t + 1, v[0]])
