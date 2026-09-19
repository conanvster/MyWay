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

## Стан показу людини (П-162), на кожного — id -> Dictionary. Це суто
## вигляд, Creature про це не знає: `дно` (чи торкався землі минулого
## кадру), `бій_до`/`спалах_до`/`каст_до` (Time.get_ticks_msec(), доки
## тримати відповідний рух), `punch` (яка з двох рук наступна), `hp`
## (для «отримав удар у спокої»).
var _anim: Dictionary = {}
## База бігу — 5,0 (`Stats.move_speed`); з бафом чи прокачаними статами
## вище (П-161/П-162).
const JOG_SPEED := 5.6
## М/с вниз, щоб рахувати «падає», а не «з гірки збігає».
const FALL_SPEED := -1.2
const COMBAT_STANCE := 2.0    ## П-162: «2 секунди після бою»
const STRIKE_HOLD := 0.7      ## П-162: сам удар — «не менше 0,7 с»
const LOCOMOTION_HOLD := 1.0  ## П-162: хода/біг/плавання — «не менше 1 с»
const HIT_FLASH := 0.6
## Не дати першому ж кадру забити Enter/Exit одразу на Idle-каст.
const CAST_ENTER_LOCK := 0.4
const CAST_EXIT_LOCK := 0.35


func _init(creatures: Dictionary = {}, world: Node3D = null,
		link: Messenger = null) -> void:
	_creatures = creatures
	_world = world
	_link = link if link != null else Messenger.new(world)
	_demo = OS.get_cmdline_user_args().has("--демо")
	_windows = OS.get_cmdline_user_args().has("--вікна")
	_shop_demo = OS.get_cmdline_user_args().has("--крамар")


var _demo := false
## Показ відкриває «Речі» й «Стати», щоб їх було на чому побачити.
var _windows := false

## Показ іде до крамаря: підійти, заговорити, купити, продати назад.
##
## Шле рівно ті самі повідомлення, що й кнопки у вікні торгівлі — і
## сервер перевіряє їх так само. Лазівки тут немає: якби вона була,
## перевірка «без грошей не купиш» проходила б і зі зламаним сервером.
var _shop_demo := false
var _shop_done := false
var _shop_step := 0
var _shop_left := 0.0
## Скільки треба назбирати, перш ніж іти купувати. Кристал душі коштує
## 25, і з двох зайців виходить приблизно вдвічі більше.
const SHOP_DEMO_MONEY := 30
const SHOP_DEMO_GOODS := "кристал душі"
const SHOP_DEMO_PAUSE := 0.8
## Річ, якої показ ніколи не подужає: на неї треба 300, а він приходить
## із сімдесятьма. Відмову сервера перевіряємо саме нею.
const SHOP_DEMO_DEAR := "благословенний кристал душі"

## Скільки грошей у торбі. Каже сервер разом із речами; показ дивиться на
## це число, щоб не йти до крамаря з порожньою кишенею.
var money := 0
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
## Святині: як близько підійти, щоб з'явилось запрошення. Трохи менше за
## серверну дальність (`world.gd:SHRINE_REACH`) — щоб запрошення не
## вискакувало рівно на межі, звідки сервер уже відповість «задалеко».
const SHRINE_ASK := Shop.TALK_RANGE * 0.85
## Як часто дивитись, чи ми біля святині. Їх пів сотні, а підходимо ми
## пішки — щокадру перебирати всі ні до чого.
const SHRINE_LOOK := 0.4

var _shrine_clock := 0.0
## Номер святині, біля якої вже питали. Доки не відійшов — не питаємо
## вдруге: те саме правило, що й у порталі («відмовився — вийди й зайди
## знову»), і без нього вікно вискакувало б щокадру.
var _asked_shrine := -1


