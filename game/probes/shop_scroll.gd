extends Node
## Прилавок і склад прокручуються, склад — сіткою значків (11.10.2026).
##
##     godot --path game res://scenes/shop_scroll.tscn
##     godot --headless --path game res://scenes/shop_scroll.tscn
##
## Слово замовника: «у крамаря багато чого доступно, але не можу
## вибрати, бо не видно смуги прокрутки; на складі зроби схожим як у
## крамаря, з іконками в комірках». Без сервера: товар і склад руками.
## З вікном — ще й знімки. Наприкінці «помилок: N».

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
	Net.joined = true
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

	var data := GameData.new()
	data.load_all()
	var names: Array = data.items.bases.keys()
	var goods: Array = []
	for i in 40:
		var base: Dictionary = data.items.base_of(names[i])
		goods.append({"назва": names[i], "ціна": 10 + i,
				"вид": base.get("вид", ""), "слот": base.get("слот", ""),
				"грейд": base.get("грейд", "")})

	print("\n— прилавок на 40 речей —")
	_hud.show_shop(5, "Ліда", goods, 30)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect("комірок прилавка", _hud._stock_cells.size(), 40)
	var last: Button = _hud._stock_cells[39]["press"]
	_expect("остання комірка — товар", last.disabled, false)
	var scroll: ScrollContainer = _hud._stock_grid["scroll"]
	var bar := scroll.get_v_scroll_bar()
	_expect("смугу видно", bar.visible, true)
	_expect("гортати є куди", bar.max_value > bar.page, true)
	scroll.scroll_vertical = int(bar.max_value)
	await get_tree().process_frame
	_expect("догорнули до кінця", scroll.scroll_vertical > 0, true)
	var bought: Array = []
	_hud.wants_buy.connect(func(_at: int, what: String, _n: int) -> void:
			bought.append(what))
	last.pressed.emit()
	_hud._confirm_done()
	_expect("останню можна купити", bought, [names[39]])
	Shot.take(root)
	await get_tree().create_timer(1.0).timeout
	_hud._shop_box.visible = false

	print("\n— склад сіткою —")
	_hud._things = [{"номер": 0, "назва": "залізний меч", "база":
			"залізний меч", "вид": "зброя", "слот": "зброя", "грейд": "D"}]
	_hud._stacks = [{"назва": "кора дуба", "вид": "ресурс", "скільки": 12}]
	_hud.show_warehouse(9)
	var kept: Array = []
	for i in 30:
		var base: Dictionary = data.items.base_of(names[i])
		kept.append({"номер": i, "назва": names[i], "база": names[i],
				"вид": base.get("вид", ""), "слот": base.get("слот", ""),
				"грейд": base.get("грейд", "")})
	_hud.set_warehouse(kept, [{"назва": "мітрил", "вид": "ресурс",
			"скільки": 4}])
	await get_tree().process_frame
	_expect("комірок складу", _hud._kept_rows.size(), 32)
	var icon: ItemIcon = _hud._kept_rows[0]["icon"]
	_expect("у комірці значок", icon.has_method("show_item")
			and not _hud._kept_rows[0]["press"].disabled, true)
	_expect("стос — з числом", _hud._kept_rows[30]["count"].text, "×4")
	var took: Array = []
	_hud.wants_withdraw_thing.connect(func(_at: int, n: int) -> void:
			took.append(n))
	_hud._kept_rows[29]["press"].pressed.emit()
	_expect("клік забирає річ 29", took, [29])
	_expect("торба: меч і кора", [_hud._bag_rows[0]["press"].disabled,
			_hud._bag_rows[1]["count"].text], [false, "×12"])
	Shot.take(root)
	await get_tree().create_timer(1.0).timeout

	print("\nпомилок: %d" % _bad)
	get_tree().quit(1 if _bad > 0 else 0)
