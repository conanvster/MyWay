extends Node
## Коваль, міцність зброї й ремені з панелями (21.09.2026).
##
## Слово замовника: «зроби коваля, щоб він надавав послуги… зачарування
## дає для магічних предметів більш вірогідно, але не 100% магічні
## параметри, для фізичних більш вірогідно фізичні… ремені з грейдом —
## більше грейд, більше полосок».
##
## Перевіряємо числами: зброя тупиться й лагодиться, ціна рахується
## сервером, зачарування забирає своє й кладе одну руну, ймовірності
## сходяться на тисячах кидків, ремінь відчиняє смуги панелі, бос дає
## есенцію.
##
##     godot --headless --path game res://scenes/smith.tscn -- --світ1

const MAIN := preload("res://scenes/main.tscn")
const SWORD := "меч з кори дуба"
const AMULET := "амулет учня"
const HELMET := "шолом з кори дуба"

var _ok := 0
var _bad := 0


class Quiet extends Messenger:
	var said: Array[String] = []

	func notice(_id: int, text: String) -> void:
		said.append(text)

	func to_all(_method: StringName, _args: Array = []) -> void:
		pass

	func to_watchers(_subject: int, _method: StringName,
			_args: Array = []) -> void:
		pass

	func to_one(_peer: int, _method: StringName, _args: Array = []) -> void:
		pass


## Бос без сцени: `_reward` читає лише ці поля.
class FakeBoss extends Node:
	var level := 30
	var is_boss := true
	var kind := 3
	var respect_range: Array = [1, 1]
	var experience_range: Array = [1, 1]
	var drop_table: Array = []


func _ready() -> void:
	_go()


func _yes(text: String, is_ok: bool) -> void:
	if is_ok:
		_ok += 1
		print("  ✓ %s" % text)
	else:
		_bad += 1
		print("  ✗ %s" % text)


