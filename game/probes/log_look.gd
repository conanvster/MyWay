extends Node
## В-8: «Лог» налазить на панель скілів у вікні 1280×720 (масштаб ×1,5 —
## це 853 точки завширшки). Знімок кожної з трьох розкладок на вибір
## замовника. Без світу й мережі.
##
##     godot --path game res://scenes/log_look.tscn -- \
##         --варіант А --знімок <файл.png>
##
## Варіант порожній — як зараз у грі. `--смуги 2` — дві смуги панелі.


func _ready() -> void:
	call_deferred("_go")


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	var variant := ""
	var at := args.find("--варіант")
	if at >= 0 and at + 1 < args.size():
		variant = args[at + 1]
	var strips := 1
	at = args.find("--смуги")
	if at >= 0 and at + 1 < args.size():
		strips = int(args[at + 1])
	get_window().size = Vector2i(1280, 720)
	var back := ColorRect.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.color = Color(0.24, 0.31, 0.22)
	get_tree().root.add_child(back)
	var hud := HUD.new()
	get_tree().root.add_child(hud)
	hud.setup(get_tree().root)
	hud.set_bar(["attack", "next_mob", "скіл:енергетичний-промінь",
			"скіл:енергетичний-вибух", "taunt", "next_player",
			"скіл:повернення-в-місто"], strips)
	for f in 3:
		await get_tree().process_frame
	if variant != "":
		hud.place_log(variant)
	for line: String in [
			"[бій] Мандрівник б'є вовка: 14 шкоди",
			"[скіл] енергетичний-промінь: вовк −32",
			"[бій] вовк б'є Мандрівника: 6 шкоди",
			"[смерть] вовк загинув",
			"[дроп] шкура вовка ×1",
			"[бій] Мандрівник б'є зайця: 12 шкоди",
			"[скіл] енергетичний-вибух: заєць −41, вовк −38",
			"[смерть] заєць загинув"]:
		hud.log_line(line)
	hud.notice("повага +12")
	hud.notice("шкура вовка ×1 — у торбі")
	for f in 20:
		await get_tree().process_frame
	var box: Control = hud._log_box
	var panel: Control = hud._cells[0]["cell"].get_parent()
	var log_rect := box.get_global_rect()
	var cell0: Rect2 = (hud._cells[0]["cell"] as Control).get_global_rect()
	print("[лог] варіант «%s»: лог %s, перша комірка %s, перетин %s"
			% [variant, log_rect, cell0, log_rect.intersects(cell0)])
	at = args.find("--знімок")
	if at >= 0 and at + 1 < args.size():
		get_viewport().get_texture().get_image().save_png(args[at + 1])
		print("[знімок] %s" % args[at + 1])
	get_tree().quit(0)
