extends Node3D
## Світ.
##
## На сервері живуть справжні персонажі; клієнт отримує їхні позиції й
## малює. Розсилка АДРЕСНА — окреме повідомлення на кожне з'єднання,
## а не широкомовне. Так зроблено навмисно: на кроці 5 сервер має слати
## кожному лише те, що той бачить (П-43). Готові вузли Godot для
## синхронізації розсилають усім однаково і для цього не годяться.

const AVATAR := preload("res://scenes/avatar.tscn")
const MOB := preload("res://scenes/mob.tscn")
## Монстри живуть у від'ємних номерах, гравці — у додатних (номер
## з'єднання). Так одна таблиця тримає і тих, і тих.
##
## Кожен рядок — місце появи. Вид визначає, хто кого чує на поміч.
const MOB_SPOTS := [
	{"home": Vector3(8, 1.5, -8), "kind": 1, "aggressive": true},
	{"home": Vector3(11, 1.5, -5), "kind": 1, "aggressive": true},
	{"home": Vector3(-6, 1.5, 10), "kind": 2, "aggressive": false},
]
## Через скільки монстр з'являється знову, і наскільки випадково.
const RESPAWN_AFTER := 12.0
const RESPAWN_SPREAD := 4.0
## Скільки разів на секунду сервер розсилає позиції.
const TICK_HZ := 20.0
## Наскільки швидко клієнт підтягує чужі капсули до надісланої позиції.
## Це згладжування картинки, а не передбачення руху (П-55).
const SMOOTHING := 14.0

var creatures: Dictionary = {}
## Кого кожне з'єднання зараз бачить: peer_id -> { чужий_id: true }.
## Сервер веде це сам, бо саме звідси береться, кому що надсилати (П-43).
var _seen: Dictionary = {}
var _since_tick := 0.0
## Гнізда монстрів: звідки й коли з'являється наступний.
var _slots: Array = []
var _last_mob_id := 0


func _ready() -> void:
	if Net.is_server:
		multiplayer.peer_disconnected.connect(_on_left)
		for i in MOB_SPOTS.size():
			_slots.append({"spot": i, "id": 0, "in": 0.0})
			_respawn(i)
		print("[світ] сервер чекає гравців, монстрів %d" % MOB_SPOTS.size())
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
	rpc_id(id, "client_vision", a.vision_radius())
	_seen[id] = {id: true}
	print("[світ] приєднався %d, усього %d" % [id, creatures.size()])


func _on_left(id: int) -> void:
	if creatures.has(id):
		creatures[id].queue_free()
		creatures.erase(id)
	_seen.erase(id)
	for peer in _seen:
		if _seen[peer].erase(id):
			rpc_id(peer, "client_despawn", id)
	print("[світ] пішов %d, лишилось %d" % [id, creatures.size()])


func _physics_process(delta: float) -> void:
	if Net.is_server:
		for a in creatures.values():
			a.server_step(delta)
		for id in creatures:
			if id < 0:
				_mob_think(id, delta)
			else:
				_pump(id)
		_clear_corpses()
		_tick_respawn(delta)
		return

	var me: Node = creatures.get(multiplayer.get_unique_id())
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
	var watcher: Node3D = creatures.get(peer)
	if watcher == null:
		return
	var seen: Dictionary = _seen.get(peer, {})
	var near: float = watcher.vision_radius()
	var far: float = near * watcher.VISION_HYSTERESIS

	var snapshot := {}
	for id in creatures:
		var other: Node3D = creatures[id]
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
	if not creatures.has(me):
		return
	if id != 0 and not _seen.get(me, {}).has(id):
		return  # цілі, якої не бачить, гравець узяти не може
	creatures[me].target_id = id
	rpc_id(me, "client_target", id)


## Удар мишею — не через панель, щоб не залежати від її розкладки.
@rpc("any_peer", "call_remote", "reliable")
func strike() -> void:
	if Net.is_server:
		_enqueue(multiplayer.get_remote_sender_id(), "attack")


## Натиснута комірка панелі.
## `shift` за П-45 перемикає перебір цілей на трупи.
@rpc("any_peer", "call_remote", "reliable")
func use_slot(slot: int, shift: bool = false) -> void:
	if not Net.is_server:
		return
	var me := multiplayer.get_remote_sender_id()
	var a: Node = creatures.get(me)
	if a == null or slot < 0 or slot >= a.BAR.size():
		return
	var action: String = a.BAR[slot]
	if action == "":
		return
	if shift and action.begins_with("next_"):
		action += "_corpse"
	_enqueue(me, action)


