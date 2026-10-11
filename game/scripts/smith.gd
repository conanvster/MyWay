class_name Smith
extends RefCounted
## Коваль: міцність зброї, ремонт і рунне посилення (21.09.2026).
##
## Слово замовника: «зброя від бою втрачає міцність і її потрібно
## відновлювати (точити або зачаровувати)… Коваль може відремонтувати
## зброю та навіть за плату та деякі інгредієнти, які дропаються з
## босів, накласти рунні посилення». І про зачарування: «для магічних
## предметів більш вірогідно, але не 100% магічні параметри, для
## фізичних більш вірогідно фізичні».
##
## Клас нічого не знає ні про мережу, ні про вузли — лише числа з
## `data/smith.json` і річ. Тому ймовірності перевіряються пробою на
## тисячах кидків, а не на слово.

## Параметри, що не є статами, а йдуть у похідні величини (відсотки).
## Їх розуміє `Creature.refresh_stats`; назви ті самі, що в даних.
const CAST := "швидкість касту"
const COOLDOWN := "швидкість відкату"
const ATTACK_SPEED := "швидкість атаки"
const PERCENTS: Array[String] = [CAST, COOLDOWN, ATTACK_SPEED]
## Стати, з яких видно, що річ магічна.
const MAGIC_STATS: Array[String] = ["інтелект", "чуття"]

var rules: Dictionary = {}


func load_from(raw: Dictionary) -> void:
	rules = raw


func has_rules() -> bool:
	return rules.has("зачарування")


## Скільки міцності в нової зброї. 0 — у цієї речі міцності немає.
func durability_for(item: Item) -> int:
	if item == null or item.kind != "зброя":
		return 0
	return int(rules.get("міцність", {}).get("зброя", 0))


func wear_per_hit() -> int:
	return int(rules.get("міцність", {}).get("за удар", 1))


## Магічна річ — магічний одяг і посох (тип бази, П-223), а прикраси —
## за ВЛАСНИМИ статами (без афіксів і руни): амулет на інтелект, перстень
## на чуття — магічні.
func is_magic(item: Item, book: ItemBook) -> bool:
	# Тип бази важить першим: магічні нарукавники дають лише швидкість
	# касту, і за статами їх не впізнати.
	var kind_type := str(book.base_of(item.base).get("тип", ""))
	if kind_type in ["магічна", "посох"]:
		return true
	if kind_type in ["важка", "легка", "щит", "меч", "сокира", "кинджал",
			"спис", "лук"]:
		return false
	var own: Dictionary = book.base_of(item.base).get("стати", {})
	var magic := 0
	var body := 0
	for stat in own:
		if str(stat) in MAGIC_STATS:
			magic += int(own[stat])
		else:
			body += int(own[stat])
	return magic > body


## Ціна ремонту: частка ціни речі × скільки бракує, не менше найменшого.
## Нічого не бракує — 0, і ремонтувати нема чого.
func repair_cost(item: Item, book: ItemBook) -> int:
	if item.durability_max <= 0 or item.durability >= item.durability_max:
		return 0
	var r: Dictionary = rules.get("ремонт", {})
	var lost := 1.0 - float(item.durability) / float(item.durability_max)
	var price := float(book.base_of(item.base).get("ціна", 0))
	return maxi(int(r.get("найменше", 1)),
			roundi(price * float(r.get("частка ціни", 0.3)) * lost))


## Рецепт кування (П-22, П-258 — слово замовника 11.10.2026: «усе
## спорядження, рецепт = матеріали грейду ×10»): метал грейду речі ×
## «крафт → матеріалу». Порожньо — це не кується: річ не з «видів» або
## без грейду (квестові амулети професій, П-224).
func recipe(base: String, book: ItemBook) -> Dictionary:
	if book == null or not book.has(base):
		return {}
	var data: Dictionary = book.base_of(base)
	var craft: Dictionary = rules.get("крафт", {})
	if not str(data.get("вид", "")) in Array(craft.get("види", [])):
		return {}
	if not data.has("грейд"):
		return {}
	return _metal_times(str(data["грейд"]), int(craft.get("матеріалу", 0)))


func _metal_times(grade: String, count: int) -> Dictionary:
	var metal := str(rules.get("зачарування", {}).get("матеріал", {})
			.get(grade, ""))
	return {metal: count} if metal != "" and count > 0 else {}


## З чого річ скрафчено: «матеріал → скільки» — її рецепт. Без книги
## речей (проба міцності) — той самий метал грейду × «матеріалу».
func craft_materials(item: Item, book: ItemBook = null) -> Dictionary:
	if book != null and book.has(item.base):
		return recipe(item.base, book)
	return _metal_times(item.grade,
			int(rules.get("крафт", {}).get("матеріалу", 0)))


