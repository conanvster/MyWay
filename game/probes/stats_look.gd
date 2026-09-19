extends Node
## Вікно «Стати» з бафами (замовник 19.09.2026: «не бачу в статах, на що
## повпливав баф»): чинне число, а в дужках власне — і для похідних
## (атака, захист, швидкість), які бафи священика множать, не чіпаючи
## статів. Без світу й мережі — порт 24565 може бути гри замовника.
##
##     godot --path game res://scenes/stats_look.tscn -- --знімок <файл.png>

const WORLD := preload("res://scripts/world.gd")

var _ok := 0
var _bad := 0


class Dummy extends Node:
	var race := "людина"
	var sex := "чоловік"
	var level := 6
	var stat_points := 0
	var base_stats := Stats.new()
	var stats := Stats.new()
	var states := States.new()


func _ready() -> void:
	_go()


func _yes(text: String, is_ok: bool) -> void:
	_ok += 1 if is_ok else 0
	_bad += 0 if is_ok else 1
	print("  %s %s" % ["✓" if is_ok else "✗", text])


func _go() -> void:
	await get_tree().process_frame
	var me := Dummy.new()
	add_child(me)
	me.base_stats.strength = 10
	me.base_stats.stamina = 10
	# Бафи священика й клич хоробрості — як у data/.
	for one: Array in [["благословення сили", "physical_attack", 1.15],
			["благословення захисту", "physical_defence", 1.15],
			["благословення швидкості", "move_speed", 1.2]]:
		me.states.apply(State.new(one[0], one[1], one[2], 1200.0))
	me.states.apply(State.new("клич хоробрості", "strength", 1.2, 15.0))
	me.stats = me.states.applied_to(me.base_stats)
	var world: Node = WORLD.new()
	var row: Dictionary = world._stats_row(me)
	world.free()
	print("  рядок: %s" % [row])
	_yes("атака з бафом більша за власну (%.1f > %.1f)"
			% [row["атака"], row["атака базова"]],
			row["атака"] > row["атака базова"])
	_yes("захист з бафом більший (%.1f > %.1f)"
			% [row["захист"], row["захист базова"]],
			row["захист"] > row["захист базова"])
	_yes("швидкість є і з бафом більша (%.1f > %.1f)"
			% [row["швидкість"], row["швидкість базова"]],
			row["швидкість"] > row["швидкість базова"])
	_yes("сила з кличем 12 при власних 10", row["сила"] == 12)

	get_window().size = Vector2i(1280, 720)
	var back := ColorRect.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.color = Color(0.24, 0.31, 0.22)
	get_tree().root.add_child(back)
	var hud := HUD.new()
	get_tree().root.add_child(hud)
	hud.setup(get_tree().root)
	await get_tree().process_frame
	hud._stats_box.toggle()
	hud.set_stats(row)
	await get_tree().process_frame
	var label: Label = hud._stats_fields["фіз. атака"]
	_yes("у вікні атака з дужками: «%s»" % label.text, "(" in label.text)
	_yes("у вікні є швидкість: «%s»" % hud._stats_fields["швидкість"].text,
			"(" in hud._stats_fields["швидкість"].text)
	for f in 20:
		await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var at := args.find("--знімок")
	if at >= 0 and at + 1 < args.size() \
			and DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_png(args[at + 1])
		print("[знімок] %s" % args[at + 1])
	print("\n  пройдено %d · провалено %d" % [_ok, _bad])
	get_tree().quit(1 if _bad > 0 else 0)
