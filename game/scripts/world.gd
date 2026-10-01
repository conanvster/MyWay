extends Node3D
## Світ: тонкий шар мережі й сама сцена.
##
## На сервері живуть справжні персонажі; клієнт отримує їхні позиції й
## малює. Розсилка АДРЕСНА — окреме повідомлення на кожне з'єднання, а не
## широкомовне. Так зроблено навмисно: сервер шле кожному лише те, що той
## бачить (П-43). Готові вузли синхронізації Godot розсилають усім
## однаково і для цього не годяться.
##
## Уся робота переїхала в модулі (крок 1.1 у PLAN.md); тут лишилися самі
## `@rpc` і створення істот. Чому саме так: шлях вузла має збігатися на
## клієнті й сервері, і возитися з цим для кожного модуля не варто.
##
## «Тонкий» тут означає не «короткий». Заміряно 18.09.2026: 2006 рядків,
## 62 `@rpc`, 110 функцій, найдовша — 86 рядків (`client_spawn`). Крок
## 1.1 звів його з 648 до 263, відтоді наросли двері підземель, склад,
## гільдія, карта й підвантаження ділянками — але логіка назовні не
## протекла: жодна довша функція не рахує бою, цін чи видимості сама.
##
##     vision.gd       хто кого бачить
##     combat.gd       удар, шкода, смерть, строк трупа
##     actions.gd      черга дій, цілі, вміння
##     mob_ai.gd       поведінка монстрів
##     spawner.gd      гнізда й поява
##     mob_zone.gd     форма зони появи: те, що намальовано в редакторі
##     game_data.gd    числа з data/*.json, із перечитуванням на ходу
##     client_view.gd  згладжування й ввід клієнта
##     hud.gd          що гравець бачить поверх світу
##     messenger.gd    єдиний вихід на клієнтів

const AVATAR := preload("res://scenes/avatar.tscn")
const MOB := preload("res://scenes/mob.tscn")
## Скільки разів на секунду сервер розсилає позиції.
const TICK_HZ := 20.0
## Як часто клієнт питає краєвид, чи потрібно підвантажити/вивантажити
## ділянку (П-63). Раз на секунду досить: гравець не перебігає сектор
## швидше, ніж за цей час.
const STREAM_HZ := 1.0

## Монстри живуть у від'ємних номерах, гравці — у додатних (номер
## з'єднання). Так одна таблиця тримає і тих, і тих. Словник спільний:
## модулі тримають його ж, не копію.
var creatures: Dictionary = {}

var data: GameData
var vision: Vision
var link: Messenger
var combat: Combat
var actions: Actions
var mobs: MobAI
var spawner: Spawner
## Крамар: асортимент, ціни й перевірки торгівлі (П-132).
var shop: Shop
var warehouse: Warehouse
## Обмін між гравцями (П-218): відкриті столи й запрошення.
var trade: Trade
## Прикликані істоти (П-41).
var summons: Summons
var runes: Runes
## Відкриті підземелля за порталами святинь (П-190).
var dungeons: Dungeons
## Строк підземель і штраф світу, з базою (Ф7). Лише на сервері.
var life: DungeonLife
## Клієнт (Ф8): номер святині -> {"until": мс за `Time.get_ticks_msec`,
## "grade"}. Сервер шле, скільки СЕКУНД лишилось, а клієнт відлічує
## від своєї миті отримання — годинники машин звіряти не треба.
var dungeon_days: Dictionary = {}
var view: ClientView
## Показ. Є лише в того клієнта, чий персонаж уже з'явився.
var hud: HUD
## Збереження персонажів через PostgREST (крок 3). Є лише на сервері.
var store: Store
## Хто під яким іменем грає: peer_id -> ім'я персонажа в базі.
var _names: Dictionary = {}
## Хто увійшов: peer_id -> { логін, пароль, персонажі }.
##
## Пароль тримається в пам'яті сервера на час сеансу, бо функції бази
## перевіряють його щоразу. Це компроміс, і він записаний у П-114:
## правильніше видавати ключ сеансу, але для гри на одній машині з
## десятьма друзями зайвий шар нічого не купує.
var _signed: Dictionary = {}

var _since_tick := 0.0
var _since_stream := 0.0
## Відбиток статів кожного гравця: щоб слати сторінку «Стати» лише тоді,
## коли числа змінились.
var _stats_mark: Dictionary = {}
## Те саме для вивчених скілів.
var _skills_mark: Dictionary = {}
## І для вмісту торби.
var _bag_mark: Dictionary = {}
## І для бафів-дебафів: своїх і цілі.
var _states_mark: Dictionary = {}


func _ready() -> void:
	# Мітку від попереднього сервера прибираємо ще до того, як почали
	# будувати: інакше стартова сторінка секунду світила б зелене на
	# чужу, стару мітку при вже зайнятому порті.
	if Net.is_server:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(READY_MARK))
	data = GameData.new()
	data.load_all()
	vision = Vision.new(creatures)
	link = Messenger.new(self, vision)
	combat = Combat.new(creatures, link)
	combat.ground_height = ground_at
	combat.on_kill = _on_kill
	combat.on_reward = _on_reward
	combat.on_out_of_reach = func(me: int, action: String) -> void:
			rpc_id(me, "client_chase", action)
	# Куди вертає оживлення й скіл «повернутися в місто»: центр першого
	# міста мапи. У версії 1 і 2 це (0,0) — столиця там навмисно, — але
	# число тепер із даних, а не зашите в коді.
	var towns: Array = data.map.get("міста", [])
	if not towns.is_empty():
		var at: Array = towns[0].get("центр", [0, 0, 0])
		combat.home_spot = Vector2(float(at[0]), float(at[2]))
	combat.skills = data.skills
	combat.progress = Progress.new(data.levels)
	combat.goods = data.items
	combat.smith = data.smith
	actions = Actions.new(creatures, vision, combat, link)
	actions.goods = data.items
	mobs = MobAI.new(creatures, combat)
	mobs.sleep_far = true
	spawner = Spawner.new(creatures, self, data)
	shop = Shop.new(data)
	warehouse = Warehouse.new()
	trade = Trade.new()
	trade.names = _names
	summons = Summons.new(creatures, combat, data, spawn, remove)
	combat.on_summon = func(me: int, what: Dictionary) -> void:
			summons.request(me, what)
	runes = Runes.new(data.skills, data.professions)
	view = ClientView.new(creatures, self, link)
	dungeons = Dungeons.new()
	dungeons.name = "Підземелля"
	add_child(dungeons)

	# Краєвид будується однаково й на сервері, і в клієнта: серверові
	# потрібні стіни, щоб крізь будинки не бігали, клієнтові — картинка.
	# Дерева й паркан підвантажуються ділянками (П-63) — лише в клієнта:
	# сервер тримає зіткнення й монстрів скрізь одразу, як і раніше.
	var land: Node = get_node_or_null("Landscape")
	if land != null:
		land.build(data.map, not Net.is_server)
		_stock_merchants(land)

	if Net.is_server:
		store = Store.new()
		add_child(store)
		store.setup(Net.db)
		life = DungeonLife.new()
		life.name = "СтрокПідземель"
		add_child(life)
		life.setup(store, dungeons.book.life, GameData.world_key())
		if OS.get_cmdline_user_args().has("--перевірка-бази"):
			store.answered.connect(func(name: String, reply: Dictionary) -> void:
					print("[перевірка] %s -> %s" % [name, reply]))
			store.call_rpc("login", {"login": "конан",
					"password": "таємниця",
					"world": GameData.world_key()})
		multiplayer.peer_disconnected.connect(_on_left)
		if OS.get_cmdline_user_args().has("--полігон"):
			_range()
		else:
			# Зони з даних (світ 2) сплять, доки поруч немає гравця.
			spawner.dormant = not data.map.get("зони появи", []).is_empty()
			spawner.start(_zones())
			# Після спавнера: відновлене підземелля додає йому свої зони.
			life.restore(_restore_dungeon, close_dungeon)
		_mark_ready()
		print("[світ] сервер чекає гравців")
	else:
		# Спавн просимо самі, коли сцена вже здатна приймати виклики.
		# Якби сервер спавнив за подією з'єднання, повідомлення могло б
		# прийти раніше, ніж клієнт готовий, і загубитись.
		multiplayer.connected_to_server.connect(
				func() -> void: rpc_id(1, "announce_ready", Net.character))
		multiplayer.connection_failed.connect(
				func() -> void: print("[мережа] ‼ сервер не відповів"))
		# І аж ТЕПЕР стукаємо: доки була стартова сторінка, світу не було,
		# і пакети шукали б вузол, якого не існує.
		Net.join()


## Мітка «світ збудовано». Її читає стартова сторінка.
##
## Навіщо вона, коли є порт. Порт ENet займається в перший же кадр, ще до
## того, як прочитано дані й поставлено 70 дерев і три десятки монстрів.
## Якби сторінка світила зелене за самим портом, кнопка «Зайти в гру»
## відмикалась би на секунду раніше, ніж є куди заходити, — і ми б
## вернули собі ту саму ваду, заради якої сторінку й писали.
##
## У мітці лежить номер процесу: за ним сторінка може зупинити сервер,
## якого сама не піднімала (наприклад, запущений `./run-server.sh`).
const READY_MARK := "user://сервер.json"


func _mark_ready() -> void:
	var file := FileAccess.open(READY_MARK, FileAccess.WRITE)
	if file == null:
		print("[світ] ‼ не вдалось записати мітку %s: %s"
				% [READY_MARK, error_string(FileAccess.get_open_error())])
		return
	# «світ» — на якій мапі сервер збудований. Стартова сторінка звіряє його
	# зі своїм і не пускає в гру, якщо не збіглось: інакше персонаж у
	# чужому рельєфі під землею (слово замовника 11.09.2026).
	file.store_string(JSON.stringify({
			"номер": OS.get_process_id(),
			"порт": Net.PORT,
			"світ": GameData.map_path().get_file(),
			"коли": int(Time.get_unix_time_from_system())}))


## Полігон: закрита ділянка для перевірок (`-- --полігон`).
##
## Замість десяти зон і трьох десятків монстрів світ дістає РІВНО трьох
## зайців на 5, 7 і 9 метрах від місця появи. Навіщо саме так:
##
## - **5 метрів** — щоб перевірка бою була про те, що просили: побачив
##   ціль неподалік, дійшов, убив, отримав здобич;
## - **заєць** (вид 2) — 1 рівня, повільний і не агресивний: він не вб'є
##   того, хто його перевіряє, і не втече за обрій;
## - **троє, а не один** — з одного зайця здобич падає з імовірністю 94%,
##   і перевірка валилась би раз на шістнадцять запусків просто так. З
##   трьох порожньо виходить раз на чотири тисячі;
## - **на 5, 14 і 23 метрах, а не поруч** — заєць кличе своїх на 6 метрів.
##   Коли вони стояли за 5, 7 і 9, на першу ж атаку збігались усі троє й
##   забивали перевіряльника (заміряно: 100 здоров'я → труп). Проміжок 9
##   метрів більший за поклик, тож б'єшся з одним;
## - **місто** — земля тут рівна (краєвид вирівнює її в радіусі 26), тож
##   ніхто не тоне й не застряє в горбі.
##
## Це НЕ лазівка: прапорець читається лише сервером при запуску, і жоден
## клієнт до нього не дотягнеться.
const RANGE_KIND := 2
const RANGE_STEPS: Array[float] = [5.0, 14.0, 23.0]
## Заєць полігона встає знову на своєму місці (В-5). Без цього показ
## крамаря, що полює на 30 монет, залежав від везіння: з трьох зайців
## гроші інколи падали лише з одного (заміряно 21.09.2026: 28 і 24
## монети — «торгівля не дійшла до кінця»). Перевіряти треба крамаря, а
## не дроп, тож зайців стає скільки треба, а не три на весь прогін.
const RANGE_RESPAWN := 6.0
var _range_on := false
var _range_wait: Dictionary = {}


func _range() -> void:
	_range_on = true
	for i in RANGE_STEPS.size():
		var at := Vector3(RANGE_STEPS[i], 0.0, 0.0)
		at.y = ground_at(at.x, at.z) + 1.0
		var mob: Node = spawn(-(i + 1), at)
		mob.setup(at, RANGE_KIND, false, data.for_kind(RANGE_KIND))
	print("[полігон] %s, штук %d, найближчий за %.1f м"
			% [data.for_kind(RANGE_KIND).get("назва", "?"),
			   RANGE_STEPS.size(), RANGE_STEPS[0]])


## Труп зайця прибрано — за `RANGE_RESPAWN` секунд він знову на місці.
func _tick_range(delta: float) -> void:
	if not _range_on:
		return
	for i in RANGE_STEPS.size():
		var id := -(i + 1)
		if creatures.has(id):
			_range_wait.erase(id)
			continue
		_range_wait[id] = float(_range_wait.get(id, RANGE_RESPAWN)) - delta
		if float(_range_wait[id]) > 0.0:
			continue
		_range_wait.erase(id)
		var at := Vector3(RANGE_STEPS[i], 0.0, 0.0)
		at.y = ground_at(at.x, at.z) + 1.0
		var mob: Node = spawn(id, at)
		mob.setup(at, RANGE_KIND, false, data.for_kind(RANGE_KIND))
		print("[полігон] заєць %d знову на %.0f м" % [id, RANGE_STEPS[i]])


## Сервер іде — мітку прибираємо. На цьому не можна будувати: заміряно
## 02.09.2026, що при `kill` (як робить `./play.sh --stop`) цей виклик до
## нас не доходить, і мітка лишається на диску. Тому сторінка вірить їй
## ЛИШЕ при зайнятому порті, а новий сервер стирає стару мітку в `_ready`.
func _exit_tree() -> void:
	if Net.is_server:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(READY_MARK))


## Скільки коштує кадр сервера — щоб це було число, а не здогадка (P2).
## Раз на хвилину, перший — за 10 с від старту.
var _perf_sum := 0
var _perf_ticks := 0
var _perf_next := 10.0


func _perf_tick(spent_usec: int) -> void:
	_perf_sum += spent_usec
	_perf_ticks += 1
	var now := Time.get_ticks_msec() / 1000.0
	if now < _perf_next:
		return
	var alive := 0
	var awake := 0
	for id in creatures:
		if id < 0 and creatures[id].is_alive():
			alive += 1
			if not creatures[id].asleep:
				awake += 1
	print("[сервер] кадр фізики %.2f мс у середньому (%d кадрів) · "
			% [_perf_sum / 1000.0 / maxi(1, _perf_ticks), _perf_ticks]
			+ "монстрів живих %d, не сплять %d" % [alive, awake])
	_perf_sum = 0
	_perf_ticks = 0
	_perf_next = now + 60.0


func _physics_process(delta: float) -> void:
	if Net.is_server:
		var tick_from := Time.get_ticks_usec()
		for a in creatures.values():
			a.server_step(delta)
		for id in creatures:
			if id < 0:
				# Прикликаний думає сам (`Summons.tick`), не як монстр.
				if not summons.is_summon(id):
					mobs.think(id, delta)
			else:
				actions.pump(id)
		combat.tick_casts(delta)
		for id in combat.clear_corpses():
			remove(id)
		spawner.tick(delta)
		_tick_shrines(delta)
		if life != null:
			for at: int in life.tick(delta):
				close_dungeon(at)
		_tick_clearing(delta)
		_tick_grace_places()
		_tick_water(delta)
		_tick_trade(delta)
		summons.tick(delta)
		_tick_range(delta)
		if store != null and store.due(delta):
			_save_everyone()
		# Числа правляться в data/*.json під час гри: помітив зміну —
		# роздав живим монстрам (крок 1.2).
		if data.poll(delta):
			print("[дані] нові числа роздано монстрам: %d"
					% spawner.apply_tuning())
		_perf_tick(Time.get_ticks_usec() - tick_from)
		return

	# Без живого з'єднання номера немає, і питати його — помилка в журнал
	# ЩОКАДРУ. На порожньому сервері таких рядків набігло 6801 за хвилину,
	# і серед них не було видно нічого іншого.
	if not Net.connected():
		return
	var me: Node = creatures.get(multiplayer.get_unique_id())
	if me != null and me.is_local:
		rpc_id(1, "submit_intent", me.sample_intent())


