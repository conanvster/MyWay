extends Node
## Професії, етапи, квести й приховані гілки (П-224, слово замовника
## 20.09.2026: «зроби дерево вмінь та скілів до S (75 рівень); кожна
## професія розвивається та має декілька етапів… при переході необхідно
## виконати квест… допоміжні гілки скриті… деякі гілки можуть бути
## відкриті вмінням синтезу навичок»).
##
## Перевіряємо не «начебто працює», а самі числа: чи бачить гравець лише
## свій ланцюг, чи мовчить прихована гілка до відкриття, чи не пускає
## квест того, хто його не зробив, і чи є чим вивчити кожне вміння.
##
##     godot --headless --path game res://scenes/profesii.tscn

const WORLD := preload("res://scripts/world.gd")

var _ok := 0
var _bad := 0
var _data: GameData


class Хтось extends Node:
	var race := "людина"
	var sex := "чоловік"
	var learned := {}
	var profession := ""
	var opened: Array[String] = []
	var kills := {}
	var quest := {}
	var items := {}
	var level := 1
	var experience := 0

	func knows(key: String) -> bool:
		return learned.has(key)

	func learn(key: String, at: int) -> void:
		learned[key] = at

	func has_item(name: String) -> bool:
		return int(items.get(name, 0)) > 0

	func take_item(name: String) -> void:
		items[name] = maxi(0, int(items.get(name, 0)) - 1)


func _ready() -> void:
	_go()


func _yes(text: String, is_ok: bool) -> void:
	_ok += 1 if is_ok else 0
	_bad += 0 if is_ok else 1
	print("  %s %s" % ["✓" if is_ok else "✗", text])


func _go() -> void:
	await get_tree().process_frame
	_data = GameData.new()
	_data.load_all()
	_дані()
	_видно()
	_квест()
	_гілки()
	_синтез()
	_руни()
	print("  підсумок: %s" % ("усе гаразд" if _bad == 0
			else "‼ вад: %d" % _bad))
	get_tree().quit(1 if _bad > 0 else 0)


func _світ() -> Node:
	# Саме `new()` без додавання у дерево: світ у `_ready` підіймає
	# мережу, а пробі потрібні лише його перевірки видимості.
	var world: Node = WORLD.new()
	world.data = _data
	world.runes = Runes.new(_data.skills, _data.professions)
	return world


func _хтось(profession: String, level: int) -> Хтось:
	var хто := Хтось.new()
	хто.profession = profession
	хто.level = level
	add_child(хто)
	return хто


func _дані() -> void:
	print("\n— що в даних —")
	var profs: Professions = _data.professions
	_yes("професій 20", profs.rows.size() == 20)
	var етапи := {}
	for key: String in profs.rows:
		var е := profs.stage_of(key)
		етапи[е] = int(етапи.get(е, 0)) + 1
	print("    за етапами: %s" % [етапи])
	_yes("етапи 2, 3 і 4: 4 · 8 · 8",
			int(етапи.get(2, 0)) == 4 and int(етапи.get(3, 0)) == 8
			and int(етапи.get(4, 0)) == 8)

	var без_квеста: Array = []
	var без_гілки: Array = []
	var обірвані: Array = []
	for key: String in profs.rows:
		if profs.quest_of(key).get("умови", []).is_empty():
			без_квеста.append(key)
		if profs.hint_for(key) == "":
			без_гілки.append(key)
		var ланцюг: Array = profs.line(key)
		var корінь: String = ланцюг[ланцюг.size() - 1]
		if profs.stage_of(корінь) != 2:
			обірвані.append(key)
	_yes("у кожної професії є квест переходу з умовами",
			без_квеста.is_empty())
	_yes("у кожної професії є прихована гілка з умовою відкриття",
			без_гілки.is_empty())
	_yes("кожен ланцюг доходить до першої професії", обірвані.is_empty())

	var умови := {}
	for key: String in profs.rows:
		var how: Dictionary = profs.branch_of(key).get("відкриття", {})
		var як := str(how.get("як", ""))
		умови[як] = int(умови.get(як, 0)) + 1
	print("    чим відкриваються гілки: %s" % [умови])
	_yes("є всі три способи відкриття (амулет, полювання, синтез)",
			умови.size() == 3)

	# Драбина грейдів: до 75 рівня має бути S і не вище.
	var верх := 0
	var грейди := {}
	var поза: Array = []
	for key: String in _data.skills.keys():
		var s: Skill = _data.skills.get_skill(key)
		if s.profession == "":
			continue
		верх = maxi(верх, s.from_level)
		грейди[s.grade] = int(грейди.get(s.grade, 0)) + 1
		if s.from_level > 75:
			поза.append(key)
	print("    умінь професій за грейдом: %s, найвищий рівень %d"
			% [грейди, верх])
	_yes("дерево доходить до S грейду", int(грейди.get("S", 0)) > 0)
	_yes("вище 75 рівня вмінь немає", поза.is_empty() and верх == 75)


