extends Node
## Вітрина вікон: «Речі», «Стати» й «Скіли», набиті речами всіх видів.
##
## Ганяти так (через сцену, не `--script`):
##     ./run.sh --вітрина
##
## Навіщо окремий режим. Вигляд вікна речей прожив непобаченим цілий
## вечір саме тому, що побачити його не було як: у грі речі падають
## рідко (шолом — 1%), а показ рук не має. Вітрина ставить по речі в
## кожен слот і по речі кожного виду в торбу — і вигляд стає перевірним
## одним знімком, а не грою до першого шолома.
##
## Це НЕ лазівка в гру: сцени світу тут немає взагалі, сервера теж, і
## жодне повідомлення нікуди не йде. Те саме, чим `--парад` є для істот.
##
## Чому сценою, а не `--script` (полагоджено 06.09.2026). У режимі
## `--script` автозавантажень немає, а `hud.gd` двічі чіпає `Net`
## (`Net.joined` у «Вийти», `Net.connected()` у смузі читання) — проба
## тихо вмирала на `HUD.new()`, не друкуючи ні рядка, і зависала до
## вбивства ззовні. Помилка скрипта дерево не спиняє, тож виглядало це
## як «нічого не відбувається». Той самий прийом, яким уже живе лінтер
## (`scenes/lint.tscn`): сцена автозавантаження підіймає.
##
## Esc — вийти, пробіл — ще один знімок. Перший знімок робиться сам.

var _hud: Node
var _shop: Shop
var _seller: Dictionary = {}
## Щоб решта коду проби лишалась така сама, як була за `SceneTree`.
@onready var root: Window = get_tree().root


func _ready() -> void:
	_go()


func _go() -> void:
	await get_tree().process_frame
	var data := GameData.new()
	data.load_all()

	# Тло: без нього вікна висять на чорному, і напівпрозорість, заради
	# якої їх і робили, нічого не показує.
	var back := ColorRect.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.color = Color(0.24, 0.31, 0.22)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(back)

	_hud = HUD.new()
	root.add_child(_hud)
	_hud.setup(root)
	await get_tree().process_frame

	_hud.set_things(_worn(data), _stacks())
	_hud.set_stats(_stats())
	_hud.set_skills(_skills())
	_hud.show_windows()
	if _hud.has_method("_toggle_skills"):
		_hud._toggle_skills()
	_hud.show_guild(0, _guild_rows(data))
	await get_tree().process_frame

	# Друга сторінка вітрини — крамар. Вікна торгівлі в грі не побачити
	# інакше як дійти до Ліди, а знімок потрібен тут і зараз.
	_shop = Shop.new(data)
	_seller = _find_seller(data)

	print("— вітрина вікон —")
	print("  комірок тіла: %d" % ItemBook.BODY_SLOTS.size())
	print("  речей у торбі: %d" % _stacks().size())
	_report()
	_report_shop()

	# Далі — просто дивитись. Перший знімок робимо самі, щоб вітрина
	# годилась і для перевірки без рук.
	print("\n  Esc — вийти · пробіл — ще знімок · Т — прилавок")
	root.close_requested.connect(get_tree().quit)
	await get_tree().process_frame
	await get_tree().process_frame
	Shot.take(root)
	# Другий знімок — прилавок. Знімати обидва самому, бо саме «нема на
	# чому побачити» й лишило вигляд вікна речей неперевіреним на вечір.
	#
	# Секунда паузи не для краси: ім'я знімка складається з часу З
	# ТОЧНІСТЮ ДО СЕКУНДИ, і два знімки поспіль просто затирали один
	# одного — на диску лишався тільки другий.
	await get_tree().create_timer(1.2).timeout
	_open_shop()
	await get_tree().process_frame
	await get_tree().process_frame
	Shot.take(root)
	await get_tree().create_timer(0.3).timeout
	var space_held := false
	var trade_held := false
	while true:
		await get_tree().process_frame
		if Input.is_key_pressed(KEY_ESCAPE):
			break
		if Input.is_key_pressed(KEY_SPACE):
			if not space_held:
				Shot.take(root)
			space_held = true
		else:
			space_held = false
		if Input.is_key_pressed(KEY_T):
			if not trade_held:
				_open_shop()
			trade_held = true
		else:
			trade_held = false
	get_tree().quit()


