class_name Item
extends RefCounted
## Одна річ: база плюс те, що на неї випало (крок 4).
##
## Речі бувають двох ґатунків, і це не примха:
##
##   складані  — гроші, ресурси, руни, витратне. Їх рахують кількістю,
##               і в інвентарі вони лежать як «ім'я → скільки».
##   поодинокі — зброя, обладунки, амулети. У кожної свої випадкові
##               афікси (П-83), тож дві однакові куртки різні, і
##               кількістю їх не порахувати.
##
## Цей клас — про поодинокі. Складані обходяться без нього.

var base := ""          ## ключ у `data/items.json`
var kind := ""          ## зброя · обладунок · амулет
var slot := ""          ## куди вдягається
## Зброя на дві руки: щит із нею не вдягнути (і навпаки).
var two_handed := false
var grade := "E"
## Стати від бази й від афіксів, уже складені: "сила" -> 3.
var stats: Dictionary = {}
## Що випало: [{"назва", "стат", "скільки"}], не більше двох.
var affixes: Array = []
## Міцність (21.09.2026, лише зброя). `durability_max` 0 — у речі
## міцності немає зовсім. На нулі зброя ламається на матеріали (П-234,
## `Smith.break_weapon`). «Тупа» — лише річ, збережена на нулі до
## 01.10.2026: її стати не діють (`Creature._gear_bonus`), доки коваль не
## полагодить.
var durability := 0
var durability_max := 0
## Рунне посилення від коваля: {"стат", "скільки"}. Одне на річ — нове
## замінює старе. Уже враховане в `stats`.
var rune: Dictionary = {}


func is_blunt() -> bool:
	return durability_max > 0 and durability <= 0


## Покласти рунне посилення: старе з `stats` знімається, нове додається.
func set_rune(new_rune: Dictionary) -> void:
	if not rune.is_empty():
		var old: String = rune["стат"]
		stats[old] = int(stats.get(old, 0)) - int(rune["скільки"])
		if int(stats[old]) == 0:
			stats.erase(old)
	rune = new_rune
	if not rune.is_empty():
		var stat: String = rune["стат"]
		stats[stat] = int(stats.get(stat, 0)) + int(rune["скільки"])


## Назва, яку бачить гравець: «гострий меч з кори дуба вовчої зграї».
func title() -> String:
	var before := ""
	var after := ""
	for affix: Dictionary in affixes:
		if affix.get("де", "") == "спереду":
			before = affix["назва"] + " "
		else:
			after = " " + affix["назва"]
	return before + base + after


## Для збереження в базу: усе, що потрібно, щоб відтворити річ.
func to_row() -> Dictionary:
	var row := {"база": base, "грейд": grade, "афікси": affixes}
	if durability_max > 0:
		row["міцність"] = [durability, durability_max]
	if not rune.is_empty():
		row["руна"] = rune
	return row


static func from_row(row: Dictionary, book: Object) -> Item:
	var made: Item = book.make(str(row.get("база", "")),
			row.get("афікси", []))
	if made != null:
		made.grade = str(row.get("грейд", made.grade))
		# Річ, збережена до 21.09.2026, міцності в рядку не має — тоді
		# лишається та, з якою її щойно зробила книга (повна).
		var worn: Array = row.get("міцність", [])
		if worn.size() == 2:
			made.durability = int(worn[0])
			made.durability_max = int(worn[1])
		var saved_rune: Variant = row.get("руна", {})
		if saved_rune is Dictionary and not saved_rune.is_empty():
			made.set_rune({"стат": str(saved_rune.get("стат", "")),
					"скільки": int(saved_rune.get("скільки", 0))})
	return made