func _видно() -> void:
	print("\n— що показує гільдмайстер —")
	var world := _світ()
	var новачок := _хтось("", 19)
	var його_все: Array = world._guild_rows(новачок)
	var спільних := 0
	var расових := 0
	for row: Dictionary in його_все:
		if str(row.get("професія", "")) != "":
			continue
		if str(row.get("вкладка", "")).begins_with("Спадок"):
			расових += 1
		else:
			спільних += 1
	print("    без професії видно %d умінь: спільних %d, расових %d"
			% [його_все.size(), спільних, расових])
	_yes("новачок бачить 16 спільних і 5 расових (своєї статі)",
			спільних == 16 and расових == 5)
	_yes("професійних умінь новачкові не показують",
			його_все.size() == спільних + расових)

	var воїн := _хтось("воїн", 39)
	var його: Array = world._guild_rows(воїн)
	var свої := 0
	var чужі := 0
	for row: Dictionary in його:
		var проф := str(row.get("професія", ""))
		if проф == "воїн":
			свої += 1
		elif проф != "":
			чужі += 1
	print("    воїн бачить %d умінь, з них своїх професійних %d"
			% [його.size(), свої])
	_yes("воїн бачить свої професійні вміння", свої > 0)
	_yes("чужих професій воїн не бачить", чужі == 0)

	var твердиня := _хтось("твердиня", 75)
	var ланцюг := {}
	for row: Dictionary in world._guild_rows(твердиня):
		var проф := str(row.get("професія", ""))
		if проф != "":
			ланцюг[проф] = true
	print("    твердиня бачить професії: %s" % [ланцюг.keys()])
	_yes("твердиня бачить увесь свій ланцюг (воїн → латник → твердиня)",
			ланцюг.size() == 3 and ланцюг.has("воїн")
			and ланцюг.has("латник") and ланцюг.has("твердиня"))

	# Прихована гілка мовчить, доки не відкрита.
	var приховані := 0
	for row: Dictionary in world._guild_rows(твердиня):
		if str(row.get("гілка", "")) != "":
			приховані += 1
	_yes("закритої гілки не видно взагалі", приховані == 0)
	твердиня.opened.append("Серце фортеці")
	твердиня.opened.append("Обітниця каменю")
	var після := 0
	for row: Dictionary in world._guild_rows(твердиня):
		if str(row.get("гілка", "")) != "":
			після += 1
	print("    після відкриття двох гілок видно %d прихованих умінь"
			% після)
	_yes("відкрита гілка з'являється (по три вміння на гілку)",
			після == 6)


func _квест() -> void:
	# П-227, слово замовника 10.10.2026: одна умова — убити 10 вибраних
	# монстрів, лічильник «0|10», завдання видає майстер гільдії.
	print("\n— квест переходу (П-227) —")
	var profs: Professions = _data.professions
	var усі_прості := true
	for key: String in profs.rows:
		var умови: Array = profs.quest_of(key).get("умови", [])
		if умови.size() != 1 or not умови[0].has("вбити") \
				or int(умови[0]["скільки"]) != 10 \
				or str(profs.quest_of(key).get("де", "")) != "майстер гільдії":
			усі_прості = false
	_yes("у всіх 20 — одна умова «убити 10», видає майстер гільдії",
			усі_прості)

	var хто := _хтось("", 20)
	var вид := profs.quest_kind("воїн")
	хто.kills[вид] = 37          # убиті ДО завдання не рахуються
	var чому := profs.why_not(хто, "воїн")
	print("    без завдання: %s" % чому)
	_yes("без завдання професію не дають",
			чому == "спершу візьми завдання в майстра гільдії")
	_yes("зарано за рівнем — завдання не дають",
			profs.take_quest(_хтось("", 10), "воїн") != "")
	_yes("не з тієї професії — завдання не дають",
			profs.take_quest(_хтось("", 60), "твердиня") != "")

	_yes("завдання взято", profs.take_quest(хто, "воїн") == "")
	_yes("удруге не береться", profs.take_quest(хто, "воїн") != "")
	_yes("лічильник з нуля, а не з 37: «%s»" % profs.quest_line(хто),
			profs.quest_line(хто) == "%s 0|10" % вид)
	хто.kills[вид] = 37 + 3
	_yes("три вбиті — «%s»" % profs.quest_line(хто),
			profs.quest_line(хто) == "%s 3|10" % вид)
	print("    на 3|10: %s" % profs.why_not(хто, "воїн"))
	_yes("на 3|10 ще не можна", profs.why_not(хто, "воїн") != "")
	хто.kills[вид] = 37 + 12
	_yes("понад 10 — лічильник стоїть на 10|10",
			profs.quest_line(хто) == "%s 10|10" % вид)
	_yes("професію дано", profs.take(хто, "воїн") == ""
			and хто.profession == "воїн")
	_yes("завдання знято після переходу", хто.quest.is_empty()
			and profs.quest_line(хто) == "")


