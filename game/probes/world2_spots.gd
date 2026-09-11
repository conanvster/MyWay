extends SceneTree
## Світ версії 2 з землі: кілька місць, по знімку на кожне.
##
## Питання, на які відповідає: чи межа зон читається переходом, а не
## ножем · чи стоять орієнтири на ґрунті · чи є на схилах ліс і чи
## тече в руслі вода · чи видно небо · (з 11.09.2026) як виглядає
## земля й трава з камери гравця і скільки це коштує відеокарті.
##
## Ганяти так:
##     ./run.sh --світ2-місця

const MAIN := preload("res://scenes/main.tscn")
const MAP2 := "res://data/map2.json"
## Зона бачення гравця (`camera_rig.gd`): туман ставиться по ній, як у
## грі. Без цього знімок показував би світ, якого гравець не бачить.
const VISION := 18.0

## Куди дивимось: назва · точка на землі · куди повернуто · нахил.
## «гравець» — камера так, як у грі: 10 м позаду, 50° униз
## (`camera_rig.gd`: distance 10, pitch 50°, pivot 1,2 м).
const SPOTS := [
	["гравець на луці", Vector3(-240, 0, -560), 30.0, -50.0],
	["гравець на межі лісу", Vector3(-262, 0, -600), 200.0, -50.0],
	["гравець у горах заходу", Vector3(-2032, 0, -1064), 270.0, -50.0],
	["гравець на мертвому сході", Vector3(1456, 0, -2260), 180.0, -50.0],
	["гай на рівнині, з висоти людини", Vector3(-240, 0, -560), 30.0, -2.0],
	["межа рівнини й вулканічної смуги", Vector3(64, 0, -1232), 270.0, -6.0],
	["гори заходу, схил", Vector3(-2032, 0, -1064), 270.0, -4.0],
	["русло в горах", Vector3(-1296, 0, -896), 20.0, -8.0],
	["мертвий схід", Vector3(1456, 0, -2260), 180.0, -4.0],
	["крижана північ", Vector3(1464, 0, -2912), 200.0, -6.0],
]


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	var text := FileAccess.get_file_as_string(MAP2)
	if text.is_empty():
		print("‼ немає %s — спершу `python3 tools/svit2.py`" % MAP2)
		quit(1)
		return
	# Кадри міряємо без вертикальної синхронізації: «60» з нею нічого не
	# каже — шістдесят буде й тоді, коли карта ледве встигає.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var world: Node3D = MAIN.instantiate()
	root.add_child(world)
	await process_frame
	var land: Node = world.get_node("Landscape")
	# З підвантаженням, як у справжнього клієнта: інакше проба тягне у
	# памʼять усі рослини світу, а видно однаково лише ті, що поруч.
	land.build(JSON.parse_string(text), true)
	await process_frame

	# Сонце — те, що в `main.tscn` («Light», з тінями), як і в грі. Своє
	# проба більше не додає: з двома сонцями знімки 11.09.2026 виходили
	# пересвіченими вдвічі — мертвий схід білим, гори вицвілими, — і так
	# хибно судили б про колір землі.
	var eye := Camera3D.new()
	eye.far = 900.0
	root.add_child(eye)
	eye.make_current()

	# Лісова стежка (слово замовника 11.09.2026: «серед лісу із
	# стежкою»): точка дороги поблизу столиці, де найбільше лісу, і
	# погляд уздовж неї — камерою гравця й з висоти людини.
	var spots: Array = SPOTS.duplicate()
	var trail := _forest_path(land, JSON.parse_string(text))
	if not trail.is_empty():
		spots.push_front(["у лісі на стежці, з висоти людини", trail[0],
				trail[1], -3.0])
		spots.push_front(["гравець на лісовій стежці", trail[0], trail[1],
				-50.0])
	for spot: Array in spots:
		var at: Vector3 = spot[1]
		var name_of: String = spot[0]
		var ground: float = land.height_at(at.x, at.z)
		var player := name_of.begins_with("гравець")
		var in_wood := name_of.begins_with("у лісі")
		# Туман як у грі — лише для камери гравця; решта місць дивиться
		# далеко, щоб порівнювати з аркушем карти.
		if player or in_wood:
			land.fog_to_vision(VISION)
		if player:
			var turn := deg_to_rad(float(spot[2]))
			var tilt := deg_to_rad(-float(spot[3]))
			var back := Vector3(sin(turn), 0.0, cos(turn))
			var pivot := Vector3(at.x, ground + 1.2, at.z)
			eye.position = pivot + back * 10.0 * cos(tilt) \
					+ Vector3.UP * 10.0 * sin(tilt)
			eye.look_at(pivot)
		else:
			if not in_wood:
				land.fog_to_vision(VISION * 7.0)
			# Перше місце без камери гравця дивимось із висоти людини,
			# решту — з двадцяти метрів: з висоти очей схил видно під
			# таким кутом, що по ньому нічого не порахуєш (05.09.2026).
			var up: float = 20.0
			if name_of.begins_with("гай") or in_wood:
				up = 1.8 if in_wood else 2.5
			eye.position = Vector3(at.x, ground + up, at.z)
			eye.rotation_degrees = Vector3(float(spot[3]), float(spot[2]), 0)
		land.stream_to(eye.position)
		for i in 20:
			await process_frame
		var draws := 0.0
		var tris := 0.0
		var started := Time.get_ticks_usec()
		for i in 60:
			await process_frame
			draws += Performance.get_monitor(
					Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			tris += Performance.get_monitor(
					Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		var fps := 60.0 / ((Time.get_ticks_usec() - started) / 1e6)
		var grass := Vector2i.ZERO
		var meadow: Node = land.get_node_or_null("Різнотрав'я")
		if meadow != null:
			grass = meadow.counts()
		print("[місце] %s — земля %.1f м · кадрів %.0f · малювань %.0f · "
				% [name_of, ground, fps, draws / 60.0]
				+ "трикутників %.0f тис. · трави %d клітинок, %d купок"
				% [tris / 60.0 / 1000.0, grass.x, grass.y])
		Shot.take(root)
		# Ім'я знімка з роздільністю в секунду: між двома має пройти
		# більше секунди, інакше другий затре перший.
		var wait := Time.get_ticks_msec() + 1100
		while Time.get_ticks_msec() < wait:
			await process_frame
	print("[місця] знімки зроблено")
	quit()


## Точка дороги в межах 1,5 км від столиці, біля якої найбільше живих
## хвойних (у радіусі 25 м), і куди дорога йде далі (кут камери).
##
## Спершу шукав за вагою лісової підстилки — і знайшов вулканічну смугу:
## там той самий шар згарища лежить скрізь, а дерева рідкі й сухі.
## Тож рахуємо самі дерева.
func _forest_path(land: Node, map: Dictionary) -> Array:
	var best := 0
	var found: Array = []
	for road: Dictionary in map.get("дороги", []):
		var pts: Array = road.get("точки", [])
		for k in range(1, pts.size() - 1):
			var x := float(pts[k][0])
			var z := float(pts[k][1])
			if Vector2(x, z).length() > 1500.0:
				continue
			var trees := 0
			for dz in [-25.0, 0.0, 25.0]:
				for dx in [-25.0, 0.0, 25.0]:
					var key: String = land._patch_at(x + dx, z + dz)
					for spec: Dictionary in land._tree_specs.get(key, []):
						if str(spec.get("вид", "")) != "хвоя":
							continue
						var at: Vector3 = spec["at"]
						if Vector2(at.x - x, at.z - z).length() < 25.0:
							trees += 1
			if trees > best:
				best = trees
				var fx := float(pts[k + 1][0]) - float(pts[k - 1][0])
				var fz := float(pts[k + 1][1]) - float(pts[k - 1][1])
				found = [Vector3(x, 0, z), rad_to_deg(atan2(-fx, -fz))]
	print("[місця] лісова стежка: хвойних у 25 м — %d, у %s"
			% [best, str(found[0]) if not found.is_empty() else "—"])
	return found
