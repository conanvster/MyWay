extends Node
## Проба В-1: на комірці панелі видно, скільки витратного лишилось.
##
## Ганяти так:
##     godot --headless --path game res://scenes/bar_counts.tscn
##
## Сервер рахував зілля правильно й раніше (проба `potion`); вада була в
## показі — панель кількості не малювала. Тут подаємо торбу, як подає
## сервер після кожного ковтка, і дивимось на число в комірці.

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
	var potion := Actions.ITEM_PREFIX + "зілля лікування"
	hud.set_things([], [{"назва": "зілля лікування", "скільки": 3}])
	hud.set_bar(["attack", potion, "", "", "", "", ""], 1)
	print("\n— зілля на панелі (В-1) —")
	_expect("комірка 2 показує 3", hud._cells[1]["count"].text, "3")
	_expect("на ударі числа немає", hud._cells[0]["count"].text, "")
	for left: int in [2, 1]:
		hud.set_things([], [{"назва": "зілля лікування", "скільки": left}])
		_expect("після ковтка — %d" % left, hud._cells[1]["count"].text,
				str(left))
	hud.set_things([], [])
	_expect("скінчилось — 0", hud._cells[1]["count"].text, "0")
	_expect("значок притемнено", hud._cells[1]["icon"].modulate.a < 0.5, true)
	hud.set_things([], [{"назва": "зілля лікування", "скільки": 5}])
	_expect("купив ще — 5 і значок яскравий",
			[hud._cells[1]["count"].text, hud._cells[1]["icon"].modulate.a],
			["5", 1.0])
	print("\nпомилок: %d" % _bad)
	get_tree().quit()
