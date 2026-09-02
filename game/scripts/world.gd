extends Node3D
## Світ: тонкий шар мережі й сама сцена.
##
## На сервері живуть справжні персонажі; клієнт отримує їхні позиції й
## малює. Розсилка АДРЕСНА — окреме повідомлення на кожне з'єднання, а не
## широкомовне. Так зроблено навмисно: сервер шле кожному лише те, що той
## бачить (П-43). Готові вузли синхронізації Godot розсилають усім
## однаково і для цього не годяться.
##
## Уся робота переїхала в модулі (крок 1.1 у ПЛАН.md); тут лишилися самі
## `@rpc` і створення істот. Чому саме так: шлях вузла має збігатися на
## клієнті й сервері, і возитися з цим для кожного модуля не варто.
##
##     vision.gd       хто кого бачить
##     combat.gd       удар, шкода, смерть, строк трупа
##     actions.gd      черга дій, цілі, вміння
##     mob_ai.gd       поведінка монстрів
##     spawner.gd      гнізда й поява
##     mob_zone.gd     форма зони появи: те, що намальовано в редакторі
##     game_data.gd    числа з дані/*.json, із перечитуванням на ходу
##     client_view.gd  згладжування й ввід клієнта
##     hud.gd          що гравець бачить поверх світу
##     messenger.gd    єдиний вихід на клієнтів

const AVATAR := preload("res://scenes/avatar.tscn")
const MOB := preload("res://scenes/mob.tscn")
## Скільки разів на секунду сервер розсилає позиції.
const TICK_HZ := 20.0

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


func _ready() -> void:
	data = GameData.new()
	data.load_all()
	vision = Vision.new(creatures)
	link = Messenger.new(self, vision)
	combat = Combat.new(creatures, link)
	combat.skills = data.skills
	combat.progress = Progress.new(data.levels)
	combat.goods = data.items
	actions = Actions.new(creatures, vision, combat, link)
	actions.goods = data.items
	mobs = MobAI.new(creatures, combat)
	spawner = Spawner.new(creatures, self, data)
	view = ClientView.new(creatures, self, link)

	# Краєвид будується однаково й на сервері, і в клієнта: серверові
	# потрібні стіни, щоб крізь будинки не бігали, клієнтові — картинка.
	var land: Node = get_node_or_null("Landscape")
	if land != null:
		land.build(data.map)

	if Net.is_server:
		store = Store.new()
		add_child(store)
		store.setup(Net.db)
		multiplayer.peer_disconnected.connect(_on_left)
		spawner.start(_zones())
		print("[світ] сервер чекає гравців")
	else:
		# Спавн просимо самі, коли сцена вже здатна приймати виклики.
		# Якби сервер спавнив за подією з'єднання, повідомлення могло б
		# прийти раніше, ніж клієнт готовий, і загубитись.
		multiplayer.connected_to_server.connect(
				func() -> void: rpc_id(1, "announce_ready", Net.character))


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
		if store != null and store.due(delta):
			_save_everyone()
		# Числа правляться в дані/*.json під час гри: помітив зміну —
		# роздав живим монстрам (крок 1.2).
		if data.poll(delta):
			print("[дані] нові числа роздано монстрам: %d"
					% spawner.apply_tuning())
		return

	var me: Node = creatures.get(multiplayer.get_unique_id())
	if me != null and me.is_local:
		rpc_id(1, "submit_intent", me.sample_intent())


func _process(delta: float) -> void:
	if not Net.is_server:
		view.smooth(delta)
		view.demo(delta)
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
		rpc_id(peer, "client_spawn", id, other.global_position, other.facing)
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
	var a := spawn(id, Vector3(0, 1.5, 0))
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
	rpc_id(id, "client_spawn", id, a.global_position, a.facing)
	rpc_id(id, "client_vision", a.vision_radius())
	rpc_id(id, "client_vitals", id, a.hp, a.stats.max_hp())
	rpc_id(id, "client_bar", PackedStringArray(a.bar))
	link.bag(id, a)
	vision.watch(id)
	print("[світ] приєднався %d, усього %d" % [id, creatures.size()])


func _on_left(id: int) -> void:
	# Зберегти ДО того, як істота зникне: інакше зберігати вже нічого.
	_save_one(id)
	_names.erase(id)
	_signed.erase(id)
	vision.drop_watcher(id)
	remove(id)
	print("[світ] пішов %d, лишилось %d" % [id, creatures.size()])


# ── клієнт: що надходить від сервера ──────────────────────────────────

@rpc("authority", "call_remote", "reliable")
func client_spawn(id: int, pos: Vector3, look: float) -> void:
	if creatures.has(id):
		return
	var a := spawn(id, pos)
	a.place_at(pos, look)
	if id == multiplayer.get_unique_id():
		a.become_local()
		view.entered_world()
		hud = HUD.new()
		hud.setup(self)
		add_child(hud)


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


@rpc("authority", "call_remote", "reliable")
func client_target(id: int) -> void:
	var me: Node = creatures.get(multiplayer.get_unique_id())
	if me != null:
		me.target_id = id
	if hud != null:
		hud.set_target(id)


@rpc("authority", "call_remote", "reliable")
func client_hp(id: int, hp: int) -> void:
	if creatures.has(id):
		creatures[id].hp = hp
	if hud != null:
		hud.set_hp(id, hp)


## Скільки в істоти здоров'я всього — щоб смуга цілі мала від чого рахувати.
@rpc("authority", "call_remote", "reliable")
func client_vitals(id: int, hp: int, max_hp: int) -> void:
	if hud != null:
		hud.set_vitals(id, hp, max_hp)


## Розкладка панелі з дані/панель.json (П-58).
@rpc("authority", "call_remote", "reliable")
func client_bar(bar: PackedStringArray) -> void:
	if hud != null:
		hud.set_bar(Array(bar))


## Свої числа щотіку: здоров'я, мана, відкат, замах, черга.
@rpc("authority", "call_remote", "unreliable_ordered")
func client_self(hp: int, max_hp: int, mp: int, max_mp: int,
		slots: PackedFloat32Array, busy_in: float,
		queue: PackedStringArray, level: int, respect: int,
		need: int) -> void:
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


## Торба: вдягнене й решта. Шлеться після кожної зміни.
@rpc("authority", "call_remote", "reliable")
func client_bag(worn: PackedStringArray, carried: PackedStringArray) -> void:
	if hud != null:
		hud.show_bag(Array(worn), Array(carried))


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


@rpc("authority", "call_remote", "reliable")
func client_revive(id: int, hp: int) -> void:
	if creatures.has(id):
		creatures[id].hp = hp
		creatures[id].stand_up()
	if hud != null:
		hud.set_hp(id, hp)


@rpc("authority", "call_remote", "reliable")
func client_notice(text: String) -> void:
	print("[гра] ", text)
	if hud != null:
		hud.notice(text)


@rpc("authority", "call_remote", "reliable")
func client_despawn(id: int) -> void:
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
