extends SceneTree
## Проба вікна «Речі»: вдягти, зняти, побачити зміну статів.
##
## Ганяти так:
##     godot --headless --path game --script res://probes/things.gd
##
## Замовник не міг вдягти броню, бо вікна речей не було взагалі: сервер
## умів `equip`, але покликати його не було звідки. Перевіряємо обидва
## боки — і що показ малює перелік, і що вдягання справді зсуває стати.

const AVATAR := preload("res://scenes/avatar.tscn")


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	await _wearing()
	await _hands()
	await _window()
	quit()


func _wearing() -> void:
	print("\n— вдягання зсуває стати —")
	var data := GameData.new()
	data.load_all()
	var hero: Node3D = AVATAR.instantiate()
	root.add_child(hero)
	await process_frame

	var armour: Item = data.items.make("куртка з кори дуба")
	if armour == null:
		print("  ‼ такої речі немає в data/items.json")
		hero.queue_free()
		return
	var at: int = hero.add_thing(armour)
	print("  у торбі: %s (слот «%s», стати %s)"
			% [armour.title(), armour.slot, armour.stats])
	print("  до вдягання:  витривалість %d, здоров'я %d"
			% [hero.stats.stamina, hero.stats.max_hp()])
	var why: String = hero.equip(at)
	print("  вдягання: %s" % ["вийшло" if why == "" else why])
	print("  після:        витривалість %d, здоров'я %d"
			% [hero.stats.stamina, hero.stats.max_hp()])
	print("  вважається вдягненим: %s" % [hero.is_worn(at)])
	hero.unequip(armour.slot)
	print("  після зняття: витривалість %d, здоров'я %d"
			% [hero.stats.stamina, hero.stats.max_hp()])
	hero.queue_free()


## Дві руки й два пальці — правила, яких оком не побачиш.
func _hands() -> void:
	print("\n— руки й пальці —")
	var data := GameData.new()
	data.load_all()
	var hero: Node3D = AVATAR.instantiate()
	root.add_child(hero)
	await process_frame

	var sword: int = hero.add_thing(data.items.make("меч з кори дуба"))
	var shield: int = hero.add_thing(data.items.make("щит з кори дуба"))
	var axe: int = hero.add_thing(data.items.make("сокира з кори дуба"))
	print("  меч на дві руки: %s, сокира: %s"
			% [hero.things[sword].two_handed, hero.things[axe].two_handed])

	print("  меч:  %s" % ["вдягнено" if hero.equip(sword) == "" else "ні"])
	print("  щит:  %s" % ["вдягнено" if hero.equip(shield) == "" else "ні"])
	print("  у руках: зброя «%s», щит «%s»"
			% [_named(hero.worn_in("зброя")), _named(hero.worn_in("щит"))])

	print("  беремо сокиру (дві руки): %s"
			% ["вдягнено" if hero.equip(axe) == "" else "ні"])
	print("  щит сам зник: %s" % [hero.worn_in("щит") == null])
	print("  спроба вдягти щит назад: %s" % hero.equip(shield))

	var ring1: int = hero.add_thing(data.items.make("перстень учня"))
	var ring2: int = hero.add_thing(data.items.make("перстень учня"))
	hero.equip(ring1)
	hero.equip(ring2)
	print("  два персні: палець 1 «%s», палець 2 «%s»"
			% [_named(hero.worn_in("перстень-1")),
			   _named(hero.worn_in("перстень-2"))])
	hero.queue_free()


func _named(item: Item) -> String:
	return item.title() if item != null else "—"


func _window() -> void:
	print("\n— саме вікно —")
	var hud := HUD.new()
	root.add_child(hud)
	hud.setup(root)
	await process_frame
	var worn_ask := []
	var wear_ask := []
	var use_ask := []
	hud.wants_take_off.connect(func(slot: String) -> void: worn_ask.append(slot))
	hud.wants_wear.connect(func(at: int, slot: String) -> void:
			wear_ask.append([at, slot]))
	hud.wants_use.connect(func(name: String) -> void: use_ask.append(name))

	hud.set_things([
		{"номер": 0, "назва": "куртка з кори дуба", "вид": "обладунок",
		 "слот": "тіло", "де": "тіло", "комірки": ["тіло"], "грейд": "E",
		 "вдягнене": true, "стати": "витривалість +2"},
		{"номер": 1, "назва": "легкий шолом з кори дуба", "вид": "обладунок",
		 "слот": "голова", "де": "", "комірки": ["голова"], "грейд": "D",
		 "вдягнене": false, "стати": "спритність +2"},
		{"номер": 2, "назва": "перстень учня", "вид": "амулет",
		 "слот": "перстень", "де": "",
		 "комірки": ["перстень-1", "перстень-2"], "грейд": "E",
		 "вдягнене": false, "стати": "чуття +1"},
		{"номер": 3, "назва": "кора дуба", "вид": "ресурс", "слот": "",
		 "де": "", "комірки": [], "грейд": "E", "вдягнене": false,
		 "стати": ""}],
		[{"назва": "кристал душі", "вид": "витратне", "грейд": "E",
		  "скільки": 3, "придатна": true},
		 {"назва": "гроші", "вид": "гроші", "грейд": "",
		  "скільки": 1060, "придатна": false}])
	await process_frame

	# Комірка більше не має тексту: у ній значок, а назва в підказці.
	# Тому й перевіряємо підказку — саме її читає людина.
	print("  комірки тіла:")
	for slot: String in ItemBook.BODY_SLOTS:
		var press: Button = hud.find_child(slot, true, false)
		var first: String = press.tooltip_text.split("\n")[0]
		print("      %-12s %-30s %s" % [slot, first,
				"порожня" if press.disabled else "можна зняти"])
	var purse: Label = hud.find_child("Гроші", true, false)
	print("  окремим рядком: «%s»" % purse.text)

	# Натискаємо так само, як натиснула б людина.
	for slot: String in ItemBook.BODY_SLOTS:
		var press: Button = hud.find_child(slot, true, false)
		if not press.disabled:
			press.pressed.emit()
	var taken := 0
	var page: Control = hud.find_child("ВікноРечей", true, false) \
			.get_node("Вміст")
	for child in page.get_children():
		if child is Button and not child.disabled \
				and not ItemBook.BODY_SLOTS.has(child.name):
			taken += 1
			child.pressed.emit()
	print("  живих комірок у торбі: %d" % taken)
	print("  попросили зняти: %s" % [worn_ask])
	print("  попросили вдягти (номери): %s" % [wear_ask])
	print("  попросили вжити: %s" % [use_ask])
	hud.queue_free()