## Натискання стає в чергу. Переповнену чергу зайве натискання не
## розпихає — воно просто гине (П-38).
func _enqueue(me: int, action: String) -> void:
	var a: Node = creatures.get(me)
	if a == null:
		return
	if a.queue.size() >= a.QUEUE_MAX:
		return
	a.queue.append(action)


## Розбір черги.
##
## Правило з П-38 і П-62 разом: шукаємо найпершу дію, готову ЗАРАЗ.
## Усе, що стоїть перед нею на відкаті, викидається — саме тому в
## `скіл1 скіл1 скіл2` другий скіл1 пропадає, а скіл2 спрацьовує.
## Якщо ж готової немає жодної, черга НЕ спорожнюється: голова чекає
## кінця відкату. Інакше п'ять натискань удару давали б один удар.
func _pump(me: int) -> void:
	var a: Node = creatures[me]
	if not a.is_alive():
		a.queue.clear()  # мертвий не діє
		return
	while a.busy_in <= 0.0 and not a.queue.is_empty():
		var at := -1
		for i in a.queue.size():
			if _off_cooldown(a, a.queue[i]):
				at = i
				break
		if at == -1:
			return  # ніхто не готовий — чекаємо, чергу лишаємо цілою
		for i in at:
			a.queue.pop_front()  # застаріле на відкаті викидається
		match a.queue.pop_front():
			"attack":
				if _attack(me):
					a.busy_in = a.stats.swing_time()
			"next_player":
				_cycle_target(me, false, false)
			"next_mob":
				_cycle_target(me, true, false)
			"next_player_corpse":
				_cycle_target(me, false, true)
			"next_mob_corpse":
				_cycle_target(me, true, true)
			"corpse_skill":
				_corpse_skill(me)
			"taunt":
				_taunt(me)


## Трупи, яким вийшов строк, зникають. Монстр просто прибирається;
## гравець піднімається на місці появи — втрати за смерть (П-27) ще не
## зроблені, тож поки це заглушка, див. П-69.
func _clear_corpses() -> void:
	for id in creatures.keys():
		var c: Node = creatures[id]
		if c.is_alive() or c.corpse_left > 0.0:
			continue
		if id < 0:
			_remove(id)
		else:
			# Не оживили за 20 хвилин — підводиться сам, із 30% (П-69, П-70).
			c.hp = maxi(1, roundi(c.stats.max_hp() * c.REVIVE_SHARE))
			c.global_position = Vector3(0, 1.5, 0)
			for peer in _seen:
				if _seen[peer].has(id):
					rpc_id(peer, "client_revive", id, c.hp)


## Монстр з'являється у своєму місці з невеликим розкидом (П-66).
func _respawn(slot: int) -> void:
	var spot: Dictionary = MOB_SPOTS[slot]
	var home: Vector3 = spot["home"]
	var a := randf() * TAU
	var r := randf() * 2.5
	_last_mob_id += 1
	var id := -_last_mob_id
	var m := _spawn(id, home + Vector3(cos(a) * r, 0.0, sin(a) * r))
	m.setup(home, spot["kind"], spot["aggressive"])
	_slots[slot]["id"] = id
	_slots[slot]["in"] = 0.0


func _tick_respawn(delta: float) -> void:
	for slot in _slots:
		if slot["id"] != 0 and creatures.has(slot["id"]):
			continue
		if slot["in"] <= 0.0:
			slot["in"] = RESPAWN_AFTER + randf() * RESPAWN_SPREAD
			slot["id"] = 0
			continue
		slot["in"] -= delta
		if slot["in"] <= 0.0:
			_respawn(_slots.find(slot))


func _remove(id: int) -> void:
	if creatures.has(id):
		creatures[id].queue_free()
		creatures.erase(id)
	for peer in _seen:
		if _seen[peer].erase(id):
			rpc_id(peer, "client_despawn", id)


## Поведінка монстра за П-66.
func _mob_think(id: int, delta: float) -> void:
	var m: Node = creatures[id]
	if not m.is_alive():
		return

	var players := {}
	for other in creatures:
		if other > 0 and creatures[other].is_alive():
			players[other] = creatures[other]

	# Відбіг задалеко від дому — розвертається й геть забуває кривдника.
	if m.too_far_from_home():
		m.forget()
		m.target_id = 0
		m.head_to(m.home, 1.0)
		return

	# Кого ненавидить найбільше; якщо нікого — агресивний виглядає жертву.
	var victim: int = m.top_threat(players)
	if victim == 0:
		victim = m.notice(players, delta)
		if victim != 0:
			m.add_threat(victim, 1.0)

	if victim == 0:
		m.target_id = 0
		m.wander(delta)
		return

	# Уперше завів ціль — гукає своїх (П-66).
	if not m._had_target:
		m._had_target = true
		_call_for_help(id, victim)

	m.target_id = victim
	var target: Node3D = creatures[victim]
	var d: float = m.global_position.distance_to(target.global_position)
	if d > m.ATTACK_RANGE:
		m.head_to(target.global_position, 1.0)
	else:
		m.wanted = Vector2.ZERO
		_attack(id)


