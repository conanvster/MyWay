extends Node
## Показ поверх світу: розкладка на різних розмірах вікна, вікно
## «Налаштування» і рухливі блоки (27.11.2026). Без світу й мережі, і
## без `user://settings.cfg` — `GameSettings.active` тут не вмикається.
##
##     godot --path game res://scenes/hud_look.tscn -- \
##         [--розмір 1728x972] [--масштаб 1.5] [--смуги 2] \
##         [--налаштування] [--рух] [--знімок <файл.png>]
##
## `--налаштування` — відкрити вікно налаштувань.
## `--рух` — самоперевірка: тягне панель ручкою, згортає «Здоров'я»,
## перевіряє, що вийшло, і повертає все кнопкою «як спершу». Знімок —
## у мить, коли панель відсунуто, а «Здоров'я» згорнуто.
## Друкує, чи «Лог» лежить на першій комірці панелі; код виходу 1 —
## якщо котрась перевірка не пройшла.

var _bad := 0


func _ready() -> void:
	call_deferred("_go")


func _arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	var at := args.find(name)
	return args[at + 1] if at >= 0 and at + 1 < args.size() else fallback


func _check(ok: bool, what: String) -> void:
	print("  %s %s" % ["✓" if ok else "✗", what])
	if not ok:
		_bad += 1


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	var wanted := _arg("--розмір", "1280x720").split("x")
	get_window().size = Vector2i(int(wanted[0]), int(wanted[1]))
	get_window().content_scale_factor = float(_arg("--масштаб", "1.5"))
	var back := ColorRect.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.color = Color(0.24, 0.31, 0.22)
	get_tree().root.add_child(back)
	# Як у грі (`world.gd`): збирається ще поза деревом, тоді в дерево.
	var hud := HUD.new()
	hud.setup(get_tree().root)
	get_tree().root.add_child(hud)
	hud.set_bar(["attack", "next_mob", "скіл:енергетичний-промінь",
			"скіл:енергетичний-вибух", "taunt", "next_player",
			"скіл:повернення-в-місто"], int(_arg("--смуги", "1")))
	for line: String in [
			"[бій] Мандрівник б'є вовка: 14 шкоди",
			"[скіл] енергетичний-промінь: вовк −32",
			"[смерть] вовк загинув",
			"[дроп] шкура вовка ×1",
			"[скіл] енергетичний-вибух: заєць −41, вовк −38"]:
		hud.log_line(line)
	hud.notice("повага +12")
	for f in 10:
		await get_tree().process_frame

	var view := get_viewport().get_visible_rect().size
	var log_rect: Rect2 = hud._log_box.get_global_rect()
	var cell0: Rect2 = (hud._cells[0]["cell"] as Control).get_global_rect()
	print("[показ] вікно %s, масштаб %s → %d×%d точок; лог на панелі: %s; " \
			% [get_window().size, get_window().content_scale_factor,
			   view.x, view.y, log_rect.intersects(cell0)]
			+ "меню на панелі: %s" % _menu_on_panel(hud))

	if args.has("--налаштування"):
		hud._toggle_settings()
		await get_tree().process_frame
		_check(hud._settings_box.visible, "вікно «Налаштування» відкрилось")

	var shot := _arg("--знімок", "")
	if args.has("--рух"):
		await _move(hud)
	if shot != "":
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(shot)
		print("[знімок] %s" % shot)
	if args.has("--рух"):
		hud._reset_layout()
		await get_tree().process_frame
		var again: Rect2 = (hud._cells[0]["cell"] as Control).get_global_rect()
		_check(again.position.is_equal_approx(cell0.position),
				"«як спершу»: панель на рідному місці %s" % again.position)
		_check(hud._vitals_box.is_visible_in_tree(), "«Здоров'я» розгорнуто")
	get_tree().quit(1 if _bad > 0 else 0)


## Тягнемо панель так, як тягнула б миша: натиск на ручку, рух, відпуск.
func _move(hud: HUD) -> void:
	var layout: HudLayout = hud._layout
	var panel := layout.block_named("панель")
	var cell: Control = hud._cells[0]["cell"]
	var was := cell.get_global_rect().position
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	layout._on_grip_input(panel, press)
	var step := InputEventMouseMotion.new()
	step.relative = Vector2(180, -120)
	layout._on_grip_input(panel, step)
	var free := press.duplicate()
	free.pressed = false
	layout._on_grip_input(panel, free)
	await get_tree().process_frame
	var now := cell.get_global_rect().position
	_check(now.is_equal_approx(was + Vector2(180, -120)),
			"панель пересунуто: %s → %s" % [was, now])
	var cast_from: float = hud._cast_box.offset_top
	hud.set_bar(hud._bar, 2)
	_check(is_equal_approx(hud._cast_box.offset_top, cast_from - 62.0),
			"смуга читання й далі росте з панеллю")

	var vitals := layout.block_named("здоров'я")
	layout.set_folded(vitals, true)
	await get_tree().process_frame
	_check(not hud._vitals_box.is_visible_in_tree(), "«Здоров'я» згорнуто")
	_check((vitals.grip as Control).visible,
			"на його місці смужка «+ Здоров'я»")
	# Ручку панелі видно, як коли миша над нею, — для знімка.
	panel.rect = layout._bounds(panel)
	(panel.grip as Control).visible = true
	layout._place_grip(panel)
	hud.notice("панель відсунуто, «Здоров'я» згорнуто")


func _menu_on_panel(hud: HUD) -> bool:
	for press: Control in hud._menu_box.get_children():
		for i in 7:
			if press.get_global_rect().intersects(
					(hud._cells[i]["cell"] as Control).get_global_rect()):
				return true
	return false
