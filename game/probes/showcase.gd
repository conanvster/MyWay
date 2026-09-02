extends SceneTree
## Вітрина вікон: «Речі», «Стати» й «Скіли», набиті речами всіх видів.
##
## Ганяти так:
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
## Esc — вийти, пробіл — ще один знімок. Перший знімок робиться сам.

var _hud: Node


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
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
	await process_frame

	_hud.set_things(_worn(data), _stacks())
	_hud.set_stats(_stats())
	_hud.set_skills(_skills())
	_hud.show_windows()
	if _hud.has_method("_toggle_skills"):
		_hud._toggle_skills()
	await process_frame

	print("— вітрина вікон —")
	print("  комірок тіла: %d" % ItemBook.BODY_SLOTS.size())
	print("  речей у торбі: %d" % _stacks().size())
	_report()

	# Далі — просто дивитись. Перший знімок робимо самі, щоб вітрина
	# годилась і для перевірки без рук.
	print("\n  Esc — вийти · пробіл — ще знімок")
	root.close_requested.connect(quit)
	await process_frame
	await process_frame
	Shot.take(root)
	var space_held := false
	while true:
		await process_frame
		if Input.is_key_pressed(KEY_ESCAPE):
			break
		if Input.is_key_pressed(KEY_SPACE):
			if not space_held:
				Shot.take(root)
			space_held = true
		else:
			space_held = false
	quit()


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
