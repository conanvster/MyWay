extends Node
## Речі на землі (П-160): викинути, видалити, підняти, загубити при смерті.
##
## Слово замовника 01.10.2026: «зроби додаткову дію — підняти річ, можна
## підняти застакані речі, можна викинути річ, або видалити в інвенторі.
## Можна викинути довільну кількість речей, вказавши кількість».
##
## Перевіряємо числами: скільки лягло, скільки лишилось у торбі, що
## піднята річ та сама (афікси, міцність, руна), що стос складається, що
## далека річ не піднімається, що строк минає, що показ малює кожну річ
## спрощеним зображенням і прибирає підняту.
##
##     godot --headless --path game res://scenes/ground.tscn -- --світ1
##     godot --path game res://scenes/ground.tscn -- --світ1 \
##             --знімок <файл.png>

const MAIN := preload("res://scenes/main.tscn")
const SWORD := "меч з кори дуба"
const BARK := "кора дуба"

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
	world.combat._link = post
	var book: ItemBook = world.data.items
	var ground: Ground = world.ground
	_yes("світ, бій і дії мають ту саму землю",
			world.combat.ground == ground and world.actions.ground == ground)

	var me: Node = world.spawn(1, Vector3(0, 30, 0))
	me.items = {}
	me.things.clear()
	me.gear.clear()

	print("\n— викинути поодиноку —")
	var sword: Item = book.make(SWORD)
	sword.durability = 417
	sword.set_rune({"стат": "сила", "скільки": 2})
	var at: int = me.add_thing(sword)
	_yes("викинути вдягнене не можна", (func() -> bool:
			me.equip(at)
			var why := ground.drop_thing(me, at)
			me.unequip("зброя")
			return why != "" and ground.lying.is_empty()).call())
	_yes("викинуто з торби", ground.drop_thing(me, at) == ""
			and me.things.is_empty() and ground.lying.size() == 1)
	var key: int = ground.lying.keys()[0]
	var spot: Vector3 = ground.lying[key]["де"]
	_yes("лягла під ноги (%.2f м)" % spot.distance_to(me.global_position),
			spot.distance_to(me.global_position) <= Ground.SPREAD + 0.01)
	_yes("на землі та сама річ", ground.lying[key]["річ"] == sword)

	print("\n— викинути кількість зі стосу —")
	me.items = {BARK: 10}
	_yes("викинуто 4 з 10", ground.drop_stack(me, BARK, 4, book) == ""
			and int(me.items[BARK]) == 6)
	_yes("більше, ніж є, не викидається: 99 → 6",
			ground.drop_stack(me, BARK, 99, book) == ""
			and not me.items.has(BARK))
	var stacks := 0
	var lying_bark := 0
	for k: int in ground.lying:
		if ground.lying[k]["річ"] == null:
			stacks += 1
			lying_bark += int(ground.lying[k]["скільки"])
	_yes("на землі два стоси, разом %d кори" % lying_bark,
			stacks == 2 and lying_bark == 10)
	_yes("нуль не викидається", ground.drop_stack(me, BARK, 0, book) != "")
	_yes("чого немає — не викидається",
			ground.drop_stack(me, "сталь", 1, book) != "")

	print("\n— підняти —")
	post.said.clear()
	var picked := 0
	while world.actions.pick_up(1):
		picked += 1
	_yes("дія «підняти» зібрала все по черзі: %d" % picked, picked == 3)
	_yes("останнє натискання каже «поруч нічого»: %s" % [post.said.back()],
			str(post.said.back()) == "поруч нічого не лежить")
	_yes("стоси склались у торбі: кора ×%d" % int(me.items.get(BARK, 0)),
			int(me.items.get(BARK, 0)) == 10)
	_yes("меч повернувся тим самим (міцність %d, руна %s)"
			% [sword.durability, sword.rune],
			me.things.size() == 1 and me.things[0] == sword
			and sword.durability == 417 and sword.rune["скільки"] == 2)
	_yes("на землі порожньо", ground.lying.is_empty())

	var far: Vector3 = me.global_position + Vector3(Ground.REACH + 2.0, 0, 0)
	ground.put_stack(BARK, 3, far, book)
	_yes("далеку річ не піднімає", not world.actions.pick_up(1)
			and ground.lying.size() == 1)
	ground.lying.clear()

	# Через чергу дій, як із панелі: «pick_up» — базове вміння.
	_yes("«підняти» кладеться на панель", world.bar_allows(me, "pick_up"))
	ground.put_stack(BARK, 2, me.global_position, book)
	me.queue.assign(["pick_up"])
	world.actions.pump(1)
	_yes("з черги піднімає: кора ×%d" % int(me.items.get(BARK, 0)),
			int(me.items.get(BARK, 0)) == 12 and ground.lying.is_empty())

	print("\n— видалити —")
	_yes("видалено 5 кори з 12", ground.destroy_stack(me, BARK, 5) == ""
			and int(me.items[BARK]) == 7 and ground.lying.is_empty())
	_yes("видалено меч", ground.destroy_thing(me, 0) == ""
			and me.things.is_empty() and ground.lying.is_empty())

	print("\n— строк —")
	ground.put_stack(BARK, 1, me.global_position, book)
	ground.changed = false
	ground.tick(Ground.LIFETIME - 1.0)
	_yes("за секунду до строку ще лежить", ground.lying.size() == 1
			and not ground.changed)
	ground.tick(2.0)
	_yes("після строку зникла й світ знає", ground.lying.is_empty()
			and ground.changed)

	print("\n— смерть —")
	var grid: Dictionary = world.combat.progress.grid
	var was: Variant = grid.get("втрата речей")
	grid["втрата речей"] = {"ресурси": 1.0, "лут": 1.0, "вдягнене": 0.0}
	me.items = {BARK: 7, "гроші": 50}
	me.things.clear()
	me.gear.clear()
	me.add_thing(book.make(SWORD))
	var lost: Array = world.combat.progress.lose_items(me, book, ground)
	_yes("загублене лягло на землю: %s" % [lost], lost.size() == 2
			and ground.lying.size() == 2)
	_yes("гроші не губляться", int(me.items.get("гроші", 0)) == 50)
	grid["втрата речей"] = was

	print("\n— показ —")
	var view: ClientView = world.view
	view.set_ground(ground.rows())
	_yes("показано %d з %d" % [view.ground_shown(), ground.lying.size()],
			view.ground_shown() == 2)
	var pictures := 0
	for node: Node in world.get_children():
		if str(node.name).begins_with("НаЗемлі"):
			for child: Node in node.get_children():
				if child is Sprite3D and child.texture != null:
					pictures += 1
	_yes("обидві — зображенням (%d)" % pictures, pictures == 2)
	ground.pick_up(me)
	view.set_ground(ground.rows())
	_yes("підняту показ прибрав: лишилась %d" % view.ground_shown(),
			view.ground_shown() == 1)

	var missing: Array = []
	for name: String in book.bases:
		if not ResourceLoader.exists(ClientView.GROUND_ART + name + ".png"):
			missing.append(name)
	print("  без спрощеного зображення %d речей (плитка грейду): %s…"
			% [missing.size(), missing.slice(0, 4)])
	_yes("зображення є в усіх речей зі значком",
			missing.size() == book.bases.size() - _with_icon(book))

	print("  підсумок: %d з %d" % [_ok, _ok + _bad])
	await _snapshot(world, me, book)
	get_tree().quit(1 if _bad > 0 else 0)


