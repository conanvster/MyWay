class_name Outlaws
extends RefCounted
## Флаг і позначка вбивці (П-26/П-64, П-84/П-87/П-88, П-261).
##
## Правила — `spec/DECIDED.md`, «Смерть і PvP»:
## - хто вдарив гравця першим — флагнутий; жертва відповіла ударом —
##   обидва в PvP, і за смерть у такому бою ніхто не позначається;
## - жертва не відповіла (або впала з першого удару) — нападник
##   позначений: ще одне вбивство на рахунку;
## - позначка згасає з часом, швидше — від убитих монстрів свого рівня й
##   вищих; ім'я біліє → червоніє, повністю червоне на 10-му вбивстві;
## - у позначеного при власній смерті падає більше речей: ×1,1 за кожне
##   вбивство, з наростанням (2 → ×1,21);
## - у містах удар по гравцю не діє взагалі (П-88).
##
## Кого позначати — правило П-84/П-87; П-263 закрито так само (слово
## замовника 11.10.2026).
##
## Пари «хто кого вдарив» живуть у пам'яті й гаснуть самі; позначка — на
## персонажі (`Creature.outlaw`) і зберігається з ним у базі: інакше
## вийти й зайти означало б її зняти.

## Числа — P5, пропозиція виконавця; живуть тут, бо даних PvP ще немає.
## Скільки секунд після останнього удару пара лишається «в бою».
const FLAG_TIME := 30.0
## Скільки секунд гри згасає одне вбивство.
const DECAY_TIME := 1800.0
## На скільки секунд пришвидшує згасання монстр свого рівня й вищого.
const MONSTER_SPEEDUP := 60.0
## Множник кількості речей, що падають, за кожне вбивство (П-261).
const LOSS_PER_KILL := 1.1
## На якому вбивстві ім'я стає цілком червоним (П-87).
const FULL_RED := 10

var _creatures: Dictionary
## Пара → {"перший": хто вдарив першим, "відповів": bool, "лишилось": с}.
## Ключ — «менший:більший» номер, щоб пара була одна, хто б не бив.
var _pairs: Dictionary = {}
## Чи це місто (П-88). Ставить світ: (Vector3) -> bool.
var in_town: Callable
## Хтось змінив рахунок — світ розішле колір імені: (id, вбивств).
var on_changed: Callable
## Гонець для журналу подій. Світ підставляє свого; без нього рядок
## іде лише в консоль, як і було.
var link: Messenger = Messenger.new()


func _init(creatures: Dictionary = {}) -> void:
	_creatures = creatures


static func _key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]


## Чи можна вдарити. Кличе бій перед кожною шкодою гравцеві від гравця
## (або від його прикликаного): `attacker` — уже господар. false — удар
## не діє зовсім: ні шкоди, ні флагу (П-88).
func allow_hit(attacker: int, victim: int) -> bool:
	if attacker <= 0 or victim <= 0 or attacker == victim:
		return true
	if in_town.is_valid():
		var a: Node3D = _creatures.get(attacker)
		var v: Node3D = _creatures.get(victim)
		if (a != null and in_town.call(a.global_position)) \
				or (v != null and in_town.call(v.global_position)):
			return false
	var key := _key(attacker, victim)
	var pair: Dictionary = _pairs.get(key, {})
	if pair.is_empty():
		pair = {"перший": attacker, "відповів": false}
		_pairs[key] = pair
		link.report(victim, "[pvp] %d напав на %d — флагнутий" % [attacker, victim])
	elif int(pair["перший"]) != attacker and not pair["відповів"]:
		pair["відповів"] = true
		link.report(victim, "[pvp] %d відповів %d — обидва в PvP" % [attacker, victim])
	pair["лишилось"] = FLAG_TIME
	return true


## Чи флагнутий гравець зараз (почав бій, який ще не згас).
func flagged(id: int) -> bool:
	for pair: Dictionary in _pairs.values():
		if int(pair["перший"]) == id:
			return true
	return false


## Гравець убив гравця. Повертає true, якщо вбивця щойно позначений.
## Погоджений бій (П-259, арена) сюди не доходить — його відсіює бій.
func on_kill(killer: int, victim: int) -> bool:
	if killer <= 0 or victim <= 0 or killer == victim:
		return false
	var pair: Dictionary = _pairs.get(_key(killer, victim), {})
	_pairs.erase(_key(killer, victim))
	# Убив той, на кого напали, — це відповідь, не вбивство без виклику.
	if pair.is_empty() or int(pair["перший"]) != killer:
		return false
	if pair["відповів"]:
		return false
	var who: Node = _creatures.get(killer)
	if who == null:
		return false
	var mark: Dictionary = who.outlaw
	var kills := int(mark.get("вбивств", 0)) + 1
	# Нове вбивство не скидає строк старих: згасання йде по одному, і
	# повний строк дістає лише те, що щойно додалось.
	var left := float(mark.get("згасає за", DECAY_TIME))
	who.outlaw = {"вбивств": kills, "згасає за": left}
	link.report(victim, "[pvp] %d убив %d без виклику — позначений, вбивств %d"
			% [killer, victim, kills])
	if on_changed.is_valid():
		on_changed.call(killer, kills)
	return true


## Скільки разів більше речей падає з цього гравця при смерті (П-261).
func loss_multiplier(who: Node) -> float:
	return pow(LOSS_PER_KILL, kills_of(who))


func kills_of(who: Node) -> int:
	if who == null or not ("outlaw" in who):
		return 0
	return int(who.outlaw.get("вбивств", 0))


## Позначений убив монстра свого рівня чи вищого — згасає швидше (П-87).
func monster_killed(killer: Node, monster_level: int) -> void:
	if kills_of(killer) <= 0 or monster_level < killer.level:
		return
	killer.outlaw["згасає за"] = float(killer.outlaw.get("згасає за",
			DECAY_TIME)) - MONSTER_SPEEDUP


## Час іде: пари гаснуть, позначки згасають (лише в живих гравців у
## світі — час гри, не календар).
func tick(delta: float) -> void:
	for key: String in _pairs.keys():
		_pairs[key]["лишилось"] = float(_pairs[key]["лишилось"]) - delta
		if _pairs[key]["лишилось"] <= 0.0:
			_pairs.erase(key)
	for id: int in _creatures:
		if id <= 0:
			continue
		var who: Node = _creatures[id]
		var before := kills_of(who)
		if before <= 0:
			continue
		var kills := before
		var left := float(who.outlaw.get("згасає за", DECAY_TIME)) - delta
		while left <= 0.0 and kills > 0:
			kills -= 1
			left += DECAY_TIME
		who.outlaw = {"вбивств": kills, "згасає за": left} if kills > 0 \
				else {}
		if kills != before and on_changed.is_valid():
			on_changed.call(id, kills)


## Гравець вийшов — його пари більше нікого не тримають.
func forget(id: int) -> void:
	for key: String in _pairs.keys():
		var ends: PackedStringArray = key.split(":")
		if int(ends[0]) == id or int(ends[1]) == id:
			_pairs.erase(key)


## Колір імені гравця (П-87): білий → червоний, цілком на 10-му.
static func name_color(kills: int) -> Color:
	var t := clampf(float(kills) / FULL_RED, 0.0, 1.0)
	return Color(1, 1, 1).lerp(Color(1.0, 0.15, 0.15), t)
