extends SceneTree
## Проба крамаря: ціни, купівля, продаж і чого сервер не дозволить.
##
## Ганяти так:
##     godot --headless --path game --script res://probes/shop.gd
##
## Крамар — це перше місце, де гравець може зробити собі речі з нічого,
## якщо десь недодивитись. Тому перевіряємо не «купилось», а **гроші до
## і після** й кожну відмову окремо: купити те, чого немає на прилавку;
## купити без грошей; продати вдягнене; продати гроші.

const AVATAR := preload("res://scenes/avatar.tscn")


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	var data := GameData.new()
	data.load_all()
	await _prices(data)
	await _buying(data)
	await _selling(data)
	await _refusals(data)
	quit()


func _hero(data: GameData) -> Node3D:
	var who: Node3D = AVATAR.instantiate()
	root.add_child(who)
	return who


func _prices(data: GameData) -> void:
	print("\n— ціни —")
	var shop := Shop.new(data)
	var city: Dictionary = data.map.get("місто", {})
	var seller := {}
	for who: Dictionary in city.get("мешканці", []):
		if not Array(who.get("товар", [])).is_empty():
			seller = who
			break
	if seller.is_empty():
		print("  ‼ у мапі немає жодного крамаря")
		return
	print("  крамар: %s, %s" % [seller.get("хто"), seller.get("ремесло")])
	var stock := shop.goods_of(seller)
	print("  на прилавку: %d" % stock.size())
	for row: Dictionary in stock:
		print("      %-32s %s  продає %4d  купує %4d"
				% [row["назва"], row["грейд"], int(row["ціна"]),
				   shop.buy_price(str(row["назва"]))])


func _buying(data: GameData) -> void:
	print("\n— купівля —")
	var shop := Shop.new(data)
	var seller := _seller(data)
	var hero := _hero(data)
	await process_frame

	Shop.give_money(hero, 500)
	print("  грошей: %d, речей: %d"
			% [Shop.money_of(hero), hero.things.size()])
	var why: String = shop.buy(hero, seller, "меч з кори дуба")
	print("  купуємо меч (120): %s" % ["вийшло" if why == "" else why])
	print("  грошей: %d, речей: %d"
			% [Shop.money_of(hero), hero.things.size()])
	print("  що саме взяли: %s"
			% [hero.things[0].title() if hero.things.size() > 0 else "—"])

	# Складана річ має лягти в стос, а не окремою річчю.
	why = shop.buy(hero, seller, "кристал душі")
	print("  купуємо кристал: %s" % ["вийшло" if why == "" else why])
	print("  у стосах: %s" % [hero.items])

	# Десять за раз — стос росте на 10, гроші меншають на 10 цін.
	var each := shop.sell_price("кристал душі")
	var was := Shop.money_of(hero)
	why = shop.buy(hero, seller, "кристал душі", 10)
	print("  купуємо 10 кристалів: %s, кристалів %d, витрачено %d (чекаю %d)"
			% ["вийшло" if why == "" else why,
			   int(hero.items.get("кристал душі", 0)),
			   was - Shop.money_of(hero), each * 10])
	# Нескладану — не більше однієї; на більше, ніж є грошей, — нічого.
	print("  2 мечі за раз: %s" % shop.buy(hero, seller, "меч з кори дуба", 2))
	was = Shop.money_of(hero)
	print("  кристалів на %d при грошах %d: %s, грошей лишилось %d"
			% [was / each + 1, was,
			   shop.buy(hero, seller, "кристал душі", was / each + 1),
			   Shop.money_of(hero)])
	print("  0 і −5 штук: «%s», «%s»"
			% [shop.buy(hero, seller, "кристал душі", 0),
			   shop.buy(hero, seller, "кристал душі", -5)])
	hero.queue_free()


func _selling(data: GameData) -> void:
	print("\n— продаж —")
	var shop := Shop.new(data)
	var hero := _hero(data)
	await process_frame

	var sword: int = hero.add_thing(data.items.make("меч з кори дуба"))
	hero.give_item("кора дуба", 7)
	print("  до продажу: грошей %d, речей %d, кори %d"
			% [Shop.money_of(hero), hero.things.size(),
			   int(hero.items.get("кора дуба", 0))])
	var why: String = shop.sell(hero, sword)
	print("  продаємо меч: %s" % ["вийшло" if why == "" else why])
	print("  грошей %d, речей %d"
			% [Shop.money_of(hero), hero.things.size()])
	why = shop.sell_stack(hero, "кора дуба")
	print("  продаємо весь стос кори: %s"
			% ["вийшло" if why == "" else why])
	print("  грошей %d, кори %d"
			% [Shop.money_of(hero), int(hero.items.get("кора дуба", 0))])
	hero.queue_free()


## Чотири відмови. Кожна з них — окремий спосіб зробити речі з нічого.
func _refusals(data: GameData) -> void:
	print("\n— чого крамар не дасть —")
	var shop := Shop.new(data)
	var seller := _seller(data)
	var hero := _hero(data)
	await process_frame

	print("  без грошей (0) купуємо меч: %s"
			% shop.buy(hero, seller, "меч з кори дуба"))
	Shop.give_money(hero, 10000)
	print("  купуємо руну, якої немає на прилавку: %s"
			% shop.buy(hero, seller, "руна енергетичного променю"))
	print("  купуємо те, чого немає в грі взагалі: %s"
			% shop.buy(hero, seller, "меч-кладенець"))

	var armour: int = hero.add_thing(data.items.make("куртка з кори дуба"))
	hero.equip(armour)
	print("  продаємо ВДЯГНЕНЕ: %s" % shop.sell(hero, armour))
	print("  продаємо гроші: %s" % shop.sell_stack(hero, "гроші"))
	print("  грошей лишилось: %d (мало бути 10000)" % Shop.money_of(hero))

	# Відстань. Мешканця тут немає, тож перевіряємо саму міру.
	var far := Node3D.new()
	root.add_child(far)
	far.global_position = hero.global_position + Vector3(0, 0, 3.0)
	print("  за 3.0 м досить близько: %s" % shop.within(hero, far))
	far.global_position = hero.global_position + Vector3(0, 0, 9.0)
	print("  за 9.0 м досить близько: %s (межа %.1f)"
			% [shop.within(hero, far), Shop.TALK_RANGE])
	far.queue_free()
	hero.queue_free()


## Крамар, у якого є меч і кристал. Перший-ліпший крамар міста ними
## більше не торгує (асортимент у мапі змінився), і купівля відмовляла
## «цього тут не продають», нічого не перевіряючи. Нема такого — прилавок
## з цих двох речей: проба про правила купівлі, не про асортимент.
func _seller(data: GameData) -> Dictionary:
	for who: Dictionary in data.map.get("місто", {}).get("мешканці", []):
		var goods := Array(who.get("товар", []))
		if goods.has("меч з кори дуба") and goods.has("кристал душі"):
			return who
	return {"товар": ["меч з кори дуба", "кристал душі"]}
