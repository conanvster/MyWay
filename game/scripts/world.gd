extends Node3D
## Світ.
##
## На сервері живуть справжні персонажі; клієнт отримує їхні позиції й
## малює. Розсилка АДРЕСНА — окреме повідомлення на кожне з'єднання,
## а не широкомовне. Так зроблено навмисно: на кроці 5 сервер має слати
## кожному лише те, що той бачить (П-43). Готові вузли Godot для
## синхронізації розсилають усім однаково і для цього не годяться.

const AVATAR := preload("res://scenes/avatar.tscn")
## Скільки разів на секунду сервер розсилає позиції.
const TICK_HZ := 20.0
## Наскільки швидко клієнт підтягує чужі капсули до надісланої позиції.
## Це згладжування картинки, а не передбачення руху (П-55).
const SMOOTHING := 14.0

var avatars: Dictionary = {}
var _since_tick := 0.0


func _ready() -> void:
	if Net.is_server:
		multiplayer.peer_disconnected.connect(_on_left)
		print("[світ] сервер чекає гравців")
	else:
		# Спавн просимо самі, коли сцена вже здатна приймати виклики.
		# Якби сервер спавнив за подією з'єднання, повідомлення могло б
		# прийти раніше, ніж клієнт готовий, і загубитись.
		multiplayer.connected_to_server.connect(
				func() -> void: rpc_id(1, "announce_ready"))


# ── сервер ────────────────────────────────────────────────────────────

@rpc("any_peer", "call_remote", "reliable")
func announce_ready() -> void:
	if not Net.is_server:
		return
	_on_joined(multiplayer.get_remote_sender_id())


func _on_joined(id: int) -> void:
	# Спершу новачкові — усіх наявних, тоді всім — новачка.
	for other in avatars:
		rpc_id(id, "client_spawn", other, avatars[other].global_position)
	var a := _spawn(id, Vector3(0, 1.5, 0))
	rpc("client_spawn", id, a.global_position)
	print("[світ] приєднався %d, усього %d" % [id, avatars.size()])


func _on_left(id: int) -> void:
	if avatars.has(id):
		avatars[id].queue_free()
		avatars.erase(id)
	rpc("client_despawn", id)
	print("[світ] пішов %d, лишилось %d" % [id, avatars.size()])


func _physics_process(delta: float) -> void:
	if Net.is_server:
		for a in avatars.values():
			a.server_step(delta)
		return

	var me: Node = avatars.get(multiplayer.get_unique_id())
	if me != null and me.is_local:
		rpc_id(1, "submit_intent", me.sample_intent())


func _process(delta: float) -> void:
	if not Net.is_server:
		_smooth(delta)
		return

	_since_tick += delta
	if _since_tick < 1.0 / TICK_HZ:
		return
	_since_tick = 0.0

	var snapshot := {}
	for id in avatars:
		snapshot[id] = avatars[id].global_position
	# Кожному окремо: тут на кроці 5 з'явиться відбір за зоною бачення.
	for peer in multiplayer.get_peers():
		rpc_id(peer, "client_positions", snapshot)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func submit_intent(intent: Vector2) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if avatars.has(id):
		avatars[id].wanted = intent


# ── клієнт ────────────────────────────────────────────────────────────

func _smooth(delta: float) -> void:
	var k := 1.0 - exp(-SMOOTHING * delta)
	for id in avatars:
		var a: Node3D = avatars[id]
		a.global_position = a.global_position.lerp(a.server_position, k)


@rpc("authority", "call_remote", "reliable")
func client_spawn(id: int, pos: Vector3) -> void:
	if avatars.has(id):
		return
	var a := _spawn(id, pos)
	if id == multiplayer.get_unique_id():
		a.become_local()


@rpc("authority", "call_remote", "reliable")
func client_despawn(id: int) -> void:
	if avatars.has(id):
		avatars[id].queue_free()
		avatars.erase(id)


@rpc("authority", "call_remote", "unreliable_ordered")
func client_positions(snapshot: Dictionary) -> void:
	for id in snapshot:
		if avatars.has(id):
			avatars[id].server_position = snapshot[id]


# ── спільне ───────────────────────────────────────────────────────────

func _spawn(id: int, pos: Vector3) -> Node3D:
	var a := AVATAR.instantiate()
	a.name = "Avatar%d" % id
	add_child(a)
	a.global_position = pos
	a.server_position = pos
	avatars[id] = a
	return a