func _process(delta: float) -> void:
	if not Net.is_server:
		view.smooth(delta)
		view.approach(delta)
		view.demo(delta)
		_since_stream += delta
		if _since_stream >= 1.0 / STREAM_HZ:
			_since_stream = 0.0
			var me: Node = creatures.get(multiplayer.get_unique_id())
			var land: Node = get_node_or_null("Landscape")
			if me != null and land != null:
				land.stream_to(me.global_position)
		return

	_since_tick += delta
	if _since_tick < 1.0 / TICK_HZ:
		return
	_since_tick = 0.0

	for peer in multiplayer.get_peers():
		_serve(peer)
		_serve_self(peer)


## Що бачить одне з'єднання. Поява й зникнення йдуть надійним каналом,
## позиції — ненадійним: загублений пакет позицій це смикання на кадр, а
## загублена поява це вічний привид.
func _serve(peer: int) -> void:
	var diff := vision.update(peer)
	for id in diff["appeared"]:
		var other: Node3D = creatures[id]
		rpc_id(peer, "client_spawn", id, other.global_position,
				other.facing, _kind_of(other), _names.get(id, ""),
				other.level, other.sex, other.race, look_of(other))
		# Смуга здоров'я цілі мусить знати, скільки його всього.
		rpc_id(peer, "client_vitals", id, other.hp, other.stats.max_hp())
	for id in diff["gone"]:
		rpc_id(peer, "client_despawn", id)
	rpc_id(peer, "client_positions", diff["snapshot"])


## Свої числа: здоров'я, мана, відкат, замах і черга. Йдуть щотіку й
## ненадійним каналом — загублений пакет це кадр застарілого показу.
func _serve_self(peer: int) -> void:
	var me: Node = creatures.get(peer)
	if me == null:
		return
	rpc_id(peer, "client_self", me.hp, me.stats.max_hp(), me.mp,
			me.stats.max_mp(), _slot_cooldowns(me), me.busy_in,
			PackedStringArray(me.queue), me.level, me.respect,
			combat.progress.need_for(me.level, me.race, me.sex))
	# Стати шлемо не щотіку, а коли вони справді змінились: рівень, речі,
	# баф. Відбиток дешевий — п'ять чисел, рівень і похідні: баф
	# священика множить атаку, захист і швидкість, не чіпаючи статів, і
	# без них вікно не бачило ні його появи, ні кінця.
	var mark := "%d/%d/%d/%d/%d/%d/%d/%d/%.2f/%.2f/%.2f" % [me.level,
			me.stat_points, me.stats.strength, me.stats.agility,
			me.stats.stamina, me.stats.intellect, me.stats.sense,
			me.stats.max_hp(), me.stats.physical_attack(),
			me.stats.physical_defence(), me.stats.move_speed()]
	if _stats_mark.get(peer, "") != mark:
		_stats_mark[peer] = mark
		send_stats(peer)
	# Те саме для вивченого: руна або новий рівень скіла мають одразу
	# з'явитись у вікні «Скіли».
	var learned_mark := str(me.learned)
	if _skills_mark.get(peer, "") != learned_mark:
		_skills_mark[peer] = learned_mark
		send_skills(peer)
	# І для торби: здобич падає в бою, і вікно речей має це побачити без
	# перевідкривання.
	var bag_mark := "%d/%s/%s" % [me.things.size(), me.items, me.gear]
	if _bag_mark.get(peer, "") != bag_mark:
		_bag_mark[peer] = bag_mark
		send_things(peer)
	# Бафи й дебафи — свої й цілі (замовник 13.09.2026: «хочу бачити, на
	# кого я наклав баф»). Лише коли змінились; секунди в відбитку цілі,
	# тож поки стан тикає — раз на секунду, а не двадцять.
	var target_id: int = me.target_id
	var target: Node = creatures.get(target_id) if target_id != 0 else null
	if target == null or not vision.sees(peer, target_id):
		target = null
		target_id = 0
	var mine := states_row(me)
	var theirs := states_row(target) if target != null else []
	var states_mark := "%s|%d|%s" % [mine, target_id, theirs]
	if _states_mark.get(peer, "") != states_mark:
		_states_mark[peer] = states_mark
		rpc_id(peer, "client_states", mine, target_id, theirs)


## Стани істоти рядками для клієнта: назва, стат, множник, секунд
## лишилось і всього (-1 — «поки живий», як баф монстра при появі).
## Статична — щоб проба кликала без світу й мережі.
static func states_row(who: Node) -> Array:
	var row: Array = []
	for state: State in who.states.all():
		var forever := state.is_forever()
		row.append([state.name, state.stat, snappedf(state.factor, 0.01),
				-1 if forever else ceili(state.left),
				-1 if forever else ceili(state.full)])
	row.sort_custom(func(a: Array, b: Array) -> bool:
			return str(a[0]) < str(b[0]))
	return row


## Скільки лишилось відкату на кожній комірці панелі. Рахує сервер, бо
## тільки він знає відкати; HUD лише малює.
func _slot_cooldowns(me: Node) -> PackedFloat32Array:
	var left := PackedFloat32Array()
	for action: String in me.bar:
		if action == "attack":
			left.append(me.attack_ready_in)
		elif action.begins_with(Actions.SKILL_PREFIX):
			left.append(me.skill_ready_in.get(
					action.substr(Actions.SKILL_PREFIX.length()), 0.0))
		else:
			left.append(0.0)
	return left


# ── сервер: що надходить від клієнтів ─────────────────────────────────

## Сервер називає свій світ. Клієнт звіряє зі своїм і, якщо не збіглось,
## кричить — і в консоль, і рядком у грі.
@rpc("authority", "call_remote", "reliable")
func client_which_world(server_map: String) -> void:
	var mine := GameData.map_path().get_file()
	if server_map == mine:
		print("[світ] сервер і клієнт в одному світі: %s" % mine)
		return
	var shout := "‼ РІЗНІ СВІТИ: сервер будує %s, клієнт %s. " \
			% [server_map, mine] \
			+ "Прапорець --світ2 треба давати ОБОМ. Гравець провалиться " \
			+ "крізь землю, бо позицію рахують по іншому рельєфу."
	print("[світ] " + shout)
	push_error(shout)
	if hud != null and hud.has_method("notice"):
		hud.notice("‼ різні світи: сервер %s, клієнт %s" % [server_map, mine])
	# Сервер головний (P1): у чужому рельєфі гравець під землею, і навіть
	# «повернутися в місто» ставить його в місто ЧУЖОГО світу — виходу
	# немає (слово замовника 11.09.2026). Тож не лишаємо його там, а
	# перезапускаємо клієнт у світі сервера.
	var user := Array(OS.get_cmdline_user_args())
	user.erase("--світ2")
	if server_map == GameData.MAP2_PATH.get_file():
		user.append("--світ2")
	var engine := Array(OS.get_cmdline_args())
	var cut := engine.find("--")
	if cut >= 0:
		engine = engine.slice(0, cut)
	# Шлях до гри — явно: рушій не повертає `--path` серед своїх
	# аргументів, і без нього перезапущений клієнт, піднятий з кореня
	# репозиторію (`run.sh`), відкрив би менеджер проєктів, а не гру.
	if not engine.has("--path"):
		engine = ["--path", ProjectSettings.globalize_path("res://")] + engine
	print("[світ] перезапускаю клієнт у світі сервера (%s). Щоб грати в "
			% server_map + "іншому — зупини сервер на стартовій сторінці й "
			+ "підніми знову з потрібним світом")
	OS.set_restart_on_exit(true, PackedStringArray(engine + ["--"] + user))
	get_tree().quit()


## Увійти в гру без бази: як було до кроку 5. Якщо база є, цей шлях
## закритий — інакше можна було б зайти чужим персонажем, назвавши ім'я.
@rpc("any_peer", "call_remote", "reliable")
func announce_ready(character: String = "") -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	# Перше, що чує клієнт: у ЯКОМУ світі сервер. Прапорець `--світ2`
	# треба давати обом, і коли його забули на одному боці, клієнт малює
	# один світ, а сервер рахує інший — гравець провалюється крізь землю,
	# монстри тонуть, а в журналі все зелене. Спіймано 05.09.2026 живою
	# грою; мовчки такі речі не лишаємо (P3).
	rpc_id(id, "client_which_world", GameData.map_path().get_file())
	if store != null and store.works():
		rpc_id(id, "client_sign_needed")
		return
	_names[id] = character if character != "" else "Гравець-%d" % id
	_on_joined(id)


## Крок 5: вхід за акаунтом. Пароль перевіряє сама база (bcrypt), сервер
## гри його не знає й не зберігає ніде, крім пам'яті сеансу.
@rpc("any_peer", "call_remote", "reliable")
func sign_in(login: String, password: String, register: bool = false) -> void:
	if not Net.is_server or store == null or not store.works():
		return
	var id := multiplayer.get_remote_sender_id()
	if creatures.has(id):
		return                       # уже в грі — удруге входити нема куди
	store.answered.connect(func(name: String, reply: Dictionary) -> void:
			if not multiplayer.get_peers().has(id):
				return
			if not bool(reply.get("ok", false)):
				rpc_id(id, "client_sign_failed",
						str(reply.get("why", "не вдалось")))
				return
			_signed[id] = {"логін": login, "пароль": password,
					"персонажі": reply.get("characters", [])}
			rpc_id(id, "client_characters",
					JSON.stringify(_signed[id]["персонажі"]))
			print("[акаунт] %s увійшов, персонажів %d"
					% [login, _signed[id]["персонажі"].size()]),
			CONNECT_ONE_SHOT)
	# Світ передаємо завжди: база віддає перелік персонажів лише того
	# світу, у якому стоїть ЦЕЙ сервер (П-204). `register` світу не
	# знає — новий акаунт однаково без персонажів.
	store.call_rpc("register" if register else "login",
			{"login": login, "password": password,
			"world": GameData.world_key()})


## Створити персонажа на своєму акаунті.
@rpc("any_peer", "call_remote", "reliable")
func create_character(name: String, race: String, sex: String) -> void:
	if not Net.is_server or store == null:
		return
	var id := multiplayer.get_remote_sender_id()
	if not _signed.has(id):
		return
	var who: Dictionary = _signed[id]
	store.answered.connect(func(_rpc: String, reply: Dictionary) -> void:
			if not bool(reply.get("ok", false)):
				rpc_id(id, "client_sign_failed",
						str(reply.get("why", "не вдалось")))
				return
			who["персонажі"].append({"name": name, "level": 1,
					"race": race, "sex": sex})
			rpc_id(id, "client_characters", JSON.stringify(who["персонажі"]))
			print("[акаунт] %s створив персонажа %s" % [who["логін"], name]),
			CONNECT_ONE_SHOT)
	store.call_rpc("new_character", {"login": who["логін"],
			"password": who["пароль"], "name": name, "race": race,
			"sex": sex, "world": GameData.world_key()})


## Обрати персонажа й нарешті зайти у світ.
@rpc("any_peer", "call_remote", "reliable")
func enter_world(character: String) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if not _signed.has(id) or creatures.has(id):
		return
	# Чужим персонажем не зайти: беремо лише з переліку свого акаунта.
	var mine := false
	for who: Dictionary in _signed[id]["персонажі"]:
		if str(who.get("name", "")) == character:
			mine = true
			break
	if not mine:
		rpc_id(id, "client_sign_failed", "це не твій персонаж")
		return
	_names[id] = character
	_on_joined(id)


## Зберегти всіх, хто в грі. Викликається раз на 30 секунд і при виході.
func _save_everyone() -> void:
	for id in _names:
		_save_one(id)


func _save_one(id: int) -> void:
	var who: Node = creatures.get(id)
	if who == null or store == null:
		return
	store.save_character(_names[id], Store.row_of(_names[id], who))


@rpc("any_peer", "call_remote", "unreliable_ordered")
func submit_intent(intent: Vector2) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if creatures.has(id):
		creatures[id].wanted = intent


@rpc("any_peer", "call_remote", "reliable")
func select_target(id: int) -> void:
	if Net.is_server:
		actions.pick_target(multiplayer.get_remote_sender_id(), id)


## Удар мишею — не через панель, щоб не залежати від її розкладки.
@rpc("any_peer", "call_remote", "reliable")
func strike() -> void:
	if Net.is_server:
		actions.enqueue(multiplayer.get_remote_sender_id(), "attack")


## Натиснута комірка панелі.
## `shift` за П-45 перемикає перебір цілей на трупи.
@rpc("any_peer", "call_remote", "reliable")
func use_slot(slot: int, shift: bool = false) -> void:
	if Net.is_server:
		actions.use_slot(multiplayer.get_remote_sender_id(), slot, shift)


## Дії, які можна класти на панель без жодного вивчення: вони є в усіх.
const BASIC_SLOTS: Array[String] = ["", "attack", "next_player", "next_mob",
		"next_player_corpse", "next_mob_corpse", "corpse_skill", "taunt",
		"sit"]


## Перекласти комірку панелі (перетягуванням у вікні «Скіли»).
##
## Перевіряє СЕРВЕР: інакше будь-хто поклав би собі скіл, якого не вчив, і
## диспетчер узяв би його за чисту монету.
@rpc("any_peer", "call_remote", "reliable")
func set_slot(slot: int, action: String) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var a: Node = creatures.get(id)
	if a == null or slot < 0 or slot >= a.bar.size():
		return
	if not a.slot_open(slot):
		link.notice(id, "ця смуга панелі закрита — потрібен кращий ремінь")
		return
	var allowed := bar_allows(a, action)
	if not allowed:
		link.notice(id, "цього на панель не покласти")
		return
	a.bar[slot] = action
	_send_bar(id)


## Чи можна покласти дію на панель: базова, вивчений скіл або річ, яку
## можна вжити.
func bar_allows(a: Node, action: String) -> bool:
	var allowed: bool = action in BASIC_SLOTS
	if not allowed and action.begins_with(Actions.SKILL_PREFIX):
		allowed = a.knows(action.substr(Actions.SKILL_PREFIX.length()))
	# Річ, яку можна вжити (зілля, кристал): на панель — щоб пити в бою,
	# не відкриваючи торби (слово замовника 19.09.2026). Наявність не
	# вимагається: комірка лишається, коли зілля скінчилось, і вживання
	# саме скаже «немає».
	if not allowed and action.begins_with(Actions.ITEM_PREFIX):
		allowed = not data.items.base_of(action.substr(
				Actions.ITEM_PREFIX.length())).get("дія", {}).is_empty()
	return allowed


## «Повернутися в місто» з вікна смерті.
##
## Робить рівно те саме, що зробив би строк у двадцять хвилин, тільки
## зараз: те саме здоров'я, те саме місце. Живому це нічого не дає —
## `combat.revive` відмовить, тож телепортом додому воно не стане.
@rpc("any_peer", "call_remote", "reliable")
func ask_revive() -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if combat.revive(id):
		print("[світ] %d повернувся в місто" % id)


## Під водою (П-61). Рівень моря знає краєвид — він його й будував.
func _tick_water(delta: float) -> void:
	var land: Node = get_node_or_null("Landscape")
	if land == null or not land.has_method("sea_level"):
		return
	var sea: float = land.sea_level()
	var sea_data: Dictionary = data.map.get("море", {})
	var holds: float = float(sea_data.get("дихання", 25.0))
	var harm: float = float(sea_data.get("шкода за секунду", 0.04))
	for id in creatures:
		var who: Node = creatures[id]
		# Під водою вважається той, у кого голова нижче поверхні.
		var under: bool = who.global_position.y + 0.9 < sea
		var was_breath: float = who.breath
		if who.breathe(delta, under, holds, harm):
			link.notice(id, "захлинаєшся!")
			if not who.is_alive():
				print("[море] %d утонув" % id)
				_link_death(id, who)
		elif under and was_breath > 0.0 and who.breath <= 0.0:
			link.notice(id, "повітря скінчилось")


