class_name Wardens
extends RefCounted
## Охорона поселень і вбиваність мешканців (П-262, П-73).
##
## Слово замовника 10.10.2026: будь-якого NPC можна вбити, але здоров'я в
## нього дуже багато; на того, хто напав на мешканця, кидається охорона;
## убив мешканця — решта мешканців цього поселення відмовляє в послугах,
## а охорона полює, але далеко від поселення не відходить. Штраф і
## мертві мешканці живуть до перезапуску світу (сервера) — тому все тут
## лише в пам'яті, у базу нічого не пишеться.
##
## Вартовий — це монстр окремого виду (`GUARD_KIND`) з моделлю людини:
## бій, таблиця загрози, повідець і поклик своїх уже є в `mob.gd` /
## `mob_ai.gd`, і другої механіки бою заводити не треба. Числа вартового
## й мешканця — `map*.json → охорона поселень` (P5).
##
## Мешканець (`NPC`) лишається нерухомим вузлом: його здоров'я веде цей
## клас за номером мешканця (`at_index`), щоб NPC не ставав Creature і
## не тягнув за собою зір, позиції й ціль.

## Номер виду вартового. Не рядок `mobs.json`: там бестіарій і
## розселення, а вартовий — роль поселення, не вид монстра.
const GUARD_KIND := 900
## Ремесло в `map*.json → мешканці`, яке стає вартовим-істотою.
const GUARD_CRAFT := "вартовий"
## Як часто вартові оглядають поселення на «чорний список», секунд.
const LOOK_EVERY := 0.5

var _creatures: Dictionary
var _link: Messenger
## Номер з'єднання → ім'я персонажа. Штраф прив'язаний до персонажа, а
## не до з'єднання: інакше перезайти в гру означало б зняти штраф.
var names: Dictionary = {}

## Поселення: назва, центр (x, z), радіус, номери мешканців, номери
## вартових-істот, «чорний список» імен.
var settlements: Array = []
## Номер мешканця → поселення.
var _home_of: Dictionary = {}
## Номер мешканця → здоров'я. Немає ключа — повне.
var _hp: Dictionary = {}
## Номери вбитих мешканців.
var dead: Dictionary = {}
## Числа з даних.
var rules: Dictionary = {}
var _look_left := 0.0


func _init(creatures: Dictionary = {}, link: Messenger = null) -> void:
	_creatures = creatures
	_link = link if link != null else Messenger.new()


## Поселення з мапи. Нумерація мешканців — та сама, що в
## `landscape.gd:_city()`: наскрізна через міста, а за ними села.
func setup(map: Dictionary) -> void:
	rules = map.get("охорона поселень", {})
	settlements.clear()
	_home_of.clear()
	var towns: int = Array(map.get("міста", [])).size()
	var places: Array = map.get("міста", []) + map.get("села", []) as Array
	var at := 0
	for place: Dictionary in places:
		var c: Array = place.get("центр", [0, 0, 0])
		var one := {
			"назва": str(place.get("назва", "поселення")),
			"центр": Vector2(float(c[0]), float(c[2])),
			# Місто з муром (світ 2, П-271) — усе, що за муром.
			"радіус": float(place.get("мур радіус", place.get("радіус", 20))),
			"мешканці": [],
			"пости": [],
			"вартові": [],
			"чорний список": {},
			# Місто, не село: лише в місті удар по гравцю не діє (П-88).
			"місто": settlements.size() < towns,
		}
		for who: Dictionary in place.get("мешканці", []):
			if str(who.get("ремесло", "")) == GUARD_CRAFT:
				var p: Array = who.get("де", [0, 0, 0])
				one["пости"].append({"хто": str(who.get("хто", "вартовий")),
						"де": Vector3(float(p[0]), float(p[1]), float(p[2]))})
			else:
				one["мешканці"].append(at)
				_home_of[at] = settlements.size()
			at += 1
		# Окремі пости там, де вартового серед мешканців немає (села й
		# міста, яким не випав вартовий у колі ремесел, `tools/svit2.py`).
		for post: Dictionary in place.get("вартові", []):
			var p: Array = post.get("де", [0, 0, 0])
			one["пости"].append({"хто": str(post.get("хто", "вартовий")),
					"де": Vector3(float(p[0]), float(p[1]), float(p[2]))})
		settlements.append(one)


## Здоров'я й захист мешканця — з даних, з запасом на випадок, коли
## ключа немає (тоді чесно друкуємо, що беремо сталі коду).
## Чи точка в місті (П-88: тут удар по гравцю не діє). Села — ні: у них
## немає ні точок появи, ні майстерень, заради яких правило писалось.
func in_town(at: Vector3) -> bool:
	for one: Dictionary in settlements:
		if one["місто"] and Vector2(at.x, at.z).distance_to(one["центр"]) \
				<= one["радіус"]:
			return true
	return false


func resident_max_hp() -> int:
	return int(rules.get("здоров'я мешканця", 6000))


func resident_defence() -> float:
	return float(rules.get("захист мешканця", 150.0))


func hp_of(at: int) -> int:
	return int(_hp.get(at, resident_max_hp()))


func is_dead(at: int) -> bool:
	return dead.has(at)


## Поселення мешканця або -1, коли такого немає (вартовий чи чужий номер).
func settlement_of(at: int) -> int:
	return int(_home_of.get(at, -1))


