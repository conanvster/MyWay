extends Node
## Проба вікна «Лог» (слово замовника 11.10.2026).
##
## Ганяти сценою — HUD чіпає автозавантаження `Net`:
##     godot --path game res://scenes/log_window.tscn
##
## Лише з вікном: без нього екран у Godot крихітний (≈42 точки заввишки),
## і `_keep_on_screen` законно затискає вікно — перевірки місця брешуть.
##
## Без сервера: рядки подаються руками, як їх шле `Messenger.report`.
## Перевіряє місце, згортання, перетягування, межу рядків і заміну
## номерів іменами. З вікном — ще й знімок. Наприкінці «помилок: N».

var _hud: Node
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
	var root := get_tree().root
	var back := ColorRect.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.color = Color(0.24, 0.31, 0.22)
	root.add_child(back)
	_hud = HUD.new()
	root.add_child(_hud)
	_hud.setup(root)
	await get_tree().process_frame
	var box: WindowBox = _hud._log_box
	var screen: Vector2 = root.get_visible_rect().size

	print("\n— місце —")
	_expect("видно одразу", box.visible, true)
	_expect("лівий нижній кут", [box.global_position.x,
			box.global_position.y + box.size.y], [12.0, screen.y - 12.0])
	_expect("хрестика нема", box._shut.visible, false)

	print("\n— імена замість номерів —")
	var world: Node = load("res://scripts/world.gd").new()
	world._titles = {-42: "скелет", -44: "упир", 363077617: "Олекса"}
	_expect("бій", world.named("[бій] -44 вдарив 363077617 ЗІ СПИНИ, лишилось 0"),
			"[бій] упир вдарив Олекса ЗІ СПИНИ, лишилось 0")
	_expect("числа не чіпає", world.named(
			"[монстр] -42 покликав своїх: 1, -7 лишився"),
			"[монстр] скелет покликав своїх: 1, -7 лишився")
	_expect("кома після номера", world.named("[x] -42, -44"), "[x] скелет, упир")
	world.free()

	print("\n— рядки —")
	for line: String in ["[монстр] скелет покликав своїх: 1",
			"[скіл] упир застосував темний дотик рівня 1, цілей 1, мани лишилось 56",
			"[бій] упир вдарив Олекса ЗІ СПИНИ, лишилось 0",
			"[смерть] Олекса втратив 85 поваги, лишилось 429",
			"[бій] Олекса загинув, труп лежатиме 1200 с"]:
		_hud.log_line(line)
	_hud.notice("втрачено 85 поваги")
	await get_tree().process_frame
	_expect("рядків", _hud.log_count(), 6)
	_expect("мітка не з'їдена як bbcode",
			_hud._log_text.get_parsed_text().contains("[смерть] Олекса"), true)
	Shot.take(root)
	await get_tree().create_timer(1.2).timeout

	print("\n— згорнути —")
	var bottom: float = box.global_position.y + box.size.y
	var tall: float = box.size.y
	box._fold.pressed.emit()
	_expect("згорнуто до заголовка", box.size.y, WindowBox.TITLE_H)
	_expect("вміст сховано", box.body.visible, false)
	_expect("нижній край на місці", box.global_position.y + box.size.y, bottom)
	Shot.take(root)
	await get_tree().create_timer(1.2).timeout
	box._fold.pressed.emit()
	_expect("розгорнуто назад", [box.size.y, box.body.visible], [tall, true])
	_expect("і нижній край той самий", box.global_position.y + box.size.y, bottom)

	print("\n— перетягнути —")
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = Vector2(40, 10)
	box._on_title_input(down)
	var move := InputEventMouseMotion.new()
	move.position = Vector2(340, -190)
	box._on_title_input(move)
	down.pressed = false
	box._on_title_input(down)
	_expect("посунулось", box.global_position - Vector2(12.0, bottom - tall),
			Vector2(300, -200))

	print("\n— межа —")
	for i in HUD.LOG_LINES + 50:
		_hud.log_line("[бій] рядок %d" % i)
	_expect("не більше межі", _hud.log_count() <= HUD.LOG_LINES, true)
	_expect("останній — найновіший",
			_hud._log_text.get_parsed_text().strip_edges().ends_with(
			"рядок %d" % (HUD.LOG_LINES + 49)), true)

	print("\nпомилок: %d" % _bad)
	get_tree().quit(1 if _bad > 0 else 0)
