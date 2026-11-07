class_name Appearance
extends RefCounted
## Зовнішність гравця: варіант моделі, зачіска, кольори (07.11.2026).
##
## Слово замовника: «не реалізовані вибори персонажів як ми додали в базі
## знань гри по 3 варіанти кожного, вибір зачісок та кольору зачісок та
## очей». Вигляд стати не міняє (`wiki/rasy.html`: «Вигляд стати не міняє»).
##
## Зберігається НАЗВАМИ, не кольорами: {«варіант»: 1, «зачіска»: «коса»,
## «волосся»: «рудий», «очі»: «зелені», «шкіра»: «смаглява», «губи»: …,
## «підводка»: «легка», «ніс»/«очі_форма»/«вуха»/«губи_форма»: назва
## форм-ключа}. Назви читає і людина в базі, і сервер перевіряє їх за
## переліком — чужий колір чи вигадану зачіску не підсунути.

## Палітри — ті самі, що в переглядачі моделей (звідти й перенесено).
const HAIR := [["як є", null], ["сивий", Color(0.92, 0.93, 0.96)],
		["сірий", Color(0.48, 0.48, 0.5)], ["солом'яний", Color(0.9, 0.78, 0.5)],
		["червоний", Color(0.62, 0.12, 0.1)], ["рудий", Color(0.8, 0.38, 0.16)],
		["каштановий", Color(0.36, 0.21, 0.12)], ["чорний", Color(0.1, 0.09, 0.09)],
		["білий", Color(1, 1, 1)]]
const EYES := [["як є", null], ["блакитні", Color(0.3, 0.55, 0.9)],
		["зелені", Color(0.3, 0.65, 0.35)], ["сірі", Color(0.55, 0.6, 0.65)],
		["бурштинові", Color(0.85, 0.55, 0.15)], ["фіалкові", Color(0.55, 0.35, 0.85)],
		["червоні", Color(0.8, 0.1, 0.1)], ["карі", Color(0.35, 0.2, 0.1)]]
const LIPS := [["як є", null], ["рожеві", Color(0.85, 0.5, 0.55)],
		["ягідні", Color(0.55, 0.15, 0.3)], ["червоні", Color(0.75, 0.1, 0.12)],
		["бліді", Color(0.82, 0.66, 0.62)]]
const SKIN := [["як є", null], ["місячно-бліда", Color(0.88, 0.86, 0.85)],
		["світла", Color(0.86, 0.72, 0.64)], ["смаглява", Color(0.7, 0.52, 0.4)],
		["бронзова", Color(0.55, 0.38, 0.26)], ["оливкова", Color(0.68, 0.6, 0.45)],
		["сіро-блакитна", Color(0.55, 0.6, 0.7)], ["попелясто-сіра", Color(0.5, 0.5, 0.52)]]
const LINER := [["немає", 0.0], ["легка", 0.45], ["темна", 0.85]]
## Кольорові вибори: ключ збереження → [палітра, ключ `SkinnedModel.customize`].
const COLOURS := {
	"волосся": [HAIR, "колір_волосся"],
	"очі": [EYES, "колір_очей"],
	"губи": [LIPS, "колір_губ"],
	"шкіра": [SKIN, "колір_шкіри"],
}
## Риси (форм-ключі `Ніс-…`, `Губи-…`, `Очі-…`, `Вуха-…`): ключ
## збереження → ключ `customize`.
const SHAPES := {"ніс": "ніс", "губи_форма": "губи", "очі_форма": "очі",
		"вуха": "вуха"}
const VARIANTS := 3

## Аватари зі сканів на скелеті Mixamo: «раса-стать» → модель на кожен
## варіант. Варіанта ще немає (скан не зроблено) — береться перший, і
## екран створення каже про це чесно (`ready_variants`).
const SCAN_DIR := "res://models/own/avatary/"
const SCANS := {
	"орк-жінка": [SCAN_DIR + "ork-s1303-mixamo/ork-s1303-mixamo.glb"],
	"ельф-жінка": [SCAN_DIR + "elf-e1903-mixamo/elf-e1903-mixamo.glb"],
	"людина-жінка": [SCAN_DIR + "lyud-l2002-mixamo/lyud-l2002-mixamo.glb"],
}


static func kind_of(race: String, sex: String) -> String:
	return "%s-%s" % [race, "жінка" if sex == "жінка" else "чоловік"]


## Скільки варіантів цього типу вже мають свою модель.
static func ready_variants(race: String, sex: String) -> int:
	return (SCANS.get(kind_of(race, sex), []) as Array).size()


## Модель для варіанта; порожньо — скану цього типу немає.
static func model_of(race: String, sex: String, variant: int) -> String:
	var list: Array = SCANS.get(kind_of(race, sex), [])
	if list.is_empty():
		return ""
	return str(list[clampi(variant - 1, 0, list.size() - 1)])


static func names_of(palette: Array) -> Array:
	var out: Array = []
	for row: Array in palette:
		out.append(row[0])
	return out


static func _colour(palette: Array, name: String) -> Variant:
	for row: Array in palette:
		if row[0] == name:
			return row[1]
	return null


## Сервер: лишити тільки відомі ключі й назви з палітр. Зачіску й риси
## перевіряє клієнт за моделлю (сервер моделей не вантажить): невідома
## назва там просто нічого не міняє.
static func clean(raw: Variant) -> Dictionary:
	var out := {"варіант": 1}
	if not raw is Dictionary:
		return out
	var d: Dictionary = raw
	out["варіант"] = clampi(int(d.get("варіант", 1)), 1, VARIANTS)
	for key: String in COLOURS:
		var name := str(d.get(key, ""))
		if name in names_of(COLOURS[key][0]):
			out[key] = name
	var liner := str(d.get("підводка", ""))
	if liner in names_of(LINER):
		out["підводка"] = liner
	for key: String in ["зачіска"] + SHAPES.keys():
		var v := str(d.get(key, "")).strip_edges()
		if v != "" and v.length() <= 32:
			out[key] = v
	return out


## Збережене (назви) → словник для `SkinnedModel.customize` (кольори).
static func to_look(saved: Dictionary) -> Dictionary:
	var look := {}
	for key: String in COLOURS:
		if saved.has(key):
			look[COLOURS[key][1]] = _colour(COLOURS[key][0], str(saved[key]))
	if saved.has("підводка"):
		look["підводка"] = float(_colour(LINER, str(saved["підводка"])))
	if saved.has("зачіска"):
		look["зачіска"] = str(saved["зачіска"])
	for key: String in SHAPES:
		if saved.has(key):
			look[SHAPES[key]] = str(saved[key])
	return look
