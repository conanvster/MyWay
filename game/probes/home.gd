extends Node
## Скіл «повернутися в місто»: чи витягує звідусіль і чи садить на землю.
##
## Причина, з якої скіл узагалі з'явився (слово замовника 05.09.2026):
## «намагаюсь протестувати але впав за текстури… респавнюсь під рівнем
## землі». Тобто перевіряти треба саме це — не «скіл спрацював», а
## «після нього персонаж СТОЇТЬ НА ЗЕМЛІ в місті», з будь-якої дірки.
##
## Ганяти так:
##     godot --headless --path game res://scenes/home.tscn

const AVATAR := preload("res://scenes/avatar.tscn")
const MAIN := preload("res://scenes/main.tscn")
const MAP2 := "res://data/map2.json"
const KEY := "повернення-в-місто"

var _bad := 0


class Recorder extends Messenger:
	var sent: Array = []

	func _init(vision: Vision = null) -> void:
		super(null, vision)

	func to_one(peer: int, method: StringName, args: Array = []) -> void:
		sent.append({"peer": peer, "method": String(method), "args": args})

	func to_watchers(who: int, method: StringName, args: Array = []) -> void:
		sent.append({"peer": who, "method": String(method), "args": args})


func _ready() -> void:
	call_deferred("_go")


func _fail(text: String) -> void:
	_bad += 1
	print("  ‼ " + text)


func _go() -> void:
	await get_tree().process_frame
	var data := GameData.new()
	data.load_all()

	print("\n— скіл у даних —")
	var skill: Skill = data.skills.get_skill(KEY)
	if skill == null:
		_fail("скіла «%s» у data/skills.json немає" % KEY)
		get_tree().quit(1)
		return
	print("  «%s»: ціль %s, каст %.0f поінтів, відкат %.0f, мана %d"
			% [skill.name, skill.target, skill.cast_points,
			   skill.cooldown_points, skill.mana(1)])
	print("  переносить у місто: %s" % skill.sends_home(1))
	if not skill.sends_home(1):
		_fail("скіл не позначений як переніс у місто")
	if skill.mana(1) != 0:
		_fail("скіл коштує мани — застряглий гравець може її не мати")
	print("  дається на старті: %s" % data.starting_skills.has(KEY))
	if not data.starting_skills.has(KEY):
		_fail("скіла немає в стартових — його нізвідки взяти")
	print("  на панелі за замовчуванням: %s"
			% ("скіл:" + KEY in data.bar))

	# Справжній світ версії 2: місто стоїть там, де стоїть, і земля під
	# ним справжня. Без цього перевірка «сів на землю» нічого не варта.
	var text := FileAccess.get_file_as_string(MAP2)
	var map: Dictionary = JSON.parse_string(text) if not text.is_empty() \
			else data.map
	# Світ-клієнт сам стукає на 127.0.0.1, а там може саме йти
	# гра замовника (19.09.2026: проба під'єдналась до живого
	# сервера світу 2 й перезапускалась по колу). «Уже в мережі» —
	# і `Net.join()` нічого не робить.
	var net: Node = get_tree().root.get_node_or_null("Net")
	if net != null:
		net.joined = true
	var world: Node3D = MAIN.instantiate()
	get_tree().root.add_child(world)
	await get_tree().process_frame
	var land: Node = world.get_node("Landscape")
	land.build(map)
	await get_tree().process_frame

	var towns: Array = map.get("міста", [])
	var centre: Array = towns[0].get("центр", [0, 0, 0]) if not towns.is_empty() \
			else [0, 0, 0]
	var home := Vector2(float(centre[0]), float(centre[2]))
	var ground: float = land.height_at(home.x, home.y)
	print("\n— куди вертає —")
	print("  місто «%s» у (%.0f, %.0f), земля там %.2f м"
			% [towns[0].get("назва", "?") if not towns.is_empty() else "?",
			   home.x, home.y, ground])

	var hero: Node3D = AVATAR.instantiate()
	world.add_child(hero)
	await get_tree().process_frame
	var creatures := {1: hero}
	var vision := Vision.new(creatures)
	vision.watch(1)
	var link := Recorder.new(vision)
	var combat := Combat.new(creatures, link)
	combat.skills = data.skills
	combat.ground_height = func(x: float, z: float) -> float:
		return land.height_at(x, z)
	combat.home_spot = home
	hero.learn(KEY, 1)

	# Три дірки, з яких треба витягти: під землею, за краєм світу й
	# просто далеко. Перша — те, що сталось у замовника.
	var holes := [
		["під землею", Vector3(600.0, ground - 80.0, -400.0)],
		["за краєм світу", Vector3(9000.0, 5.0, 9000.0)],
		["просто далеко", Vector3(-2100.0, 60.0, -2400.0)],
	]
	print("\n— витягує з дірки —")
	for hole: Array in holes:
		var from: Vector3 = hole[1]
		hero.place_at(from, 0.0)
		hero.hp = hero.stats.max_hp()
		hero.mp = 0                      # мани немає навмисно
		hero.skill_ready_in.clear()
		hero.stop_cast()
		link.sent.clear()
		var started: bool = combat.cast(1, KEY)
		# Скіл довгий: читається, а не спрацьовує миттю.
		var guard := 0
		while hero.is_casting() and guard < 4000:
			combat.tick_casts(0.05)
			guard += 1
		var at := hero.global_position
		var under: float = land.height_at(at.x, at.z)
		var near: float = Vector2(at.x - home.x, at.z - home.y).length()
		print("  %s: з (%.0f, %.0f, %.0f) → (%.0f, %.1f, %.0f); "
				% [hole[0], from.x, from.y, from.z, at.x, at.y, at.z]
				+ "земля %.2f, від міста %.0f м, читання %s"
				% [under, near, "почалось" if started else "НЕ почалось"])
		if not started:
			_fail("%s: скіл не почав читатись" % hole[0])
		if near > 1.0:
			_fail("%s: після скіла не в місті (%.0f м)" % [hole[0], near])
		if at.y < under:
			_fail("%s: поставлено ПІД землю (%.2f проти %.2f)"
					% [hole[0], at.y, under])

	print("\n— чого скіл не робить —")
	hero.skill_ready_in.clear()
	hero.hp = 0
	hero.die()
	print("  мертвому не читається: %s (має бути false)"
			% combat.cast(1, KEY))
	if combat.cast(1, KEY):
		_fail("скіл працює на мертвому — для мертвих є вікно смерті")
	# Підводимо тим самим шляхом, що й гра, — кнопкою вікна смерті.
	combat.revive(1)
	hero.skill_ready_in.clear()
	combat.cast(1, KEY)
	while hero.is_casting():
		combat.tick_casts(0.05)
	var again: bool = combat.cast(1, KEY)
	print("  одразу вдруге: %s (має бути false — відкат)" % again)
	if again:
		_fail("відкат не тримає: скіл можна крутити без упину")

	print("\n— підсумок —")
	if _bad == 0:
		print("  ✓ скіл вертає в місто з будь-якої дірки й садить на землю")
	else:
		print("  ‼ зауважень: %d" % _bad)
	get_tree().quit(1 if _bad else 0)
