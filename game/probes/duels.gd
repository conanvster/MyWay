extends SceneTree
## Проба Р-5: виклик і арена (П-259, П-260, П-74).
##
##     godot --headless --path game --script res://probes/duels.gd
##
## Справжні `Combat.attack` і `Duels`: виклик, арена (підлога тримає),
## бій без флагу й без утрати речей, переможець, повернення, нічия за
## часом, вихід із гри посеред бою.

const AVATAR := preload("res://scenes/avatar.tscn")
const FIELD := Vector3(100, 1, 100)
const STEP := 1.0 / 60.0

var _bad := 0
var _creatures := {}
var _combat: Combat
var _outlaws: Outlaws
var _duels: Duels
var _data: GameData


func _init() -> void:
	call_deferred("_go")


func _expect(what: String, ok: bool) -> void:
	if not ok:
		_bad += 1
	print("  %s %s" % ["✓" if ok else "✗", what])


func _go() -> void:
	await process_frame
	GameData.chosen_map = GameData.MAP2_PATH
	_data = GameData.new()
	_data.load_all()
	var wardens := Wardens.new(_creatures)
	wardens.setup(_data.map)
	_combat = Combat.new(_creatures)
	_combat.progress = Progress.new(_data.levels)
	_combat.goods = _data.items
	_combat.skills = _data.skills
	_outlaws = Outlaws.new(_creatures)
	_outlaws.in_town = wardens.in_town
	_combat.outlaws = _outlaws
	_duels = Duels.new()
	root.add_child(_duels)
	_combat.agreed_pvp = _duels.agreed

	var a: Node3D = await _hero(1, FIELD)
	var b: Node3D = await _hero(2, FIELD + Vector3(1.5, 0, 0))
	var c: Node3D = await _hero(3, FIELD + Vector3(30, 0, 0))

	print("\n— виклик —")
	_expect("далеко — не можна (%s)" % _duels.invite(1, 3, a, c),
			_duels.invite(1, 3, a, c) != "")
	_expect("монстра не кличуть", _duels.invite(1, -5, a, b) != "")
	_expect("поруч — виклик пішов", _duels.invite(1, 2, a, b) == "")
	_expect("кличе 1", _duels.invited_by(2) == 1)
	_expect("ще ніхто не на арені", not _duels.agreed(1, 2))

	print("\n— згода → арена —")
	var from_a: Vector3 = a.global_position
	var from_b: Vector3 = b.global_position
	var res: Dictionary = _duels.accept(2, a, b)
	_expect("місце 0 (%s)" % [res], res.get("місце", -1) == 0)
	var slot: int = res["місце"]
	_duels.raise(slot)
	a.place_at(Duels.start_point(slot, 0), 0.0)
	b.place_at(Duels.start_point(slot, 1), 0.0)
	for i in 90:
		await physics_frame
		a.server_step(STEP)
		b.server_step(STEP)
	print("    1 стоїть на %s, 2 — на %s" % [a.global_position,
			b.global_position])
	_expect("підлога тримає: висота ≈ %.0f (%.2f)"
			% [Duels.ORIGIN.y, a.global_position.y],
			absf(a.global_position.y - Duels.ORIGIN.y) < 1.5)
	_expect("обидва на тій самій арені",
			Duels.slot_at(a.global_position.x, a.global_position.z) == slot
			and Duels.slot_at(b.global_position.x,
					b.global_position.z) == slot)
	_expect("поза ареною підлоги немає",
			is_nan(_duels.floor_at(FIELD.x, FIELD.z)))
	_expect("погоджений бій", _duels.agreed(1, 2) and _duels.agreed(2, 1))
	_expect("третій сюди не стосується", not _duels.agreed(1, 3))
	_expect("на арені вже — другий виклик не можна",
			_duels.invite(1, 3, a, c) != "")

	print("\n— бій на арені: без флагу, без утрати речей —")
	b.place_at(a.global_position + Vector3(1.5, 0, 0), 0.0)
	var hp: int = b.hp
	_expect("удар пройшов", _strike(1, 2) and b.hp < hp)
	_expect("ніхто не флагнутий", not _outlaws.flagged(1)
			and not _outlaws.flagged(2))
	b.items = {"кора дуба": 200}
	b.respect = 500
	var respect_before: int = b.respect
	b.hp = 1
	_strike(1, 2)
	_expect("2 загинув", not b.is_alive())
	var winner := _duels.on_death(2)
	_expect("переможець — 1", winner == 1)
	_expect("речі не впали (%d з 200)" % int(b.items.get("кора дуба", 0)),
			int(b.items.get("кора дуба", 0)) == 200)
	_expect("1 не позначений", _outlaws.kills_of(a) == 0)
	_expect("повага 2 не знялась (%d → %d, П-260)"
			% [respect_before, b.respect], b.respect == respect_before)
	_expect("бій скінчено — далі вже не погоджений", not _duels.agreed(1, 2))

	print("\n— повернення за %.0f с —" % Duels.RETURN_AFTER)
	var back: Dictionary = _duels.tick(Duels.RETURN_AFTER - 0.5)
	_expect("ще рано", back["назад"].is_empty())
	back = _duels.tick(1.0)
	var spots := {}
	for row: Array in back["назад"]:
		spots[int(row[0])] = row[1]
	_expect("обох назад, кожного на своє місце",
			spots.get(1) == from_a and spots.get(2) == from_b)
	_expect("арену звільнено", not _duels.in_duel(1)
			and not _duels.in_duel(2))

	print("\n— мовчання — виклик згасає (П-74) —")
	await _revive(b)
	# Щойно бились — «у бою»; виклик, як і обмін, у бою не йде.
	_expect("одразу після бою не кличуть (%s)" % _duels.invite(1, 2, a, b),
			_duels.invited_by(2) == 0)
	a.in_fight = 0.0
	b.in_fight = 0.0
	a.place_at(FIELD, 0.0)
	b.place_at(FIELD + Vector3(1.5, 0, 0), 0.0)
	_duels.invite(1, 2, a, b)
	var gone: Dictionary = _duels.tick(Duels.INVITE_TIME + 0.1)
	_expect("згас за %.0f с: %s" % [Duels.INVITE_TIME, gone["прострочені"]],
			gone["прострочені"] == [[1, 2]] and _duels.invited_by(2) == 0)
	_expect("згода на згаслий — відмова",
			_duels.accept(2, a, b).has("чому"))

	print("\n— час бою вийшов — нічия —")
	_duels.invite(2, 1, b, a)
	_duels.accept(1, b, a)
	_expect("ще йде", _duels.agreed(1, 2))
	var draw: Dictionary = _duels.tick(Duels.FIGHT_TIME + 0.1)
	_expect("нічия: %s" % [draw["нічия"]], draw["нічия"] == [[2, 1]])
	_expect("після нічиєї — не погоджений", not _duels.agreed(1, 2))
	draw = _duels.tick(Duels.RETURN_AFTER + 0.1)
	_expect("і обох назад", draw["назад"].size() == 2)

	print("\n— вийшов із гри посеред бою —")
	_duels.invite(1, 2, a, b)
	res = _duels.accept(2, a, b)
	var left: Variant = _duels.forget(2)
	_expect("того, хто вийшов, — на місце виклику ДО збереження",
			left is Vector3 and left == b.global_position)
	_expect("бій скінчено", not _duels.agreed(1, 2))
	var after: Dictionary = _duels.tick(Duels.RETURN_AFTER + 0.1)
	_expect("того, хто лишився, — назад", after["назад"].size() == 1
			and int(after["назад"][0][0]) == 1)

	print("\n— два бої одночасно — різні арени —")
	var d: Node3D = await _hero(4, FIELD + Vector3(30, 0, 1.5))
	_duels.invite(1, 2, a, b)
	var first: Dictionary = _duels.accept(2, a, b)
	_duels.invite(3, 4, c, d)
	var second: Dictionary = _duels.accept(4, c, d)
	_expect("місця %s і %s" % [first.get("місце"), second.get("місце")],
			first.get("місце") != second.get("місце"))
	_expect("між аренами не б'ються", not _duels.agreed(1, 3))

	print("\nпомилок: %d" % _bad)
	quit(1 if _bad > 0 else 0)


func _hero(id: int, at: Vector3) -> Node3D:
	var h: Node3D = AVATAR.instantiate()
	root.add_child(h)
	await process_frame
	h.place_at(at, 0.0)
	_creatures[id] = h
	return h


func _revive(h: Node3D) -> void:
	h.hp = h.stats.max_hp()
	h.corpse_left = 0.0
	h.server_step(0.016)
	await process_frame


func _strike(me: int, victim: int) -> bool:
	var a: Node = _creatures[me]
	a.target_id = victim
	a.attack_ready_in = 0.0
	return _combat.attack(me)