## Смерть без убивці: утоплення. Труп і втрати ті самі, що й у бою.
func _link_death(id: int, who: Node) -> void:
	who.die()
	link.to_watchers(id, &"client_died", [id])
	if id > 0:
		var lost: int = combat.progress.death_loss(who)
		link.notice(id, "втрачено %d поваги" % lost)


## Святині (П-153): «зачищено» — це нуль живих у кільці охорони. Стан
## рахує СЕРВЕР і шле номером; клієнт лише показує (П-08).
##
## Не щокадру: святинь тридцять із гаком, а міняється стан рідко —
## рівно тоді, коли впав останній охоронець.
const SHRINE_CHECK := 1.0

var _shrine_clock := 0.0
## Номер святині -> стан, який уже надіслано. Щоб не слати те саме.
var _shrine_sent: Dictionary = {}


func _tick_shrines(delta: float) -> void:
	_shrine_clock -= delta
	if _shrine_clock > 0.0:
		return
	_shrine_clock = SHRINE_CHECK
	var land: Node = get_node_or_null("Landscape")
	if land == null or not land.has_method("shrines"):
		return
	var all: Array = land.shrines()
	for i in all.size():
		var shrine: Shrine = all[i]
		# Активовану не чіпаємо: назад в «під охороною» її вертає лише
		# закриття підземелля (`close_dungeon`, Ф7).
		if shrine.stage == Shrine.Stage.АКТИВОВАНА:
			continue
		# Купок охорони кілька (главар і помічники в кожній,
		# 20.09.2026), тож живих рахуємо по ВСІХ зонах святині — інакше
		# «зачищено» вмикалось би від однієї вибитої купки, і портал
		# відкривався б повз решту охорони.
		var zones: Array = shrine.find_children("*", "MobZone", false,
				false)
		if zones.is_empty():
			continue
		var alive := 0
		for zone: Node in zones:
			alive += spawner.alive_in(zone)
		var stage: int = Shrine.Stage.ПІД_ОХОРОНОЮ \
				if alive > 0 else Shrine.Stage.ЗАЧИЩЕНА
		if int(_shrine_sent.get(i, -1)) == stage:
			continue
		_shrine_sent[i] = stage
		shrine.set_stage(stage)
		link.to_all(&"client_shrine", [i, stage])


## Наскільки близько треба підійти, щоб активувати святиню. Та сама
## дальність, що й розмова з мешканцем: більше однієї міри «підійшов» у
## грі бути не повинно.
const SHRINE_REACH := Shop.TALK_RANGE


## Активувати святиню ключем (П-153).
##
## Усе рахує СЕРВЕР (П-08): і відстань, і те, чи зачищено охорону, і чи
## є ключ потрібного грейду. Клієнт лише просить — інакше активація
## була б найкоротшим шляхом до безкоштовного підземелля.
@rpc("any_peer", "call_remote", "reliable")
func ask_activate(at: int) -> void:
	if not Net.is_server:
		return
	activate_shrine(multiplayer.get_remote_sender_id(), at)


## Те саме без мережі — щоб перевірялось пробою.
##
## Виносити тіло з `@rpc` у звичайний метод довелось не з любові до
## чистоти: `get_remote_sender_id()` поза справжнім викликом дає 0, і
## проба перевіряла порожнечу, думаючи, що все гаразд (спіймано
## 05.09.2026 — чотири «зелені» кроки насправді нічого не робили). Той
## самий урок, що вже змусив винести бій із `world.gd`.
func activate_shrine(id: int, at: int) -> void:
	var a: Node = creatures.get(id)
	var land: Node = get_node_or_null("Landscape")
	if a == null or land == null or not land.has_method("shrines"):
		return
	var all: Array = land.shrines()
	if at < 0 or at >= all.size():
		return
	var shrine: Shrine = all[at]
	if a.global_position.distance_to(shrine.global_position) > SHRINE_REACH:
		link.notice(id, "святиня задалеко")
		return
	if shrine.stage == Shrine.Stage.АКТИВОВАНА:
		link.notice(id, "святиня вже відкрита")
		return
	if shrine.stage != Shrine.Stage.ЗАЧИЩЕНА:
		link.notice(id, "спершу зачисти охорону святині")
		return
	var key := "ключ святині %s" % shrine.grade
	if int(a.items.get(key, 0)) <= 0:
		# Дослівно те, що просив замовник у П-153.
		link.notice(id, "немає ключа відповідного рівня")
		return
	a.items[key] = int(a.items[key]) - 1
	if int(a.items[key]) <= 0:
		a.items.erase(key)
	shrine.set_stage(Shrine.Stage.АКТИВОВАНА)
	_shrine_sent[at] = Shrine.Stage.АКТИВОВАНА
	link.to_all(&"client_shrine", [at, Shrine.Stage.АКТИВОВАНА])
	if life != null:
		life.activated(at, shrine.grade)
		link.to_all(&"client_dungeon_days", [at, life.days_left(at)
				* DungeonLife.DAY, shrine.grade])
	link.notice(id, "святиня активована: %s відкрито портал на %.0f днів"
			% [shrine.grade, life.days_open() if life != null else 0.0])
	_after_bag(id, a)


## Розповісти новому гравцеві, які святині вже зачищені чи відкриті.
##
## Без цього той, хто зайшов пізніше, бачив би світ, якого немає: сервер
## шле лише ЗМІНИ стану, а зміни сталися до його приходу. Спіймано на
## живому прогоні 05.09.2026 — не пробою, а міркуванням про те, що
## станеться з другим гравцем.
func _tell_shrines(peer: int) -> void:
	var land: Node = get_node_or_null("Landscape")
	if land == null or not land.has_method("shrines"):
		return
	var all: Array = land.shrines()
	for i in all.size():
		var shrine: Shrine = all[i]
		if shrine.stage == Shrine.Stage.ПІД_ОХОРОНОЮ:
			continue      # це і є стан за замовчуванням у клієнта
		link.to_one(peer, &"client_shrine", [i, shrine.stage])
		if life != null and life.records.has(i):
			link.to_one(peer, &"client_dungeon_days",
					[i, life.days_left(i) * DungeonLife.DAY, shrine.grade])


## Стан святині: зачищено її чи ще ні (П-153).
@rpc("authority", "call_remote", "reliable")
func client_shrine(at: int, stage: int) -> void:
	var land: Node = get_node_or_null("Landscape")
	if land == null or not land.has_method("shrines"):
		return
	var all: Array = land.shrines()
	if at < 0 or at >= all.size():
		return
	all[at].set_stage(stage)


## Портал святині веде в підземелля (П-190, Ф4′). Коло порталу плюс 4 м:
## було плюс 1, і замовник 13.09.2026 двічі дістав «портал задалеко» —
## поки вікно запрошення стояло відкрите, персонаж ішов далі за кліком і
## виходив із кола. Тепер клієнт ще й зупиняє його на запрошенні.
const PORTAL_REACH := Portal.RING + 4.0


## Увійти в підземелля за порталом святині `at`.
@rpc("any_peer", "call_remote", "reliable")
func ask_enter_dungeon(at: int) -> void:
	if not Net.is_server:
		return
	enter_dungeon(multiplayer.get_remote_sender_id(), at)


## Те саме без мережі — щоб перевірялось пробою (див. `activate_shrine`).
##
## Перше входження ВІДКРИВАЄ підземелля: шаблон із бібліотеки з вагами
## статів того, хто відкрив (П-191), скільки рівнів — теж від його сили
## (Ф5′), зерно, заселення за грейдом святині. Далі будь-хто заходить у
## те саме, доки воно стоїть: «відкрити й зачистити можуть різні гравці»
## (П-153).
func enter_dungeon(id: int, at: int) -> void:
	var a: Node = creatures.get(id)
	var land: Node = get_node_or_null("Landscape")
	if a == null or not a.is_alive() or land == null \
			or not land.has_method("shrines"):
		return
	var all: Array = land.shrines()
	if at < 0 or at >= all.size():
		return
	var shrine: Shrine = all[at]
	var gate: Portal = shrine.portal()
	if shrine.stage != Shrine.Stage.АКТИВОВАНА or gate == null:
		link.notice(id, "портал не відкрито")
		return
	var flat := Vector2(a.global_position.x - gate.global_position.x,
			a.global_position.z - gate.global_position.z).length()
	if flat > PORTAL_REACH:
		link.notice(id, "портал задалеко")
		return
	var first := Dungeons.key(at, 0)
	if not dungeons.open.has(first):
		var power := DungeonBook.power_of(a)
		var depth := dungeons.book.depth_for(power)
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var template := dungeons.book.pick_weighted(rng, power, 0)
		var with_seed := rng.randi() % 1000000000
		if not _raise_level(at, 0, template, with_seed, shrine.grade,
				depth):
			link.notice(id, "‼ підземелля не збудувалось")
			return
		if life != null:
			life.built(at, template, with_seed, depth, power)
	_arrive(id, a, first)


## Збудувати рівень `level` підземелля святини `at`, заселити й сказати
## всім клієнтам. `with_boss` — false, коли бос цього рівня вже вбитий.
func _raise_level(at: int, level: int, template: String, with_seed: int,
		grade: String, depth: int, with_boss: bool = true) -> bool:
	var key := Dungeons.key(at, level)
	if dungeons.raise(key, template, with_seed, grade, depth).is_empty():
		return false
	spawner.add_zones(dungeons.zones_for(key, data.mobs, with_boss))
	link.to_all(&"client_dungeon", [key, template, with_seed, grade, depth])
	return true


## Поставити гравця на вхід рівня `key` і сказати, де він.
func _arrive(id: int, a: Node, key: int) -> void:
	var entry: Dictionary = dungeons.open[key]
	a.place_at(dungeons.entry_point(key), 0.0)
	link.to_watchers(id, &"client_place", [id, a.global_position, a.facing])
	link.to_one(id, &"client_place", [id, a.global_position, a.facing])
	link.notice(id, "підземелля «%s» · ворота %s · рівень %d з %d"
			% [entry["plan"].title, entry["grade"],
			   Dungeons.level_of(key) + 1, int(entry["depth"])])


## Спуститися порталом «Далі» (Ф5′/Ф6): він запалюється в палаті боса,
## щойно бос повалений. Наступний рівень будується першим, хто спустився,
## — з вагами сили того, хто ВІДКРИВ підземелля (вона збережена), тож і
## після перезапуску вийде той самий розклад складності.
@rpc("any_peer", "call_remote", "reliable")
func ask_descend(key: int) -> void:
	if not Net.is_server:
		return
	descend(multiplayer.get_remote_sender_id(), key)


func descend(id: int, key: int) -> void:
	var a: Node = creatures.get(id)
	if a == null or not a.is_alive() or not dungeons.open.has(key):
		return
	var entry: Dictionary = dungeons.open[key]
	var down: Portal = entry["down"]
	if down == null or not is_instance_valid(down):
		link.notice(id, "прохід далі ще закритий — спершу бос")
		return
	var flat := Vector2(a.global_position.x - down.global_position.x,
			a.global_position.z - down.global_position.z).length()
	if flat > PORTAL_REACH:
		link.notice(id, "прохід задалеко")
		return
	var at := Dungeons.shrine_of(key)
	var next := Dungeons.level_of(key) + 1
	var depth := int(entry["depth"])
	if next >= depth:
		return
	var below := Dungeons.key(at, next)
	if not dungeons.open.has(below):
		var power: int = int(life.records.get(at, {}).get("power",
				DungeonBook.power_of(a))) if life != null \
				else DungeonBook.power_of(a)
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var template := dungeons.book.pick_weighted(rng, power, next)
		var with_seed := rng.randi() % 1000000000
		if not _raise_level(at, next, template, with_seed, entry["grade"],
				depth):
			link.notice(id, "‼ рівень не збудувався")
			return
		if life != null:
			life.built_level(at, next, template, with_seed)
	_arrive(id, a, below)


## Вийти з підземелля — з кола «Вихід» назад до святині. «Вихід» є на
## кожному рівні.
@rpc("any_peer", "call_remote", "reliable")
func ask_leave_dungeon() -> void:
	if not Net.is_server:
		return
	leave_dungeon(multiplayer.get_remote_sender_id())


func leave_dungeon(id: int) -> void:
	var a: Node = creatures.get(id)
	if a == null or not a.is_alive():
		return
	var key := dungeons.index_at(a.global_position.x, a.global_position.z)
	if key < 0:
		return
	var exit: Portal = dungeons.open[key]["exit"]
	var flat := Vector2(a.global_position.x - exit.global_position.x,
			a.global_position.z - exit.global_position.z).length()
	if flat > PORTAL_REACH:
		link.notice(id, "вихід задалеко")
		return
	a.place_at(_beside_shrine(Dungeons.shrine_of(key)), 0.0)
	link.to_watchers(id, &"client_place", [id, a.global_position, a.facing])
	link.notice(id, "повернувся до святині")


## Поруч із колом порталу святині, а не в ньому: інакше одразу знову
## «увійти?».
func _beside_shrine(at: int) -> Vector3:
	var land: Node = get_node_or_null("Landscape")
	var shrine: Shrine = land.shrines()[at]
	var gate: Portal = shrine.portal()
	var from: Vector3 = gate.global_position if gate != null \
			else shrine.global_position
	var back := from + Vector3(0.0, 0.0, Portal.RING + 2.0)
	back.y = ground_at(back.x, back.z) + 1.0
	return back


## Скільки секунд підземелля стоїть після зачистки, перш ніж закритись:
## щоб гравці встигли забрати здобич. Число виконавця.
const CLEAR_AFTER := 60.0
## Святиня -> скільки секунд лишилось до закриття зачищеного.
var _clearing: Dictionary = {}


## Убивця отримав своє (кличе `combat._reward`). Тут ведеться рахунок
## убитих: його просять і квести переходу між професіями, і гілки, що
## відкриваються полюванням (П-224).
func _on_reward(me: int, killer: Node, victim: Node) -> void:
	var species := str(data.for_kind(int(victim.kind)).get("назва", ""))
	if species == "":
		return
	killer.kills[species] = int(killer.kills.get(species, 0)) + 1
	_check_branches(me, killer)


## Чи не відкрилась щойно прихована гілка. Дивимось після кожного
## вбивства (там і рахунок, і здобич з амулетом) і щоразу, як гравець
## відчинив гільдію: амулет міг прийти обміном або з крамниці.
func _check_branches(id: int, a: Node) -> void:
	for title: String in data.professions.open_ready(a):
		link.notice(id, "відкрито приховану гілку: %s" % title)
		print("[професії] %d відкрив гілку «%s»" % [id, title])


## Хтось загинув (кличе `combat._kill`). Цікавить лише бос рівня
## підземелля (Ф6): його смерть — прохід далі або, на останньому рівні,
## зачистка всього підземелля.
func _on_kill(victim_id: int, victim: Node) -> void:
	if victim_id >= 0 or not victim.get("is_boss"):
		return
	var key := dungeons.index_at(victim.global_position.x,
			victim.global_position.z)
	if key < 0:
		return
	var entry: Dictionary = dungeons.open[key]
	for zone: Node in entry["zones"]:
		if zone is MobZone and zone.boss:
			zone.spent = true
	var at := Dungeons.shrine_of(key)
	var level := Dungeons.level_of(key)
	var depth := int(entry["depth"])
	if life != null:
		life.boss_down(at, level)
	if level + 1 < depth:
		dungeons.light_down(key)
		link.to_all(&"client_dungeon_down", [key])
		_tell_inside(at, "бос повалений — у його палаті відкрився прохід "
				+ "на рівень %d з %d" % [level + 2, depth])
	else:
		_clearing[at] = CLEAR_AFTER
		_tell_inside(at, "останній бос повалений — підземелля зачищено! "
				+ "За %.0f с воно закриється, без штрафу" % CLEAR_AFTER)


