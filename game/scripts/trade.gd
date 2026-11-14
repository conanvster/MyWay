class_name Trade
extends RefCounted
## Обмін між гравцями (П-218): одне вікно, підтвердження обох сторін.
##
## Живе на СЕРВЕРІ й нікому не вірить (P1). Клієнт каже лише «пропоную
## оце» чи «згоден»; що саме лежить на столі, рахує й переносить тут.
##
## Хід обміну:
##   1. А кличе Б (`invite`), Б погоджується (`accept`) — стіл відкрито.
##   2. Кожен кладе на свій бік речі й стоси (`offer_*`) або забирає
##      назад (`take_back_*`). Будь-яка зміна на столі знімає обидві
##      згоди: інакше можна було б підмінити річ після чужого «так».
##   3. Обидва тиснуть «Згоден» (`agree`). Друга згода переносить усе
##      разом (`_swap`) — або нічого, якщо чогось уже не стало.
##
## Дрібниці, що їх рішення лишило виконавцеві (П-218, 01.10.2026):
## обмін лише поруч (`RANGE`), не в бою й не мертвим; стіл закривається,
## щойно хтось відійшов, загинув, вступив у бій чи вийшов із гри; кожен
## завершений обмін пишеться в журнал сервера рядком «[обмін]».

## Скільки можна стояти одне від одного. Як до мешканця й до цілі в бою:
## «поруч» у грі скрізь означає одне й те саме число.
const RANGE := 4.0
## Скільки чекає запрошення, доки Б не відповів.
const INVITE_TIME := 30.0

## Відкриті столи: номер гравця -> {"з", "речі": Array[Item], "стоси":
## {назва: скільки}, "згоден"}. Кожен стіл записано двічі — за обома.
var _deals: Dictionary = {}
## Запрошення: кого кличуть -> {"від", "лишилось"}.
var _invites: Dictionary = {}
## Імена персонажів за номером — той самий словник, що веде світ. У
## пробі може бути порожній: тоді «гравець N».
var names: Dictionary = {}
## Книга речей — для місткості торби («торба повна», 14.11.2026).
var book: ItemBook = null


func _name(id: int) -> String:
	return str(names.get(id, "гравець %d" % id))


func partner(id: int) -> int:
	return int(_deals[id]["з"]) if _deals.has(id) else 0


func busy(id: int) -> bool:
	return _deals.has(id)


## Чому цим двом зараз не можна міняти. Порожньо — можна.
func why_not(a: Node, b: Node) -> String:
	if a == null or b == null:
		return "гравця немає"
	if a == b:
		return "сам із собою не міняються"
	if a.hp <= 0 or b.hp <= 0:
		return "мертві не міняються"
	if a.in_fight > 0.0 or b.in_fight > 0.0:
		return "у бою не міняються"
	if a.global_position.distance_to(b.global_position) > RANGE:
		return "задалеко для обміну: підійди ближче"
	return ""


## А кличе Б. Порожньо — запрошення пішло.
func invite(from: int, to: int, a: Node, b: Node) -> String:
	var why := why_not(a, b)
	if why != "":
		return why
	if busy(from):
		return "ти вже міняєшся"
	if busy(to):
		return "%s уже міняється з кимось" % _name(to)
	_invites[to] = {"від": from, "лишилось": INVITE_TIME}
	return ""


## Хто кличе цього гравця. Нуль — ніхто.
func invited_by(to: int) -> int:
	return int(_invites[to]["від"]) if _invites.has(to) else 0


## Б погодився. Порожньо — стіл відкрито.
func accept(to: int, a: Node, b: Node) -> String:
	var from := invited_by(to)
	_invites.erase(to)
	if from == 0:
		return "запрошення вже немає"
	var why := why_not(a, b)
	if why != "":
		return why
	if busy(from) or busy(to):
		return "хтось уже міняється"
	_deals[from] = _side(to)
	_deals[to] = _side(from)
	return ""


func decline(to: int) -> int:
	var from := invited_by(to)
	_invites.erase(to)
	return from


func _side(with: int) -> Dictionary:
	return {"з": with, "речі": [], "стоси": {}, "згоден": false}