## Чи відмовляє мешканець цьому гравцеві в послугах (П-262).
func refuses(id: int, at: int) -> bool:
	var s := settlement_of(at)
	if s < 0:
		return false
	return settlements[s]["чорний список"].has(_name(id))


func is_wanted(id: int, s: int) -> bool:
	return s >= 0 and s < settlements.size() \
			and settlements[s]["чорний список"].has(_name(id))


func _name(id: int) -> String:
	return str(names.get(id, "гравець %d" % id))


## Поставити вартових на пости. `spawn(id, pos) -> Node`, `next_id() ->
## int` (від'ємний) дає світ: вузли — його робота. Повертає, скільки
## поставлено. Убиті вартові не повертаються до перезапуску (П-73), тож
## спавнеру зон вони не віддаються.
func post_guards(spawn: Callable, next_id: Callable,
		ground: Callable = Callable()) -> int:
	var tuning := guard_tuning()
	var count := 0
	for s in settlements.size():
		var one: Dictionary = settlements[s]
		for post: Dictionary in one["пости"]:
			var at: Vector3 = post["де"]
			if ground.is_valid():
				at.y = float(ground.call(at.x, at.z)) + 1.0
			var id: int = next_id.call()
			var m: Node = spawn.call(id, at)
			m.setup(at, GUARD_KIND, false, tuning)
			m.settlement = s
			# Далеко від поселення не відходить: від ЦЕНТРУ — не далі краю
			# поселення й ще трохи (P5, `повідець понад радіус`). Монстр
			# міряє повідець від свого дому (посту), тож відстань посту від
			# центру віднімається: інакше в бік від центру вартовий ішов
			# би на неї далі (проба: 56 м замість 36).
			var post_off: float = Vector2(at.x, at.z).distance_to(one["центр"])
			m.leash = maxf(5.0, one["радіус"] - post_off
					+ float(rules.get("повідець понад радіус", 10.0)))
			one["вартові"].append(id)
			count += 1
	return count


## Числа вартового в тому самому вигляді, що рядок `mobs.json`: їх
## читають і `Mob.apply_tuning`, і клієнт (`GameData.for_kind`).
func guard_tuning() -> Dictionary:
	return rules.get("вартовий", {})


## Удар гравця по мешканцю. Перевірки відстані й відкату — у світі; тут
## лише шкода, тривога й наслідки. Повертає завдану шкоду (0 — не вдалося).
func hit_resident(id: int, at: int, power: float) -> int:
	var s := settlement_of(at)
	if s < 0 or is_dead(at):
		return 0
	var hit: int = Stats.damage_through(power, resident_defence())
	_hp[at] = maxi(0, hp_of(at) - hit)
	alarm(s, id, hit)
	if _hp[at] <= 0:
		_kill_resident(id, at, s)
	return hit


## Напали на NPC поселення — охорона б'є нападника (П-262).
func alarm(s: int, id: int, amount: float) -> void:
	for g: int in settlements[s]["вартові"]:
		var m: Node = _creatures.get(g)
		if m != null and m.is_alive():
			m.add_threat(id, amount + m.threat_per_hit)


func _kill_resident(id: int, at: int, s: int) -> void:
	dead[at] = true
	_blacklist(id, s)


func _blacklist(id: int, s: int) -> void:
	var one: Dictionary = settlements[s]
	var who := _name(id)
	if one["чорний список"].has(who):
		return
	one["чорний список"][who] = true
	_link.notice(id, "‼ %s: мешканці відмовляють тобі в послугах, охорона "
			% one["назва"] + "полює на тебе — до перезапуску світу")
	print("[охорона] %s у чорному списку поселення %s" % [who, one["назва"]])


## Хтось загинув. Убитий вартовий — це теж убитий NPC поселення: убивця
## (чи господар прикликаного) іде в «чорний список». Сам вартовий не
## повертається до перезапуску — спавнер його не знає.
func on_kill(victim: Node, killer_id: int) -> void:
	var s := int(victim.get("settlement")) if "settlement" in victim else -1
	if s < 0:
		return
	settlements[s]["вартові"].erase(_id_of(victim))
	if killer_id > 0:
		_blacklist(killer_id, s)


func _id_of(node: Node) -> int:
	for id: int in _creatures:
		if _creatures[id] == node:
			return id
	return 0


## Полювання: гравець із «чорного списку» в межах поселення (з тим самим
## запасом, що й повідець) — вартові беруть його на загрозу. Вийшов за
## межу — вартовий дійде до краю повідця, забуде й вернеться на пост.
func tick(delta: float) -> void:
	_look_left -= delta
	if _look_left > 0.0:
		return
	_look_left = LOOK_EVERY
	var extra := float(rules.get("повідець понад радіус", 10.0))
	for s in settlements.size():
		var one: Dictionary = settlements[s]
		if one["чорний список"].is_empty() or one["вартові"].is_empty():
			continue
		for id: int in _creatures:
			if id <= 0 or not one["чорний список"].has(_name(id)):
				continue
			var p: Node3D = _creatures[id]
			if not p.is_alive():
				continue
			var d := Vector2(p.global_position.x, p.global_position.z) \
					.distance_to(one["центр"])
			if d <= one["радіус"] + extra:
				alarm(s, id, 1.0)


## Що показати гравцеві, який щойно зайшов: мертві мешканці й поранені.
func state_rows() -> Array:
	var out: Array = []
	for at: int in _hp:
		out.append([at, int(_hp[at])])
	return out