## Запрошення активувати святиню ключем (П-153). Друге запрошення — на
## сам телепорт — окреме: `_watch_portals` нижче (П-190).
func _watch_shrines(delta: float) -> void:
	_shrine_clock -= delta
	if _shrine_clock > 0.0:
		return
	_shrine_clock = SHRINE_LOOK
	var me: Node = _me()
	var land: Node = _world.get_node_or_null("Landscape")
	if me == null or land == null or not land.has_method("shrines"):
		return
	if _world.hud == null:
		return
	var all: Array = land.shrines()
	# Лічильник днів над відкритими (Ф8) — раз на огляд, не щокадру.
	for i in all.size():
		var left: float = _world.days_left(i)
		all[i].show_days("" if left < 0.0 else _days_text(left))
	var near := -1
	for i in all.size():
		var shrine: Shrine = all[i]
		if shrine.stage != Shrine.Stage.ЗАЧИЩЕНА:
			continue
		if me.global_position.distance_to(shrine.global_position) <= SHRINE_ASK:
			near = i
			break
	if near < 0:
		# Відійшов від усіх — наступний підхід знову спитає.
		_asked_shrine = -1
		return
	if near == _asked_shrine:
		return
	_asked_shrine = near
	# Стати на місці, поки вікно відкрите: інакше персонаж іде далі за
	# кліком, і на «так» сервер уже відповідає «задалеко».
	me.walk_to = Vector3.ZERO
	var shrine: Shrine = all[near]
	_world.hud.ask_confirm(
			"Активувати святиню ключем грейду %s?" % shrine.grade,
			func() -> void: _link.to_server(&"ask_activate", [near]))


## «29 днів», «1 день», «5 год» — останню добу рахуємо годинами, інакше
## «0 днів» висіло б цілу добу.
static func _days_text(days: float) -> String:
	if days < 1.0:
		return "%d год" % ceili(days * 24.0)
	var n := floori(days)
	var word := "днів"
	if n % 10 == 1 and n % 100 != 11:
		word = "день"
	elif n % 10 in [2, 3, 4] and not (n % 100 in [12, 13, 14]):
		word = "дні"
	return "%d %s" % [n, word]


var _portal_clock := 0.0
## У якому підземеллі ми зараз (-1 — у світі) і що було до входу.
var _in_dungeon := -1
var _world_air: Environment = null
var _lantern: OmniLight3D = null


## Запрошення в підземелля й назад (П-190, Ф4′). Коло порталу саме пам'ятає,
## хто вже в ньому стоїть (`Portal.entered`), тож «відмовився — вийди й
## зайди знову» виходить само собою, як і вирішено в П-153.
func _watch_portals(delta: float) -> void:
	_portal_clock -= delta
	if _portal_clock > 0.0:
		return
	_portal_clock = SHRINE_LOOK
	var me: Node = _me()
	if me == null or _world.hud == null or _world.dungeons == null:
		return
	var my_id: int = _world.multiplayer.get_unique_id()
	var pos: Vector3 = me.global_position
	var dungeons: Dungeons = _world.dungeons
	_dress_for(dungeons.index_at(pos.x, pos.z), me)

	var land: Node = _world.get_node_or_null("Landscape")
	if land != null and land.has_method("shrines"):
		var all: Array = land.shrines()
		for i in all.size():
			var gate: Portal = all[i].portal()
			if gate == null or not gate.entered(my_id, pos):
				continue
			var at := i
			me.walk_to = Vector3.ZERO
			var go := func() -> void:
				_link.to_server(&"ask_enter_dungeon", [at])
			_world.hud.ask_confirm(
					"Увійти в підземелля за воротами %s?" % gate.grade, go)
			return
	for at: int in dungeons.open:
		var entry: Dictionary = dungeons.open[at]
		var exit: Portal = entry["exit"]
		if exit.entered(my_id, pos):
			me.walk_to = Vector3.ZERO
			_world.hud.ask_confirm(
					"Вийти з підземелля «%s»?" % entry["plan"].title,
					func() -> void: _link.to_server(&"ask_leave_dungeon"))
			return
		# Прохід далі в палаті поваленого боса (Ф5′/Ф6).
		var down: Portal = entry["down"]
		if down != null and is_instance_valid(down) \
				and down.entered(my_id, pos):
			me.walk_to = Vector3.ZERO
			var key := at
			_world.hud.ask_confirm("Спуститися на рівень %d з %d?"
					% [Dungeons.level_of(key) + 2, int(entry["depth"])],
					func() -> void: _link.to_server(&"ask_descend", [key]))
			return


