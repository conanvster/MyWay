class_name ClientView
extends RefCounted
## Клієнтський бік: згладжування картинки й ввід.
##
## Клієнт нічого не вирішує (П-08). Він показує те, що надіслав сервер,
## і надсилає наміри: куди біжу, у кого влучив мишею, що натиснув.

## Наскільки швидко клієнт підтягує чужі капсули до надісланої позиції.
## Це згладжування картинки, а не передбачення руху (П-55, П-82).
const SMOOTHING := 14.0

## Режим показу: клієнт сам бере ціль і б'є, щоб можна було зняти HUD у
## бою. Це НЕ лазівка: він шле рівно ті самі повідомлення, що й людина
## клавішами, і сервер перевіряє їх так само. Вмикається аргументом:
##     godot --path game -- --демо
const DEMO_START := 3.0    ## скільки чекати, поки з'явиться світ
const DEMO_EVERY := 0.9    ## як часто натискати
const DEMO_SHOT := 2.5     ## як часто знімати екран
const DEMO_CLICK := 6.0    ## як часто тицяти в землю, щоб бачити помітку

var _creatures: Dictionary
## Вузол світу: потрібен для променя миші та номера свого з'єднання.
var _world: Node3D
var _link: Messenger


func _init(creatures: Dictionary = {}, world: Node3D = null,
		link: Messenger = null) -> void:
	_creatures = creatures
	_world = world
	_link = link if link != null else Messenger.new(world)
	_demo = OS.get_cmdline_user_args().has("--демо")


var _demo := false
var _demo_left := DEMO_START
var _demo_step := 0
var _shot_left := DEMO_START + 2.0
var _click_left := DEMO_START + 1.0
var _fps_left := DEMO_START + 2.0


## Екран входу. Є лише доти, доки не обрано персонажа (крок 5).
var _sign: SignScreen


## Сервер сказав, що без акаунта не пустить.
func ask_sign_in() -> void:
	if _sign != null:
		return
	# Якщо акаунт названо в рядку запуску — заходимо самі, без екрана.
	# Це для проб і для показу; людина однаково бачить екран.
	if Net.account != "":
		_link.to_server(&"sign_in", [Net.account, Net.password, false])
		return
	_sign = SignScreen.new()
	_world.add_child(_sign)
	_sign.setup()
	_sign.wants_sign_in.connect(func(login: String, password: String,
			register: bool) -> void:
		_link.to_server(&"sign_in", [login, password, register]))
	_sign.wants_new_character.connect(func(name: String, race: String,
			sex: String) -> void:
		_link.to_server(&"create_character", [name, race, sex]))
	_sign.wants_enter.connect(func(character: String) -> void:
		_link.to_server(&"enter_world", [character]))


func sign_failed(why: String) -> void:
	print("[вхід] ", why)
	if _sign != null:
		_sign.failed(why)


func show_characters(list: Variant) -> void:
	if list is not Array:
		return
	# Той самий шлях без рук: обираємо названого персонажа, а якщо його
	# ще немає — створюємо й заходимо.
	if Net.account != "" and _sign == null:
		for who: Dictionary in list:
			if str(who.get("name", "")) == Net.character:
				_link.to_server(&"enter_world", [Net.character])
				return
		_link.to_server(&"create_character",
				[Net.character, "людина", "чоловік"])
		return
	if _sign != null:
		_sign.show_characters(list)


func _process_sign() -> void:
	pass


## Персонаж з'явився — екран прибираємо.
func entered_world() -> void:
	if _sign != null:
		_sign.done()
		_sign = null


func _me() -> Node:
	# Без живого з'єднання номера немає, і питати його — помилка в журнал
	# щокадру. Спіймано, коли сервер упав раніше за клієнт.
	if _world.multiplayer.multiplayer_peer == null \
			or _world.multiplayer.multiplayer_peer.get_connection_status() \
			!= MultiplayerPeer.CONNECTION_CONNECTED:
		return null
	return _creatures.get(_world.multiplayer.get_unique_id())


## Підтягування до надісланої позиції. Стрибком переставляє `place_at`
## (поява, оживлення, телепорти) — саме тому воно окремим повідомленням.
func smooth(delta: float) -> void:
	var k := 1.0 - exp(-SMOOTHING * delta)
	for id in _creatures:
		var a: Node3D = _creatures[id]
		var was := a.global_position
		a.global_position = a.global_position.lerp(a.server_position, k)
		a.rotation.y = lerp_angle(a.rotation.y, a.server_facing, k)
		# Ноги переставляються за тим, як істота СПРАВДІ рухається на
		# екрані. Так анімація не бреше: стоїть — стоїть, біжить — біжить,
		# і серверові не треба слати ще й це.
		var body: Node3D = a.model()
		if body != null and a.is_alive():
			body.animate(was.distance_to(a.global_position) / maxf(delta, 0.001))


