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


## Кого бити й скільки (П-227): квест у грі — одна умова «убити N виду».
func quest_kind(key: String) -> String:
	for cond: Dictionary in quest_of(key).get("умови", []):
		if cond.has("вбити"):
			return str(cond["вбити"])
	return ""


func quest_need(key: String) -> int:
	for cond: Dictionary in quest_of(key).get("умови", []):
		if cond.has("вбити"):
			return int(cond.get("скільки", 1))
	return 0


## Чи взято саме це завдання.
func quest_taken(who: Node, key: String) -> bool:
	return str(who.quest.get("професія", "")) == key


## Лічильник «убито|треба» (П-227). Рахується від мітки, поставленої,
## коли завдання взяли в майстра гільдії: убиті до того не йдуть у
## рахунок. Не взято — нуль. Один рядок {що, зроблено, треба, готово,
## взято} — у тому самому вигляді, що й раніше, щоб показ не міняти.
func quest_progress(who: Node, key: String) -> Array:
	var kind := quest_kind(key)
	if kind == "":
		return []
	var need := quest_need(key)
	var done := 0
	if quest_taken(who, key):
		done = maxi(0, int(who.kills.get(kind, 0)) - int(who.quest.get("від", 0)))
	return [{"що": "убити %s" % kind, "зроблено": mini(done, need),
			"треба": need, "готово": done >= need,
			"взято": quest_taken(who, key)}]


## Лічильник одним рядком для екрана: «вовкулака 3|10». Порожньо — нічого
## не взято.
func quest_line(who: Node) -> String:
	var key := str(who.quest.get("професія", ""))
	if key == "" or not rows.has(key):
		return ""
	var steps := quest_progress(who, key)
	if steps.is_empty():
		return ""
	return "%s %d|%d" % [quest_kind(key), int(steps[0]["зроблено"]),
			int(steps[0]["треба"])]


## Чи можна йти на цю професію взагалі: батько й рівень. Квест — окремо.
func _why_not_path(who: Node, key: String) -> String:
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
	return ""


## Чи дадуть завдання — без наслідків, для показу кнопки.
func why_not_quest(who: Node, key: String) -> String:
	var why := _why_not_path(who, key)
	if why != "":
		return why
	if quest_kind(key) == "":
		return "у цієї професії немає завдання"
	if quest_taken(who, key):
		return "завдання вже взято"
	return ""


## Узяти завдання в майстра гільдії (П-227). Порожній рядок — узято.
## Одне завдання за раз: нове замінює старе (лічильник починається
## наново) — гравець передумав, куди йти.
func take_quest(who: Node, key: String) -> String:
	var why := why_not_quest(who, key)
	if why != "":
		return why
	who.quest = {"професія": key,
			"від": int(who.kills.get(quest_kind(key), 0))}
	return ""


## Чи можна взяти цю професію. Порожній рядок — можна, інакше причина.
func why_not(who: Node, key: String) -> String:
	var why := _why_not_path(who, key)
	if why != "":
		return why
	if quest_kind(key) == "":
		return ""
	if not quest_taken(who, key):
		return "спершу візьми завдання в майстра гільдії"
	for step: Dictionary in quest_progress(who, key):
		if not step["готово"]:
			return "завдання «%s»: %s — %d|%d" % [
					str(quest_of(key).get("назва", "")), step["що"],
					int(step["зроблено"]), int(step["треба"])]
	return ""


## Узяти професію. Виконане завдання знімається.
func take(who: Node, key: String) -> String:
	var why := why_not(who, key)
	if why != "":
		return why
	who.profession = key
	who.quest = {}
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