## Покласти на стіл поодиноку річ за номером у торбі.
func offer_thing(id: int, who: Node, at: int) -> String:
	if not busy(id):
		return "обміну немає"
	if at < 0 or at >= who.things.size():
		return "такої речі немає"
	if who.is_worn(at):
		return "спершу зніми"
	var item: Item = who.things[at]
	var mine: Array = _deals[id]["речі"]
	if mine.has(item):
		return "уже на столі"
	mine.append(item)
	_unagree(id)
	return ""


## Покласти на стіл `count` штук стосу. Те, що вже лежить, замінюється:
## гравець вибрав число − / + (П-164), і це число й є пропозиція.
func offer_stack(id: int, who: Node, name: String, count: int) -> String:
	if not busy(id):
		return "обміну немає"
	var have := int(who.items.get(name, 0))
	if have <= 0:
		return "такої речі немає"
	if count <= 0 or count > have:
		return "стільки немає: є %d" % have
	_deals[id]["стоси"][name] = count
	_unagree(id)
	return ""


func take_back_thing(id: int, at_on_table: int) -> String:
	if not busy(id):
		return "обміну немає"
	var mine: Array = _deals[id]["речі"]
	if at_on_table < 0 or at_on_table >= mine.size():
		return "цього на столі немає"
	mine.remove_at(at_on_table)
	_unagree(id)
	return ""


func take_back_stack(id: int, name: String) -> String:
	if not busy(id):
		return "обміну немає"
	if not _deals[id]["стоси"].erase(name):
		return "цього на столі немає"
	_unagree(id)
	return ""


## Будь-яка зміна на столі — обидві згоди знято.
func _unagree(id: int) -> void:
	_deals[id]["згоден"] = false
	var other := partner(id)
	if _deals.has(other):
		_deals[other]["згоден"] = false


## «Згоден». Повертає:
##   ""        — згоду записано, чекаємо другого;
##   "обмінено" — обидва згодні, усе перенесено, стіл закрито;
##   інше      — причина, чому ні (стіл тоді закрито, якщо зламався).
func agree(id: int, a: Node, b: Node) -> String:
	if not busy(id):
		return "обміну немає"
	var why := why_not(a, b)
	if why != "":
		return why
	_deals[id]["згоден"] = true
	var other := partner(id)
	if not bool(_deals[other]["згоден"]):
		return ""
	why = _swap(id, a, other, b)
	close(id)
	return "обмінено" if why == "" else why


## Перенести обидва боки разом. Спершу перевіряємо ВСЕ, потім рухаємо:
## половинчастий обмін — найгірше, що тут може статися.
func _swap(id_a: int, a: Node, id_b: int, b: Node) -> String:
	for pair: Array in [[id_a, a], [id_b, b]]:
		var side: Dictionary = _deals[pair[0]]
		var who: Node = pair[1]
		var title := _name(pair[0])
		for item: Item in side["речі"]:
			var at: int = who.things.find(item)
			if at < 0:
				return "%s уже не має однієї з речей" % title
			if who.is_worn(at):
				return "%s устиг вдягти річ зі столу" % title
		for name: String in side["стоси"]:
			if int(who.items.get(name, 0)) < int(side["стоси"][name]):
				return "%s уже не має стільки «%s»" % [title, name]

	# Торба повна (14.11.2026): кожен мусить умістити те, що отримує, —
	# з урахуванням місць, які звільнить віддане.
	if book != null:
		for pair: Array in [[_deals[id_b], a, _deals[id_a]], [_deals[id_a], b, _deals[id_b]]]:
			var gets: Dictionary = pair[0]
			var who: Node = pair[1]
			var gives: Dictionary = pair[2]
			var freed: int = (gives["речі"] as Array).size()
			for name: String in gives["стоси"]:
				if name != "гроші" and int(gives["стоси"][name]) >= int(who.items.get(name, 0)):
					freed += 1
			if not book.bag_fits(who, (gets["речі"] as Array).size(),
					(gets["стоси"] as Dictionary).keys(), freed):
				return "у %s торба повна" % _name(id_a if who == a else id_b)
	var a_gives := _pull(_deals[id_a], a)
	var b_gives := _pull(_deals[id_b], b)
	_push(a_gives, b)
	_push(b_gives, a)
	print("[обмін] %s (%d) → %s (%d): %s · %s (%d) → %s (%d): %s" % [
			_name(id_a), id_a, _name(id_b), id_b, _list(a_gives),
			_name(id_b), id_b, _name(id_a), id_a, _list(b_gives)])
	return ""