## Прилавок Ліди з мапи, з цінами, порахованими сервером.
func _open_shop() -> void:
	if _shop == null or _seller.is_empty():
		print("  ‼ у мапі немає жодного крамаря — прилавка не буде")
		return
	_hud.show_shop(0, "%s, %s" % [_seller.get("хто"), _seller.get("ремесло")],
			_shop.goods_of(_seller),
			_shop.buyback_percent())


func _find_seller(data: GameData) -> Dictionary:
	for who: Dictionary in data.map.get("місто", {}).get("мешканці", []):
		if not Array(who.get("товар", [])).is_empty():
			return who
	return {}


## Прилавок числами: скільки товару, скільки свого, і чи вміщається.
func _report_shop() -> void:
	if _shop == null or _seller.is_empty():
		print("\n  ‼ крамаря в мапі немає")
		return
	_open_shop()
	var window: Control = _hud.find_child("ВікноТоргівлі", true, false)
	var stock := _shop.goods_of(_seller)
	print("\n— прилавок —")
	print("  крамар: %s, %s" % [_seller.get("хто"), _seller.get("ремесло")])
	print("  на прилавку: %d" % stock.size())
	print("  перше на прилавку: %s за %d" % [stock[0]["назва"], stock[0]["ціна"]])
	var screen: Vector2 = root.get_viewport().get_visible_rect().size
	print("  вікно торгівлі: %.0f×%.0f, екран %.0f×%.0f, вміщається: %s"
			% [window.size.x, window.size.y, screen.x, screen.y,
			   "ні ‼" if window.size.x > screen.x
					or window.size.y > screen.y else "так"])
	var hint: Label = window.get_node("Вміст").get_node("Ціна")
	print("  рядок ціни: «%s»" % hint.text)
	_report_confirm(window, stock)
	window.visible = false


## Підтвердження купівлі (П-159) — чи справді стоїть між натиском і
## покупкою. Перевіряємо натиском, а не читанням коду: рахуємо, скільки
## разів пролунало `wants_buy` до «Так» і після нього.
func _report_confirm(_window: Control, stock: Array) -> void:
	var box: Control = _hud.find_child("ВікноПідтвердження", true, false)
	print("\n— підтвердження купівлі (П-159) —")
	if box == null:
		print("  ‼ вікна підтвердження немає")
		return
	var bought: Array[String] = []
	_hud.wants_buy.connect(func(_at: int, what: String) -> void:
			bought.append(what))

	# Перша комірка прилавка — та сама, чию ціну щойно надрукували.
	var cells: Array = _hud._stock_cells
	if cells.is_empty():
		print("  ‼ жодної комірки прилавка не знайшлось")
		return
	var first: Button = cells[0]["press"]
	print("  до натиску: вікно видиме %s, куплено %d"
			% [box.visible, bought.size()])
	first.pressed.emit()
	print("  після натиску: вікно видиме %s, куплено %d — %s"
			% [box.visible, bought.size(),
			   "питає, не купує" if box.visible and bought.is_empty()
					else "‼ купило без питання"])
	var text: Label = box.get_node("Вміст").get_child(0)
	print("  питання: «%s» (сума %s)"
			% [text.text, "є" if text.text.contains(
					str(stock[0]["ціна"])) else "‼ немає"])

	# «Скасувати» має нічого не купити.
	_hud.hide_confirm()
	print("  після «Скасувати»: вікно видиме %s, куплено %d — %s"
			% [box.visible, bought.size(),
			   "скасовується" if not box.visible and bought.is_empty()
					else "‼ не скасувалось"])

	# І тепер по-справжньому: натиск, тоді «Так».
	first.pressed.emit()
	_hud._confirm_done()
	print("  після «Так»: куплено %d (%s) — %s"
			% [bought.size(), ", ".join(bought),
			   "купує" if bought.size() == 1 else "‼ не купило"])

	_report_confirm_store(box)