## Усередині підземелля — його повітря, без сонця, і ліхтар довкола
## гравця: згори, як дивиться камера гри, без нього поза свічками не
## видно нічого (знімки 13.09.2026). Ліхтар — пропозиція виконавця, П-193.
func _dress_for(at: int, me: Node) -> void:
	if at >= 0 and (_lantern == null or not is_instance_valid(_lantern)):
		_lantern = OmniLight3D.new()
		_lantern.name = "Ліхтар"
		_lantern.light_color = Color(1.0, 0.9, 0.75)
		_lantern.light_energy = 1.2
		_lantern.omni_range = 14.0
		_lantern.position = Vector3(0.0, 2.2, 0.0)
		me.add_child(_lantern)
	elif at < 0 and _lantern != null and is_instance_valid(_lantern):
		_lantern.queue_free()
		_lantern = null
	_show_only(at)
	if at == _in_dungeon:
		return
	_in_dungeon = at
	var sky := _world.get_node_or_null("Landscape/Небо") as WorldEnvironment
	var sun := _world.get_node_or_null("Light") as DirectionalLight3D
	if sun != null:
		sun.visible = at < 0
	if sky == null:
		return
	if _world_air == null:
		_world_air = sky.environment
	if at >= 0:
		var plan: DungeonPlan = _world.dungeons.open[at]["plan"]
		sky.environment = DungeonView.environment(
				_world.dungeons.book.style_of(plan))
	else:
		sky.environment = _world_air


## Малювати лише те, де гравець: у підземеллі — тільки його, у світі —
## тільки світ. Слово замовника 19.09.2026: камера, що провалилась за
## стіну, бачила інші підземелля й написи світу в чорній порожнечі. На
## зіткнення це не впливає — `visible` вимикає лише малювання. Кличеться
## щоразу, а не на зміні `at`: підземелля, відкрите іншим гравцем, будується
## видимим посеред гри.
func _show_only(at: int) -> void:
	for other: int in _world.dungeons.open:
		var view: Node3D = _world.dungeons.open[other]["view"]
		if is_instance_valid(view):
			view.visible = other == at
	var land := _world.get_node_or_null("Landscape") as Node3D
	if land != null:
		land.visible = at < 0


func smooth(delta: float) -> void:
	var k := 1.0 - exp(-SMOOTHING * delta)
	_watch_shrines(delta)
	_watch_portals(delta)
	for id in _creatures:
		var a: Node3D = _creatures[id]
		var was := a.global_position
		a.global_position = a.global_position.lerp(a.server_position, k)
		a.rotation.y = lerp_angle(a.rotation.y, a.server_facing, k)
		# Ноги переставляються за тим, як істота СПРАВДІ рухається на
		# екрані. Так анімація не бреше: стоїть — стоїть, біжить — біжить,
		# і серверові не треба слати ще й це.
		var body: Node3D = a.model()
		if body == null:
			continue
		var moved := a.global_position - was
		var speed := was.distance_to(a.global_position) / maxf(delta, 0.001)
		# Модель людини (Superhero+UAL1) має рухів на порядок більше, ніж
		# монстри чи фігурки-заглушки — П-162 стосується лише її; решта
		# й далі йде старим, простим шляхом (walk/idle за модулем
		# швидкості), щоб нічого монстрам не зламати.
		if body is SkinnedModel and a.has_method("apply_sex"):
			_human_state(id, a, body, speed, moved, delta)
		elif a.is_alive():
			body.animate(speed, _backward(id, a, moved))


## Обличчям до цілі, ногами — куди їде: рух проти погляду (відступ у
## бою) грає ту саму ходу навпаки — немає жодного руху «назад» у
## наборі (П-150). Гістерезис (увійти строгіше, ніж вийти) навмисно:
## сирий кут `moved` тремтить кадр-до-кадру біля порогу, і без запасу
## прапорець мигтів по кілька разів на секунду — щоразу новий рестарт
## кліпа (П-162, побачено наживо: «рвана» хода).
func _backward(id: int, a: Node3D, moved: Vector3) -> bool:
	var st: Dictionary = _anim.get(id, {})
	var now_back: bool = st.get("назад", false)
	if moved.length() > 0.01:
		var forward := -a.global_transform.basis.z
		var facing: float = forward.dot(moved.normalized())
		now_back = facing < -0.15 if now_back else facing < -0.55
	st["назад"] = now_back
	_anim[id] = st
	return now_back