## Усе, що кується, — назви баз за грейдом і назвою.
func recipes(book: ItemBook) -> Array:
	var out: Array = []
	for base: String in book.bases.keys():
		if not recipe(base, book).is_empty():
			out.append(base)
	out.sort_custom(func(a: String, b: String) -> bool:
		var ga := ItemBook.GRADES.find(str(book.base_of(a)["грейд"]))
		var gb := ItemBook.GRADES.find(str(book.base_of(b)["грейд"]))
		return ga < gb if ga != gb else a < b)
	return out


## Чого бракує на кування: порожньо — усього досить.
func missing_to_forge(who: Node, base: String, book: ItemBook) -> Array:
	var needs := recipe(base, book)
	var out: Array = []
	for name: String in needs:
		var lack := int(needs[name]) - int(who.items.get(name, 0))
		if lack > 0:
			out.append("%s ×%d" % [name, lack])
	return out


## Скувати `base`: забрати матеріали, покласти в торбу нову річ — таку
## саму, як із дропу (афікси кидає `ItemBook.make`). Повертає причину
## відмови або порожньо; скуте — у `forged`.
var forged: Item = null


func forge(who: Node, base: String, book: ItemBook) -> String:
	forged = null
	var needs := recipe(base, book)
	if needs.is_empty():
		return "%s не кується" % base
	var lacking := missing_to_forge(who, base, book)
	if not lacking.is_empty():
		return "бракує: %s" % ", ".join(lacking)
	var item: Item = book.make(base)
	if item == null:
		return "%s не кується" % base
	for name: String in needs:
		who.take_item(name, int(needs[name]))
	who.add_thing(item)
	forged = item
	return ""


## Що лишає зламана зброя (П-234, слово замовника 01.10.2026): «до
## цілого 10% від матеріалів для крафту речі, якщо зачароване, то 20%
## ресурсів для зачарування». До цілого — угору: з 3 металів зачарування
## 20% — це 0,6, тобто 1. Гроші зачарування — не ресурс, не повертаються.
func break_yield(item: Item, book: ItemBook) -> Dictionary:
	var r: Dictionary = rules.get("поломка", {})
	var out := {}
	var craft := craft_materials(item, book)
	for name: String in craft:
		_add_share(out, name, int(craft[name]),
				float(r.get("частка крафту", 0.1)))
	if not item.rune.is_empty():
		var needs: Dictionary = enchant_cost(item, book)["речі"]
		for name: String in needs:
			_add_share(out, name, int(needs[name]),
					float(r.get("частка зачарування", 0.2)))
	return out


func _add_share(out: Dictionary, name: String, count: int,
		share: float) -> void:
	# 1e-6 — щоб 10 × 0,1 не дало 2 через похибку дробу.
	var got := ceili(count * share - 1e-6)
	if got > 0:
		out[name] = int(out.get(name, 0)) + got


## Зламати вдягнену зброю: річ зникає, у торбу лягає `break_yield`.
## Повертає {"назва", "лишила"}; порожньо — ламати нічого.
func break_weapon(who: Node, book: ItemBook) -> Dictionary:
	if not who.gear.has("зброя"):
		return {}
	var at := int(who.gear["зброя"])
	if at < 0 or at >= who.things.size():
		return {}
	var item: Item = who.things[at]
	var left := break_yield(item, book)
	who.drop_thing(at)
	for name: String in left:
		who.give_item(name, int(left[name]))
	return {"назва": item.title(), "лишила": left}


## Як показати, що лишилось: «залізо ×1, рунна есенція D ×1».
static func yield_text(left: Dictionary) -> String:
	var parts: Array = []
	for name: String in left:
		parts.append("%s ×%d" % [name, int(left[name])])
	return ", ".join(parts) if not parts.is_empty() else "нічого"


## Що просить зачарування цієї речі: гроші й складані речі.
func enchant_cost(item: Item, book: ItemBook) -> Dictionary:
	var e: Dictionary = rules.get("зачарування", {})
	var price := float(book.base_of(item.base).get("ціна", 0))
	var needs := {}
	var essence := "рунна есенція %s" % item.grade
	needs[essence] = int(e.get("есенції", 1))
	var metal := str(e.get("матеріал", {}).get(item.grade, ""))
	if metal != "":
		needs[metal] = int(e.get("матеріалу", 1))
	return {"гроші": maxi(1, roundi(price * float(e.get("ціна частка", 0.5)))),
			"речі": needs}


## Розмах параметра на цьому грейді — той самий множник, що в афіксів.
func scale_for(grade: String) -> float:
	var step := float(rules.get("зачарування", {}).get("крок за грейд", 0.0))
	return 1.0 + step * maxf(0.0, float(ItemBook.GRADES.find(grade)))