## Зняти зі сторони все, що вона віддає.
func _pull(side: Dictionary, who: Node) -> Dictionary:
	var things: Array = []
	for item: Item in side["речі"]:
		things.append(who.drop_thing(who.things.find(item)))
	var stacks: Dictionary = side["стоси"].duplicate()
	for name: String in stacks:
		who.take_item(name, int(stacks[name]))
	return {"речі": things, "стоси": stacks}


## Віддати те, що зняли з іншої сторони, цьому гравцеві.
func _push(goods: Dictionary, to: Node) -> void:
	for item: Item in goods["речі"]:
		to.add_thing(item)
	for name: String in goods["стоси"]:
		to.give_item(name, int(goods["стоси"][name]))


func _list(goods: Dictionary) -> String:
	var parts := PackedStringArray()
	for item: Item in goods["речі"]:
		parts.append(item.title())
	for name: String in goods["стоси"]:
		parts.append("%s ×%d" % [name, int(goods["стоси"][name])])
	return ", ".join(parts) if not parts.is_empty() else "нічого"


## Закрити стіл. Повертає номер другого, щоб і йому сказати.
func close(id: int) -> int:
	var other := partner(id)
	_deals.erase(id)
	_deals.erase(other)
	return other


## Що лежить на столі — для вікна. `mine` — свій бік, `theirs` — чужий.
func table_of(id: int) -> Dictionary:
	if not busy(id):
		return {}
	var other := partner(id)
	return {
		"моє": _rows(_deals[id]),
		"їхнє": _rows(_deals[other]),
		"я згоден": bool(_deals[id]["згоден"]),
		"вони згодні": bool(_deals[other]["згоден"]),
	}


## Поодинока річ зі свого боку столу — щоб знайти її номер у торбі.
func thing_on_table(id: int, at_on_table: int) -> Item:
	if not busy(id):
		return null
	var mine: Array = _deals[id]["речі"]
	if at_on_table < 0 or at_on_table >= mine.size():
		return null
	return mine[at_on_table]


func _rows(side: Dictionary) -> Array:
	var out: Array = []
	var at := 0
	for item: Item in side["речі"]:
		out.append({"на столі": at, "назва": item.title(), "база": item.base,
				"вид": item.kind, "слот": item.slot, "грейд": item.grade})
		at += 1
	for name: String in side["стоси"]:
		out.append({"назва": name, "скільки": int(side["стоси"][name])})
	return out


## Кожен кадр сервера: старіють запрошення, а відкриті столи
## перевіряються — хто відійшов, загинув чи вступив у бій, той стіл
## втрачає. Повертає [[номер, номер другого, причина]] закритих столів і
## [[кого кликали, хто кликав]] запрошень, що прострочились.
func tick(delta: float, creatures: Dictionary) -> Dictionary:
	var expired: Array = []
	for to: int in _invites.keys():
		_invites[to]["лишилось"] = float(_invites[to]["лишилось"]) - delta
		if float(_invites[to]["лишилось"]) <= 0.0:
			expired.append([to, int(_invites[to]["від"])])
			_invites.erase(to)

	var broken: Array = []
	var seen := {}
	for id: int in _deals.keys():
		if seen.has(id) or not _deals.has(id):
			continue
		var other := partner(id)
		seen[id] = true
		seen[other] = true
		var why := why_not(creatures.get(id), creatures.get(other))
		if why != "":
			close(id)
			broken.append([id, other, why])
	return {"зламані": broken, "прострочені": expired}


## Гравець пішов з гри: його стіл і запрошення зникають.
func forget(id: int) -> int:
	_invites.erase(id)
	for to: int in _invites.keys():
		if int(_invites[to]["від"]) == id:
			_invites.erase(to)
	return close(id) if busy(id) else 0
