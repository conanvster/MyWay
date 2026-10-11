extends Node
## Проба вікна «Кування» (П-258).
##
## Ганяти сценою — HUD чіпає автозавантаження `Net`:
##     godot --path game res://scenes/forge_window.tscn
##     godot --headless --path game res://scenes/forge_window.tscn
##
## Без сервера: рецепти подаються руками, а що вікно ПРОСИТЬ, ловиться з
## його сигналів. З вікном — ще й знімок. Наприкінці «помилок: N».

var _hud: Node
var _bad := 0
var _asked: Array = []


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
	var root := get_tree().root
	var back := ColorRect.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.color = Color(0.24, 0.31, 0.22)
	root.add_child(back)
	_hud = HUD.new()
	root.add_child(_hud)
	_hud.setup(root)
	await get_tree().process_frame
	_hud.wants_forge.connect(func(at: int) -> void:
			_asked.append(["кування", at]))
	_hud.wants_craft.connect(func(at: int, base: String) -> void:
			_asked.append(["скувати", at, base]))

	print("\n— розмова з ковалем —")
	_hud.show_talk(7, "Горан, коваль", false, false, false, false, false,
			false, true)
	_expect("кнопка «Кування» є", _hud._talk_forge.visible, true)
	_hud._talk_forge.pressed.emit()
	_expect("просить вікно в коваля 7", _asked.back(), ["кування", 7])
	_hud.show_talk(8, "Ліда, крамарка", true)
	_expect("у крамарки — немає", _hud._talk_forge.visible, false)

	print("\n— вікно —")
	var rows := [
		{"назва": "меч з кори дуба", "грейд": "E", "вид": "зброя",
			"слот": "зброя", "стати": {"сила": 2}, "ціна": 120,
			"речі": {"кора дуба": 10}},
		{"назва": "куртка з кори дуба", "грейд": "E", "вид": "обладунок",
			"слот": "тіло", "стати": {"витривалість": 2}, "ціна": 115,
			"речі": {"кора дуба": 10}},
		{"назва": "кістяна сокира", "грейд": "B", "вид": "зброя",
			"слот": "зброя", "стати": {"сила": 9}, "ціна": 3105,
			"речі": {"мітрил": 10}},
	]
	_hud.show_forge(7, "Горан, коваль", rows, {"кора дуба": 12, "мітрил": 4})
	await get_tree().process_frame
	_expect("вікно видно", _hud._forge_box.visible, true)
	_expect("спершу грейд E: рядків", _lines().size(), 2)
	var first: Array = _lines()[0]
	_expect("кори досить — «Скувати»", [first[1], first[2]],
			["кора дуба 12/10", "Скувати"])
	_button(0).pressed.emit()
	_expect("просить скувати меч у коваля 7", _asked.back(),
			["скувати", 7, "меч з кори дуба"])
	Shot.take(root)
	await get_tree().create_timer(1.2).timeout

	_tab("B").pressed.emit()
	await get_tree().process_frame
	_expect("вкладка B: рядків", _lines().size(), 1)
	_expect("мітрилу мало — «Бракує» й вимкнено",
			[_lines()[0][1], _lines()[0][2], _button(0).disabled],
			["мітрил 4/10", "Бракує", true])
	_tab("SS").pressed.emit()
	await get_tree().process_frame
	_expect("вкладка SS порожня", _lines().size(), 0)
	_expect("натиснута лише одна вкладка", _pressed_tabs(), ["SS"])

	print("\nпомилок: %d" % _bad)
	get_tree().quit()


## Рядки вікна: [опис, матеріали, текст кнопки]. Ті, що вже звільняються
## (`queue_free` від попереднього показу), не рахуються.
func _lines() -> Array:
	var out: Array = []
	for line: Node in _hud._forge_list.get_children():
		if line.is_queued_for_deletion():
			continue
		out.append([line.get_child(0).text, line.get_child(1).text,
				line.get_child(2).text])
	return out


func _button(i: int) -> Button:
	var alive: Array = _hud._forge_list.get_children().filter(
			func(n: Node) -> bool: return not n.is_queued_for_deletion())
	return alive[i].get_child(2)


func _tab(grade: String) -> Button:
	return _hud._forge_tabs.get_node("Грейд" + grade)


func _pressed_tabs() -> Array:
	var out: Array = []
	for tab: Button in _hud._forge_tabs.get_children():
		if tab.button_pressed:
			out.append(tab.text)
	return out
