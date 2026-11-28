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
## Темп рухів (11.10.2026): швидкість, за якої кліп грає як у файлі.
## Хода — база бігу без бафів (`Stats.move_speed`), біг — поріг бігу.
const WALK_REF := 5.0
const JOG_REF := JOG_SPEED
## Пауза між ударами за середньої спритності й без бафів
## (`Stats.attack_cooldown`). Коротша — замах швидший у стільки ж разів.
const SWING_REF := 1.2
const TEMPO_MIN := 0.6
const TEMPO_MAX := 3.0
## Частий удар (баф): з якої частини руху найпізніше починати (сам удар у
## кліпах — близько середини) і наскільки тоді можна прискорити залишок.
const IMPACT_FROM_MAX := 0.45
const FAST_STRIKE_TEMPO_MAX := 4.0
## Каст — до ×4: рух касту сканів 2,28 с, а сильні бафи ріжуть читання до
## 0,6 с; далі рух коротшає лише до межі.
const CAST_TEMPO_MAX := 4.0
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
	_ward_demo = OS.get_cmdline_user_args().has("--варта")
	_trade_demo = OS.get_cmdline_user_args().has("--обмін")
	_trade_lead = OS.get_cmdline_user_args().has("--веде")
	_duel_demo = OS.get_cmdline_user_args().has("--арена")


var _demo := false
## Показ відкриває «Речі» й «Стати», щоб їх було на чому побачити.
var _windows := false

## Показ іде до крамаря: підійти, заговорити, купити, продати назад.
##
## Шле рівно ті самі повідомлення, що й кнопки у вікні торгівлі — і
## сервер перевіряє їх так само. Лазівки тут немає: якби вона була,
## перевірка «без грошей не купиш» проходила б і зі зламаним сервером.
var _shop_demo := false
## Показ б'є крамаря Ctrl+ударом (П-262) і друкує, що бачить: підпис зі
## здоров'ям мешканця, де вартовий і що лишилось від себе.
var _ward_demo := false
var _ward_hits := 0
var _ward_left := 0.0
var _ward_time := 0.0
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

## Показ обміну (П-218): два клієнти, `--обмін --веде` і просто
## `--обмін`. Ведучий полює до перших грошей, другий ходить за ним
## слідом і в бій не лізе. Тоді ведучий кличе на обмін, кладе всі гроші,
## обидва згоджуються — і кожен друкує, скільки грошей у нього стало.
## Шле ті самі прохання, що й кнопки вікна обміну.
var _trade_demo := false
var _trade_lead := false
var _trade_done := false
var _trade_left := 0.0
var _trade_gave := 0
var _trade_table: Dictionary = {}
var _trade_asked_agree := false
const TRADE_DEMO_NEAR := 2.5
## Де міняються: по другий бік від зайців полігона (вони на +x).
const TRADE_DEMO_SPOT := Vector3(-12.0, 0.0, 0.0)
const TRADE_DEMO_EVERY := 2.0

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
			sex: String, look: Dictionary) -> void:
		_link.to_server(&"create_character", [name, race, sex,
				JSON.stringify(look)]))
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
var _step_clock := 0.0
## Перехід, про який уже спитали: "дерево:перехід:вгору". Поки стоїш
## біля нього — не питаємо вдруге; відійшов — спитає знову.
var _asked_step := ""


## Драбина, сходи чи портал між поверхами дерева-велета (07.11.2026):
## підійшов — «піднятися?» / «спуститися?».
func _watch_tree_steps(delta: float) -> void:
	_step_clock -= delta
	if _step_clock > 0.0:
		return
	_step_clock = SHRINE_LOOK
	var me: Node = _me()
	var land: Node = _world.get_node_or_null("Landscape")
	if me == null or _world.hud == null or land == null \
			or not land.has_method("giant_trees"):
		return
	var trees: Array[GiantTree] = land.giant_trees()
	for t in trees.size():
		var here: Array = trees[t].step_at(me.global_position)
		if here.is_empty():
			continue
		var key := "%d:%d:%s" % [t, int(here[0]), here[1]]
		if key == _asked_step:
			return
		_asked_step = key
		me.walk_to = Vector3.ZERO
		var step: Dictionary = trees[t].steps[int(here[0])]
		var up: bool = here[1]
		var to: int = int(step["з"]) + (2 if up else 1)
		var how: String = {"драбина": "драбиною", "сходи": "сходами",
				"портал": "порталом"}.get(str(step["вид"]), "")
		var at := t
		var which := int(here[0])
		_world.hud.ask_confirm("%s %s на %d поверх (рівень %d)?" % [
				"Піднятися" if up else "Спуститися", how, to,
				trees[t].levels[to - 1]],
				func() -> void: _link.to_server(&"ask_tree_step",
						[at, which, up]))
		return
	_asked_step = ""


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
	_watch_tree_steps(delta)
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
		elif body is SkinnedModel and a.is_alive():
			_monster_state(id, a, body, speed, moved)
		elif a.is_alive():
			body.animate(speed, _backward(id, a, moved))


