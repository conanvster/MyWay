extends SceneTree
## Місткість торби (слово замовника 14.11.2026): «повна торба — річ
## лишається лежати на землі, і гравець бачить „торба повна“» і
## «зачищене підземелля +2 ячейки».
##
##     godot --headless --path game --script res://probes/bag.gd
##
## Числа, не враження: скільки місць, скільки зайнято, куди лягла
## здобич, що відповіли крамар, склад, земля й коваль, і що +2 місця
## справді пускають ще дві речі.

const AVATAR := preload("res://scenes/avatar.tscn")

var _bad := 0


func _init() -> void:
	call_deferred("_go")


func _expect(what: String, ok: bool) -> void:
	if not ok:
		_bad += 1
	print("  %s %s" % ["✓" if ok else "✗", what])


func _go() -> void:
	await process_frame
	var data := GameData.new()
	data.load_all()
	var book: ItemBook = data.items
	var hero: Node3D = AVATAR.instantiate()
	root.add_child(hero)
	await process_frame
	var creatures := {1: hero}
	var link := Messenger.new()
	var ground := Ground.new()
	var combat := Combat.new(creatures, link)
	combat.goods = book
	combat.ground = ground

	print("\n— місця —")
	var room := book.bag_room(hero)
	_expect("основа з даних: %d місць" % room, room == 30)
	hero.give_item("гроші", 100000)
	hero.give_item("кора дуба", 5)
	_expect("гроші місця не займають, стос — одне: зайнято %d"
			% book.bag_used(hero), book.bag_used(hero) == 1)
	# Вдягнене місця не займає.
	var worn: int = hero.add_thing(book.make("шолом з кори дуба"))
	hero.equip(worn)
	_expect("вдягнене місця не займає: зайнято %d" % book.bag_used(hero),
			book.bag_used(hero) == 1)
	while book.bag_used(hero) < room:
		hero.add_thing(book.make("пояс з кори дуба"))
	_expect("торба повна: %d / %d" % [book.bag_used(hero), room],
			book.bag_used(hero) == room)
	_expect("ще одна поодинока не влазить", not book.bag_fits(hero, 1))
	_expect("стос того, що вже є, влазить", book.bag_fits(hero, 0, ["кора дуба"]))
	_expect("новий стос не влазить", not book.bag_fits(hero, 0, ["зілля лікування"]))

	print("\n— здобич при повній торбі —")
	var before: int = hero.things.size()
	# Шолом: комірка голови зайнята — вдягнутись нікуди, лише в торбу.
	combat._give(1, hero, "шолом з кори дуба", 1)
	_expect("поодинока лягла на землю: на землі %d, у торбі не додалось"
			% ground.lying.size(), ground.lying.size() == 1
			and hero.things.size() == before)
	combat._give(1, hero, "зілля лікування", 3)
	_expect("новий стос ліг на землю: на землі %d" % ground.lying.size(),
			ground.lying.size() == 2 and not hero.items.has("зілля лікування"))
	combat._give(1, hero, "кора дуба", 2)
	_expect("стос того, що вже є, пішов у торбу: кори %d"
			% int(hero.items.get("кора дуба", 0)),
			int(hero.items.get("кора дуба", 0)) == 7)
	hero.unequip("голова")
	before = hero.things.size()
	var at_ground: int = ground.lying.size()
	combat._give(1, hero, "шолом з кори дуба", 1)
	_expect("порожня комірка тіла бере річ і з повної торби: вдягнено, на землі не додалось",
			hero.things.size() == before + 1 and hero.gear.has("голова")
			and ground.lying.size() == at_ground)
	# Зняти шолом, який щойно вдягнувся, — торба переповнена на одну
	# (видно, бо зняте лягає в торбу). Викидаємо зайве, щоб далі було рівно.
	hero.equip(worn)
	hero.drop_thing(hero.things.size() - 1)
	_expect("рівно повна: %d / %d" % [book.bag_used(hero), room],
			book.bag_used(hero) == room)

	print("\n— земля, крамар, склад, коваль —")
	var got := ground.pick_up(hero, book)
	_expect("з землі не піднімає: «%s»" % str(got),
			bool(got.get("торба повна", false)) and ground.lying.size() == 2)
	var shop := Shop.new(data)
	var why := shop.buy(hero, {"товар": ["амулет учня"]}, "амулет учня")
	var money := int(hero.items.get("гроші", 0))
	_expect("крамар не продає: «%s», гроші не взято (%d)" % [why, money],
			why == "торба повна" and money == 100000)
	var store := Warehouse.new()
	store.book = book
	hero.warehouse_things.append(book.make("амулет учня"))
	hero.warehouse_items["зілля лікування"] = 2
	why = store.withdraw_thing(hero, 0)
	_expect("склад не віддає річ: «%s»" % why, why == "торба повна"
			and hero.warehouse_things.size() == 1)
	why = store.withdraw_stack(hero, "зілля лікування")
	_expect("склад не віддає новий стос: «%s»" % why, why == "торба повна")

	print("\n— +2 місця —")
	var step := int(book.bag.get("за зачищене підземелля", 0))
	hero.bag_extra += step
	_expect("за зачищене підземелля +%d: тепер %d" % [step, book.bag_room(hero)],
			step == 2 and book.bag_room(hero) == 32)
	got = ground.pick_up(hero, book)
	_expect("тепер піднімає: «%s»" % str(got.get("назва", "")),
			not got.is_empty() and not got.has("торба повна"))
	why = store.withdraw_thing(hero, 0)
	_expect("і склад віддає: «%s», зайнято %d / %d"
			% [why, book.bag_used(hero), book.bag_room(hero)],
			why == "" and book.bag_used(hero) == 32)

	print("\n— запис у базу й назад —")
	var row := Store.row_of("Проба", hero)
	_expect("у записі bag_extra = %s" % str(row.get("bag_extra")),
			int(row.get("bag_extra", -1)) == 2)
	var other: Node3D = AVATAR.instantiate()
	root.add_child(other)
	await process_frame
	Store.apply_row(other, row, book)
	_expect("прочитано назад: %d місць" % book.bag_room(other),
			book.bag_room(other) == 32)

	print("\n%s" % ("усе гаразд" if _bad == 0 else "вад: %d" % _bad))
	quit(0 if _bad == 0 else 1)
