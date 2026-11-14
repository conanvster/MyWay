extends Node
## Позначка смерті на карті й повтор затиснутої клавіші (слово замовника
## 14.11.2026): «додай позначку на карті, щоб було видно, де лежать речі
## останній раз або два рази вбитого … якщо затиснути кнопку, наприклад
## 1, — буде робити повтор дії … через 0.3 сек».
##
## Перевіряємо числами:
##   • сервер шле загиблому `client_death_mark` з місцем і кількістю
##     загубленого — лише коли щось справді впало (погоджений бій і
##     порожня торба — без позначки);
##   • HUD тримає дві останні, новіша перша, обидві карти бачать той самий
##     масив; карта малює їх без помилок;
##   • затиснута «1» тисне комірку одразу й далі раз на 0,3 с; відпустили —
##     стоп; Ctrl+1 повторює саме комірку смуги 2.
##
##     godot --headless --path game res://scenes/death_mark.tscn -- --світ2

const MAIN := preload("res://scenes/main.tscn")
const BARK := "кора дуба"

var _ok := 0
var _bad := 0


class Quiet extends Messenger:
	var marks: Array = []
	var slots: Array = []

	func notice(_id: int, _text: String) -> void:
		pass

	func to_all(_method: StringName, _args: Array = []) -> void:
		pass

	func to_watchers(_subject: int, _method: StringName,
			_args: Array = []) -> void:
		pass

	func to_one(peer: int, method: StringName, args: Array = []) -> void:
		if method == &"client_death_mark":
			marks.append([peer] + args)

	func to_server(method: StringName, args: Array = []) -> void:
		if method == &"use_slot":
			slots.append(args)


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
	Net.joined = true  # проба не в мережу: порт 24565 — гра замовника
	var world: Node3D = MAIN.instantiate()
	get_tree().root.add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame
	var post := Quiet.new(world, null)
	world.link = post
	world.actions._link = post
	world.combat._link = post
	world.view._link = post

	_server_side(world, post)
	_hud_side()
	await _hold_key(world, post)

	print("  підсумок: %d з %d" % [_ok, _ok + _bad])
	await _snapshot(world)
	get_tree().quit(1 if _bad > 0 else 0)


## Знімок для ока людини: велика карта й «око бога» з двома позначками
## біля гравця — новіша яскрава, старша бліда.
func _snapshot(world: Node3D) -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--знімок")
	if at < 0 or at + 1 >= args.size() \
			or DisplayServer.get_name() == "headless":
		return
	var hud: HUD = world.hud if world.get("hud") != null else null
	if hud == null:
		hud = HUD.new()
		add_child(hud)
		hud.setup(world)
	var me := Vector3(40, 12, -30)
	hud.add_death_mark(me + Vector3(-90, 0, 60), 2)
	hud.add_death_mark(me + Vector3(35, 0, -25), 5)
	hud._map_view.map = world.data.map
	hud._map_box.visible = true
	hud._map_view.look_close(500.0)
	hud._map_view.show_me(me, 0.6)
	hud._map_view.center_on_me()
	hud._eye_view.map = world.data.map
	hud._eye_box.visible = true
	hud._eye_view.look_close(HUD.EYE_METRES)
	hud._eye_view.show_me(me, 0.6)
	hud._eye_view.center_on_me()
	for _f in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args[at + 1])
	print("[знімок] %s" % args[at + 1])


func _victim(world: Node3D, id: int, at: Vector3) -> Node:
	var who: Node = world.spawn(id, at)
	who.items = {BARK: 5}
	who.things.clear()
	who.gear.clear()
	return who


