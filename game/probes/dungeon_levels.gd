extends Node
## Рівні підземелля й боси (П-153, Ф5′/Ф6; П-191 і П-192 — слово
## замовника 19.09.2026: «з вагами статів», «бос із наступної смуги»).
##
## Що перевіряється: сильнішому частіше випадає складніший шаблон; рівнів
## стільки, скільки дає сила; бос — із наступної смуги й не вертається;
## смерть боса запалює «Далі», спуск веде на глибший рівень, де монстри
## сильніші; останній бос — зачистка й закриття без штрафу; відновлення
## після перезапуску ставить ті самі рівні без уже вбитих босів.
##
## Ганяти так (сценою, бо потрібні автозавантаження):
##     godot --headless --path game res://scenes/dungeon_levels.tscn -- --світ1

const MAIN := preload("res://scenes/main.tscn")

var _ok := 0
var _bad := 0


class Quiet extends Messenger:
	var said: Array[String] = []

	func notice(_id: int, text: String) -> void:
		said.append(text)

	func to_all(_method: StringName, _args: Array = []) -> void:
		pass

	func to_watchers(_subject: int, _method: StringName,
			_args: Array = []) -> void:
		pass

	func to_one(_peer: int, _method: StringName, _args: Array = []) -> void:
		pass


func _ready() -> void:
	_go()


func _yes(text: String, is_ok: bool) -> void:
	if is_ok:
		_ok += 1
		print("  ✓ %s" % text)
	else:
		_bad += 1
		print("  ✗ %s" % text)


func _boss_in(world: Node, key: int) -> Node:
	for id: int in world.creatures:
		var c: Node3D = world.creatures[id]
		if id < 0 and c.is_boss and c.is_alive() and world.dungeons.index_at(
				c.global_position.x, c.global_position.z) == key:
			return c
	return null


func _kill_boss(world: Node, key: int) -> Node:
	var boss := _boss_in(world, key)
	if boss == null:
		return null
	var id := 0
	for k: int in world.creatures:
		if world.creatures[k] == boss:
			id = k
	boss.die()
	world._on_kill(id, boss)
	return boss


