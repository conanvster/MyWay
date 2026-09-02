extends SceneTree
## Проба панелі: чи справді скіл можна перекласти й чи не покладеш чужого.
##
## Ганяти так:
##     godot --headless --path game --script res://probes/bar.gd
##
## Перевіряє три речі:
##   1. вікно «Скіли» показує те, що вивчено, і віддає дані перетягування;
##   2. комірка панелі приймає кинуте, а дві комірки міняються місцями;
##   3. розкладка переживає збереження — інакше її довелось би складати
##      щоразу заново.

const AVATAR := preload("res://scenes/avatar.tscn")


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	await _window()
	_saving()
	quit()


func _window() -> void:
	print("\n— вікно «Скіли» й перетягування —")
	var hud := HUD.new()
	root.add_child(hud)
	hud.setup(root)
	await process_frame

	var bar := ["attack", "next_mob", "скіл:енергетичний-промінь",
			"скіл:енергетичний-вибух", "taunt", "next_player", "corpse_skill"]
	hud.set_bar(bar)
	hud.set_skills([
		{"ключ": "енергетичний-вибух", "назва": "енергетичний вибух",
		 "грейд": "E", "рівень": 1, "рівнів": 3, "мана": 8, "дальність": 4.0},
		{"ключ": "енергетичний-промінь", "назва": "енергетичний промінь",
		 "грейд": "E", "рівень": 2, "рівнів": 4, "мана": 17, "дальність": 13.0}])
	await process_frame

	var grid: GridContainer = hud.find_child("Сітка", true, false)
	print("  комірок у вікні: %d" % grid.get_child_count())
	for cell in grid.get_children():
		print("    %s (ключ %s)" % [cell.title, cell.key])

	# Те саме, що робить миша: беремо дані перетягування зі скіла.
	var dragged: Variant = grid.get_child(0)._get_drag_data(Vector2.ZERO)
	print("  що тягнемо: %s" % [dragged])

	# І кидаємо на комірку 5 (індекс 4, там зараз «агресія»).
	var asked: Array = []
	hud.wants_slot.connect(func(where: int, action: String) -> void:
			asked.append([where, action]))
	var cells: Array = []
	for node in hud.find_children("*", "BarCell", true, false):
		cells.append(node)
	print("  комірок панелі: %d" % cells.size())
	cells[4]._drop_data(Vector2.ZERO, dragged)
	print("  попросили сервер: %s (чекаю [[4, скіл:енергетичний-вибух]])"
			% [asked])

	# Перетягування з комірки в комірку: мають помінятись місцями.
	asked.clear()
	var from_cell: Variant = cells[0]._get_drag_data(Vector2.ZERO)
	cells[1]._drop_data(Vector2.ZERO, from_cell)
	print("  міняємо 1 і 2 місцями -> %s" % [asked])
	print("  (перше — куди поїхало старе з другої, друге — що поклали)")
	hud.queue_free()


func _saving() -> void:
	print("\n— розкладка переживає збереження —")
	var hero: Node3D = AVATAR.instantiate()
	root.add_child(hero)
	hero.bar.assign(["attack", "скіл:енергетичний-промінь", "", "", "", "", ""])
	var row := Store.row_of("Проба", hero)
	print("  у рядок пішло: %s" % [row.get("bar")])

	var other: Node3D = AVATAR.instantiate()
	root.add_child(other)
	print("  у нового типова: %s" % [other.bar])
	Store.apply_row(other, row)
	print("  після читання:  %s" % [other.bar])
	Store.apply_row(other, {"bar": []})
	print("  порожня в базі нічого не ламає: %s" % [other.bar])
	hero.queue_free()
	other.queue_free()
