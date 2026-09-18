extends Node
## Перевірка місця при вході (слово замовника 19.09.2026).
##
## Замовник провалився крізь землю в столиці світу 2, вийшов із гри, і
## сервер зберіг у базі `y = -156 895`. Кожен наступний вхід клав його
## назад у те саме падіння: гравець тонув, не встигши нічого зробити.
## Позиція з бази бралась на віру — `Store.apply_row` ставив її як є.
##
## Слово замовника: «необхідно зробити так щоб кожного разу підчас
## заходу в гру перевірялось чи доступне місце, можливо воно зникло, чи
## змінилось, то телепортувати гравця в найближче місто».
##
## Ганяти так (сценою, бо потрібні автозавантаження):
##     godot --headless --path game res://scenes/rescue.tscn
##     godot --headless --path game res://scenes/rescue.tscn -- --світ2

const MAIN := preload("res://scenes/main.tscn")

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


## Світ будує себе сам у `_ready` — другий раз не будуємо: у версії 2 це
## 74 тисячі рослин удруге, і проба просто висла.
func _go() -> void:
	await get_tree().process_frame
	var world: Node3D = MAIN.instantiate()
	get_tree().root.add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame
	var land: Node = world.get_node("Landscape")
	var towns: Array = land.towns()
	var side: float = float(
			world.data.map.get("земля", {}).get("сторона", 600.0))
	print("\n— чи доступне місце при вході (світ %.0f м, міст %d) —"
			% [side, towns.size()])

	var me: Node3D = world.spawn(1, Vector3(0, world.ground_at(0, 0) + 6, 0))

	# 1. Ціле місце не рухається: рятунок не переносить без причини.
	var floor_y: float = world.ground_at(19.0, -1.25)
	var good := Vector3(19.0, floor_y + 1.0, -1.25)
	me.place_at(good, 0.0)
	world._rescue(me, "проба")
	_yes("ціле місце лишилось на місці (y %.2f)" % me.global_position.y,
			me.global_position.is_equal_approx(good))

	# 2. Метр під землею — ще схил, а не дірка.
	var slope := Vector3(19.0, floor_y - 1.0, -1.25)
	me.place_at(slope, 0.0)
	world._rescue(me, "проба")
	_yes("метр під землею — не вважається падінням",
			me.global_position.is_equal_approx(slope))

	# 3. Те саме число, що замовник знайшов у базі.
	me.place_at(Vector3(19.181969, -156895.19, -1.2538514), 0.0)
	world._rescue(me, "проба")
	var here: Vector3 = me.global_position
	_yes("y = -156 895 більше не лишає в падінні: y %.2f" % here.y,
			here.y > world.ground_at(here.x, here.z) - 0.01)
	_yes("переніс саме в місто (%.0f, %.0f)" % [here.x, here.z],
			_is_town(towns, here))

	# 4. Поза межами світу — теж у місто. Сюди ж потрапляє підземелля,
	#    яке закрилось: вони не зберігаються між запусками сервера.
	me.place_at(Vector3(side * 4.0, 50.0, side * 4.0), 0.0)
	world._rescue(me, "проба")
	_yes("за межами світу — вернуло в місто (%.0f, %.0f)"
			% [me.global_position.x, me.global_position.z],
			_is_town(towns, me.global_position))

	# 5. Місто саме НАЙБЛИЖЧЕ, а не завжди столиця.
	_far_town(world, land, me, towns)

	print("\n  пройдено %d · провалено %d" % [_ok, _bad])
	get_tree().quit(1 if _bad > 0 else 0)


## Чи стоїть точка в якомусь із міст мапи (по центру, з запасом).
func _is_town(towns: Array, at: Vector3) -> bool:
	for town: Dictionary in towns:
		var mid: Array = town.get("центр", [0, 0, 0])
		if absf(at.x - float(mid[0])) < 0.5 \
				and absf(at.z - float(mid[2])) < 0.5:
			return true
	return false


## Провалитись біля найдальшого міста й перевірити, що вернуло саме до
## нього. У світі 600 м місто одне — тоді перевіряти нема чого.
func _far_town(world: Node3D, _land: Node, me: Node3D, towns: Array) -> void:
	if towns.size() < 2:
		print("  (міст у мапі одне — «найближче» перевіряти нема на чому)")
		return
	var last: Array = towns[towns.size() - 1].get("центр", [0, 0, 0])
	var x := float(last[0]) + 40.0
	var z := float(last[2]) + 40.0
	me.place_at(Vector3(x, world.ground_at(x, z) - 900.0, z), 0.0)
	world._rescue(me, "проба")
	var at: Vector3 = me.global_position
	_yes("провалився біля (%.0f, %.0f) — вернуло до (%.0f, %.0f), а не в столицю"
			% [x, z, at.x, at.z],
			absf(at.x - float(last[0])) < 0.5
					and absf(at.z - float(last[2])) < 0.5)