## Монстр гукає своїх — тільки того самого виду й тільки поблизу.
func _call_for_help(id: int, victim: int) -> void:
	var m: Node = creatures[id]
	var called := 0
	for other in creatures:
		if other >= 0:
			continue
		var o: Node = creatures[other]
		if o.is_alive() and o.hears(m, m.global_position):
			o.add_threat(victim, 1.0)
			called += 1
	if called > 0:
		print("[монстр] %d покликав своїх: %d" % [id, called])


## Уміння «агресія»: піднімає загрозу так, щоб монстр перемкнувся.
func _taunt(me: int) -> void:
	var a: Node = creatures[me]
	var t: Node = creatures.get(a.target_id)
	if t == null or a.target_id >= 0:
		_notice(me, "неможливо застосувати на даному типі цілі")
		return
	if not t.is_alive():
		_notice(me, "неможливо застосувати на даному типі цілі")
		return
	# Стати вище за найбільшу теперішню загрозу, а не додати трохи.
	var most := 0.0
	for id in t.threat:
		most = maxf(most, t.threat[id])
	t.add_threat(me, most - t.threat.get(me, 0.0) + 20.0)
	print("[монстр] %d перемкнувся на %d" % [a.target_id, me])


## Заглушка замість справжніх умінь по трупах — продовжує строк.
## Заодно показує правило П-42: до живого таке вміння не застосовне.
func _corpse_skill(me: int) -> void:
	var a: Node = creatures[me]
	var t: Node = creatures.get(a.target_id)
	if t == null:
		_notice(me, "немає цілі")
		return
	if not t.is_corpse():
		_notice(me, "неможливо застосувати на даному типі цілі")
		return
	t.extend_corpse()
	print("[труп] %d продовжено до %.0f с" % [a.target_id, t.corpse_left])


## Чи минув відкат саме цієї дії. Інші причини невдачі (немає цілі,
## задалеко) сюди не входять — вони дають повідомлення й викидання.
func _off_cooldown(a: Node, action: String) -> bool:
	if action == "attack":
		return a.attack_ready_in <= 0.0
	return true


## Повідомлення в чат. Монстри не з'єднання, їм слати нікуди.
func _notice(id: int, text: String) -> void:
	if id > 0:
		rpc_id(id, "client_notice", text)


## Повертає true, якщо удар справді відбувся.
func _attack(me: int) -> bool:
	if not creatures.has(me):
		return false
	var a: Node = creatures[me]
	if not a.is_alive():
		return false
	if a.attack_ready_in > 0.0:
		return false  # відкат не минув — дія викидається (П-35, П-38)
	var victim: Node = creatures.get(a.target_id)
	if victim == null:
		_notice(me, "немає цілі")
		return false
	if not victim.is_alive():
		_notice(me, "неможливо застосувати на даному типі цілі")
		return false
	var dist: float = a.global_position.distance_to(victim.global_position)
	if dist > a.ATTACK_RANGE:
		_notice(me, "задалеко")
		return false

	a.attack_ready_in = a.stats.attack_cooldown()
	var hit: int = Stats.damage_through(
			a.stats.physical_attack(), victim.stats.physical_defence())
	victim.hp = maxi(0, victim.hp - hit)
	# Удар по монстру додає загрози: саме за нею він обирає, кого бити.
	if a.target_id < 0 and me > 0:
		victim.add_threat(me, hit + victim.THREAT_PER_HIT)
	# Про зміну здоров'я знають лише ті, хто бачить постраждалого.
	for peer in _seen:
		if _seen[peer].has(a.target_id):
			rpc_id(peer, "client_hp", a.target_id, victim.hp)
	print("[бій] %d вдарив %d, лишилось %d" % [me, a.target_id, victim.hp])
	if victim.hp <= 0:
		victim.die()
		print("[бій] %d загинув, труп лежатиме %.0f с"
				% [a.target_id, victim.corpse_left])
		for peer in _seen:
			if _seen[peer].has(a.target_id):
				rpc_id(peer, "client_died", a.target_id)
	return true


