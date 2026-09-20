extends Node
## Дерево скілів для всіх рас і статей (П-221, слово замовника
## 20.09.2026: «згенерувати дерево скілів та вмінь для всіх рас та полу»).
##
## Перевіряємо числами, а не оком: чи бачить кожна раса СВОЮ гілку й не
## бачить чужої, чи різняться чоловіча й жіноча гілки, чи в кожного
## скіла є чим його вивчити і чи ця руна взагалі звідкись падає.
##
##     godot --headless --path game res://scenes/tree.tscn

const WORLD := preload("res://scripts/world.gd")

var _ok := 0
var _bad := 0


class Хтось extends Node:
	var race := "людина"
	var sex := "чоловік"
	var learned := {}

	func knows(_key: String) -> bool:
		return false


func _ready() -> void:
	_go()


func _yes(text: String, is_ok: bool) -> void:
	_ok += 1 if is_ok else 0
	_bad += 0 if is_ok else 1
	print("  %s %s" % ["✓" if is_ok else "✗", text])


func _go() -> void:
	await get_tree().process_frame
	_tree()
	_runes()
	print("  підсумок: %s" % ("усе гаразд" if _bad == 0
			else "‼ вад: %d" % _bad))
	get_tree().quit(1 if _bad > 0 else 0)


func _rows(world: Node, race: String, sex: String) -> Array:
	var хто := Хтось.new()
	хто.race = race
	хто.sex = sex
	add_child(хто)
	var out: Array = world._guild_rows(хто)
	хто.queue_free()
	return out


func _tree() -> void:
	print("\n— що бачить кожен —")
	var world: Node = WORLD.new()
	world.data = GameData.new()
	world.data.load_all()
	var усі := {}
	for race: String in ["людина", "ельф", "орк"]:
		for sex: String in ["чоловік", "жінка"]:
			var rows := _rows(world, race, sex)
			var tabs := {}
			for row: Dictionary in rows:
				tabs[str(row["вкладка"])] = true
			усі["%s-%s" % [race, sex]] = rows
			print("    %-8s %-8s скілів %2d, вкладок %d: %s"
					% [race, sex, rows.size(), tabs.size(),
					   ", ".join(PackedStringArray(tabs.keys()))])

	var спадки := {"людина": "Спадок людей", "ельф": "Спадок ельфів",
			"орк": "Спадок орків"}
	var чисто := true
	for race: String in спадки:
		for sex: String in ["чоловік", "жінка"]:
			var свій := false
			var чужий := false
			for row: Dictionary in усі["%s-%s" % [race, sex]]:
				var tab := str(row["вкладка"])
				if tab == спадки[race]:
					свій = true
				elif tab.begins_with("Спадок"):
					чужий = true
			if not свій or чужий:
				чисто = false
				print("    ‼ %s-%s: свій %s, чужий %s"
						% [race, sex, свій, чужий])
	_yes("кожна раса бачить свою гілку й не бачить чужої", чисто)

	# Чоловік і жінка мають різнитись рівно на два скіли (по одному
	# своєму в кожній расі): менше — стать ні на що не впливає, більше —
	# гілки розійшлись сильніше, ніж замовляли.
	var різне := true
	for race: String in спадки:
		var ч := {}
		var ж := {}
		for row: Dictionary in усі["%s-чоловік" % race]:
			ч[str(row["ключ"])] = true
		for row: Dictionary in усі["%s-жінка" % race]:
			ж[str(row["ключ"])] = true
		var лише_ч: Array = ч.keys().filter(
				func(k: String) -> bool: return not ж.has(k))
		var лише_ж: Array = ж.keys().filter(
				func(k: String) -> bool: return not ч.has(k))
		print("    %-8s лише чоловіче: %s · лише жіноче: %s"
				% [race, лише_ч, лише_ж])
		if лише_ч.size() != 1 or лише_ж.size() != 1:
			різне = false
	_yes("у кожної раси рівно один свій скіл чоловікові й один жінці",
			різне)

	# Дерево має бути зв'язним: передумова, якщо вона є, мусить бути в
	# тому самому переліку, інакше гілку не розкрити ніколи.
	var сироти: Array = []
	for who: String in усі:
		var ключі := {}
		for row: Dictionary in усі[who]:
			ключі[str(row["ключ"])] = true
		for row: Dictionary in усі[who]:
			var треба := str(row["передумова"])
			if треба != "" and not ключі.has(треба):
				сироти.append("%s: %s ← %s" % [who, row["ключ"], треба])
	if not сироти.is_empty():
		print("    ‼ %s" % " · ".join(PackedStringArray(сироти)))
	_yes("у кожного скіла його передумова доступна тому самому гравцеві",
			сироти.is_empty())
	world.free()


func _runes() -> void:
	print("\n— чим вивчати —")
	var data := GameData.new()
	data.load_all()
	var без_руни: Array = []
	var руна_нізвідки: Array = []
	# Стартові скіли дають задарма (`bar.json → стартові скіли`), руни
	# їм не потрібні — інакше проба вимагала б руну на те, що й так є.
	var стартові: Dictionary = data.starting_skills
	for key: String in data.skills.keys():
		var skill: Skill = data.skills.get_skill(key)
		if skill.category == "" or стартові.has(key):
			continue
		if skill.rune == "":
			без_руни.append(key)
			continue
		if not data.items.has(skill.rune):
			руна_нізвідки.append(skill.rune)
			continue
		var падає := false
		for kind: String in data.mobs:
			if kind == "_про":
				continue
			for drop: Dictionary in data.mobs[kind].get("дроп", []):
				if str(drop.get("що", "")) == skill.rune:
					падає = true
		if not падає:
			руна_нізвідки.append(skill.rune)
	if not без_руни.is_empty():
		print("    ‼ без руни: %s" % " ".join(PackedStringArray(без_руни)))
	if not руна_нізвідки.is_empty():
		print("    ‼ руна нізвідки: %s"
				% " ".join(PackedStringArray(руна_нізвідки)))
	_yes("у кожного скіла дерева є руна вивчення", без_руни.is_empty())
	_yes("кожна така руна звідкись падає", руна_нізвідки.is_empty())
