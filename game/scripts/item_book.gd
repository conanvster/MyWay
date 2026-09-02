class_name ItemBook
extends RefCounted
## Усі речі з `data/items.json` і кидання афіксів (крок 4).
##
## Афікси — пропозиція П-83 (випадкові властивості, як у D2). Якщо
## замовник вирішить, що характеристики мають бути фіксовані, перелік
## афіксів у файлі просто порожніє: код лишається той самий, речі стають
## однаковими.

## Порядок грейдів: афікс «з грейду D» на E-річ не випаде.
const GRADES := ["E", "D", "C", "B", "A", "S", "SS"]

var bases: Dictionary = {}
var affixes: Dictionary = {}


func load_from(raw: Dictionary) -> void:
	bases = raw.get("бази", {})
	affixes = raw.get("афікси", {})


func has(name: String) -> bool:
	return bases.has(name)


func base_of(name: String) -> Dictionary:
	return bases.get(name, {})


func kind_of(name: String) -> String:
	return str(base_of(name).get("вид", ""))


## Складані речі рахуються кількістю, поодинокі — ні.
func is_stackable(name: String) -> bool:
	return kind_of(name) in ["гроші", "ресурс", "руна", "витратне"]


func count() -> int:
	return bases.size()


## Зробити річ із бази. `rolled` порожній — афікси кидаються заново.
func make(name: String, rolled: Array = []) -> Item:
	if not has(name):
		return null
	var data: Dictionary = base_of(name)
	var item := Item.new()
	item.base = name
	item.kind = str(data.get("вид", ""))
	item.slot = str(data.get("слот", ""))
	item.grade = str(data.get("грейд", "E"))
	item.affixes = rolled if not rolled.is_empty() \
			else _roll(item.grade, str(data.get("рід", "ч")))
	# JSON не знає цілих: без цього «витривалість» приходила як 1.0, і в
	# показі речі стояло б «+1.0» замість «+1».
	item.stats = {}
	for stat in data.get("стати", {}):
		item.stats[stat] = int(data["стати"][stat])
	for affix: Dictionary in item.affixes:
		var stat: String = affix["стат"]
		item.stats[stat] = int(item.stats.get(stat, 0)) + int(affix["скільки"])
	return item


## Кинути афікси: не більше одного спереду й одного ззаду.
##
## Афікс спереду — прикметник, і він мусить збігтися з річчю в роді:
## «міцний меч», але «міцна куртка». Форми лежать у даних, бо це
## українська мова, а не властивість коду.
func _roll(grade: String, gender: String = "ч") -> Array:
	var out: Array = []
	for where: String in ["спереду", "ззаду"]:
		for affix: Dictionary in affixes.get(where, []):
			if not _grade_allows(grade, str(affix.get("з грейду", "E"))):
				continue
			if randf() > float(affix.get("шанс", 0.0)):
				continue
			var name: Variant = affix["назва"]
			out.append({
				"де": where,
				"назва": name.get(gender, name.values()[0]) \
						if name is Dictionary else name,
				"стат": affix["стат"],
				"скільки": randi_range(int(affix["від"]), int(affix["до"])),
			})
			break        # з кожного боку не більше одного
	return out


## Що показати гравцеві: вдягнене окремо, решта окремо. Робиться тут, бо
## і бій, і дії шлють одне й те саме, а знати про HUD їм не треба.
static func bag_of(who: Node) -> Dictionary:
	var worn: Array = []
	var carried: Array = []
	for at in who.things.size():
		var item: Item = who.things[at]
		var line := item.title()
		if who.is_worn(at):
			worn.append("%s: %s" % [item.slot, line])
		else:
			carried.append(line)
	var stacks: Array = []
	for name in who.items:
		stacks.append("%s ×%d" % [name, int(who.items[name])])
	return {"вдягнене": worn, "у торбі": carried + stacks}


static func _grade_allows(item_grade: String, need: String) -> bool:
	return GRADES.find(item_grade) >= GRADES.find(need)