## Показ монстра (П-297, 28.11.2026: «стоїть, біжить, б'є, кастує, реакція на
## удар, смерть»). Модель без потрібного руху (`Cast`, `Hit`) іде старим
## шляхом — хода/стояння, як було, нічого не ламаючи. Удар ставить
## `SkinnedModel.swing()` (world.gd), смерть — `creature.lay_down()`.
func _monster_state(id: int, a: Node3D, body: SkinnedModel, speed: float,
		moved: Vector3) -> void:
	var st: Dictionary = _anim.get(id, {})
	var now := Time.get_ticks_msec() / 1000.0
	var last_hp: int = st.get("hp", a.hp)
	# влучання — не посеред власного удару (інакше смикається)
	if a.hp < last_hp and not a.is_casting() and not body.is_busy() \
			and body.has_move("Hit"):
		body.hold_move(body.variant("Hit"))
	st["hp"] = a.hp
	if body.is_busy():
		_anim[id] = st
		return
	if a.is_casting() and body.has_move("Cast"):
		body.show_move("Cast")
		body.set_tempo(st.get("темп_касту", 1.0))
		_anim[id] = st
		return
	_anim[id] = st
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
	# Темп: поки триває удар — його власний (`swung`), решта рухів — як у
	# файлі; хода й біг нижче ставлять свій від швидкості.
	body.set_tempo(st.get("темп_удару", 1.0)
			if now < st.get("удар_до", 0.0) else 1.0)

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
		# Зі щитом у руці — блок (рух є у сканів), інакше — влучання.
		body.show_move("Block" if a.has_method("holds_shield")
				and a.holds_shield() and body.has_move("Block")
				else "Hit_Chest")
		_anim[id] = st
		return

	if a.is_casting():
		# Входу в каст у сканів немає — одразу сам каст.
		if now < st.get("каст_вхід_до", 0.0) \
				and body.has_move("Spell_Simple_Enter"):
			body.show_move("Spell_Simple_Enter")
		else:
			body.show_move("Spell_Simple_Idle")
			body.set_tempo(st.get("темп_касту", 1.0))
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
	var shown := desired
	if locked != "" and locked != desired and now < st.get("лок_до", 0.0):
		shown = locked
	else:
		st["лок_рух"] = desired
		st["лок_до"] = now + LOCOMOTION_HOLD
	body.show_move(shown, backward)
	# Ноги в такт швидкості: баф на біг — частіший крок, дебаф — рідший.
	if shown == "Walk":
		body.set_tempo(clampf(speed / WALK_REF, TEMPO_MIN, TEMPO_MAX))
	elif shown == "Jog_Fwd":
		body.set_tempo(clampf(speed / JOG_REF, TEMPO_MIN, TEMPO_MAX))
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
func swung(id: int, armed: bool, gap: float = 0.0) -> void:
	var a: Node = _creatures.get(id)
	var body: Node3D = a.model() if a != null else null
	var rich: bool = body is SkinnedModel and a.has_method("apply_sex")
	if body == null or not rich:
		return
	var st: Dictionary = _anim.get(id, {})
	# Рух за зброєю (07.11.2026, слово замовника: «рухи — відповідні діям»):
	# лук — постріл, решта — замах; моделі без пострілу — замах.
	var move := "Sword_Attack"
	if not armed:
		var punch: bool = st.get("punch", false)
		move = "Punch_Cross" if punch else "Punch_Jab"
		st["punch"] = not punch
	elif a.has_method("held_kind") and a.held_kind() == "лук" \
			and body.has_move("Bow_Shot"):
		move = "Bow_Shot"
	# Темп — щоб увесь рух уклався в паузу між ударами (див. нижче). Коли
	# пауза коротша навіть за рух утричі швидше (баф на атаку), рух
	# починається не з замаху, а ближче до самого удару: кожен удар з логів
	# — окремий видимий удар (слово замовника 27.11.2026: «за один удар по
	# логам проходить до 4 ударів»). Далі за IMPACT_FROM_MAX не різати —
	# сам удар у кліпах близько середини.
	var clip: float = body.move_length(move)
	var whole: float = clip if clip > 0.0 else SWING_REF
	var from_part := 0.0
	if gap > 0.0 and whole / gap > TEMPO_MAX:
		from_part = clampf(1.0 - gap * TEMPO_MAX / whole, 0.0, IMPACT_FROM_MAX)
	body.show_move(move, false, true, from_part)
	# Спершу сам удар не менше STRIKE_HOLD (П-162), і лише ПІСЛЯ нього —
	# COMBAT_STANCE стійки; інакше стійка перебивала б удар одразу на
	# наступному кадрі, і його не встигали побачити.
	# Бафом прискорений удар — швидший замах і коротше тримання: інакше
	# наступний удар приходив би раніше, ніж скінчився попередній.
	# Повільніше за файл не граємо: повільний боєць просто довше стоїть.
	# Темп — щоб увесь рух уклався в паузу між ударами (від справжньої
	# тривалості кліпа: у сканів удар 1,52 с і на паузі 1,2 с обривався
	# посередині). Паузу ріжуть спритність і бафи (`Stats.attack_cooldown`).
	var tempo := 1.0
	var left := whole * (1.0 - from_part)
	if gap > 0.0:
		tempo = clampf(left / gap, 1.0, FAST_STRIKE_TEMPO_MAX
				if from_part > 0.0 else TEMPO_MAX)
	body.set_tempo(tempo)
	st["темп_удару"] = tempo
	var hold := maxf(STRIKE_HOLD * (1.0 - from_part), left) / tempo
	var now := Time.get_ticks_msec() / 1000.0
	st["удар_до"] = now + hold
	st["бій_до"] = now + hold + COMBAT_STANCE
	_anim[id] = st