func _go() -> void:
	await get_tree().process_frame
	Net.joined = true
	var world: Node3D = MAIN.instantiate()
	get_tree().root.add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame
	var post := Quiet.new(world, null)
	world.link = post
	world.actions._link = post
	world.combat._link = post
	var book: ItemBook = world.data.items
	var smith: Smith = world.data.smith

	print("\n— дані коваля —")
	_yes("правила прочитались", smith.has_rules())
	var metals: Dictionary = smith.rules["зачарування"]["матеріал"]
	var no_essence: Array = []
	var no_metal: Array = []
	for grade: String in ItemBook.GRADES:
		if not book.has("рунна есенція %s" % grade):
			no_essence.append(grade)
		if not book.has(str(metals.get(grade, ""))):
			no_metal.append(grade)
	_yes("есенція є на всі 7 грейдів (бракує: %s)" % [no_essence],
			no_essence.is_empty())
	_yes("метал є на всі 7 грейдів (бракує: %s)" % [no_metal],
			no_metal.is_empty())
	var unsourced: Array = []
	for grade: String in ItemBook.GRADES:
		var metal := str(metals[grade])
		var found := false
		for kind in world.data.mobs:
			var m: Dictionary = world.data.mobs[kind]
			if book.grade_for_level(int(m.get("рівень", 1))) != grade:
				continue
			for row: Dictionary in m.get("дроп", []):
				if row.get("що") == metal:
					found = true
		if not found:
			unsourced.append(metal)
	_yes("кожен метал падає з монстрів свого грейду (ні: %s)" % [unsourced],
			unsourced.is_empty())

	print("\n— міцність —")
	var me: Node = world.spawn(1, Vector3(0, 30, 0))
	me.items = {}
	me.things.clear()
	me.gear.clear()
	var sword: Item = book.make(SWORD)
	var helmet: Item = book.make(HELMET)
	_yes("меч: міцність %d/%d" % [sword.durability, sword.durability_max],
			sword.durability_max == 1000 and sword.durability == 1000)
	_yes("шолом міцності не має", helmet.durability_max == 0)
	var at_sword: int = me.add_thing(sword)
	me.equip(at_sword)
	var strong: int = me.stats.strength
	var blunted := 0
	for _i in 1000:
		if me.wear_weapon(1):
			blunted += 1
	_yes("1000 ударів тупить меч рівно один раз (%d)" % blunted,
			blunted == 1 and sword.is_blunt())
	_yes("тупий меч не дає сили: %d → %d" % [strong, me.stats.strength],
			me.stats.strength == strong - int(sword.stats.get("сила", 0)))
	var fix: int = smith.repair_cost(sword, book)
	var price := int(book.base_of(SWORD)["ціна"])
	_yes("ремонт тупого: %d (ціна %d × 0,3)" % [fix, price],
			fix == maxi(5, roundi(price * 0.3)))
	var why: String = smith.repair(me, at_sword, book)
	_yes("без грошей не лагодить: «%s»" % why, why != "" and sword.is_blunt())
	me.items = {"гроші": 1000}
	why = smith.repair(me, at_sword, book)
	_yes("з грошима лагодить: міцність %d, грошей %d"
			% [sword.durability, int(me.items["гроші"])],
			why == "" and sword.durability == 1000
			and int(me.items["гроші"]) == 1000 - fix)
	_yes("сила вернулась: %d" % me.stats.strength, me.stats.strength == strong)
	_yes("цілу вдруге не лагодить", smith.repair(me, at_sword, book) != "")

	print("\n— магічна чи фізична —")
	var amulet: Item = book.make(AMULET)
	_yes("амулет учня (інтелект) — магічний", smith.is_magic(amulet, book))
	_yes("меч — фізичний", not smith.is_magic(sword, book))
	_yes("шолом — фізичний", not smith.is_magic(helmet, book))

	print("\n— імовірності зачарування —")
	var rng := RandomNumberGenerator.new()
	rng.seed = 21092026
	for item: Item in [amulet, sword]:
		var magic_side := 0
		var n := 4000
		for _i in n:
			var r: Dictionary = smith.roll(item, book, rng)
			var magic_stat := false
			for row: Dictionary in smith.rules["зачарування"]["магічні"]:
				if row["стат"] == r["стат"]:
					magic_stat = true
			magic_side += 1 if magic_stat else 0
		var share := float(magic_side) / n
		var want := 0.75 if smith.is_magic(item, book) else 0.25
		_yes("%s: магічних %.1f%% (очікую %.0f%% ± 3)"
				% [item.base, share * 100, want * 100],
				absf(share - want) < 0.03)
	var sums := 0.0
	for row: Dictionary in smith.chances(true, "E"):
		sums += float(row["шанс"])
	_yes("шанси в таблиці сумуються в 100%% (%.4f)" % sums,
			absf(sums - 1.0) < 0.0001)
	var top := 0
	for row: Dictionary in smith.chances(true, "SS"):
		top = maxi(top, int(row["до"]))
	_yes("на SS розмах більший: до %d (на E до 4)" % top, top > 4)

	print("\n— зачарування —")
	var at_amulet: int = me.add_thing(amulet)
	me.equip(at_amulet)
	me.items = {"гроші": 100000}
	why = smith.enchant(me, at_amulet, book, rng)
	_yes("без есенції й металу відмова: «%s»" % why, why.begins_with("бракує"))
	me.items = {"гроші": 100000, "рунна есенція E": 2, "кора дуба": 6}
	var cost: Dictionary = smith.enchant_cost(amulet, book)
	var stats_before: Dictionary = amulet.stats.duplicate()
	why = smith.enchant(me, at_amulet, book, rng)
	var first: Dictionary = smith.last
	_yes("зачаровано: %s" % Smith.rune_text(first), why == "" and not first.is_empty())
	_yes("забрано: гроші %d, есенція 1, кора 3"
			% int(cost["гроші"]),
			int(me.items["гроші"]) == 100000 - int(cost["гроші"])
			and int(me.items["рунна есенція E"]) == 1
			and int(me.items["кора дуба"]) == 3)
	var stat: String = first["стат"]
	_yes("руна лягла в стати речі: %s %d → %d" % [stat,
			int(stats_before.get(stat, 0)), int(amulet.stats.get(stat, 0))],
			int(amulet.stats.get(stat, 0))
			== int(stats_before.get(stat, 0)) + int(first["скільки"]))
	why = smith.enchant(me, at_amulet, book, rng)
	var second: Dictionary = smith.last
	var added := 0
	for key in amulet.stats:
		added += int(amulet.stats[key]) - int(stats_before.get(key, 0))
	_yes("друга руна замінює першу, не складається (+%d = %d)"
			% [added, int(second["скільки"])],
			why == "" and added == int(second["скільки"]))
	var row: Dictionary = amulet.to_row()
	var back: Item = Item.from_row(row, book)
	_yes("руна й міцність переживають базу: %s, %s" % [
			Smith.rune_text(back.rune), Smith.rune_text(amulet.rune)],
			back.rune == amulet.rune and back.stats == amulet.stats)
	sword.durability = 17
	var sword_back: Item = Item.from_row(sword.to_row(), book)
	_yes("міцність меча з бази: %d/%d" % [sword_back.durability,
			sword_back.durability_max], sword_back.durability == 17)
	sword.durability = 1000

	print("\n— відсоткові руни —")
	amulet.set_rune({"стат": Smith.CAST, "скільки": 10})
	me.refresh_stats()
	_yes("швидкість касту +10%% → бонус %.2f" % me.stats.cast_speed_bonus,
			is_equal_approx(me.stats.cast_speed_bonus, 0.10))
	amulet.set_rune({"стат": Smith.ATTACK_SPEED, "скільки": 10})
	me.refresh_stats()
	_yes("швидкість атаки +10%% → множник %.2f" % me.stats.battle_factor,
			is_equal_approx(me.stats.battle_factor, 1.10))
	amulet.set_rune({"стат": Smith.COOLDOWN, "скільки": 5})
	me.refresh_stats()
	_yes("швидкість відкату +5%% → зріз %.2f" % me.stats.cooldown_cut,
			is_equal_approx(me.stats.cooldown_cut, 0.05))

	print("\n— ремінь і смуги панелі —")
	me.pad_bar()
	_yes("панель на 28 комірок (%d)" % me.bar.size(), me.bar.size() == 28)
	_yes("без ременя одна смуга", me.strips() == 1)
	var belts := {"пояс з кори дуба": 1, "залізний пояс": 2,
			"сталевий пояс": 3, "кістяний пояс": 4}
	for belt: String in belts:
		var at_belt: int = me.add_thing(book.make(belt))
		me.equip(at_belt)
		_yes("%s → смуг %d" % [belt, me.strips()],
				me.strips() == int(belts[belt]))
	var total_belts := 0
	for name: String in book.bases:
		if str(book.base_of(name).get("слот", "")) == "ремінь":
			total_belts += 1
	_yes("ременів у грі рівно 4 (%d)" % total_belts, total_belts == 4)
	me.unequip("ремінь")
	me.bar[8] = "attack"
	me.queue.clear()
	world.actions.use_slot(1, 8, false)
	_yes("без ременя друга смуга не тиснеться", me.queue.is_empty())
	var at_iron: int = me.add_thing(book.make("залізний пояс"))
	me.equip(at_iron)
	world.actions.use_slot(1, 8, false)
	_yes("із залізним поясом (D) тиснеться: черга %s" % [me.queue],
			me.queue.has("attack"))

	print("\n— есенція з боса —")
	var boss := FakeBoss.new()
	me.items = {}
	me.level = 30
	world.combat._reward(1, me, boss)
	var essence := "рунна есенція %s" % book.grade_for_level(30)
	_yes("бос 30 рівня дав «%s» ×%d" % [essence,
			int(me.items.get(essence, 0))],
			int(me.items.get(essence, 0)) >= 1)
	boss.is_boss = false
	me.items = {}
	world.combat._reward(1, me, boss)
	_yes("не-бос есенції не дає", not me.items.has(essence))
	boss.free()

	print("  підсумок: %d з %d" % [_ok, _ok + _bad])
	get_tree().quit(1 if _bad > 0 else 0)
