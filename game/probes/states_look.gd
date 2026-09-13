extends Node
## Бафи й дебафи в HUD (замовник 13.09.2026: «хочу бачити, на кого я
## наклав баф; якщо на себе — трохи нижче черги, якщо на монстрах — під
## іменем монстра з кількістю хп») — числами й знімком.
##
## Без світу й мережі навмисно: `main.tscn` стукає на 127.0.0.1, а там
## може саме йти гра замовника.
##
##     godot --path game res://scenes/states_look.tscn -- --знімок <файл.png>

const WORLD := preload("res://scripts/world.gd")

var _ok := 0
var _bad := 0


## Істота-заглушка: рядку станів потрібні лише самі стани.
class Dummy extends Node:
	var states := States.new()


func _ready() -> void:
	_go()


func _yes(text: String, is_ok: bool) -> void:
	if is_ok:
		_ok += 1
		print("  ✓ %s" % text)
	else:
		_bad += 1
		print("  ✗ %s" % text)


func _named(row: Array, title: String) -> Array:
	for one: Array in row:
		if one[0] == title:
			return one
	return []


func _go() -> void:
	await get_tree().process_frame
	print("\n— стани: що шле сервер —")
	var me := Dummy.new()
	add_child(me)
	me.states.apply(State.new("стійка щита", "stamina", 1.15, 20.0))
	me.states.apply(State.from_data({"назва": "вовча вдача",
			"стат": "stamina", "множник": 1.15, "строк": 0.0}))
	me.states.apply(State.new("павутина", "agility", 0.7, 6.4))
	var row: Array = WORLD.states_row(me)
	print("  рядок: %s" % [row])
	_yes("усі три стани в рядку", row.size() == 3)
	_yes("вічний баф монстра — «-1» секунд",
			int(_named(row, "вовча вдача")[3]) == -1)
	_yes("секунди вгору: 6,4 показується як 7",
			int(_named(row, "павутина")[3]) == 7)
	_yes("порядок сталий, за назвою (%s)" % row[0][0],
			row[0][0] == "вовча вдача")

	print("\n— стани: що малює HUD —")
	var root := get_tree().root
	get_window().size = Vector2i(1280, 720)
	var back := ColorRect.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.color = Color(0.24, 0.31, 0.22)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(back)
	var hud := HUD.new()
	root.add_child(hud)
	hud.setup(root)
	await get_tree().process_frame
	hud.update_self(140, 180, 40, 90, PackedFloat32Array(), 0.0, [])

	# Ціль без світу: рамку заповнюємо самі, `set_target` питав би світ.
	hud._target = -7
	hud._target_box.visible = true
	hud._target_name.text = "вовк"
	hud._target_fill.size.x = HUD.WIDE * 0.6
	var theirs := [["вовча вдача", "stamina", 1.15, -1, -1],
			["павутина", "agility", 0.7, 4, 8]]

	hud.set_states(row, -99, theirs)
	_yes("стани ЧУЖОЇ цілі не показуються (%d)"
			% hud._target_states.get_child_count(),
			hud._target_states.get_child_count() == 0)
	hud.set_states(row, -7, theirs)
	await get_tree().process_frame
	_yes("мої стани під чергою: %d комірки" % hud._my_states.get_child_count(),
			hud._my_states.get_child_count() == 3)
	_yes("стани цілі під її смугою: %d" % hud._target_states.get_child_count(),
			hud._target_states.get_child_count() == 2)
	var first: Control = hud._target_states.get_child(1)
	_yes("підказка під мишею: «%s»" % first.tooltip_text.replace("\n", " · "),
			first.tooltip_text.begins_with("павутина"))

	for f in 20:
		await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var at := args.find("--знімок")
	if at >= 0 and at + 1 < args.size() \
			and DisplayServer.get_name() != "headless":
		var err := get_viewport().get_texture().get_image() \
				.save_png(args[at + 1])
		print("[знімок] %s%s" % [args[at + 1], "" if err == OK
				else " ‼ " + error_string(err)])
	print("\n  пройдено %d · провалено %d" % [_ok, _bad])
	get_tree().quit(1 if _bad > 0 else 0)
