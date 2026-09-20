class_name Professions
extends RefCounted
## Професії, етапи, квести переходу й приховані гілки (П-224).
##
## Слово замовника 20.09.2026: «кожна професія розвивається та має
## декілька етапів (початковий, середній, основна професія, найвищий
## рівень), при переході необхідно виконати квест… допоміжні гілки
## скриті і можуть бути відкриті за деяких умов, наприклад знайшовши
## рідкісний амулет або вбивши певну кількість монстрів певного типу…
## деякі гілки можуть бути відкриті вмінням синтезу навичок».
##
## Клас нічого не знає про мережу й вузли: питає «можна чи ні» і
## відповідає причиною словами, які видно гравцеві — так само, як
## `Runes`.

var rows: Dictionary = {}          ## ключ професії → її рядок з даних
var stages: Dictionary = {}        ## номер етапу → {назва, від, до}


func load_from(data: Dictionary) -> void:
	rows = data.get("професії", {})
	stages = data.get("етапи", {})


func has(key: String) -> bool:
	return rows.has(key)


func name_of(key: String) -> String:
	return str(rows.get(key, {}).get("назва", key))


func stage_of(key: String) -> int:
	return int(rows.get(key, {}).get("етап", 1))


## Ланцюг професій згори вниз: твердиня → латник → воїн. Вміння всіх
## професій ланцюга лишаються при гравцеві: перехід не забирає вивченого.
func line(key: String) -> Array:
	var out: Array = []
	var at := key
	while at != "" and rows.has(at) and not out.has(at):
		out.append(at)
		at = str(rows[at].get("батько", ""))
	return out


## Куди можна піти далі з тієї професії, що зараз. Рівень тут не
## перевіряється: гравець має БАЧИТИ, що його чекає, ще до того, як
## доросте — інакше гілки дерева існують лише в голові розробника.
func next_after(key: String) -> Array:
	var out: Array = []
	for other: String in rows:
		if str(rows[other].get("батько", "")) == key:
			out.append(other)
	out.sort()
	return out


func quest_of(key: String) -> Dictionary:
	return rows.get(key, {}).get("квест", {})


## Скільки з умови вже зроблено й скільки треба. Одна умова — один рядок
## {що, зроблено, треба, готово}.
func quest_progress(who: Node, key: String) -> Array:
	var out: Array = []
	for cond: Dictionary in quest_of(key).get("умови", []):
		var done := 0
		var need := int(cond.get("скільки", 1))
		var what := ""
		if cond.has("вбити"):
			what = "убити %s" % cond["вбити"]
			done = int(who.kills.get(cond["вбити"], 0))
		elif cond.has("принести"):
			what = "принести %s" % cond["принести"]
			done = int(who.items.get(cond["принести"], 0))
		out.append({"що": what, "зроблено": mini(done, need),
				"треба": need, "готово": done >= need})
	return out


## Чи можна взяти цю професію. Порожній рядок — можна, інакше причина.
func why_not(who: Node, key: String) -> String:
	if not rows.has(key):
		return "такої професії немає"
	var row: Dictionary = rows[key]
	if who.profession == key:
		return "ти вже %s" % name_of(key)
	if str(row.get("батько", "")) != who.profession:
		var parent := str(row.get("батько", ""))
		return "спершу потрібно бути: %s" % (name_of(parent)
				if parent != "" else "без професії")
	if who.level < int(row.get("з рівня", 1)):
		return "%s береться з %d рівня" % [name_of(key),
				int(row.get("з рівня", 1))]
	for step: Dictionary in quest_progress(who, key):
		if not step["готово"]:
			return "квест «%s»: %s — %d із %d" % [
					str(quest_of(key).get("назва", "")), step["що"],
					int(step["зроблено"]), int(step["треба"])]
	return ""


## Узяти професію. Речі, які просив квест, ЗАБИРАЮТЬСЯ: інакше одна
## в'язка шкур провела б крізь усі чотири етапи.
func take(who: Node, key: String) -> String:
	var why := why_not(who, key)
	if why != "":
		return why
	for cond: Dictionary in quest_of(key).get("умови", []):
		if cond.has("принести"):
			var what := str(cond["принести"])
			var need := int(cond.get("скільки", 1))
			who.items[what] = maxi(0, int(who.items.get(what, 0)) - need)
			if who.items[what] == 0:
				who.items.erase(what)
	who.profession = key
	return ""


# ──────────────────────── приховані гілки ───────────────────────────

func branch_of(key: String) -> Dictionary:
	return rows.get(key, {}).get("гілка", {})


## Чи відкрита гілка тому, хто питає. Назва гілки, а не ключ професії:
## саме назва стоїть у самому вмінні.
func branch_open(who: Node, branch: String) -> bool:
	return branch == "" or who.opened.has(branch)


## Пройтись усіма гілками ланцюга й відкрити ті, чия умова вже виконана.
## Повертає назви щойно відкритих — світ із них робить повідомлення.
##
## Три умови, усі три — слово замовника: рідкісний амулет у торбі, певна
## кількість убитих певного виду, вивчене вміння синтезу.
func open_ready(who: Node) -> Array:
	var fresh: Array = []
	for key: String in line(who.profession):
		var branch: Dictionary = branch_of(key)
		var title := str(branch.get("назва", ""))
		if title == "" or who.opened.has(title):
			continue
		var how: Dictionary = branch.get("відкриття", {})
		var kind := str(how.get("як", ""))
		var ready := false
		match kind:
			"амулет":
				ready = int(who.items.get(str(how.get("річ", "")), 0)) > 0
			"полювання":
				ready = int(who.kills.get(str(how.get("вид", "")), 0)) \
						>= int(how.get("скільки", 0))
			"синтез":
				ready = who.knows(str(how.get("скіл", "")))
		if ready:
			who.opened.append(title)
			fresh.append(title)
	return fresh


## Як саме відкривається гілка — рядком для гравця. Показуємо ДО
## відкриття: приховане вміння лишається прихованим, а от натяк, куди
## копати, гравець має мати, інакше гілку знайде тільки той, хто читав
## файли гри.
func hint_for(key: String) -> String:
	var how: Dictionary = branch_of(key).get("відкриття", {})
	match str(how.get("як", "")):
		"амулет":
			return "знайти %s" % str(how.get("річ", ""))
		"полювання":
			return "убити %d × %s" % [int(how.get("скільки", 0)),
					str(how.get("вид", ""))]
		"синтез":
			return "злити вміння синтезом"
	return ""
