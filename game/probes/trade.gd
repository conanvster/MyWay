extends SceneTree
## Проба обміну між гравцями (П-218) і кількості зі стосу (П-164).
##
## Ганяти так:
##     godot --headless --path game --script res://probes/trade.gd
##
## Той самий принцип, що й `probes/warehouse.gd`: торби ОБОХ до й після,
## і кожна відмова окремо. Наприкінці — «помилок: N»; 0 — усе як треба.

const AVATAR := preload("res://scenes/avatar.tscn")

var _bad := 0


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	var data := GameData.new()
	data.load_all()
	await _swap(data)
	await _unagree(data)
	await _refusals(data)
	await _broken(data)
	await _counts(data)
	print("\nпомилок: %d" % _bad)
	quit()


func _hero(at: Vector3) -> Node3D:
	var hero: Node3D = AVATAR.instantiate()
	root.add_child(hero)
	await process_frame
	hero.global_position = at
	hero.hp = 100
	hero.in_fight = 0.0
	return hero


func _expect(what: String, got: Variant, want: Variant) -> void:
	var ok: bool = got == want
	if not ok:
		_bad += 1
	print("  %s %s: %s%s" % ["✓" if ok else "✗", what, str(got),
			"" if ok else " (чекали %s)" % str(want)])


func _pair() -> Array:
	var a := await _hero(Vector3.ZERO)
	var b := await _hero(Vector3(2, 0, 0))
	return [a, b]


## Звичайний обмін: меч і 50 руди від А за 300 грошей від Б.
func _swap(data: GameData) -> void:
	print("\n— обмін: меч і 50 руди за 300 грошей —")
	var t := Trade.new()
	var p := await _pair()
	var a: Node3D = p[0]
	var b: Node3D = p[1]
	var sword: int = a.add_thing(data.items.make("меч з кори дуба"))
	a.give_item("руда заліза", 80)
	b.give_item("гроші", 1000)

	_expect("запрошення", t.invite(1, 2, a, b), "")
	_expect("хто кличе Б", t.invited_by(2), 1)
	_expect("Б приймає", t.accept(2, a, b), "")
	_expect("А кладе меч", t.offer_thing(1, a, sword), "")
	_expect("А кладе 50 руди з 80", t.offer_stack(1, a, "руда заліза", 50), "")
	_expect("Б кладе 300 грошей", t.offer_stack(2, b, "гроші", 300), "")
	_expect("стіл А: моє", t.table_of(1)["моє"].size(), 2)
	_expect("стіл А: їхнє", t.table_of(1)["їхнє"].size(), 1)
	_expect("А згоден — чекаємо Б", t.agree(1, a, b), "")
	_expect("Б бачить згоду А", t.table_of(2)["вони згодні"], true)
	_expect("Б згоден — обмінено", t.agree(2, b, a), "обмінено")
	_expect("стіл закрито", t.busy(1) or t.busy(2), false)
	_expect("А: мечів", a.things.size(), 0)
	_expect("Б: мечів", b.things.size(), 1)
	_expect("А: руди", int(a.items.get("руда заліза", 0)), 30)
	_expect("Б: руди", int(b.items.get("руда заліза", 0)), 50)
	_expect("А: гроші", int(a.items.get("гроші", 0)), 300)
	_expect("Б: гроші", int(b.items.get("гроші", 0)), 700)
	a.queue_free()
	b.queue_free()


## Зміна на столі після чужої згоди знімає обидві згоди.
func _unagree(_data: GameData) -> void:
	print("\n— підміна після згоди —")
	var t := Trade.new()
	var p := await _pair()
	var a: Node3D = p[0]
	var b: Node3D = p[1]
	a.give_item("гроші", 500)
	b.give_item("руда заліза", 10)
	t.invite(1, 2, a, b)
	t.accept(2, a, b)
	t.offer_stack(1, a, "гроші", 500)
	t.offer_stack(2, b, "руда заліза", 10)
	t.agree(2, b, a)
	_expect("Б згоден", t.table_of(1)["вони згодні"], true)
	t.offer_stack(1, a, "гроші", 1)
	_expect("А зменшив гроші — згоду Б знято", t.table_of(1)["вони згодні"],
			false)
	_expect("А згоден", t.agree(1, a, b), "")
	_expect("нічого не перейшло до другої згоди",
			int(b.items.get("гроші", 0)), 0)
	a.queue_free()
	b.queue_free()


