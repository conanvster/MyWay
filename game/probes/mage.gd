extends Node
## Майстер магії (слово замовника 20.09.2026: «в містах додай мастера
## магії у якого можна попросити телепортуватися в інше місто»).
##
## Перевіряємо числами, а не «начебто працює»: чи стоїть майстер у
## КОЖНОМУ місті, чи рахує сервер ціну сам, чи не пропонує перенести
## туди, де ти вже стоїш, і чи відмовляє, коли грошей менше за ціну.
##
##     godot --headless --path game res://scenes/mage.tscn
##
## Сценою, а не `--script`: HUD тягне `client_view.gd`, а той — Net.

const WORLD := preload("res://scripts/world.gd")

var _ok := 0
var _bad := 0


func _ready() -> void:
	_go()


func _yes(text: String, is_ok: bool) -> void:
	_ok += 1 if is_ok else 0
	_bad += 0 if is_ok else 1
	print("  %s %s" % ["✓" if is_ok else "✗", text])


class Стоїть extends Node3D:
	var items := {"гроші": 0}
	var level := 10

	func is_alive() -> bool:
		return true


func _go() -> void:
	await get_tree().process_frame
	_in_data()
	_prices()
	await _window()
	print("  підсумок: %s" % ("усе гаразд" if _bad == 0
			else "‼ вад: %d" % _bad))
	get_tree().quit(1 if _bad > 0 else 0)


func _in_data() -> void:
	print("\n— майстер у містах —")
	var data := GameData.new()
	data.load_all()
	var без: Array = []
	for town: Dictionary in data.map.get("міста", []):
		var має := false
		for who: Dictionary in town.get("мешканці", []):
			if str(who.get("ремесло", "")) == NPC.MAGE:
				має = true
		if not має:
			без.append(str(town.get("назва", "?")))
	print("    міст: %d, без майстра: %s" % [data.map["міста"].size(),
			"немає" if без.is_empty() else ", ".join(PackedStringArray(без))])
	_yes("майстер стоїть у кожному місті", без.is_empty())

	var npc := NPC.new()
	npc.craft = NPC.MAGE
	_yes("NPC із цим ремеслом переносить", npc.ports())
	npc.craft = NPC.PRIEST
	_yes("священик — ні", not npc.ports())
	npc.free()

	var raw := FileAccess.get_file_as_string("res://data/teleports.json")
	var rules: Variant = JSON.parse_string(raw)
	_yes("ціни лежать у data/teleports.json", rules is Dictionary)


func _prices() -> void:
	print("\n— ціни рахує сервер —")
	var world: Node = WORLD.new()
	world.data = GameData.new()
	world.data.load_all()
	var стоїть := Стоїть.new()
	add_child(стоїть)
	# Столиця — (0,0): звідти й питаємо.
	стоїть.global_position = Vector3.ZERO
	var rules := {"ціна за км": 250.0, "найменша ціна": 300}
	var towns: Array = world._towns_for(стоїть, rules)
	for one: Dictionary in towns:
		print("    %-18s %5.0f м → %d" % [one["назва"], one["далеко"],
				one["ціна"]])
	var назви: Array = []
	for one: Dictionary in towns:
		назви.append(str(one["назва"]))
	_yes("того міста, де стоїш, у переліку немає",
			not назви.has("Стільна"))
	_yes("решта міст у переліку є",
			towns.size() == world.data.map["міста"].size() - 1)
	var дешеве := 99999
	for one: Dictionary in towns:
		дешеве = mini(дешеве, int(one["ціна"]))
	_yes("ціна не падає нижче за найменшу (%d ≥ 300)" % дешеве,
			дешеве >= 300)
	var далеке: Dictionary = towns[0]
	for one: Dictionary in towns:
		if float(one["далеко"]) > float(далеке["далеко"]):
			далеке = one
	_yes("далі — дорожче (%s, %.1f км, %d)"
			% [далеке["назва"], float(далеке["далеко"]) / 1000.0,
			   int(далеке["ціна"])],
			int(далеке["ціна"])
			== maxi(300, int(round(float(далеке["далеко"]) / 1000.0
					* 250.0))))
	стоїть.queue_free()
	world.free()


func _window() -> void:
	print("\n— вікно «Куди перенести» —")
	var hud := HUD.new()
	add_child(hud)
	hud.setup(self)
	await get_tree().process_frame

	var просив: Array = []
	hud.wants_port.connect(func(at: int, town: String) -> void:
			просив.append([at, town]))

	hud.show_talk(3, "Ліда, майстер магії", false, false, false, false,
			true)
	await get_tree().process_frame
	_yes("у розмові є кнопка переносу", hud._talk_mage.visible)

	hud.show_ports(3, "Ліда, майстер магії", [
			{"назва": "Крайня Брама", "далеко": 1101.0, "ціна": 300},
			{"назва": "Попелище", "далеко": 2586.0, "ціна": 647}], 500)
	await get_tree().process_frame
	_yes("вікно відкрилось", hud._ports_box.visible)
	var живі: Array = []
	for press: Button in hud._ports_rows:
		if press.visible:
			живі.append(press)
	print("    рядки: %s" % [живі.map(
			func(b: Button) -> String: return b.text)])
	_yes("рядків стільки, скільки міст", живі.size() == 2)
	_yes("на що вистачає — натиснути можна", not живі[0].disabled)
	# 500 монет проти 647: ціну видно, але кнопка мертва — ховати місто
	# означало б брехати, що туди не носять.
	_yes("на що не вистачає — видно, але не натиснути", живі[1].disabled)

	живі[0].pressed.emit()
	await get_tree().process_frame
	print("    попросив: %s" % [просив])
	_yes("натиск назвав саме це місто",
			просив.size() == 1 and просив[0][1] == "Крайня Брама")
	_yes("вікно закрилось після вибору", not hud._ports_box.visible)
	hud.queue_free()
