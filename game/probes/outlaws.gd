extends SceneTree
## Проба Р-7: флаг і позначка вбивці (П-26/П-64, П-84/П-87/П-88, П-261).
##
##     godot --headless --path game --script res://probes/outlaws.gd
##
## Справжній `Combat.attack` між двома аватарами, світ 1: місто Стільна
## в (0, 0) радіусом 26, поле — за 100 м від нього.

const AVATAR := preload("res://scenes/avatar.tscn")
const FIELD := Vector3(100, 1, 100)

var _bad := 0
var _creatures := {}
var _combat: Combat
var _outlaws: Outlaws
var _data: GameData


func _init() -> void:
	call_deferred("_go")


func _expect(what: String, ok: bool) -> void:
	if not ok:
		_bad += 1
	print("  %s %s" % ["✓" if ok else "✗", what])


func _go() -> void:
	await process_frame
	GameData.chosen_map = GameData.MAP_PATH
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
	var changed: Array = []
	_outlaws.on_changed = func(id: int, kills: int) -> void:
		changed.append([id, kills])

	var a: Node3D = await _hero(1, FIELD)
	var b: Node3D = await _hero(2, FIELD + Vector3(1.5, 0, 0))
	var c: Node3D = await _hero(3, FIELD + Vector3(-1.5, 0, 0))

	print("\n— П-88: у місті удар по гравцю не діє —")
	_expect("центр Стільної — місто, поле — ні, село світу 2 — ні",
			wardens.in_town(Vector3(0, 0, 0))
			and not wardens.in_town(FIELD))
	a.place_at(Vector3(2, 1, 0), 0.0)
	b.place_at(Vector3(3.5, 1, 0), 0.0)
	var hp: int = b.hp
	_expect("удар у місті не пройшов", not _strike(1, 2) and b.hp == hp)
	_expect("і не флагнув", not _outlaws.flagged(1))
	a.place_at(FIELD, 0.0)
	b.place_at(FIELD + Vector3(1.5, 0, 0), 0.0)

	print("\n— відповів ударом → обидва в PvP, позначки немає —")
	_expect("1 б'є 2 — пройшло", _strike(1, 2) and b.hp < hp)
	_expect("1 флагнутий, 2 — ні", _outlaws.flagged(1)
			and not _outlaws.flagged(2))
	_strike(2, 1)
	b.hp = 1
	_strike(1, 2)
	_expect("2 загинув", not b.is_alive())
	_expect("1 не позначений (жертва відповіла)", _outlaws.kills_of(a) == 0)

	print("\n— не відповів → нападник позначений —")
	await _revive(b)
	c.hp = 1
	_strike(1, 3)
	_expect("3 загинув з першого удару", not c.is_alive())
	_expect("1 позначений: 1 вбивство", _outlaws.kills_of(a) == 1)
	_expect("розіслано колір: %s" % [changed], changed == [[1, 1]])
	_expect("колір імені 1 вбивства — ледь рожевий, 10 — червоний",
			Outlaws.name_color(1).g < 1.0 and Outlaws.name_color(1).g > 0.8
			and is_equal_approx(Outlaws.name_color(10).g, 0.15))

	print("\n— убитий у відповідь нападника не позначає жертву —")
	await _revive(c)
	_strike(1, 3)
	a.hp = 1
	_strike(3, 1)
	_expect("1 загинув від 3", not a.is_alive())
	_expect("3 не позначений — це відповідь", _outlaws.kills_of(c) == 0)
	await _revive(a)

	print("\n— П-261: позначений губить більше —")
	a.outlaw = {"вбивств": 2, "згасає за": 100.0}
	_expect("2 вбивства → ×1,21 (%.3f)" % _outlaws.loss_multiplier(a),
			is_equal_approx(_outlaws.loss_multiplier(a), 1.21))
	var plain := _average_loss(1.0)
	var marked := _average_loss(_outlaws.loss_multiplier(a))
	print("    у середньому з 200 речей падає %.1f, у позначеного (×1,21) %.1f"
			% [plain, marked])
	_expect("співвідношення ≈ 1,21 (%.2f)" % (marked / plain),
			absf(marked / plain - 1.21) < 0.08)

	print("\n— згасання —")
	a.outlaw = {"вбивств": 2, "згасає за": 10.0}
	a.level = 20
	_outlaws.monster_killed(a, 19)
	_expect("монстр нижчого рівня не пришвидшує",
			is_equal_approx(a.outlaw["згасає за"], 10.0))
	_outlaws.monster_killed(a, 20)
	_expect("свого рівня — мінус %.0f с" % Outlaws.MONSTER_SPEEDUP,
			is_equal_approx(a.outlaw["згасає за"], 10.0
					- Outlaws.MONSTER_SPEEDUP))
	changed.clear()
	_outlaws.tick(0.1)
	_expect("строк минув — 2 → 1 (%s)" % [a.outlaw],
			_outlaws.kills_of(a) == 1 and changed == [[1, 1]])
	_outlaws.tick(Outlaws.DECAY_TIME)
	_expect("ще за строк — чистий", a.outlaw.is_empty()
			and changed.back() == [1, 0])

	print("\n— пара гасне за %.0f с —" % Outlaws.FLAG_TIME)
	c.place_at(b.global_position + Vector3(0, 0, 1.5), 0.0)
	_strike(2, 3)
	_expect("2 флагнутий", _outlaws.flagged(2))
	_outlaws.tick(Outlaws.FLAG_TIME + 0.1)
	_expect("згасло", not _outlaws.flagged(2))

	print("\n— збереження —")
	a.outlaw = {"вбивств": 3, "згасає за": 42.0}
	var row := Store.row_of("Проба", a)
	var fresh: Node3D = await _hero(9, FIELD)
	Store.apply_row(fresh, row, _data.items)
	_expect("позначка пережила перезахід (%s)" % [fresh.outlaw],
			_outlaws.kills_of(fresh) == 3
			and is_equal_approx(fresh.outlaw["згасає за"], 42.0))

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


## Удар без відкату й черги — сам `Combat.attack`.
func _strike(me: int, victim: int) -> bool:
	var a: Node = _creatures[me]
	a.target_id = victim
	a.attack_ready_in = 0.0
	return _combat.attack(me)


## Скільки речей у середньому падає з 200 однакових ресурсів.
func _average_loss(more: float) -> float:
	var total := 0
	var dummy: Node3D = AVATAR.instantiate()
	root.add_child(dummy)
	for i in 50:
		dummy.items = {"кора дуба": 200}
		_combat.progress.lose_items(dummy, _data.items, null, more)
		total += 200 - int(dummy.items.get("кора дуба", 0))
	dummy.queue_free()
	return total / 50.0