## Показ моделі людини за станом (П-162). Порядок перевірок і є
## пріоритетом: смерть перекриває все, влучання в спокої — усе, крім
## смерті, і так далі до звичайної ходи.
func _human_state(id: int, a: Node3D, body: Node3D, speed: float,
		moved: Vector3, delta: float) -> void:
	var st: Dictionary = _anim.get(id, {})
	var now := Time.get_ticks_msec() / 1000.0

	if not a.is_alive():
		# lay_down() (creature.gd) уже поставив Death01 в момент смерті;
		# тут — лише запобіжник для того, хто побачив труп щойно
		# з'явившись (client_died тоді ще не приходив).
		body.show_move("Death01")
		_anim[id] = st
		return

	var last_hp: int = st.get("hp", a.hp)
	if a.hp < last_hp and speed < 0.35 and now >= st.get("бій_до", 0.0) \
			and not a.is_casting():
		st["спалах_до"] = now + HIT_FLASH
	st["hp"] = a.hp

	if now < st.get("спалах_до", 0.0):
		body.show_move("Hit_Chest")
		_anim[id] = st
		return

	if a.is_casting():
		if now < st.get("каст_вхід_до", 0.0):
			body.show_move("Spell_Simple_Enter")
		else:
			body.show_move("Spell_Simple_Idle")
		_anim[id] = st
		return

	if now < st.get("каст_вихід_до", 0.0):
		body.show_move("Spell_Simple_Exit")
		_anim[id] = st
		return

	# Сам удар (П-162: «не менше 0,7 с») тримається НЕ чіпаючи показ —
	# swung() уже поставив Punch_Jab/Cross/Sword_Attack, тут його просто
	# не перебиваємо. Стійка після бою йде вже ПІСЛЯ цього вікна, не
	# одразу з моменту замаху.
	if now < st.get("удар_до", 0.0):
		_anim[id] = st
		return
	if now < st.get("бій_до", 0.0):
		body.show_move("Sword_Idle")
		_anim[id] = st
		return

	var vertical: float = moved.y / maxf(delta, 0.001)
	var was_falling: bool = st.get("падає", false)
	if vertical < FALL_SPEED:
		st["падає"] = true
		body.show_move("Jump_Start")
		_anim[id] = st
		return
	if was_falling:
		st["падає"] = false
		body.show_move("Jump_Land")
		_anim[id] = st
		return

	var backward := _backward(id, a, moved)
	var desired := "Idle"
	if _underwater(a):
		desired = "Swim_Fwd"
	elif speed > JOG_SPEED:
		desired = "Jog_Fwd"
	elif speed > 0.35:
		desired = "Walk"

	# Мінімальне тримання (П-162: «не менше 1 с») — інакше швидкість, що
	# коливається біля порогу, чи то й ту саму хитку `backward`, шарпає
	# Walk/Jog/Idle туди-сюди частіше, ніж за секунду виходить помітити.
	var locked: String = st.get("лок_рух", "")
	if locked != "" and locked != desired and now < st.get("лок_до", 0.0):
		body.show_move(locked, backward)
	else:
		body.show_move(desired, backward)
		st["лок_рух"] = desired
		st["лок_до"] = now + LOCOMOTION_HOLD
	_anim[id] = st


## Той самий поріг, що й на сервері (`world._tick_water`) — голова нижче
## моря. Клієнт бачить ту саму геометрію, тож рахує сам, без нової мережі.
func _underwater(a: Node3D) -> bool:
	var land: Node = _world.get_node_or_null("Landscape")
	if land == null or not land.has_method("sea_level"):
		return false
	return a.global_position.y + 0.9 < land.sea_level()