## Сказати всім гравцям, що зараз у підземеллі святині `at`.
func _tell_inside(at: int, text: String) -> void:
	for id: int in creatures:
		var a: Node3D = creatures[id]
		if id <= 0:
			continue
		var key := dungeons.index_at(a.global_position.x, a.global_position.z)
		if key >= 0 and Dungeons.shrine_of(key) == at:
			link.notice(id, text)


func _tick_clearing(delta: float) -> void:
	for at: int in _clearing.keys():
		_clearing[at] -= delta
		if _clearing[at] <= 0.0:
			_clearing.erase(at)
			_shut(at, false)


## Підземелля, відкрите до перезапуску сервера (Ф7): святиня знову
## світиться відкритою, а якщо в нього вже заходили — стоять ті самі
## рівні з тими самими шаблонами й зернами; де бос уже вбитий, його
## немає, а прохід далі горить.
func _restore_dungeon(at: int, record: Dictionary) -> void:
	var land: Node = get_node_or_null("Landscape")
	if land == null or not land.has_method("shrines") \
			or at < 0 or at >= land.shrines().size():
		print("[підземелля] ‼ святині %d у цьому світі немає" % at)
		return
	var shrine: Shrine = land.shrines()[at]
	shrine.set_stage(Shrine.Stage.АКТИВОВАНА)
	_shrine_sent[at] = Shrine.Stage.АКТИВОВАНА
	var template := str(record["template"])
	if template == "":
		return
	var depth := int(record.get("depth", 1))
	var cleared := int(record.get("cleared", 0))
	if cleared >= depth:
		# Зачищене, але закритись не встигло — закриваємо тепер.
		_shut(at, false)
		return
	var levels: Array = record.get("levels", [])
	if levels.is_empty():
		levels = [{"template": template, "seed": int(record["seed"])}]
	for level in levels.size():
		var one: Dictionary = levels[level]
		if not _raise_level(at, level, str(one["template"]),
				int(one["seed"]), str(record["grade"]), depth,
				level >= cleared):
			return
		if level < cleared:
			dungeons.light_down(Dungeons.key(at, level))


## Строк минув (Ф7, П-153): бос не вбитий — підземелля закривається зі
## штрафом світу.
func close_dungeon(at: int) -> void:
	_shut(at, true)


## Закрити підземелля святині `at` з усіма рівнями: хто всередині —
## до святині, святиня знову під охороною. `penalty` — строк минув
## (штраф світу, Ф7); без нього — зачищено (Ф6).
func _shut(at: int, penalty: bool) -> void:
	var levels := dungeons.levels_of(at)
	var title := "за святинею %d" % at
	if not levels.is_empty():
		title = "«%s»" % dungeons.open[levels[0]]["plan"].title
		var back := _beside_shrine(at)
		for id: int in creatures.keys():
			var a: Node3D = creatures[id]
			if id <= 0:
				continue
			var key := dungeons.index_at(a.global_position.x,
					a.global_position.z)
			if key < 0 or Dungeons.shrine_of(key) != at:
				continue
			a.place_at(back, 0.0)
			link.to_watchers(id, &"client_place",
					[id, a.global_position, a.facing])
			link.to_one(id, &"client_place",
					[id, a.global_position, a.facing])
		for key: int in levels:
			spawner.drop_zones(dungeons.open[key]["zones"])
		dungeons.close(at)
		link.to_all(&"client_dungeon_closed", [at])
	if life != null:
		if penalty:
			life.expire(at)
		else:
			life.clear(at)
	_clearing.erase(at)
	var land: Node = get_node_or_null("Landscape")
	if land != null and land.has_method("shrines") \
			and at >= 0 and at < land.shrines().size():
		land.shrines()[at].set_stage(Shrine.Stage.ПІД_ОХОРОНОЮ)
		_shrine_sent[at] = Shrine.Stage.ПІД_ОХОРОНОЮ
		link.to_all(&"client_shrine", [at, Shrine.Stage.ПІД_ОХОРОНОЮ])
	link.to_all(&"client_dungeon_days", [at, -1.0, ""])
	var text := ""
	if penalty:
		for id: int in creatures:
			if id < 0:
				penalize(creatures[id])
		text = "підземелля %s закрилось: бос не вбитий за %.0f днів — " \
				% [title, life.days_open()] \
				+ "світ під штрафом на %.0f днів, монстри сильніші" \
				% life.days_penalty()
	else:
		text = "підземелля %s зачищено й закрилось" % title
	print("[підземелля] " + text)
	for id: int in creatures:
		if id > 0:
			link.notice(id, text)


## Повісити на монстра чинні штрафи світу (Ф7) і, в глибоких рівнях
## підземелля, «глибину» (Ф5′: що глибше, то сильніші). Той самий стан
## удруге не подвоюється — поновлює строк (П-108), тож кликати можна
## скільки завгодно.
func penalize(m: Node) -> void:
	var was: int = m.stats.max_hp()
	if life != null:
		for state: State in life.penalty_states():
			m.add_state(state)
	var key := dungeons.index_at(m.global_position.x, m.global_position.z) \
			if dungeons != null else -1
	var level := Dungeons.level_of(key) if key >= 0 else 0
	if level > 0:
		for one: Dictionary in dungeons.book.weights.get("глибина", []):
			var stat := str(one.get("стат", ""))
			m.add_state(State.new("глибина %d · %s" % [level, stat], stat,
					pow(float(one.get("множник", 1.0)), level), INF))
	# Здоров'я — тією самою часткою від нового максимуму: цілий монстр
	# лишається цілим (утричі товщим), поранений — так само пораненим.
	var now: int = m.stats.max_hp()
	if now != was and was > 0:
		m.hp = roundi(float(m.hp) * now / was)


## Розповісти новому гравцеві, які підземелля вже відкриті: сервер шле
## лише зміни, а ці сталися до його приходу (та сама пастка, що зі
## святинями).
func _tell_dungeons(peer: int) -> void:
	for key: int in dungeons.open:
		var entry: Dictionary = dungeons.open[key]
		link.to_one(peer, &"client_dungeon", [key, entry["template"],
				entry["seed"], entry["grade"], entry["depth"]])
		if entry["down"] != null:
			link.to_one(peer, &"client_dungeon_down", [key])


## Скільки лишилось підземеллю за святинею `at` (Ф8). Від'ємне —
## строку більше немає: підземелля закрилось.
@rpc("authority", "call_remote", "reliable")
func client_dungeon_days(at: int, seconds: float, grade: String) -> void:
	if seconds < 0.0:
		dungeon_days.erase(at)
		return
	dungeon_days[at] = {"until": Time.get_ticks_msec() + int(seconds * 1000.0),
			"grade": grade}


## Скільки днів лишилось за святинею, у клієнта; -1 — не відкрита.
func days_left(at: int) -> float:
	if not dungeon_days.has(at):
		return -1.0
	return maxf(0.0, (int(dungeon_days[at]["until"])
			- Time.get_ticks_msec()) / 1000.0 / DungeonLife.DAY)


## Раса, стать і що вдягнуто — змінились або щойно прочитані з бази.
@rpc("authority", "call_remote", "reliable")
func client_appearance(id: int, race: String, sex: String,
		look: Dictionary) -> void:
	var a: Node = creatures.get(id)
	if a == null or not a.has_method("apply_sex"):
		return
	a.apply_sex(sex, race)
	a.wear(look, data.items)


## Сервер закрив підземелля святині (Ф7/Ф6) — прибрати всі його рівні й
## у себе.
@rpc("authority", "call_remote", "reliable")
func client_dungeon_closed(at: int) -> void:
	dungeons.close(at)


## Бос рівня повалений — запалити в себе портал «Далі».
@rpc("authority", "call_remote", "reliable")
func client_dungeon_down(key: int) -> void:
	dungeons.light_down(key)


## Сервер відкрив рівень підземелля — клієнт будує те саме з тих самих
## чисел.
@rpc("authority", "call_remote", "reliable")
func client_dungeon(at: int, template: String, with_seed: int,
		grade: String, depth: int = 1) -> void:
	dungeons.raise(at, template, with_seed, grade, depth)


## Благодатні місця: зони, де відновлюють швидко (П-113). Перевіряємо
## щокадру — їх одиниці, а гравців десяток.
##
## Не плутати зі «святинею» (П-153) — точками-порталами в підземелля:
## одне українське слово раніше позначало обидва об'єкти, розведено
## 05.09.2026 (П-158).
## Благодатні місця стоять у сцені й не міняються. Шукати їх обходом
## УСЬОГО дерева щокадру — на світі 2 це 21 тисяча вузлів краєвиду й
## монстри — зайво; тепер раз на 5 с (300 кадрів фізики).
var _grace_places: Array = []
var _grace_found_at := -1000000


func _tick_grace_places() -> void:
	var frame := Engine.get_physics_frames()
	if frame - _grace_found_at >= 300:
		_grace_found_at = frame
		_grace_places = find_children("*", "GracePlace", true, false)
	var places := _grace_places
	if places.is_empty():
		return
	for id in creatures:
		if id < 0:
			continue
		var who: Node3D = creatures[id]
		var rate := 0.0
		for place: GracePlace in places:
			if not place.has_point(who.global_position):
				continue
			if who.in_fight > 0.0 and not place.in_fight:
				continue
			rate = maxf(rate, place.restore)
		if rate > 0.0 and who.in_grace <= 0.0:
			link.notice(id, "благодатне місце: тут відновлюєшся швидко")
		who.in_grace = rate


## Зони появи — вузли `MobZone` у сцені. Їх малюють у редакторі, тому
## сервер їх не вигадує, а знаходить.
## Звідки беруться зони появи.
##
## Версія 1 — вузли `MobZone` зі сцени: їхні межі зручніше тягнути
## мишею, і саме про це просив замовник. Версія 2 — з даних: сцена
## намальована під світ 600 м, і на 5632 м частина її зон опинялась у
## воді, а монстри тонули (журнал замовника 05.09.2026). Зони версії 2
## пораховані на справжньому рельєфі й перевірені на сухість по всьому
## колу — `tools/svit2.py`.
func _zones() -> Array:
	var from_data: Array = data.map.get("зони появи", [])
	if not from_data.is_empty():
		return _zones_from_data(from_data) + _shrine_zones()
	var found := find_children("*", "MobZone", true, false)
	if found.is_empty():
		push_warning("[світ] у сцені немає жодної зони появи — монстрів не буде")
		print("[світ] ‼ у сцені немає жодної зони появи")
	return found


## Зона з даних: те саме `MobZone`, тільки форма не намальована мишею,
## а зроблена тут — циліндр свого радіуса. Спавнер однаково ставить
## монстра на висоту землі, тож висота циліндра ні на що не впливає.
func _zones_from_data(list: Array) -> Array:
	var made: Array = []
	for one: Dictionary in list:
		var zone := MobZone.new()
		var at: Array = one.get("де", [0, 0, 0])
		zone.name = "ЗонаПояви%d" % (made.size() + 1)
		zone.position = Vector3(float(at[0]), 0.0, float(at[2]))
		zone.kind = int(one.get("вид", 1))
		zone.count = int(one.get("скільки", 1))
		zone.aggressive = bool(one.get("агресивний", false))
		zone.respawn_after = float(one.get("респавн", 12.0))
		zone.respawn_spread = float(one.get("розкид респавну", 4.0))
		var body := CollisionShape3D.new()
		var round_shape := CylinderShape3D.new()
		round_shape.radius = float(one.get("радіус", 20.0))
		round_shape.height = 4.0
		body.shape = round_shape
		zone.add_child(body)
		add_child(zone)
		made.append(zone)
	print("[світ] зони появи з даних: %d" % made.size())
	return made


## Охорона святинь (П-153) — теж `MobZone`, але не намальована в сцені
## й не записана серед «зон появи»: її ставить кільцем сам
## `landscape.gd`, дитиною святині. У версії 1 вона підбиралась разом з
## усіма зі сцени; у версії 2 зони беруться з даних, і без цього рядка
## святиня стояла б зовсім без охорони — тобто активувалась би без бою,
## а бій за неї і є вся її механіка.
##
## Намальовані в сцені зони сюди свідомо НЕ потрапляють: вони зроблені
## під світ 600 м, і саме через них монстри тонули на 5632 м.
func _shrine_zones() -> Array:
	var out: Array = []
	for one in find_children("*", "MobZone", true, false):
		if one.get_parent() is Shrine:
			out.append(one)
	if not out.is_empty():
		print("[світ] плюс охорона святинь: зон %d" % out.size())
	return out


func _on_joined(id: int) -> void:
	# 6 м запасу, як і в spawner.gd: падає сам, сідає на видиму поверхню.
	var a := spawn(id, Vector3(0, ground_at(0.0, 0.0) + 6.0, 0))
	_tell_shrines(id)
	_tell_dungeons(id)
	a.account = _signed.get(id, {}).get("логін", "")
	# Прочитане з бази накладається, щойно прийде відповідь: гра не жде
	# базу, а база не жде гру.
	if store != null and store.works():
		store.loaded.connect(func(name: String, row: Dictionary) -> void:
				if name != _names.get(id, "") or not creatures.has(id):
					return
				Store.apply_row(creatures[id], row, data.items)
				_rescue(creatures[id], name)
				# Стартові скіли даються ПІСЛЯ читання: інакше прочитане
				# з бази («скілів немає») затирає їх, і новий персонаж
				# заходить у світ ні з чим. Спіймано на живому прогоні.
				#
				# Доростають, а не лише роздаються порожньому: стартовий
				# перелік із часом поповнюється (так з'явилось
				# «повернення в місто», П-176), і персонаж, заведений
				# раніше, лишався без нього назавжди — а це єдиний вихід
				# із дірки. Знайдено 19.09.2026: Ork рівня 6 не мав ні
				# скіла, ні кнопки, коли провалився.
				for key in data.starting_skills:
					if not creatures[id].learned.has(key):
						creatures[id].learn(key,
								int(data.starting_skills[key]))
						print("[база] %s дістав стартовий скіл «%s»"
								% [name, key])
				creatures[id].refresh_stats()
				creatures[id].pad_bar()
				_send_bar(id)
				if row.is_empty():
					print("[база] %s новий, починає з нуля" % name)
				else:
					print("[база] %s повернувся: рівень %d, поваги %d"
							% [name, creatures[id].level,
							   creatures[id].respect])
				rpc_id(id, "client_place", id, creatures[id].global_position,
						creatures[id].facing)
				# Поява пішла клієнтові ДО того, як база відповіла, — зі
				# статтю й расою за замовчуванням. Тепер справжні.
				_tell_look(id, creatures[id]), CONNECT_ONE_SHOT)
		store.load_character(_names[id])
	a.bar = data.bar if not data.bar.is_empty() else a.bar
	a.pad_bar()
	# Стартові скіли — заглушка до рун і крамниць (П-97).
	for skill_key in data.starting_skills:
		a.learn(skill_key, int(data.starting_skills[skill_key]))
	# Себе гравець бачить завжди; решту роздасть звірка зон бачення.
	rpc_id(id, "client_spawn", id, a.global_position, a.facing,
			_kind_of(a), _names.get(id, ""), a.level, a.sex, a.race,
			look_of(a))
	rpc_id(id, "client_vision", a.vision_radius())
	rpc_id(id, "client_vitals", id, a.hp, a.stats.max_hp())
	_send_bar(id)
	vision.watch(id)
	send_stats(id)
	send_skills(id)
	send_things(id)
	print("[світ] приєднався %d, усього %d" % [id, creatures.size()])