func _refusals(data: GameData) -> void:
	print("\n— чого обмін не дасть —")
	var t := Trade.new()
	var p := await _pair()
	var a: Node3D = p[0]
	var b: Node3D = p[1]
	_expect("сам із собою", t.invite(1, 1, a, a), "сам із собою не міняються")
	b.global_position = Vector3(10, 0, 0)
	_expect("задалеко", t.invite(1, 2, a, b),
			"задалеко для обміну: підійди ближче")
	b.global_position = Vector3(2, 0, 0)
	b.in_fight = 3.0
	_expect("у бою", t.invite(1, 2, a, b), "у бою не міняються")
	b.in_fight = 0.0
	b.hp = 0
	_expect("мертвий", t.invite(1, 2, a, b), "мертві не міняються")
	b.hp = 100
	_expect("прийняти без запрошення", t.accept(2, a, b),
			"запрошення вже немає")
	t.invite(1, 2, a, b)
	t.accept(2, a, b)
	var coat: int = a.add_thing(data.items.make("куртка з кори дуба"))
	a.equip(coat)
	_expect("вдягнене на стіл", t.offer_thing(1, a, coat), "спершу зніми")
	a.give_item("гроші", 5)
	_expect("більше, ніж є", t.offer_stack(1, a, "гроші", 6),
			"стільки немає: є 5")
	_expect("нуль", t.offer_stack(1, a, "гроші", 0), "стільки немає: є 5")
	_expect("стос, якого немає", t.offer_stack(1, a, "чогось-немає", 1),
			"такої речі немає")
	var c := await _hero(Vector3(1, 0, 1))
	_expect("третій кличе зайнятого", t.invite(3, 2, c, b),
			"гравець 2 уже міняється з кимось")
	a.queue_free()
	b.queue_free()
	c.queue_free()


## Стіл, що зламався: продав річ зі столу, відійшов, вийшов із гри.
func _broken(data: GameData) -> void:
	print("\n— стіл ламається —")
	var t := Trade.new()
	var p := await _pair()
	var a: Node3D = p[0]
	var b: Node3D = p[1]
	var sword: int = a.add_thing(data.items.make("меч з кори дуба"))
	b.give_item("гроші", 100)
	t.invite(1, 2, a, b)
	t.accept(2, a, b)
	t.offer_thing(1, a, sword)
	t.offer_stack(2, b, "гроші", 100)
	t.agree(1, a, b)
	a.drop_thing(sword)   # наче продав крамареві посеред обміну
	_expect("річ зі столу зникла — відмова", t.agree(2, b, a),
			"гравець 1 уже не має однієї з речей")
	_expect("гроші Б на місці", int(b.items.get("гроші", 0)), 100)
	_expect("стіл закрито", t.busy(1), false)

	t.invite(1, 2, a, b)
	t.accept(2, a, b)
	b.global_position = Vector3(20, 0, 0)
	var res: Dictionary = t.tick(0.1, {1: a, 2: b})
	_expect("Б відійшов — стіл зламано", res["зламані"].size(), 1)
	_expect("стіл закрито", t.busy(2), false)

	b.global_position = Vector3(2, 0, 0)
	t.invite(1, 2, a, b)
	res = t.tick(31.0, {1: a, 2: b})
	_expect("запрошення прострочилось", res["прострочені"].size(), 1)
	t.invite(1, 2, a, b)
	t.accept(2, a, b)
	_expect("А вийшов — Б повідомити", t.forget(1), 2)
	_expect("стіл закрито", t.busy(2), false)
	a.queue_free()
	b.queue_free()


## П-164: продаж і склад беруть число, а не лише весь стос.
func _counts(data: GameData) -> void:
	print("\n— скільки зі стосу (П-164) —")
	var shop := Shop.new(data)
	var wh := Warehouse.new()
	var a := await _hero(Vector3.ZERO)
	a.give_item("кора дуба", 10)
	var one := shop.buy_price("кора дуба")
	_expect("продати 3 з 10", shop.sell_stack(a, "кора дуба", 3), "")
	_expect("лишилось руди", int(a.items.get("кора дуба", 0)), 7)
	_expect("гроші за 3", int(a.items.get("гроші", 0)), one * 3)
	_expect("продати 8 з 7", shop.sell_stack(a, "кора дуба", 8),
			"стільки немає: є 7")
	_expect("на склад 5 з 7", wh.store_stack(a, "кора дуба", 5), "")
	_expect("торба / склад", [int(a.items.get("кора дуба", 0)),
			int(a.warehouse_items.get("кора дуба", 0))], [2, 5])
	_expect("зі складу 4 з 5", wh.withdraw_stack(a, "кора дуба", 4), "")
	_expect("торба / склад", [int(a.items.get("кора дуба", 0)),
			int(a.warehouse_items.get("кора дуба", 0))], [6, 1])
	_expect("зі складу 2 з 1", wh.withdraw_stack(a, "кора дуба", 2),
			"стільки на складі немає: є 1")
	_expect("увесь стос (−1) як раніше", wh.withdraw_stack(a, "кора дуба"), "")
	_expect("склад порожній", a.warehouse_items.has("кора дуба"), false)
	a.queue_free()