## Показ: спершу взяти найближчого монстра (комірка 3), далі бити.
func demo(delta: float) -> void:
	if not _demo or _me() == null:
		return
	# У режимі показу гравець ще й іде до найближчого монстра — інакше
	# він стоїть на місці й на всі удари відповідає «задалеко».
	var me: Node = _me()
	var closest: Node3D = null
	var best := 1e9
	for id in _creatures:
		if id >= 0:
			continue
		var far: float = me.global_position.distance_to(
				_creatures[id].global_position)
		if far < best:
			best = far
			closest = _creatures[id]
	me.walk_to = closest.global_position if closest != null else Vector3.ZERO

	# Тицяємо в землю тим самим шляхом, що й людина мишею: інакше
	# клік нічим не перевірити — рук у проби немає.
	_click_left -= delta
	if _click_left <= 0.0:
		_click_left = DEMO_CLICK
		var screen: Vector2 = _world.get_viewport().get_visible_rect().size
		click_at(Vector2(screen.x * 0.5, screen.y * 0.72))
		# Знімок одразу по кліку: помітка гасне за дві секунди, і в
		# звичайний лад знімків вона просто не потрапляла.
		_shot_left = 0.25

	# Раз на п'ять секунд кажемо, скільки кадрів на секунду: без цього
	# «швидше чи повільніше» лишається відчуттям, а не числом.
	_fps_left -= delta
	if _fps_left <= 0.0:
		_fps_left = 5.0
		print("[кадри] %d за секунду" % Engine.get_frames_per_second())

	_shot_left -= delta
	if _shot_left <= 0.0:
		_shot_left = DEMO_SHOT
		take_shot()
	_demo_left -= delta
	if _demo_left > 0.0:
		return
	_demo_left = DEMO_EVERY
	_demo_step += 1
	if _demo_step == 1:
		_link.to_server(&"use_slot", [2, false])   # взяти монстра
		return
	# Далі по колу: удар · вибух · удар · промінь — щоб на знімку було
	# видно і бій, і відкати скілів на панелі.
	match _demo_step % 4:
		2: _link.to_server(&"use_slot", [5, false])  # енергетичний вибух
		0: _link.to_server(&"use_slot", [6, false])  # енергетичний промінь
		_: _link.to_server(&"strike")


func apply_positions(snapshot: Dictionary) -> void:
	for id in snapshot:
		if _creatures.has(id):
			var p: Vector4 = snapshot[id]
			_creatures[id].server_position = Vector3(p.x, p.y, p.z)
			_creatures[id].server_facing = p.w


func input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F12:
			take_shot()
			return
		var slot := slot_of(event.keycode)
		if slot != -1:
			_link.to_server(&"use_slot", [slot, event.shift_pressed])
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		click_at(event.position)


## Розкладка панелі — П-58; поки просто 1–7 підряд.
func slot_of(code: int) -> int:
	if code >= KEY_1 and code <= KEY_7:
		return code - KEY_1
	return -1


## Перший клік по цілі бере її, наступні по вже вибраній — б'ють (П-20).
func click_at(where: Vector2) -> void:
	var me: Node = _me()
	if me == null:
		return
	var cam: Camera3D = me.get_node("CameraRig/Camera3D")
	var from := cam.project_ray_origin(where)
	var query := PhysicsRayQueryParameters3D.create(
			from, from + cam.project_ray_normal(where) * 200.0)
	# Шари 2 «істоти» і 4 «мешканці»: клікати можна і по монстрах, і по
	# людях у місті.
	query.collision_mask = 2 | 4
	var space := _world.get_world_3d().direct_space_state
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		walk_toward(where)
		return
	var body: Object = hit["collider"]
	if body is NPC:
		# Мешканець поки не говорить (П-113) — але має відповідати хоч
		# чимось, інакше здається, що гра не помітила кліку.
		if _world.hud != null:
			_world.hud.notice("%s — поки не говорить" % body.title())
		return

	var id := id_of(body)
	if id == 0:
		return

	if me.target_id == id:
		_link.to_server(&"strike")
	else:
		_link.to_server(&"select_target", [id])


## Клік по землі — наказ іти. Другий промінь, уже по світу: перший шукав
## істот і мешканців, цей шукає, куди саме ткнули.
func walk_toward(where: Vector2) -> void:
	var me: Node = _me()
	if me == null or not me.is_alive():
		return
	var cam: Camera3D = me.get_node("CameraRig/Camera3D")
	var from := cam.project_ray_origin(where)
	var query := PhysicsRayQueryParameters3D.create(
			from, from + cam.project_ray_normal(where) * 400.0)
	query.collision_mask = 1  # шар «світ»: земля, будинки, гори
	var hit: Dictionary = _world.get_world_3d().direct_space_state \
			.intersect_ray(query)
	if hit.is_empty():
		return
	var point: Vector3 = hit["position"]
	me.walk_to = point
	_mark(point)


## Помітка на землі: куди наказано йти. Гасне за дві секунди — стільки
## просив замовник, і саме стільки треба, щоб оком помітити, куди тицьнув.
const MARK_TIME := 2.0


func _mark(point: Vector3) -> void:
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.45
	mesh.outer_radius = 0.75
	mesh.rings = 20
	ring.mesh = mesh
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(1.0, 0.85, 0.35, 0.95)
	# Світиться сама й не ховається за землею: інакше на брукові її
	# майже не видно.
	paint.emission_enabled = true
	paint.emission = Color(1.0, 0.8, 0.3)
	paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	paint.no_depth_test = true
	ring.set_surface_override_material(0, paint)
	ring.position = point + Vector3(0, 0.08, 0)
	_world.add_child(ring)

	var fade := _world.create_tween()
	fade.set_parallel(true)
	fade.tween_property(paint, "albedo_color:a", 0.0, MARK_TIME)
	fade.tween_property(ring, "scale", Vector3(1.6, 1.0, 1.6), MARK_TIME)
	fade.chain().tween_callback(ring.queue_free)


func id_of(node: Object) -> int:
	for id in _creatures:
		if _creatures[id] == node:
			return id
	return 0


## Знімок екрана по F12. Саме знімання — у `shot.gd`: воно потрібне ще й
## стартовій сторінці, а двічі писати те саме не варто.
func take_shot() -> void:
	Shot.take(_world)
