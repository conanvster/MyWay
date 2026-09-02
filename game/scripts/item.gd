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
	return {"база": base, "грейд": grade, "афікси": affixes}


static func from_row(row: Dictionary, book: Object) -> Item:
	var made: Item = book.make(str(row.get("база", "")),
			row.get("афікси", []))
	if made != null:
		made.grade = str(row.get("грейд", made.grade))
	return made
