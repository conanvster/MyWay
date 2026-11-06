extends SceneTree
## Проба кування (П-22, П-258): рецепт = метал грейду ×10.
##
##     godot --headless --path game --script res://probes/forge.gd
##
## Числа, а не «начебто кується»: скільки рецептів, звідки падає метал
## кожного (лише зі своєї смуги рівнів — інакше річ B кувалась би зі
## скелетів 8 рівня), сходинка цін, кування з нестачею й без, поломка.

const AVATAR := preload("res://scenes/avatar.tscn")

var _bad := 0


func _init() -> void:
	call_deferred("_go")


func _expect(what: String, ok: bool) -> void:
	if not ok:
		_bad += 1
	print("  %s %s" % ["✓" if ok else "✗", what])


func _go() -> void:
	await process_frame
	GameData.chosen_map = GameData.MAP2_PATH
	var data := GameData.new()
	data.load_all()
	var smith: Smith = data.smith
	var book: ItemBook = data.items

	print("\n— що кується —")
	var kinds: Array = smith.rules["крафт"]["види"]
	var expected := 0
	for base: String in book.bases:
		var info: Dictionary = book.base_of(base)
		if str(info.get("вид", "")) in kinds and info.has("грейд"):
			expected += 1
	var all: Array = smith.recipes(book)
	print("    рецептів %d (усе спорядження з грейдом)" % all.size())
	_expect("рецепт має кожна річ з грейдом серед %s" % [kinds],
			all.size() == expected and expected > 0)
	_expect("артефакт, ключ, руна, зілля — не куються",
			smith.recipe("артефакт ока бога", book).is_empty()
			and smith.recipe("ключ святині E", book).is_empty()
			and smith.recipe("зілля лікування", book).is_empty())
	_expect("квестовий амулет без грейду — не кується",
			smith.recipe("амулет солоної крові", book).is_empty())

	print("\n— метал кожного грейду: звідки падає й почому —")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
			GameData.ITEMS_PATH))
	var bands := _bands(raw)
	var metals: Dictionary = smith.rules["зачарування"]["матеріал"]
	var last_price := 0
	for grade: String in ItemBook.GRADES:
		var metal := str(metals[grade])
		var levels := _drop_levels(data.mobs, metal)
		var band: Array = bands[grade]
		var price := int(book.base_of(metal).get("ціна", 0))
		var medians := _median_price(book, grade)
		print("    %-3s %-14s ціна %5d · падає з рівнів %s (смуга %d–%d) · "
				% [grade, metal, price, levels, band[0], band[1]]
				+ "рецепт %d проти медіани речі %d (%.0f%%)"
				% [price * 10, medians, 100.0 * price * 10 / maxf(1, medians)])
		_expect("%s: %s падає, і лише в смузі %s" % [grade, metal, grade],
				not levels.is_empty() and levels.min() >= band[0]
				and levels.max() <= band[1])
		if last_price > 0:
			_expect("%s: ціна ≈ ×3 від попереднього (%.1f)"
					% [grade, float(price) / last_price],
					absf(float(price) / last_price - 3.0) < 0.6)
		last_price = price

	print("\n— кування —")
	var hero: Node3D = AVATAR.instantiate()
	root.add_child(hero)
	await process_frame
	var sword := "меч з кори дуба"
	var needs: Dictionary = smith.recipe(sword, book)
	_expect("рецепт меча E: %s" % [needs], needs == {"кора дуба": 10})
	hero.items = {"кора дуба": 9}
	var things: int = hero.things.size()
	var why := smith.forge(hero, sword, book)
	_expect("з 9 корою — відмова: «%s»" % why, why != ""
			and int(hero.items.get("кора дуба", 0)) == 9
			and hero.things.size() == things)
	hero.items = {"кора дуба": 10}
	why = smith.forge(hero, sword, book)
	var made: Item = smith.forged
	_expect("з 10 — скуто «%s»" % (made.title() if made else "?"),
			why == "" and made != null and made.base == sword
			and hero.things.size() == things + 1)
	_expect("кору забрано вся", int(hero.items.get("кора дуба", 0)) == 0)
	_expect("зброя з повною міцністю (%d)" % made.durability,
			made.durability_max > 0 and made.durability == made.durability_max)
	_expect("річ невідома — відмова", smith.forge(hero, "щось", book) != "")

	var with_affix := 0
	for i in 200:
		hero.items = {"кора дуба": 10}
		smith.forge(hero, sword, book)
		if not smith.forged.affixes.is_empty():
			with_affix += 1
	print("    афікси випали на %d з 200 скутих — як і з дропу" % with_affix)
	_expect("афікси кидаються", with_affix > 0)

	print("\n— поломка повертає 10% рецепта (П-234) —")
	var left := smith.break_yield(made, book)
	_expect("зламаний меч E лишає %s" % [left], left == {"кора дуба": 1})
	var b_sword := ""
	for base: String in all:
		if str(book.base_of(base)["грейд"]) == "B" \
				and str(book.base_of(base)["вид"]) == "зброя":
			b_sword = base
			break
	var b_item := book.make(b_sword)
	_expect("зламана зброя B («%s») лишає мітрил ×1: %s"
			% [b_sword, smith.break_yield(b_item, book)],
			smith.break_yield(b_item, book) == {"мітрил": 1})

	hero.queue_free()
	print("\nпомилок: %d" % _bad)
	quit(1 if _bad > 0 else 0)


## Грейд → [перший рівень, останній] з `items.json → грейди → до рівня`.
func _bands(raw: Dictionary) -> Dictionary:
	var top: Dictionary = raw["грейди"]["до рівня"]
	var out := {}
	var low := 1
	for grade: String in ItemBook.GRADES:
		out[grade] = [low, int(top[grade])]
		low = int(top[grade]) + 1
	return out


func _drop_levels(mobs: Dictionary, what: String) -> Array:
	var out: Array = []
	for key: String in mobs:
		var mob = mobs[key]
		if not mob is Dictionary:
			continue
		for row in mob.get("дроп", []):
			if row is Dictionary and str(row.get("що", "")) == what:
				out.append(int(mob.get("рівень", 1)))
	return out


func _median_price(book: ItemBook, grade: String) -> int:
	var prices: Array = []
	for base: String in book.bases:
		var info: Dictionary = book.base_of(base)
		if str(info.get("грейд", "")) == grade \
				and str(info.get("вид", "")) in ["зброя", "обладунок", "амулет"]:
			prices.append(int(info.get("ціна", 0)))
	prices.sort()
	return prices[prices.size() / 2] if not prices.is_empty() else 0
