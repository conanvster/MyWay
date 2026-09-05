extends SceneTree
## Світ версії 2: чи збігається побудована земля з намальованою картою.
##
## Питання, на які проба відповідає числами, а не картинкою:
## скільки коштує побудова · чи берегова лінія в грі та сама, що на
## карті · чи столиця стоїть у (0,0) · чи всі 25 іменних об'єктів
## стоять на сухому · чи можна ходити схилами · чи не тоне ліс.
##
## Ганяти так:
##     godot --headless --path game --script res://probes/world2.gd

const MAIN := preload("res://scenes/main.tscn")
const MAP2 := "res://data/map2.json"
## Скільки точок кидаємо для звірки з полем.
const PROBES := 4000
## Крутіше за це не піднімешся: `floor_max_angle` у Godot типово 45°.
const CLIMB_LIMIT := 45.0

var _bad := 0


func _init() -> void:
	call_deferred("_go")


func _fail(text: String) -> void:
	_bad += 1
	print("  ‼ " + text)


func _rss_mib() -> float:
	var f := FileAccess.open("/proc/self/statm", FileAccess.READ)
	if f == null:
		return -1.0
	var parts := f.get_line().split(" ")
	return float(parts[1]) * 4096.0 / 1048576.0 if parts.size() > 1 else -1.0