## Замахнувся: `armed` вирішує, який рух — сервер знає спорядження,
## клієнт ні. Punch_Jab/Punch_Cross чергуються (слово замовника).
func swung(id: int, armed: bool) -> void:
	var a: Node = _creatures.get(id)
	var body: Node3D = a.model() if a != null else null
	var rich: bool = body is SkinnedModel and a.has_method("apply_sex")
	if body == null or not rich:
		return
	var st: Dictionary = _anim.get(id, {})
	if armed:
		body.show_move("Sword_Attack")
	else:
		var punch: bool = st.get("punch", false)
		body.show_move("Punch_Cross" if punch else "Punch_Jab")
		st["punch"] = not punch
	# Спершу сам удар не менше STRIKE_HOLD (П-162), і лише ПІСЛЯ нього —
	# COMBAT_STANCE стійки; інакше стійка перебивала б удар одразу на
	# наступному кадрі, і його не встигали побачити.
	var now := Time.get_ticks_msec() / 1000.0
	st["удар_до"] = now + STRIKE_HOLD
	st["бій_до"] = now + STRIKE_HOLD + COMBAT_STANCE
	_anim[id] = st


## Хтось почав/скінчив читати скіл (П-162) — короткі замки на вхід/вихід,
## щоб `_human_state` не забив Enter/Exit ще на тому самому кадрі.
func cast_started(id: int) -> void:
	var st: Dictionary = _anim.get(id, {})
	st["каст_вхід_до"] = Time.get_ticks_msec() / 1000.0 + CAST_ENTER_LOCK
	_anim[id] = st


func cast_ended(id: int) -> void:
	var st: Dictionary = _anim.get(id, {})
	st["каст_вихід_до"] = Time.get_ticks_msec() / 1000.0 + CAST_EXIT_LOCK
	_anim[id] = st