## Друга половина П-159: перенесення в склад теж питає.
func _report_confirm_store(box: Control) -> void:
	print("\n— підтвердження перенесення в склад (П-159) —")
	var stored: Array[String] = []
	_hud.wants_store_thing.connect(func(_at: int, _n: int) -> void:
			stored.append("річ"))
	_hud.wants_store_stack.connect(func(_at: int, what: String) -> void:
			stored.append(what))
	_hud.show_warehouse(0)
	var rows: Array = _hud._bag_rows
	if rows.is_empty():
		print("  ‼ рядків торби у складі немає")
		return
	var press: Button = rows[0]
	if press.disabled:
		print("  ‼ перший рядок торби порожній")
		return
	press.pressed.emit()
	var text: Label = box.get_node("Вміст").get_child(0)
	print("  після натиску: питає «%s», перенесено %d — %s"
			% [text.text, stored.size(),
			   "питає, не переносить" if box.visible and stored.is_empty()
					else "‼ перенесло без питання"])
	_hud._confirm_done()
	print("  після «Так»: перенесено %d — %s"
			% [stored.size(),
			   "переносить" if stored.size() == 1 else "‼ не перенесло"])
	_hud._warehouse_box.visible = false


## По речі в кожен слот тіла плюс те, що лежить у торбі.
func _worn(data: GameData) -> Array:
	var out: Array = []
	var at := 0
	# Слот -> база, якою його заповнити. Персні два, база одна.
	var wear := {
		"голова": "шолом з кори дуба",
		"підвіска": "амулет учня",
		"тіло": "куртка з кори дуба",
		"ремінь": "пояс з кори дуба",
		"рукавиці": "рукавиці з кори дуба",
		"взуття": "чоботи з кори дуба",
		"зброя": "меч з кори дуба",
		"щит": "щит з кори дуба",
		"перстень-1": "перстень учня",
		"перстень-2": "перстень учня",
	}
	# Грейди йдуть по колу: інакше всі значки одного кольору, і чи
	# розрізняються грейди взагалі — на знімку не видно.
	var grades: Array = ItemBook.GRADES
	for slot: String in ItemBook.BODY_SLOTS:
		var base: String = str(wear[slot])
		var item: Item = data.items.make(base)
		out.append({
			"номер": at,
			"назва": item.title() if item != null else base,
			"вид": data.items.kind_of(base),
			"слот": slot if not slot.begins_with("перстень") else "перстень",
			"комірки": ItemBook.slots_for(
					slot if not slot.begins_with("перстень") else "перстень"),
			"грейд": str(grades[at % grades.size()]),
			"вдягнене": true,
			"де": slot,
			"стати": "сила +%d" % (at + 1),
		})
		at += 1
	# І кілька в торбі, зокрема дворучна — щоб було видно і значок, і те,
	# що комірка жива.
	for spare: Array in [["сокира з кори дуба", "зброя"],
			["шолом з кори дуба", "голова"],
			["куртка з кори дуба", "тіло"],
			["перстень учня", "перстень"]]:
		var base: String = str(spare[0])
		var item: Item = data.items.make(base)
		out.append({
			"номер": at,
			"назва": item.title() if item != null else base,
			"вид": data.items.kind_of(base),
			"слот": str(spare[1]),
			"комірки": ItemBook.slots_for(str(spare[1])),
			"грейд": str(grades[at % grades.size()]),
			"вдягнене": false,
			"де": "",
			"стати": "спритність +1",
		})
		at += 1
	return out


func _stacks() -> Array:
	return [
		{"назва": "кора дуба", "вид": "ресурс", "грейд": "",
		 "скільки": 12, "придатна": false},
		{"назва": "шкура", "вид": "ресурс", "грейд": "",
		 "скільки": 3, "придатна": false},
		{"назва": "кристал душі", "вид": "витратне", "грейд": "E",
		 "скільки": 5, "придатна": true},
		{"назва": "руна енергетичного променю", "вид": "руна", "грейд": "E",
		 "скільки": 1, "придатна": true},
		{"назва": "руна підняття E грейду", "вид": "руна", "грейд": "D",
		 "скільки": 2, "придатна": true},
		{"назва": "гроші", "вид": "гроші", "грейд": "",
		 "скільки": 1060, "придатна": false},
	]


