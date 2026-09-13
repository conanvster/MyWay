extends Node
## Рух під час читання скіла (П-200) — числами, без світу й мережі.
##
##     godot --headless --path game res://scenes/cast_move.tscn
##
## Слово замовника 13.09.2026: читання «повинно або сповільнювати
## кастуючого, або повністю зупиняти», залежно від скіла, і для всіх.
## Міряємо на монстрі (гравець ходить тим самим `server_step`): скільки
## проходить за секунду без читання, читаючи стійку (0,5) і читаючи
## повернення в місто (0). Касти — справжнім `combat.cast`.

const MOB := preload("res://scenes/mob.tscn")
const SECONDS := 1.0

var _ok := 0
var _bad := 0


func _ready() -> void:
	_go()


func _yes(text: String, is_ok: bool) -> void:
	if is_ok:
		_ok += 1
		print("  ✓ %s" % text)
	else:
		_bad += 1
		print("  ✗ %s" % text)


func _walk(m: Node3D, seconds: float) -> float:
	var from := m.global_position
	for f in roundi(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame
		m.wanted = Vector2(1, 0)
		m.server_step(1.0 / Engine.physics_ticks_per_second)
	return Vector2(m.global_position.x - from.x,
			m.global_position.z - from.z).length()


func _go() -> void:
	await get_tree().process_frame
	var data := GameData.new()
	data.load_all()

	print("\n— рух при читанні: дані —")
	var slow := 0
	var still := 0
	for key: String in data.skills.keys():
		var share: float = data.skills.get_skill(key).move_while_casting
		if share > 0.0:
			slow += 1
		else:
			still += 1
	_yes("жоден скіл не лишає повної швидкості (сповільнює %d, зупиняє %d)"
			% [slow, still], slow + still == data.skills.count())
	_yes("стійка щита — на ходу, 0,5",
			is_equal_approx(data.skills.get_skill("стійка-щита")
			.move_while_casting, 0.5))
	_yes("енергетичний промінь — стоячи, 0",
			data.skills.get_skill("енергетичний-промінь")
			.move_while_casting == 0.0)

	var floor_body := StaticBody3D.new()
	var plate := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	plate.shape = box
	plate.position = Vector3(0, -0.5, 0)
	floor_body.add_child(plate)
	add_child(floor_body)

	var m: Node3D = MOB.instantiate()
	add_child(m)
	m.global_position = Vector3(0, 0.5, 0)
	m.setup(m.global_position, 2, false, data.for_kind(2))
	m.mp = 999
	for f in 30:
		await get_tree().physics_frame
		m.wanted = Vector2.ZERO
		m.server_step(1.0 / Engine.physics_ticks_per_second)

	var combat := Combat.new({-1: m}, Messenger.new())
	combat.skills = data.skills
	m.learn("стійка-щита", 1)
	m.learn("повернення-в-місто", 1)

	print("\n— рух при читанні: заміри за %.0f с —" % SECONDS)
	var free_walk: float = await _walk(m, SECONDS)
	_yes("без читання йде: %.2f м" % free_walk, free_walk > 0.5)

	var began := combat.cast(-1, "стійка-щита")
	_yes("стійка щита читається (%s, %.1f с)" % [began, m.casting_left],
			began and m.is_casting())
	m.casting_left = 99.0
	var half: float = await _walk(m, SECONDS)
	_yes("читаючи стійку — удвічі повільніше: %.2f м (очікую ~%.2f)"
			% [half, free_walk * 0.5],
			absf(half - free_walk * 0.5) < free_walk * 0.1)
	m.stop_cast()

	m.skill_ready_in.clear()
	began = combat.cast(-1, "повернення-в-місто")
	_yes("повернення в місто читається (%s)" % began,
			began and m.is_casting())
	m.casting_left = 99.0
	var stood: float = await _walk(m, SECONDS * 1.5)
	_yes("читаючи повернення — стоїть: %.3f м за %.1f с"
			% [stood, SECONDS * 1.5], stood < 0.02)
	m.stop_cast()

	var again: float = await _walk(m, SECONDS)
	_yes("дочитав — знову йде на повну: %.2f м" % again,
			absf(again - free_walk) < free_walk * 0.1)

	print("\n  пройдено %d · провалено %d" % [_ok, _bad])
	get_tree().quit(1 if _bad > 0 else 0)
