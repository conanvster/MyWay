extends SceneTree
## Проба Р-6: NPC убивані, охорона поселень (П-262, П-73).
##
##     godot --headless --path game --script res://probes/wardens.gd
##
## Не «начебто б'ються», а числа: хто кого взяв на загрозу, скільки
## метрів до нападника, де вартовий зупинився, кому відмовлено. Світ 1
## (`map.json`): Стільна в (0, 0) радіусом 26, вартовий Тиміш на (10, 0, 1).

const MOB := preload("res://scenes/mob.tscn")
const AVATAR := preload("res://scenes/avatar.tscn")
const STEP := 1.0 / 60.0

var _bad := 0
var _creatures := {}
var _wardens: Wardens
var _combat: Combat
var _ai: MobAI
var _data: GameData
var _next := 0


func _init() -> void:
	call_deferred("_go")


func _expect(what: String, ok: bool) -> void:
	if not ok:
		_bad += 1
	print("  %s %s" % ["✓" if ok else "✗", what])


func _go() -> void:
	await process_frame
	var floor := StaticBody3D.new()
	var plane := CollisionShape3D.new()
	plane.shape = WorldBoundaryShape3D.new()
	floor.add_child(plane)
	root.add_child(floor)

	GameData.chosen_map = GameData.MAP_PATH
	_data = GameData.new()
	_data.load_all()
	_combat = Combat.new(_creatures)
	_combat.progress = Progress.new(_data.levels)
	_combat.goods = _data.items
	_combat.skills = _data.skills
	_ai = MobAI.new(_creatures, _combat)
	_wardens = Wardens.new(_creatures)
	_wardens.names = {1: "Проба"}
	_wardens.setup(_data.map)
	_combat.on_kill = func(_v_id: int, victim: Node, killer: int) -> void:
		_wardens.on_kill(victim, killer)

	print("\n— поселення й пости (світ 1) —")
	var town: Dictionary = _wardens.settlements[0]
	print("    поселень %d; у «%s» мешканців %s, постів %d"
			% [_wardens.settlements.size(), town["назва"],
			   town["мешканці"], town["пости"].size()])
	_expect("4 поселення, у кожному пост", _wardens.settlements.size() == 4
			and _wardens.settlements.all(func(s: Dictionary) -> bool:
				return s["пости"].size() == 1))
	_expect("вартовий не серед мешканців (номер 3 — Тиміш)",
			not town["мешканці"].has(3) and _wardens.settlement_of(3) == -1)
	var placed := _wardens.post_guards(_spawn, _new_id)
	for i in 30:
		await _tick_all()
	var guard_id: int = town["вартові"][0]
	var guard: Node3D = _creatures[guard_id]
	print("    поставлено %d; вартовий %d: вид %d, рівень %d, здоров'я %d, "
			% [placed, guard_id, guard.kind, guard.level, guard.hp]
			+ "повідець %.1f м" % guard.leash)
	_expect("вартових 4, вид 900", placed == 4
			and guard.kind == Wardens.GUARD_KIND)
	_expect("здоров'я вартового з даних (сила/витр. 100) = 640",
			guard.stats.max_hp() == 640)
	_expect("модель людини з набором рухів",
			guard.get_node_or_null("Mesh") is SkinnedModel
			and guard.get_node("Mesh").anim_path != "")
	_expect("мешканець — 6000 здоров'я, захист 150",
			_wardens.hp_of(0) == 6000
			and is_equal_approx(_wardens.resident_defence(), 150.0))

	var hero: Node3D = AVATAR.instantiate()
	root.add_child(hero)
	await process_frame
	_creatures[1] = hero
	hero.level = 40
	hero.place_at(Vector3(-6, 1, 0), 0.0)
	var hero_hp: int = hero.hp
	for i in 10:
		await _tick_all()

	print("\n— спокій: охорона не чіпає чесного гравця —")
	for i in 120:
		await _tick_all()
	_expect("вартовий без цілі", guard.target_id == 0)
	_expect("гравець без шкоди", hero.hp == hero_hp)

	print("\n— удар по мешканцю → охорона б'є нападника —")
	var hit := _wardens.hit_resident(1, 0, hero.stats.physical_attack())
	print("    удар %d, у мешканця лишилось %d/%d" % [hit, _wardens.hp_of(0),
			_wardens.resident_max_hp()])
	_expect("шкода пройшла крізь захист (≥1)", hit >= 1
			and _wardens.hp_of(0) == 6000 - hit)
	_expect("ще не вбивця — послуги є", not _wardens.refuses(1, 1))
	var t := 0.0
	while t < 8.0 and hero.hp == hero_hp:
		await _tick_all()
		t += STEP
	var d: float = guard.global_position.distance_to(hero.global_position)
	print("    вартовий ударив за %.1f с, між ними %.1f м, у гравця %d/%d"
			% [t, d, hero.hp, hero.stats.max_hp()])
	_expect("вартовий підбіг і вдарив", guard.target_id == 1
			and hero.hp < hero_hp)

	print("\n— убивство мешканця → відмова й полювання —")
	hero.hp = hero.stats.max_hp()
	var blows := 0
	while not _wardens.is_dead(0) and blows < 100000:
		_wardens.hit_resident(1, 0, hero.stats.physical_attack())
		blows += 1
	print("    до смерті мешканця %d ударів гравця 40 рівня (атака %.1f)"
			% [blows + 1, hero.stats.physical_attack()])
	_expect("мешканець мертвий", _wardens.is_dead(0))
	_expect("інший мешканець того ж поселення відмовляє",
			_wardens.refuses(1, 1))
	var other_town: int = _wardens.settlements[1]["мешканці"][0]
	_expect("мешканець іншого поселення — ні",
			not _wardens.refuses(1, other_town))
	_expect("інший гравець — обслуговується", not _wardens.refuses(2, 1))

	print("\n— охорона далеко від поселення не відходить —")
	# Утікаємо на схід бігом, щокадру; вартовий жене до повідця.
	guard.forget()
	guard.target_id = 0
	var farthest := 0.0
	hero.hp = 100000
	for i in 60 * 30:
		var p: Vector3 = hero.global_position
		if p.x < 70.0:
			hero.place_at(Vector3(p.x + 0.12, 1, 0), 0.0)
		await _tick_all()
		var off := Vector2(guard.global_position.x, guard.global_position.z) \
				.length()
		farthest = maxf(farthest, off)
	var limit: float = town["радіус"] + 10.0
	print("    гравець на %.0f м від центру; вартовий найдалі — %.1f м "
			% [hero.global_position.length(), farthest]
			+ "(повідець від посту — %.1f м, межа %.1f м)"
			% [guard.leash, limit])
	_expect("вартовий не далі повідця (+1 м на крок)", farthest <= limit + 1.0)
	_expect("вартовий вертається додому", guard.global_position.distance_to(
			guard.home) < 3.0 or guard.target_id == 0)

	print("\n— повернувся в поселення → знову полюють —")
	hero.place_at(Vector3(-5, 1, 0), 0.0)
	t = 0.0
	while t < 3.0 and guard.target_id != 1:
		await _tick_all()
		t += STEP
	_expect("вартовий узяв убивцю за %.1f с" % t, guard.target_id == 1)

	print("\n— убитий вартовий: без нагороди, у «чорний список» —")
	var victim_town: Dictionary = _wardens.settlements[2]
	var g2: Node3D = _creatures[victim_town["вартові"][0]]
	var respect_before: int = hero.respect
	g2.hp = 1
	hero.place_at(g2.global_position + Vector3(1.5, 0, 0), 0.0)
	await _tick_all()
	hero.target_id = victim_town["вартові"][0]
	hero.attack_ready_in = 0.0
	_combat.attack(1)
	_expect("вартовий загинув", not g2.is_alive())
	_expect("повага не прийшла (%d → %d)" % [respect_before, hero.respect],
			hero.respect == respect_before)
	_expect("убивця вартового — у чорному списку поселення 3",
			_wardens.is_wanted(1, 2))
	_expect("вартового більше немає серед живих поста",
			victim_town["вартові"].is_empty())

	print("\n— перезапуск світу скидає все (П-73) —")
	var fresh := Wardens.new({})
	fresh.names = {1: "Проба"}
	fresh.setup(_data.map)
	_expect("мешканець живий, повне здоров'я", not fresh.is_dead(0)
			and fresh.hp_of(0) == 6000)
	_expect("відмов немає", not fresh.refuses(1, 1))

	print("\n— світ 2: охорона в кожному поселенні —")
	GameData.chosen_map = GameData.MAP2_PATH
	var data2 := GameData.new()
	data2.load_all()
	var w2 := Wardens.new({})
	w2.setup(data2.map)
	var empty: Array = []
	for s: Dictionary in w2.settlements:
		if s["пости"].is_empty():
			empty.append(s["назва"])
	print("    поселень %d, без поста: %s" % [w2.settlements.size(), empty])
	_expect("9 поселень, без поста — жодного", w2.settlements.size() == 9
			and empty.is_empty())

	print("\nпомилок: %d" % _bad)
	quit(1 if _bad > 0 else 0)


func _new_id() -> int:
	_next += 1
	return -_next


func _spawn(id: int, at: Vector3) -> Node:
	var m: Node3D = MOB.instantiate()
	root.add_child(m)
	m.place_at(at, 0.0)
	m.global_position = at + Vector3(0, 1, 0)
	_creatures[id] = m
	return m


func _tick_all() -> void:
	await physics_frame
	for a: Node in _creatures.values():
		a.server_step(STEP)
	for id: int in _creatures:
		if id < 0:
			_ai.think(id, STEP)
	_wardens.tick(STEP)