## Перебирає видимі цілі за віддаленістю, по колу. Монстри й гравці —
## окремі дії за П-31, тому й переліки окремі.
func _cycle_target(me: int, mobs: bool, corpses: bool) -> void:
	var a: Node = creatures[me]
	var seen: Dictionary = _seen.get(me, {})
	var list: Array = []
	for id in seen:
		if id == me or not creatures.has(id):
			continue
		var c: Node = creatures[id]
		# Звичайний перебір трупи пропускає: у бою ціль потрібна швидко,
		# і чіплятись за мертвих — найгірше, що може статись (П-45).
		if c.is_corpse() != corpses:
			continue
		if (id < 0) == mobs:
			list.append(id)
	if list.is_empty():
		creatures[me].target_id = 0
		rpc_id(me, "client_target", 0)
		return
	list.sort_custom(func(x, y):
			return a.global_position.distance_to(creatures[x].global_position) \
					< a.global_position.distance_to(creatures[y].global_position))
	var at := list.find(a.target_id)
	var next: int = list[(at + 1) % list.size()] if at != -1 else list[0]
	creatures[me].target_id = next
	rpc_id(me, "client_target", next)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func submit_intent(intent: Vector2) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if creatures.has(id):
		creatures[id].wanted = intent


# ── клієнт: ввід ──────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if Net.is_server:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var slot := _slot_of(event.keycode)
		if slot != -1:
			rpc_id(1, "use_slot", slot, event.shift_pressed)
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_click_at(event.position)


func _slot_of(code: int) -> int:
	if code >= KEY_1 and code <= KEY_7:
		return code - KEY_1
	return -1


## Перший клік по цілі бере її, наступні по вже вибраній — б'ють (П-20).
func _click_at(where: Vector2) -> void:
	var me: Node = creatures.get(multiplayer.get_unique_id())
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
	for id in creatures:
		if creatures[id] == node:
			return id
	return 0


# ── клієнт ────────────────────────────────────────────────────────────

func _smooth(delta: float) -> void:
	var k := 1.0 - exp(-SMOOTHING * delta)
	for id in creatures:
		var a: Node3D = creatures[id]
		a.global_position = a.global_position.lerp(a.server_position, k)


@rpc("authority", "call_remote", "reliable")
func client_spawn(id: int, pos: Vector3) -> void:
	if creatures.has(id):
		return
	var a := _spawn(id, pos)
	if id == multiplayer.get_unique_id():
		a.become_local()


## Скільки бачить мій персонаж. Камері це потрібно, щоб не відмотуватись
## далі за зону бачення (П-47).
@rpc("authority", "call_remote", "reliable")
func client_vision(radius: float) -> void:
	var me: Node = creatures.get(multiplayer.get_unique_id())
	if me != null:
		me.get_node("CameraRig").vision_radius = radius


@rpc("authority", "call_remote", "reliable")
func client_target(id: int) -> void:
	var me: Node = creatures.get(multiplayer.get_unique_id())
	if me != null:
		me.target_id = id


@rpc("authority", "call_remote", "reliable")
func client_hp(id: int, hp: int) -> void:
	if creatures.has(id):
		creatures[id].hp = hp


## Ціль загинула. Труп, його строк і вміння по трупах — крок 10.
@rpc("authority", "call_remote", "reliable")
func client_died(id: int) -> void:
	if creatures.has(id):
		creatures[id].hp = 0
		creatures[id].lay_down()


@rpc("authority", "call_remote", "reliable")
func client_revive(id: int, hp: int) -> void:
	if creatures.has(id):
		creatures[id].hp = hp


@rpc("authority", "call_remote", "reliable")
func client_notice(text: String) -> void:
	print("[гра] ", text)


@rpc("authority", "call_remote", "reliable")
func client_despawn(id: int) -> void:
	if creatures.has(id):
		creatures[id].queue_free()
		creatures.erase(id)


@rpc("authority", "call_remote", "unreliable_ordered")
func client_positions(snapshot: Dictionary) -> void:
	for id in snapshot:
		if creatures.has(id):
			creatures[id].server_position = snapshot[id]


# ── спільне ───────────────────────────────────────────────────────────

func _spawn(id: int, pos: Vector3) -> Node3D:
	var a: Node3D = MOB.instantiate() if id < 0 else AVATAR.instantiate()
	a.name = ("Mob%d" % -id) if id < 0 else ("Avatar%d" % id)
	add_child(a)
	a.global_position = pos
	a.server_position = pos
	creatures[id] = a
	return a
