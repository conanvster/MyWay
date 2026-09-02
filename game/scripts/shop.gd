class_name Shop
extends RefCounted
## Крамар: що продає, за скільки купує, і чи вільно це робити.
##
## Живе на СЕРВЕРІ й нікому не вірить (П-08). Клієнт шле лише «хочу оце
## в отого мешканця» — усе решта, від відстані до грошей, перевіряється
## тут. Інакше вікно торгівлі було б найкоротшим шляхом до нескінченних
## речей: клієнт просто малював би собі меч.
##
## Числа всі до одного в даних: асортимент — у `map.json` у мешканця
## («товар»), ціни — у `items.json` («ціна»), частка викупу — там-таки
## («торгівля»). Новий крамар — це рядок у мапі, не код (П-132).

## Скільки треба підійти. Стільки ж, скільки до цілі в бою: інакше
## виходить, що поговорити можна далі, ніж дотягнутись.
const TALK_RANGE := 4.0

## Якщо в даних частки немає — беремо цю. Крамар, що купує за 100%,
## робить гроші безмежними: продав і купив назад без утрат.
const DEFAULT_BUYBACK := 0.4

var _data: GameData


func _init(data: GameData) -> void:
	_data = data


## За скільки крамар ПРОДАЄ цю річ. Нуль — такої речі в даних немає.
func sell_price(name: String) -> int:
	return int(_data.items.base_of(name).get("ціна", 0))


## За скільки крамар КУПУЄ. Округлення вниз, але не до нуля: річ, за яку
## дають 0, виглядає як поламана гра, а не як дешева річ.
func buy_price(name: String) -> int:
	var full := sell_price(name)
	if full <= 0:
		return 0
	return maxi(1, int(floor(full * _buyback())))


func _buyback() -> float:
	var rules: Dictionary = _data.items.trade
	return float(rules.get("крамар купує за", DEFAULT_BUYBACK))


## Те саме у відсотках — у вікні торгівлі його показують один раз рядком.
func buyback_percent() -> int:
	return int(round(_buyback() * 100.0))


## Чого крамар не бере взагалі. Гроші — щоб не було «продам гроші за
## гроші»; вдягнене перевіряється окремо, бо це не про річ, а про стан.
func refuses(name: String) -> bool:
	var rules: Dictionary = _data.items.trade
	return Array(rules.get("не купує", ["гроші"])).has(name)


## Асортимент мешканця з мапи. Порожній — це не крамар.
func goods_of(resident: Dictionary) -> Array:
	var out: Array = []
	for name: String in resident.get("товар", []):
		if not _data.items.has(name):
			# Мовчки не ковтаємо: назва з мапи, якої немає в речах, — це
			# описка в даних, і крамар без неї просто збідніє непомітно.
			push_warning("[крамар] «%s» немає в items.json" % name)
			continue
		var base: Dictionary = _data.items.base_of(name)
		out.append({
			"назва": name,
			"вид": str(base.get("вид", "")),
			"слот": str(base.get("слот", "")),
			"грейд": str(base.get("грейд", "")),
			"ціна": sell_price(name),
			"складана": _data.items.is_stackable(name),
		})
	return out


## Чи досить близько. Мешканець стоїть на місці, тож міряємо просто.
func within(who: Node3D, resident: Node3D) -> bool:
	return who.global_position.distance_to(resident.global_position) \
			<= TALK_RANGE


## Купівля. Повертає порожній рядок, коли вийшло, або причину відмови.
func buy(who: Node, resident: Dictionary, name: String) -> String:
	var stock := goods_of(resident)
	var found := false
	for row: Dictionary in stock:
		if str(row["назва"]) == name:
			found = true
			break
	if not found:
		return "цього тут не продають"
	var price := sell_price(name)
	if price <= 0:
		return "ціни на це немає"
	if money_of(who) < price:
		return "не вистачає грошей: треба %d" % price
	take_money(who, price)
	if _data.items.is_stackable(name):
		who.give_item(name, 1)
	else:
		var made: Item = _data.items.make(name)
		if made == null:
			return "не вийшло зробити річ"
		who.add_thing(made)
	return ""


## Продаж поодинокої речі за її номером у торбі.
func sell(who: Node, at: int) -> String:
	if at < 0 or at >= who.things.size():
		return "такої речі немає"
	if who.is_worn(at):
		return "спершу зніми"
	var item: Item = who.things[at]
	var paid := buy_price(item.base)
	if paid <= 0 or refuses(item.base):
		return "крамар цього не бере"
	who.drop_thing(at)
	give_money(who, paid)
	return ""


## Продаж складаної речі — усього стосу одразу.
func sell_stack(who: Node, name: String) -> String:
	var have := int(who.items.get(name, 0))
	if have <= 0:
		return "такої речі немає"
	if refuses(name):
		return "крамар цього не бере"
	var paid := buy_price(name) * have
	if paid <= 0:
		return "крамар цього не бере"
	who.take_item(name, have)
	give_money(who, paid)
	return ""


# ── гроші ─────────────────────────────────────────────────────────────
#
# Гроші — звичайна складана річ на ім'я «гроші», а не окреме поле. Так
# вони самі собою падають із монстрів, лежать у торбі й зберігаються в
# базі; окреме поле довелося б проводити через усе те саме окремо.

static func money_of(who: Node) -> int:
	return int(who.items.get("гроші", 0))


static func take_money(who: Node, amount: int) -> void:
	who.take_item("гроші", amount)


static func give_money(who: Node, amount: int) -> void:
	who.give_item("гроші", amount)
