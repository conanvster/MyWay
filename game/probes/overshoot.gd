extends Node
## Під великим бафом на швидкість гравець не проскакує точку й не
## повертається стрибком (слово замовника 11.10.2026).
##
##     godot --headless --path game res://scenes/overshoot.tscn
##
## Сервер підставний, але чесний: везе за наміром клієнта, шле знімок
## раз на 0,05 с (20 Гц), а клієнт згладжує, як `ClientView.smooth`.
## Міряється, на скільки серверна позиція проскочила точку й чи
## розвертався рух назад.

const AVATAR := preload("res://scenes/avatar.tscn")
var _bad := 0


func _ready() -> void:
	_go()


func _expect(what: String, ok: bool, got: String) -> void:
	if not ok:
		_bad += 1
	print("  %s %s: %s" % ["✓" if ok else "✗", what, got])


func _go() -> void:
	Net.joined = true
	await get_tree().process_frame
	var a: Node = AVATAR.instantiate()
	get_tree().root.add_child(a)
	a.set_physics_process(false)
	await get_tree().process_frame
	for row: Array in [[5.0, 4.0], [15.0, 4.0], [25.0, 3.0]]:
		await _walk(a, row[0], row[1])
	a.queue_free()

	print("\n— рефлекс «крок назад» (П-163) під бафом —")
	var plain := await _push_wall(1.0)
	var fast := await _push_wall(3.0)
	_expect("без бафа відступ", plain > 0.5, "%.2f м" % plain)
	_expect("з бафом ×3 — не далі, ніж без", fast <= plain + 0.3,
			"%.2f м (без бафа %.2f)" % [fast, plain])
	print("\nпомилок: %d" % _bad)
	get_tree().quit(1 if _bad > 0 else 0)


## Тиснути в стіну 2 с на сервері; скільки найдалі відступив від неї.
func _push_wall(buff: float) -> float:
	var room := Node3D.new()
	get_tree().root.add_child(room)
	for box: Array in [[Vector3(20, 1, 20), Vector3(0, -0.5, 0)],
			[Vector3(6, 4, 1), Vector3(0, 2, -3)]]:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var cube := BoxShape3D.new()
		cube.size = box[0]
		shape.shape = cube
		body.add_child(shape)
		body.position = box[1]
		room.add_child(body)
	var a: Node = AVATAR.instantiate()
	room.add_child(a)
	a.set_physics_process(false)
	a.place_at(Vector3(0, 1.0, 0), 0.0)
	if buff != 1.0:
		a.add_state(State.new("швидкість", "move_speed", buff, 60.0))
	for i in 20:
		await get_tree().physics_frame
		a.server_step(get_physics_process_delta_time())
	a.wanted = Vector2(0, -1)
	var closest := 99.0
	var back := 0.0
	for i in 120:
		await get_tree().physics_frame
		a.server_step(get_physics_process_delta_time())
		var z: float = a.global_position.z
		closest = minf(closest, z)
		back = maxf(back, z - closest)
	print("    ×%.0f: найближче z %.2f, відступ %.2f" % [buff, closest, back])
	room.queue_free()
	await get_tree().process_frame
	return back


## Пройти `span` метрів уперед на швидкості `speed`.
func _walk(a: Node, speed: float, span: float) -> void:
	var server := Vector3.ZERO
	a.place_at(Vector3.ZERO, 0.0)
	a.server_position = Vector3.ZERO
	a.server_speed = 0.0
	a._seen_time = 0.0
	a.walk_to = Vector3(0, 0, -span)
	var since_shot := 0.0
	var intent := Vector2.ZERO
	var most := 0.0
	var back := false
	for i in 150:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		# Сервер везе за наміром, що прийшов кадр тому.
		var step := Vector3(intent.x, 0, intent.y) * speed * dt
		if step.z > 0.001:
			back = true
		server += step
		since_shot += dt
		if since_shot >= 0.05:
			since_shot = 0.0
			a.server_position = server
		a.global_position = a.global_position.lerp(a.server_position,
				1.0 - exp(-ClientView.SMOOTHING * dt))
		intent = a.sample_intent()
		most = maxf(most, -server.z - span)
	_expect("%.0f м/с: проскочив точку не більше ніж на 1 м" % speed,
			most <= 1.0, "%.2f м" % most)
	_expect("%.0f м/с: назад не розвертався" % speed, not back,
			"назад" if back else "ні")
