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


func _me() -> Node:
	return _creatures.get(_world.multiplayer.get_unique_id())


## Підтягування до надісланої позиції. Стрибком переставляє `place_at`
## (поява, оживлення, телепорти) — саме тому воно окремим повідомленням.
func smooth(delta: float) -> void:
	var k := 1.0 - exp(-SMOOTHING * delta)
	for id in _creatures:
		var a: Node3D = _creatures[id]
		a.global_position = a.global_position.lerp(a.server_position, k)
		a.rotation.y = lerp_angle(a.rotation.y, a.server_facing, k)


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
	me.demo_to = closest.global_position if closest != null else Vector3.ZERO

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


func id_of(node: Object) -> int:
	for id in _creatures:
		if _creatures[id] == node:
			return id
	return 0


## Знімок екрана по F12.
##
## Потрібен, бо очима перевіряється те, чого не перевірити пробою: HUD,
## камера, світло. Зовнішні знімалки під цим композитором не працюють
## (grim: "compositor doesn't support wlr-screencopy"), а зсередини Godot
## знімок виходить завжди.
##
## Знімати можна лише ПІСЛЯ того, як кадр намальовано, інакше в текстурі
## порожнеча — звідси одноразове під'єднання до frame_post_draw.
func take_shot() -> void:
	RenderingServer.frame_post_draw.connect(_save_shot,
			CONNECT_ONE_SHOT)


func _save_shot() -> void:
	var image := _world.get_viewport().get_texture().get_image()
	var path := "user://знімок-%s.png" % Time.get_datetime_string_from_system(
			false, true).replace(":", "-").replace(" ", "_")
	var err := image.save_png(path)
	if err != OK:
		push_error("[знімок] не зберігся: %s" % error_string(err))
		print("[знімок] ‼ не зберігся: %s" % error_string(err))
		return
	print("[знімок] ", ProjectSettings.globalize_path(path))