func _гілки() -> void:
	print("\n— три способи відкрити приховану гілку —")
	var profs: Professions = _data.professions

	var з_амулетом := _хтось("воїн", 36)
	_yes("без амулета гілка закрита",
			profs.open_ready(з_амулетом).is_empty())
	з_амулетом.items["амулет солоної крові"] = 1
	var відкрито: Array = profs.open_ready(з_амулетом)
	print("    амулет відкрив: %s" % [відкрито])
	_yes("амулет відкриває гілку воїна", відкрито == ["Кров і сіль"])
	_yes("удруге не відкривається", profs.open_ready(з_амулетом).is_empty())

	var мисливець := _хтось("стрілець", 36)
	мисливець.kills["вовк"] = 199
	_yes("199 вовків замало", profs.open_ready(мисливець).is_empty())
	мисливець.kills["вовк"] = 200
	var від_полювання: Array = profs.open_ready(мисливець)
	print("    полювання відкрило: %s" % [від_полювання])
	_yes("двохсотий вовк відкриває гілку стрільця",
			від_полювання == ["Мисливські вузли"])

	var чародій := _хтось("чародій", 36)
	_yes("без синтезу гілка чародія закрита",
			profs.open_ready(чародій).is_empty())
	чародій.learned["шепіт-порожнечі"] = 1
	var від_синтезу: Array = profs.open_ready(чародій)
	print("    синтез відкрив: %s" % [від_синтезу])
	_yes("вміння синтезу відкриває гілку",
			від_синтезу == ["Шепіт порожнечі"])


func _синтез() -> void:
	print("\n— синтез навичок —")
	var runes := Runes.new(_data.skills, _data.professions)
	var хто := _хтось("чародій", 36)
	хто.experience = 100000
	var чому := runes.synthesize(хто, "шепіт-порожнечі")
	print("    без батьків: %s" % чому)
	_yes("без обох навичок не зливається", чому != "")
	хто.learned["крижаний-спис"] = 1
	_yes("з однією навичкою теж ні",
			runes.synthesize(хто, "шепіт-порожнечі") != "")
	хто.learned["печать-розуму"] = 1
	_yes("з обома — злито",
			runes.synthesize(хто, "шепіт-порожнечі") == ""
			and хто.knows("шепіт-порожнечі"))
	_yes("батьки лишились при гравцеві",
			хто.knows("крижаний-спис") and хто.knows("печать-розуму"))
	var інший := _хтось("чародій", 36)
	інший.items["руна вміння «шепіт порожнечі»"] = 1
	інший.experience = 100000
	_yes("руною вміння синтезу не вивчити",
			runes.learn(інший, "шепіт-порожнечі") != "")
	var не_свій := _хтось("воїн", 75)
	не_свій.experience = 100000
	не_свій.learned["крижаний-спис"] = 1
	не_свій.learned["печать-розуму"] = 1
	_yes("чужу професію не синтезувати",
			runes.synthesize(не_свій, "шепіт-порожнечі") != "")


func _руни() -> void:
	print("\n— чим вивчати —")
	var без_руни: Array = []
	var руни := {}
	for key: String in _data.skills.keys():
		var s: Skill = _data.skills.get_skill(key)
		if s.profession == "" or s.source == "синтез":
			continue
		if s.rune == "":
			без_руни.append(key)
		else:
			руни[s.rune] = true
	_yes("у кожного вміння професії є руна вивчення", без_руни.is_empty())

	var падає := {}
	for kind: String in _data.mobs:
		for row: Dictionary in _data.mobs[kind].get("дроп", []):
			падає[str(row.get("що", ""))] = true
	var нізвідки: Array = []
	for rune: String in руни:
		if not падає.has(rune):
			нізвідки.append(rune)
	print("    рун професій %d, з них падають %d"
			% [руни.size(), руни.size() - нізвідки.size()])
	if not нізвідки.is_empty():
		print("    ‼ нізвідки: %s" % [нізвідки.slice(0, 5)])
	_yes("кожна руна звідкись падає", нізвідки.is_empty())

	var амулети: Array = []
	for key: String in _data.professions.rows:
		var how: Dictionary = _data.professions.branch_of(key).get(
				"відкриття", {})
		if str(how.get("як", "")) == "амулет" \
				and not падає.has(str(how.get("річ", ""))):
			амулети.append(str(how.get("річ", "")))
	_yes("кожен амулет прихованої гілки звідкись падає",
			амулети.is_empty())
