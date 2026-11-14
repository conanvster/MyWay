extends SceneTree
## Бій за перегородками дерев-велетів (13.11.2026: «щоб під час бою з
## монстрами можна було сховатися або втекти»).
##
##     godot --headless --path game --script res://probes/tree_fight.gd
##
## Монстр женеться прямою лінією без пошуку шляху (mob_ai.gd), а від
## застрягання в нього лише рефлекс «крок назад, тоді вбік» (creature.gd).
## Тож для кожної перегородки: гравець стає за нею, монстр — по той бік,
## на прямій крізь стіну; до 25 с симуляції по 1/60 с. Рахуємо, скільки
## монстрів обійшли й дістали гравця, скільки за хвилину так і лишились
## за стіною, і чи хтось не провалився крізь підлогу чи не застряг у тілі
## стіни. Вади — лише ці дві останні; «не обійшов» — це і є схованка, її
## частку проба показує, а не судить.

const MOB := preload("res://scenes/mob.tscn")
const AVATAR := preload("res://scenes/avatar.tscn")
const MAIN := preload("res://scenes/main.tscn")
const STEP := 1.0 / 60.0
const SECONDS := 25.0
## Скільки перегородок пробувати на поверсі (рівномірно з усіх).
const PER_FLOOR := 2

var _bad := 0
var _creatures := {}
var _combat: Combat
var _ai: MobAI
var _data: GameData


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
	_data = GameData.new()
	_data.load_all()
	_combat = Combat.new(_creatures)
	_combat.progress = Progress.new(_data.levels)
	_combat.goods = _data.items
	_combat.skills = _data.skills
	_ai = MobAI.new(_creatures, _combat)
	# Без Engine.time_scale: у Godot 4 він множить і крок фізики, і монстр
	# «біг» 28 м/с крізь пів зали. Тож бій іде в реальному часі.

	var world: Node3D = MAIN.instantiate()
	root.add_child(world)
	await process_frame
	var land: Landscape = world.get_node("Landscape")
	land.build(_data.map, false)
	await physics_frame
	await physics_frame
	var trees: Array[GiantTree] = land.giant_trees()
	_expect("дерев-велетів збудовано: %d" % trees.size(), not trees.is_empty())

	var totals := {"бої": 0, "дістав": 0, "за стіною": 0, "кинув погоню": 0,
			"загубив ціль": 0,
			"провалився": 0,
			"у стіні": 0, "пропущено": 0}
	var only := OS.get_environment("TREE_FIGHT_ONLY")
	for tree in trees:
		if only != "" and tree.title != only:
			continue
		print("\n— %s —" % tree.title)
		for k in tree.radii.size():
			var mine: Array = tree.screens.filter(func(s: Dictionary) -> bool:
				return int(s["k"]) == k)
			if mine.is_empty():
				continue
			var stride := maxi(1, mine.size() / PER_FLOOR)
			for i in range(0, mine.size(), stride):
				if i / stride >= PER_FLOOR:
					break
				if only != "" and (k > 0 or i > 0):
					continue
				var res: String = await _fight(tree, k, mine[i])
				totals[res] += 1
				if res != "пропущено":
					totals["бої"] += 1
	print("\n— разом —")
	print("    боїв %d: дістав гравця %d, кинув погоню %d, загубив ціль %d, усі 25 с тиснув у стіну %d"
			% [totals["бої"], totals["дістав"], totals["кинув погоню"],
			totals["загубив ціль"], totals["за стіною"]])
	print("    пропущено (місце зайняте) %d" % totals["пропущено"])
	_expect("ніхто не провалився крізь підлогу (%d)" % totals["провалився"],
			totals["провалився"] == 0)
	_expect("ніхто не застряг у тілі стіни (%d)" % totals["у стіні"],
			totals["у стіні"] == 0)
	_expect("боїв відбулось хоч скільки", totals["бої"] > 0)
	_expect("ніхто не тиснув у стіну всі 25 с (%d)" % totals["за стіною"],
			totals["за стіною"] == 0)
	print("\n%s" % ("усе гаразд" if _bad == 0 else "вад: %d" % _bad))
	quit(0 if _bad == 0 else 1)


## Один бій біля перегородки. Повертає, чим скінчився.
func _fight(tree: GiantTree, k: int, screen: Dictionary) -> String:
	var pts: Array = screen["pts"]
	var mid_i := pts.size() / 2
	var a: Vector3 = pts[mid_i - 1]
	var b: Vector3 = pts[mid_i]
	var along := (b - a)
	along.y = 0.0
	along = along.normalized()
	var across := Vector3(-along.z, 0.0, along.x)
	var mid: Vector3 = tree.position + (a + b) * 0.5
	var floor_y := tree.floors[k]
	var hide := mid + across * 3.0
	var chase := mid - across * 9.0
	hide.y = floor_y + 1.0
	chase.y = floor_y + 1.0
	var space := root.get_world_3d().direct_space_state
	if not _free(space, hide) or not _free(space, chase) \
			or tree.storey_of(hide) != k or tree.storey_of(chase) != k:
		return "пропущено"

	var player: Node3D = AVATAR.instantiate()
	root.add_child(player)
	player.place_at(hide, 0.0)
	_creatures[1] = player
	var mob: Node3D = MOB.instantiate()
	root.add_child(mob)
	mob.place_at(chase, 0.0)
	mob.home = chase
	mob.aggressive = true
	_creatures[-1] = mob
	mob.add_threat(1, 10.0)
	await physics_frame

	var res := "за стіною"
	var t := 0.0
	var best := INF
	while t < SECONDS:
		await physics_frame
		for c: Node in _creatures.values():
			c.server_step(STEP)
		# Гравець стоїть і не відповідає; живим його тримаємо, бо мета —
		# дорога монстра, а не бій.
		player.hp = player.stats.max_hp()
		_ai.think(-1, STEP)
		t += STEP
		if OS.has_environment("TREE_FIGHT_TRACE") and fmod(t, 0.5) < STEP:
			print("      t %.1f at %s side %d left %.2f blocked %.1f wanted %s" % [t,
					str(mob.global_position.snapped(Vector3.ONE * 0.1)), mob.detour_side,
					mob.detour_left, mob.blocked_for, str(mob.wanted)])
		var d := Vector2(mob.global_position.x - hide.x,
				mob.global_position.z - hide.z).length()
		best = minf(best, d)
		if mob.global_position.y < floor_y - 3.0:
			res = "провалився"
			break
		if d <= mob.ATTACK_RANGE + 0.6:
			res = "дістав"
			break
		if mob.calm_left > 0.0:
			res = "кинув погоню"
			break
		if mob.target_id == 0:
			res = "загубив ціль"
			break
	if res == "за стіною" and mob.calm_left > 0.0:
		res = "кинув погоню"
	if res != "дістав" and res != "провалився" \
			and not _free(space, mob.global_position, [mob.get_rid(), player.get_rid()]):
		res = "у стіні"
	print("    поверх %d, перегородка %.0f м: %s за %.1f с (найближче %.1f м)"
			% [k + 1, _length(pts), res, t, best])
	_creatures.clear()
	player.queue_free()
	mob.queue_free()
	await physics_frame
	return res


func _free(space: PhysicsDirectSpaceState3D, at: Vector3, skip: Array[RID] = []) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.45
	shape.height = 1.6
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), at + Vector3(0, 0.2, 0))
	q.exclude = skip
	return space.intersect_shape(q, 1).is_empty()


func _length(pts: Array) -> float:
	var s := 0.0
	for j in range(1, pts.size()):
		s += (pts[j] as Vector3).distance_to(pts[j - 1])
	return s
