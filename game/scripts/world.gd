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
var runes: Runes
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
	combat.skills = data.skills
	combat.progress = Progress.new(data.levels)
	combat.goods = data.items
	actions = Actions.new(creatures, vision, combat, link)
	actions.goods = data.items
	mobs = MobAI.new(creatures, combat)
	spawner = Spawner.new(creatures, self, data)
	shop = Shop.new(data)
	warehouse = Warehouse.new()
	runes = Runes.new(data.skills)
	view = ClientView.new(creatures, self, link)

	# Краєвид будується однаково й на сервері, і в клієнта: серверові
	# потрібні стіни, щоб крізь будинки не бігали, клієнтові — картинка.
	# Дерева й паркан підвантажуються ділянками (П-63) — лише в клієнта:
	# сервер тримає зіткнення й монстрів скрізь одразу, як і раніше.
	var land: Node = get_node_or_null("Landscape")
	if land != null:
		land.build(data.map, not Net.is_server)

	if Net.is_server:
		store = Store.new()
		add_child(store)
		store.setup(Net.db)
		if OS.get_cmdline_user_args().has("--перевірка-бази"):
			store.answered.connect(func(name: String, reply: Dictionary) -> void:
					print("[перевірка] %s -> %s" % [name, reply]))
			store.call_rpc("login", {"login": "конан", "password": "таємниця"})
		multiplayer.peer_disconnected.connect(_on_left)
		if OS.get_cmdline_user_args().has("--полігон"):
			_range()
		else:
			spawner.start(_zones())
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
	file.store_string(JSON.stringify({
			"номер": OS.get_process_id(),
			"порт": Net.PORT,
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


func _range() -> void:
	for i in RANGE_STEPS.size():
		var at := Vector3(RANGE_STEPS[i], 0.0, 0.0)
		at.y = ground_at(at.x, at.z) + 1.0
		var mob: Node = spawn(-(i + 1), at)
		mob.setup(at, RANGE_KIND, false, data.for_kind(RANGE_KIND))
	print("[полігон] %s, штук %d, найближчий за %.1f м"
			% [data.for_kind(RANGE_KIND).get("назва", "?"),
			   RANGE_STEPS.size(), RANGE_STEPS[0]])


## Сервер іде — мітку прибираємо. На цьому не можна будувати: заміряно
## 02.09.2026, що при `kill` (як робить `./play.sh --stop`) цей виклик до
## нас не доходить, і мітка лишається на диску. Тому сторінка вірить їй
## ЛИШЕ при зайнятому порті, а новий сервер стирає стару мітку в `_ready`.
func _exit_tree() -> void:
	if Net.is_server:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(READY_MARK))


func _physics_process(delta: float) -> void:
	if Net.is_server:
		for a in creatures.values():
			a.server_step(delta)
		for id in creatures:
			if id < 0:
				mobs.think(id, delta)
			else:
				actions.pump(id)
		combat.tick_casts(delta)
		for id in combat.clear_corpses():
			remove(id)
		spawner.tick(delta)
		_tick_sanctuaries()
		_tick_water(delta)
		if store != null and store.due(delta):
			_save_everyone()
		# Числа правляться в data/*.json під час гри: помітив зміну —
		# роздав живим монстрам (крок 1.2).
		if data.poll(delta):
			print("[дані] нові числа роздано монстрам: %d"
					% spawner.apply_tuning())
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
				other.level, other.sex)
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
	# баф. Відбиток дешевий — п'ять чисел і рівень.
	var mark := "%d/%d/%d/%d/%d/%d/%d" % [me.level, me.stat_points,
			me.stats.strength, me.stats.agility, me.stats.stamina,
			me.stats.intellect, me.stats.sense]
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

## Увійти в гру без бази: як було до кроку 5. Якщо база є, цей шлях
## закритий — інакше можна було б зайти чужим персонажем, назвавши ім'я.
@rpc("any_peer", "call_remote", "reliable")
func announce_ready(character: String = "") -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
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
	store.call_rpc("register" if register else "login",
			{"login": login, "password": password})


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
			"password": who["пароль"], "name": name, "race": race, "sex": sex})


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
	var allowed: bool = action in BASIC_SLOTS
	if not allowed and action.begins_with(Actions.SKILL_PREFIX):
		allowed = a.knows(action.substr(Actions.SKILL_PREFIX.length()))
	if not allowed:
		link.notice(id, "цього на панель не покласти")
		return
	a.bar[slot] = action
	rpc_id(id, "client_bar", PackedStringArray(a.bar))


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