func _go() -> void:
	await process_frame
	var text := FileAccess.get_file_as_string(MAP2)
	if text.is_empty():
		print("‼ немає %s — спершу `python3 tools/svit2.py`" % MAP2)
		quit(1)
		return
	var map: Dictionary = JSON.parse_string(text)
	var earth: Dictionary = map["земля"]
	var side: float = float(earth["сторона"])
	var grid: int = int(earth["точок"])
	var step: float = float(earth["крок"])
	var start := Vector2(float(earth["початок"][0]), float(earth["початок"][1]))

	# Те саме поле, з якого будує гра, — читаємо самі, щоб було з чим
	# звіряти: збіг «сам із собою» нічого б не доводив, тому нижче
	# звіряємо не число з числом, а ЗЕМЛЮ з ПОЛЕМ.
	var relief := FileAccess.get_file_as_bytes(str(earth["рельєф"])) \
			.to_float32_array()
	var zones := FileAccess.get_file_as_bytes(str(earth["зони"]))

	var world: Node3D = MAIN.instantiate()
	root.add_child(world)
	await process_frame
	var land: Node = world.get_node("Landscape")

	var before := _rss_mib()
	var started := Time.get_ticks_msec()
	land.build(map)
	var spent := Time.get_ticks_msec() - started
	await process_frame

	print("\n— побудова —")
	print("  сторона %.0f м, сітка %d×%d, крок %.1f м" % [side, grid, grid, step])
	print("  збудовано за %d мс, вузлів у краєвиді %d, памʼять %.0f → %.0f МіБ"
			% [spent, land.get_child_count(), before, _rss_mib()])
	var body: Node = land.get_node_or_null("Земля")
	if body == null:
		_fail("вузла «Земля» немає взагалі")
		quit(1)
		return
	# Меші землі лежать по клаптях, тож шукаємо вглиб, а не в лоб.
	var tris := 0
	var pieces := 0
	var surfaces := {}
	for child in body.find_children("*", "MeshInstance3D", true, false):
		var view: MeshInstance3D = child
		if view.mesh == null:
			continue
		pieces += 1
		tris += view.mesh.get_faces().size() / 3
		surfaces[str(view.name).trim_prefix("Меш-")] = true
	print("  трикутників %d у %d мешах, різних поверхонь %d"
			% [tris, pieces, surfaces.size()])
	if pieces < 2:
		_fail("земля одним мешем — рушій не зможе відкинути невидиме")

	print("\n— земля проти поля карти —")
	var sea_level: float = land.sea_level()
	var wrong_side := 0
	var worst := 0.0
	var seed_rng := RandomNumberGenerator.new()
	seed_rng.seed = 7
	for i in PROBES:
		var ix := seed_rng.randi_range(0, grid - 1)
		var iz := seed_rng.randi_range(0, grid - 1)
		var x := start.x + ix * step
		var z := start.y + iz * step
		var want: float = relief[iz * grid + ix]
		var got: float = land.height_at(x, z)
		# Точки в місті рівняються майданчиком — їх у звірку не беремо.
		if _near_town(map, x, z):
			continue
		worst = maxf(worst, absf(got - want))
		var dry_in_field: bool = zones[iz * grid + ix] != 0
		var dry_in_game: bool = got > sea_level
		if dry_in_field != dry_in_game:
			wrong_side += 1
	print("  найбільше розходження висоти з полем: %.2f м "
			% worst + "(дрібні нерівності, розмах %.1f)"
			% [float(earth.get("розмах", 0.9))])
	print("  берег: точок по різні боки води в грі й на карті — %d із %d"
			% [wrong_side, PROBES])
	if worst > float(earth.get("розмах", 0.9)) + 0.05:
		_fail("земля відходить від поля далі, ніж на дрібні нерівності")
	if wrong_side * 200 > PROBES:
		_fail("берегова лінія в грі не та, що на карті (більше 0,5%)")

	print("\n— столиця в (0,0) —")
	var capital: Dictionary = map["міста"][0]
	var level := float(capital["висота"])
	var middle: float = land.height_at(0.0, 0.0)
	var side_10: float = land.height_at(10.0, 0.0)
	print("  «%s»: центр %.2f, за 10 кроків %.2f, задано %.2f"
			% [capital["назва"], middle, side_10, level])
	if absf(middle - level) > 0.01 or absf(side_10 - level) > 0.01:
		_fail("майданчик столиці не рівний — спавн і оживлення сядуть у схил")
	var flat_to: float = float(capital.get("рівне", capital["радіус"]))
	var outside: float = land.height_at(flat_to + 40.0, 0.0)
	if absf(outside - level) < 0.01:
		_fail("за межами міста земля так само рівна — майданчик не згасає")

	print("\n— 25 іменних об'єктів —")
	var wet := 0
	var checked := 0
	for group: String in ["міста", "села"]:
		for place: Dictionary in map.get(group, []):
			checked += 1
			var at: Array = place["центр"]
			if land.height_at(float(at[0]), float(at[2])) <= sea_level:
				wet += 1
				_fail("%s «%s» у воді" % [group, place.get("назва", "?")])
	for mark: Dictionary in map.get("орієнтири", []):
		checked += 1
		var at: Array = mark["де"]
		if land.height_at(float(at[0]), float(at[2])) <= sea_level:
			wet += 1
			_fail("%s у воді на (%.0f, %.0f)" % [mark["вид"], at[0], at[2]])
	print("  перевірено %d, у воді %d" % [checked, wet])

	print("\n— чи можна там ходити —")
	var steep := 0
	var counted := 0
	for i in PROBES:
		var ix := seed_rng.randi_range(1, grid - 2)
		var iz := seed_rng.randi_range(1, grid - 2)
		if zones[iz * grid + ix] == 0:
			continue
		counted += 1
		var x := start.x + ix * step
		var z := start.y + iz * step
		var dy: float = absf(land.height_at(x + step, z) - land.height_at(x, z))
		if rad_to_deg(atan2(dy, step)) > CLIMB_LIMIT:
			steep += 1
	print("  схилів крутіших за %.0f° на суші: %.1f%% (%d із %d)"
			% [CLIMB_LIMIT, 100.0 * steep / maxi(1, counted), steep, counted])

	print("\n— де заводяться монстри й де входить гравець —")
	# Слово замовника 05.09.2026: «монстри та гравець провалюються, бо
	# точка респавна або нижче поверхні, або на межі поверхні». Тому
	# міряємо не центр зони, а все її коло — і саме те, чи є під точкою
	# суха земля з запасом над морем.
	var spawn_high: float = land.height_at(0.0, 0.0)
	print("  вхід і оживлення в (0,0): земля %.2f, ставимо на %.2f"
			% [spawn_high, spawn_high + 6.0])
	if spawn_high <= sea_level + 1.0:
		_fail("точка входу (0,0) не на сухій землі")
	var zones_from: Array = map.get("зони появи", [])
	var wet_zone := 0
	var lowest := 1e9
	for zone: Dictionary in zones_from:
		var at: Array = zone.get("де", [0, 0, 0])
		var radius: float = float(zone.get("радіус", 20.0))
		for k in 9:
			var turn := TAU * float(k) / 8.0
			var far: float = 0.0 if k == 8 else radius
			var x: float = float(at[0]) + cos(turn) * far
			var z: float = float(at[2]) + sin(turn) * far
			var under: float = land.height_at(x, z)
			lowest = minf(lowest, under)
			if under <= sea_level + 1.0:
				wet_zone += 1
				break
	print("  зон появи %d, монстрів %d; зон із мокрим краєм: %d"
			% [zones_from.size(),
			   zones_from.reduce(func(sum: int, one: Dictionary) -> int:
					return sum + int(one.get("скільки", 1)), 0),
			   wet_zone])
	print("  найнижча точка по краях усіх зон: %.2f м (море %.2f)"
			% [lowest if lowest < 1e8 else 0.0, sea_level])
	if zones_from.is_empty():
		_fail("у даних немає зон появи — монстри стануть по сцені світу 600 м")
	if wet_zone > 0:
		_fail("%d зон появи торкаються води — монстри там тонуть" % wet_zone)

	print("\n— чи збігається те, по чому ходять, із тим, що видно —")
	# Промінь згори вниз: фізика має зустріти землю там само, де її
	# рахує `height_at`. Якщо ні — крізь неї падають, і саме це
	# замовник і побачив («впав за текстури»).
	var space := (land as Node3D).get_world_3d().direct_space_state
	var missed := 0
	var off := 0.0
	var tried := 0
	for i in 600:
		var ix := seed_rng.randi_range(2, grid - 3)
		var iz := seed_rng.randi_range(2, grid - 3)
		if zones[iz * grid + ix] == 0:
			continue
		tried += 1
		var x := start.x + ix * step
		var z := start.y + iz * step
		var want: float = land.height_at(x, z)
		var query := PhysicsRayQueryParameters3D.create(
				Vector3(x, want + 60.0, z), Vector3(x, want - 60.0, z))
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			missed += 1
			continue
		off = maxf(off, absf(float(hit["position"].y) - want))
	print("  промінь не зустрів землі: %d із %d" % [missed, tried])
	print("  найбільша різниця між зіткненням і рельєфом: %.2f м" % off)
	if missed > 0:
		_fail("є місця, де землі фізично немає — крізь них падають")
	if off > 0.6:
		_fail("зіткнення зсунуте відносно видимої землі на %.2f м" % off)

	print("\n— ліс не тоне —")
	var sunk := 0
	var trees := 0
	for child in land.get_children():
		if not str(child.name).begins_with("Дерево"):
			continue
		trees += 1
		if (child as Node3D).global_position.y < sea_level:
			sunk += 1
	print("  дерев %d, під водою %d" % [trees, sunk])
	if sunk > 0:
		_fail("дерева ростуть під водою")

	print("\n— підсумок —")
	if _bad == 0:
		print("  ✓ світ версії 2 збігається з картою")
	else:
		print("  ‼ зауважень: %d" % _bad)
	quit(1 if _bad else 0)


func _near_town(map: Dictionary, x: float, z: float) -> bool:
	var edge: float = float(map["земля"].get("поле", 14))
	for group: String in ["міста", "села"]:
		for place: Dictionary in map.get(group, []):
			var at: Array = place["центр"]
			var far := Vector2(x - float(at[0]), z - float(at[2])).length()
			if far < float(place.get("рівне", place["радіус"])) + edge:
				return true
	return false