## Що показувати на сторінці «Стати». Збирає СЕРВЕР: у клієнта ні базових
## статів, ні спорядження немає й бути не повинно (П-08).
func _stats_row(a: Node) -> Dictionary:
	return {
		"раса": a.race,
		"стать": a.sex,
		"рівень": a.level,
		"очки": a.stat_points,
		"сила": a.stats.strength,
		"сила базова": a.base_stats.strength,
		"спритність": a.stats.agility,
		"спритність базова": a.base_stats.agility,
		"витривалість": a.stats.stamina,
		"витривалість базова": a.base_stats.stamina,
		"інтелект": a.stats.intellect,
		"інтелект базова": a.base_stats.intellect,
		"чуття": a.stats.sense,
		"чуття базова": a.base_stats.sense,
		"здоров'я": a.stats.max_hp(),
		"мана": a.stats.max_mp(),
		"атака": a.stats.physical_attack(),
		"магічна атака": a.stats.magical_attack(),
		"захист": a.stats.physical_defence(),
		"магічний захист": a.stats.magical_defence(),
		"швидкість": a.stats.move_speed(),
		# Власне, без речей і бафів — щоб у вікні було видно, що саме
		# дав баф (замовник 19.09.2026: «не бачу в статах, на що
		# повпливав баф»).
		"здоров'я базова": a.base_stats.max_hp(),
		"мана базова": a.base_stats.max_mp(),
		"атака базова": a.base_stats.physical_attack(),
		"магічна атака базова": a.base_stats.magical_attack(),
		"захист базова": a.base_stats.physical_defence(),
		"магічний захист базова": a.base_stats.magical_defence(),
		"швидкість базова": a.base_stats.move_speed(),
	}


## Що вміє гравець: ключ, назва, грейд, рівень і числа поточного рівня.
## Збирає сервер — у клієнта книги скілів для ЧУЖИХ рівнів немає.
func _skills_row(a: Node) -> Array:
	var out: Array = []
	for key: String in a.learned:
		var skill: Skill = data.skills.get_skill(key)
		if skill == null:
			continue
		var level: int = int(a.learned[key])
		out.append({
			"ключ": key,
			"назва": skill.name,
			"опис": skill.description,
			"стихія": skill.element,
			"грейд": skill.grade,
			"рівень": level,
			"рівнів": skill.max_level(),
			"мана": skill.mana(level),
			"дальність": skill.range_at(level),
			"шкода": skill.power_share(level),
			"ефект": skill.state_at(level),
		})
	return out


func send_skills(id: int) -> void:
	var a: Node = creatures.get(id)
	if a == null or id <= 0:
		return
	rpc_id(id, "client_skills", _skills_row(a))


## Речі гравця: поодинокі (з афіксами) і складані.
func _bag_row(a: Node) -> Array:
	var out: Array = []
	var where := {}
	for slot in a.gear:
		where[int(a.gear[slot])] = slot
	for at in a.things.size():
		var item: Item = a.things[at]
		var lines := PackedStringArray()
		for stat_name in item.stats:
			lines.append("%s +%d" % [stat_name, int(item.stats[stat_name])])
		out.append({
			"номер": at,
			"назва": item.title(),
			# Значок шукається за БАЗОВОЮ назвою: «назва» несе афікси
			# («легкий меч з кори дуба»), і файлу з таким ім'ям нема й не
			# буде — афіксів у малюнках не намалювати наперед.
			"база": item.base,
			"вид": item.kind,
			# За скільки крамар це викупить. Рахує СЕРВЕР: у клієнта ні
			# цін, ні частки викупу немає й бути не повинно (П-08), а
			# замовник просив у вікні торгівлі саме ціну, не частку.
			# Нуль — крамар цього не бере.
			"продати за": 0 if shop.refuses(item.base) \
					else shop.buy_price(item.base),
			"слот": item.slot,
			"комірки": ItemBook.slots_for(item.slot),
			"дві руки": item.two_handed,
			"грейд": item.grade,
			"вдягнене": a.is_worn(at),
			"де": str(where.get(at, "")),
			"стати": ", ".join(lines),
		})
	return out


func _stacks_row(a: Node) -> Array:
	var out: Array = []
	for name in a.items:
		var base: Dictionary = data.items.base_of(str(name))
		out.append({
			"назва": str(name),
			"вид": str(base.get("вид", "")),
			"грейд": str(base.get("грейд", "")),
			"продати за": 0 if shop.refuses(str(name)) \
					else shop.buy_price(str(name)),
			"скільки": int(a.items[name]),
			"придатна": not base.get("дія", {}).is_empty(),
		})
	return out


func send_things(id: int) -> void:
	var a: Node = creatures.get(id)
	if a == null or id <= 0:
		return
	rpc_id(id, "client_things", _bag_row(a), _stacks_row(a))


## Вдягти річ із торби. Номер перевіряє сама істота (`equip`), а слот вона
## ж і звільняє: що там стояло, знімається саме собою.
@rpc("any_peer", "call_remote", "reliable")
func ask_wear(at: int, want: String = "") -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var a: Node = creatures.get(id)
	if a == null:
		return
	var why: String = a.equip(at, want)
	if why != "":
		link.notice(id, why)
		return
	link.notice(id, "вдягнено: %s" % a.things[at].title())
	_after_bag(id, a)
	_tell_look(id, a)


## Зняти те, що стоїть у цьому слоті.
@rpc("any_peer", "call_remote", "reliable")
func ask_take_off(slot: String) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var a: Node = creatures.get(id)
	if a == null or not a.gear.has(slot):
		return
	a.unequip(slot)
	link.notice(id, "знято: %s" % slot)
	_after_bag(id, a)
	_tell_look(id, a)


## Крамар без свого переліку «товар» у мапі продає загальний асортимент
## (`items.json → торгівля → асортимент крамаря`). Мапа світу 2
## генерується й руками не правиться, і товару в її крамарів немає зовсім
## — без цього там не було де купити навіть зілля. І сервер, і клієнт:
## клієнтові це каже, чи показувати «Торгувати».
func _stock_merchants(land: Node) -> void:
	var stock: Array = data.items.trade.get("асортимент крамаря", [])
	for child in land.get_children():
		if child is NPC and child.craft.begins_with("крамар") \
				and child.goods.is_empty():
			child.goods = stock


## Вигляд гравця для чужих очей (19.09.2026, слово замовника: «моделі
## роздягнені, і коли в інвентарі вдягаю одяг — та частина, яку
## вдягаю, вдягається в моделі»): комірка -> назва речі, лише ті
## комірки, що видно на тілі (`SkinnedModel.PIECES`).
func look_of(a: Node) -> Dictionary:
	var out := {}
	if not ("gear" in a):
		return out
	for slot: String in a.gear:
		if not SkinnedModel.PIECES.has(slot):
			continue
		var at: int = int(a.gear[slot])
		if at >= 0 and at < a.things.size():
			out[slot] = a.things[at].base
	return out


## Сказати собі й усім, хто бачить, як тепер виглядає гравець.
func _tell_look(id: int, a: Node) -> void:
	var args := [id, a.race, a.sex, look_of(a)]
	link.to_one(id, &"client_appearance", args)
	link.to_watchers(id, &"client_appearance", args)


## Ужити складану річ — кристал душі й таке інше.
@rpc("any_peer", "call_remote", "reliable")
func ask_use(name: String) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if actions.use_item(id, name):
		_after_bag(id, creatures.get(id))


# ── крамар (П-132) ────────────────────────────────────────────────────
#
# Мешканці — вузли краєвиду, а не істоти: вони не ходять, не б'ються і не
# мають здоров'я. Через це в них немає номера з'єднання, і називають їх
# НОМЕРОМ У МАПІ: обидва боки будують місто з того самого файлу.
#
# Клієнт шле лише «хочу оце в отого» — відстань, асортимент і гроші
# рахує сервер (П-08). Без цього вікно торгівлі було б найкоротшим
# шляхом до нескінченних речей.


## Хто це й чи можна з ним говорити. `-1` у відповіді — «ні».
func _resident(id: int, at: int) -> NPC:
	var a: Node = creatures.get(id)
	var land: Node = get_node_or_null("Landscape")
	if a == null or land == null or not land.has_method("resident_at"):
		return null
	var who: NPC = land.resident_at(at)
	if who == null:
		return null
	if not shop.within(a, who):
		link.notice(id, "%s задалеко" % who.title())
		return null
	return who


## Заговорити до мешканця. Відповідь — вікно розмови з кнопками.
@rpc("any_peer", "call_remote", "reliable")
func ask_talk(at: int) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: NPC = _resident(id, at)
	if who == null:
		return
	rpc_id(id, "client_talk", at, who.title(), who.trades(),
			who.keeps(), who.teaches(), who.blesses(), who.ports(),
			who.blesses() and not _super_blessing().is_empty(),
			who.forges())


const BLESSINGS_PATH := "res://data/blessings.json"


## Бафи священика (слово замовника 19.09.2026). Файл читаємо на кожне
## прохання: прохання рідкісні, а числа так правляться без перезапуску.
## Зіпсований файл — кажемо гравцеві й у журнал (P3), а не мовчимо.
@rpc("any_peer", "call_remote", "reliable")
func ask_bless(at: int) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: NPC = _resident(id, at)
	if who == null or not who.blesses():
		return
	var a: Node = creatures.get(id)
	if not a.is_alive():
		return
	var raw := FileAccess.get_file_as_string(BLESSINGS_PATH)
	var parsed: Variant = JSON.parse_string(raw)
	if not parsed is Dictionary or not parsed.get("бафи") is Array:
		print("[священик] ‼ %s не прочитався" % BLESSINGS_PATH)
		link.notice(id, "‼ бафи священика не прочитались")
		return
	var need := int(parsed.get("з рівня", 1))
	if a.level < need:
		link.notice(id, "%s благословляє з %d рівня" % [who.title(), need])
		return
	var given: Array = []
	for one: Variant in parsed["бафи"]:
		if one is Dictionary:
			a.add_state(State.from_data(one))
			given.append(str(one.get("назва", "стан")))
	link.notice(id, "%s: %s" % [who.title(), ", ".join(given)])


const TELEPORTS_PATH := "res://data/teleports.json"
## Ближче за це до середини міста — вважаємо, що ти вже в ньому, і в
## перелік воно не йде: пропонувати перенести туди, де стоїш, безглуздо.
const SAME_TOWN := 120.0


## Числа майстра магії. Читаємо файл на кожне прохання — прохання
## рідкісні, а ціни так правляться без перезапуску (як у священика).
## Зіпсований файл озвучуємо, а не ковтаємо (P3).
func _teleport_rules(id: int) -> Dictionary:
	var raw := FileAccess.get_file_as_string(TELEPORTS_PATH)
	var parsed: Variant = JSON.parse_string(raw)
	if not parsed is Dictionary:
		print("[магія] ‼ %s не прочитався" % TELEPORTS_PATH)
		link.notice(id, "‼ ціни майстра магії не прочитались")
		return {}
	return parsed


## Куди він може перенести і почому. Рахує СЕРВЕР: клієнт ціну не
## вигадує (P1), він лише показує те, що прийшло.
func _towns_for(a: Node, rules: Dictionary) -> Array:
	var here := Vector2(a.global_position.x, a.global_position.z)
	var per_km := float(rules.get("ціна за км", 250.0))
	var least := int(rules.get("найменша ціна", 300))
	var out: Array = []
	for town: Dictionary in data.map.get("міста", []):
		var at: Array = town.get("центр", [0, 0, 0])
		var spot := Vector2(float(at[0]), float(at[2]))
		var far := here.distance_to(spot)
		if far < SAME_TOWN:
			continue
		out.append({"назва": str(town.get("назва", "місто")),
				"далеко": far,
				"ціна": maxi(least, int(round(far / 1000.0 * per_km)))})
	return out


## Майстер магії: перелік міст із цінами (слово замовника 20.09.2026).
@rpc("any_peer", "call_remote", "reliable")
func ask_ports(at: int) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: NPC = _resident(id, at)
	if who == null or not who.ports():
		return
	var a: Node = creatures.get(id)
	if a == null or not a.is_alive():
		return
	var rules := _teleport_rules(id)
	if rules.is_empty():
		return
	var need := int(rules.get("з рівня", 1))
	if a.level < need:
		link.notice(id, "%s береться з %d рівня" % [who.title(), need])
		return
	var towns := _towns_for(a, rules)
	if towns.is_empty():
		link.notice(id, "%s: звідси нікуди переносити" % who.title())
		return
	rpc_id(id, "client_ports", at, who.title(), towns,
			Shop.money_of(a))


# ── коваль (21.09.2026) ───────────────────────────────────────────────
#
# Ремонт і рунне посилення. Уся арифметика — у `Smith`; тут лише хто,
# де й чи досить близько. Ціну рахує сервер щоразу, клієнт шле номер речі.

var _smith_rng := RandomNumberGenerator.new()


## Вікно коваля: кожна річ, яку можна полагодити чи зачарувати, з ціною.
@rpc("any_peer", "call_remote", "reliable")
func ask_smith(at: int) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: NPC = _resident(id, at)
	if who == null or not who.forges():
		return
	_send_smith(id, at, who.title())


func _send_smith(id: int, at: int, title: String) -> void:
	var a: Node = creatures.get(id)
	if a == null:
		return
	var rows: Array = []
	for i in a.things.size():
		var item: Item = a.things[i]
		if not item.kind in ["зброя", "обладунок", "амулет"]:
			continue
		var cost: Dictionary = data.smith.enchant_cost(item, data.items)
		rows.append({
			"номер": i, "назва": item.title(), "грейд": item.grade,
			"вдягнено": a.is_worn(i),
			"міцність": [item.durability, item.durability_max],
			"ремонт": data.smith.repair_cost(item, data.items),
			"гроші": int(cost["гроші"]), "речі": cost["речі"],
			"бракує": data.smith.missing_for(a, item, data.items),
			"руна": Smith.rune_text(item.rune),
			"магічна": data.smith.is_magic(item, data.items)})
	rpc_id(id, "client_smith", at, title, rows, Shop.money_of(a))


@rpc("any_peer", "call_remote", "reliable")
func ask_repair(at: int, thing_at: int) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: NPC = _resident(id, at)
	if who == null or not who.forges():
		return
	var a: Node = creatures.get(id)
	var why: String = data.smith.repair(a, thing_at, data.items)
	if why != "":
		link.notice(id, why)
		return
	link.notice(id, "%s: полагоджено «%s»" % [who.title(),
			a.things[thing_at].title()])
	print("[коваль] %d полагодив %s" % [id, a.things[thing_at].base])
	_after_bag(id, a)
	_send_smith(id, at, who.title())


@rpc("any_peer", "call_remote", "reliable")
func ask_enchant(at: int, thing_at: int) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: NPC = _resident(id, at)
	if who == null or not who.forges():
		return
	var a: Node = creatures.get(id)
	var why: String = data.smith.enchant(a, thing_at, data.items, _smith_rng)
	if why != "":
		link.notice(id, why)
		return
	var text := Smith.rune_text(data.smith.last)
	link.notice(id, "%s: на «%s» лягла руна — %s" % [who.title(),
			a.things[thing_at].title(), text])
	print("[коваль] %d зачарував %s: %s" % [id, a.things[thing_at].base, text])
	_after_bag(id, a)
	_send_smith(id, at, who.title())


## Перенести. Ціну беремо ЩЕ РАЗ тут, а не ту, що надіслав клієнт:
## інакше «телепорт за 1 монету» робиться однією правкою пакета (P1).
@rpc("any_peer", "call_remote", "reliable")
func ask_port(at: int, town_name: String) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: NPC = _resident(id, at)
	if who == null or not who.ports():
		return
	var a: Node = creatures.get(id)
	if a == null or not a.is_alive():
		return
	var rules := _teleport_rules(id)
	if rules.is_empty():
		return
	if a.level < int(rules.get("з рівня", 1)):
		return
	var want: Dictionary = {}
	for one: Dictionary in _towns_for(a, rules):
		if str(one["назва"]) == town_name:
			want = one
	if want.is_empty():
		link.notice(id, "%s: туди звідси не переносять" % who.title())
		return
	var price := int(want["ціна"])
	if Shop.money_of(a) < price:
		link.notice(id, "%s бере %d, а в тебе %d"
				% [who.title(), price, Shop.money_of(a)])
		return
	var spot := Vector2.ZERO
	for town: Dictionary in data.map.get("міста", []):
		if str(town.get("назва", "")) == town_name:
			var at_town: Array = town["центр"]
			spot = Vector2(float(at_town[0]), float(at_town[2]))
	Shop.take_money(a, price)
	combat.send_to(id, spot, "магія")
	send_things(id)
	link.notice(id, "%s переніс у %s за %d" % [who.title(), town_name,
			price])