## Святині: місця, де відновлюють швидко (П-113). Перевіряємо щокадру —
## їх одиниці, а гравців десяток.
func _tick_sanctuaries() -> void:
	var places := find_children("*", "Sanctuary", true, false)
	if places.is_empty():
		return
	for id in creatures:
		if id < 0:
			continue
		var who: Node3D = creatures[id]
		var rate := 0.0
		for place: Sanctuary in places:
			if not place.has_point(who.global_position):
				continue
			if who.in_fight > 0.0 and not place.in_fight:
				continue
			rate = maxf(rate, place.restore)
		if rate > 0.0 and who.in_sanctuary <= 0.0:
			link.notice(id, "святиня: тут відновлюєшся швидко")
		who.in_sanctuary = rate


## Зони появи — вузли `MobZone` у сцені. Їх малюють у редакторі, тому
## сервер їх не вигадує, а знаходить.
func _zones() -> Array:
	var found := find_children("*", "MobZone", true, false)
	if found.is_empty():
		push_warning("[світ] у сцені немає жодної зони появи — монстрів не буде")
		print("[світ] ‼ у сцені немає жодної зони появи")
	return found


func _on_joined(id: int) -> void:
	# 6 м запасу, як і в spawner.gd: падає сам, сідає на видиму поверхню.
	var a := spawn(id, Vector3(0, ground_at(0.0, 0.0) + 6.0, 0))
	a.account = _signed.get(id, {}).get("логін", "")
	# Прочитане з бази накладається, щойно прийде відповідь: гра не жде
	# базу, а база не жде гру.
	if store != null and store.works():
		store.loaded.connect(func(name: String, row: Dictionary) -> void:
				if name != _names.get(id, "") or not creatures.has(id):
					return
				Store.apply_row(creatures[id], row, data.items)
				# Стартові скіли даються ПІСЛЯ читання: інакше прочитане
				# з бази («скілів немає») затирає їх, і новий персонаж
				# заходить у світ ні з чим. Спіймано на живому прогоні.
				if creatures[id].learned.is_empty():
					for key in data.starting_skills:
						creatures[id].learn(key,
								int(data.starting_skills[key]))
				creatures[id].refresh_stats()
				if row.is_empty():
					print("[база] %s новий, починає з нуля" % name)
				else:
					print("[база] %s повернувся: рівень %d, поваги %d"
							% [name, creatures[id].level,
							   creatures[id].respect])
				rpc_id(id, "client_place", id, creatures[id].global_position,
						creatures[id].facing), CONNECT_ONE_SHOT)
		store.load_character(_names[id])
	a.bar = data.bar if not data.bar.is_empty() else a.bar
	# Стартові скіли — заглушка до рун і крамниць (П-97).
	for skill_key in data.starting_skills:
		a.learn(skill_key, int(data.starting_skills[skill_key]))
	# Себе гравець бачить завжди; решту роздасть звірка зон бачення.
	rpc_id(id, "client_spawn", id, a.global_position, a.facing,
			_kind_of(a), _names.get(id, ""), a.level, a.sex)
	rpc_id(id, "client_vision", a.vision_radius())
	rpc_id(id, "client_vitals", id, a.hp, a.stats.max_hp())
	rpc_id(id, "client_bar", PackedStringArray(a.bar))
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
			who.craft == "завідувач складу", who.craft == "гільдмайстер")


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


## Продати складану річ — увесь стос одразу.
@rpc("any_peer", "call_remote", "reliable")
func ask_sell_stack(at: int, name: String) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: NPC = _resident(id, at)
	if who == null or not who.trades():
		return
	var a: Node = creatures.get(id)
	var count := int(a.items.get(name, 0))
	var paid := shop.buy_price(name) * count
	var why: String = shop.sell_stack(a, name)
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
	if who == null or who.craft != "завідувач складу":
		return
	send_things(id)
	send_warehouse(id, at)


@rpc("any_peer", "call_remote", "reliable")
func ask_store_thing(at: int, thing_at: int) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: NPC = _resident(id, at)
	if who == null or who.craft != "завідувач складу":
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
	if who == null or who.craft != "завідувач складу":
		return
	var a: Node = creatures.get(id)
	var why: String = warehouse.withdraw_thing(a, thing_at)
	if why != "":
		link.notice(id, why)
		return
	_after_warehouse(id, a, at)


@rpc("any_peer", "call_remote", "reliable")
func ask_store_stack(at: int, name: String) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: NPC = _resident(id, at)
	if who == null or who.craft != "завідувач складу":
		return
	var a: Node = creatures.get(id)
	var why: String = warehouse.store_stack(a, name)
	if why != "":
		link.notice(id, why)
		return
	_after_warehouse(id, a, at)


@rpc("any_peer", "call_remote", "reliable")
func ask_withdraw_stack(at: int, name: String) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: NPC = _resident(id, at)
	if who == null or who.craft != "завідувач складу":
		return
	var a: Node = creatures.get(id)
	var why: String = warehouse.withdraw_stack(a, name)
	if why != "":
		link.notice(id, why)
		return
	_after_warehouse(id, a, at)


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
		})
	return out


