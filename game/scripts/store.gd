class_name Store
extends Node
## Збереження персонажів (крок 3, друга половина).
##
## База — **Postgres**, а говоримо ми з нею через **PostgREST** (П-76,
## П-92): готовий бінарник перед базою, який віддає таблиці як REST.
## Godot уміє HTTP рідно, а SQL і ролі лишаються замовникові.
##
## Тут навмисно немає жодного SQL: усе, що вміє цей клас, — чотири
## звертання до `/персонажі`. Схема бази й права — робота Postgres.
##
## **Асинхронно.** Запит не спиняє кадр світу: сервер шле й забуває, а
## відповідь приходить сигналом. Саме через це й обрано PostgREST, а не
## драйвер (див. П-92).

signal loaded(name: String, row: Dictionary)
signal saved(name: String, ok: bool)

## Куди стукати. Порожня адреса означає «бази немає» — сервер тоді працює
## як і раніше, просто нічого не зберігає, і каже про це вголос.
var base_url := ""
## Раз на скільки секунд зберігати тих, хто в грі.
var every := 30.0

var _since := 0.0
## Назви таблиці й стовпців — ЛАТИНОЮ, і це навмисно. Кирилиця в SQL
## вимагає лапок у кожному запиті, а в адресі PostgREST — ще й кодування
## відсотками; жодної користі, самі граблі. Українська лишається там, де
## її читають люди: у коді, документах і на екрані.
var _table := "characters"


func setup(url: String, seconds: float = 30.0) -> void:
	base_url = url.rstrip("/")
	every = seconds
	if base_url == "":
		print("[база] адреси немає — гра йде без збереження")
	else:
		print("[база] %s, зберігаю раз на %.0f с" % [base_url, every])


func works() -> bool:
	return base_url != ""


## Прочитати персонажа за іменем. Відповідь приходить сигналом `loaded`.
func load_character(name: String) -> void:
	if not works():
		loaded.emit(name, {})
		return
	var request := HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(
			func(result: int, code: int, _headers: PackedStringArray,
					body: PackedByteArray) -> void:
				request.queue_free()
				var row := {}
				if code == 200:
					var parsed: Variant = JSON.parse_string(
							body.get_string_from_utf8())
					if parsed is Array and not parsed.is_empty():
						row = parsed[0]
				elif result != HTTPRequest.RESULT_SUCCESS or code >= 400:
					push_error("[база] читання %s: код %d" % [name, code])
					print("[база] ‼ читання %s не вдалось, код %d"
							% [name, code])
				loaded.emit(name, row))
	var url := "%s/%s?name=eq.%s&world=eq.%s" \
			% [base_url, _table, name.uri_encode(),
			GameData.world_key().uri_encode()]
	request.request(url)


## Записати персонажа. PostgREST уміє «додати або оновити» одним запитом,
## якщо попросити `resolution=merge-duplicates` — так не треба знати
## наперед, чи персонаж уже є.
func save_character(name: String, row: Dictionary) -> void:
	if not works():
		saved.emit(name, false)
		return
	var request := HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(
			func(result: int, code: int, _headers: PackedStringArray,
					_body: PackedByteArray) -> void:
				request.queue_free()
				var ok: bool = result == HTTPRequest.RESULT_SUCCESS \
						and code >= 200 and code < 300
				if not ok:
					push_error("[база] запис %s: код %d" % [name, code])
					print("[база] ‼ запис %s не вдався, код %d" % [name, code])
				saved.emit(name, ok))
	var headers := PackedStringArray([
			"Content-Type: application/json",
			"Prefer: resolution=merge-duplicates"])
	request.request("%s/%s" % [base_url, _table], headers,
			HTTPClient.METHOD_POST, JSON.stringify(row))


## Виклик функції в базі: `POST /rpc/ім_я`. Так ходять акаунти (крок 5) —
## перевірка пароля робиться в самому Postgres, а сюди приходить лише
## відповідь.
##
## Пароль летить від клієнта до сервера гри, а звідти в базу. Поки все на
## одній машині, це не діра; коли сервер вийде назовні, з'єднання має
## стати захищеним — записано в П-114.
signal answered(name: String, reply: Dictionary)


func call_rpc(name: String, args: Dictionary) -> void:
	if not works():
		answered.emit(name, {"ok": false, "why": "бази немає"})
		return
	var request := HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(
			func(result: int, code: int, _headers: PackedStringArray,
					body: PackedByteArray) -> void:
				request.queue_free()
				var reply := {}
				if code == 200:
					var parsed: Variant = JSON.parse_string(
							body.get_string_from_utf8())
					if parsed is Dictionary:
						reply = parsed
				else:
					# Друкуємо і код відповіді, і причину самого запиту:
					# «код 0» без причини нічого не каже — це може бути і
					# збій з'єднання, і скасований запит.
					push_error("[база] %s: код %d, причина %d"
							% [name, code, result])
					print("[база] ‼ %s не вдалось: код %d, причина %d"
							% [name, code, result])
					reply = {"ok": false, "why": "база не відповіла"}
				answered.emit(name, reply))
	request.request("%s/rpc/%s" % [base_url, name],
			PackedStringArray(["Content-Type: application/json"]),
			HTTPClient.METHOD_POST, JSON.stringify(args))