## Супер-баф на проби (слово замовника 20.09.2026). Окремою кнопкою, а
## не разом зі звичайними: це не механіка гри, а спосіб швидко щось
## перевірити на ходу. Блок у `blessings.json → супер`; немає блоку —
## немає й кнопки.
func _super_blessing() -> Array:
	var raw := FileAccess.get_file_as_string(BLESSINGS_PATH)
	var parsed: Variant = JSON.parse_string(raw)
	if not parsed is Dictionary:
		return []
	var block: Variant = parsed.get("супер", {})
	# Порожньо чи зіпсовано — кнопки просто не буде, і це не помилка.
	if not block is Dictionary or not block.get("бафи") is Array:
		return []
	return block["бафи"]


@rpc("any_peer", "call_remote", "reliable")
func ask_super_bless(at: int) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: NPC = _resident(id, at)
	if who == null or not who.blesses():
		return
	var a: Node = creatures.get(id)
	if a == null or not a.is_alive():
		return
	var buffs := _super_blessing()
	if buffs.is_empty():
		link.notice(id, "‼ супер-баф не прочитався")
		return
	var given: Array = []
	for one: Variant in buffs:
		if one is Dictionary:
			a.add_state(State.from_data(one))
			given.append(str(one.get("назва", "стан")))
	print("[проба] %d дістав супер-баф: %s" % [id, ", ".join(given)])
	link.notice(id, "ПРОБА: %s" % ", ".join(given))


## Показати прилавок. Асортимент шлемо цілком: він короткий і не
## змінюється, а рахувати ціни на клієнті означало б їм вірити.
@rpc("any_peer", "call_remote", "reliable")
func ask_shop(at: int) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: NPC = _resident(id, at)
	if who == null or not who.trades():
		return
	rpc_id(id, "client_shop", at, who.title(),
			shop.goods_of({"товар": who.goods}), shop.buyback_percent())


@rpc("any_peer", "call_remote", "reliable")
func ask_buy(at: int, name: String) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: NPC = _resident(id, at)
	if who == null or not who.trades():
		return
	var a: Node = creatures.get(id)
	var why: String = shop.buy(a, {"товар": who.goods}, name)
	if why != "":
		link.notice(id, why)
		return
	link.notice(id, "куплено: %s за %d" % [name, shop.sell_price(name)])
	_after_bag(id, a)


## Продати поодиноку річ за її номером у торбі.
@rpc("any_peer", "call_remote", "reliable")
func ask_sell(at: int, thing_at: int) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: NPC = _resident(id, at)
	if who == null or not who.trades():
		return
	var a: Node = creatures.get(id)
	if thing_at < 0 or thing_at >= a.things.size():
		return
	# Назву й ціну беремо ДО продажу: після нього речі вже немає.
	var sold: String = a.things[thing_at].title()
	var paid: int = shop.buy_price(a.things[thing_at].base)
	var why: String = shop.sell(a, thing_at)
	if why != "":
		link.notice(id, why)
		return
	link.notice(id, "продано: %s за %d" % [sold, paid])
	_after_bag(id, a)


## Продати складану річ: скільки — вибрав гравець − / + (П-164).
@rpc("any_peer", "call_remote", "reliable")
func ask_sell_stack(at: int, name: String, count: int = -1) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: NPC = _resident(id, at)
	if who == null or not who.trades():
		return
	var a: Node = creatures.get(id)
	if count < 0:
		count = int(a.items.get(name, 0))
	var paid := shop.buy_price(name) * count
	var why: String = shop.sell_stack(a, name, count)
	if why != "":
		link.notice(id, why)
		return
	link.notice(id, "продано: %s ×%d за %d" % [name, count, paid])
	_after_bag(id, a)


# ── склад (крок 5, П-145) ────────────────────────────────────────────

@rpc("any_peer", "call_remote", "reliable")
func ask_warehouse(at: int) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: NPC = _resident(id, at)
	if who == null or not who.keeps():
		return
	send_things(id)
	send_warehouse(id, at)


@rpc("any_peer", "call_remote", "reliable")
func ask_store_thing(at: int, thing_at: int) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: NPC = _resident(id, at)
	if who == null or not who.keeps():
		return
	var a: Node = creatures.get(id)
	var why: String = warehouse.store_thing(a, thing_at)
	if why != "":
		link.notice(id, why)
		return
	_after_warehouse(id, a, at)


@rpc("any_peer", "call_remote", "reliable")
func ask_withdraw_thing(at: int, thing_at: int) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: NPC = _resident(id, at)
	if who == null or not who.keeps():
		return
	var a: Node = creatures.get(id)
	var why: String = warehouse.withdraw_thing(a, thing_at)
	if why != "":
		link.notice(id, why)
		return
	_after_warehouse(id, a, at)


@rpc("any_peer", "call_remote", "reliable")
func ask_store_stack(at: int, name: String, count: int = -1) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: NPC = _resident(id, at)
	if who == null or not who.keeps():
		return
	var a: Node = creatures.get(id)
	var why: String = warehouse.store_stack(a, name, count)
	if why != "":
		link.notice(id, why)
		return
	_after_warehouse(id, a, at)


@rpc("any_peer", "call_remote", "reliable")
func ask_withdraw_stack(at: int, name: String, count: int = -1) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: NPC = _resident(id, at)
	if who == null or not who.keeps():
		return
	var a: Node = creatures.get(id)
	var why: String = warehouse.withdraw_stack(a, name, count)
	if why != "":
		link.notice(id, why)
		return
	_after_warehouse(id, a, at)


# ── обмін між гравцями (П-218) ───────────────────────────────────────
#
# Логіка — `Trade`; тут лише хто що попросив і кому що сказати.

## Покликати ціль на обмін.
@rpc("any_peer", "call_remote", "reliable")
func ask_trade_invite(to: int) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if to <= 0:
		link.notice(id, "міняються лише з гравцями")
		return
	var why: String = trade.invite(id, to, creatures.get(id),
			creatures.get(to))
	if why != "":
		link.notice(id, why)
		return
	link.notice(id, "запрошення до обміну надіслано: %s"
			% _names.get(to, "гравець"))
	rpc_id(to, "client_trade_invite", str(_names.get(id, "гравець")),
			Trade.INVITE_TIME)


## Відповідь на запрошення.
@rpc("any_peer", "call_remote", "reliable")
func ask_trade_answer(yes: bool) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var from: int = trade.invited_by(id)
	if not yes:
		trade.decline(id)
		if from != 0:
			link.notice(from, "%s відмовився від обміну"
					% _names.get(id, "гравець"))
		return
	var why: String = trade.accept(id, creatures.get(from), creatures.get(id))
	if why != "":
		link.notice(id, why)
		if from != 0:
			link.notice(from, "обмін не відкрився: %s" % why)
		return
	_send_table(id)


@rpc("any_peer", "call_remote", "reliable")
func ask_trade_offer_thing(thing_at: int) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	_trade_reply(id, trade.offer_thing(id, creatures.get(id), thing_at))


@rpc("any_peer", "call_remote", "reliable")
func ask_trade_offer_stack(name: String, count: int) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	_trade_reply(id, trade.offer_stack(id, creatures.get(id), name, count))


@rpc("any_peer", "call_remote", "reliable")
func ask_trade_take_back_thing(at_on_table: int) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	_trade_reply(id, trade.take_back_thing(id, at_on_table))


@rpc("any_peer", "call_remote", "reliable")
func ask_trade_take_back_stack(name: String) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	_trade_reply(id, trade.take_back_stack(id, name))


@rpc("any_peer", "call_remote", "reliable")
func ask_trade_agree() -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var other: int = trade.partner(id)
	if other == 0:
		return
	var a: Node = creatures.get(id)
	var b: Node = creatures.get(other)
	var why: String = trade.agree(id, a, b)
	if why == "":
		_send_table(id)
		return
	if why == "обмінено":
		for one: int in [id, other]:
			rpc_id(one, "client_trade_closed", "")
			link.notice(one, "обмін відбувся")
			_after_bag(one, creatures.get(one))
		return
	# Відмова: стіл міг і вціліти (задалеко — ще можна підійти), і
	# закритись (річ зникла). Кажемо обом і показуємо, що лишилось.
	if trade.busy(id):
		link.notice(id, why)
		_send_table(id)
	else:
		_trade_closed(id, why)
		_trade_closed(other, why)


@rpc("any_peer", "call_remote", "reliable")
func ask_trade_cancel() -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var other: int = trade.close(id) if trade.busy(id) else 0
	rpc_id(id, "client_trade_closed", "обмін скасовано")
	if other != 0:
		_trade_closed(other, "%s скасував обмін" % _names.get(id, "гравець"))


func _trade_reply(id: int, why: String) -> void:
	if why != "":
		link.notice(id, why)
	if trade.busy(id):
		_send_table(id)


## Показати стіл обом. Свої речі на столі несуть свій номер у торбі —
## щоб вікно не пропонувало покласти ту саму річ удруге.
func _send_table(id: int) -> void:
	for one: int in [id, trade.partner(id)]:
		if one == 0 or not creatures.has(one):
			continue
		var table: Dictionary = trade.table_of(one)
		var me: Node = creatures[one]
		for row: Dictionary in table["моє"]:
			if row.has("на столі"):
				row["номер"] = me.things.find(
						trade.thing_on_table(one, int(row["на столі"])))
		send_things(one)
		rpc_id(one, "client_trade_table",
				str(_names.get(trade.partner(one), "гравець")), table)


func _trade_closed(id: int, why: String) -> void:
	if not creatures.has(id):
		return
	rpc_id(id, "client_trade_closed", why)
	if why != "":
		link.notice(id, why)


func _tick_trade(delta: float) -> void:
	var res: Dictionary = trade.tick(delta, creatures)
	for row: Array in res["зламані"]:
		_trade_closed(int(row[0]), "обмін перервано: %s" % row[2])
		_trade_closed(int(row[1]), "обмін перервано: %s" % row[2])
	for row: Array in res["прострочені"]:
		link.notice(int(row[1]), "%s не відповів на обмін"
				% _names.get(int(row[0]), "гравець"))
		if creatures.has(int(row[0])):
			rpc_id(int(row[0]), "client_trade_invite_gone")


# ── гільдія: вивчення й підняття рівня скілів (крок 5, П-145) ───────
#
# Сама логіка (`Runes`) написана 02.09.2026, задовго до цього мешканця —
# перевіряти й міняти вивчене вміла, а покликати нікуди не було. Гільд-
# майстер саме те місце, звідки її нарешті можна викликати.

## Лише скіли з дерева (П-150): у мобів «вкладки» немає — вони тут не
## показуються, лишаються тим, чим і були, вміннями монстра, не
## гільдії.
func _guild_rows(a: Node) -> Array:
	var out: Array = []
	for key: String in data.skills.keys():
		var skill: Skill = data.skills.get_skill(key)
		if skill.category == "":
			continue
		# Дерево для всіх рас і статей (П-221): чужу гілку гільдмайстер
		# не показує взагалі. Фільтр тут, на СЕРВЕРІ, а не у вікні:
		# інакше клієнт знав би про чужі скіли й міг би попросити їх.
		if not skill.fits(a.race, a.sex):
			continue
		if skill.source != "дерево" and skill.source != "синтез":
			continue
		# Професії (П-224): видно лише свій ланцюг. Чужа професія — це
		# чуже дерево, і клієнт про нього знати не повинен, так само як
		# про чужу расову гілку.
		if skill.profession != "" \
				and not data.professions.line(a.profession).has(
					skill.profession):
			continue
		# Прихована гілка мовчить, доки не відкрита: ні назви, ні чисел.
		if not data.professions.branch_open(a, skill.branch):
			continue
		var known: bool = a.knows(key)
		var level: int = int(a.learned.get(key, 0))
		out.append({
			"ключ": key,
			"назва": skill.name,
			"грейд": skill.grade,
			"вивчено": known,
			"рівень": level,
			"максимум": skill.max_level(),
			"з рівня": skill.from_level,
			"руна вивчення": skill.rune,
			"руна підняття": Runes.level_rune_for(skill.grade),
			"досвід вивчення": skill.learn_cost,
			"досвід підняття": Runes.raise_cost(skill, maxi(level, 1)),
			"вкладка": skill.category,
			"місце": [skill.position.x, skill.position.y],
			"передумова": skill.requires,
			"передумова відома":
					skill.requires == "" or a.knows(skill.requires),
			"опис": skill.description,
			"професія": skill.profession,
			"гілка": skill.branch,
			"обовязковий": skill.mandatory,
			"джерело": skill.source,
			"синтез": skill.synthesis,
			"синтез відомий": _synthesis_known(a, skill),
		})
	return out


## Чи вивчені обидві навички, з яких це вміння зливається.
func _synthesis_known(a: Node, skill: Skill) -> bool:
	if skill.synthesis.is_empty():
		return false
	for from: String in skill.synthesis:
		if not a.knows(from):
			return false
	return true


## Друга половина вікна гільдії (П-224): хто я зараз, що відкрито і куди
## можна піти далі. Умови квеста рахує сервер — клієнт бачить лише «3 із
## 20», і підробити прогрес, надіславши свій, не може.
func _guild_about(a: Node) -> Dictionary:
	var profs: Professions = data.professions
	var next: Array = []
	for key: String in profs.next_after(a.profession):
		var quest: Dictionary = profs.quest_of(key)
		next.append({
			"ключ": key,
			"назва": profs.name_of(key),
			"етап": profs.stage_of(key),
			"з рівня": int(profs.rows[key].get("з рівня", 1)),
			"опис": str(profs.rows[key].get("опис", "")),
			"квест": str(quest.get("назва", "")),
			"де": str(quest.get("де", "")),
			"умови": profs.quest_progress(a, key),
			"можна": profs.why_not(a, key) == "",
			"чому ні": profs.why_not(a, key),
			"гілка": str(profs.branch_of(key).get("назва", "")),
			"як відкрити": profs.hint_for(key),
		})
	var mine: Array = []
	for key: String in profs.line(a.profession):
		mine.append({"ключ": key, "назва": profs.name_of(key),
				"етап": profs.stage_of(key),
				"гілка": str(profs.branch_of(key).get("назва", "")),
				"відкрита": a.opened.has(
					str(profs.branch_of(key).get("назва", ""))),
				"як відкрити": profs.hint_for(key)})
	return {
		"професія": a.profession,
		"назва професії": profs.name_of(a.profession) if a.profession != ""
				else "без професії",
		"етап": profs.stage_of(a.profession) if a.profession != "" else 1,
		"мої": mine,
		"далі": next,
		"відкриті гілки": a.opened,
	}


@rpc("any_peer", "call_remote", "reliable")
func ask_guild(at: int) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: NPC = _resident(id, at)
	if who == null or not who.teaches():
		return
	var a: Node = creatures.get(id)
	# Амулет міг прийти не з монстра, а з крамниці чи від іншого гравця,
	# тому дивимось на гілки й тут, а не лише після вбивства.
	_check_branches(id, a)
	rpc_id(id, "client_guild", at, _guild_rows(a), _guild_about(a))