@rpc("any_peer", "call_remote", "reliable")
func ask_guild(at: int) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: NPC = _resident(id, at)
	if who == null or who.craft != "гільдмайстер":
		return
	var a: Node = creatures.get(id)
	rpc_id(id, "client_guild", at, _guild_rows(a))


@rpc("any_peer", "call_remote", "reliable")
func ask_learn_skill(at: int, key: String) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: NPC = _resident(id, at)
	if who == null or who.craft != "гільдмайстер":
		return
	var a: Node = creatures.get(id)
	var why: String = runes.learn(a, key)
	if why != "":
		link.notice(id, why)
		return
	link.notice(id, "вивчено: %s" % data.skills.get_skill(key).name)
	send_stats(id)
	rpc_id(id, "client_guild", at, _guild_rows(a))


@rpc("any_peer", "call_remote", "reliable")
func ask_raise_skill(at: int, key: String) -> void:
	if not Net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: NPC = _resident(id, at)
	if who == null or who.craft != "гільдмайстер":
		return
	var a: Node = creatures.get(id)
	var why: String = runes.raise(a, key)
	if why != "":
		link.notice(id, why)
		return
	link.notice(id, "піднято рівень: %s → %d"
			% [data.skills.get_skill(key).name, int(a.learned[key])])
	send_stats(id)
	rpc_id(id, "client_guild", at, _guild_rows(a))


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
	_names.erase(id)
	_signed.erase(id)
	_stats_mark.erase(id)
	_skills_mark.erase(id)
	_bag_mark.erase(id)
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
		title: String = "", level: int = 1, sex: String = "чоловік") -> void:
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
			a.apply_sex(sex)
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
		hud.wants_sell_stack.connect(func(at: int, name: String) -> void:
				rpc_id(1, "ask_sell_stack", at, name))
		# Склад і гільдія (П-145) — та сама «спитай, сервер вирішить».
		hud.wants_warehouse.connect(func(at: int) -> void:
				rpc_id(1, "ask_warehouse", at))
		hud.wants_store_thing.connect(func(at: int, thing_at: int) -> void:
				rpc_id(1, "ask_store_thing", at, thing_at))
		hud.wants_store_stack.connect(func(at: int, name: String) -> void:
				rpc_id(1, "ask_store_stack", at, name))
		hud.wants_withdraw_thing.connect(func(at: int, thing_at: int) -> void:
				rpc_id(1, "ask_withdraw_thing", at, thing_at))
		hud.wants_withdraw_stack.connect(func(at: int, name: String) -> void:
				rpc_id(1, "ask_withdraw_stack", at, name))
		hud.wants_guild.connect(func(at: int) -> void:
				rpc_id(1, "ask_guild", at))
		hud.wants_learn_skill.connect(func(at: int, key: String) -> void:
				rpc_id(1, "ask_learn_skill", at, key))
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


## Скільки в істоти здоров'я всього — щоб смуга цілі мала від чого рахувати.
@rpc("authority", "call_remote", "reliable")
func client_vitals(id: int, hp: int, max_hp: int) -> void:
	if hud != null:
		hud.set_vitals(id, hp, max_hp)


## Розкладка панелі з data/bar.json (П-58).
@rpc("authority", "call_remote", "reliable")
func client_bar(bar: PackedStringArray) -> void:
	if hud != null:
		hud.set_bar(Array(bar))
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


## Хтось почав читати скіл: у нього над головою смуга.
@rpc("authority", "call_remote", "reliable")
func client_cast(id: int, name: String, seconds: float) -> void:
	if hud != null:
		hud.cast_started(id, name, seconds)


## Дочитав або збили.
@rpc("authority", "call_remote", "reliable")
func client_cast_end(id: int, done: bool) -> void:
	if hud != null:
		hud.cast_ended(id, done)


## Мешканець відповів: вікно розмови (П-132).
@rpc("authority", "call_remote", "reliable")
func client_talk(at: int, title: String, trades: bool,
		warehouse_keeper: bool = false, guild_master: bool = false) -> void:
	if hud != null:
		hud.show_talk(at, title, trades, warehouse_keeper, guild_master)


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
func client_guild(at: int, rows: Array) -> void:
	if hud != null:
		hud.show_guild(at, rows)


## Хтось замахнувся: показуємо рух рукою.
@rpc("authority", "call_remote", "reliable")
func client_swing(id: int) -> void:
	if creatures.has(id):
		var body: Node3D = creatures[id].model()
		if body != null:
			body.swing()


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
func ground_at(x: float, z: float) -> float:
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