## Показ: спершу взяти найближчого монстра (комірка 3), далі бити.
func demo(delta: float) -> void:
	if not _demo or _me() == null:
		return
	# Крамар старший за полювання: назбирав грошей — іди витрать.
	if _demo_shop(delta):
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
		# Малювань і трикутників ЗА КАДР — це і є навантаження на
		# відеокарту. Без них «60 кадрів» нічого не кажуть: із
		# вертикальною синхронізацією шістдесят буде і тоді, коли карта
		# ледве встигає (слово замовника 06.09.2026: «відеокарта не
		# справляється»). Ці два числа показують, скільки саме
		# відсікається туманом і клаптями, а скільки таки малюється.
		print("[кадри] %d за секунду · малювань %d · трикутників %d · "
				% [Engine.get_frames_per_second(),
				   Performance.get_monitor(
						Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				   Performance.get_monitor(
						Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)]
				+ "об'єктів %d · вузлів %d · пам'ять %d МіБ"
				% [Performance.get_monitor(Performance.OBJECT_COUNT),
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
		if event.keycode == KEY_ESCAPE:
			cancel()
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
	# Шари 2 «істоти», 4 «мешканці» і 8 «святині»: клікати можна по
	# монстрах, людях у місті й святинях.
	query.collision_mask = 2 | 4 | 8
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
	if body is Shrine:
		_aim_shrine(body)
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
## На кому зараз помітка вибору — мешканець чи святиня (монстрів мітить
## `world.gd:client_target`).
var _marked: Node3D = null


func _put_mark(node: Node3D, radius: float, height: float) -> void:
	_drop_mark()
	_marked = node
	SelectMark.put(node, radius, height)


func _drop_mark() -> void:
	if _marked != null and is_instance_valid(_marked):
		SelectMark.clear(_marked)
	_marked = null


## Клік по святині (замовник 13.09.2026: «не вибирається, як NPC, хоча я
## цього очікую»). Вибирає, каже в рамці, що з нею, і веде: до святині —
## щоб з'явилось запрошення активувати, а якщо портал уже відкрито — прямо
## в коло порталу.
func _aim_shrine(shrine: Shrine) -> void:
	var me: Node = _me()
	if me == null or not me.is_alive():
		return
	_forget_resident()
	if me.target_id != 0:
		_link.to_server(&"select_target", [0])
	_put_mark(shrine, 2.2, 4.2)
	var what := "портал відкрито"
	if shrine.stage == Shrine.Stage.ПІД_ОХОРОНОЮ:
		what = "під охороною"
	elif shrine.stage == Shrine.Stage.ЗАЧИЩЕНА:
		what = "можна активувати ключем"
	if _world.hud != null:
		_world.hud.aim_resident("Святиня · ворота %s · %s"
				% [shrine.grade, what], false)
	if shrine.stage == Shrine.Stage.ПІД_ОХОРОНОЮ:
		_say("спершу зачисти охорону святині")
		return
	var gate := shrine.portal()
	if gate != null:
		# Клік — новий намір: коло знову спитає, навіть якщо вже
		# відмовлявся.
		gate.left(_world.multiplayer.get_unique_id())
		me.walk_to = gate.global_position
	else:
		_asked_shrine = -1
		var away: Vector3 = me.global_position - shrine.global_position
		away.y = 0.0
		me.walk_to = shrine.global_position + away.normalized() * 2.2
	_mark(me.walk_to)


func _aim_resident(body: NPC) -> void:
	if body.at_index < 0:
		return
	_resident = body.at_index
	_resident_at = body.global_position
	_put_mark(body, 0.7, 2.0)
	# Ціль у бою знімаємо: одна ціль за раз, інакше «удар» бив би когось
	# іншого, поки на екрані стоїть ім'я мешканця.
	var me: Node = _me()
	if me != null and me.target_id != 0:
		_link.to_server(&"select_target", [0])
	if _world.hud != null:
		_world.hud.aim_resident(body.title(), body.trades())


## Те саме ззовні: сервер сказав, що ціллю став хтось інший.
func forget_resident() -> void:
	_forget_resident()


## Скасувати все відразу (П-149): чергу дій на сервері, ціль і власний
## підхід до неї — той самий підхід, що веде до далекої цілі чи до
## мешканця, інакше персонаж однаково дійшов би куди йшов і вдарив.
func cancel() -> void:
	_link.to_server(&"ask_cancel")
	_wait_slot = -1
	_wait_talk = -1
	_forget_resident()
	var me: Node = _me()
	if me != null:
		me.walk_to = Vector3.ZERO


func _forget_resident() -> void:
	var had_mark := _marked != null
	_drop_mark()
	if _resident < 0:
		# Вибрана була святиня — рамку з її назвою теж прибрати.
		if had_mark and _world.hud != null:
			_world.hud.aim_resident("", false)
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


## Показ у крамаря. Повертає true, поки зайнятий ним: тоді полювання
## цього кадру не відбувається, інакше показ бив би зайця через усе місто.
##
## Кроки рознесені в часі не для краси: сервер відповідає окремими
## повідомленнями, і без пауз перевірка не встигала б розрізнити, на що
## саме він відповів.
func _demo_shop(delta: float) -> bool:
	if not _shop_demo or _shop_done:
		return false
	# Доки грошей нема — полюємо. Інакше показ стоїть біля прилавка й
	# ніколи їх не заробить.
	if money < SHOP_DEMO_MONEY and _shop_step == 0:
		return false
	var seller: NPC = _first_seller()
	if seller == null:
		_shop_done = true
		print("[крамар] у мапі немає жодного крамаря")
		return false
	var me: Node = _me()
	if me.global_position.distance_to(seller.global_position) \
			> Shop.TALK_RANGE * 0.85:
		me.walk_to = seller.global_position
		return true
	me.walk_to = Vector3.ZERO

	_shop_left -= delta
	if _shop_left > 0.0:
		return true
	_shop_left = SHOP_DEMO_PAUSE
	_shop_step += 1
	var at: int = seller.at_index
	match _shop_step:
		1:
			_aim_resident(seller)
		2:
			_link.to_server(&"ask_talk", [at])
		3:
			_link.to_server(&"ask_shop", [at])
		4:
			# Заздалегідь задорога річ: сервер МУСИТЬ відмовити. Це
			# найважливіше з усього, що тут перевіряється, — саме на цій
			# перевірці впаде зламаний сервер, який вірить клієнтові.
			_link.to_server(&"ask_buy", [at, SHOP_DEMO_DEAR])
		5:
			_link.to_server(&"ask_buy", [at, SHOP_DEMO_GOODS])
		6:
			_link.to_server(&"ask_sell_stack", [at, SHOP_DEMO_GOODS])
		_:
			_shop_done = true
			print("[крамар] показ закінчив торгувати")
	return true


## Перший крамар у краєвиді. Мешканців мало й вони не з'являються на ходу,
## тож шукати щокадру не дорого — і не треба тримати ще одну таблицю.
func _first_seller() -> NPC:
	var land: Node = _world.get_node_or_null("Landscape")
	if land == null:
		return null
	for child in land.get_children():
		if child is NPC and child.trades():
			return child
	return null


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