## Шанс кожного параметра для речі такого боку й грейду — те саме, що
## кидає `roll`, лише пораховане наперед. Звідси бере числа й вікі.
## [{стат, бік, шанс, від, до, відсотки}]
func chances(magic: bool, grade: String) -> Array:
	var e: Dictionary = rules.get("зачарування", {})
	var own := float(e.get("свій бік", 0.75))
	var out: Array = []
	for side: String in ["магічні", "фізичні"]:
		var side_chance := own if (side == "магічні") == magic else 1.0 - own
		var pool: Array = e.get(side, [])
		var total := 0.0
		for row: Dictionary in pool:
			total += float(row.get("вага", 1))
		for row: Dictionary in pool:
			out.append({
				"стат": str(row["стат"]), "бік": side,
				"шанс": side_chance * float(row.get("вага", 1))
						/ maxf(1.0, total),
				"від": maxi(1, roundi(int(row["від"]) * scale_for(grade))),
				"до": maxi(1, roundi(int(row["до"]) * scale_for(grade))),
				"відсотки": bool(row.get("відсотки", false))})
	return out


## Кинути рунне посилення: спершу бік, потім параметр за вагою, потім
## величину. Повертає {"стат", "скільки"}.
func roll(item: Item, book: ItemBook,
		rng: RandomNumberGenerator) -> Dictionary:
	var e: Dictionary = rules.get("зачарування", {})
	var magic := is_magic(item, book)
	var own := rng.randf() < float(e.get("свій бік", 0.75))
	var side := "магічні" if own == magic else "фізичні"
	var pool: Array = e.get(side, [])
	if pool.is_empty():
		return {}
	var total := 0.0
	for row: Dictionary in pool:
		total += float(row.get("вага", 1))
	var pick := rng.randf() * total
	var chosen: Dictionary = pool[-1]
	for row: Dictionary in pool:
		pick -= float(row.get("вага", 1))
		if pick <= 0.0:
			chosen = row
			break
	var s := scale_for(item.grade)
	var low := maxi(1, roundi(int(chosen["від"]) * s))
	var high := maxi(low, roundi(int(chosen["до"]) * s))
	return {"стат": str(chosen["стат"]), "скільки": rng.randi_range(low, high)}


# ── дії: і сервер, і проба кличуть саме їх ──────────────────────────
#
# Повертають порожній рядок, коли вдалось, і причину відмови, коли ні.
# Ціну рахують тут-таки щоразу заново: клієнт шле лише «оцю річ», а не
# число — інакше ремонт за 1 монету робився б правкою пакета (P1).


## Полагодити річ `at` у торбі.
func repair(who: Node, at: int, book: ItemBook) -> String:
	if at < 0 or at >= who.things.size():
		return "такої речі немає"
	var item: Item = who.things[at]
	if item.durability_max <= 0:
		return "%s не зношується" % item.title()
	var cost := repair_cost(item, book)
	if cost <= 0:
		return "%s і так ціла" % item.title()
	if Shop.money_of(who) < cost:
		return "на ремонт треба %d, а в тебе %d" % [cost, Shop.money_of(who)]
	Shop.take_money(who, cost)
	var was_blunt := item.is_blunt()
	item.durability = item.durability_max
	if was_blunt:
		who.refresh_stats()
	return ""


## Чого бракує на зачарування: порожньо — усього досить.
func missing_for(who: Node, item: Item, book: ItemBook) -> Array:
	var cost := enchant_cost(item, book)
	var out: Array = []
	if Shop.money_of(who) < int(cost["гроші"]):
		out.append("гроші %d" % (int(cost["гроші"]) - Shop.money_of(who)))
	for name: String in cost["речі"]:
		var need := int(cost["речі"][name])
		var have := int(who.items.get(name, 0))
		if have < need:
			out.append("%s ×%d" % [name, need - have])
	return out


## Зачарувати річ `at`: забрати ціну, кинути руну, повернути міцність.
## Повертає причину відмови або порожньо; що саме випало — у `last`.
var last: Dictionary = {}


func enchant(who: Node, at: int, book: ItemBook,
		rng: RandomNumberGenerator) -> String:
	last = {}
	if at < 0 or at >= who.things.size():
		return "такої речі немає"
	var item: Item = who.things[at]
	if not item.kind in ["зброя", "обладунок", "амулет"]:
		return "%s не зачаровується" % item.title()
	var lacking := missing_for(who, item, book)
	if not lacking.is_empty():
		return "бракує: %s" % ", ".join(lacking)
	var cost := enchant_cost(item, book)
	Shop.take_money(who, int(cost["гроші"]))
	for name: String in cost["речі"]:
		who.take_item(name, int(cost["речі"][name]))
	last = roll(item, book, rng)
	item.set_rune(last)
	if item.durability_max > 0:
		item.durability = item.durability_max
	who.refresh_stats()
	return ""


## Як показати руну людині: «інтелект +3», «швидкість касту +4%».
static func rune_text(rune: Dictionary) -> String:
	if rune.is_empty():
		return ""
	var stat := str(rune.get("стат", ""))
	return "%s +%d%s" % [stat, int(rune.get("скільки", 0)),
			"%" if stat in PERCENTS else ""]
