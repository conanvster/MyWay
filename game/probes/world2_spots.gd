extends Node
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
## П'ятий елемент — висота камери над землею (без нього — 20 м).
const SPOTS := [
	["столиця: брама ззовні", Vector3(100, 0, 0), 90.0, -4.0, 3.0],
	["столиця: вулиця", Vector3(48, 0, 0), 90.0, -4.0, 1.8],
	["столиця згори", Vector3(130, 0, 130), 45.0, -16.0, 45.0],
	["село Броди", Vector3(-608, 0, -114), 0.0, -8.0, 4.0],
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


func _ready() -> void:
	call_deferred("_go")


func _go() -> void:
	await get_tree().process_frame
	var text := FileAccess.get_file_as_string(MAP2)
	if text.is_empty():
		print("‼ немає %s — спершу `python3 tools/svit2.py`" % MAP2)
		get_tree().quit(1)
		return
	# Кадри міряємо без вертикальної синхронізації: «60» з нею нічого не
	# каже — шістдесят буде й тоді, коли карта ледве встигає.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	# Світ-клієнт сам стукає на 127.0.0.1, а там може саме йти
	# гра замовника (19.09.2026: проба під'єдналась до живого
	# сервера світу 2 й перезапускалась по колу). «Уже в мережі» —
	# і `Net.join()` нічого не робить.
	var net: Node = get_tree().root.get_node_or_null("Net")
	if net != null:
		net.joined = true
	var world: Node3D = MAIN.instantiate()
	get_tree().root.add_child(world)
	await get_tree().process_frame
	var land: Node = world.get_node("Landscape")
	# З підвантаженням, як у справжнього клієнта: інакше проба тягне у
	# памʼять усі рослини світу, а видно однаково лише ті, що поруч.
	var map: Dictionary = JSON.parse_string(text)
	land.build(map, true)
	await get_tree().process_frame

	# Сонце — те, що в `main.tscn` («Light», з тінями), як і в грі. Своє
	# проба більше не додає: з двома сонцями знімки 11.09.2026 виходили
	# пересвіченими вдвічі — мертвий схід білим, гори вицвілими, — і так
	# хибно судили б про колір землі.
	var eye := Camera3D.new()
	eye.far = 900.0
	get_tree().root.add_child(eye)
	eye.make_current()

	# Лісова стежка (слово замовника 11.09.2026: «серед лісу із
	# стежкою»): точка дороги поблизу столиці, де найбільше лісу, і
	# погляд уздовж неї — камерою гравця й з висоти людини.
	var spots: Array = SPOTS.duplicate()
	# `--поселення-згори` — лише міста й села, кожне згори під 60°:
	# центр і розмір муру — з тих самих даних, з яких їх будує `TownLook`.
	if OS.get_cmdline_user_args().has("--поселення-згори"):
		spots = _settlements_from_above(JSON.parse_string(text))
	# `--площі` — площа кожного міста з висоти 7 м, у два боки: будівлі
	# площі й мешканці перед ними (06.11.2026).
	if OS.get_cmdline_user_args().has("--площі"):
		spots = []
		for place: Dictionary in JSON.parse_string(text).get("міста", []):
			var c: Array = place["центр"]
			for yaw: float in [0.0, 120.0, 240.0]:
				var back := Vector3(sin(deg_to_rad(yaw)), 0,
						cos(deg_to_rad(yaw))) * 6.0
				spots.append(["площа %s %d°" % [place["назва"], yaw],
						Vector3(float(c[0]), 0, float(c[2])) + back, yaw,
						-14.0, 7.0])
	var trail := _forest_path(land, JSON.parse_string(text))
	# `--світло` (П5, 06.11.2026): кожне місце — п'ятьма варіантами світла й
	# обробки кадру, щоразу +1 зміна (`_light`). Знімки — у
	# user://світло/<місце>-<варіант>.png, кадри — в журнал.
	var light_mode := OS.get_cmdline_user_args().has("--світло")
	# `--пори` (26.11.2026, П-273 після П-274): кожну серію світла — на
	# чотири пори доби; `--кадрів N` — скільки кадрів міряти (на процесорному
	# рендері кадри нічого не кажуть, а 60 — це хвилини на знімок).
	var user_args := OS.get_cmdline_user_args()
	if user_args.has("--пори"):
		_hours = HOURS
	var day: DayCycle = world.get("day")
	if light_mode and day != null:
		day.set_process(false)
	var at_frames := user_args.find("--кадрів")
	if at_frames >= 0 and at_frames + 1 < user_args.size():
		_measure = maxi(1, int(user_args[at_frames + 1]))
	if light_mode:
		spots = [["площа Стільна", Vector3(0, 0, 6), 0.0, -14.0, 7.0]]
		for one: Array in SPOTS:
			if str(one[0]) in ["гай на рівнині, з висоти людини",
					"гори заходу, схил", "мертвий схід",
					"гравець на межі лісу"]:
				spots.append(one)
	if not trail.is_empty() and (spots.size() == SPOTS.size() or light_mode):
		spots.push_front(["у лісі на стежці, з висоти людини", trail[0],
				trail[1], -3.0])
		spots.push_front(["гравець на лісовій стежці", trail[0], trail[1],
				-50.0])
	# `--лише <слово>` — лише місця, в назві яких є це слово (напр.
	# «столиця», «село»): повний обхід триває хвилини, а міста — секунди.
	var args := OS.get_cmdline_user_args()
	var only := ""
	if args.find("--лише") >= 0 and args.find("--лише") + 1 < args.size():
		only = args[args.find("--лише") + 1]
	for spot: Array in spots:
		var at: Vector3 = spot[1]
		var name_of: String = spot[0]
		if only != "" and not only in name_of:
			continue
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
			var up: float = float(spot[4]) if spot.size() > 4 else 20.0
			if name_of.begins_with("гай") or in_wood:
				up = 1.8 if in_wood else 2.5
			eye.position = Vector3(at.x, ground + up, at.z)
			eye.rotation_degrees = Vector3(float(spot[3]), float(spot[2]), 0)
		land.stream_to(eye.position)
		for i in 20:
			await get_tree().process_frame
		var draws := 0.0
		var tris := 0.0
		var started := Time.get_ticks_usec()
		for i in _measure:
			await get_tree().process_frame
			draws += Performance.get_monitor(
					Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			tris += Performance.get_monitor(
					Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		var fps := _measure / ((Time.get_ticks_usec() - started) / 1e6)
		var grass := Vector2i.ZERO
		var meadow: Node = land.get_node_or_null("Різнотрав'я")
		if meadow != null:
			grass = meadow.counts()
		print("[місце] %s — земля %.1f м · кадрів %.0f · малювань %.0f · "
				% [name_of, ground, fps, draws / _measure]
				+ "трикутників %.0f тис. · трави %d клітинок, %d купок"
				% [tris / _measure / 1000.0, grass.x, grass.y])
		if light_mode:
			if _hours.is_empty():
				await _light_series(land, name_of)
			for row: Array in _hours:
				_set_hour(world, float(row[1]))
				await _light_series(land, "%s-%s" % [name_of, row[0]])
			continue
		Shot.take(get_tree().root)
		# Ім'я знімка з роздільністю в секунду: між двома має пройти
		# більше секунди, інакше другий затре перший.
		var wait := Time.get_ticks_msec() + 1100
		while Time.get_ticks_msec() < wait:
			await get_tree().process_frame
	print("[місця] знімки зроблено")
	get_tree().quit()


## Години для `--пори`: середина кожної пори з `data/doba.json`, ранок і
## вечір — ближче до сходу й заходу, де світло найбільш «своє».
const HOURS := [["1-ранок", 7.0], ["2-день", 13.0], ["3-вечір", 19.3],
		["4-ніч", 23.5]]
var _hours: Array = []
var _first_mean := 0.0


## Середня яскравість кадру (0…1) по сітці 64×36 — для самоперевірки.
static func _mean(image: Image) -> float:
	var sum := 0.0
	for y in 36:
		for x in 64:
			var c := image.get_pixel(x * image.get_width() / 64,
					y * image.get_height() / 36)
			sum += c.r + c.g + c.b
	return sum / (64.0 * 36.0 * 3.0)
var _measure := 60


## Поставити світ на годину й зупинити годинник, щоб серія світла не
## пливла посеред знімків.
func _set_hour(world: Node, h: float) -> void:
	var day: DayCycle = world.get("day")
	if day == null:
		print("‼ у світу немає доби (DayCycle)")
		return
	day.fixed_hour = h
	day.apply(h)
	day.set_process(false)
	# Серія світла бере за «зараз» те, що поставила доба.
	_base.clear()
	print("[світло] година %.1f — %s" % [h, day.part_of(h)])


const LIGHTS := ["1-зараз", "2-agx", "3-agx-ssil", "4-agx-ssil-glow",
		"5-agx-ssil-glow-корекція"]
var _base := {}


## П5: той самий кадр п'ятьма варіантами, кожен додає одну зміну.
func _light_series(_land: Node, name_of: String) -> void:
	# Оточення — те, що СПРАВДІ показується. `land._air` тут не годиться:
	# світ будує землю раз у `_ready`, проба — вдруге, і другий
	# WorldEnvironment лишається непоказаним. До 26.11.2026 серія правила
	# саме його, і всі п'ять варіантів виходили однаковими (знімки
	# 06.11 і 26.11 — недійсні).
	var air: Environment = get_viewport().find_world_3d().environment
	if _base.is_empty():
		for key: String in ["tonemap_mode", "tonemap_exposure", "ssil_enabled",
				"glow_enabled", "adjustment_enabled"]:
			_base[key] = air.get(key)
	DirAccess.make_dir_recursive_absolute("user://світло")
	for k in LIGHTS.size():
		_light(air, k)
		for i in 20:
			await get_tree().process_frame
		var started := Time.get_ticks_usec()
		for i in _measure:
			await get_tree().process_frame
		var fps := _measure / ((Time.get_ticks_usec() - started) / 1e6)
		await RenderingServer.frame_post_draw
		var path := "user://світло/%s-%s.png" % [name_of.replace(" ", "_")
				.replace(",", ""), LIGHTS[k]]
		var image := get_viewport().get_texture().get_image()
		image.save_png(path)
		# Самоперевірка: варіант, що нічим не відрізняється від першого,
		# означає, що серія знову править не те оточення.
		var mean := _mean(image)
		if k == 0:
			_first_mean = mean
		elif absf(mean - _first_mean) < 0.002:
			print("‼ [світло] %s · %s не відрізняється від «зараз»"
					% [name_of, LIGHTS[k]])
		print("[світло] %s · %s · кадрів %.0f" % [name_of, LIGHTS[k], fps])
	_light(air, 0)


func _light(air: Environment, step: int) -> void:
	for key: String in _base:
		air.set(key, _base[key])
	if step >= 1:
		air.tonemap_mode = Environment.TONE_MAPPER_AGX
		# Від експозиції, яку поставила доба, а не стала 1,1.
		air.tonemap_exposure = float(_base["tonemap_exposure"]) * 1.1
	if step >= 2:
		air.ssil_enabled = true
		air.ssil_radius = 5.0
		air.ssil_intensity = 1.0
	if step >= 3:
		air.glow_enabled = true
		air.glow_intensity = 0.6
		air.glow_bloom = 0.0
		air.glow_hdr_threshold = 1.2
	if step >= 4:
		air.adjustment_enabled = true
		air.adjustment_contrast = 1.06
		air.adjustment_saturation = 1.1
		air.adjustment_brightness = 1.0


## Місця «згори» на кожне місто й село: камера на південь від центру,
## дивиться на північ під 60° униз; відстань — за радіусом муру, щоб
## усе поселення влізло в кадр.
func _settlements_from_above(map: Dictionary) -> Array:
	var out: Array = []
	for group: String in ["міста", "села"]:
		for place: Dictionary in map.get(group, []):
			var c: Array = place["центр"]
			var reach := float(place.get("мур радіус",
					float(place.get("радіус", 30.0)) * 1.2))
			var up := reach * 1.55
			var back := up / tan(deg_to_rad(60.0))
			var label := "%s %s згори" % ["місто" if group == "міста"
					else "село", place.get("назва", "")]
			out.append([label, Vector3(float(c[0]), 0, float(c[2]) + back),
					0.0, -60.0, up])
	return out


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

