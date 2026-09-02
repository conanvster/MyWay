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
	_windows = OS.get_cmdline_user_args().has("--вікна")


var _demo := false
## Показ відкриває «Речі» й «Стати», щоб їх було на чому побачити.
var _windows := false
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
	# Без живого з'єднання номера немає, і питати його — помилка щокадру.
	if not Net.connected():
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
	if closest != null:
		me.walk_to = closest.global_position
	else:
		# Жодного монстра не видно — і не дивно: зона бачення 18 метрів,
		# а зони появи за містом. Тоді йдемо до найближчої зони: вона є в
		# сцені й у клієнта теж.
		me.walk_to = _nearest_zone(me.global_position)


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
	#
	# Поруч — об'єкти й пам'ять. Клієнт показу одного разу набрав 28 ГіБ і
	# машину поклав OOM-килер; за самими кадрами цього не видно було
	# взагалі, а два ці числа кажуть одразу, чи щось накопичується і чи
	# це вузли, чи сира пам'ять.
	_fps_left -= delta
	if _fps_left <= 0.0:
		_fps_left = 5.0
		print("[кадри] %d за секунду · об'єктів %d · вузлів %d · пам'ять %d МіБ"
				% [Engine.get_frames_per_second(),
				   Performance.get_monitor(Performance.OBJECT_COUNT),
				   Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
				   Performance.get_monitor(Performance.MEMORY_STATIC)
						/ 1024 / 1024])

	_shot_left -= delta
	if _shot_left <= 0.0:
		_shot_left = DEMO_SHOT
		take_shot()
	_demo_left -= delta
	if _demo_left > 0.0:
		return
	_demo_left = DEMO_EVERY
	_demo_step += 1
	# Немає цілі — беремо наступного монстра. Раніше ціль бралась ЛИШЕ
	# один раз, на початку: убивши першого, показ до кінця прогону казав
	# «немає цілі», і ні друга ціль, ні підхід до неї не перевірялись.
	# Вікна «Речі» й «Стати» руками ніхто не відкриє: у показу немає рук,
	# а без них жоден знімок їх не покаже. Тому окремий прапорець
	# `--вікна`, і відкриваються вони РАЗ, на шостому кроці — до нього
	# вже щось убито, тож у торбі є здобич, а не порожні комірки.
	if _windows and _demo_step == 6 and _world.hud != null:
		_world.hud.show_windows()
	var aimed: Node3D = _creatures.get(me.target_id)
	if me.target_id == 0 or aimed == null or not aimed.is_alive():
		_press("next_mob")
		return
	# Далі по колу: удар · вибух · удар · промінь — щоб на знімку було
	# видно і бій, і відкати скілів на панелі.
	# Через `use_slot`, а не навпростець: показ має ходити тим самим
	# шляхом, що й людина, інакше підхід до цілі ніхто б не перевіряв.
	match _demo_step % 4:
		2: _press(Actions.SKILL_PREFIX + "енергетичний-вибух")
		0: _press(Actions.SKILL_PREFIX + "енергетичний-промінь")
		_: _press("attack")


## Натиснути ту комірку, у якій лежить ця дія.
##
## За НОМЕРОМ комірки шукати не можна: розкладку кожен складає під себе,
## і показ, прив'язаний до номерів, ламається від першої ж перестановки.
## Уже ламався: після зміни типової розкладки він бив «наступну ціль»
## замість променя й не вбив нікого за півтори хвилини.
func _press(action: String) -> void:
	var slot := _bar.find(action)
	if slot >= 0:
		use_slot(slot, false)


## Осередок найближчої зони появи. Порожній вектор — зон немає.
func _nearest_zone(from: Vector3) -> Vector3:
	var found := Vector3.ZERO
	var best := 1e9
	for zone in _world.find_children("*", "MobZone", true, false):
		var far: float = from.distance_to(zone.global_position)
		# Прийшли — беремо наступну за віддаленістю, щоб не тупцювати.
		if far < 6.0 or far >= best:
			continue
		best = far
		found = zone.global_position
	return found


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
			use_slot(slot, event.shift_pressed)
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
		# Мешканець стає ціллю, як монстр. Далі з ним говорять тією самою
		# дією, що б'ють монстра: вибрав, підійшов, «удар» — і замість
		# шкоди приходить вікно розмови (П-132). Окремої кнопки «говорити»
		# не треба, і панель не росте від кожного нового мешканця.
		_aim_resident(body)
		return

	var id := id_of(body)
	if id == 0:
		return

	_forget_resident()
	if me.target_id == id:
		_link.to_server(&"strike")
	else:
		_link.to_server(&"select_target", [id])


## Кого з мешканців вибрано. -1 — нікого.
var _resident := -1


func _aim_resident(body: NPC) -> void:
	if body.at_index < 0:
		return
	_resident = body.at_index
	_resident_at = body.global_position
	# Ціль у бою знімаємо: одна ціль за раз, інакше «удар» бив би когось
	# іншого, поки на екрані стоїть ім'я мешканця.
	var me: Node = _me()
	if me != null and me.target_id != 0:
		_link.to_server(&"select_target", [0])
	if _world.hud != null:
		_world.hud.aim_resident(body.title(), body.trades())


func _forget_resident() -> void:
	if _resident < 0:
		return
	_resident = -1
	if _world.hud != null:
		_world.hud.aim_resident("", false)


## Де він стоїть. Мешканець нерухомий, тож місця досить — шукати вузол
## щокадру ні до чого.
var _resident_at := Vector3.ZERO


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


