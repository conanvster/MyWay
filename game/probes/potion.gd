extends Node
## Зілля лікування (слово замовника 19.09.2026: «створи зілля лікування і
## додай в магазин, його можна додати в панель і використати під час бою,
## зілля піднімає 500 хп»).
##
##     godot --headless --path game res://scenes/potion.tscn -- --світ1

const MAIN := preload("res://scenes/main.tscn")
const POTION := "зілля лікування"

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
	print("\n— зілля лікування —")

	var land: Node = world.get_node("Landscape")
	var seller: NPC = null
	for child in land.get_children():
		if child is NPC and child.trades():
			seller = child
			break
	_yes("крамар світу 1 продає зілля", seller != null
			and seller.goods.has(POTION))
	var bare := NPC.new()
	bare.craft = "крамар"
	land.add_child(bare)
	world._stock_merchants(land)
	_yes("крамар без свого переліку (світ 2) продає зілля й торгує",
			bare.trades() and bare.goods.has(POTION))
	var goods: Array = world.shop.goods_of({"товар": bare.goods})
	var price := -1
	for row: Dictionary in goods:
		if row["назва"] == POTION:
			price = int(row["ціна"])
	_yes("у крамниці зілля за %d" % price, price > 0)

	var me: Node = world.spawn(1, Vector3(0, 30, 0))
	me.items = {POTION: 2}
	var top: int = me.stats.max_hp()
	me.hp = 10
	world.actions.use_item(1, POTION)
	_yes("зілля: здоров'я 10 → %d (максимум %d, зілля до 500)"
			% [me.hp, top], me.hp == mini(top, 510))
	_yes("витрачено одне: лишилось %d" % int(me.items.get(POTION, 0)),
			int(me.items.get(POTION, 0)) == 1)
	post.said.clear()
	world.actions.use_item(1, POTION)
	_yes("при повному здоров'ї не п'ється: «%s»" % ", ".join(post.said),
			int(me.items.get(POTION, 0)) == 1)
	# Великий запас здоров'я: зілля дає рівно 500, не більше.
	me.base_stats.stamina = 200
	me.refresh_stats()
	me.hp = 100
	world.actions.use_item(1, POTION)
	_yes("великий запас: +%d (рівно 500)" % (me.hp - 100), me.hp == 600)

	_yes("на панель можна: зілля", world.bar_allows(me,
			Actions.ITEM_PREFIX + POTION))
	_yes("на панель не можна: річ без дії (меч)", not world.bar_allows(me,
			Actions.ITEM_PREFIX + "меч з кори дуба"))
	me.items = {POTION: 3}
	var hud := HUD.new()
	get_tree().root.add_child(hud)
	hud.setup(world)
	await get_tree().process_frame
	var button := Button.new()
	get_tree().root.add_child(button)
	var carried: Dictionary = hud._bag_drag(button, POTION)
	var cell := BarCell.new()
	_yes("торба віддає «%s», панель приймає" % carried.get("дія", "—"),
			carried.get("дія", "") == Actions.ITEM_PREFIX + POTION
			and cell._can_drop_data(Vector2.ZERO, carried))
	_yes("значок зілля є", ItemIcon.of(POTION) != null)

	print("  підсумок: %d з %d" % [_ok, _ok + _bad])
	get_tree().quit(1 if _bad > 0 else 0)