func _server_side(world: Node3D, post: Quiet) -> void:
	print("\n— сервер: позначка смерті —")
	var grid: Dictionary = world.combat.progress.grid
	var was: Variant = grid.get("втрата речей")
	grid["втрата речей"] = {"ресурси": 1.0, "лут": 1.0, "вдягнене": 0.0}

	var pve := _victim(world, 4, Vector3(8, 30, 0))
	var died_at: Vector3 = pve.global_position
	var lying_before: int = world.ground.lying.size()
	world.combat._kill(-1, null, pve, 4)
	var fell: int = world.ground.lying.size() - lying_before
	_yes("убив монстр — одна позначка", post.marks.size() == 1)
	if post.marks.size() == 1:
		var m: Array = post.marks[0]
		_yes("позначка тому, хто загинув (%d)" % m[0], m[0] == 4)
		_yes("місце — де загинув (%.2f м)" % died_at.distance_to(m[1]),
				died_at.distance_to(m[1]) < 0.01)
		_yes("кількість = що лягло на землю (%d і %d)" % [m[2], fell],
				m[2] == fell and fell > 0)
		# Речі лежать у межах розсипу від позначки — по ній їх і знайдуть.
		var far := 0.0
		for key: int in world.ground.lying:
			var p: Vector3 = world.ground.lying[key]["де"]
			far = maxf(far, Vector2(died_at.x - p.x, died_at.z - p.z).length())
		_yes("речі не далі розсипу від позначки (%.2f м)" % far,
				far <= Ground.SPREAD + 0.01)

	var duel := _victim(world, 5, Vector3(5, 30, 2))
	var killer: Node = world.spawn(2, Vector3(6, 30, 0))
	world.combat.agreed_pvp = func(_k: int, _v: int) -> bool: return true
	world.combat._kill(2, killer, duel, 5)
	world.combat.agreed_pvp = Callable()
	_yes("погоджений бій — речі при ньому, позначки нема",
			post.marks.size() == 1)

	var empty: Node = world.spawn(6, Vector3(3, 30, 3))
	empty.items = {}
	empty.things.clear()
	empty.gear.clear()
	world.combat._kill(-1, null, empty, 6)
	_yes("нічого не впало — позначки нема", post.marks.size() == 1)
	grid["втрата речей"] = was


func _hud_side() -> void:
	print("\n— HUD і карта: дві останні —")
	var hud := HUD.new()
	add_child(hud)
	hud.setup(self)
	hud.add_death_mark(Vector3(1, 0, 1), 2)
	hud.add_death_mark(Vector3(2, 0, 2), 3)
	hud.add_death_mark(Vector3(3, 0, 3), 4)
	var kept: Array = hud.death_marks()
	_yes("тримає дві (%d)" % kept.size(), kept.size() == HUD.DEATH_MARKS)
	_yes("новіша перша, найстаршу забуто",
			kept[0]["скільки"] == 4 and kept[1]["скільки"] == 3)
	_yes("велика карта й «око бога» бачать той самий перелік",
			is_same(hud._map_view.deaths, kept)
			and is_same(hud._eye_view.deaths, kept))
	hud.queue_free()


func _key(code: Key, down: bool, ctrl := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	e.ctrl_pressed = ctrl
	Input.parse_input_event(e)
	return e


func _run(view: ClientView, seconds: float) -> void:
	var step := 1.0 / 60.0
	var t := 0.0
	while t < seconds - 0.0001:
		view.repeat_held(step)
		t += step


func _hold_key(world: Node3D, post: Quiet) -> void:
	print("\n— затиснута клавіша —")
	var view: ClientView = world.view
	# Час утримання задає лише `_run`: свій `_process` світу на повільних
	# кадрах (вікно на llvmpipe) підганяв би повтор поміж кроками проби.
	world.set_process(false)
	world.spawn(world.multiplayer.get_unique_id(), Vector3(0, 30, 0))
	post.slots.clear()
	_key(KEY_1, true)  # подію світові доставляє сам Input → view.input
	await get_tree().process_frame
	_yes("натиснув — одразу раз (%d)" % post.slots.size(),
			post.slots.size() == 1)
	_run(view, 0.25)
	_yes("до 0,3 с повтору нема (%d)" % post.slots.size(),
			post.slots.size() == 1)
	_run(view, 0.1)
	_yes("на 0,3 с — повтор (%d)" % post.slots.size(), post.slots.size() == 2)
	_run(view, 1.0)  # усього ~1,35 с утримання
	_yes("за 1,35 с — 1 + 4 (%d)" % post.slots.size(), post.slots.size() == 5)
	_yes("тисне ту саму комірку 0", post.slots.all(
			func(a: Array) -> bool: return a[0] == 0))
	_key(KEY_1, false)
	await get_tree().process_frame
	_run(view, 1.0)
	_yes("відпустив — стоп (%d)" % post.slots.size(), post.slots.size() == 5)

	post.slots.clear()
	_key(KEY_1, true, true)
	await get_tree().process_frame
	_run(view, 0.7)
	_yes("Ctrl+1 — комірка 7, раз + два повтори (%s)" % [post.slots],
			post.slots.size() == 3 and post.slots.all(
				func(a: Array) -> bool: return a[0] == 7))
	_key(KEY_1, false, true)
	await get_tree().process_frame
	_run(view, 0.5)
	_yes("відпустив — стоп", post.slots.size() == 3)
	world.set_process(true)