## Хтось почав/скінчив читати скіл (П-162) — короткі замки на вхід/вихід,
## щоб `_human_state` не забив Enter/Exit ще на тому самому кадрі.
## `seconds` — скільки читати (`Stats.cast_time`, бафи на швидкість касту
## його ріжуть): рух касту грає в такому темпі, щоб скінчитись разом із
## читанням.
func cast_started(id: int, seconds: float = 0.0) -> void:
	var st: Dictionary = _anim.get(id, {})
	st["каст_вхід_до"] = Time.get_ticks_msec() / 1000.0 + CAST_ENTER_LOCK
	st["темп_касту"] = 1.0
	var a: Node = _creatures.get(id)
	var body: Node3D = a.model() if a != null else null
	if body is SkinnedModel and seconds > 0.0:
		# монстр — свій `Cast` (П-297), людина — набір UAL1
		var clip: float = body.move_length("Spell_Simple_Idle"
				if a.has_method("apply_sex") else "Cast")
		if clip > 0.0:
			st["темп_касту"] = clampf(clip / seconds, TEMPO_MIN, CAST_TEMPO_MAX)
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
	if _demo_ward(delta):
		return
	if _demo_trade(delta):
		return
	if _demo_duel(delta):
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
			# Смуги 2–4 панелі (П-232): Ctrl, Alt, Ctrl+Alt. Чи відкрита
			# смуга, вирішує сервер за ременем — тут лише номер комірки.
			if event.ctrl_pressed and event.alt_pressed:
				slot += 21
			elif event.alt_pressed:
				slot += 14
			elif event.ctrl_pressed:
				slot += 7
			use_slot(slot, event.shift_pressed)
			_held_key = event.keycode
			_held_slot = slot
			_held_shift = event.shift_pressed
			_held_wait = HOLD_REPEAT
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		click_at(event.position, event.double_click, event.ctrl_pressed)


## Затиснута клавіша панелі повторює дію (слово замовника 14.11.2026:
## «якщо затиснути кнопку, наприклад 1, — буде робити повтор дії, щоб не
## натискати багато разів, але це відбувається через 0.3 сек»). Перший
## раз — одразу при натисканні, далі кожні 0,3 с, доки клавішу тримають.
## Системний автоповтор (`echo`) не годиться: його затримку й частоту
## задає ОС, а не гра. Клієнт лише частіше шле той самий намір — відкат,
## ману й ціль сервер перевіряє, як і на кожне окреме натискання (П-08).
const HOLD_REPEAT := 0.3

## Яку клавішу тримають (0 — жодну), яку комірку вона тисне й з Shift чи
## без: комбінацію запам'ятовуємо на момент натискання, щоб відпущений
## посеред повтору Ctrl не перекинув дію на іншу смугу панелі.
var _held_key := 0
var _held_slot := -1
var _held_shift := false
var _held_wait := 0.0