## Знімок для ока людини: кілька різних речей на справжній землі світу,
## камера з-за спини, як у грі.
func _snapshot(world: Node3D, me: Node, book: ItemBook) -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--знімок")
	if at < 0 or at + 1 >= args.size() \
			or DisplayServer.get_name() == "headless":
		return
	var ground: Ground = world.ground
	ground.lying.clear()
	var p: Vector3 = me.global_position
	p.y = world.ground_at(p.x, p.z) + 0.5
	var spots := [Vector3(-1.2, 0, 0), Vector3(0, 0, 0), Vector3(1.2, 0, 0),
			Vector3(-0.6, 0, 1.1), Vector3(0.7, 0, 1.2)]
	ground.put_thing(book.make(SWORD), p + spots[0])
	ground.put_stack(BARK, 5, p + spots[1], book)
	ground.put_stack("зілля лікування", 3, p + spots[2], book)
	ground.put_thing(book.make("залізні чоботи"), p + spots[3])
	ground.put_thing(book.make("обсидіановий меч"), p + spots[4])
	# Розсип `_put` тут заважає роздивитись: ставимо рівно в точки.
	var i := 0
	for key: int in ground.lying:
		ground.lying[key]["де"] = p + spots[i]
		i += 1
	me.visible = false
	world.view.set_ground(ground.rows())
	var eye := Camera3D.new()
	world.add_child(eye)
	eye.position = p + Vector3(0, 2.6, 3.4)
	eye.look_at(p + Vector3(0, 0, 0.4))
	eye.current = true
	for _f in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args[at + 1])
	print("[знімок] %s" % args[at + 1])


func _with_icon(book: ItemBook) -> int:
	var n := 0
	for name: String in book.bases:
		if ItemIcon.of(name) != null:
			n += 1
	return n
