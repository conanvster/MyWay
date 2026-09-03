extends SceneTree
## Проба складу (крок 5, П-145): покласти, забрати, чого не дасть.
##
## Ганяти так:
##     godot --headless --path game --script res://probes/warehouse.gd
##
## Той самий принцип, що й `probes/shop.gd`: перевіряємо не «спрацювало»,
## а торбу й склад ДО й ПІСЛЯ кожної дії, і кожну відмову окремо.

const AVATAR := preload("res://scenes/avatar.tscn")


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	var data := GameData.new()
	data.load_all()
	await _stacks(data)
	await _things(data)
	await _refusals(data)
	quit()


func _hero() -> Node3D:
	var hero: Node3D = AVATAR.instantiate()
	root.add_child(hero)
	await process_frame
	return hero


func _stacks(_data: GameData) -> void:
	print("\n— складані —")
	var wh := Warehouse.new()
	var hero := await _hero()

	hero.give_item("руда заліза", 5)
	print("  до: торба %d, склад %d" % [int(hero.items.get("руда заліза", 0)),
			int(hero.warehouse_items.get("руда заліза", 0))])
	var why: String = wh.store_stack(hero, "руда заліза")
	print("  кладемо весь стос: %s" % ["вийшло" if why == "" else why])
	print("  після: торба %d, склад %d" % [int(hero.items.get("руда заліза", 0)),
			int(hero.warehouse_items.get("руда заліза", 0))])

	why = wh.withdraw_stack(hero, "руда заліза")
	print("  забираємо весь стос: %s" % ["вийшло" if why == "" else why])
	print("  після: торба %d, склад %d" % [int(hero.items.get("руда заліза", 0)),
			int(hero.warehouse_items.get("руда заліза", 0))])
	hero.queue_free()


func _things(data: GameData) -> void:
	print("\n— поодинокі —")
	var wh := Warehouse.new()
	var hero := await _hero()

	var at: int = hero.add_thing(data.items.make("меч з кори дуба"))
	print("  до: торба %d, склад %d" % [hero.things.size(),
			hero.warehouse_things.size()])
	var why: String = wh.store_thing(hero, at)
	print("  кладемо меч: %s" % ["вийшло" if why == "" else why])
	print("  після: торба %d, склад %d" % [hero.things.size(),
			hero.warehouse_things.size()])

	why = wh.withdraw_thing(hero, 0)
	print("  забираємо меч: %s" % ["вийшло" if why == "" else why])
	print("  після: торба %d, склад %d" % [hero.things.size(),
			hero.warehouse_things.size()])
	hero.queue_free()


## Три відмови: вдягненого не кладемо, чужого не забираємо, порожнього
## стосу не кладемо.
func _refusals(data: GameData) -> void:
	print("\n— чого склад не дасть —")
	var wh := Warehouse.new()
	var hero := await _hero()

	var at: int = hero.add_thing(data.items.make("куртка з кори дуба"))
	hero.equip(at)
	print("  кладемо ВДЯГНЕНЕ: %s" % wh.store_thing(hero, at))
	print("  кладемо стос, якого немає: %s"
			% wh.store_stack(hero, "чогось-немає"))
	print("  забираємо зі складу поодиноку, якої там немає: %s"
			% wh.withdraw_thing(hero, 0))
	print("  забираємо зі складу стос, якого там немає: %s"
			% wh.withdraw_stack(hero, "чогось-немає"))
	hero.queue_free()