## Щокадру: тримають клавішу — раз на `HOLD_REPEAT` знову тиснемо комірку.
## Відпускання беремо не з події, а з `Input`: подія відпускання може
## дістатись полю чату чи вікну, а не світові, і повтор тоді не зупинився б.
func repeat_held(delta: float) -> void:
	if _held_key == 0:
		return
	if not Input.is_key_pressed(_held_key) or _typing():
		_held_key = 0
		return
	_held_wait -= delta
	if _held_wait > 0.0:
		return
	_held_wait += HOLD_REPEAT
	# Ще біжимо до цілі по цю ж дію — `approach` сам ударить, щойно
	# дістане. Повтор тут лише сипав би «підходжу до цілі» щотретини секунди.
	if _wait_slot == _held_slot:
		return
	use_slot(_held_slot, _held_shift)


## Фокус у полі для тексту (чат, кількість) — та сама цифра там пишеться,
## а не б'є.
func _typing() -> bool:
	if _world == null or not _world.is_inside_tree():
		return false
	var focus := _world.get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit


## Розкладка панелі — П-58; поки просто 1–7 підряд.
func slot_of(code: int) -> int:
	if code >= KEY_1 and code <= KEY_7:
		return code - KEY_1
	return -1


## Перший клік по цілі бере її, наступні по вже вибраній — б'ють (П-20).
## Подвійний клік по мешканцю — одразу розмова (слово замовника
## 19.09.2026: «по подвійному кліку на NPC теж відкривається діалог»).
func click_at(where: Vector2, double := false, force := false) -> void:
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
		# Ctrl+клік — удар по мешканцю (П-262), як примусова атака в L2:
		# звичайний клік лишається розмовою, і випадково напасти на
		# крамаря не вийде.
		if force:
			_strike_resident()
		elif double:
			_talk_to_resident()
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


## Заговорити до вибраного мешканця: близько — одразу, далеко —
## підійти й тоді заговорити (`_approach_resident`). Спільне для «удару»
## по мешканцю й подвійного кліку.
func _talk_to_resident() -> void:
	var me: Node = _me()
	_wait_hit = false
	if me == null or _resident < 0:
		return
	if me.where().distance_to(_resident_at) <= Shop.TALK_RANGE:
		_link.to_server(&"ask_talk", [_resident])
		return
	_wait_talk = _resident
	_wait_left = REACH_TIME
	me.walk_to = _resident_at
	_say("підходжу до мешканця")


## Ударити вибраного мешканця: близько — одразу, далеко — підійти тим
## самим підходом, що й до розмови, і вдарити вже на місці.
func _strike_resident() -> void:
	var me: Node = _me()
	if me == null or _resident < 0:
		return
	if me.where().distance_to(_resident_at) <= me.ATTACK_RANGE + 0.3:
		_link.to_server(&"strike_resident", [_resident])
		return
	_wait_talk = _resident
	_wait_hit = true
	_wait_left = REACH_TIME
	me.walk_to = _resident_at
	_say("підходжу до мешканця")


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


# ── речі на землі (П-160) ─────────────────────────────────────────────
#
# Спрощене зображення (слово замовника 01.10.2026) — значок речі без
# тла (`tools/zemlia_znachky.py` → `assets/icons/ground/`), що стоїть на
# землі обличчям до камери, і підпис над ним. Сервер шле весь перелік
# щоразу, як щось лягло чи зникло; показ лише звіряє, що додати й що
# прибрати.

const GROUND_ART := "res://assets/icons/ground/"
## Розмір речі на землі, метри: досить, щоб помітити з-за спини героя, і
## не більше за саму річ у руках.
const GROUND_SIZE := 0.7
## На скільки намальована земля вища за фізичну (заміряно знімком проби
## `ground`: на 4 см річ ховалась зовсім, на 30 см стояла).
const GROUND_LIFT := 0.2

## номер на землі -> вузол показу
var _ground_nodes: Dictionary = {}


func set_ground(rows: Array) -> void:
	if _world == null:
		return
	var keep := {}
	for row: Dictionary in rows:
		var key := int(row.get("номер", 0))
		keep[key] = true
		if _ground_nodes.has(key):
			continue
		var node := _ground_piece(row)
		_world.add_child(node)
		_ground_nodes[key] = node
	for key: int in _ground_nodes.keys():
		if not keep.has(key):
			_ground_nodes[key].queue_free()
			_ground_nodes.erase(key)


## Скільки речей зараз показано на землі — для проби.
func ground_shown() -> int:
	return _ground_nodes.size()