## Що саме зберігається. Позиція теж: гравець має з'явитись там, де вийшов.
static func row_of(name: String, who: Node) -> Dictionary:
	return {
		"name": name,
		# Персонажі розділені по світах (П-204): ключ у базі — пара
		# (ім'я, світ), тож без цього поля запис пішов би не в той світ
		# або створив би двійника.
		"world": GameData.world_key(),
		# Порожній рядок — не NULL: зовнішній ключ на `accounts` таку річ
		# не пускає (П-118). `null` для PostgREST — це справжня відсутність
		# значення.
		"account": who.account if who.account != "" else null,
		# Колонка має `DEFAULT now()`, але це діє лише на вставці; без
		# цього поля оновлення саму мітку не чіпає (П-117).
		"saved_at": Time.get_datetime_string_from_system(true) + "Z",
		"level": who.level,
		"respect": who.respect,
		"experience": who.experience,
		"stat_points": who.stat_points,
		"stats": {
			"сила": who.base_stats.strength,
			"спритність": who.base_stats.agility,
			"витривалість": who.base_stats.stamina,
			"інтелект": who.base_stats.intellect,
			"чуття": who.base_stats.sense,
		},
		"race": who.race,
		"sex": who.sex,
		"hp": who.hp,
		"mp": who.mp,
		"x": who.global_position.x,
		"y": who.global_position.y,
		"z": who.global_position.z,
		"skills": who.learned,
		"items": who.items,
		"things": _things_row(who),
		"warehouse_items": who.warehouse_items,
		"warehouse_things": _things_row_of(who.warehouse_things),
		"gear": who.gear,
		# Розкладка панелі — своя в кожного (її тягають мишею у вікні
		# «Скіли»), тож без неї персонаж щоразу вертався б до типової.
		"bar": who.bar,
	}


## Поодинокі речі зберігаються з афіксами: інакше після перезапуску
## «гострий меч вовчої зграї» став би звичайним мечем.
static func _things_row(who: Node) -> Array:
	return _things_row_of(who.things)


static func _things_row_of(things: Array) -> Array:
	var out: Array = []
	for item: Item in things:
		out.append(item.to_row())
	return out


## Зворотне: покласти прочитане в істоту.
## Речі відтворюються з книги: без неї повернеться саме ім'я бази, а
## афікси зникнуть — тому книга передається окремим доводом.
static func apply_row(who: Node, row: Dictionary, goods: Object = null) -> void:
	if row.is_empty():
		return
	if goods != null:
		who.things.clear()
		for thing: Dictionary in row.get("things", []):
			var item: Item = Item.from_row(thing, goods)
			if item != null:
				who.things.append(item)
		who.warehouse_things.clear()
		for thing: Dictionary in row.get("warehouse_things", []):
			var stored: Item = Item.from_row(thing, goods)
			if stored != null:
				who.warehouse_things.append(stored)
	who.level = int(row.get("level", who.level))
	who.respect = int(row.get("respect", who.respect))
	who.experience = int(row.get("experience", who.experience))
	who.stat_points = int(row.get("stat_points", who.stat_points))
	var saved_stats: Dictionary = row.get("stats", {})
	for field: String in Stats.STAT_FIELDS:
		var prop: String = Stats.STAT_FIELDS[field]
		who.base_stats.set(prop,
				int(saved_stats.get(field, who.base_stats.get(prop))))
	who.race = str(row.get("race", who.race))
	who.sex = str(row.get("sex", who.sex))
	# Стати треба перерахувати ДО того, як нижче обмежимо здоров'я й ману
	# максимумом — інакше max_hp() тут ще читає старі базові стати.
	who.refresh_stats()
	# JSON не знає цілих: усе, що прийшло, — числа з комою. Без цього
	# рівні скілів і кількість речей ставали б 1.0 замість 1, і будь-яке
	# порівняння з цілим потім давало б несподіванки.
	who.learned = _whole(row.get("skills", {}))
	who.items = _whole(row.get("items", {}))
	who.warehouse_items = _whole(row.get("warehouse_items", {}))
	who.gear = _whole(row.get("gear", {}))
	# Порожня розкладка — це «ще не розкладав»: тоді лишається типова з
	# data/bar.json, яку вже поставив світ.
	var saved_bar: Array = row.get("bar", [])
	if not saved_bar.is_empty():
		who.bar.assign(saved_bar)
	who.place_at(Vector3(float(row.get("x", 0.0)), float(row.get("y", 1.5)),
			float(row.get("z", 0.0))), 0.0)
	# Здоров'я й ману ставимо після позиції: `place_at` їх не чіпає, але
	# порядок читається легше, коли спершу «де», потім «в якому стані».
	who.hp = mini(int(row.get("hp", who.hp)), who.stats.max_hp())
	who.mp = mini(int(row.get("mp", who.mp)), who.stats.max_mp())


static func _whole(from: Dictionary) -> Dictionary:
	var out := {}
	for key in from:
		out[key] = int(from[key])
	return out


## Час зберігати? Рахує сам, щоб світові не тримати ще один лічильник.
func due(delta: float) -> bool:
	if not works():
		return false
	_since += delta
	if _since < every:
		return false
	_since = 0.0
	return true