func _stats() -> Dictionary:
	return {
		"раса": "людина", "стать": "чоловік", "рівень": 14, "очки": 3,
		"сила": 18, "сила базова": 14,
		"спритність": 12, "спритність базова": 12,
		"витривалість": 16, "витривалість базова": 13,
		"інтелект": 11, "інтелект базова": 11,
		"чуття": 10, "чуття базова": 10,
		"здоров'я": 264, "мана": 148,
		"атака": 31.4, "магічна атака": 18.2,
		"захист": 42.0, "магічний захист": 27.5,
	}


func _skills() -> Array:
	return [
		{"ключ": "енергетичний-промінь", "назва": "енергетичний промінь",
		 "грейд": "E", "рівень": 3, "рівнів": 4, "мана": 12,
		 "дальність": 18.0},
		{"ключ": "енергетичний-вибух", "назва": "енергетичний вибух",
		 "грейд": "E", "рівень": 1, "рівнів": 3, "мана": 20,
		 "дальність": 5.0},
	]


## Дерево скілів (П-150) удаваним персонажем 10 рівня: корені вивчені,
## одна гілка тягнеться далі, друга стоїть замкненою — щоб на знімку
## були відразу всі три стани вузла.
func _guild_rows(data: GameData) -> Array:
	var known := {
		"енергетичний-вибух": 2, "потужний-удар": 0,
		"клич-хоробрості": 3, "клич-люті": 1,
		"стійка-щита": 2, "залізна-шкіра": 1,
	}
	var out: Array = []
	for key: String in data.skills.keys():
		var skill: Skill = data.skills.get_skill(key)
		if skill.category == "":
			continue
		var level: int = int(known.get(key, -1))
		var is_known: bool = level >= 1
		out.append({
			"ключ": key, "назва": skill.name, "грейд": skill.grade,
			"вивчено": is_known, "рівень": maxi(level, 0),
			"максимум": skill.max_level(), "з рівня": skill.from_level,
			"руна вивчення": skill.rune,
			"руна підняття": Runes.level_rune_for(skill.grade),
			"досвід вивчення": skill.learn_cost,
			"досвід підняття": Runes.raise_cost(skill, maxi(level, 1)),
			"вкладка": skill.category,
			"місце": [skill.position.x, skill.position.y],
			"передумова": skill.requires,
			"передумова відома": skill.requires == ""
					or int(known.get(skill.requires, -1)) >= 1,
		})
	return out


## Що вийшло — числами, бо на знімку «трохи не туди» не видно.
func _report() -> void:
	var window: Control = _hud.find_child("ВікноРечей", true, false)
	var page: Control = window.get_node("Вміст")
	var filled := 0
	var empty := 0
	for slot: String in ItemBook.BODY_SLOTS:
		var press: Button = _hud.find_child(slot, true, false)
		if press != null and not press.disabled:
			filled += 1
		else:
			empty += 1
	print("  зайнятих комірок тіла: %d, порожніх: %d" % [filled, empty])
	print("  вікно «Речі»: %.0f×%.0f у куті (%.0f, %.0f)"
			% [window.size.x, window.size.y,
			   window.global_position.x, window.global_position.y])
	var screen: Vector2 = root.get_viewport().get_visible_rect().size
	var out_of_screen: bool = window.global_position.x < 0 \
			or window.global_position.y < 0 \
			or window.global_position.x + window.size.x > screen.x \
			or window.global_position.y + window.size.y > screen.y
	print("  вилазить за екран %.0f×%.0f: %s"
			% [screen.x, screen.y, "ТАК ‼" if out_of_screen else "ні"])
	var purse: Label = page.get_node("Гроші")
	print("  гроші окремим рядком: «%s»" % purse.text)