## Узяти наступну професію (П-224). Сервер сам перевіряє рівень, батька
## й усі умови квеста: клієнт надсилає лише «хочу оцю».
@rpc("any_peer", "call_remote", "reliable")
func ask_take_profession(at: int, key: String) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: NPC = _resident(id, at)
	if who == null or not who.teaches():
		return
	var a: Node = creatures.get(id)
	var why: String = data.professions.take(a, key)
	if why != "":
		link.notice(id, why)
		rpc_id(id, "client_guild", at, _guild_rows(a), _guild_about(a))
		return
	link.notice(id, "тепер ти %s" % data.professions.name_of(key))
	print("[професії] %d став: %s (етап %d)"
			% [id, key, data.professions.stage_of(key)])
	_check_branches(id, a)
	send_stats(id)
	rpc_id(id, "client_guild", at, _guild_rows(a), _guild_about(a))


## Синтез двох умінь в одне (П-224).
@rpc("any_peer", "call_remote", "reliable")
func ask_synthesize(at: int, key: String) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: NPC = _resident(id, at)
	if who == null or not who.teaches():
		return
	var a: Node = creatures.get(id)
	var why: String = runes.synthesize(a, key)
	if why != "":
		link.notice(id, why)
		return
	link.notice(id, "злито: %s" % data.skills.get_skill(key).name)
	# Синтез сам може відчинити приховану гілку — саме так замовник це
	# й описав, тож дивимось одразу після злиття.
	_check_branches(id, a)
	send_stats(id)
	rpc_id(id, "client_guild", at, _guild_rows(a), _guild_about(a))


@rpc("any_peer", "call_remote", "reliable")
func ask_learn_skill(at: int, key: String) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: NPC = _resident(id, at)
	if who == null or not who.teaches():
		return
	var a: Node = creatures.get(id)
	var why: String = runes.learn(a, key)
	if why != "":
		link.notice(id, why)
		return
	link.notice(id, "вивчено: %s" % data.skills.get_skill(key).name)
	send_stats(id)
	rpc_id(id, "client_guild", at, _guild_rows(a), _guild_about(a))


@rpc("any_peer", "call_remote", "reliable")
func ask_raise_skill(at: int, key: String) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: NPC = _resident(id, at)
	if who == null or not who.teaches():
		return
	var a: Node = creatures.get(id)
	var why: String = runes.raise(a, key)
	if why != "":
		link.notice(id, why)
		return
	link.notice(id, "піднято рівень: %s → %d"
			% [data.skills.get_skill(key).name, int(a.learned[key])])
	send_stats(id)
	rpc_id(id, "client_guild", at, _guild_rows(a), _guild_about(a))


## Розподілити одне вільне очко (П-147). Разом із максимумом росте й
## ПОТОЧНЕ здоров'я/мана — на ту саму різницю, інакше очко у Витривалість
## нічого не давало б, поки гравець не долікується.
@rpc("any_peer", "call_remote", "reliable")
func ask_spend_stat(field: String) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var a: Node = creatures.get(id)
	if a == null:
		return
	var why: String = combat.progress.spend_stat(a, field)
	if why != "":
		link.notice(id, why)
		return
	send_stats(id)


## Скасувати чергу й ціль одним натисканням (П-149): передумав бити
## далеку ціль, а поруч уже хтось б'є. Черга просто спорожняється —
## жодна дія з неї не встигає спрацювати.
@rpc("any_peer", "call_remote", "reliable")
func ask_cancel() -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var a: Node = creatures.get(id)
	if a == null:
		return
	a.queue.clear()
	a.target_id = 0
	rpc_id(id, "client_target", 0)


## Після будь-якої зміни в торбі: сама торба, стати (спорядження їх
## зсуває) і перелік речей для вікна.
func _after_bag(id: int, a: Node) -> void:
	send_things(id)
	send_stats(id)
	# Ремінь міг змінитись — а з ним і скільки смуг панелі відкрито.
	_send_bar(id)


## Розкладка панелі й скільки її смуг відкриває ремінь (П-232).
func _send_bar(id: int) -> void:
	var a: Node = creatures.get(id)
	if a == null or not a.has_method("strips"):
		return
	rpc_id(id, "client_bar", PackedStringArray(a.bar), a.strips())


## Те саме після зміни на складі: і торба (річ туди-сюди йде з неї), і
## сам склад, бо вікно показує обидва списки одночасно.
func _after_warehouse(id: int, a: Node, at: int) -> void:
	send_things(id)
	send_stats(id)
	send_warehouse(id, at)


func _warehouse_thing_row(things: Array) -> Array:
	var out: Array = []
	for at in things.size():
		var item: Item = things[at]
		out.append({"номер": at, "назва": item.title(), "вид": item.kind})
	return out


func _warehouse_stack_row(items: Dictionary) -> Array:
	var out: Array = []
	for name in items:
		var base: Dictionary = data.items.base_of(str(name))
		out.append({"назва": str(name), "вид": str(base.get("вид", "")),
				"скільки": int(items[name])})
	return out


func send_warehouse(id: int, at: int) -> void:
	var a: Node = creatures.get(id)
	if a == null or id <= 0:
		return
	rpc_id(id, "client_warehouse", at, _warehouse_thing_row(a.warehouse_things),
			_warehouse_stack_row(a.warehouse_items))


## Переслати гравцеві його стати. Кличеться там, де числа могли змінитись.
func send_stats(id: int) -> void:
	var a: Node = creatures.get(id)
	if a == null or id <= 0:
		return
	rpc_id(id, "client_stats", _stats_row(a))


func _on_left(id: int) -> void:
	# Зберегти ДО того, як істота зникне: інакше зберігати вже нічого.
	_save_one(id)
	# Стіл обміну закривається, а не висить: другий лишився б сам на сам
	# із вікном, у якому вже ніхто не відповість.
	summons.dismiss(id)
	var other: int = trade.forget(id)
	if other != 0:
		_trade_closed(other, "%s вийшов із гри" % _names.get(id, "гравець"))
	_names.erase(id)
	_signed.erase(id)
	_stats_mark.erase(id)
	_skills_mark.erase(id)
	_bag_mark.erase(id)
	_states_mark.erase(id)
	vision.drop_watcher(id)
	remove(id)
	print("[світ] пішов %d, лишилось %d" % [id, creatures.size()])


# ── клієнт: що надходить від сервера ──────────────────────────────────

## Хто це такий: вид монстра числом.
##
## Без цього клієнт знав про істоту лише номер з'єднання — і показував
## «монстр 22». Вид досить надіслати числом: назву, рівень, колір і зріст
## клієнт бере з тих самих `data/mobs.json`, що й сервер.
func _kind_of(who: Node) -> int:
	return int(who.kind) if "kind" in who else 0


@rpc("authority", "call_remote", "reliable")
func client_spawn(id: int, pos: Vector3, look: float, kind: int = 0,
		title: String = "", level: int = 1, sex: String = "чоловік",
		race: String = "людина", worn: Dictionary = {}) -> void:
	if creatures.has(id):
		return
	var a := spawn(id, pos)
	a.place_at(pos, look)
	a.level = level
	# Монстрові дістається вигляд і назва з даних — тих самих, що в
	# сервера. Досі клієнт малював усіх однаковими сірими фігурками, бо
	# виду просто не знав.
	if id < 0 and kind > 0:
		var about: Dictionary = data.for_kind(kind)
		a.kind = kind
		a.apply_tuning(about)
		_titles[id] = str(about.get("назва", "монстр"))
		a.level = int(about.get("рівень", level))
	else:
		_titles[id] = title if title != "" else "гравець %d" % id
		# Модель людини (П-150): стать приходить одразу при появі, а не
		# пізніше зі статами — інакше чужого гравця бачили б капсулою,
		# доки вікно «Стати» не відкриють.
		if a.has_method("apply_sex"):
			a.apply_sex(sex, race)
			a.wear(worn, data.items)
	_tag(id)
	if id == multiplayer.get_unique_id():
		a.become_local()
		view.entered_world()
		hud = HUD.new()
		hud.setup(self)
		# Кнопка «Повернутися в місто» ходить тим самим шляхом, що й будь-яке
		# натискання людини: показ нічого не вирішує (П-08), він лише просить.
		hud.wants_revive.connect(func() -> void: rpc_id(1, "ask_revive"))
		# Перекладену комірку підтверджує сервер: він перевіряє, чи скіл
		# узагалі вивчено, і сам шле назад нову розкладку.
		hud.wants_slot.connect(func(where: int, action: String) -> void:
				rpc_id(1, "set_slot", where, action))
		# Клік по комірці — те саме, що натиснути її число на клавіатурі,
		# разом із підходом до цілі.
		hud.wants_slot_used.connect(func(where: int) -> void:
				view.use_slot(where, false))
		# Речі: вдягти, зняти, ужити. Усе перевіряє сервер — показ лише
		# просить (П-08).
		hud.wants_wear.connect(func(at: int, slot: String) -> void:
				rpc_id(1, "ask_wear", at, slot))
		hud.wants_take_off.connect(func(slot: String) -> void:
				rpc_id(1, "ask_take_off", slot))
		hud.wants_use.connect(func(name: String) -> void:
				rpc_id(1, "ask_use", name))
		# Крамар (П-132). Кнопка «Торгувати» й кожна комірка прилавка —
		# це прохання до сервера, не дія: гроші й асортимент рахує він.
		hud.wants_shop.connect(func(at: int) -> void:
				rpc_id(1, "ask_shop", at))
		hud.wants_buy.connect(func(at: int, name: String) -> void:
				rpc_id(1, "ask_buy", at, name))
		hud.wants_sell.connect(func(at: int, thing_at: int) -> void:
				rpc_id(1, "ask_sell", at, thing_at))
		hud.wants_sell_stack.connect(
				func(at: int, name: String, count: int) -> void:
				rpc_id(1, "ask_sell_stack", at, name, count))
		# Склад і гільдія (П-145) — та сама «спитай, сервер вирішить».
		hud.wants_warehouse.connect(func(at: int) -> void:
				rpc_id(1, "ask_warehouse", at))
		hud.wants_store_thing.connect(func(at: int, thing_at: int) -> void:
				rpc_id(1, "ask_store_thing", at, thing_at))
		hud.wants_store_stack.connect(
				func(at: int, name: String, count: int) -> void:
				rpc_id(1, "ask_store_stack", at, name, count))
		hud.wants_withdraw_thing.connect(func(at: int, thing_at: int) -> void:
				rpc_id(1, "ask_withdraw_thing", at, thing_at))
		hud.wants_withdraw_stack.connect(
				func(at: int, name: String, count: int) -> void:
				rpc_id(1, "ask_withdraw_stack", at, name, count))
		# Обмін між гравцями (П-218).
		hud.wants_trade_invite.connect(func(to: int) -> void:
				rpc_id(1, "ask_trade_invite", to))
		hud.wants_trade_answer.connect(func(yes: bool) -> void:
				rpc_id(1, "ask_trade_answer", yes))
		hud.wants_trade_offer_thing.connect(func(thing_at: int) -> void:
				rpc_id(1, "ask_trade_offer_thing", thing_at))
		hud.wants_trade_offer_stack.connect(
				func(name: String, count: int) -> void:
				rpc_id(1, "ask_trade_offer_stack", name, count))
		hud.wants_trade_take_back_thing.connect(func(at: int) -> void:
				rpc_id(1, "ask_trade_take_back_thing", at))
		hud.wants_trade_take_back_stack.connect(func(name: String) -> void:
				rpc_id(1, "ask_trade_take_back_stack", name))
		hud.wants_trade_agree.connect(func() -> void:
				rpc_id(1, "ask_trade_agree"))
		hud.wants_trade_cancel.connect(func() -> void:
				rpc_id(1, "ask_trade_cancel"))
		hud.wants_guild.connect(func(at: int) -> void:
				rpc_id(1, "ask_guild", at))
		hud.wants_bless.connect(func(at: int) -> void:
				rpc_id(1, "ask_bless", at))
		hud.wants_super_bless.connect(func(at: int) -> void:
				rpc_id(1, "ask_super_bless", at))
		hud.wants_ports.connect(func(at: int) -> void:
				rpc_id(1, "ask_ports", at))
		hud.wants_smith.connect(func(at: int) -> void:
				rpc_id(1, "ask_smith", at))
		hud.wants_repair.connect(func(at: int, thing_at: int) -> void:
				rpc_id(1, "ask_repair", at, thing_at))
		hud.wants_enchant.connect(func(at: int, thing_at: int) -> void:
				rpc_id(1, "ask_enchant", at, thing_at))
		hud.wants_port.connect(func(at: int, town: String) -> void:
				rpc_id(1, "ask_port", at, town))
		hud.wants_learn_skill.connect(func(at: int, key: String) -> void:
				rpc_id(1, "ask_learn_skill", at, key))
		hud.wants_take_profession.connect(func(at: int, key: String) -> void:
				rpc_id(1, "ask_take_profession", at, key))
		hud.wants_synthesize.connect(func(at: int, key: String) -> void:
				rpc_id(1, "ask_synthesize", at, key))
		hud.wants_raise_skill.connect(func(at: int, key: String) -> void:
				rpc_id(1, "ask_raise_skill", at, key))
		hud.wants_spend_stat.connect(func(field: String) -> void:
				rpc_id(1, "ask_spend_stat", field))
		add_child(hud)


## Імена всього, що видно: номер -> як підписувати.
var _titles: Dictionary = {}
## Мій рівень: від нього рахується колір чужого імені.
var _my_level := 1


## Підписати істоту над головою кольором за різницею рівнів.
func _tag(id: int) -> void:
	var who: Node = creatures.get(id)
	if who == null or id == multiplayer.get_unique_id():
		return          # над собою підпис не потрібен — це й так ти
	var title: String = _titles.get(id, "?")
	var text := "%s  [%d]" % [title, who.level] if id < 0 else title
	who.show_tag(text, HUD.level_color(who.level - _my_level))


## Перефарбувати всі підписи. Треба після кожного свого рівня: та сама
## істота з «білої» стає «голубою», і це головна підказка, куди йти.
func _tags_again() -> void:
	for id in creatures:
		_tag(id)


## Як зветься істота — для рамки цілі в показі.
func title_of(id: int) -> String:
	return str(_titles.get(id, "монстр %d" % -id if id < 0 else "гравець"))


## Колір імені цієї істоти для показу.
func tint_of(id: int) -> Color:
	var who: Node = creatures.get(id)
	if who == null:
		return Color(1, 1, 1)
	return HUD.level_color(who.level - _my_level)


## Переставити стрибком: оживлення, а далі й телепорти. Окреме надійне
## повідомлення саме тому, що плавність тут шкідлива (див. place_at).
@rpc("authority", "call_remote", "reliable")
func client_place(id: int, pos: Vector3, look: float) -> void:
	if creatures.has(id):
		creatures[id].place_at(pos, look)


## Сервер каже: без входу не пустимо (крок 5).
@rpc("authority", "call_remote", "reliable")
func client_sign_needed() -> void:
	if view != null:
		view.ask_sign_in()


@rpc("authority", "call_remote", "reliable")
func client_sign_failed(why: String) -> void:
	if view != null:
		view.sign_failed(why)


## Перелік персонажів акаунта — рядком JSON, бо це вкладені словники.
@rpc("authority", "call_remote", "reliable")
func client_characters(list: String) -> void:
	if view != null:
		view.show_characters(JSON.parse_string(list))


## Скільки бачить мій персонаж. Камері це потрібно, щоб не відмотуватись
## далі за зону бачення (П-47).
@rpc("authority", "call_remote", "reliable")
func client_vision(radius: float) -> void:
	var me: Node = creatures.get(multiplayer.get_unique_id())
	if me != null:
		me.get_node("CameraRig").vision_radius = radius
	# Туман ховає рівно ту межу, за яку сервер уже нічого не шле (П-65).
	var land: Node = get_node_or_null("Landscape")
	if land != null:
		land.fog_to_vision(radius)


## Чию стрілку над головою показано зараз (П-156) — щоб забрати зі старої
## цілі, коли обрано нову.
var _marked_target := 0