func _go() -> void:
	await get_tree().process_frame
	Net.joined = true
	var world: Node3D = MAIN.instantiate()
	get_tree().root.add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame
	world.link = Quiet.new(world, null)
	var life := DungeonLife.new()
	world.add_child(life)
	life.setup(null, world.dungeons.book.life, GameData.world_key())
	world.life = life
	var book: DungeonBook = world.dungeons.book
	var land: Node = world.get_node("Landscape")

	print("\n— ваги статів (П-191) —")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var means := {}
	for power: int in [50, 80]:
		var sum := 0.0
		for i in 400:
			sum += float(book.templates[book.pick_weighted(rng, power, 0)]
					["складність"])
		means[power] = sum / 400.0
	_yes("новачок (сила 50) — середня складність %.2f, сильний (80) — %.2f"
			% [means[50], means[80]], means[80] > means[50] + 1.0)
	_yes("рівнів: сила 50 → %d, 68 → %d, 200 → %d (межа 10)"
			% [book.depth_for(50), book.depth_for(68), book.depth_for(200)],
			book.depth_for(50) == 2 and book.depth_for(68) == 4
			and book.depth_for(200) == 10)

	print("\n— бос і рівні (Ф5′/Ф6, П-192) —")
	var at := 0
	var shrine: Shrine = land.shrines()[at]
	var me: Node = world.spawn(1, shrine.global_position + Vector3(1.5, 0, 0))
	me.items = {"ключ святині %s" % shrine.grade: 1}
	me.hp = maxi(me.hp, 50)
	shrine.set_stage(Shrine.Stage.ЗАЧИЩЕНА)
	world.activate_shrine(1, at)
	await get_tree().process_frame
	me.global_position = shrine.portal().global_position
	world.enter_dungeon(1, at)
	await get_tree().process_frame
	var first := Dungeons.key(at, 0)
	var depth: int = world.dungeons.open[first]["depth"]
	_yes("підземелля відкрито, рівнів %d (сила %d)"
			% [depth, DungeonBook.power_of(me)], depth >= 2)
	var boss := _boss_in(world, first)
	var grades: Array = ItemBook.GRADES
	var next_band := DungeonBook.band(world.data.mobs,
			grades[grades.find(shrine.grade) + 1])
	_yes("бос є і він із наступної смуги (%s): %s"
			% [grades[grades.find(shrine.grade) + 1],
			   world.data.mobs[str(boss.kind)]["назва"] if boss else "—"],
			boss != null and next_band.has(boss.kind))

	_kill_boss(world, first)
	var down: Portal = world.dungeons.open[first]["down"]
	_yes("бос повалений — «Далі» запалено", down != null)
	var zone_spent := false
	for zone: Node in world.dungeons.open[first]["zones"]:
		if zone is MobZone and zone.boss:
			zone_spent = zone.spent
	_yes("зона боса більше не заселяється", zone_spent)

	me.global_position = down.global_position
	world.descend(1, first)
	await get_tree().process_frame
	var second := Dungeons.key(at, 1)
	_yes("спуск: гравець на рівні 2",
			world.dungeons.index_at(me.global_position.x,
					me.global_position.z) == second)
	var deep: Node = null
	for id: int in world.creatures:
		var c: Node3D = world.creatures[id]
		if id < 0 and world.dungeons.index_at(c.global_position.x,
				c.global_position.z) == second and not c.is_boss:
			deep = c
			break
	var deep_hp: int = deep.stats.max_hp() if deep != null else 0
	var base_hp := 0
	if deep != null:
		var bare := Stats.new()
		bare.strength = deep.base_stats.strength
		bare.stamina = deep.base_stats.stamina
		bare.agility = deep.base_stats.agility
		base_hp = bare.max_hp()
	_yes("на рівні 2 монстри сильніші: здоров'я %d проти %d"
			% [deep_hp, base_hp], deep != null and deep_hp > base_hp)

	# Решта рівнів — до кінця.
	var level := 1
	while level < depth:
		var key := Dungeons.key(at, level)
		_kill_boss(world, key)
		if level + 1 < depth:
			me.global_position = world.dungeons.open[key]["down"] \
					.global_position
			world.descend(1, key)
			await get_tree().process_frame
		level += 1
	_yes("останній бос — зачистка почалась", world._clearing.has(at))
	world._tick_clearing(world.CLEAR_AFTER + 1.0)
	_yes("зачищене закрилось: рівнів лишилось %d"
			% world.dungeons.levels_of(at).size(),
			world.dungeons.levels_of(at).is_empty())
	_yes("без штрафу світу (штрафів %d), запис прибрано"
			% life.penalties.size(),
			life.penalties.is_empty() and not life.records.has(at))
	_yes("гравець повернувся до святині (%.1f м)"
			% me.global_position.distance_to(shrine.global_position),
			me.global_position.distance_to(shrine.global_position) < 12.0)
	_yes("святиня знову під охороною",
			shrine.stage == Shrine.Stage.ПІД_ОХОРОНОЮ)

	print("\n— відновлення після перезапуску —")
	var two := 2
	world._restore_dungeon(two, {"template": "старий-льох", "seed": 5,
			"grade": land.shrines()[two].grade, "depth": 3, "cleared": 1,
			"levels": [{"template": "старий-льох", "seed": 5},
					{"template": "костниця", "seed": 9}]})
	var r0 := Dungeons.key(two, 0)
	var r1 := Dungeons.key(two, 1)
	_yes("обидва рівні стоять, шаблони ті самі",
			world.dungeons.open.has(r0) and world.dungeons.open.has(r1)
			and world.dungeons.open[r1]["template"] == "костниця")
	_yes("на рівні 1 боса немає (вже вбитий), «Далі» горить",
			_boss_in(world, r0) == null
			and world.dungeons.open[r0]["down"] != null)
	_yes("на рівні 2 бос є", _boss_in(world, r1) != null)

	print("  підсумок: %d з %d" % [_ok, _ok + _bad])
	get_tree().quit(1 if _bad > 0 else 0)
