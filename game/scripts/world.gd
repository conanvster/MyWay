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
## Кого кожне з'єднання зараз бачить: peer_id -> { чужий_id: true }.
## Сервер веде це сам, бо саме звідси береться, кому що надсилати (П-43).
var _seen: Dictionary = {}
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
	var a := _spawn(id, Vector3(0, 1.5, 0))
	# Себе гравець бачить завжди; решту роздасть звірка зон бачення.
	rpc_id(id, "client_spawn", id, a.global_position)
	rpc_id(id, "client_vision", a.VISION_RADIUS)
	_seen[id] = {id: true}
	print("[світ] приєднався %d, усього %d" % [id, avatars.size()])


func _on_left(id: int) -> void:
	if avatars.has(id):
		avatars[id].queue_free()
		avatars.erase(id)
	_seen.erase(id)
	for peer in _seen:
		if _seen[peer].erase(id):
			rpc_id(peer, "client_despawn", id)
	print("[світ] пішов %d, лишилось %d" % [id, avatars.size()])


func _physics_process(delta: float) -> void:
	if Net.is_server:
		for a in avatars.values():
			a.server_step(delta)
		for id in avatars:
			_pump(id)
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

	for peer in multiplayer.get_peers():
		_serve(peer)


## Що бачить одне з'єднання. Поява й зникнення йдуть надійним каналом,
## позиції — ненадійним: загублений пакет позицій це смикання на кадр,
## а загублена поява це вічний привид.
func _serve(peer: int) -> void:
	var watcher: Node3D = avatars.get(peer)
	if watcher == null:
		return
	var seen: Dictionary = _seen.get(peer, {})
	var near: float = watcher.VISION_RADIUS
	var far: float = near * watcher.VISION_HYSTERESIS

	var snapshot := {}
	for id in avatars:
		var other: Node3D = avatars[id]
		var dist := watcher.global_position.distance_to(other.global_position)
		# Поріг залежить від того, чи бачили досі: інакше на самій межі
		# персонаж блимав би щокадру.
		var visible: bool = dist <= (far if seen.has(id) else near)
		if id == peer:
			visible = true

		if visible:
			if not seen.has(id):
				seen[id] = true
				rpc_id(peer, "client_spawn", id, other.global_position)
			snapshot[id] = other.global_position
		elif seen.has(id):
			seen.erase(id)
			rpc_id(peer, "client_despawn", id)

	_seen[peer] = seen
	rpc_id(peer, "client_positions", snapshot)


# ── бій ───────────────────────────────────────────────────────────────

## Взяти ціль мишею. Клієнт лише каже, у кого влучив променем; чи має
## він право її бачити, вирішує сервер.
@rpc("any_peer", "call_remote", "reliable")
func select_target(id: int) -> void:
	if not Net.is_server:
		return
	var me := multiplayer.get_remote_sender_id()
	if not avatars.has(me):
		return
	if id != 0 and not _seen.get(me, {}).has(id):
		return  # цілі, якої не бачить, гравець узяти не може
	avatars[me].target_id = id
	rpc_id(me, "client_target", id)


## Удар мишею — не через панель, щоб не залежати від її розкладки.
@rpc("any_peer", "call_remote", "reliable")
func strike() -> void:
	if Net.is_server:
		_enqueue(multiplayer.get_remote_sender_id(), "attack")


## Натиснута комірка панелі.
@rpc("any_peer", "call_remote", "reliable")
func use_slot(slot: int) -> void:
	if not Net.is_server:
		return
	var me := multiplayer.get_remote_sender_id()
	var a: Node = avatars.get(me)
	if a == null or slot < 0 or slot >= a.BAR.size():
		return
	var action: String = a.BAR[slot]
	if action != "":
		_enqueue(me, action)


## Натискання стає в чергу. Переповнену чергу зайве натискання не
## розпихає — воно просто гине (П-38).
func _enqueue(me: int, action: String) -> void:
	var a: Node = avatars.get(me)
	if a == null:
		return
	if a.queue.size() >= a.QUEUE_MAX:
		return
	a.queue.append(action)


## Розбір черги. Викликається, коли персонаж вільний.
##
## Дія, яку зараз виконати не можна, ВИКИДАЄТЬСЯ і черга йде далі — не
## чекає (П-38). Тому за довгого відкату друге поспіль те саме вміння
## пропадає, а те, що стоїть за ним, спрацьовує одразу.
func _pump(me: int) -> void:
	var a: Node = avatars[me]
	while a.busy_in <= 0.0 and not a.queue.is_empty():
		var action: String = a.queue.pop_front()
		match action:
			"attack":
				if _attack(me):
					a.busy_in = a.SWING_TIME
			"next_player":
				_cycle_target(me)
			"next_mob":
				pass  # монстри з'являться на кроці 9


