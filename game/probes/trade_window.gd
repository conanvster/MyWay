extends Node
## Проба вікон обміну (П-218) і вибору кількості − / + (П-164).
##
## Ганяти так (сценою — HUD чіпає автозавантаження `Net`):
##     godot --path game res://scenes/trade_window.tscn
##     godot --headless --path game res://scenes/trade_window.tscn
##
## Без сервера: стіл подається руками, а що вікно ПРОСИТЬ, ловиться з
## його сигналів. З вікном — ще й два знімки (кількість і стіл).
## Наприкінці «помилок: N».

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

	for sig: String in ["wants_sell_stack", "wants_store_stack",
			"wants_withdraw_stack", "wants_trade_offer_thing",
			"wants_trade_offer_stack", "wants_trade_take_back_thing",
			"wants_trade_take_back_stack", "wants_trade_agree",
			"wants_trade_cancel", "wants_trade_answer"]:
		_hud.connect(sig, _catch.bind(sig))

	_hud.set_things([
		{"номер": 0, "назва": "меч з кори дуба", "вид": "зброя",
			"слот": "зброя", "грейд": "E", "вдягнене": false},
		{"номер": 1, "назва": "куртка з кори дуба", "вид": "обладунок",
			"слот": "тіло", "грейд": "E", "вдягнене": true},
	], [
		{"назва": "гроші", "вид": "гроші", "скільки": 5000},
		{"назва": "кора дуба", "вид": "ресурс", "скільки": 12},
	])

	print("\n— скільки зі стосу (П-164) —")
	_hud.ask_count(func(n: int) -> String:
				return "Продати «кора дуба» ×%d за %d?" % [n, n * 3],
			12, func(n: int) -> void:
				_hud.wants_sell_stack.emit(0, "кора дуба", n))
	_expect("за замовчуванням увесь стос", _hud._count, 12)
	_expect("рядок − / + видно", _hud._count_row.visible, true)
	_hud._count_step(-1)
	_hud._count_step(-1)
	_hud._count_step(-1)
	_expect("тричі −", _hud._count, 9)
	_expect("питання з сумою", _hud._confirm_text.text,
			"Продати «кора дуба» ×9 за 27?")
	_hud._count_step(+100)
	_expect("+ не більше стосу", _hud._count, 12)
	_hud._count_step(-100)
	_expect("− не менше 1", _hud._count, 1)
	_hud._count_step(+4)
	await get_tree().process_frame
	Shot.take(root)
	await get_tree().create_timer(1.2).timeout
	_hud._confirm_done()
	_expect("«Так» шле вибране число", _asked.back(),
			["wants_sell_stack", [0, "кора дуба", 5]])

	# Затиснута «+»: 0,4 с паузи, далі крок кожні 0,06 с.
	_hud.ask_count(func(n: int) -> String: return "%d" % n, 5000,
			func(_n: int) -> void: pass)
	_hud._count_step(-5000)
	_hud._count_hold = 1
	_hud._count_hold_left = 0.4
	for i in 60:
		_hud._count_tick(0.06)
	_expect("затиснута «+» за 3,6 с набігає сотнями (>1000)",
			_hud._count > 1000, true)
	_hud._count_hold = 0
	_hud._confirm_refused()
	_expect("«Скасувати» ховає", _hud._confirm_box.visible, false)

	_hud.ask_count(func(n: int) -> String: return "%d" % n, 1,
			func(_n: int) -> void: pass)
	_expect("стос з однієї штуки — без − / +", _hud._count_row.visible, false)
	_hud.hide_confirm()

	print("\n— запрошення до обміну —")
	_asked.clear()
	_hud.ask_trade_invite("Борислав")
	_expect("питає", _hud._confirm_text.text,
			"Борислав пропонує обмін. Погодитись?")
	_hud._confirm_box.visible = false     # хрестик
	_expect("хрестик — це «ні»", _asked, [["wants_trade_answer", [false]]])
	_asked.clear()
	_hud.ask_trade_invite("Борислав")
	_hud._confirm_done()
	_expect("«Так» — це «так»", _asked, [["wants_trade_answer", [true]]])

	print("\n— стіл обміну —")
	_asked.clear()
	_hud.show_trade("Борислав", {
		"моє": [{"на столі": 0, "номер": 0, "назва": "меч з кори дуба",
				"грейд": "E"},
				{"назва": "кора дуба", "скільки": 5}],
		"їхнє": [{"назва": "гроші", "скільки": 300}],
		"я згоден": false, "вони згодні": true,
	})
	_expect("вікно видно", _hud._trade_box.visible, true)
	var bag: Array = []
	for b: Button in _hud._trade_bag_rows:
		if not b.disabled:
			bag.append(b.text)
	_expect("торба: без вдягненого й без меча зі столу", bag,
			["гроші ×5000", "кора дуба ×12"])
	_expect("чужий бік", _hud._trade_theirs_rows[0].text, "гроші ×300")
	_expect("чужу згоду видно", _hud._trade_theirs_head.text,
			"Борислав  ✓ згоден")
	_hud._trade_mine_rows[1].pressed.emit()
	_expect("клік по своєму стосу — забрати", _asked.back(),
			["wants_trade_take_back_stack", ["кора дуба"]])
	_hud._trade_bag_rows[0].pressed.emit()
	_expect("клік по грошах питає скільки", _hud._count, 5000)
	_hud._count_step(-4000)
	_hud._confirm_done()
	_expect("кладе 1000 грошей", _asked.back(),
			["wants_trade_offer_stack", ["гроші", 1000]])
	_hud._trade_agree.pressed.emit()
	_expect("«Згоден»", _asked.back(), ["wants_trade_agree", []])
	await get_tree().process_frame
	Shot.take(root)
	await get_tree().create_timer(1.2).timeout

	_asked.clear()
	_hud.hide_trade()
	_expect("сервер закрив — «скасувати» не шлемо", _asked, [])
	_hud.show_trade("Борислав", {"моє": [], "їхнє": [], "я згоден": false,
			"вони згодні": false})
	_hud._trade_box.visible = false
	_expect("хрестик — скасувати", _asked.back(), ["wants_trade_cancel", []])

	print("\nпомилок: %d" % _bad)
	get_tree().quit()


func _catch(a: Variant = null, b: Variant = null, c: Variant = null,
		sig: String = "") -> void:
	# Сигнали різної довжини: зайві null відкидаємо, ім'я — останнє.
	var args: Array = []
	for one: Variant in [a, b, c]:
		if one is String and sig == "" and str(one).begins_with("wants_"):
			sig = str(one)
			continue
		if one != null:
			args.append(one)
	_asked.append([sig, args])