@rpc("authority", "call_remote", "reliable")
func client_target(id: int) -> void:
	var me: Node = creatures.get(multiplayer.get_unique_id())
	if me != null:
		me.target_id = id
	# Ціль одна. Узяв монстра — мешканець більше не вибраний, інакше
	# кожна дія відповідала б «до мешканця це не застосуєш», а на екрані
	# стояло б ім'я монстра. Спіймано перевіркою: показ так замкнувся
	# намертво й за півтори хвилини не вдарив нікого.
	if id != 0:
		view.forget_resident()
	if hud != null:
		hud.set_target(id)
	var old: Node = creatures.get(_marked_target)
	if old != null:
		old.mark_as_target(false)
	_marked_target = id
	var now: Node = creatures.get(id)
	if now != null:
		now.mark_as_target(true)


@rpc("authority", "call_remote", "reliable")
func client_hp(id: int, hp: int) -> void:
	if creatures.has(id):
		creatures[id].hp = hp
	if hud != null:
		hud.set_hp(id, hp)


## Що в торбі — для вікна «Речі».
##
## Не просто рядки: щоб річ можна було вдягти натиском, клієнтові
## потрібен її НОМЕР у переліку, слот і те, чи вона вже на тілі.
@rpc("authority", "call_remote", "reliable")
func client_things(things: Array, stacks: Array) -> void:
	if hud != null:
		hud.set_things(things, stacks)
	# Показ дивиться на гроші, щоб не йти до крамаря з порожньою кишенею.
	# Віддав усі — стосу «гроші» в торбі немає, і число мусить стати 0.
	view.money = 0
	for row: Dictionary in stacks:
		if str(row.get("назва", "")) == "гроші":
			view.money = int(row.get("скільки", 0))


## Що гравець уміє — для вікна «Скіли», з якого скіли тягнуть на панель.
@rpc("authority", "call_remote", "reliable")
func client_skills(list: Array) -> void:
	if hud != null:
		hud.set_skills(list)


## Свої стати — для сторінки «Стати» в меню.
##
## Шлеться рідко: при вході й коли числа могли змінитись (рівень,
## спорядження). Щотіку тут нема чого гнати — це не смуга здоров'я.
@rpc("authority", "call_remote", "reliable")
func client_stats(data: Dictionary) -> void:
	if hud != null:
		hud.set_stats(data)


## Ціль вийшла з-під руки, поки летів удар (В-2): доганяй і бий знову.
@rpc("authority", "call_remote", "reliable")
func client_chase(action: String) -> void:
	view.chase(action)


## Обмін (П-218): кличуть, стіл змінився, стіл закрито.
@rpc("authority", "call_remote", "reliable")
func client_trade_invite(from: String, _wait: float) -> void:
	if view.trade_invited():
		return
	if hud != null:
		hud.ask_trade_invite(from)


@rpc("authority", "call_remote", "reliable")
func client_trade_invite_gone() -> void:
	if hud != null:
		hud.trade_invite_gone()


@rpc("authority", "call_remote", "reliable")
func client_trade_table(with: String, table: Dictionary) -> void:
	view.trade_table(table)
	if hud != null:
		hud.show_trade(with, table)


@rpc("authority", "call_remote", "reliable")
func client_trade_closed(why: String) -> void:
	view.trade_closed(why)
	if hud != null:
		hud.hide_trade()


## Скільки в істоти здоров'я всього — щоб смуга цілі мала від чого рахувати.
@rpc("authority", "call_remote", "reliable")
func client_vitals(id: int, hp: int, max_hp: int) -> void:
	if hud != null:
		hud.set_vitals(id, hp, max_hp)


## Розкладка панелі з data/bar.json (П-58).
@rpc("authority", "call_remote", "reliable")
func client_bar(bar: PackedStringArray, strips: int = 1) -> void:
	if hud != null:
		hud.set_bar(Array(bar), strips)
	# Ту саму розкладку знає й ввід: без неї він не скаже, чи потрібна
	# натиснутій дії відстань (підхід до цілі).
	view.set_bar(Array(bar))


## Свої числа щотіку: здоров'я, мана, відкат, замах, черга.
@rpc("authority", "call_remote", "unreliable_ordered")
func client_self(hp: int, max_hp: int, mp: int, max_mp: int,
		slots: PackedFloat32Array, busy_in: float,
		queue: PackedStringArray, level: int, respect: int,
		need: int) -> void:
	if _my_level != level:
		_my_level = level
		_tags_again()
	if hud != null:
		hud.update_self(hp, max_hp, mp, max_mp, slots, busy_in, Array(queue))
		hud.update_level(level, respect, need)


## Бафи й дебафи: свої й вибраної цілі (рядки — `_states_row`).
@rpc("authority", "call_remote", "reliable")
func client_states(mine: Array, target: int, theirs: Array) -> void:
	if hud != null:
		hud.set_states(mine, target, theirs)
	# Під штрафом світу вибраний монстр підсвічується фіолетовим (слово
	# замовника 19.09.2026, П-213). Стани цілі приходять саме сюди.
	var who: Node = creatures.get(target)
	if who != null:
		var cursed := false
		for row: Array in theirs:
			if str(row[0]).begins_with(DungeonLife.PENALTY_NAME):
				cursed = true
		SelectMark.tint(who, SelectMark.CURSED if cursed
				else SelectMark.TONE)


## Хтось почав читати скіл: у нього над головою смуга.
@rpc("authority", "call_remote", "reliable")
func client_cast(id: int, name: String, seconds: float) -> void:
	if hud != null:
		hud.cast_started(id, name, seconds)
	# `is_casting()` на клієнтській копії досі ніхто не виставляв — лише
	# HUD-смугу. Показу рухів (П-162) потрібен той самий прапорець на
	# істоті, а не окремий канал.
	var a: Node = creatures.get(id)
	if a != null:
		a.start_cast(name, seconds, 0)
	if view != null:
		view.cast_started(id)


## Дочитав або збили.
@rpc("authority", "call_remote", "reliable")
func client_cast_end(id: int, done: bool) -> void:
	if hud != null:
		hud.cast_ended(id, done)
	var a: Node = creatures.get(id)
	if a != null:
		a.stop_cast()
	if view != null:
		view.cast_ended(id)


## Мешканець відповів: вікно розмови (П-132).
@rpc("authority", "call_remote", "reliable")
func client_talk(at: int, title: String, trades: bool,
		warehouse_keeper: bool = false, guild_master: bool = false,
		priest: bool = false, mage: bool = false,
		super_buff: bool = false, smith: bool = false) -> void:
	if hud != null:
		hud.show_talk(at, title, trades, warehouse_keeper, guild_master,
				priest, mage, super_buff, smith)


## Коваль: що в тебе є, почому ремонт і що просить зачарування.
@rpc("authority", "call_remote", "reliable")
func client_smith(at: int, title: String, rows: Array, money: int) -> void:
	if hud != null:
		hud.show_smith(at, title, rows, money)


## Майстер магії: куди й почому (20.09.2026).
@rpc("authority", "call_remote", "reliable")
func client_ports(at: int, title: String, towns: Array,
		money: int) -> void:
	if hud != null:
		hud.show_ports(at, title, towns, money)


## Прилавок: що продають і за скільки. `buyback` — у відсотках, щоб у
## вікні можна було чесно написати, скільки дадуть за твоє.
@rpc("authority", "call_remote", "reliable")
func client_shop(at: int, title: String, goods: Array,
		buyback: int) -> void:
	if hud != null:
		hud.show_shop(at, title, goods, buyback)


## Вікно складу: список того, що вже там лежить (крок 5, П-145).
@rpc("authority", "call_remote", "reliable")
func client_warehouse(at: int, things: Array, stacks: Array) -> void:
	if hud != null:
		hud.show_warehouse(at)
		hud.set_warehouse(things, stacks)


## Вікно гільдії: усі скіли з даних і чи вже вивчені, щоб гравець бачив,
## що можна, а що ще ні, ще до підходу до вимог.
@rpc("authority", "call_remote", "reliable")
func client_guild(at: int, rows: Array,
		about: Dictionary = {}) -> void:
	if hud != null:
		hud.show_guild(at, rows, about)


## Хтось замахнувся: показуємо рух рукою. `armed` — зброя чи голі руки
## (П-162): бере рішення сервер (`combat.attack`), клієнту чуже
## спорядження не відомо.
@rpc("authority", "call_remote", "reliable")
func client_swing(id: int, armed: bool = false) -> void:
	var a: Node = creatures.get(id)
	# Людину веде view.swung() (П-162: Punch_Jab/Cross чи Sword_Attack) —
	# старий generic swing() тут же одразу перебив би той самий вибір.
	if a != null and not a.has_method("apply_sex"):
		var body: Node3D = a.model()
		if body != null:
			body.swing()
	if view != null:
		view.swung(id, armed)


## Число шкоди над головою.
@rpc("authority", "call_remote", "reliable")
func client_damage(id: int, amount: int, behind: bool) -> void:
	if hud != null:
		hud.damage(id, amount, behind)


@rpc("authority", "call_remote", "reliable")
func client_died(id: int) -> void:
	if creatures.has(id):
		creatures[id].hp = 0
		creatures[id].lay_down()
	if hud != null:
		hud.set_hp(id, 0)
		if id == multiplayer.get_unique_id():
			hud.died()
	# Помер із вибраним мешканцем — вибір знімається (П-135). Інакше
	# після підйому в місті ім'я крамарки й далі стоїть на екрані, а
	# «удар» означає «заговорити» й жене персонажа через усю мапу до
	# місця, де його щойно вбили. `_wait_talk` (підхід у процесі)
	# знімався й раніше, сам вибір — ні.
	if id == multiplayer.get_unique_id() and view != null:
		view.forget_resident()


@rpc("authority", "call_remote", "reliable")
func client_revive(id: int, hp: int) -> void:
	if creatures.has(id):
		creatures[id].hp = hp
		creatures[id].stand_up()
	if hud != null:
		hud.set_hp(id, hp)
		if id == multiplayer.get_unique_id():
			hud.revived()


@rpc("authority", "call_remote", "reliable")
func client_notice(text: String) -> void:
	print("[гра] ", text)
	if hud != null:
		hud.notice(text)


@rpc("authority", "call_remote", "reliable")
func client_despawn(id: int) -> void:
	_titles.erase(id)
	if creatures.has(id):
		creatures[id].queue_free()
		creatures.erase(id)
	if hud != null:
		hud.forget(id)


@rpc("authority", "call_remote", "unreliable_ordered")
func client_positions(snapshot: Dictionary) -> void:
	view.apply_positions(snapshot)


func _unhandled_input(event: InputEvent) -> void:
	if not Net.is_server:
		view.input(event)


# ── спільне: істоти у сцені ───────────────────────────────────────────

## Висота землі в точці — питає спавнер, щоб не садити монстрів у ґрунт.
## Нижче землі на стільки метрів — це вже не «стоїть на схилі», а
## «провалився». Три метри дає запас на нерівність під ногами й на те,
## що збережена висота — центр тіла, а не підошва.
const FELL_THROUGH := 3.0


## Чи ціле те місце, де персонаж вийшов із гри. Порожній рядок — ціле;
## інакше рядок каже, ЩО саме з ним не так (P3: мовчки не ковтаємо).
##
## Знайдено 19.09.2026 на живій грі: персонаж провалився крізь землю в
## столиці світу 2, сервер зберіг `y = -156 895`, і кожен наступний вхід
## клав його назад у те саме падіння — гравець тонув, не встигши нічого
## зробити.
func _place_gone(at: Vector3) -> String:
	# Підземелля стоять поза межами світу навмисно (П-167). Якщо те саме
	# підземелля ще відкрите — місце ціле, гравець просто в ньому.
	if dungeons != null:
		var floor_y: float = dungeons.floor_at(at.x, at.z)
		if not is_nan(floor_y):
			return "" if at.y >= floor_y - FELL_THROUGH \
					else "провалився крізь підлогу підземелля"
	if not _inside_world(at):
		# Сюди ж потрапляє й підземелля, яке закрилось: вони не
		# зберігаються, тож після перезапуску сервера гравець опинився б
		# на 40 м над морем без підлоги під ногами.
		return "місця вже немає: поза межами світу"
	var ground := ground_at(at.x, at.z)
	if at.y < ground - FELL_THROUGH:
		return "під землею на %.0f м" % (ground - at.y)
	return ""


## Перевірка місця при кожному вході (слово замовника 19.09.2026:
## «перевірялось чи доступне місце, можливо воно зникло, чи змінилось,
## то телепортувати гравця в найближче місто»).
##
## Кличеться після читання з бази — саме там лежить те, де гравця застав
## вихід, і саме йому не можна вірити на слово.
func _rescue(a: Node3D, who: String) -> void:
	var at: Vector3 = a.global_position
	var why := _place_gone(at)
	if why == "":
		return
	var town := _nearest_town(at)
	var high := ground_at(town.x, town.y)
	# 6 м запасу, як при вході й у `combat.send_home`: падає сам і сідає
	# на видиму поверхню, а не в ґрунт.
	a.place_at(Vector3(town.x, high + 6.0, town.y), a.facing)
	print("[база] ‼ %s: %s — переніс у найближче місто (%.0f, %.0f)"
			% [who, why, town.x, town.y])


## Найближче місто до точки. Села версії 2 сюди теж потрапляють —
## `towns()` їх віддає разом із містами, і для загубленого гравця село
## нічим не гірше: це рівний майданчик із землею під ногами.
##
## Міст у мапі немає взагалі — лишається (0,0): там стоїть вхід у світ.
func _nearest_town(at: Vector3) -> Vector2:
	var land: Node = get_node_or_null("Landscape")
	if land == null or not land.has_method("towns"):
		return Vector2.ZERO
	var best := Vector2.ZERO
	var best_far := INF
	for town: Dictionary in land.towns():
		var mid: Array = town.get("центр", [0, 0, 0])
		var spot := Vector2(float(mid[0]), float(mid[2]))
		var far: float = Vector2(at.x, at.z).distance_to(spot)
		if far < best_far:
			best_far = far
			best = spot
	return best


## Чи точка взагалі в цьому світі. Світи міняються прапорцем `--світ2`,
## а персонаж у базі один на обидва: збережений за 1748 м від столиці
## світу 2 і відкритий у світі 600 м опиниться далеко поза картою.
func _inside_world(at: Vector3) -> bool:
	var earth: Dictionary = data.map.get("земля", {})
	var side := float(earth.get("сторона", 0.0))
	if side <= 0.0:
		return true
	var from: Array = earth.get("початок", [-side * 0.5, -side * 0.5])
	var x0 := float(from[0])
	var z0 := float(from[1])
	return at.x >= x0 and at.x <= x0 + side \
			and at.z >= z0 and at.z <= z0 + side


func ground_at(x: float, z: float) -> float:
	# У підземеллі земля — його підлога, а не рельєф світу під ним
	# (П-190): інакше монстр з'являвся б за 40 м під склепом.
	if dungeons != null:
		var below := dungeons.floor_at(x, z)
		if not is_nan(below):
			return below
	var land: Node = get_node_or_null("Landscape")
	return land.height_at(x, z) if land != null \
			and land.has_method("height_at") else 0.0


## Створити істоту й внести в таблицю. Вузли — робота світу, тому
## створення й знищення лишається тут, а модулі про сцену не знають.
func spawn(id: int, pos: Vector3) -> Node3D:
	var a: Node3D = MOB.instantiate() if id < 0 else AVATAR.instantiate()
	a.name = ("Mob%d" % -id) if id < 0 else ("Avatar%d" % id)
	add_child(a)
	a.global_position = pos
	a.server_position = pos
	creatures[id] = a
	return a


## Прибрати істоту зі світу й сказати про це всім, хто її бачив.
func remove(id: int) -> void:
	if creatures.has(id):
		creatures[id].queue_free()
		creatures.erase(id)
	for peer in vision.forget(id):
		rpc_id(peer, "client_despawn", id)
