extends Node
## Артефакт «око бога» (слово замовника 20.09.2026): у торбі — на екрані
## мінікарта, яку можна посунути й згорнути; подвійний клік по речі
## розгортає її назад; другий такий артефакт нічого не додає; продали —
## і карта зникла.
##
## Ганяти так:
##     godot --headless --path game res://scenes/eye.tscn
##     godot --path game res://scenes/eye.tscn -- --знімок <файл.png>
##
## Сценою, а не `--script`: HUD тягне `client_view.gd`, а той — Net,
## і без автозавантажень усе це просто не компілюється. Світу й мережі
## проба не чіпає: порт 24565 може бути грою замовника.

var _ok := 0
var _bad := 0


func _ready() -> void:
	_go()


func _yes(text: String, is_ok: bool) -> void:
	_ok += 1 if is_ok else 0
	_bad += 0 if is_ok else 1
	print("  %s %s" % ["✓" if is_ok else "✗", text])


func _go() -> void:
	await get_tree().process_frame
	_in_data()
	await _in_window()
	print("  підсумок: %s" % ("усе гаразд" if _bad == 0
			else "‼ вад: %d" % _bad))
	await _snapshot()
	get_tree().quit(1 if _bad > 0 else 0)


## Знімок для ока людини: торба з артефактом і розгорнута мінікарта над
## справжнім аркушем світу.
func _snapshot() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--знімок")
	if at < 0 or at + 1 >= args.size() \
			or DisplayServer.get_name() == "headless":
		return
	var data := GameData.new()
	data.load_all()
	var hud := HUD.new()
	add_child(hud)
	hud.setup(self)
	await get_tree().process_frame
	hud.set_things([], _stack(1))
	hud._eye_view.map = data.map
	hud._eye_view.look_close(HUD.EYE_METRES)
	hud._eye_view.show_me(Vector3(0, 12, 0), 0.6)
	hud._toggle_things()
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args[at + 1])
	print("[знімок] %s" % args[at + 1])


func _in_data() -> void:
	print("\n— річ у даних —")
	var data := GameData.new()
	data.load_all()
	var book: ItemBook = data.items
	_yes("база «%s» є" % HUD.EYE_ITEM, book.has(HUD.EYE_ITEM))
	_yes("вид — артефакт", book.kind_of(HUD.EYE_ITEM) == "артефакт")
	# Складана: «більше одного нічого не додає», тож другий має лягати
	# числом у ту саму комірку, а не займати нову.
	_yes("складана", book.is_stackable(HUD.EYE_ITEM))
	var base: Dictionary = book.base_of(HUD.EYE_ITEM)
	_yes("ціна більша за нуль — є що продати",
			int(base.get("ціна", 0)) > 0)
	var from: Array = []
	for kind: String in data.mobs:
		if kind == "_про":
			continue
		for drop: Dictionary in data.mobs[kind].get("дроп", []):
			if str(drop.get("що", "")) == HUD.EYE_ITEM:
				from.append(str(data.mobs[kind]["назва"]))
	print("    падає з: %s" % ", ".join(PackedStringArray(from)))
	_yes("є з кого вибити", not from.is_empty())


func _stack(count: int) -> Array:
	return [{"назва": HUD.EYE_ITEM, "вид": "артефакт", "грейд": "SS",
			 "скільки": count, "придатна": false},
			{"назва": "гроші", "вид": "гроші", "грейд": "",
			 "скільки": 100, "придатна": false}]


func _cell_with_eye(hud: HUD) -> Button:
	for cell: Dictionary in hud._bag_cells:
		var press: Button = cell["press"]
		if press.tooltip_text.begins_with(HUD.EYE_ITEM):
			return press
	return null


func _in_window() -> void:
	print("\n— мінікарта —")
	var hud := HUD.new()
	add_child(hud)
	hud.setup(self)
	await get_tree().process_frame

	hud.set_things([], [{"назва": "гроші", "вид": "гроші", "грейд": "",
			"скільки": 100, "придатна": false}])
	await get_tree().process_frame
	_yes("без артефакта карти немає", not hud._eye_box.visible)

	hud.set_things([], _stack(1))
	await get_tree().process_frame
	_yes("артефакт з'явився — карта розгорнулась", hud._eye_box.visible)
	_yes("карта йде за гравцем", hud._eye_view.follow_me)

	# Хрестик вікна — це і є «згорнути в інвентар».
	hud._eye_box.visible = false
	hud.set_things([], _stack(2))
	await get_tree().process_frame
	_yes("другий артефакт нічого не додає: згорнута лишилась згорнутою",
			not hud._eye_box.visible)

	var press: Button = _cell_with_eye(hud)
	_yes("річ є в торбі окремою коміркою", press != null)
	if press != null:
		_yes("комірка жива (подвійний клік дійде)", not press.disabled)
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.double_click = true
		press.gui_input.emit(click)
		await get_tree().process_frame
		_yes("подвійний клік розгорнув карту", hud._eye_box.visible)
		press.gui_input.emit(click)
		await get_tree().process_frame
		_yes("ще один подвійний клік згорнув", not hud._eye_box.visible)

	hud._eye_box.visible = true
	hud.set_things([], [{"назва": "гроші", "вид": "гроші", "грейд": "",
			"скільки": 100, "придатна": false}])
	await get_tree().process_frame
	_yes("продали (артефакт зник) — карта зникла теж",
			not hud._eye_box.visible)

	# Посунути й згорнути: вікно тягається за заголовок, як усі інші.
	hud._has_eye = true
	hud._eye_box.visible = true
	var was: Vector2 = hud._eye_box.position
	hud._eye_box.position = was + Vector2(120, 60)
	hud._toggle_eye()
	hud._toggle_eye()
	_yes("посунуту карту згортання не вертає на місце",
			hud._eye_box.position != was)
	hud.queue_free()
