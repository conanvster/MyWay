extends Node
## Світи розділені (П-204) і основним став другий (П-205).
##
## Слова замовника 19.09.2026: «логін пароль один й той самий, але в
## залежності від вибраного світу будуть свої аватари-перси, мабуть
## варто в лаунчері дожати можливість вибрати світ» і «хочу перевести
## Світ 1 в неактивний — використовувати тільки для тесту чогось, а
## основним зробити Світ 2».
##
## Привід: персонаж `Alex` зберігся в світі 2 з координатою -1748 м і
## потрапляв у перелік світу 600 м — тобто поза картою.
##
## Ганяти так (сценою, бо потрібні автозавантаження):
##     godot --headless --path game res://scenes/worlds.tscn
##     godot --headless --path game res://scenes/worlds.tscn -- --світ1

const LAUNCHER := preload("res://scripts/launcher.gd")

var _ok := 0
var _bad := 0


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
	var by_flag := GameData.map_path()
	var asked_first := OS.get_cmdline_user_args().has("--світ1")

	print("\n— який світ основний (П-205) —")
	_yes("без прапорців береться світ 2: %s" % GameData.world_key(),
			asked_first or GameData.world_key() == "map2.json")
	_yes("--світ1 дає світ 600 м: %s" % GameData.world_key(),
			not asked_first or GameData.world_key() == "map.json")

	print("\n— вибір світу на стартовій сторінці (П-204) —")
	var page: Control = LAUNCHER.new()
	get_tree().root.add_child(page)
	await get_tree().process_frame
	var pick: OptionButton = page._world_pick
	_yes("у переліку два світи, основний перший (%s)"
			% pick.get_item_text(0),
			pick.item_count == 2
					and str(pick.get_item_metadata(0)) == GameData.MAP2_PATH)
	_yes("вибрано те, з чим відкрито сторінку (%s)" % by_flag,
			str(pick.get_item_metadata(pick.selected)) == by_flag)

	# Сервер — процес окремий, і світ йому йде прапорцем. Саме тут
	# ховалась вада: при виборі світу 1 прапорець не додавався зовсім,
	# і сервер підіймався б у світі 2.
	for at in 2:
		pick.item_selected.emit(at)
		await get_tree().process_frame
		var want: String = str(pick.get_item_metadata(at))
		var args: Array = page._server_args()
		var flag := "--світ1" if want == GameData.MAP_PATH else "--світ2"
		_yes("обрано «%s» — серверові йде %s"
				% [pick.get_item_text(at), flag],
				GameData.map_path() == want and args.has(flag))

	print("\n— персонаж знає свій світ (П-204) —")
	GameData.chosen_map = GameData.MAP2_PATH
	var world_two := GameData.world_key()
	GameData.chosen_map = GameData.MAP_PATH
	var world_one := GameData.world_key()
	_yes("світи звуться по-різному: «%s» і «%s»" % [world_two, world_one],
			world_two != world_one and world_two == "map2.json"
					and world_one == "map.json")

	GameData.chosen_map = by_flag
	print("\n  пройдено %d · провалено %d" % [_ok, _bad])
	get_tree().quit(1 if _bad > 0 else 0)