## Повертає true, якщо удар справді відбувся.
func _attack(me: int) -> bool:
	if not avatars.has(me):
		return false
	var a: Node = avatars[me]
	if a.attack_ready_in > 0.0:
		return false  # відкат не минув — дія викидається (П-35, П-38)
	var victim: Node = avatars.get(a.target_id)
	if victim == null:
		rpc_id(me, "client_notice", "немає цілі")
		return false
	if not victim.is_alive():
		rpc_id(me, "client_notice", "неможливо застосувати на даному типі цілі")
		return false
	var dist: float = a.global_position.distance_to(victim.global_position)
	if dist > a.ATTACK_RANGE:
		rpc_id(me, "client_notice", "задалеко")
		return false

	a.attack_ready_in = a.ATTACK_COOLDOWN
	victim.hp = maxi(0, victim.hp - a.ATTACK_DAMAGE)
	# Про зміну здоров'я знають лише ті, хто бачить постраждалого.
	for peer in _seen:
		if _seen[peer].has(a.target_id):
			rpc_id(peer, "client_hp", a.target_id, victim.hp)
	print("[бій] %d вдарив %d, лишилось %d" % [me, a.target_id, victim.hp])
	return true


## «Наступний гравець»: перебирає видимих за віддаленістю, по колу.
func _cycle_target(me: int) -> void:
	var a: Node = avatars[me]
	var seen: Dictionary = _seen.get(me, {})
	var list: Array = []
	for id in seen:
		if id != me and avatars.has(id) and avatars[id].is_alive():
			list.append(id)
	if list.is_empty():
		avatars[me].target_id = 0
		rpc_id(me, "client_target", 0)
		return
	list.sort_custom(func(x, y):
			return a.global_position.distance_to(avatars[x].global_position) \
					< a.global_position.distance_to(avatars[y].global_position))
	var at := list.find(a.target_id)
	var next: int = list[(at + 1) % list.size()] if at != -1 else list[0]
	avatars[me].target_id = next
	rpc_id(me, "client_target", next)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func submit_intent(intent: Vector2) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if avatars.has(id):
		avatars[id].wanted = intent


# ── клієнт: ввід ──────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if Net.is_server:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var slot := _slot_of(event.keycode)
		if slot != -1:
			rpc_id(1, "use_slot", slot)
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_click_at(event.position)


func _slot_of(code: int) -> int:
	if code >= KEY_1 and code <= KEY_7:
		return code - KEY_1
	return -1


## Перший клік по цілі бере її, наступні по вже вибраній — б'ють (П-20).
func _click_at(where: Vector2) -> void:
	var me: Node = avatars.get(multiplayer.get_unique_id())
	if me == null:
		return
	var cam: Camera3D = me.get_node("CameraRig/Camera3D")
	var from := cam.project_ray_origin(where)
	var query := PhysicsRayQueryParameters3D.create(
			from, from + cam.project_ray_normal(where) * 200.0)
	query.collision_mask = 2  # шар «істоти»
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var id := _id_of(hit["collider"])
	if id == 0:
		return
	if me.target_id == id:
		rpc_id(1, "strike")
	else:
		rpc_id(1, "select_target", id)


func _id_of(node: Object) -> int:
	for id in avatars:
		if avatars[id] == node:
			return id
	return 0


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


## Скільки бачить мій персонаж. Камері це потрібно, щоб не відмотуватись
## далі за зону бачення (П-47).
@rpc("authority", "call_remote", "reliable")
func client_vision(radius: float) -> void:
	var me: Node = avatars.get(multiplayer.get_unique_id())
	if me != null:
		me.get_node("CameraRig").vision_radius = radius


@rpc("authority", "call_remote", "reliable")
func client_target(id: int) -> void:
	var me: Node = avatars.get(multiplayer.get_unique_id())
	if me != null:
		me.target_id = id


@rpc("authority", "call_remote", "reliable")
func client_hp(id: int, hp: int) -> void:
	if avatars.has(id):
		avatars[id].hp = hp


@rpc("authority", "call_remote", "reliable")
func client_notice(text: String) -> void:
	print("[гра] ", text)


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