## Висота видимої землі під річчю. Променем по шару «світ», як клік
## «іти сюди»: `ground_at` — це рельєф без бруківки й підлог, і річ
## ховалась під ними. Промінь від 3 м угору, не з неба: інакше річ,
## викинута під дахом, лягла б на дах.
func _ground_y(at: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(
			at + Vector3(0, 3.0, 0), at + Vector3(0, -50.0, 0))
	query.collision_mask = 1  # шар «світ»
	var hit: Dictionary = _world.get_world_3d().direct_space_state \
			.intersect_ray(query)
	if not hit.is_empty():
		return float(hit["position"].y)
	if _world.has_method("ground_at"):
		return _world.ground_at(at.x, at.z)
	return at.y


func _ground_piece(row: Dictionary) -> Node3D:
	var at: Vector3 = row.get("де", Vector3.ZERO)
	var piece := Node3D.new()
	piece.name = "НаЗемлі%d" % int(row.get("номер", 0))
	piece.position = Vector3(at.x, _ground_y(at), at.z)

	var base := str(row.get("база", row.get("назва", "")))
	var file := GROUND_ART + base + ".png"
	var art: Texture2D = load(file) if ResourceLoader.exists(file) else null
	if art == null:
		# Малюнка немає — квадрат кольору грейду, а не порожнеча: річ
		# має бути видно, інакше її не знайти й не підняти (P3).
		print("[земля] ‼ немає спрощеного зображення: %s" % base)
		var plain := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		plain.fill(ItemIcon.grade_color(str(row.get("грейд", "E"))))
		# Квадрат удвічі менший за річ: межі всередині лишаються прозорими.
		plain.fill_rect(Rect2i(0, 0, 32, 8), Color(0, 0, 0, 0))
		plain.fill_rect(Rect2i(0, 24, 32, 8), Color(0, 0, 0, 0))
		plain.fill_rect(Rect2i(0, 0, 8, 32), Color(0, 0, 0, 0))
		plain.fill_rect(Rect2i(24, 0, 8, 32), Color(0, 0, 0, 0))
		art = ImageTexture.create_from_image(plain)
	# Стоїть обличчям до камери, низом на землі. Плазом річ із-за спини
	# героя сплющувалась у риску, а намальована земля ще й вища за
	# фізичну — плаский малюнок ховався в ній.
	var picture := Sprite3D.new()
	picture.texture = art
	picture.pixel_size = GROUND_SIZE / float(maxi(1, art.get_width()))
	picture.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	picture.position.y = GROUND_SIZE * 0.5 + GROUND_LIFT
	picture.double_sided = true
	piece.add_child(picture)

	var label := Label3D.new()
	var count := int(row.get("скільки", 1))
	label.text = str(row.get("назва", "?")) \
			+ (" ×%d" % count if count > 1 else "")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.004
	label.font_size = 32
	label.outline_size = 8
	label.position.y = GROUND_SIZE + GROUND_LIFT + 0.15
	piece.add_child(label)
	return piece


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
	if _wait_hit:
		if me.where().distance_to(_resident_at) <= me.ATTACK_RANGE:
			_link.to_server(&"strike_resident", [_wait_talk])
			me.walk_to = Vector3.ZERO
			_wait_talk = -1
			_wait_hit = false
		return
	if me.where().distance_to(_resident_at) <= Shop.TALK_RANGE * 0.85:
		_link.to_server(&"ask_talk", [_wait_talk])
		me.walk_to = Vector3.ZERO
		_wait_talk = -1


## Показ у крамаря. Повертає true, поки зайнятий ним: тоді полювання
## цього кадру не відбувається, інакше показ бив би зайця через усе місто.
##
## Кроки рознесені в часі не для краси: сервер відповідає окремими
## повідомленнями, і без пауз перевірка не встигала б розрізнити, на що
## саме він відповів.
const WARD_HITS := 12


func _demo_ward(delta: float) -> bool:
	if not _ward_demo:
		return false
	var seller: NPC = _first_seller()
	var me: Node = _me()
	if seller == null or me == null:
		return true
	_ward_time += delta
	_ward_left -= delta
	if _ward_left > 0.0:
		return true
	_ward_left = 1.0
	var guard: Node3D = null
	for id: int in _creatures:
		var c: Node = _creatures[id]
		if id < 0 and "kind" in c and int(c.kind) == Wardens.GUARD_KIND:
			guard = c
	var tag: Label3D = seller.get_node_or_null("Підпис")
	print("[варта] %.0f с · удар %d · підпис «%s» · вартовий %s · "
			% [_ward_time, _ward_hits, tag.text if tag != null else "?",
			   "за %.1f м" % guard.global_position.distance_to(
					me.global_position) if guard != null else "не видно"]
			+ "моє здоров'я %d" % me.hp)
	if _ward_hits >= WARD_HITS or _ward_time > 40.0 or not me.is_alive():
		print("[варта] кінець: ударів %d, живий %s" % [_ward_hits,
				me.is_alive()])
		_ward_demo = false
		return true
	_aim_resident(seller)
	_strike_resident()
	_ward_hits += 1
	return true


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
		me.walk_to = _towards_resident(me, seller)
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
			_link.to_server(&"ask_buy", [at, SHOP_DEMO_DEAR, 1])
		5:
			_link.to_server(&"ask_buy", [at, SHOP_DEMO_GOODS, 1])
		6:
			_link.to_server(&"ask_sell_stack", [at, SHOP_DEMO_GOODS, -1])
		_:
			_shop_done = true
			print("[крамар] показ закінчив торгувати")
	return true


## Куди йти до мешканця. У світі 2 він стоїть перед своєю будівлею,
## обличчям до площі, і навпростець із вулиці на нього стоять доми —
## показ упирався в стіну (06.11.2026). Тому спершу на точку перед ним на
## площі (6 м уздовж його погляду), а вже звідти — до нього.
func _towards_resident(me: Node, who: Node3D) -> Vector3:
	var front := who.global_transform.basis.z
	front.y = 0.0
	if front.length() < 0.01:
		return who.global_position
	var spot := who.global_position + front.normalized() * 6.0
	var to_me: Vector3 = me.global_position - who.global_position
	to_me.y = 0.0
	# Уже перед ним (у секторі його погляду) — прямо до нього.
	if to_me.length() < 7.0 and to_me.normalized().dot(front.normalized()) > 0.5:
		return who.global_position
	if me.global_position.distance_to(spot) < 1.5:
		return who.global_position
	return spot


## Показ обміну. Повертає true, поки зайнятий ним (полювання стоїть).
func _demo_trade(delta: float) -> bool:
	if not _trade_demo or _trade_done:
		return false
	# Ведучий полює, доки не має грошей і доки його ціль жива: кинута
	# недобита ціль б'є в спину, і ведучий гине посеред обміну (перший
	# прогін — «мертві не міняються»). Тоді відходить до місця обміну —
	# убік від зайців полігона: вони відроджуються (В-5), і чекати
	# порожнього поля не можна.
	if _trade_lead and _trade_table.is_empty() \
			and (money < 1 or _target_alive()):
		return false
	var me: Node = _me()
	if _trade_lead:
		var spot := Vector3(TRADE_DEMO_SPOT.x, me.global_position.y,
				TRADE_DEMO_SPOT.z)
		if me.global_position.distance_to(spot) > 1.5:
			me.walk_to = spot
			return true
	var other: Node3D = null
	for id: int in _creatures:
		if id > 0 and id != _world.multiplayer.get_unique_id():
			other = _creatures[id]
	if other == null:
		me.walk_to = Vector3.ZERO
		return true
	if me.global_position.distance_to(other.global_position) > TRADE_DEMO_NEAR:
		if not _trade_lead:
			me.walk_to = other.global_position
		return true
	me.walk_to = Vector3.ZERO
	if not _trade_lead:
		return true

	_trade_left -= delta
	if _trade_left > 0.0:
		return true
	_trade_left = TRADE_DEMO_EVERY
	if _trade_table.is_empty():
		# Кличемо, доки не відкриється стіл: другий міг бути ще в бою
		# чи задалеко, і сервер тоді відмовляє — це не вада.
		var other_id := 0
		for id: int in _creatures:
			if _creatures[id] == other:
				other_id = id
		_link.to_server(&"ask_trade_invite", [other_id])
		return true
	if Array(_trade_table.get("моє", [])).is_empty():
		_trade_gave = money
		print("[обмін] показ: кладу гроші ×%d" % money)
		_link.to_server(&"ask_trade_offer_stack", ["гроші", money])
		return true
	return true


## Показ арени (П-260): два клієнти, `--арена --веде` і `--арена`.
## Другий ходить за ведучим; ведучий кличе на арену, другий погоджується;
## на арені б'є лише ведучий — щоб бій скінчився, а не тягся до нічиєї.
## Кожен друкує, де стоїть: до виклику, на арені й після повернення.
## Шле ті самі прохання, що й кнопка «Виклик» і вікно згоди.
var _duel_demo := false
var _duel_done := false
var _duel_left := 0.0
var _duel_from := Vector3.ZERO
var _duel_was_in := false


func _demo_duel(delta: float) -> bool:
	if not _duel_demo or _duel_done:
		return false
	var me: Node = _me()
	var in_arena := Duels.slot_at(me.global_position.x,
			me.global_position.z) >= 0
	# Місце виклику — останнє, де стояв перед переносом: сервер вертає
	# туди, де гравець був у мить згоди, а не коли прийшов виклик (другий
	# ще міг іти до ведучого).
	if not in_arena and not _duel_was_in:
		_duel_from = me.global_position
	if in_arena and not _duel_was_in:
		_duel_was_in = true
		print("[арена] показ: на арені, стою в (%.0f, %.1f, %.0f)"
				% [me.global_position.x, me.global_position.y,
				   me.global_position.z])
	if _duel_was_in and not in_arena:
		_duel_done = true
		print("[арена] показ закінчив: назад за %.1f м від місця виклику, "
				% Vector2(me.global_position.x - _duel_from.x,
					me.global_position.z - _duel_from.z).length()
				+ "живий %s, здоров'я %d" % [me.is_alive(), me.hp])
		# В-12: «місце виклику» клієнта — не міра. Клієнт, що вантажить
		# світ, кілька секунд не малює кадрів, а сервер тим часом уже веде
		# його до ведучого: клієнт запам'ятовує місце появи (0, 0), хоч
		# сервер вертає точно туди, де той стояв у мить згоди. Тому
		# `check.sh` звіряє «тепер» із точкою, яку запам'ятав сервер.
		print("[арена] показ: я %d, тепер (%.1f, %.1f), "
				% [_world.multiplayer.get_unique_id(), me.global_position.x,
				   me.global_position.z]
				+ "місце виклику (%.1f, %.1f)" % [_duel_from.x, _duel_from.z])
		return true
	var other_id := 0
	for id: int in _creatures:
		if id > 0 and id != _world.multiplayer.get_unique_id():
			other_id = id
	if other_id == 0:
		me.walk_to = Vector3.ZERO
		return true
	var other: Node3D = _creatures[other_id]
	_duel_left -= delta
	if in_arena:
		# Ведучий іде до суперника (удар — лише поруч), другий стоїть.
		me.walk_to = other.global_position if _trade_lead \
				and me.global_position.distance_to(other.global_position) \
				> 2.0 else Vector3.ZERO
		if _trade_lead and _duel_left <= 0.0 and other.is_alive():
			_duel_left = 1.0
			_link.to_server(&"select_target", [other_id])
			_link.to_server(&"strike")
		return true
	if _trade_lead:
		var spot := Vector3(TRADE_DEMO_SPOT.x, me.global_position.y,
				TRADE_DEMO_SPOT.z)
		if me.global_position.distance_to(spot) > 1.5:
			me.walk_to = spot
			return true
	if me.global_position.distance_to(other.global_position) \
			> TRADE_DEMO_NEAR:
		if not _trade_lead:
			me.walk_to = other.global_position
		return true
	me.walk_to = Vector3.ZERO
	if _trade_lead and _duel_left <= 0.0:
		# Кличемо, доки не перенесе: другий міг бути ще задалеко чи в
		# бою, і сервер тоді відмовляє — це не вада.
		_duel_left = 2.0
		print("[арена] показ: кличу %d з (%.0f, %.0f)"
				% [other_id, me.global_position.x, me.global_position.z])
		_link.to_server(&"ask_duel_invite", [other_id])
	return true


## Сервер покликав на арену — у показі погоджуємось.
func duel_invited() -> bool:
	if not _duel_demo:
		return false
	var me: Node = _me()
	print("[арена] показ: мене кличуть, стою в (%.0f, %.0f) — так"
			% [me.global_position.x, me.global_position.z])
	_link.to_server(&"ask_duel_answer", [true])
	return true


## Ціль ведучого ще жива — бій не скінчено.
func _target_alive() -> bool:
	var me: Node = _me()
	var target: Node = _creatures.get(me.target_id) if me.target_id != 0 \
			else null
	return target != null and target.is_alive()


## Сервер покликав на обмін — у показі погоджуємось.
func trade_invited() -> bool:
	if not _trade_demo:
		return false
	_link.to_server(&"ask_trade_answer", [true])
	return true


## Стіл змінився. Показ згоджується, щойно на столі лежить те, чого
## чекали: ведучий — свої гроші, другий — гроші ведучого.
func trade_table(table: Dictionary) -> void:
	if not _trade_demo:
		return
	_trade_table = table
	var side: Array = table.get("моє" if _trade_lead else "їхнє", [])
	if side.is_empty() or bool(table.get("я згоден", false)):
		return
	print("[обмін] показ: на столі %s, згоден" % [side])
	_link.to_server(&"ask_trade_agree", [])


func trade_closed(why: String) -> void:
	if not _trade_demo or _trade_table.is_empty():
		return
	_trade_table = {}
	if why != "":
		print("[обмін] показ: стіл закрито — %s" % why)
		return
	_trade_done = true
	# Гроші приходять окремо, слідом за закриттям, — чекаємо їх.
	await _world.get_tree().create_timer(1.0).timeout
	print("[обмін] показ закінчив: %s, грошей тепер %d"
			% ["віддав %d" % _trade_gave if _trade_lead else "отримав",
			   money])


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
## Підхід до мешканця — щоб ударити (Ctrl+клік, П-262), а не заговорити.
var _wait_hit := false
var _wait_shift := false
var _wait_target := 0
var _wait_range := 0.0
var _wait_left := 0.0


## Перенесло (`world.client_place`): не бігти до старої точки й не
## підходити до старої цілі — вони лишились там, звідки перенесло.
func forget_intent() -> void:
	var me: Node = _me()
	if me != null:
		me.walk_to = Vector3.ZERO
	_wait_slot = -1
	_wait_talk = -1
	_wait_hit = false
	_wait_target = 0
	_wait_left = 0.0
	_chases = 0
	forget_resident()


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


## Сервер сказав: ціль вийшла з-під руки, поки летіла дія (В-2). Беремо
## ту саму комірку й доганяємо, як після натискання на далеку ціль. Щоб
## не бігати по колу, коли клієнт і сервер бачать відстань по-різному,
## поспіль доганяємо не більше `CHASE_MAX` разів — далі чесне «задалеко».
func chase(action: String) -> void:
	var me: Node = _me()
	var slot := _bar.find(action)
	if me == null or slot < 0 or me.target_id == 0:
		_say("задалеко")
		return
	var target: Node3D = _creatures.get(me.target_id)
	if target == null or not target.is_alive():
		return
	_chases += 1
	if _chases > CHASE_MAX:
		_chases = 0
		_say("задалеко")
		return
	_wait_talk = -1
	_wait_slot = slot
	_wait_shift = false
	_wait_target = me.target_id
	_wait_range = _reach_of(action) * CHASE_MARGIN
	_wait_left = REACH_TIME
	me.walk_to = target.global_position
	print("[гра] ціль відступила — доганяю")


## Скільки разів поспіль догнали без жодного натискання гравця.
var _chases := 0
const CHASE_MAX := 3
## Доганяємо ближче, ніж при звичайному підході: ціль уже раз утекла
## з-під руки, і рівно на межі вона втече знову.
const CHASE_MARGIN := 0.6


func use_slot(slot: int, shift: bool) -> void:
	_wait_slot = -1
	_wait_talk = -1
	_chases = 0
	var me: Node = _me()
	var action: String = _bar[slot] if slot < _bar.size() else ""
	var need := _reach_of(action)
	# Вибрано мешканця — «удар» означає «заговорити». Решта дій по ньому
	# просто нічого не робить: лікувати крамарку нема від чого.
	if _resident >= 0 and me != null:
		if action != "attack":
			_say("до мешканця це не застосуєш")
			return
		_talk_to_resident()
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
	# За сервером, не за малюнком: намальовані й я, і ціль відстають, і
	# під бафом на швидкість сервер проносив гравця крізь монстра, а
	# зіткнення відкидало назад (слово замовника 11.10.2026).
	var far: float = me.where().distance_to(target.server_position)
	if far <= _wait_range:
		_link.to_server(&"use_slot", [_wait_slot, _wait_shift])
		me.walk_to = Vector3.ZERO
		_wait_slot = -1
		return
	# Майже дійшов, а сервер ще везе — не підганяти: докотиться сам.
	if far <= _wait_range + me.lead():
		me.walk_to = Vector3.ZERO
		return
	me.walk_to = target.server_position


## Своє повідомлення — тим самим шляхом, що й серверне: у показ і в
## консоль. Без друку його не видно у перевірках, а перевіряти підхід до
## цілі очима щоразу — це те, від чого ми й тікаємо.
func _say(text: String) -> void:
	print("[гра] ", text)
	if _world.hud != null:
		_world.hud.notice(text)