# ── підійти й застосувати ─────────────────────────────────────────────
#
# Замовник узяв ціль, натиснув 6 — і не сталось нічого. Сервер чесно
# відповідав «задалеко» й ДІЮ ВИКИДАВ: у черзі їй не місце, бо поки
# дійдеш, вона вже застаріє. Але людина чекає іншого: «підійду й зроблю».
#
# Рішення на боці клієнта, і це не порушує П-08. Клієнт нічого не
# вирішує — він лише йде до цілі (як ходить від кліку мишею) і повторює
# натискання, коли вже близько. Сервер перевіряє відстань так само
# суворо, як і раніше.

## Те саме, але до мешканця: він нерухомий, здоров'я не має й померти не
## може, тож умов тут менше, ніж у бою.
func _approach_resident(delta: float) -> void:
	var me: Node = _me()
	if me == null or not me.is_alive():
		_wait_talk = -1
		return
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_A) \
			or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_D):
		_wait_talk = -1
		return
	_wait_left -= delta
	if _wait_left <= 0.0:
		_wait_talk = -1
		_say("до мешканця не дійти")
		return
	if me.global_position.distance_to(_resident_at) <= Shop.TALK_RANGE * 0.85:
		_link.to_server(&"ask_talk", [_wait_talk])
		me.walk_to = Vector3.ZERO
		_wait_talk = -1


## Скільки щонайбільше йти до цілі, перш ніж кинути намір.
const REACH_TIME := 8.0
## Підходимо трохи ближче за межу: ціль рухається, і на самій межі
## перший же її крок робив би «задалеко» знову.
const REACH_MARGIN := 0.85

## Розкладка панелі: та сама, що в показі. Потрібна, щоб знати, яка
## дальність у того, що натиснули.
var _bar: Array[String] = []
var _wait_slot := -1
## Номер мешканця, до якого йдемо говорити. -1 — нікуди.
var _wait_talk := -1
var _wait_shift := false
var _wait_target := 0
var _wait_range := 0.0
var _wait_left := 0.0


func set_bar(bar: Array) -> void:
	_bar.assign(bar)


## Яка дальність потрібна цій дії. 0 — дія без відстані (перебір цілей,
## «сісти»), таку шлемо одразу.
func _reach_of(action: String) -> float:
	if action == "attack":
		return Creature.ATTACK_RANGE
	# Приставку беремо з `Actions`, а не пишемо вдруге: коли її колись
	# перейменують, друга копія тихо перестане збігатись.
	if not action.begins_with(Actions.SKILL_PREFIX):
		return 0.0
	var book: SkillBook = _world.data.skills if _world.data != null else null
	if book == null:
		return 0.0
	var skill: Skill = book.get_skill(
			action.substr(Actions.SKILL_PREFIX.length()))
	if skill == null:
		return 0.0
	# Рівень скіла знає сервер, не клієнт. Беремо перший — у нього
	# дальність найменша, тож підійдемо трохи ближче, ніж конче треба.
	return skill.range_at(1)


func use_slot(slot: int, shift: bool) -> void:
	_wait_slot = -1
	_wait_talk = -1
	var me: Node = _me()
	var action: String = _bar[slot] if slot < _bar.size() else ""
	var need := _reach_of(action)
	# Вибрано мешканця — «удар» означає «заговорити». Решта дій по ньому
	# просто нічого не робить: лікувати крамарку нема від чого.
	if _resident >= 0 and me != null:
		if action != "attack":
			_say("до мешканця це не застосуєш")
			return
		if me.global_position.distance_to(_resident_at) <= Shop.TALK_RANGE:
			_link.to_server(&"ask_talk", [_resident])
			return
		_wait_talk = _resident
		_wait_left = REACH_TIME
		me.walk_to = _resident_at
		_say("підходжу до мешканця")
		return
	if me == null or need <= 0.0 or me.target_id == 0:
		_link.to_server(&"use_slot", [slot, shift])
		return
	var target: Node3D = _creatures.get(me.target_id)
	# Мертвої чи зниклої цілі не доганяємо: хай сервер скаже, чому ні.
	if target == null or not target.is_alive():
		_link.to_server(&"use_slot", [slot, shift])
		return
	if me.global_position.distance_to(target.global_position) <= need:
		_link.to_server(&"use_slot", [slot, shift])
		return
	_wait_slot = slot
	_wait_shift = shift
	_wait_target = me.target_id
	_wait_range = need * REACH_MARGIN
	_wait_left = REACH_TIME
	_say("підходжу до цілі")


## Крок підходу. Кличеться щокадру з `world._process` на клієнті.
func approach(delta: float) -> void:
	if _wait_talk >= 0:
		_approach_resident(delta)
		return
	if _wait_slot < 0:
		return
	var me: Node = _me()
	if me == null or not me.is_alive():
		_wait_slot = -1
		return
	# Клавіатура старша за намір, як і скрізь: пішов сам — намір знято.
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_A) \
			or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_D):
		_wait_slot = -1
		return
	var target: Node3D = _creatures.get(_wait_target)
	if target == null or not target.is_alive() or me.target_id != _wait_target:
		_wait_slot = -1
		return
	_wait_left -= delta
	if _wait_left <= 0.0:
		_wait_slot = -1
		_say("до цілі не дійти")
		return
	if me.global_position.distance_to(target.global_position) <= _wait_range:
		_link.to_server(&"use_slot", [_wait_slot, _wait_shift])
		me.walk_to = Vector3.ZERO
		_wait_slot = -1
		return
	me.walk_to = target.global_position


## Своє повідомлення — тим самим шляхом, що й серверне: у показ і в
## консоль. Без друку його не видно у перевірках, а перевіряти підхід до
## цілі очима щоразу — це те, від чого ми й тікаємо.
func _say(text: String) -> void:
	print("[гра] ", text)
	if _world.hud != null:
		_world.hud.notice(text)
