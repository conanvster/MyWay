extends Node
## Проба показу завдання переходу (П-227): кнопка в майстра гільдії й
## лічильник «вовкулака 3|10» на екрані.
##
##     godot --headless --path game res://scenes/quest_hud.tscn

var _bad := 0


func _ready() -> void:
	_go()


func _expect(what: String, got: Variant, want: Variant) -> void:
	var ok: bool = got == want
	if not ok:
		_bad += 1
	print("  %s %s: %s%s" % ["✓" if ok else "✗", what, str(got),
			"" if ok else " (чекали %s)" % str(want)])


func _go() -> void:
	await get_tree().process_frame
	var hud := HUD.new()
	get_tree().root.add_child(hud)
	hud.setup(get_tree().root)
	await get_tree().process_frame
	var asked: Array = []
	hud.wants_take_quest.connect(func(at: int, key: String) -> void:
			asked.append(["завдання", at, key]))
	hud.wants_take_profession.connect(func(at: int, key: String) -> void:
			asked.append(["професія", at, key]))

	print("\n— лічильник на екрані —")
	hud.set_stats({})
	_expect("без завдання рядка немає", hud._quest_box.visible, false)
	hud.set_stats({"завдання": "вовкулака 3|10"})
	_expect("із завданням видно", hud._quest_box.visible, true)
	_expect("текст", hud._quest_text.text, "завдання: вовкулака 3|10")

	print("\n— кнопка в майстра гільдії —")
	var row := {"ключ": "воїн", "назва": "Воїн", "квест": "Перша кров",
			"де": "майстер гільдії", "умови": [{"що": "убити вовкулака",
			"зроблено": 0, "треба": 10, "готово": false, "взято": false}],
			"можна": false, "взято": false, "можна взяти": true}
	hud._show_profession(row)
	_expect("не взято — «Взяти завдання»", hud._guild_detail_press.text,
			"Взяти завдання")
	_expect("показ «0|10 (ще не взято)»",
			hud._guild_detail_info.text.contains("0|10  (ще не взято)"), true)
	hud._guild_detail_press.pressed.emit()
	_expect("тисне — просить завдання", asked.back(), ["завдання", -1, "воїн"])
	row["взято"] = true
	row["умови"][0]["взято"] = true
	row["умови"][0]["зроблено"] = 3
	hud._show_profession(row)
	_expect("узято, 3|10 — «ще ні»", [hud._guild_detail_press.text,
			hud._guild_detail_press.disabled], ["ще ні", true])
	row["можна"] = true
	hud._show_profession(row)
	_expect("виконано — «Стати: Воїн»", hud._guild_detail_press.text,
			"Стати: Воїн")
	hud._guild_detail_press.pressed.emit()
	_expect("тисне — просить професію", asked.back(), ["професія", -1, "воїн"])
	print("\nпомилок: %d" % _bad)
	get_tree().quit()
