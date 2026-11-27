class_name Landscape
extends Node3D
## Краєвид: земля, місто з будинками й мешканцями, ліс, гори.
##
## Будується кодом за числами з `data/map.json`. Чому не руками в
## редакторі: сімдесят дерев і п'ять будинків — це сімдесят п'ять вузлів,
## які потім не посунути одним рухом. А так гора переїжджає правкою
## одного рядка, і видно її одразу.
##
## Зони появи монстрів навмисно лишаються вузлами в сцені: їхні межі
## зручніше тягнути мишею, і саме про це просив замовник.
##
## Розкид дерев випадковий, але з **однаковим зерном**: ліс має бути той
## самий і на сервері, і в кожного клієнта, інакше дерево росло б у
## різних місцях у різних людей.
const SEED := 20260902
## Уся суша (не море) піднята на стільки за словом замовника 03.09.2026
## (П-140, число зменшено з 5 на 3 того ж вечора). Додається останнім,
## до вже готової форми рельєфу — самі числа шуму, підлоги над морем
## (П-138) і насипів (Cave, Forest) не чіпалися.
const LAND_LIFT := 3.0
## Мешканці міста — та сама модель, що й гравці (П-162); шляхи беремо
## зі скрипта аватара, не дублюємо — немає `class_name Avatar`, тому
## через сам ресурс скрипта.
const AvatarScript := preload("res://scripts/avatar.gd")

var data: Dictionary = {}

## Підвантаження ділянками (П-63). Дерева й паркан — найдорожчі
## декорації (137 і ~109 з 489 мс, заміряно 03.09.2026), і жоден код
## більше ніде не звертається до них за іменем (`grep` по
## `Дерево`/`Паркан` за межами цього файлу — порожньо), тож їх безпечно
## відкладати. Земля, зіткнення, будинки, мешканці й гори лишаються
## одразу для всіх: перше — бо гравець чи монстр може опинитись де
## завгодно, друге — бо це NPC, з якими говорять, а не прикраса.
##
## Сервер СТРІМІНГ НЕ ВМИКАЄ НІКОЛИ (`build()` без другого доводу) —
## йому потрібне зіткнення й дерева, і паркан скрізь одразу, так само,
## як і сьогодні. Це вмикається лише для клієнта (`world.gd`).
var _streaming := false
## Специфікації — постійний реєстр, не «черга»: сектор лишається тут і
## після вивантаження, щоб підняти той самий розкид дерев ще раз, а не
## рахувати випадковість наново (вона й так одна на весь `build()`).
var _tree_specs: Dictionary = {}     # сектор -> Array[Dictionary]
var _tree_nodes: Dictionary = {}     # сектор -> Array[Node], лише завантажені
var _fence_specs: Dictionary = {}
var _fence_nodes: Dictionary = {}
var _loaded_sectors: Dictionary = {}   # сектор -> true, якщо збудовано
var _sector_seen_at: Dictionary = {}   # сектор -> мс, коли гравець там був

## ── Світ версії 2 ──────────────────────────────────────────────────
## Версія 1 бере висоту з шуму (`height_at` нижче). Версія 2 читає її з
## поля, порахованого генератором карти: тоді земля в грі й намальована
## карта — те саме число, а не дві схожі картинки. Поле порожнє → усе
## працює точно як раніше, тож світ версії 1 цим не зачеплений.
var _relief := PackedFloat32Array()    ## метри, `_grid`×`_grid` точок
var _zones := PackedByteArray()        ## код зони в тій самій точці
var _grid := 0                         ## точок на бік; 0 = версія 1
var _grid_step := 0.0                  ## метрів між точками
var _origin := Vector2.ZERO            ## світові координати точки [0,0]
var _zone_names: Array[String] = []    ## код зони -> назва


## Земля з вагами фото-шарів (`ground_paint.gd`) — в обох версіях
## світу (версія 1 — з 17.10.2026).
var _layers: GroundPaint
## Різнотрав'я довкола камери (`meadow.gd`) — лише в клієнта світу 2.
var _meadow_node: Meadow
## Двори поселень для трави: (x, z, радіус) — рахуються раз, а не на
## кожну з тисяч купок.
var _yards: Array[Vector3] = []


func build(from_data: Dictionary, stream: bool = false) -> void:
	data = from_data
	_streaming = stream
	seed(SEED)
	_counts.clear()
	_ground_paints.clear()
	_wind_paints.clear()
	_photo_ready.clear()
	_scan_parts.clear()
	_layers = null
	_load_field()
	_paths()
	_sky()
	_ground()
	_city()
	_forest()
	_greenery()
	_rivers()
	# Мости (П-174) — після річок: настил тверде тіло і на сервері.
	BridgeLook.build_all(self)
	_mountains()
	_landmarks()
	_shrines()
	_meadow()


## Прочитати рельєф і зони світу версії 2. Обидва файли — сирі числа
## поспіль (float32 і байт на точку), не JSON: 705×705 це півмільйона
## чисел, і розбір їх текстом коштував би секунди на кожному запуску.
##
## Помилку не ковтаємо (P3): немає файлу чи не той розмір — кажемо, що
## саме не так, і світ будується як версія 1, а не з нулями.
func _load_field() -> void:
	_relief = PackedFloat32Array()
	_zones = PackedByteArray()
	_grid = 0
	_zone_names.clear()
	var earth: Dictionary = data.get("земля", {})
	var relief_path := str(earth.get("рельєф", ""))
	if relief_path.is_empty():
		return
	var want := int(earth.get("точок", 0))
	var relief := FileAccess.get_file_as_bytes(relief_path)
	var zones := FileAccess.get_file_as_bytes(str(earth.get("зони", "")))
	if relief.is_empty() or zones.is_empty():
		print("[краєвид] ‼ світ версії 2: не прочитано %s або %s — "
				% [relief_path, earth.get("зони", "")]
				+ "будую як версію 1")
		return
	if relief.size() != want * want * 4 or zones.size() != want * want:
		print("[краєвид] ‼ світ версії 2: рельєф %d байтів і зони %d при "
				% [relief.size(), zones.size()]
				+ "сітці %d×%d — чекав %d і %d; будую як версію 1"
				% [want, want, want * want * 4, want * want])
		return
	_relief = relief.to_float32_array()
	_zones = zones
	_grid = want
	_grid_step = float(earth.get("крок", 8.0))
	_plant_wanted = float(earth.get("видно рослини", PLANT_SEEN))
	_plant_seen = GraphicsQuality.plant_distance(_plant_wanted)
	GraphicsQuality.register_landscape(self)
	var start: Array = earth.get("початок", [0, 0])
	_origin = Vector2(float(start[0]), float(start[1]))
	for zone: Dictionary in data.get("зони", []):
		var code := int(zone.get("код", 0))
		while _zone_names.size() <= code:
			_zone_names.append("")
		_zone_names[code] = str(zone.get("назва", "зона %d" % code))
	print("[краєвид] світ версії 2: сітка %d×%d, крок %.1f м, "
			% [_grid, _grid, _grid_step]
			+ "початок (%.0f, %.0f)" % [_origin.x, _origin.y])


## ── Стежки світу версії 2 ─────────────────────────────────────────
## Слово замовника 11.09.2026 з трьома знімками туманного лісу: «я очікую
## побачити такий вигляд — тут серед лісу із стежкою». Стежки — ті самі
## 26 доріг із даних (`дороги`, П-174), лише покладені в землю ґрунтом.
##
## Дорога в даних — ламана по сітці генератора (крок 32 м, повороти під
## 45°): у лісі така «драбинка» читалась би прокладеною під шнур. Тому
## вона тричі згладжується (Чайкін) і легко петляє шумом — до 2,2 м убік.
##
## Лягає не у вершини (8 м — стежка розпливлась би на шістнадцять), а в
## окреме поле ВІДСТАНІ до найближчої стежки, кроком 4 м. Поле читають:
## шейдер землі (край стежки до сантиметрів), `_greenery()` (на стежці
## не росте ні дерево, ні кущ — і на сервері, і в клієнта однаково) і
## різнотрав'я (найгустіше на узбіччі, як на знімках замовника).
const PATH_HALF := 1.4        ## пів ширини стежки, метрів
const PATH_STEP := 4.0        ## крок поля відстаней
const PATH_RANGE := 8.0       ## далі за це відстань у полі не розрізняється
var _path_gap := PackedByteArray()
var _path_side := 0
var _path_texture: ImageTexture


func _paths() -> void:
	_path_gap = PackedByteArray()
	_path_side = 0
	_path_texture = null
	var roads: Array = data.get("дороги", []).duplicate()
	# Під'їзди поселень (06.11.2026): дорога з мапи — до брами, з кожної
	# брами й кінця стежки села — хоча б коротка дорога назовні.
	for group: String in ["міста", "села"]:
		for place: Dictionary in data.get(group, []):
			for line: Array in place.get("під'їзди", []):
				roads.append({"точки": line, "під'їзд": true})
	if _grid == 0 or roads.is_empty():
		return
	var started := Time.get_ticks_msec()
	_path_side = int(ceil(_grid_step * (_grid - 1) / PATH_STEP)) + 1
	_path_gap.resize(_path_side * _path_side)
	_path_gap.fill(255)
	var wander := FastNoiseLite.new()
	wander.seed = SEED + 777
	wander.frequency = 0.025
	var long := 0.0
	for road: Dictionary in roads:
		var line := _trail(road.get("точки", []), wander)
		for k in range(line.size() - 1):
			_stamp_path(line[k], line[k + 1])
			long += line[k].distance_to(line[k + 1])
	_path_texture = ImageTexture.create_from_image(Image.create_from_data(
			_path_side, _path_side, false, Image.FORMAT_R8, _path_gap))
	print("[краєвид] стежок %d, %.1f км, поле %d×%d по %.0f м, %d мс"
			% [roads.size(), long / 1000.0, _path_side, _path_side,
			PATH_STEP, Time.get_ticks_msec() - started])


## Ламана з даних → плавна стежка: три проходи Чайкіна й петляння шумом,
## яке згасає до кінців (кінці — у містах, їх не зсуваємо).
static func _trail(raw: Array, wander: FastNoiseLite) -> PackedVector2Array:
	var line := PackedVector2Array()
	for p: Array in raw:
		line.append(Vector2(float(p[0]), float(p[1])))
	for pass_no in 6:
		if line.size() < 3:
			break
		var soft := PackedVector2Array([line[0]])
		for k in range(line.size() - 1):
			soft.append(line[k].lerp(line[k + 1], 0.25))
			soft.append(line[k].lerp(line[k + 1], 0.75))
		soft.append(line[line.size() - 1])
		line = soft
	var total := 0.0
	var along := PackedFloat32Array([0.0])
	for k in range(1, line.size()):
		total += line[k].distance_to(line[k - 1])
		along.append(total)
	var out := PackedVector2Array()
	for k in line.size():
		var ahead := line[mini(k + 1, line.size() - 1)] \
				- line[maxi(k - 1, 0)]
		var side := Vector2(-ahead.y, ahead.x).normalized()
		var fade := clampf(minf(along[k], total - along[k]) / 30.0, 0.0, 1.0)
		out.append(line[k] + side * wander.get_noise_2d(line[k].x, line[k].y)
				* 2.2 * fade)
	return out


func _stamp_path(a: Vector2, b: Vector2) -> void:
	var pad := Vector2.ONE * PATH_RANGE
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - pad
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + pad
	var x0 := clampi(floori((lo.x - _origin.x) / PATH_STEP), 0, _path_side - 1)
	var x1 := clampi(ceili((hi.x - _origin.x) / PATH_STEP), 0, _path_side - 1)
	var z0 := clampi(floori((lo.y - _origin.y) / PATH_STEP), 0, _path_side - 1)
	var z1 := clampi(ceili((hi.y - _origin.y) / PATH_STEP), 0, _path_side - 1)
	for iz in range(z0, z1 + 1):
		for ix in range(x0, x1 + 1):
			var p := _origin + Vector2(ix, iz) * PATH_STEP
			var far := Geometry2D.get_closest_point_to_segment(p, a, b) \
					.distance_to(p)
			var i := iz * _path_side + ix
			_path_gap[i] = mini(_path_gap[i],
					clampi(int(far / PATH_RANGE * 255.0), 0, 255))


## Відстань від точки до найближчої стежки, метрів (далі `PATH_RANGE` —
## просто «далеко»). Без стежок — нескінченність.
func path_gap(x: float, z: float) -> float:
	if _path_side == 0:
		return INF
	var fx := (x - _origin.x) / PATH_STEP
	var fz := (z - _origin.y) / PATH_STEP
	var ix := clampi(floori(fx), 0, _path_side - 2)
	var iz := clampi(floori(fz), 0, _path_side - 2)
	var tx := clampf(fx - ix, 0.0, 1.0)
	var tz := clampf(fz - iz, 0.0, 1.0)
	var i := iz * _path_side + ix
	return lerpf(lerpf(_path_gap[i], _path_gap[i + 1], tx),
			lerpf(_path_gap[i + _path_side], _path_gap[i + _path_side + 1], tx),
			tz) / 255.0 * PATH_RANGE


## Скільки лісу в точці — вага лісової підстилки. Для проб: знайти
## стежку, що йде крізь гай.
func forest_at(x: float, z: float) -> float:
	if _layers == null or _layers.weights.is_empty():
		return 0.0
	return _layers.layer_at(x, z, GroundPaint.LITTER)


## Скільки метрів до межі сектора тримати сусідній сектор завантаженим —
## інакше дерева зникали б і з'являлись просто на очах, щойно перейшов
## межу x=0 чи z=0 туди-сюди.
const STREAM_MARGIN := 15.0
## Секунд поза сектором, перш ніж вивантажити його: не миттю на першому
## кроці назад, а з запасом, щоб не смикати туди-сюди на самій межі.
const STREAM_UNLOAD_AFTER := 12.0


## Кличе клієнт (`world.gd`) періодично зі своєю позицією. Сервер це
## НЕ кличе ніколи — у нього все побудовано одразу (`build()` без
## `stream`), і `_streaming` лишається `false`.
func stream_to(pos: Vector3) -> void:
	if not _streaming:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var want := _wanted_sectors(pos)
	for key: String in want:
		_sector_seen_at[key] = now
		if not _loaded_sectors.get(key, false):
			HitchLog.timed("ділянка %s" % key, _load_sector.bind(key))
	var known: Array = _tree_specs.keys()
	for key: String in _fence_specs.keys():
		if not known.has(key):
			known.append(key)
	for key: String in known:
		if not _loaded_sectors.get(key, false) or want.has(key):
			continue
		if now - float(_sector_seen_at.get(key, now)) > STREAM_UNLOAD_AFTER:
			_unload_sector(key)


## Свій сектор завжди, і сусідній через межу x=0/z=0, якщо до неї
## ближче за `STREAM_MARGIN` — саме так гравець біля центру міста
## (де сходяться всі чотири) тримає їх завантаженими одразу, а не по
## одному щоразу, як переступить лінію.
## За скільки метрів рослина перестає малюватись зовсім.
##
## Слово замовника 06.09.2026: «ми будуємо одразу всі дерева на мапі, а
## не тільки ті що в зоні бачення — відеокарта не справляється». Було
## гірше, ніж він думав: підвантаження вже було, але тримало ділянки в
## радіусі 560 м, тоді як **туман закінчується на 54 м** (зона бачення
## 18 × запас 3, П-65). Тобто дев'ять десятих дерев малювались у
## непрозорий туман.
##
## Тепер два замки. Перший — цей: рушій сам відкидає меш, до якого
## далі за `visibility_range_end`, і це коштує нуль малювання. Другий —
## ділянки нижче. Число з запасом за туман, щоб дерево не спалахувало
## на межі видимого.
const PLANT_SEEN := 110.0


## Пустити вітер по вже готовій моделі.
##
## Слово замовника: пріоритет моделям — щоб гойдалися. Гойдання дає
## шейдер, і моделі його теж отримують: у кожної поверхні береться її
## власна текстура й підставляється в той самий `wind.gdshader`. Що
## нижче рослина, то жвавіше вона гойдається — трава метляється, кущ
## ворушиться, дерево ледь хитає кроною.
##
## Кеш за парою «текстура + розмах»: тисячі кущів мають ділити один
## матеріал, інакше це тисячі шейдерів.
var _wind_paints: Dictionary = {}


func _wind_up(view: Node, tall: float, measure: bool = false) -> void:
	var sway: float = clampf(0.10 - tall * 0.012, 0.020, 0.10)
	var speed: float = clampf(1.9 - tall * 0.10, 0.8, 1.9)
	for child in view.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = child
		if mesh.mesh == null:
			continue
		# Скан має свою висоту в метрах, а не одиницю: зсув рахуємо від
		# його справжнього низу й верху, інакше папороть на 0,4 м ледь
		# ворушилась би.
		var low := 0.0
		var span := 1.0
		if measure:
			var box := mesh.mesh.get_aabb()
			low = box.position.y
			span = maxf(box.size.y, 0.01)
		for i in mesh.mesh.get_surface_count():
			var was: Material = mesh.mesh.surface_get_material(i)
			if was is not StandardMaterial3D:
				continue
			var flat: StandardMaterial3D = was
			if flat.albedo_texture == null:
				continue
			var key := "%s|%.3f|%.3f|%.3f" % [
					flat.albedo_texture.resource_path, sway, low, span]
			if not _wind_paints.has(key):
				var moved := ShaderMaterial.new()
				moved.shader = WIND
				moved.set_shader_parameter("albedo_tex", flat.albedo_texture)
				moved.set_shader_parameter("sway", sway)
				moved.set_shader_parameter("speed", speed)
				moved.set_shader_parameter("model_floor", low)
				moved.set_shader_parameter("model_tall", span)
				# Модель уже має свою прозорість, поріг лишаємо низьким:
				# інакше в трави зникали б кінчики.
				moved.set_shader_parameter("scissor", 0.25)
				# Скан Poly Haven має карту нормалей — без неї листя
				# папороті пласке, як вирізане з паперу.
				if flat.normal_enabled and flat.normal_texture != null:
					moved.set_shader_parameter("normal_tex",
							flat.normal_texture)
					moved.set_shader_parameter("use_normal", true)
				_wind_paints[key] = moved
			mesh.set_surface_override_material(i, _wind_paints[key])


## Далі за це не малюємо взагалі.
func _near_only(view: Node) -> void:
	for child in view.find_children("*", "GeometryInstance3D", true, false):
		var mesh: GeometryInstance3D = child
		mesh.visibility_range_end = _plant_seen
		mesh.visibility_range_end_margin = 12.0
		mesh.visibility_range_fade_mode = \
				GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	if view is GeometryInstance3D:
		var self_mesh: GeometryInstance3D = view
		self_mesh.visibility_range_end = _plant_seen
		self_mesh.visibility_range_end_margin = 12.0


var _plant_seen := PLANT_SEEN
## Скільки хоче світ (`видно рослини` у мапі); `_plant_seen` — після
## якості графіки (`GraphicsQuality.plant_distance`).
var _plant_wanted := PLANT_SEEN


## Якість графіки змінилась — нова дальність рослин уже збудованим.
func retune_plants() -> void:
	var was := _plant_seen
	_plant_seen = GraphicsQuality.plant_distance(_plant_wanted)
	if is_equal_approx(was, _plant_seen):
		return
	for child in find_children("*", "GeometryInstance3D", true, false):
		var mesh: GeometryInstance3D = child
		if is_equal_approx(mesh.visibility_range_end, was):
			mesh.visibility_range_end = _plant_seen


## Скільки метрів має бік ділянки підвантаження у світі версії 2.
## Чотири сектори П-143 тут не годяться: на 5632 м це чотири чверті по
## 2800 м, тобто «усе одразу» під іншою назвою.
const PATCH := 176.0
## У якому радіусі від гравця тримати ділянки завантаженими. Було 560 м
## при тумані на 54 — тобто вузли будувались на десять разів далі, ніж
## їх узагалі видно. Тепер трохи більше за межу малювання, щоб дерево
## встигло зʼявитись раніше, ніж вийде з туману.
const PATCH_NEAR := 200.0


## Ключ ділянки, до якої належить точка.
func _patch_at(x: float, z: float) -> String:
	if _grid == 0:
		return _sector_at(x, z)
	return "ділянка %d:%d" % [floori(x / PATCH), floori(z / PATCH)]


func _wanted_sectors(pos: Vector3) -> Array:
	if _grid > 0:
		var near: Array = []
		var reach := int(ceil(PATCH_NEAR / PATCH))
		for dz in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				near.append(_patch_at(pos.x + dx * PATCH, pos.z + dz * PATCH))
		return near
	var want: Array = [_sector_at(pos.x, pos.z)]
	var near_x := absf(pos.x) < STREAM_MARGIN
	var near_z := absf(pos.z) < STREAM_MARGIN
	var flip_x: float = -1.0 if pos.x >= 0.0 else 1.0
	var flip_z: float = -1.0 if pos.z >= 0.0 else 1.0
	if near_x:
		var key := _sector_at(flip_x, pos.z)
		if not want.has(key):
			want.append(key)
	if near_z:
		var key := _sector_at(pos.x, flip_z)
		if not want.has(key):
			want.append(key)
	if near_x and near_z:
		var key := _sector_at(flip_x, flip_z)
		if not want.has(key):
			want.append(key)
	return want


func _load_sector(key: String) -> void:
	_loaded_sectors[key] = true
	for spec: Dictionary in _tree_specs.get(key, []):
		var made: Node = _tree(spec)
		if made != null:
			_tree_nodes.get_or_add(key, []).append(made)
	for spec: Dictionary in _fence_specs.get(key, []):
		_fence_nodes.get_or_add(key, []).append(_fence_panel(spec))


func _unload_sector(key: String) -> void:
	_loaded_sectors[key] = false
	for node: Node in _tree_nodes.get(key, []):
		if is_instance_valid(node):
			node.queue_free()
	for node: Node in _fence_nodes.get(key, []):
		if is_instance_valid(node):
			node.queue_free()
	_tree_nodes[key] = []
	_fence_nodes[key] = []


## Небо й розсіяне світло. Без цього все, чого не торкнувся промінь
## сонця, лишається майже чорним — на першому знімку міста тінь від
## будинку була суцільною плямою.
func _sky() -> void:
	var sky := Sky.new()
	var painted := ProceduralSkyMaterial.new()
	painted.sky_top_color = Color("#3f6ea8")
	painted.sky_horizon_color = Color("#9fb6c4")
	painted.ground_bottom_color = Color("#3b4432")
	painted.ground_horizon_color = Color("#7d8a76")
	sky.sky_material = painted

	var air := Environment.new()
	air.background_mode = Environment.BG_SKY
	air.sky = sky
	# Довкілля НЕ з неба (АРГБ синього #3f6ea8), а свій нейтральний колір:
	# земля в тіні дерев не бачить прямого сонця взагалі, і при небесному
	# джерелі вся тінь ставала синьо-сірою — зелений ґрунт (яким кольором
	# його не пофарбуй) тонув у синяві (П-138, тест у лісі 03.09.2026).
	air.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	air.ambient_light_color = Color("#c9cdb8")
	air.ambient_light_energy = 0.9
	# Легкий туман удалині: гори на краю світу мають танути, а не стояти
	# картонкою. Справжній туман зони бачення — П-65, це не він.
	air.fog_enabled = true
	air.fog_mode = Environment.FOG_MODE_DEPTH
	air.fog_depth_begin = 40.0
	air.fog_depth_end = 130.0
	air.fog_sky_affect = 0.25
	air.fog_light_color = Color(str(data.get("туман", {})
			.get("колір", "#a8b6c2")))
	air.fog_density = 0.0025
	# Світ 2 — «реалістично й атмосферно» (смак замовника, 06.09.2026) і
	# «більш реалістично» (11.09.2026). Три речі, без яких фото-земля
	# виглядала пересвіченою плиткою:
	# - кіношне тонування (Filmic): світле не вигорає в біле, а трава
	#   лишається травою, а не кислотно-зеленою;
	# - затінення в западинах (SSAO): камінь сидить у землі, стовбур
	#   має тінь біля кореня — без цього все стоїть на столі;
	# - розсіяне світло слабше: з ним 0,9 тіньовий бік був майже як
	#   освітлений, і рельєф читався пласким; і 0,7 ще вицвітало (знімок
	#   гір із камери гравця), тож 0,5.
	# Світ версії 1 не чіпаємо — він як був.
	if _grid > 0:
		# Туманний хвойний ліс зі знімків замовника (11.09.2026): небо
		# затягнуте, сонце м'яке, а між стовбурами стоїть туман, у якому
		# дальні дерева сіріють шарами. Звичайний туман по відстані тут не
		# годиться — він лише фарбує далеке; об'ємний стоїть у повітрі й
		# світиться від неба, як справжній.
		painted.sky_top_color = Color("#8d99a4")
		painted.sky_horizon_color = Color("#c3c8c7")
		air.volumetric_fog_enabled = true
		air.volumetric_fog_density = 0.016
		air.volumetric_fog_albedo = Color("#c6cbc4")
		air.volumetric_fog_anisotropy = 0.3
		air.volumetric_fog_length = 80.0
		air.volumetric_fog_ambient_inject = 0.6
		air.volumetric_fog_sky_affect = 0.0
		var sun := get_parent().get_node_or_null("Light") as DirectionalLight3D
		if sun != null:
			sun.light_energy = 0.8
			sun.light_color = Color("#eef0ee")
		air.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		air.tonemap_exposure = 1.05
		air.ssao_enabled = true
		air.ssao_radius = 1.4
		air.ssao_intensity = 1.6
		air.ambient_light_energy = 0.5
	_air = air
	GraphicsQuality.tune_environment(air)
	GraphicsQuality.tune_sun(get_parent().get_node_or_null("Light")
			as DirectionalLight3D)

	var holder := WorldEnvironment.new()
	holder.name = "Небо"
	holder.environment = air
	add_child(holder)


func _paint(color: String) -> StandardMaterial3D:
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(color)
	paint.roughness = 0.95
	return paint


## Поверхня з крапом — замість текстури, якої в нас немає.
##
## У наборі є стіни, дахи й камінь, а землі й трави немає. Рівний колір
## без нічого читається саме так, як сказав замовник: «тіні від
## ландшафту є, а текстури немає» — бо її й справді немає, є заливка.
##
## Тому робимо свою: шум трипланарно поверх кольору. Трипланарно — щоб не
## розгортати UV на рельєфі, який будується кодом; `size` задає, через
## скільки метрів візерунок повторюється.
func _speckled(color: String, size: float, strength: float
		) -> StandardMaterial3D:
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(color)
	paint.roughness = 0.95
	var noise := FastNoiseLite.new()
	noise.seed = SEED
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	# Частота — у пікселях текстури, не в метрах. При 0,9 кожен піксель
	# уже незалежний, і з двох кроків це зливається в рівний тон — саме
	# так і вийшло з першої спроби. Потрібні плями на пів текстури.
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var grain := NoiseTexture2D.new()
	grain.noise = noise
	grain.width = 256
	grain.height = 256
	grain.seamless = true
	# Крап не має ставати плямами: зводимо його до вузької смуги біля
	# одиниці, інакше земля рябіє, як шкура далматинця.
	grain.color_ramp = Gradient.new()
	grain.color_ramp.set_color(0, Color(1, 1, 1) * (1.0 - strength))
	grain.color_ramp.set_color(1, Color(1, 1, 1))
	paint.albedo_texture = grain
	paint.uv1_triplanar = true
	paint.uv1_scale = Vector3.ONE / maxf(0.5, size)
	return paint


## Поверхня зі справжньою фотографією (П-143, 03.09.2026) — той самий
## трипланарний принцип, що й `_speckled()`, тільки замість шуму поверх
## кольору лягає готова текстура з `models/nature/` (Quaternius Stylized
## Nature MegaKit, CC0). Якщо файлу немає на диску — просто білий
## матеріал: гра має йти без пака, як і з будинками.
func _textured(path: String, size: float) -> StandardMaterial3D:
	var paint := StandardMaterial3D.new()
	paint.roughness = 0.95
	if ResourceLoader.exists(path):
		paint.albedo_texture = load(path)
	paint.uv1_triplanar = true
	paint.uv1_scale = Vector3.ONE / maxf(0.5, size)
	return paint


## Godot стирає ім'я, якщо таке вже є в батька: другий «Будинок» стає
## «@StaticBody3D@8». Тому нумеруємо самі — у редакторі має бути видно,
## де що, а не сорок однакових значків.
var _counts: Dictionary = {}


func _named(word: String) -> String:
	_counts[word] = int(_counts.get(word, 0)) + 1
	return "%s-%d" % [word, _counts[word]]


## Тіло, яке видно й крізь яке не пройти.
func _solid(where: Vector3, mesh: Mesh, shape: Shape3D, color: String,
		name_of: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = _named(name_of)
	body.position = where
	add_child(body)
	var view := MeshInstance3D.new()
	view.name = "Меш"
	view.mesh = mesh
	view.set_surface_override_material(0, _paint(color))
	body.add_child(view)
	var wall := CollisionShape3D.new()
	wall.name = "Стіна"
	wall.shape = shape
	body.add_child(wall)
	return body


## Висота землі в точці. Шум двома шарами: великі пагорби плюс дрібні
## нерівності. Місто вирівнюється до нуля — на схилі не постоїш.
## Небо й туман: тримаємо, щоб міняти дальність тумана під зону бачення.
var _air: Environment
var _noise: FastNoiseLite
## Міста, довкола яких земля вирівнюється. Список, а не одне: світ виріс
## 05.09.2026, і міст у ньому кілька. Старий ключ `місто` (одне) досі
## читається — щоб дані, збережені раніше, не ставали недійсними.
var _flat_spots: Array[Dictionary] = []
## Лишається для сумісності: перше місто зі списку.
var _city_at := Vector3.ZERO
var _city_flat := 0.0


## Усі міста мапи, хай їх одне (`місто`) чи кілька (`міста`).
func towns() -> Array:
	var many: Array = data.get("міста", [])
	# Версія 2: села будуються тим самим кодом, що й міста — вони й
	# відрізняються лише розміром і тим, що мешканців у них поки немає.
	# Рівняти землю під собою мають однаково, тож і в `_flat_spots`
	# мусять потрапити обидва.
	if not many.is_empty():
		return many + data.get("села", []) as Array
	var one: Dictionary = data.get("місто", {})
	return [] if one.is_empty() else [one]


## Висота поля версії 2 в довільній точці: чотири сусідні вузли сітки,
## змішані лінійно. Поза сіткою — край: далі землі просто немає, там
## відкрите море.
func _field_at(x: float, z: float) -> float:
	var fx: float = (x - _origin.x) / _grid_step
	var fz: float = (z - _origin.y) / _grid_step
	var ix := clampi(int(floor(fx)), 0, _grid - 2)
	var iz := clampi(int(floor(fz)), 0, _grid - 2)
	var tx: float = clampf(fx - ix, 0.0, 1.0)
	var tz: float = clampf(fz - iz, 0.0, 1.0)
	var a: float = _relief[iz * _grid + ix]
	var b: float = _relief[iz * _grid + ix + 1]
	var c: float = _relief[(iz + 1) * _grid + ix]
	var d: float = _relief[(iz + 1) * _grid + ix + 1]
	return lerp(lerp(a, b, tx), lerp(c, d, tx), tz)


## Код зони в точці (версія 2). Найближчий вузол, без змішування:
## зона — це число з переліку, середнього між лісом і морем не буває.
func _zone_raw(x: float, z: float) -> int:
	if _grid == 0:
		return 0
	var ix := clampi(roundi((x - _origin.x) / _grid_step), 0, _grid - 1)
	var iz := clampi(roundi((z - _origin.y) / _grid_step), 0, _grid - 1)
	return _zones[iz * _grid + ix]


## Наскільки далеко зміщується вибірка зони, метрів. Дві частоти:
## велика дає затоки й миси на межі, дрібна — зубці по краю.
const ZONE_TEAR_WIDE := 26.0
const ZONE_TEAR_FINE := 8.0
var _tear_wide: FastNoiseLite
var _tear_fine: FastNoiseLite


## Зона зі рваною межею.
##
## На аркуші межі зон розмиті шумом (`zone_soft` у генераторі), але
## на 8-метровій сітці гри це все одно читалось ножовою лінією через
## півсвіту (знімок замовника 05.09.2026). Тут вибірка ще раз зсувається
## шумом — на 26 і 8 метрів — тож замість лінії виходять затоки, миси й
## зубці, і зони заходять одна в одну.
##
## БЕРЕГ НЕ ЧІПАЄМО: якби зсув працював і на морі, суша вилазила б
## клаптями поверх води й навпаки, а берег має лишитись рівно тим, що
## намальовано (проба `world2.gd` міряє саме це).
func _zone_at(x: float, z: float) -> int:
	var base := _zone_raw(x, z)
	if base == 0 or _tear_wide == null:
		return base
	var dx := _tear_wide.get_noise_2d(x, z) * ZONE_TEAR_WIDE \
			+ _tear_fine.get_noise_2d(x, z) * ZONE_TEAR_FINE
	var dz := _tear_wide.get_noise_2d(z + 411.0, x - 173.0) * ZONE_TEAR_WIDE \
			+ _tear_fine.get_noise_2d(z + 97.0, x + 51.0) * ZONE_TEAR_FINE
	var moved := _zone_raw(x + dx, z + dz)
	return base if moved == 0 else moved


func height_at(x: float, z: float) -> float:
	if _grid > 0:
		return _height_v2(x, z)
	if _noise == null:
		return 0.0
	var earth: Dictionary = data.get("земля", {})
	var high := _noise.get_noise_2d(x, z) * float(earth.get("розмах", 7.0))
	# Дрібні нерівності, щоб схили не були гладкі, як стіл.
	high += _noise.get_noise_2d(x * 3.1, z * 3.1) * 0.8
	# Кожне місто вирівнює землю під собою. Береться найближче: міста
	# стоять далеко одне від одного, і накладатись їхні майданчики не
	# мають — а якщо колись стануть, найближче однаково вирішує.
	var edge: float = float(data.get("земля", {}).get("поле", 14))
	var near := 1e9
	var flat := 0.0
	for spot: Dictionary in _flat_spots:
		var where: Vector3 = spot["де"]
		var far: float = Vector2(x - where.x, z - where.z).length()
		if far - float(spot["радіус"]) < near - flat:
			near = far
			flat = float(spot["радіус"])
	if not _flat_spots.is_empty():
		if near < flat:
			return LAND_LIFT
		# М'який перехід від міста до пагорбів: інакше на межі стіна.
		if near < flat + edge:
			high *= (near - flat) / edge

	# Підлога НАД морем, не РІВНО на морі (П-116, П-138): суша острова
	# ніколи не пірнає нижче моря сама собою — шум на розмаху 7,0 проти
	# моря −2,20 топив випадкові латки де завгодно (7% лісу, ціла гора), а
	# латання зона за зоною ганялось за краєм власного ж насипу (тест
	# 03.09.2026: за межею «поле» ефект згасає до нуля, латка вилазить
	# знову — «на обрії»). Запас 0,5 м навмисний: рівно на рівні моря
	# земля й вода лежать в одній площині, і напівпрозора вода поверх
	# співпадаючого ґрунту сама стає тією ж плямою, що й топлення (той
	# самий знімок лісу 03.09.2026 підтвердив — річка лишалась видна й
	# після підлоги рівно на -2,20). Справжнє море лишається морем — це
	# не зачіпає ні його, ні відкриту воду за краєм сітки 240×240 (там
	# `height_at` не рахує взагалі, землі там немає, лише сама площина).
	high = maxf(high, sea_level() + 0.5)

	# Підняті ділянки (П-116, П-138): де самої підлоги мало — окремий
	# майданчик чи насип поверх неї. Два способи: «до» — пласке плато на
	# фіксованій висоті (дно печери), «додати» — природний насип, що
	# зберігає хвилі шуму (лука має лишитись горбистою). Обидва плавно
	# згасають до звичайного рельєфу (уже не нижче моря) за межею «поле».
	for mound: Dictionary in earth.get("підняти", []):
		var center := Vector2(float(mound["де"][0]), float(mound["де"][2]))
		var r: float = float(mound.get("радіус", 10.0))
		var mound_edge: float = float(mound.get("поле", 6.0))
		var d: float = Vector2(x, z).distance_to(center)
		if d >= r + mound_edge:
			continue
		var t: float = 1.0 if d < r else 1.0 - (d - r) / mound_edge
		if mound.has("додати"):
			high += float(mound["додати"]) * t
		else:
			high = maxf(high, lerp(high, float(mound.get("до", 0.0)), t))
	return high + LAND_LIFT


## Висота світу версії 2: поле генератора плюс дрібні нерівності.
##
## LAND_LIFT тут не додається: у полі висота вже в метрах над морем,
## і берег лежить рівно там, де його намальовано на карті. Майданчик
## міста рівняється до ВЛАСНОЇ висоти цього міста, а не до спільної
## сталої, — міста стоять на різних рівнях, від 6 до 58 м.
func _height_v2(x: float, z: float) -> float:
	var earth: Dictionary = data.get("земля", {})
	var high := _field_at(x, z)
	# Нерівності тільки на суші: у морі дно однаково під водою, а
	# берегова смуга від них починала б миготіти вище-нижче за воду.
	if _noise != null and high > sea_level() + 1.0:
		high += _noise.get_noise_2d(x, z) * float(earth.get("розмах", 0.9))

	var edge: float = float(earth.get("поле", 14))
	var near := 1e9
	var flat := 0.0
	var level := 0.0
	for spot: Dictionary in _flat_spots:
		var where: Vector3 = spot["де"]
		var far: float = Vector2(x - where.x, z - where.z).length()
		if far - float(spot["радіус"]) < near - flat:
			near = far
			flat = float(spot["радіус"])
			level = float(spot.get("висота", high))
			edge = float(spot.get("поле", earth.get("поле", 14)))
	if not _flat_spots.is_empty():
		if near < flat:
			return level
		if near < flat + edge:
			high = lerp(level, high, (near - flat) / edge)
	return high


## Чотири сектори поверхні (П-143, 03.09.2026): ліс, поле, пісок,
## каміння — приблизно за чвертю світу від центру міста, за словом
## замовника. Розкладка підігнана під те, де вже стоять зони появи:
## поле (північний схід) — де Meadow; ліс (південний схід) — де Forest і
## DeepForest; пісок (південний захід) — де Cave й Lair; каміння
## (північний захід) — де Ruins і гори.
const SECTORS := ["поле", "ліс", "пісок", "каміння"]
## Пісок — справжня фотографія з набору природи (той самий, що дав скелі).
const SAND_TEXTURE := "res://models/nature/Rocks_Desert_Diffuse.png"

## Ліва-верхня точка сітки землі у світових координатах. Версія 1 —
## завжди (-сторона/2, -сторона/2); версія 2 зсунута під столицю.
var _ground_from := Vector2.ZERO
## Скільки клітинок сітки в боці одного клаптя землі. 44 при кроці 8 м —
## клапоть 352 м, тобто приблизно вшестеро більший за туман; менші
## клапті дали б більше вузлів, ніж економії.
const CHUNK := 44
## Матеріали землі за ключем: той самий ключ тепер трапляється в сотнях
## клаптів, і робити для кожного свій матеріал означало б сотні
## однакових шейдерів.
var _ground_paints: Dictionary = {}


## Матеріал поверхні з кешем.
func _ground_material(key: String, earth: Dictionary) -> StandardMaterial3D:
	if not _ground_paints.has(key):
		_ground_paints[key] = _surface_material(key, earth)
	return _ground_paints[key]


## На скільки поверхонь ділиться земля. Версія 1 — чотири сектори
## (П-143); версія 2 — зони згенерованої карти, бо саме вони й дають
## їй вигляд: крижана північ біла, мертвий схід сірий, вулканічна
## смуга бура. Розділ по секторах на світі 5632 м не значив би нічого.
func _surface_keys() -> Array:
	if _grid == 0:
		return SECTORS
	var keys: Array = []
	for zone: Dictionary in data.get("зони", []):
		keys.append(str(zone.get("назва", "")))
	return keys if not keys.is_empty() else SECTORS


## Наскільки далеко від межі ще малюється перехідна смуга, метрів.
const ZONE_BLEND := 20.0


func _zone_name(code: int) -> String:
	if code >= 0 and code < _zone_names.size() \
			and not _zone_names[code].is_empty():
		return _zone_names[code]
	return _zone_names[0] if not _zone_names.is_empty() else SECTORS[0]


## Яка поверхня в цій точці. Крім самих зон є ще ПЕРЕХІДНІ смуги: якщо
## поруч інша зона, клітинка йде в поверхню «межа: A|B», а її колір —
## середнє двох. Разом із рваною вибіркою вище це дає три сходинки
## кольору замість однієї лінії, і межа читається як перехід, а не як
## обрив. Море в перехід не входить — берег лишається берегом.
func _surface_at(x: float, z: float) -> String:
	if _grid == 0:
		return _sector_at(x, z)
	var code := _zone_at(x, z)
	if code == 0:
		return _zone_name(0)
	# Дві смуги, не одна: ближча мішається навпіл, дальша — на чверть.
	# Разом із рваною вибіркою це чотири сходинки кольору замість
	# однієї лінії, і зона перетікає в зону, а не впирається в неї.
	var found := _zone_beside(x, z, code, ZONE_BLEND)
	if found != 0:
		return _blend_key(code, found, 50)
	found = _zone_beside(x, z, code, ZONE_BLEND * 2.4)
	if found != 0:
		return _blend_key(code, found, 25)
	return _zone_name(code) + _belt_at(_zone_name(code), height_at(x, z))


## Висотні пояси гірських зон: долина зеленіша, вершина білястіша.
##
## На аркуші захід намальовано саме так — «тонування від зелені в
## долинах до біластого на вершинах» (з опису плитки). Однією фарбою
## на всю зону гора виглядала пологим піщаним горбом, а не горою.
## Решти зон це не стосується: там рельєфу мало й пояси нічого не дали б.
const BELT_ZONES := ["гори заходу", "крижана північ"]
## Пороги дібрані знімками: на 70 м біластим ставав увесь верхній
## третину заходу і гора читалась засніженою, хоч на аркуші білясті
## лише самі маківки. 82 з 95,7 — це вони й є.
const BELT_VALLEY := 42.0
const BELT_PEAK := 82.0


func _belt_at(zone_name: String, high: float) -> String:
	if not BELT_ZONES.has(zone_name):
		return ""
	if high < BELT_VALLEY:
		return " · долина"
	if high > BELT_PEAK:
		return " · вершина"
	return ""


## Чи є поруч інша суходільна зона — і яка саме.
func _zone_beside(x: float, z: float, code: int, far: float) -> int:
	for step: Vector2 in [Vector2(far, 0), Vector2(-far, 0),
			Vector2(0, far), Vector2(0, -far),
			Vector2(far, far) * 0.7, Vector2(-far, -far) * 0.7]:
		var near := _zone_at(x + step.x, z + step.y)
		if near != 0 and near != code:
			return near
	return 0


## Ключ перехідної смуги. Частка — наскільки домішано СУСІДНЮ зону;
## порядок імен сталий, щоб дві сусідні клітинки не завели дві
## поверхні на ту саму пару.
func _blend_key(code: int, near: int, share: int) -> String:
	return "межа %d: %s>%s" % [share, _zone_name(code), _zone_name(near)]


func _surface_material(key: String, earth: Dictionary) -> StandardMaterial3D:
	if _grid == 0:
		return _sector_material(key, earth)
	return _zone_material(key)


## Матеріал зони. Пісок, каміння й вулканічну смугу малюють справжні
## фотографії з `models/nature/` (той самий пак, що дав скелі гір),
## решту — трипланарний крап кольором ІЗ ПАЛІТРИ КАРТИ: ті самі числа,
## якими намальовано аркуш, тож зона в грі має колір своєї зони на
## карті, а не підібраний на око.
## Колір зони з палітри карти.
func _zone_colour(name_of: String) -> String:
	for zone: Dictionary in data.get("зони", []):
		if str(zone.get("назва", "")) == name_of:
			return str(zone.get("колір", "#7a8a58"))
	return "#7a8a58"


func _zone_material(key: String) -> StandardMaterial3D:
	if key.begins_with("межа "):
		var share := key.substr(5, key.find(":") - 5).to_int() / 100.0
		var pair := key.substr(key.find(":") + 2).split(">")
		var mixed := Color(_zone_colour(pair[0])) \
				.lerp(Color(_zone_colour(pair[1])), share)
		# Крап дрібніший і сильніший, ніж у самих зон: перехідна смуга
		# має здаватись перемішаним ґрунтом, а не третьою зоною.
		return _speckled("#" + mixed.to_html(false), 9.0, 0.30)
	if key.ends_with(" · долина"):
		var base := Color(_zone_colour(key.trim_suffix(" · долина")))
		return _speckled("#" + base.lerp(Color("#6f8250"), 0.45)
				.to_html(false), 14.0, 0.24)
	if key.ends_with(" · вершина"):
		var top := Color(_zone_colour(key.trim_suffix(" · вершина")))
		return _speckled("#" + top.lerp(Color("#e6e4dc"), 0.45)
				.to_html(false), 16.0, 0.20)
	var tint := _zone_colour(key)
	match key:
		"гори заходу":
			# Камінь крупнішим візерунком: схил має читатись здалеку.
			return _speckled(tint, 18.0, 0.26)
		"море":
			# Дно: те, що видно крізь воду. Крап дрібніший — під водою
			# великі плями читаються як каламуть, а не як пісок.
			return _speckled(tint, 6.0, 0.14)
		_:
			return _speckled(tint, 12.0, 0.22)


## Чому тут немає фотографій каменю й піску, хоч у версії 1 вони є.
##
## Спробувано й заміряно знімком згори 05.09.2026: `Rocks_Diffuse` і
## `Rocks_Desert_Diffuse` тягнуть власний відтінок сильніше за будь-яке
## перефарбування. Гори заходу (на аркуші пісочні, #b09e7e) виходили
## оливкові (116,115,74), південна тераса (#bab08e) — помаранчева
## (255,180,83). Множник на колір зони справді діяв — зелень падала на
## 11%, синь на 27% — і однаково не давав фарби аркуша. Тож усі шість
## зон малює трипланарний крап кольором ІЗ ПАЛІТРИ КАРТИ: зона в грі
## того ж кольору, що й на карті, а не схожого.


static func _sector_at(x: float, z: float) -> String:
	if x >= 0.0:
		return "поле" if z >= 0.0 else "ліс"
	return "каміння" if z >= 0.0 else "пісок"


## Матеріал сектора. Пісок і каміння — справжні фотографії з
## `models/nature/` (той самий пак, що дав скелі гір); ліс і поле
## лишаються трипланарним крапом `_speckled()`, як і брук міста, — просто
## різного кольору.
func _sector_material(key: String, earth: Dictionary) -> StandardMaterial3D:
	match key:
		"пісок":
			return _textured(SAND_TEXTURE, 20.0)
		"каміння":
			return _textured("res://models/nature/Rocks_Diffuse.png", 20.0)
		"поле":
			return _speckled("#8aa050", 12.0, 0.22)
		_:
			return _speckled(str(earth.get("колір", "#5c8a42")), 12.0, 0.22)


## Земля з рельєфом: сітка вершин, висота з шуму, і та сама висота —
## у форму зіткнення. `HeightMapShape3D` бере рівно ті самі числа, тож
## картинка й те, по чому ходять, не розходяться. Візерунок ділиться на
## чотири сектори (вище), колізія лишається одна на всю землю.
func _ground() -> void:
	var earth: Dictionary = data.get("земля", {})
	var side: float = float(earth.get("сторона", 240))
	var step: float = float(earth.get("крок", 4))
	_flat_spots.clear()
	for town: Dictionary in towns():
		# Рівняти землю треба на всю пляму поселення («рівне»), а
		# брук, паркан і будинки стоять у меншому дворі («радіус»):
		# на карті місто — це вся забудова з полями, а не бруківка.
		var spot := {"де": _point(town.get("центр", [0, 0, 0])),
				"радіус": float(town.get("рівне",
						town.get("радіус", 26)))}
		# Версія 2: кожне місто рівняє землю до своєї висоти, не до
		# спільної сталої — вони стоять на різних рівнях.
		if town.has("висота"):
			spot["висота"] = float(town["висота"])
		_flat_spots.append(spot)
	if not _flat_spots.is_empty():
		_city_at = _flat_spots[0]["де"]
		_city_flat = float(_flat_spots[0]["радіус"])
	# Дерева-велети (13.11.2026: «зробив би в 2–3 рази більше масштабу»):
	# стовбур у сотні метрів на прибережному схилі мав би всередині і море,
	# і урвище — тож земля під ним рівняється до висоти його середини, як
	# під містом, лише з довшим переходом до схилу довкола.
	if _grid > 0:
		for mark: Dictionary in data.get("орієнтири", []):
			if str(mark.get("вид", "")) != "дерево-велет":
				continue
			var at := _point(mark.get("де", [0, 0, 0]))
			var giant := GiantTree.spec_near(at.x, at.z)
			if giant.is_empty():
				continue
			_flat_spots.append({"де": at, "радіус": GiantTree.pad_radius(giant),
					"висота": maxf(_field_at(at.x, at.z), sea_level() + 3.0),
					"поле": GiantTree.PAD_EDGE})

	_noise = FastNoiseLite.new()
	_noise.seed = SEED
	_noise.frequency = float(earth.get("частота", 0.012))
	# Шум, яким рветься межа зон. Частоти дібрані під самі зміщення:
	# 0,006 — хвиля завдовжки близько 160 м (затоки й миси), 0,04 —
	# близько 25 м (зубці по краю).
	_tear_wide = FastNoiseLite.new()
	_tear_wide.seed = SEED + 7
	_tear_wide.frequency = 0.006
	_tear_fine = FastNoiseLite.new()
	_tear_fine.seed = SEED + 13
	_tear_fine.frequency = 0.040

	# Початок сітки. Версія 1 центрує світ у (0,0); версія 2 зсунута
	# так, щоб столиця стояла в (0,0) — на цю точку жорстко зав'язані
	# спавн (`world.gd`) і оживлення (`combat.gd`).
	var start := Vector2(-side * 0.5, -side * 0.5)
	if earth.has("початок"):
		var from: Array = earth["початок"]
		start = Vector2(float(from[0]), float(from[1]))
	_ground_from = start

	var points := int(side / step) + 1
	var heights := PackedFloat32Array()
	heights.resize(points * points)
	for iz in points:
		for ix in points:
			var x := start.x + ix * step
			var z := start.y + iz * step
			heights[iz * points + ix] = height_at(x, z)

	var body := StaticBody3D.new()
	body.name = "Земля"
	add_child(body)

	# Версія 1 — теж фото-шари (17.10.2026); сектори лишились запасом,
	# якщо колись знадобиться стара земля.
	_painted_ground(body, heights, points, start, step)

	var shape := HeightMapShape3D.new()
	shape.map_width = points
	shape.map_depth = points
	shape.map_data = heights
	var wall := CollisionShape3D.new()
	wall.name = "Рельєф"
	wall.shape = shape
	# Форма міряє в клітинках по одиниці, а наша клітинка — `крок`.
	wall.scale = Vector3(step, 1.0, step)
	# Форма завжди центрована на своєму вузлі, а сітка версії 2 зсунута
	# (столиця в (0,0), не центр світу) — без цього зсуву земля, по якій
	# ходять, лежала б за кілометри від тієї, яку видно.
	wall.position = Vector3(start.x + side * 0.5, 0.0, start.y + side * 0.5)
	body.add_child(wall)

	_sea()


## Земля світу версії 2: клапті з вагами фото-шарів і ОДИН матеріал.
##
## Клапоть — квадрат `CHUNK` клітинок: коробка меша маленька, і поза
## полем зору він не малюється (06.09.2026, «відеокарта не
## справляється»). Поверхня на клапоть тепер одна: зона, схил, гай і
## берег — це ваги шарів у вершинах, а не окремі меші на кожну зону.
## Зіткнення лишається ОДНЕ на весь світ: фізика нічого не малює.
func _painted_ground(body: StaticBody3D, heights: PackedFloat32Array,
		points: int, start: Vector2, step: float) -> void:
	var started := Time.get_ticks_msec()
	_layers = GroundPaint.new()
	var look: Material = null
	if DisplayServer.get_name() == "headless":
		# Серверові земля — лише число під ногами: ваги й текстури йому
		# ні до чого, а коштували б секунди побудови.
		_layers.shape_only(heights, points, start, step)
	else:
		if _grid > 0:
			_layers.paint(self, heights, points, start, step)
		else:
			_layers.paint_sectors(self, heights, points, start, step)
		look = GroundPaint.material(_path_texture,
				_origin - Vector2.ONE * PATH_STEP * 0.5, _path_side * PATH_STEP,
				PATH_RANGE, PATH_HALF)
	var weighed := Time.get_ticks_msec() - started
	var built := 0
	for cz in range(0, points - 1, CHUNK):
		for cx in range(0, points - 1, CHUNK):
			var patch := Node3D.new()
			patch.name = "Клапоть%d-%d" % [cx / CHUNK, cz / CHUNK]
			var view := MeshInstance3D.new()
			view.name = "Меш-земля"
			view.mesh = _layers.chunk_mesh(cx, cz, CHUNK)
			if look != null:
				view.material_override = look
			patch.add_child(view)
			body.add_child(patch)
			built += 1
	print("[краєвид] земля: клаптів %d, шарів %d, ваги %d мс, усього %d мс"
			% [built, GroundPaint.LAYERS.size(), weighed,
			Time.get_ticks_msec() - started])


## Висота ВИДИМОЇ землі в точці — рівно по трикутнику клаптя.
##
## `height_at()` дає поле з дрібними нерівностями в будь-якій точці, а
## меш землі — площини між вершинами кожні 8 м. Травинка, поставлена
## по `height_at()`, висіла б або тонула на пів метра; по цьому — стоїть.
func surface_y(x: float, z: float) -> float:
	if _layers == null:
		return height_at(x, z)
	return _layers.surface_y(x, z)


## Що росте в точці: r — скільки трави, g — наскільки суха, b — квіти.
func cover_at(x: float, z: float) -> Color:
	if _layers == null:
		return Color(0, 0, 0, 0)
	return _layers.cover_at(x, z)


## Чи точка у дворі поселення (не в полі довкола — там трава росте).
func in_yard(x: float, z: float) -> bool:
	for yard: Vector3 in _yards:
		if Vector2(x - yard.x, z - yard.y).length() < yard.z:
			return true
	return false


## Різнотрав'я — тільки клієнтові світу 2: серверові трава ні до чого,
## об неї не спотикаються.
func _meadow() -> void:
	if _meadow_node != null:
		_meadow_node.queue_free()
		_meadow_node = null
	_yards.clear()
	for town: Dictionary in towns():
		var at: Array = town.get("центр", [0, 0, 0])
		_yards.append(Vector3(float(at[0]), float(at[2]),
				float(town.get("мур радіус", town.get("радіус", 26.0))) + 3.0))
	if _layers == null or _layers.cover.is_empty():
		return
	_meadow_node = Meadow.new()
	_meadow_node.name = "Різнотрав'я"
	add_child(_meadow_node)
	_meadow_node.setup(self)


## Земля світу версії 1: поверхні по секторах (П-143), як і була.
func _sector_ground(body: StaticBody3D, heights: PackedFloat32Array,
		points: int, start: Vector2, step: float, earth: Dictionary) -> void:
	var chunk: int = CHUNK if _grid > 0 else points
	var built := 0
	var meshes := 0
	for cz in range(0, points - 1, chunk):
		for cx in range(0, points - 1, chunk):
			var patch := Node3D.new()
			patch.name = "Клапоть%d-%d" % [cx / chunk, cz / chunk]
			var here := {}
			for iz in range(cz, mini(cz + chunk, points - 1)):
				for ix in range(cx, mini(cx + chunk, points - 1)):
					var a := Vector3(start.x + ix * step,
							heights[iz * points + ix], start.y + iz * step)
					var b := Vector3(a.x + step,
							heights[iz * points + ix + 1], a.z)
					var c := Vector3(a.x, heights[(iz + 1) * points + ix],
							a.z + step)
					var d := Vector3(a.x + step,
							heights[(iz + 1) * points + ix + 1], a.z + step)
					var key := _surface_at(a.x + step * 0.5,
							a.z + step * 0.5)
					if not here.has(key):
						var fresh := SurfaceTool.new()
						fresh.begin(Mesh.PRIMITIVE_TRIANGLES)
						here[key] = fresh
					var st: SurfaceTool = here[key]
					# Порядок за годинниковою стрілкою зверху — інакше
					# нормаль дивиться вниз, і рушій відсікає землю як
					# тильну грань (знайдено 03.09.2026: то й була
					# причина «моря крізь сушу»).
					for corner: Vector3 in [a, b, c, b, d, c]:
						st.add_vertex(corner)
			for key: String in here.keys():
				var st: SurfaceTool = here[key]
				st.generate_normals()
				var mesh := st.commit()
				# Зона може не трапитись жодного разу — порожню
				# поверхню не чіпаємо, інакше падає на матеріалі.
				if mesh == null or mesh.get_surface_count() == 0:
					continue
				var view := MeshInstance3D.new()
				view.name = "Меш-" + key
				view.mesh = mesh
				view.set_surface_override_material(0,
						_ground_material(key, earth))
				patch.add_child(view)
				meshes += 1
			if patch.get_child_count() > 0:
				body.add_child(patch)
				built += 1
	if _grid > 0:
		print("[краєвид] земля: клаптів %d, мешів %d (по %d клітинок)"
				% [built, meshes, chunk])


## Море: рівна вода на своєму рівні. Усе, що нижче, — під водою (П-61).
func _sea() -> void:
	var sea: Dictionary = data.get("море", {})
	if sea.is_empty():
		return
	var side: float = float(data.get("земля", {}).get("сторона", 240))
	var water := PlaneMesh.new()
	water.size = Vector2(side * 1.4, side * 1.4)
	var top := MeshInstance3D.new()
	top.name = "Море"
	top.mesh = water
	var paint := _paint(str(sea.get("колір", "#25506b")))
	paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	paint.albedo_color.a = 0.72
	paint.metallic = 0.3
	paint.roughness = 0.15
	top.set_surface_override_material(0, paint)
	# Центр води — центр СІТКИ, не початок координат: на версії 2 світ
	# зсунутий під столицю, і вода, лишена в (0,0), не діставала б
	# берега на дальньому краю.
	top.position = Vector3(_ground_from.x + side * 0.5,
			float(sea.get("рівень", -2.2)), _ground_from.y + side * 0.5)
	add_child(top)


## Поставити точку на землю: висота береться з того самого рельєфу, по
## якому ходять. Без цього дерева на схилі висіли б у повітрі.
##
## Не нижче моря: шум рельєфу подекуди пірнає під рівень моря й поза
## пляжами (де сама земля цього не показує — вирівнювання діє тільки в
## місті), і все, що ставиться цією функцією, там просто тонуло б —
## заміряно 7% дерев лісу нижче -2,20 м і одну з чотирьох гір, чия основа
## опинялась під водою (той самий клас вади, що П-116, тільки для лісу й
## гір, а не для монстрів).
func _on_ground(point: Vector3) -> Vector3:
	var ground: float = maxf(height_at(point.x, point.z), sea_level())
	return Vector3(point.x, ground + point.y, point.z)


func sea_level() -> float:
	return float(data.get("море", {}).get("рівень", -2.2))


## Місто: брук, будинки з дахами й мешканці.
## Усі міста мапи. Мешканці нумеруються наскрізно через усі міста:
## `resident_at(номер)` мусить лишатись однозначним, інакше клік по
## крамарці в одному місті відкривав би прилавок крамарки в іншому.
func _city() -> void:
	var at := 0
	for town: Dictionary in towns():
		at = _one_city(town, at)


func _one_city(city: Dictionary, first_dweller: int) -> int:
	if city.is_empty():
		return first_dweller
	var center := _point(city.get("центр", [0, 0, 0]))
	# Світ 2 — міста й села як на мапі (план §3г, П-271): мур, брами,
	# вулиці, донжон, доми з фото-текстурами; села — хати вздовж стежки.
	if city.has("мур") or city.has("стежка"):
		TownLook.build(self, city)
		var people: Array = city.get("мешканці", [])
		for i in people.size():
			if str(people[i].get("ремесло", "")) != Wardens.GUARD_CRAFT:
				_dweller(people[i], first_dweller + i)
		return first_dweller + people.size()

	# Брук — тонкий круг, щоб місто було видно згори.
	var road := CylinderMesh.new()
	road.top_radius = float(city.get("радіус", 20))
	road.bottom_radius = road.top_radius
	road.height = 0.2
	var stone := MeshInstance3D.new()
	stone.name = "Брук"
	stone.mesh = road
	# Брук — камінь, і візерунок на ньому має бути дрібніший за земляний.
	stone.set_surface_override_material(0,
			_speckled(str(city.get("колір бруку", "#6e6459")), 4.0, 0.30))
	stone.position = _on_ground(center) + Vector3(0, 0.06, 0)
	add_child(stone)

	for house: Dictionary in city.get("будинки", []):
		var at := _on_ground(_point(house["де"]))
		if house.has("модулі") and ResourceLoader.exists(WALL % "Plaster_Straight"):
			_kit_house(at, house)
		else:
			_house(at, _point(house.get("розмір", [6, 4, 6])),
					str(house.get("колір", "#8a6a4a")),
					str(house.get("дах", "#6b3f2f")))

	var dwellers: Array = city.get("мешканці", [])
	for i in dwellers.size():
		# Вартовий — не нерухомий мешканець, а істота, яку ставить сервер
		# (`Wardens.post_guards`, П-262): клієнт бачить його, як монстра.
		# Номер він однаково займає — нумерація мешканців не зсувається.
		if str(dwellers[i].get("ремесло", "")) == Wardens.GUARD_CRAFT:
			continue
		_dweller(dwellers[i], first_dweller + i)

	_fence(_on_ground(center), float(city.get("радіус", 20)))
	return first_dweller + dwellers.size()


## Дерев'яний паркан по колу міста (Quaternius Medieval Village MegaKit,
## `models/village/`) — розширення світу 03.09.2026. Не фортеця з вежами
## й ворітьми: замовник просив просто паркан, **без воріт**, і вхід
## лишається вільним на всі чотири сторони світу (проходи по 6 м у
## північ/схід/південь/захід). Якщо моделі паркана немає на диску —
## просто нічого не будуємо: паркан — прикраса, не межа гри.
const FENCE_MODEL := "res://models/village/Prop_WoodenFence_Single.gltf"
## Довжина панелі, заміряно `probes/_measure_nature.gd` (разово): 2,0641 м.
const FENCE_PANEL := 2.0641
const FENCE_GATE_WIDTH := 6.0


## Паркан не має жодної випадковості (сама тригонометрія), тож розбити
## на «специфікація/побудова» можна просто фільтром, без турбот про
## порядок `randf()` (на відміну від дерев).
func _fence(center: Vector3, radius: float) -> void:
	if not ResourceLoader.exists(FENCE_MODEL):
		return
	var count := int(TAU * radius / FENCE_PANEL)
	var gate_half: float = (FENCE_GATE_WIDTH / radius) * 0.5
	for i in count:
		# Секція — ХОРДА між двома сусідніми точками кола, а не дотична в
		# точці: так кінці сусідніх секцій сходяться. Було інакше, і між
		# секціями світились проміжки (знімок замовника 12.09.2026).
		var a0 := TAU * i / count
		var a1 := TAU * (i + 1) / count
		var angle := (a0 + a1) * 0.5
		var at_gate := false
		for side in 4:
			if absf(wrapf(angle - side * PI * 0.5, -PI, PI)) < gate_half:
				at_gate = true
				break
		if at_gate:
			continue
		var p0 := center + Vector3(cos(a0), 0, sin(a0)) * radius
		var p1 := center + Vector3(cos(a1), 0, sin(a1)) * radius
		var at := (p0 + p1) * 0.5
		# Прохід і там, де до міста підходить стежка: паркан поперек
		# стежки — це стіна посеред дороги.
		if path_gap(at.x, at.z) < PATH_HALF + 1.2:
			continue
		# Висота — земля ПІД САМОЮ секцією, а не центр міста. Було навпаки,
		# і там, де земля біля краю двору вища, секція на 0,81 м ховалась
		# у ґрунт, а ящик зіткнення на 1,2 м стирчав низькою сходинкою —
		# персонаж на неї вилазив («ти весь час намагаєшся залізти на
		# бридким чином побудований забор», слово замовника 12.09.2026).
		# Нижчий із двох кінців, щоб на схилі не висіла над землею.
		at.y = minf(surface_y(p0.x, p0.z), surface_y(p1.x, p1.z)) - 0.04
		var key := _patch_at(at.x, at.z)
		var spec := {"at": at, "angle": angle, "long": p0.distance_to(p1)}
		_fence_specs.get_or_add(key, []).append(spec)
		if not _streaming or _loaded_sectors.get(key, false):
			_fence_nodes.get_or_add(key, []).append(_fence_panel(spec))


func _fence_panel(spec: Dictionary) -> Node:
	var scene: PackedScene = load(FENCE_MODEL)
	var body := StaticBody3D.new()
	body.name = _named("Паркан")
	body.position = spec["at"]
	# Панель лягає вздовж хорди. Поворот навколо вертикалі в Godot веде
	# вісь X моделі в (cos φ, 0, −sin φ), а дотична до кола в точці θ —
	# (−sin θ, 0, cos θ): отже φ = −θ − 90°. Було +θ + 90° — збігалось
	# лише на чотирьох сторонах світу, а між ними секції ставали поперек
	# кола (знімки замовника 12.09.2026: «паркан не виправлено»).
	body.rotation.y = -float(spec["angle"]) - PI * 0.5
	add_child(body)
	# Модель розтягнута рівно на довжину хорди (різниця — пів відсотка),
	# щоб кінці сусідніх секцій зійшлися.
	var long: float = float(spec.get("long", FENCE_PANEL))
	var view: Node3D = scene.instantiate()
	view.name = "Модель"
	view.scale = Vector3(long / FENCE_PANEL, 1.0, 1.0)
	body.add_child(view)
	_no_shadows(view)
	# Ящик — від трохи нижче землі до 1,2 м: знизу без щілини на схилі,
	# згори вищий за модель (0,81 м), тож на секцію не вилізти.
	var wall := CollisionShape3D.new()
	wall.name = "Стіна"
	var box := BoxShape3D.new()
	box.size = Vector3(long, 1.4, 0.3)
	wall.shape = box
	wall.position = Vector3(0, 0.5, 0)
	body.add_child(wall)
	return body


func _house(where: Vector3, size: Vector3, walls: String, roof: String) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var shape := BoxShape3D.new()
	shape.size = size
	var body := _solid(where + Vector3(0, size.y * 0.5, 0), mesh, shape, walls,
			"Будинок")

	# Дах — чотиригранна піраміда: циліндр із нулем угорі й чотирма гранями.
	var cap := CylinderMesh.new()
	cap.top_radius = 0.0
	cap.bottom_radius = maxf(size.x, size.z) * 0.78
	cap.height = size.y * 0.55
	cap.radial_segments = 4
	var top := MeshInstance3D.new()
	top.name = _named("Дах")
	top.mesh = cap
	top.set_surface_override_material(0, _paint(roof))
	top.position = where + Vector3(0, size.y + cap.height * 0.5, 0)
	top.rotation.y = PI * 0.25
	add_child(top)

	# Дах теж має зіткнення — інакше камера проходить крізь нього так само,
	# як і в наборі кита (П-121, `ROOF_TOP` вище). Коробка замість піраміди:
	# грубіше за форму, зате камеру напевно не пропустить.
	var cap_shape := BoxShape3D.new()
	cap_shape.size = Vector3(cap.bottom_radius * 2.0, cap.height,
			cap.bottom_radius * 2.0)
	var cap_wall := CollisionShape3D.new()
	cap_wall.name = "Дах-стіна"
	cap_wall.shape = cap_shape
	cap_wall.position = Vector3(0, size.y * 0.5 + cap.height * 0.5, 0)
	body.add_child(cap_wall)


## Деталі набору Medieval Village MegaKit (Quaternius, CC0). Сітка в
## наборі стала: стіна 2 метри завширшки й 3,12 заввишки, підлога 2×2,
## дах на 4×4. Тому будинок описується в МОДУЛЯХ — «два на два», — а не
## в метрах: інакше довелось би підганяти числа руками під кожну деталь.
const WALL := "res://models/village/Wall_%s.gltf"
const ROOF_4X4 := "res://models/village/Roof_RoundTiles_4x4.gltf"
const FLOOR := "res://models/village/Floor_Brick.gltf"
const MODULE := 2.0        ## ширина однієї деталі, метрів
const WALL_HEIGHT := 3.12
## Дах ставиться на `WALL_HEIGHT + 0.5` і сам заміряний 4,25 м угору, дном
## на -0,52 від опорної точки (`probes/_measure_roof.gd`, разово) — тобто
## вершина опиняється на 3,62 + 3,73 = 7,35 м, далеко за стінами. Стара
## коробка зіткнення сягала лише WALL_HEIGHT, і камера проходила крізь дах
## наскрізь (П-121): дах узагалі не мав зіткнення.
const ROOF_TOP := 7.35
## Дах звисає за стіни: заміряно, разова деталь ширша за свою клітину
## модулів приблизно на 1,5 м — по 0,75 з кожного боку.
const ROOF_OVERHANG := 0.8


## Будинок, зібраний із деталей набору.
##
## Стіни ставляться по колу: кожна дивиться назовні, бо в деталі
## зовнішній бік — це -Z. Одна зі стін спереду — з дверима, ще кілька —
## з вікнами; решта глухі.
func _kit_house(where: Vector3, house: Dictionary) -> void:
	var modules: Vector2 = _pair(house.get("модулі", [2, 2]))
	var wide := int(maxf(1.0, modules.x))
	var deep := int(maxf(1.0, modules.y))
	var stone: bool = bool(house.get("цегла", false))
	var straight := WALL % ("UnevenBrick_Straight" if stone else "Plaster_Straight")
	var window := WALL % ("UnevenBrick_Window_Wide_Round" if stone
			else "Plaster_Window_Wide_Round")
	var door := WALL % "Plaster_Door_Round"

	var body := StaticBody3D.new()
	body.name = _named("Будинок")
	body.position = where
	body.rotation.y = deg_to_rad(float(house.get("поворот", 0.0)))
	add_child(body)

	var half_x := (wide - 1) * MODULE * 0.5
	var half_z := (deep - 1) * MODULE * 0.5
	var edge_z := deep * MODULE * 0.5
	var edge_x := wide * MODULE * 0.5

	# Двері — посередині ближньої стіни; вікна — через одну деталь.
	var door_at := wide / 2
	for i in wide:
		var x := -half_x + i * MODULE
		_piece(body, door if i == door_at else (window if i % 2 == 0
				else straight), Vector3(x, 0, edge_z), 0.0)
		# Лице модуля набору — його +z (цоколь, балки); перед і зад
		# стояли 180/0 — лицем усередину (знайдено 06.11.2026).
		_piece(body, window if i % 2 == 1 else straight,
				Vector3(x, 0, -edge_z), 180.0)
	for i in deep:
		var z := -half_z + i * MODULE
		_piece(body, window if i % 2 == 0 else straight,
				Vector3(-edge_x, 0, z), 270.0)
		_piece(body, straight, Vector3(edge_x, 0, z), 90.0)

	# Підлога всередині.
	for ix in wide:
		for iz in deep:
			_piece(body, FLOOR, Vector3(-half_x + ix * MODULE, 0.02,
					-half_z + iz * MODULE), 0.0)

	# Дах: одна деталь на кожні 2×2 модулі.
	for ix in range(0, wide, 2):
		for iz in range(0, deep, 2):
			var at := Vector3(-half_x + (ix + minf(1, wide - ix - 1)) * MODULE * 0.5,
					WALL_HEIGHT + 0.5, -half_z + (iz + minf(1, deep - iz - 1)) * MODULE * 0.5)
			_piece(body, ROOF_4X4, at, 0.0)

	# Крізь будинок не пускає одна коробка на весь обрис — і вона мусить
	# накривати ДАХ, а не спинятись на стінах (П-121, див. ROOF_TOP).
	var shape := BoxShape3D.new()
	shape.size = Vector3(wide * MODULE + ROOF_OVERHANG * 2.0, ROOF_TOP,
			deep * MODULE + ROOF_OVERHANG * 2.0)
	var wall := CollisionShape3D.new()
	wall.name = "Стіна"
	wall.shape = shape
	wall.position = Vector3(0, ROOF_TOP * 0.5, 0)
	body.add_child(wall)


## Одна деталь на своєму місці.
func _piece(parent: Node3D, path: String, at: Vector3, turn: float) -> void:
	if not ResourceLoader.exists(path):
		return
	var scene: PackedScene = load(path)
	if scene == null:
		return
	var part: Node3D = scene.instantiate()
	part.position = at
	part.rotation.y = deg_to_rad(turn)
	parent.add_child(part)


static func _pair(from: Variant) -> Vector2:
	var list: Array = from
	return Vector2(float(list[0]), float(list[1]))


## Вимкнути тіні на всіх мешах усередині моделі. Заміряно 03.09.2026: із
## тінями від 70 дерев і паркану довкола міста показ ішов 1 кадр за
## секунду; дерева й скелі — прикраса на видноті, а не те, що кидає тінь
## на бій, тож вимикати безпечно.
static func _no_shadows(node: Node) -> void:
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = child
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Будинок із готової моделі (крок 6, П-15).
##
## Модель дає лише вигляд; крізь що не пройти — окрема коробка за її
## розміром. Так зроблено навмисно: у гарних моделях геометрія дрібна, і
## зіткнення по ній коштувало б дорожче за саму картинку, а гравцеві
## однаково важливо тільки те, що всередину не зайти.
##
## Якщо моделі немає на диску, будинок лишається коробкою: гра має
## запускатися й без завантажених паків.
func _model_house(where: Vector3, path: String, house: Dictionary) -> void:
	var scene: PackedScene = load(path)
	if scene == null:
		_house(where, _point(house.get("розмір", [6, 4, 6])),
				str(house.get("колір", "#8a6a4a")),
				str(house.get("дах", "#6b3f2f")))
		return
	var body := StaticBody3D.new()
	body.name = _named("Будинок")
	body.position = where
	body.rotation.y = deg_to_rad(float(house.get("поворот", 0.0)))
	add_child(body)

	var view: Node3D = scene.instantiate()
	view.name = "Модель"
	var scale := float(house.get("масштаб", 1.0))
	view.scale = Vector3(scale, scale, scale)
	body.add_child(view)

	# Коробка за розміром самої моделі: не треба вгадувати числа руками.
	var box := _size_of(view) * scale
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(box.x, 0.5), maxf(box.y, 0.5), maxf(box.z, 0.5))
	var wall := CollisionShape3D.new()
	wall.name = "Стіна"
	wall.shape = shape
	wall.position = Vector3(0, shape.size.y * 0.5, 0)
	body.add_child(wall)


## Розмір моделі: збираємо межі всіх мешів усередині.
static func _size_of(node: Node) -> Vector3:
	var box := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = child
		if mesh.mesh == null:
			continue
		var part := mesh.transform * mesh.mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box.size if not first else Vector3(4, 3, 4)


## Мешканець за номером. Сервер шукає ним того, з ким гравець говорить.
func resident_at(at: int) -> NPC:
	for child in get_children():
		if child is NPC and child.at_index == at:
			return child
	return null


## Мешканець: капсула на своєму місці. Крамар ще й торгує (П-132).
func _dweller(who: Dictionary, at: int) -> void:
	var body := NPC.new()
	body.name = "Мешканець-" + str(who.get("хто", "мешканець"))
	body.who = str(who.get("хто", "мешканець"))
	body.craft = str(who.get("ремесло", ""))
	body.at_index = at
	body.goods = who.get("товар", [])
	body.tint = Color(str(who.get("колір", "#75706a")))
	body.position = _on_ground(_point(who["де"])) + Vector3(0, 1.0, 0)
	# Біля своєї будівлі мешканець стоїть обличчям до площі (06.11.2026).
	if who.has("поворот"):
		body.rotation.y = deg_to_rad(float(who["поворот"]))
	# Шар «мешканці» (третій, тобто 4): промінь миші шукає і його теж,
	# інакше клік по мешканцеві пролітає крізь нього — на цьому й
	# спіймався замовник під час першої ж проби.
	body.collision_layer = 4
	add_child(body)

	# Мешканці — та сама модель людини, що й гравці (замовник просив
	# 05.09.2026): стать — за останньою літерою імені («Ліда» → жінка,
	# «Горан»/«Отець Мирон» → чоловік — свою назву, не титул, завжди
	# останню в рядку). Стоять нерухомо, але з анімацією спілкування
	# (Idle_Talking, не Idle) — сигнал «до нього можна підійти», навіть
	# коли самого вікна розмови ще нема (П-113).
	var name_ends: String = str(who.get("хто", "")).strip_edges()
	var is_female: bool = name_ends.ends_with("а") or name_ends.ends_with("я")
	var made: String = AvatarScript.MODEL_FEMALE if is_female \
			else AvatarScript.MODEL_MALE
	var figure := SkinnedModel.new()
	figure.name = "Mesh"
	figure.path = made
	figure.anim_path = AvatarScript.MODEL_ANIM
	figure.height = 1.75
	body.add_child(figure)
	figure.build()
	figure.show_move("Idle_Talking")
	body.show_name()
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	shape.position = Vector3(0, 0.1, 0)
	body.add_child(shape)


## Орієнтири світу версії 2: некрополі, руїни, дерева-велети, вулкани й
## обеліски — ті самі 25 іменних об'єктів, що стоять на згенерованій
## карті, у тих самих місцях.
##
## Це прикраса, а не механіка: жодного вікна, жодної здобичі. Потрібні
## вони для того, за чим і потрібна карта, — щоб було по чому впізнати,
## де ти. Форми складаються з уже наявних наборів (ті самі дерева,
## скелі й стіни, що в лісі, горах і святинях), нічого нового на диск
## не додається.
func _landmarks() -> void:
	# Повторна побудова (проби будують світ удруге) — дерева-велети не
	# подвоюються: за номером дерева звертаються сервер і клієнт.
	for old: GiantTree in giant_trees():
		remove_child(old)
		old.queue_free()
	for mark: Dictionary in data.get("орієнтири", []):
		var kind := str(mark.get("вид", ""))
		# Тільки x і z: середнє число в даних — підйом над землею, і
		# орієнтир мусить стояти НА ґрунті, хай там що в даних.
		var spot := _point(mark.get("де", [0, 0, 0]))
		# Дерево-велет із поверхами (`data/dereva.json`, 07.11.2026) — ціле
		# місце для полювання, а не прикраса: своя побудова.
		if kind == "дерево-велет":
			var giant := GiantTree.spec_near(spot.x, spot.z)
			if not giant.is_empty():
				var tree := GiantTree.new()
				add_child(tree)
				tree.position = Vector3(spot.x, 0.0, spot.z)
				tree.build(giant, self, DisplayServer.get_name() != "headless")
				# Ті самі два виклики випадковості, що з'їв би `_giant_tree`:
				# інакше зсунувся б розкид усього, що будується далі.
				randi()
				randf()
				continue
		var at := _on_ground(Vector3(spot.x, 0.0, spot.z))
		var radius := float(mark.get("радіус", 20))
		var holder := Node3D.new()
		holder.name = _named(kind.capitalize())
		holder.position = at
		add_child(holder)
		match kind:
			"дерево-велет":
				_giant_tree(holder)
			"вулкан":
				_volcano(holder, radius)
			"некрополь":
				_necropolis(holder, radius)
			"руїни":
				_ruin_field(holder, radius)
			_:
				_stone_pillar(holder, 9.0)


## Дерево-велет: та сама модель, що й у лісі, але «у рази більше за
## звичайні дерева» — так його описує сам аркуш карти.
func _giant_tree(holder: Node3D) -> void:
	# Криве дерево з набору — саме те, чим має бути дерево-велет:
	# власна висота 16-19 м проти семи в звичайного, і крона іншого
	# кольору. На схилах гір воно виглядало чужим (надто червоне), а
	# поодиноким велетнем на рівнині — як і задумано на аркуші.
	var list: Array = PLANTS["кривуля"]
	var pick: Array = list[randi() % list.size()]
	var path: String = "res://models/nature/%s.gltf" % pick[0]
	if not ResourceLoader.exists(path):
		_stone_pillar(holder, 20.0)
		return
	var view: Node3D = (load(path) as PackedScene).instantiate()
	var scale := 1.35
	view.scale = Vector3(scale, scale, scale)
	view.rotation.y = randf() * TAU
	holder.add_child(view)
	_no_shadows(view)


## Вулкан: конус із заглибленим жерлом. Готової моделі в наборах немає,
## тож примітив — той самий запасний шлях, що й для обеліска (П-15).
func _volcano(holder: Node3D, radius: float) -> void:
	var cone := CylinderMesh.new()
	cone.bottom_radius = radius * 0.8
	cone.top_radius = radius * 0.22
	cone.height = radius * 0.55
	var view := MeshInstance3D.new()
	view.mesh = cone
	view.position = Vector3(0, cone.height * 0.5, 0)
	view.set_surface_override_material(0, _speckled("#4a3c34", 6.0, 0.30))
	holder.add_child(view)
	var mouth := MeshInstance3D.new()
	var glow := CylinderMesh.new()
	glow.top_radius = radius * 0.20
	glow.bottom_radius = radius * 0.20
	glow.height = 0.4
	mouth.mesh = glow
	mouth.position = Vector3(0, cone.height - 0.1, 0)
	var lava := StandardMaterial3D.new()
	lava.albedo_color = Color("#a85a34")
	lava.emission_enabled = true
	lava.emission = Color("#a85a34")
	lava.emission_energy_multiplier = 1.4
	mouth.set_surface_override_material(0, lava)
	holder.add_child(mouth)
	var wall := StaticBody3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius * 0.7
	shape.height = cone.height
	var box := CollisionShape3D.new()
	box.shape = shape
	box.position = Vector3(0, cone.height * 0.5, 0)
	wall.add_child(box)
	holder.add_child(wall)


## Некрополь: поле надгробків із обеліском посередині.
func _necropolis(holder: Node3D, radius: float) -> void:
	_stone_pillar(holder, 12.0)
	var stone := _paint("#8e8880")
	for i in 24:
		var turn := TAU * float(i) / 24.0 + randf() * 0.2
		var far := radius * (0.30 + 0.55 * sqrt(randf()))
		var slab := MeshInstance3D.new()
		var block := BoxMesh.new()
		block.size = Vector3(0.9, randf_range(1.2, 2.2), 0.28)
		slab.mesh = block
		# Земля береться в СВІТОВІЙ точці, але з нульовим підйомом:
		# `holder.position` уже на ґрунті, і якби ми додали його в
		# `_on_ground`, надгробок піднявся б на подвійну висоту — саме
		# так обеліски й полетіли в небо (05.09.2026).
		var spot := Vector3(cos(turn) * far, 0.0, sin(turn) * far)
		var world := holder.position + spot
		slab.position = _on_ground(Vector3(world.x, 0.0, world.z)) \
				- holder.position + Vector3(0, block.size.y * 0.5, 0)
		slab.rotation.y = randf() * TAU
		slab.set_surface_override_material(0, stone)
		holder.add_child(slab)


## Руїни: уламки стін, розкидані плямою. Стіни ті самі, що в будинках.
func _ruin_field(holder: Node3D, radius: float) -> void:
	var wall_path: String = WALL % "Plaster_Straight"
	for i in 10:
		var turn := TAU * float(i) / 10.0 + randf() * 0.3
		var far := radius * (0.2 + 0.6 * randf())
		var spot := Vector3(cos(turn) * far, 0.0, sin(turn) * far)
		var piece: Node3D
		if ResourceLoader.exists(wall_path):
			piece = (load(wall_path) as PackedScene).instantiate()
			piece.scale = Vector3(1.0, randf_range(0.3, 0.9), 1.0)
		else:
			piece = MeshInstance3D.new()
			var block := BoxMesh.new()
			block.size = Vector3(2.0, randf_range(1.0, 2.6), 0.3)
			(piece as MeshInstance3D).mesh = block
		var world := holder.position + spot
		piece.position = _on_ground(Vector3(world.x, 0.0, world.z)) \
				- holder.position
		piece.rotation.y = randf() * TAU
		holder.add_child(piece)


## Кам'яний стовп — обеліск. Форма та сама, що в святинь
## (`shrine.gd:_obelisk`), тільки без грейду й рун: тут це орієнтир.
func _stone_pillar(holder: Node3D, height: float) -> void:
	var stone := _paint("#57545c")
	var shaft := MeshInstance3D.new()
	var body := BoxMesh.new()
	body.size = Vector3(height * 0.16, height, height * 0.16)
	shaft.mesh = body
	shaft.position = Vector3(0, height * 0.5, 0)
	shaft.set_surface_override_material(0, stone)
	holder.add_child(shaft)
	var tip := MeshInstance3D.new()
	var top := CylinderMesh.new()
	top.top_radius = 0.0
	top.bottom_radius = height * 0.12
	top.height = height * 0.18
	top.radial_segments = 4
	tip.mesh = top
	tip.position = Vector3(0, height * 1.09, 0)
	tip.rotation.y = PI * 0.25
	tip.set_surface_override_material(0, stone)
	holder.add_child(tip)


## Святині (П-153) — точки, біля яких відкривають портал у підземелля.
##
## Беруться з даних, а не кидаються випадково: рішення каже
## «заздалегідь вибрані об'єкти», і саме тому перелік заморожений у
## `map.json` (як будинки й гори). Стрімінгом не чіпаються: їх 31 на
## весь світ, вони дешеві, і зникати вони не мають — по них гравець
## орієнтується.
func _shrines() -> void:
	var guard: Dictionary = data.get("охорона святинь", {})
	for spot: Dictionary in data.get("святині", []):
		var shrine := Shrine.new()
		shrine.name = _named("Святиня")
		shrine.form = str(spot.get("форма", "камінь"))
		shrine.grade = str(spot.get("грейд", "E"))
		shrine.shard_red = str(spot.get("уламки", "сині")) == "червоні"
		add_child(shrine)
		shrine.position = _on_ground(_point(spot["де"]))
		# Портал за 5 м убік — на ЗЕМЛІ там, а не на висоті святині.
		var gate := shrine.position + Shrine.PORTAL_AT
		shrine.portal_lift = _on_ground(Vector3(gate.x, 0.0, gate.z)).y \
				- shrine.position.y
		if not guard.is_empty():
			_shrine_guard(shrine, _guard_for(guard, shrine.grade,
					spot.get("охорона", {})))


## Скупчення монстрів довкола святині — НЕ впритул до неї, а кільцем на
## відстані (П-153). Кільце робиться кількома малими формами, а не одним
## великим циліндром: `MobZone` бере точку з-поміж дочірніх форм
## пропорційно об'єму, тож кілька форм по колу дають саме кільце, і в
## самої святині ніхто не з'являється.
##
## Зона стає дитиною святині — тоді `world.gd:_zones()`, який шукає
## `MobZone` по всьому дереву, підбирає її сам, і другого списку зон
## заводити не треба.
## Налаштування охорони для однієї святині — три шари, знизу вгору
## (слово замовника 20.09.2026: «хочу тонкі налаштування охорони,
## скільки монстрів, як далеко від святині»):
##
##   1. загальні числа `охорона святинь`;
##   2. `за грейдом` — свої для E, D, … SS;
##   3. `охорона` в самій святині — для однієї окремої.
##
## Кожен шар перекриває лише ті ключі, які назвав, тож щоб зробити одну
## святиню лютішою, досить одного рядка в ній, а не копії всього.
func _guard_for(guard: Dictionary, grade: String,
		mine: Dictionary) -> Dictionary:
	var out := guard.duplicate(true)
	var by_grade: Dictionary = guard.get("за грейдом", {})
	for key: String in by_grade.get(grade, {}):
		out[key] = by_grade[grade][key]
	for key: String in mine:
		out[key] = mine[key]
	# Старий вигляд даних: вид лежав окремою таблицею «вид за грейдом».
	if not out.has("вид"):
		var old: Dictionary = guard.get("вид за грейдом", {})
		out["вид"] = int(old.get(grade, 1))
	return out


func _shrine_guard(shrine: Shrine, guard: Dictionary) -> void:
	# Охорона стоїть КУПКАМИ по колу, і в кожній купці свій главар
	# (слово замовника 20.09.2026: «в грейдах E, D, C — був один главарь
	# того виду який кидається на перехожих та викликає на допомогу»).
	#
	# Главар і помічники — того самого ВИДУ: поклик на поміч чують лише
	# свої того самого виду (`creature.gd`), тож різні види в купці
	# зробили б заклик німим.
	#
	# Купки навмисно далеко одна від одної: поклик має піднімати СВОЮ
	# купку, а не всі одразу («не пересікаються» — слово замовника).
	# Відстань між сусідніми купками перевіряє проба `guard`.
	var kind := int(guard.get("вид", 1))
	var groups := maxi(1, int(guard.get("купок", guard.get("кілець", 4))))
	var chiefs := int(guard.get("главарів", 0))
	var helpers := int(guard.get("помічників", 0))
	if chiefs <= 0 and helpers <= 0:
		# Старий вигляд даних: просто «скільки» на все кільце.
		helpers = maxi(1, int(guard.get("скільки", 3)))
		groups = 1
	var far := float(guard.get("відстань", 14.0))
	var spread := float(guard.get("розкид", 4.0))
	var back := float(guard.get("вертається через", 180.0))
	for i in groups:
		var turn := TAU * float(i) / float(groups)
		var at := Vector3(cos(turn) * far, 0.0, sin(turn) * far)
		if chiefs > 0:
			# Главар сидить у самій середині купки: тоді помічники
			# завжди в межах його поклику, а сусідня купка — ні.
			_guard_zone(shrine, "Главар%d" % (i + 1), kind, chiefs,
					true, at, spread * 0.35, back)
		if helpers > 0:
			_guard_zone(shrine, "Охорона%d" % (i + 1), kind, helpers,
					false, at, spread, back)


## Одна купка: `MobZone` дитиною святині, щоб `world.gd:_zones()`
## підібрав її сам, і одна форма — щоб монстри стали саме тут.
func _guard_zone(shrine: Shrine, name: String, kind: int, count: int,
		angry: bool, at: Vector3, radius: float, back: float) -> void:
	var zone := MobZone.new()
	zone.name = name
	zone.kind = kind
	zone.count = count
	zone.aggressive = angry
	zone.respawn_after = back
	zone.respawn_spread = 20.0
	shrine.add_child(zone)
	var shape := CollisionShape3D.new()
	var ball := CylinderShape3D.new()
	ball.radius = maxf(0.5, radius)
	ball.height = 4.0
	shape.shape = ball
	shape.position = at
	zone.add_child(shape)


## Дерева-велети з поверхами — у порядку даних (`data/dereva.json`):
## сервер і клієнт звертаються до дерева за номером.
func giant_trees() -> Array[GiantTree]:
	var out: Array[GiantTree] = []
	for child in get_children():
		if child is GiantTree:
			out.append(child)
	return out


## Усі святині в тому самому порядку, що й у даних. Порядок важить:
## сервер шле клієнтові стан святині НОМЕРОМ, а не іменем вузла.
func shrines() -> Array[Node]:
	var out: Array[Node] = []
	for child in find_children("Святиня*", "", false, false):
		out.append(child)
	return out


## Де стоять святині — щоб не читати даних удруге.
func shrine_spots() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for child in shrines():
		out.append(child.global_position)
	return out


## Ліс: дерева з розкидом по колу, кожне трохи іншої висоти.
## Дерева рахуються завжди в тому самому порядку виклику `randf()` —
## розкид лишається однаковим і на сервері, і в кожного клієнта (П-63
## не сміє це порушити), незалежно від того, коли саме дерево з'явиться
## на екрані.
## Усі ліси мапи. Список (`ліси`), але старий ключ `ліс` (один) досі
## читається — світ виріс 05.09.2026, а дані лишились чинні.
##
## Порядок обходу — той, що в даних, і випадковість витрачається строго
## по ньому: інакше дерева виростали б на різних місцях у сервера й
## клієнта (та сама пастка, що вже ловила П-63).
## Рослинність світу версії 2: не перелік дерев, а РОЗКИД ЗА ПРАВИЛАМИ.
##
## Слово замовника 05.09.2026: «навіть гори немає дерев, річок та
## іншого, тільки поверхня». Сорок кіл-гаїв на 17 км² справді лишали
## між собою голу землю. Тепер кожна зона має своє правило (густота,
## види, межа лісу), а дерева садяться по всій своїй зоні.
##
## Випадковість витрачається В ОДНОМУ проході й до підвантаження — так
## само, як у `_one_forest()`: інакше розкид розійшовся б на сервері
## й у клієнта, і дерево стояло б у різних людей у різних місцях.
## Сітка кандидатів, метрів. 20 давало одну рослину на 37 м — на
## відкритому схилі це порожньо; 12 дає гай, у якому дерева видно одне
## за одним. Число в даних (`земля.сітка рослин`), бо це той самий
## випадок, що й П-72: підбирається в грі, не на папері.
const GREEN_STEP := 12.0
const GREEN_JITTER := 5.0       ## на скільки кандидат зсувається вбік
## Яка частка клітинок у серцевині хвойного гаю дістає брилу, пень чи
## колоду. Підібрано знімками, не словом замовника.
const FOREST_BITS := 0.10
const FOREST_KINDS := ["брила", "пень", "колода"]


func _greenery() -> void:
	var rules: Array = data.get("рослинність", [])
	if rules.is_empty():
		return
	var earth: Dictionary = data.get("земля", {})
	var side: float = float(earth.get("сторона", 240))
	var by_zone := {}
	var clumps := {}
	for rule: Dictionary in rules:
		var zone := int(rule.get("зона", -1))
		by_zone[zone] = rule
		var noise := FastNoiseLite.new()
		noise.seed = SEED + zone * 31
		noise.frequency = float(rule.get("клуб", 0.012))
		clumps[zone] = noise

	var sea := sea_level()
	var placed := 0
	var grid_of: float = float(earth.get("сітка рослин", GREEN_STEP))
	var steps := int(side / grid_of)
	for iz in steps:
		for ix in steps:
			var x := _ground_from.x + (ix + 0.5) * grid_of \
					+ randf_range(-GREEN_JITTER, GREEN_JITTER)
			var z := _ground_from.y + (iz + 0.5) * grid_of \
					+ randf_range(-GREEN_JITTER, GREEN_JITTER)
			var zone := _zone_at(x, z)
			if not by_zone.has(zone):
				continue
			var rule: Dictionary = by_zone[zone]
			var step_of: float = float(rule.get("крок", GREEN_STEP))
			var chance: float = float(rule.get("густота", 0.4)) \
					* pow(grid_of / step_of, 2.0)
			if randf() > chance:
				continue
			var clump: FastNoiseLite = clumps[zone]
			var edge: float = float(rule.get("поріг", 0.0))
			var noise_here: float = clump.get_noise_2d(x, z)
			if noise_here < edge:
				continue
			# Що глибше в гаю, то більше дерев на ту саму клітинку.
			# Одне дерево на клітинку давало саван — рідкі поодинокі
			# стовбури; замовник показав, що чекає СТІНУ стовбурів у
			# гаю й галявину між гаями. Тому кількість росте від сили
			# шуму: на краю гаю одне, у серцевині шість-сім.
			var strength: float = clampf((noise_here - edge)
					/ maxf(0.001, 1.0 - edge), 0.0, 1.0)
			var many: float = chance * (1.0
					+ strength * float(rule.get("гай", 0.0)))
			var count := int(many)
			if randf() < many - count:
				count += 1
			var kinds: Array = rule.get("види", ["дерево"])
			var span: Array = rule.get("розмір", rule.get("висота",
					[0.8, 1.2]))
			var top: float = float(rule.get("вище нема", 1e9))
			for k in count:
				var px := x + randf_range(-grid_of, grid_of) * 0.5
				var pz := z + randf_range(-grid_of, grid_of) * 0.5
				var ground := height_at(px, pz)
				if ground <= sea + 0.6 or ground > top:
					continue
				if _in_settlement(px, pz):
					continue
				# На стежці нічого не росте — інакше вона не стежка.
				if path_gap(px, pz) < PATH_HALF + 1.6:
					continue
				var kind := str(kinds[randi() % kinds.size()])
				var size := randf_range(float(span[0]), float(span[1]))
				_place_plant(Vector3(px, ground, pz), kind, size)
				placed += 1
				var tally: int = int(by_zone[zone].get("_скільки", 0))
				by_zone[zone]["_скільки"] = tally + 1
			# Серцевина хвойного гаю: брила, пень чи колода. Той самий потік
			# випадковості, що й у дерев, — на сервері й у клієнта однаково.
			if kinds.has("хвоя") and strength > 0.35 and randf() < FOREST_BITS:
				var bit_x := x + randf_range(-grid_of, grid_of) * 0.5
				var bit_z := z + randf_range(-grid_of, grid_of) * 0.5
				var bit := str(FOREST_KINDS[randi() % FOREST_KINDS.size()])
				var bit_size := randf_range(0.8, 1.2)
				var bit_ground := height_at(bit_x, bit_z)
				if bit_ground > sea + 0.6 and not _in_settlement(bit_x, bit_z) \
						and path_gap(bit_x, bit_z) > PATH_HALF + 1.0:
					_place_plant(Vector3(bit_x, bit_ground, bit_z), bit,
							bit_size)
					placed += 1
	var parts := PackedStringArray()
	for rule: Dictionary in rules:
		parts.append("%s %d" % [rule.get("назва", "?"),
				int(rule.get("_скільки", 0))])
	print("[краєвид] рослин розкидано: %d (%s)" % [placed, ", ".join(parts)])


## Чи точка в поселенні (або в його полі): там садити не можна.
func _in_settlement(x: float, z: float) -> bool:
	for spot: Dictionary in _flat_spots:
		var where: Vector3 = spot["де"]
		if Vector2(x - where.x, z - where.z).length() \
				< float(spot["радіус"]) + 6.0:
			return true
	return false


## Що з чого росте. Ключ — вид із даних, значення — моделі набору
## природи з їхньою ЗМІРЯНОЮ висотою (проба `--рослини` друкує ті самі
## числа). Висота потрібна не для масштабування «під розмір», а для
## зіткнення: моделі вже зроблені в людський масштаб, і найприродніше
## вони виглядають, коли їх майже не тягнути — звідси розмір близько 1.
##
## Було шість моделей на весь світ, і ліс через це виглядав
## штампованим (слово замовника 06.09.2026: «дерева виглядають
## неправдоподібно»). Тепер їх сорок дві, чотири роди дерев.
const PLANTS := {
	"дерево": [["CommonTree_1", 7.02], ["CommonTree_2", 7.40],
			["CommonTree_3", 9.18], ["CommonTree_4", 9.20],
			["CommonTree_5", 6.76]],
	"сосна": [["Pine_1", 7.08], ["Pine_2", 7.14], ["Pine_3", 7.16],
			["Pine_4", 10.00], ["Pine_5", 8.49]],
	"кривуля": [["TwistedTree_1", 16.52], ["TwistedTree_2", 18.75],
			["TwistedTree_3", 15.87], ["TwistedTree_4", 18.54],
			["TwistedTree_5", 15.46]],
	"сухе дерево": [["DeadTree_1", 9.16], ["DeadTree_2", 11.15],
			["DeadTree_3", 12.94], ["DeadTree_4", 12.44],
			["DeadTree_5", 16.10]],
	"кущ": [["Bush_Common", 1.35], ["Bush_Common_Flowers", 1.35],
			["Fern_1", 0.76], ["Plant_1_Big", 2.31], ["Plant_1", 0.98]],
	"трава": [["Grass_Common_Short", 1.31], ["Grass_Common_Tall", 1.84],
			["Grass_Wispy_Short", 0.99], ["Grass_Wispy_Tall", 1.64],
			["Clover_1", 1.13], ["Clover_2", 1.26]],
	"квіти": [["Flower_3_Group", 2.02], ["Flower_4_Group", 2.43],
			["Mushroom_Common", 0.45]],
	"камінь": [["Rock_Medium_1", 1.99], ["Rock_Medium_2", 1.85],
			["Rock_Medium_3", 2.00]],
	"камінець": [["Pebble_Round_1", 0.09], ["Pebble_Round_2", 0.09],
			["Pebble_Round_3", 0.10]],
}


## Фотоскани Poly Haven (CC0, `models/nature/scan/`): файл · частина
## моделі · ЗМІРЯНА висота й ширина (метри, з самого glTF) · множник,
## яким вона ставиться. Мультяшних кущів і каміння Quaternius у світі 2
## більше немає: замовник хоче реалістично (06.09.2026 — «дерева
## виглядають неправдоподібно», 11.09.2026 — «більш реалістично»).
##
## Скан — справжній розмір у метрах: камінь із мохом 0,5-1,8 м, а от
## папороть і кропива зняті маленькими (0,2-0,4 м), тож їм множник.
## Трава й квіти світу 2 сюди не входять — це різнотрав'я `meadow.gd`.
const SCANS := {
	"кущ": [
		["fern_02", "fern_02_a", 0.29, 0.55, 2.2],
		["fern_02", "fern_02_b", 0.43, 0.89, 2.0],
		["fern_02", "fern_02_c", 0.35, 0.77, 2.1],
		["fern_02", "fern_02_d", 0.21, 0.57, 2.4],
		["nettle_plant", "nettle_plant_tall_a_LOD0", 0.22, 0.09, 5.0],
		["nettle_plant", "nettle_plant_tall_b_LOD0", 0.19, 0.08, 5.2],
		["nettle_plant", "nettle_plant_medium_a_LOD0", 0.13, 0.07, 5.5],
	],
	"камінь": [
		["rock_moss_set_01", "rock_moss_set_01_rock01", 1.47, 2.24, 1.0],
		["rock_moss_set_01", "rock_moss_set_01_rock02", 1.26, 2.66, 1.0],
		["rock_moss_set_01", "rock_moss_set_01_rock03", 1.10, 2.08, 1.0],
		["rock_moss_set_01", "rock_moss_set_01_rock04", 1.77, 1.96, 1.0],
		["rock_moss_set_01", "rock_moss_set_01_rock05", 1.21, 1.82, 1.0],
		["rock_moss_set_01", "rock_moss_set_01_rock06", 1.26, 2.13, 1.0],
		["rock_moss_set_02", "rock_moss_set_02_rock07", 0.74, 1.22, 1.3],
		["rock_moss_set_02", "rock_moss_set_02_rock08", 0.53, 0.98, 1.4],
		["rock_moss_set_02", "rock_moss_set_02_rock09", 0.61, 1.01, 1.4],
		["rock_moss_set_02", "rock_moss_set_02_rock10", 0.77, 1.55, 1.3],
		["rock_moss_set_02", "rock_moss_set_02_rock11", 1.31, 1.53, 1.0],
		["rock_moss_set_02", "rock_moss_set_02_rock12", 0.74, 1.44, 1.3],
		["rock_moss_set_02", "rock_moss_set_02_rock13", 1.26, 1.14, 1.0],
	],
	# Лісова дрібнота зі знімків замовника (11.09.2026): великі темні
	# брили з мохом, пні, колоди. Брила — ті самі камені з мохом, тільки
	# втричі більші: 3-5 м, з зіткненням, як на першому знімку.
	"брила": [
		["rock_moss_set_01", "rock_moss_set_01_rock01", 1.47, 2.24, 2.8],
		["rock_moss_set_01", "rock_moss_set_01_rock02", 1.26, 2.66, 3.0],
		["rock_moss_set_01", "rock_moss_set_01_rock04", 1.77, 1.96, 2.6],
		["rock_moss_set_01", "rock_moss_set_01_rock05", 1.21, 1.82, 3.2],
		["rock_moss_set_02", "rock_moss_set_02_rock11", 1.31, 1.53, 3.0],
		["rock_moss_set_02", "rock_moss_set_02_rock13", 1.26, 1.14, 3.0],
	],
	"пень": [
		["tree_stump_01", "tree_stump_01", 0.57, 1.43, 1.0],
	],
	"колода": [
		["dead_tree_trunk", "dead_tree_trunk", 0.29, 0.28, 2.0],
	],
	"камінець": [
		["rock_07", "rock_07", 0.14, 0.17, 2.2],
		["rock_09", "rock_09_LOD0", 0.03, 0.07, 5.0],
		["moon_rock_02", "moon_rock_02_LOD0", 0.20, 0.25, 1.5],
	],
}
## Готові частини сканів за «файл:частина»: меш і як його поставити,
## щоб низ стояв на землі, а середина — на осі.
var _scan_parts: Dictionary = {}


## Дістати частину скану з його сцени — один раз на всю гру.
func _scan_piece(file: String, part: String) -> Array:
	var key := file + ":" + part
	if _scan_parts.has(key):
		return _scan_parts[key]
	var found: Array = []
	var path := "res://models/nature/scan/%s/%s_1k.gltf" % [file, file]
	if ResourceLoader.exists(path):
		var scene: Node = (load(path) as PackedScene).instantiate()
		var node := scene.find_child(part, true, false)
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var mesh_view: MeshInstance3D = node
			var place := Transform3D.IDENTITY
			var up_the: Node = mesh_view
			while up_the != scene and up_the is Node3D:
				place = (up_the as Node3D).transform * place
				up_the = up_the.get_parent()
			var box := place * mesh_view.mesh.get_aabb()
			var foot := Vector3(box.get_center().x, box.position.y,
					box.get_center().z)
			found = [mesh_view.mesh, Transform3D(place.basis,
					place.origin - foot)]
		scene.free()
	if found.is_empty():
		print("[краєвид] ‼ немає «%s» у %s" % [part, path])
	_scan_parts[key] = found
	return found


## Рослина чи камінь зі скану.
##
## Камінь трохи втоплений у землю — на п'яту частину висоти: камінь,
## що стоїть на ґрунті, як на столі, читається бутафорією, а в природі
## він завжди сидить у землі.
func _scan_node(spec: Dictionary) -> Node:
	var names := str(spec["model"]).split(":")
	var kind := str(spec.get("вид", ""))
	var height: float = spec["height"]
	var by: float = float(spec.get("розмір", 1.0))
	var headless := DisplayServer.get_name() == "headless"
	var through := _walk_through(spec)
	if through and headless:
		return null
	var holder: Node3D
	if through:
		holder = Node3D.new()
		holder.name = _named("Кущ" if kind == "кущ" else "Камінь")
	else:
		var body := StaticBody3D.new()
		body.name = _named("Камінь")
		var wall := CollisionShape3D.new()
		wall.name = "Стіна"
		var shape := CylinderShape3D.new()
		var wide: float = float(names[3]) if names.size() > 3 else 1.0
		shape.radius = clampf(wide * by * 0.38, 0.3, 1.8)
		shape.height = height
		wall.shape = shape
		wall.position = Vector3(0, height * 0.5, 0)
		body.add_child(wall)
		holder = body
	holder.position = spec["at"]
	add_child(holder)
	if headless:
		return holder
	var piece := _scan_piece(names[1], names[2])
	if piece.is_empty():
		return holder
	var view := MeshInstance3D.new()
	view.name = "Модель"
	view.mesh = piece[0]
	var inner: Transform3D = piece[1]
	var turn := Transform3D(Basis(Vector3.UP, float(spec["spin"]))
			.scaled(Vector3(by, by, by)), Vector3.ZERO)
	view.transform = turn * inner
	if kind in ["камінь", "камінець", "брила", "колода"]:
		view.position.y -= height * 0.2
	holder.add_child(view)
	_near_only(holder)
	if kind == "кущ":
		_no_shadows(holder)
		_wind_up(holder, height, true)
	elif kind == "камінець":
		_no_shadows(holder)
	return holder


## Фотографічні хвойні: не модель, а два схрещені прямокутники з
## фотографією дерева й прозорим тлом.
##
## Слово замовника 06.09.2026 з трьома знімками туманного хвойного
## лісу: «дерева не відповідають очікуванням, спробуй знайти щось
## схоже». Мультяшні моделі Quaternius такого не дають у принципі —
## це інша стилістика. Кіношні дерева Poly Haven дають, але один меш
## сосни там важить 926 МіБ, а ялиці — 456: вони для кадру, не для гри.
##
## Тож узято те, чим і роблять ліс у справжніх іграх: фотографія дерева
## з альфою на схрещених площинах. **Чотири трикутники на дерево**
## замість сотень — і саме тому це заразом відповідь на «відеокарта не
## справляється». Здалеку й у тумані — а на референсах саме туман —
## відрізнити від меша неможливо.
##
## Джерело: OpenGameArt, CC0 (`models/nature/photo/LICENSE_CC0_trees.txt`).
## Сніжні й літні розведено (слово замовника 06.09.2026: «здається ти
## змішав ялинки під снігом і літні»). Розведено заміром, не на око:
## частка світлих малонасичених пікселів у кроні — Conifer3 7,2%,
## Conifer2 1,7%, решта нуль.
## Шейдер вітру — один на всі рослини. Він і малює, і гойдає.
const WIND := preload("res://scripts/wind.gdshader")

const PHOTO_TREES := {
	# Слово замовника 11.09.2026: «знайди більше дерев, і більших, і
	# таких самих за розміром, але більш різноманітних». Було п'ять фото
	# ялин OpenGameArt на весь ліс; тепер до них — картки, зняті збоку з
	# фотосканів Poly Haven (ялиці, сосни з голим рудим стовбуром,
	# листяне деревце), кожне дерево з трьох боків. Висота — справжня,
	# з моделі; велетні — ті самі найбільші сосни й ялиці, збільшені до
	# 26-31 м (на другому знімку замовника сосни саме такі).
	"хвоя": [["Conifer1", 22.0], ["Conifer4", 17.0], ["Conifer5", 21.0],
			["Conifer6", 18.0], ["Conifer7", 20.0],
			["Scan_fir_tree_01_a_0", 18.8],
			["Scan_fir_tree_01_a_60", 18.8],
			["Scan_fir_tree_01_a_120", 18.8],
			["Scan_fir_tree_01_b_0", 14.0],
			["Scan_fir_tree_01_b_60", 14.0],
			["Scan_fir_tree_01_b_120", 14.0],
			["Scan_fir_tree_01_c_0", 14.4],
			["Scan_fir_tree_01_c_60", 14.4],
			["Scan_fir_tree_01_c_120", 14.4],
			["Scan_pine_tree_01_a_0", 20.3],
			["Scan_pine_tree_01_a_60", 20.3],
			["Scan_pine_tree_01_a_120", 20.3],
			["Scan_pine_tree_01_b_0", 14.8],
			["Scan_pine_tree_01_b_60", 14.8],
			["Scan_pine_tree_01_b_120", 14.8],
			["Scan_pine_tree_01_c_0", 17.4],
			["Scan_pine_tree_01_c_60", 17.4],
			["Scan_pine_tree_01_c_120", 17.4],
			# велетні
			["Scan_pine_tree_01_a_0", 30.0],
			["Scan_pine_tree_01_a_60", 31.0],
			["Scan_pine_tree_01_c_120", 26.0],
			["Scan_fir_tree_01_a_0", 27.0],
			["Scan_fir_tree_01_a_120", 28.0],
			# листяне деревце — рідкий гість у хвойному гаю
			["Scan_tree_small_02_0", 8.5], ["Scan_tree_small_02_60", 8.0],
			["Scan_tree_small_02_120", 9.0]],
	"хвоя в снігу": [["Conifer2", 19.0], ["Conifer3", 15.0]],
	# Підріст — ті самі фотографії, тільки молодими деревцями. На
	# референсах замовника під великими смереками скрізь стоять малі,
	# і саме вони роблять ліс лісом, а не колонадою. Тепер до них —
	# середні ялиці й сосни зі сканів (3-6 м) і саджанці (1,6-2,8 м).
	"підріст": [["Conifer1", 3.4], ["Conifer4", 2.6], ["Conifer5", 3.0],
			["Conifer6", 2.2], ["Conifer7", 2.8],
			["Scan_fir_sapling_medium_a_0", 4.8],
			["Scan_fir_sapling_medium_a_60", 4.8],
			["Scan_fir_sapling_medium_a_120", 4.8],
			["Scan_fir_sapling_medium_b_0", 4.2],
			["Scan_fir_sapling_medium_b_60", 4.2],
			["Scan_fir_sapling_medium_b_120", 4.2],
			["Scan_fir_sapling_medium_c_0", 3.2],
			["Scan_fir_sapling_medium_c_60", 3.2],
			["Scan_fir_sapling_medium_c_120", 3.2],
			["Scan_pine_sapling_medium_a_0", 5.6],
			["Scan_pine_sapling_medium_a_60", 5.6],
			["Scan_pine_sapling_medium_a_120", 5.6],
			["Scan_pine_sapling_medium_b_0", 4.5],
			["Scan_pine_sapling_medium_b_60", 4.5],
			["Scan_pine_sapling_medium_b_120", 4.5],
			["Scan_pine_sapling_medium_c_0", 3.4],
			["Scan_pine_sapling_medium_c_60", 3.4],
			["Scan_pine_sapling_medium_c_120", 3.4],
			["Scan_fir_sapling_a_0", 2.8], ["Scan_fir_sapling_a_60", 2.8],
			["Scan_fir_sapling_b_0", 2.1], ["Scan_fir_sapling_b_60", 2.1],
			["Scan_fir_sapling_c_0", 1.6], ["Scan_fir_sapling_c_60", 1.6],
			["Scan_pine_sapling_small_a_0", 2.8],
			["Scan_pine_sapling_small_a_60", 2.8],
			["Scan_pine_sapling_small_b_0", 2.3],
			["Scan_pine_sapling_small_b_60", 2.3],
			["Scan_pine_sapling_small_c_0", 2.1],
			["Scan_pine_sapling_small_c_60", 2.1]],
	"суха хвоя": [["ConiferDead1", 17.0], ["ConiferDead2", 16.0],
			["ConiferDead3", 15.0], ["ConiferDead5", 18.0],
			["ConiferDead6", 14.0], ["ConiferDead7", 16.0],
			["ConiferDead8", 13.0], ["ConiferDead9", 17.0]],
}
## Готові меші й матеріали за текстурою: усі дерева одного виду ділять
## один меш і один матеріал, інакше сімдесят тисяч дерев — це сімдесят
## тисяч матеріалів.
var _photo_ready: Dictionary = {}


## Хрест із двох площин під текстуру дерева. Висота — одиниця, ширину
## бере з пропорцій самої картинки; масштабує вже той, хто ставить.
func _photo_pair(name_of: String) -> Array:
	if _photo_ready.has(name_of):
		return _photo_ready[name_of]
	var path := "res://models/nature/photo/%s.png" % name_of
	var picture := RawImage.read(path)
	if picture == null:
		# Картки зі сканів — у WebP: 6 МБ замість 25 у PNG.
		path = path.get_basename() + ".webp"
		picture = RawImage.read(path)
	if picture == null:
		print("[краєвид] ‼ немає %s" % path)
		_photo_ready[name_of] = []
		return []
	# Об'ємна крона (06.11.2026): гілки — смуги того самого фото, ярусами
	# довкола стовбура (`_crown_volume`). Вирізаємо ДО mipmap-рівнів.
	var volume := _crown_volume(picture)
	picture.generate_mipmaps()
	var wide: float = float(picture.get_width()) / float(picture.get_height())
	# Вітер (`wind.gdshader`): він і малює картку, і гойдає її. Ножицями,
	# а не прозорістю — прозорість довелось би сортувати, а сімдесят
	# тисяч дерев із сортуванням це те саме гальмо.
	var paint := ShaderMaterial.new()
	paint.shader = WIND
	paint.set_shader_parameter("albedo_tex",
			ImageTexture.create_from_image(picture) if volume.is_empty()
			else volume[1])
	# Велике дерево гойдається менше за травинку — і за розмахом, і за
	# темпом: у крони більше інерції.
	# Малі — лише метрові саджанці; решта сканів — великі дерева, і
	# гойдатись як травинка їм не можна.
	var small: bool = name_of.contains("sapling") \
			and not name_of.contains("medium")
	# 0,030 давало на двадцятиметровій ялині ~0,3 м на кінчику — проба
	# (11.09.2026) ледь відрізнила це від шуму кадру: 2,0% пікселів за
	# 1,5 с. Замовник просив, щоб вітерець колихав і дерева, тож 0,045:
	# ~0,45 м у середньому пориві, до 0,9 м у сильному.
	paint.set_shader_parameter("sway", 0.045 if not small else 0.075)
	paint.set_shader_parameter("speed", 1.0 if not small else 1.5)
	var mesh: ArrayMesh = _crown_mesh(wide) if volume.is_empty() \
			else volume[0]
	_photo_ready[name_of] = [mesh, paint, _bark_paint(paint)]
	return _photo_ready[name_of]


## Кора стовбура — той самий вітер, що й у крони (інакше верх стовбура
## відставав би від гілок), тільки непрозора й без світла крізь хвою.
var _barks: Dictionary = {}


func _bark_paint(crown: ShaderMaterial) -> ShaderMaterial:
	var key := "%.3f|%.3f" % [float(crown.get_shader_parameter("sway")),
			float(crown.get_shader_parameter("speed"))]
	if _barks.has(key):
		return _barks[key]
	var bark := ShaderMaterial.new()
	bark.shader = WIND
	# Фото кори яскраве, а стовбур у тіні власної крони — удвічі темніший.
	bark.set_shader_parameter("albedo_tex", _raw_texture(BARK % "Color", 0.5))
	var bumps := _raw_texture(BARK % "Normal")
	if bumps != null:
		bark.set_shader_parameter("normal_tex", bumps)
		bark.set_shader_parameter("use_normal", true)
	bark.set_shader_parameter("sway", crown.get_shader_parameter("sway"))
	bark.set_shader_parameter("speed", crown.get_shader_parameter("speed"))
	bark.set_shader_parameter("scissor", 0.0)
	bark.set_shader_parameter("through", Color(0, 0, 0))
	_barks[key] = bark
	return bark


## Кора сосни — ambientCG Bark014 (CC0), рудувато-бура, як стовбури на
## другому знімку замовника.
const BARK := "res://models/nature/bark/Bark014_%s.jpg"


static func _raw_texture(path: String, bright := 1.0) -> ImageTexture:
	var picture := RawImage.read(path)
	if picture == null:
		print("[краєвид] ‼ немає %s" % path)
		return null
	if bright != 1.0:
		picture.adjust_bcs(bright, 1.0, 1.0)
	picture.generate_mipmaps()
	return ImageTexture.create_from_image(picture)


## Об'ємна крона з фото (слово замовника 06.11.2026: «маєм деякі дерева
## зроблені з двох зображень хрестом, необхідно переробити їх в об'ємну
## модель з круглою-циліндричною формою»).
##
## З прозорості фото міряється силует: на якій висоті крона і яка вона
## там широка. Ліва й права половини фото на `CROWN_BANDS` висотах
## вирізаються в атлас — це гілки з справжньою хвоєю, стовбуром до
## лівого краю. Крона — яруси гілок колом довкола осі: радіус ярусу —
## пів ширини силуету на тій висоті, гілка — дві картки навхрест уздовж
## себе, з легким провисанням. З будь-якого боку й згори — круглий
## конус тієї самої ялиці чи сосни, а не хрест чи зірка. Висота — 0…1,
## як і в старої крони: масштаб, вітер і стовбур ті самі.
##
## Повертає [сітка, текстура-атлас] або [], якщо силует не прочитався
## (тоді — стара зірка).
const CROWN_BANDS := 10
const CROWN_WHORLS := 20
const CROWN_BRANCHES := 6


static func _crown_volume(picture: Image) -> Array:
	if picture.get_format() != Image.FORMAT_RGBA8:
		picture.convert(Image.FORMAT_RGBA8)
	var w := picture.get_width()
	var h := picture.get_height()
	var small := picture.duplicate() as Image
	var sw := 96
	var sh := 256
	small.resize(sw, sh, Image.INTERPOLATE_BILINEAR)
	# Ліва й права межа силуету в кожному рядку (частки ширини).
	var left := PackedFloat32Array()
	var right := PackedFloat32Array()
	left.resize(sh)
	right.resize(sh)
	var centres: Array[float] = []
	for j in sh:
		var l := -1
		var r := -1
		for i in sw:
			if small.get_pixel(i, j).a > 0.1:
				if l < 0:
					l = i
				r = i
		left[j] = -1.0 if l < 0 else float(l) / sw
		right[j] = -1.0 if r < 0 else float(r + 1) / sw
		if l >= 0 and r - l > sw * 0.12:
			centres.append((left[j] + right[j]) * 0.5)
	if centres.size() < 8:
		return []
	centres.sort()
	var cx: float = centres[centres.size() / 2]
	# Крона — рядки, ширші за стовбур. y — частка висоти від низу.
	var lo := 1.0
	var hi := 0.0
	var half := PackedFloat32Array()
	half.resize(sh)
	for j in sh:
		var y := 1.0 - (j + 0.5) / sh
		if left[j] < 0.0:
			half[j] = 0.0
			continue
		# Радіус у частках ВИСОТИ: ширина в частках ширини × w/h.
		half[j] = maxf(cx - left[j], right[j] - cx) * float(w) / float(h)
		if right[j] - left[j] > 0.12:
			lo = minf(lo, y)
			hi = maxf(hi, y)
	if hi - lo < 0.1:
		return []
	# Яруси гілок — там, де на фото гілки, а не рівними смугами: рядки з
	# найбільшою кількістю непрозорих пікселів (у сосни 5–8 рідких ярусів,
	# у ялини — багато густих). Рівні смуги брали по кілька ярусів разом
	# із проміжками, і сосна зблизька ставала темною грудкою (06.11.2026).
	var dens := PackedFloat32Array()
	dens.resize(sh)
	for j in sh:
		var c := 0
		for i in sw:
			if small.get_pixel(i, j).a > 0.1:
				c += 1
		dens[j] = c
	var soft := PackedFloat32Array()
	soft.resize(sh)
	var peak := 0.0
	for j in sh:
		var sum := 0.0
		var cnt := 0
		for d in range(-2, 3):
			if j + d >= 0 and j + d < sh:
				sum += dens[j + d]
				cnt += 1
		soft[j] = sum / cnt
		var y := 1.0 - (j + 0.5) / sh
		if y >= lo and y <= hi:
			peak = maxf(peak, soft[j])
	var layers: Array[float] = []   # y ярусів (частки висоти)
	for j in range(3, sh - 3):
		var y := 1.0 - (j + 0.5) / sh
		if y < lo or y > hi or soft[j] < peak * 0.25:
			continue
		var top := true
		for d in range(-4, 5):
			if j + d >= 0 and j + d < sh and soft[j + d] > soft[j]:
				top = false
		if top and (layers.is_empty() or absf(layers[-1] - y) > 0.022):
			layers.append(y)
	if layers.size() < 5:
		layers.clear()
		for k in CROWN_WHORLS:
			layers.append(lo + (k + 0.5) * (hi - lo) / CROWN_WHORLS)
	# Між рідкими ярусами — ще по одному тоншому, щоб не світились діри.
	layers.sort()
	var filled: Array[float] = []
	for k in layers.size():
		filled.append(layers[k])
		if k + 1 < layers.size() and layers[k + 1] - layers[k] > 0.07:
			filled.append((layers[k] + layers[k + 1]) * 0.5)
	layers = filled
	var count := layers.size()
	var band := clampi(int(h * 0.045), 12, 96)
	var cw := maxi(16, int(w * 0.5))
	var atlas := Image.create(cw, band * count * 2, false, Image.FORMAT_RGBA8)
	var trunk_px := int(cx * w)
	for k in count:
		var top := clampi(int((1.0 - layers[k]) * h) - band / 2, 0, h - band)
		var from_left := picture.get_region(Rect2i(maxi(0, trunk_px - cw), top,
				mini(cw, trunk_px), band))
		from_left.flip_x()
		atlas.blit_rect(from_left, Rect2i(Vector2i.ZERO, from_left.get_size()),
				Vector2i(0, (k * 2) * band))
		var from_right := picture.get_region(Rect2i(trunk_px, top,
				mini(cw, w - trunk_px), band))
		atlas.blit_rect(from_right, Rect2i(Vector2i.ZERO,
				from_right.get_size()), Vector2i(0, (k * 2 + 1) * band))
	atlas.generate_mipmaps()
	var thick := float(band) / float(h)
	var rows := count * 2

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centre := Vector3(0, (lo + hi) * 0.5, 0)
	for n in count:
		var y: float = layers[n]
		var j := clampi(int((1.0 - y) * sh), 0, sh - 1)
		var reach := maxf(half[j], thick * 0.6)
		for b in CROWN_BRANCHES:
			var turn := n * 2.39996 + b * TAU / CROWN_BRANCHES \
					+ sin(n * 7.1 + b * 3.3) * 0.25
			var dir := Vector3(cos(turn), 0, sin(turn))
			var root := Vector3(0, y, 0) + dir * 0.004
			var tip := Vector3(0, y, 0) + dir * reach \
					+ Vector3.DOWN * reach * 0.22
			var axis := (tip - root).normalized()
			var flat := axis.cross(Vector3.UP).normalized()
			var up := flat.cross(axis).normalized()
			var row := n * 2 + (b % 2)
			var v0 := float(row) / rows
			var v1 := float(row + 1) / rows
			# Обидві картки — ±29° від вертикалі: горизонтальна збоку під
			# гострим кутом розмазувала фото «дошками» (знімок 06.11.2026).
			for across: Vector3 in [(up + flat * 0.55).normalized(),
					(up - flat * 0.55).normalized()]:
				var s0 := across * thick * 0.5
				var quad := [root + s0, tip + s0, tip - s0, root - s0]
				var uv := [Vector2(0, v0), Vector2(1, v0), Vector2(1, v1),
						Vector2(0, v1)]
				for i: int in [0, 1, 2, 0, 2, 3]:
					var p: Vector3 = quad[i]
					var bent := (p - centre).normalized()
					st.set_normal((bent * 0.75 + Vector3.UP * 0.45).normalized())
					st.set_uv(uv[i])
					st.add_vertex(p)
	var mesh := st.commit()
	_trunk_into(mesh)
	return [mesh, ImageTexture.create_from_image(atlas)]


## Стовбур із корою — другою поверхнею сітки крони.
static func _trunk_into(mesh: ArrayMesh) -> void:
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 7
	for s in sides:
		var a0 := TAU * s / sides
		var a1 := TAU * (s + 1) / sides
		var ring := [[a0, 0.0, 0.012, float(s)], [a1, 0.0, 0.012, s + 1.0],
				[a1, 0.6, 0.003, s + 1.0], [a0, 0.6, 0.003, float(s)]]
		for i: int in [0, 1, 2, 0, 2, 3]:
			var one: Array = ring[i]
			var a: float = one[0]
			bark.set_normal(Vector3(cos(a), 0.15, sin(a)).normalized())
			bark.set_uv(Vector2(float(one[3]) / sides, float(one[1]) * 12.0))
			bark.add_vertex(Vector3(cos(a) * float(one[2]), one[1],
					sin(a) * float(one[2])))
	bark.generate_tangents()
	bark.commit(mesh)


## Крона з ШЕСТИ напівплощин навколо осі й стовбур із корою.
##
## Було (06.09.2026): хрест із двох площин. Збоку — дерево, але згори,
## під 50° камери гравця, — плаский хрест, а стовбура майже не видно.
## Знімки замовника (11.09.2026) — об'ємні смереки й сосни з голими
## рудими стовбурами. Тож тепер шість напівплощин по 60°, на кожній
## половина фото від осі назовні (парні — права половина, непарні —
## ліва): з будь-якого боку видно кілька силуетів одразу, а згори
## замість хреста — зірка. Під ними — справжній стовбур із корою до 0,8
## висоти. 26 трикутників на дерево замість чотирьох: на світі з
## двадцятьма тисячами дерев це все одно менше, ніж одна купка трави.
##
## Нормалі СФЕРИЧНІ, як і були: нормаль строго вгору робила крону
## пласкою дошкою (слово замовника 06.09.2026 про освітлення).
static func _crown_mesh(wide: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var middle := Vector3(0, 0.55, 0)
	for k in 6:
		var turn := k * PI / 3.0 + 0.3
		var out := Vector3(cos(turn), 0, sin(turn)) * wide * 0.5
		var edge_u: float = 1.0 if k % 2 == 0 else 0.0
		var made: Array[Vector3] = [Vector3.ZERO, out, out + Vector3.UP,
				Vector3.UP]
		var uvs := [Vector2(0.5, 1), Vector2(edge_u, 1), Vector2(edge_u, 0),
				Vector2(0.5, 0)]
		for i: int in [0, 1, 2, 0, 2, 3]:
			var bent := (made[i] - middle + out * 0.3).normalized()
			st.set_normal((bent * 0.75 + Vector3.UP * 0.45).normalized())
			st.set_uv(uvs[i])
			st.add_vertex(made[i])
	var mesh := st.commit()
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 7
	for s in sides:
		var a0 := TAU * s / sides
		var a1 := TAU * (s + 1) / sides
		# До 0,6 висоти, не 0,8: угорі фото смереки рідке, і стовбур
		# стирчав над кроною світлою жердиною (знімок 11.09.2026).
		var ring := [[a0, 0.0, 0.012, float(s)], [a1, 0.0, 0.012, s + 1.0],
				[a1, 0.6, 0.003, s + 1.0], [a0, 0.6, 0.003, float(s)]]
		for i: int in [0, 1, 2, 0, 2, 3]:
			var one: Array = ring[i]
			var a: float = one[0]
			bark.set_normal(Vector3(cos(a), 0.15, sin(a)).normalized())
			bark.set_uv(Vector2(float(one[3]) / sides, float(one[1]) * 12.0))
			bark.add_vertex(Vector3(cos(a) * float(one[2]), one[1],
					sin(a) * float(one[2])))
	bark.generate_tangents()
	bark.commit(mesh)
	return mesh


## Одна рослина. Розмір — множник до власної висоти моделі, не «підтягти
## до N метрів»: у наборі дерево вже сім-девʼять метрів, і природний
## розкид дає саме легка різниця в розмірі, а не однакова висота.
func _place_plant(at: Vector3, kind: String, size: float) -> void:
	# Трава й квіти світу 2 — це різнотрав'я (`meadow.gd`), а не
	# поодинокі моделі на сітці 12 м.
	if _grid > 0 and (kind == "трава" or kind == "квіти"):
		return
	if _grid > 0 and SCANS.has(kind):
		var scans: Array = SCANS[kind]
		var one: Array = scans[randi() % scans.size()]
		var by: float = float(one[4]) * size
		_place_tree(at, float(one[2]) * by, "", "",
				"скан:%s:%s:%.2f" % [one[0], one[1], float(one[3])],
				randf() * TAU, kind, by)
		return
	# «листяне» / «підлісок» у правилах світу 2 — будь-який сорт Tree3D
	# свого роду. Сорт — з місця (хеш), не з `randi()`: так розкид решти
	# світу не зсувається, а сервер і клієнт однаково знають, що де росте.
	if kind == "листяне" or kind == "підлісок":
		var sorts: Array = Tree3DLook.LEAFY if kind == "листяне" \
				else Tree3DLook.BUSHES
		kind = sorts[absi(hash(Vector2i(roundi(at.x * 10.0),
				roundi(at.z * 10.0)))) % sorts.size()]
	# Листяні Tree3D (план §3в). Випадковість — та сама, що в гілки фото
	# нижче: одне `randi()` на вигляд і одне `randf()` на поворот.
	if Tree3DLook.KINDS.has(kind):
		var sort: Dictionary = Tree3DLook.KINDS[kind]
		_place_tree(at, float(sort["висота"]) * size, "", "",
				"t3d:%s:%d" % [kind, randi() % Tree3DLook.SEEDS],
				randf() * TAU, kind, size)
		return
	if PHOTO_TREES.has(kind):
		var photo: Array = PHOTO_TREES[kind]
		var one: Array = photo[randi() % photo.size()]
		_place_tree(at, float(one[1]) * size, "", "", "фото:" + str(one[0]),
				randf() * TAU, kind, size)
		return
	var list: Array = PLANTS.get(kind, PLANTS["дерево"])
	var pick: Array = list[randi() % list.size()]
	var model: String = "res://models/nature/%s.gltf" % pick[0]
	var tall: float = float(pick[1]) * size
	_place_tree(at, tall, "#5b4632", "#2f5e33", model, randf() * TAU, kind,
			size)


## Річки: стрічка води вздовж кожного русла.
##
## Саме русло вже врізане в рельєф (`tools/svit2.py` опускає землю
## вздовж тих самих клітин, якими річка намальована на аркуші), тож
## тут лишається постелити воду. Стрічка — дві вершини на кожну точку
## русла, ширина росте до гирла, як і на карті.
func _rivers() -> void:
	var streams: Array = data.get("русла", [])
	if streams.is_empty():
		return
	var water := _paint(str(data.get("море", {}).get("колір", "#25506b")))
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.albedo_color.a = 0.78
	water.metallic = 0.25
	water.roughness = 0.12
	water.cull_mode = BaseMaterial3D.CULL_DISABLED
	var made := 0
	for stream: Dictionary in streams:
		var points: Array = stream.get("точки", [])
		if points.size() < 2:
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for here: Array in _river_line(points):
			var at := Vector3(float(here[0]), float(here[2]), float(here[1]))
			var across := Vector3(float(here[4]), 0.0, float(here[5])) \
					.cross(Vector3.UP)
			var reach := wet_reach(here)
			# Нормаль ставимо самі: `generate_normals()` уміє лише
			# окремі трикутники, а стрічка — це смуга.
			# Край — там, де берег виходить з води (+0,6 м у берег): вода
			# рівна впоперек і сходиться з землею. До 07.11.2026 край
			# стояв на ширині з даних, а врізане дно ширше (×2,2) — край
			# висів на 1,4 м над дном. Берега не знайшли (косогір) — край
			# на ширині з даних, не вище за свою землю.
			for k in 2:
				var side := -1.0 if k == 0 else 1.0
				var edge := at + across * side * float(reach[k])
				if reach[k + 2]:
					edge = at + across * side * (float(reach[k]) + 0.6)
				else:
					edge.y = minf(at.y, surface_y(edge.x, edge.z) + 0.05)
				st.set_normal(Vector3.UP)
				st.add_vertex(edge)
		var mesh := st.commit()
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var view := MeshInstance3D.new()
		view.name = _named("Річка")
		view.mesh = mesh
		view.set_surface_override_material(0, water)
		add_child(view)
		made += 1
	print("[краєвид] річок постелено: %d" % made)


## Річка кроком ≤4 м, вода — на землі + `RIVER_ABOVE`, але не вище за
## рівень із даних. Заміряно 06.11.2026: вузли русла стоять через ~32 м, а
## врізаного русла під стрічкою немає (берег над «дном» — медіана 7 см), тож
## пряма стрічка між вузлами висіла над схилом: у 94% точок вода була вища
## за нижчий берег, у горах — до 43 м. Точка: [x, z, y, ширина, dx, dz].
const RIVER_ABOVE := 1.4
const RIVER_STEP := 4.0


func _river_line(points: Array) -> Array:
	var out: Array = []
	for k in range(points.size() - 1):
		var a: Array = points[k]
		var b: Array = points[k + 1]
		var flat := Vector2(float(b[0]) - float(a[0]),
				float(b[1]) - float(a[1]))
		var long := flat.length()
		if long < 0.01:
			continue
		var dir := flat / long
		var steps := maxi(1, int(ceil(long / RIVER_STEP)))
		var last := 1 if k == points.size() - 2 else 0
		for i in steps + last:
			var t := float(i) / steps
			var x := lerpf(float(a[0]), float(b[0]), t)
			var z := lerpf(float(a[1]), float(b[1]), t)
			out.append([x, z, river_y(x, z, lerpf(float(a[2]), float(b[2]), t)),
					lerpf(float(a[3]), float(b[3]), t), dir.x, dir.y])
	return out


## Де вода сходиться з берегом по обидва боки точки `_river_line`:
## [ліво, право, ліво знайдено, право знайдено] — метри від осі.
## Берег — перше місце (кроком 0,5 м), де земля вища за воду на 0,2 м;
## шукаємо не далі врізаної смуги (`РІЧКА_БЕРЕГ` = 2,2 ширини в
## `tools/svit2.py`) + 4 м. Не знайшли — ширина з даних.
const WET_ABOVE := 0.2
const WET_BAND := 2.2


func wet_reach(here: Array) -> Array:
	var at := Vector2(float(here[0]), float(here[1]))
	var water := maxf(float(here[2]), sea_level())
	var width := float(here[3])
	var across := Vector2(-float(here[5]), float(here[4]))
	var out := [width * 0.5, width * 0.5, false, false]
	var most := width * WET_BAND + 4.0
	for k in 2:
		var dir := across * (-1.0 if k == 0 else 1.0)
		var d := 0.0
		while d <= most:
			var p := at + dir * d
			if surface_y(p.x, p.y) >= water + WET_ABOVE:
				out[k] = maxf(d, 0.5)
				out[k + 2] = true
				break
			d += 0.5
	return out


## Висота води в точці: земля + `RIVER_ABOVE`, не вище за рівень даних.
## Те саме бере міст (`BridgeLook`), щоб настил лягав над водою.
func river_y(x: float, z: float, level: float) -> float:
	return minf(level, surface_y(x, z) + RIVER_ABOVE)


## Відрізки річок у клітинах по `RIVER_CELL` м — щоб на десятки тисяч
## рослин не перебирати всі 1500 відрізків.
const RIVER_CELL := 32.0
const RIVER_DRY := 2.0      ## від краю води до стовбура щонайменше, м
var _river_cells: Dictionary = {}
var _river_cells_ready := false


func _river_index() -> void:
	_river_cells_ready = true
	_river_cells.clear()
	# Відрізки кроком 4 м, півширина — до берега (`wet_reach`), не з
	# даних: врізане дно ширше, і дерева інакше ставали в воду.
	for stream: Dictionary in data.get("русла", []):
		var line := _river_line(stream.get("точки", []))
		var halves: Array = []
		for here: Array in line:
			var wet := wet_reach(here)
			halves.append(maxf(float(wet[0]), float(wet[1])))
		for k in range(line.size() - 1):
			var a := Vector2(float(line[k][0]), float(line[k][1]))
			var b := Vector2(float(line[k + 1][0]), float(line[k + 1][1]))
			var reach := maxf(halves[k], halves[k + 1]) + RIVER_DRY
			var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * reach
			var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * reach
			for cx in range(floori(lo.x / RIVER_CELL), floori(hi.x / RIVER_CELL) + 1):
				for cz in range(floori(lo.y / RIVER_CELL),
						floori(hi.y / RIVER_CELL) + 1):
					_river_cells.get_or_add(Vector2i(cx, cz), []).append(
							[a, b, halves[k], halves[k + 1]])


## Чи точка у воді річки (з запасом `extra` за край). Різнотрав'я
## (`meadow.gd`) бере звідси, щоб травинки не стирчали з води.
func in_river(x: float, z: float, extra: float = 0.0) -> bool:
	if not _river_cells_ready:
		_river_index()
	var p := Vector2(x, z)
	for seg: Array in _river_cells.get(Vector2i(floori(x / RIVER_CELL),
			floori(z / RIVER_CELL)), []):
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var close := Geometry2D.get_closest_point_to_segment(p, a, b)
		var t := close.distance_to(a) / maxf(0.01, a.distance_to(b))
		if close.distance_to(p) < lerpf(seg[2], seg[3], t) + extra:
			return true
	return false


## Точка поза водою: якщо вона в річці чи ближче `RIVER_DRY` до краю —
## зсув перпендикулярно від русла на берег, висота — земля там.
func _off_river(at: Vector3) -> Vector3:
	if not _river_cells_ready:
		_river_index()
	if _river_cells.is_empty():
		return at
	var p := Vector2(at.x, at.z)
	var cell := Vector2i(floori(p.x / RIVER_CELL), floori(p.y / RIVER_CELL))
	for pass_no in 6:
		var moved := false
		for seg: Array in _river_cells.get(cell, []):
			var a: Vector2 = seg[0]
			var b: Vector2 = seg[1]
			var close := Geometry2D.get_closest_point_to_segment(p, a, b)
			var t := close.distance_to(a) / maxf(0.01, a.distance_to(b))
			var need := lerpf(seg[2], seg[3], t) + RIVER_DRY
			var off := p - close
			if off.length() >= need:
				continue
			var away := off.normalized() if off.length() > 0.01 \
					else (b - a).normalized().orthogonal()
			p = close + away * (need + 0.2)
			moved = true
		if not moved:
			break
		cell = Vector2i(floori(p.x / RIVER_CELL), floori(p.y / RIVER_CELL))
	if p.x == at.x and p.y == at.z:
		return at
	# Біля злиття відсунуте від одного русла потрапляє в інше (07.11.2026:
	# 8 дерев у воді в одній купці) — таке не садимо зовсім.
	if in_river(p.x, p.y, RIVER_DRY * 0.5):
		return Vector3(p.x, INF, p.y)
	return Vector3(p.x, height_at(p.x, p.y), p.y)


func _forest() -> void:
	var many: Array = data.get("ліси", [])
	if many.is_empty():
		var one: Dictionary = data.get("ліс", {})
		if not one.is_empty():
			many = [one]
	for wood: Dictionary in many:
		_one_forest(wood)


func _one_forest(wood: Dictionary) -> void:
	if wood.is_empty():
		return
	var center := _point(wood.get("центр", [0, 0, 0]))
	var radius := float(wood.get("радіус", 20))
	var heights: Array = wood.get("висота", [4.0, 8.0])
	var bark := str(wood.get("стовбур", "#5b4632"))
	var leaves := str(wood.get("крона", "#2f5e33"))
	for i in int(wood.get("дерев", 40)):
		var angle := randf() * TAU
		var far := radius * sqrt(randf())
		var at := _on_ground(center + Vector3(cos(angle) * far, 0.0,
				sin(angle) * far))
		var height := randf_range(float(heights[0]), float(heights[1]))
		# Модель і поворот — тут-таки, а не всередині `_tree()`: та може
		# покликатись пізніше за підвантаженням, і якби `randi()`/`randf()`
		# для моделі чекали на цей момент, розкид розійшовся б на
		# сервері й клієнті (перевірено пробою — розходився, звідси й
		# коментар не просто про акуратність).
		var model: String = TREE_MODELS[randi() % TREE_MODELS.size()]
		var spin := randf() * TAU
		# «сорти» — дерева Tree3D замість моделей (план §3в). Те саме
		# одне `randi()` вище вибирає й сорт, і зерно — розкид не зсувається.
		var sorts: Array = wood.get("сорти", [])
		if not sorts.is_empty():
			var pick := absi(hash(model + str(i)))
			var sort: String = sorts[pick % sorts.size()]
			model = "t3d:%s:%d" % [sort, pick / sorts.size() % Tree3DLook.SEEDS]
			# Висота лісу — для дерева 8 м; сорт тягне її до своєї: тополя
			# вища, чагарник утричі нижчий.
			height *= float(Tree3DLook.KINDS[sort]["висота"]) / 8.0
		_place_tree(at, height, bark, leaves, model, spin)
	# Підлісок (17.10.2026, «додай … чагарник»): кущі Tree3D між деревами,
	# крізь них ходять. Випадковість — після дерев, тим самим потоком на
	# сервері й у клієнта; сервер їх не будує зовсім (`_tree`).
	var under: Dictionary = wood.get("підлісок", {})
	var bushes: Array = under.get("сорти", [])
	for _i in int(under.get("кущів", 0)) if not bushes.is_empty() else 0:
		var angle := randf() * TAU
		var far := radius * 1.1 * sqrt(randf())
		var at := _on_ground(center + Vector3(cos(angle) * far, 0.0,
				sin(angle) * far))
		var pick := randi()
		var sort: String = bushes[pick % bushes.size()]
		var tall := float(Tree3DLook.KINDS[sort]["висота"]) \
				* randf_range(0.7, 1.2)
		_place_tree(at, tall, bark, leaves, "t3d:%s:%d" % [sort,
				pick / bushes.size() % Tree3DLook.SEEDS], randf() * TAU,
				"кущ")


## Одразу будує дерево, якщо секторами не підвантажуємо (сервер, або
## проби, що ганяють `build()` напряму), або кладе специфікацію на
## пізніше, якщо сектор ще не потрібен клієнтові. Жодної випадковості
## тут і нижче — вся вже витрачена вище, в одному незалежному від
## підвантаження проході.
func _place_tree(at: Vector3, height: float, bark: String, leaves: String,
		model: String, spin: float, kind: String = "дерево",
		size: float = 0.0) -> void:
	# У воді не росте: переносимо на берег (слово замовника 06.11.2026:
	# «перевір, чи немає в нас дерев у воді … перенеси дерева на суходол»).
	# Тут, а не в `_greenery`: випадковість уже витрачена, тож вигляд
	# решти лісу не зсувається. Камінь у руслі лишається — природно.
	if kind != "камінь":
		at = _off_river(at)
		if is_inf(at.y):
			return
	# Під стовбуром дерева-велета нічого не росте (і крізь його стіни теж).
	if GiantTree.blocks(at.x, at.z):
		return
	var key := _patch_at(at.x, at.z)
	var spec := {"at": at, "height": height, "bark": bark, "leaves": leaves,
			"model": model, "spin": spin, "вид": kind, "розмір": size}
	_tree_specs.get_or_add(key, []).append(spec)
	if not _streaming or _loaded_sectors.get(key, false):
		var made: Node = _tree(spec)
		if made != null:
			_tree_nodes.get_or_add(key, []).append(made)


## Справжні моделі (Quaternius Stylized Nature MegaKit, CC0,
## `models/nature/`) — розширення світу 03.09.2026. Якщо паку немає на
## диску, дерево лишається примітивом, як і раніше (той самий принцип,
## що й для будинків: гра має йти на чистій машині).
const TREE_MODELS := [
	"res://models/nature/CommonTree_1.gltf",
	"res://models/nature/CommonTree_2.gltf",
	"res://models/nature/CommonTree_3.gltf",
	"res://models/nature/Pine_1.gltf",
	"res://models/nature/Pine_2.gltf",
	"res://models/nature/Pine_3.gltf",
]
## Ті самі моделі, але розділені за видом: у версії 2 зона сама каже,
## що в ній росте — на крижаній півночі хвоя, на рівнині листяні.
const LEAFY_MODELS := [
	"res://models/nature/CommonTree_1.gltf",
	"res://models/nature/CommonTree_2.gltf",
	"res://models/nature/CommonTree_3.gltf",
]
const PINE_MODELS := [
	"res://models/nature/Pine_1.gltf",
	"res://models/nature/Pine_2.gltf",
	"res://models/nature/Pine_3.gltf",
]
## Висота моделі дерева в наборі, заміряно (7,3…9,4 м) — беремо середню
## як опору для масштабу; свій розкид висот (`map.json`) лишається
## множником поверх неї.
const TREE_MODEL_HEIGHT := 8.0


## Повертає корінь дерева (`StaticBody3D`) — підвантаження ділянками
## (П-63) має що вивантажувати назад, коли гравець піде геть.
##
## Без жодної випадковості: модель і поворот уже вибрані в `_forest()`,
## сюди приходять готовим `spec`, щоб виклик можна було відкласти, не
## зачепивши спільний потік `randf()`.
## Види, крізь які ходять: кущ і камінь під коліно — прикраса, а не
## перепона. На світі версії 2 їх десятки тисяч, і кожен зайвий
## `StaticBody3D` коштує серверові памʼяті ні за що; до того ж ліс,
## у якому спотикаєшся об кожен кущ, не ліс, а смуга перешкод.
func _walk_through(spec: Dictionary) -> bool:
	var kind := str(spec.get("вид", ""))
	if kind in ["кущ", "трава", "квіти", "камінець", "підріст", "пень",
			"колода"] or kind in Tree3DLook.BUSHES:
		return true
	return kind == "камінь" and float(spec.get("height", 9.0)) < 1.6


func _tree(spec: Dictionary) -> Node:
	var where: Vector3 = spec["at"]
	var height: float = spec["height"]
	var bark: String = spec["bark"]
	var leaves: String = spec["leaves"]
	if str(spec["model"]).begins_with("скан:"):
		return _scan_node(spec)
	if _walk_through(spec):
		# Серверові його нема навіщо взагалі: нема зіткнення — нема й вузла.
		if DisplayServer.get_name() == "headless":
			return null
		var only_view := Node3D.new()
		only_view.name = _named("Кущ")
		only_view.position = where
		add_child(only_view)
		var path: String = spec["model"]
		if path.begins_with("t3d:"):
			var parts := path.split(":")
			var bush := Tree3DLook.view(parts[1], int(parts[2]), height)
			if bush != null:
				bush.rotation.y = spec["spin"]
				only_view.add_child(bush)
				_no_shadows(bush)
				_near_only(bush)
				_wind_up(bush, height, true)
		elif ResourceLoader.exists(path):
			var made: Node3D = (load(path) as PackedScene).instantiate()
			var by: float = float(spec.get("розмір", 0.0))
			if by <= 0.0:
				by = height / TREE_MODEL_HEIGHT
			made.scale = Vector3(by, by, by)
			made.rotation.y = spec["spin"]
			only_view.add_child(made)
			_no_shadows(made)
			_near_only(made)
			_wind_up(made, height)
		return only_view
	var body := StaticBody3D.new()
	body.name = _named("Дерево")
	body.position = where
	add_child(body)
	# Зіткнення — тонкий стовбур незалежно від того, є модель чи ні:
	# крона лишається прохідною, як і завжди.
	var wall := CollisionShape3D.new()
	wall.name = "Стіна"
	var shape := CylinderShape3D.new()
	shape.radius = 0.32
	shape.height = height
	wall.shape = shape
	wall.position = Vector3(0, height * 0.5, 0)
	body.add_child(wall)

	# Дерево Tree3D: сітки вирощено раз на сорт і зерно (`tree3d_look.gd`),
	# тут лише ставимо їх. Серверові вигляд не потрібен — лише стовбур.
	if str(spec["model"]).begins_with("t3d:"):
		if DisplayServer.get_name() != "headless":
			var parts := str(spec["model"]).split(":")
			var grown := Tree3DLook.view(parts[1], int(parts[2]), height)
			if grown != null:
				grown.rotation.y = spec["spin"]
				body.add_child(grown)
				_no_shadows(grown)
				_near_only(grown)
				_wind_up(grown, height, true)
		return body

	# Фотографічне дерево: хрест із двох площин замість моделі.
	if str(spec["model"]).begins_with("фото:"):
		if DisplayServer.get_name() != "headless":
			var pair := _photo_pair(str(spec["model"]).trim_prefix("фото:"))
			if not pair.is_empty():
				var flat := MeshInstance3D.new()
				flat.name = "Крона"
				flat.mesh = pair[0]
				flat.set_surface_override_material(0, pair[1])
				flat.set_surface_override_material(1, pair[2])
				flat.scale = Vector3(height, height, height)
				flat.rotation.y = spec["spin"]
				flat.cast_shadow = \
						GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				body.add_child(flat)
				_near_only(flat)
		return body

	# Серверу картинка не потрібна — тільки те, об що спотикаються.
	# На світі версії 2 рослин тисячі, і завантаження моделі для
	# кожної коштувало б серверові пам'яті ні за що.
	if DisplayServer.get_name() == "headless":
		return body

	var model_path: String = spec["model"]
	if ResourceLoader.exists(model_path):
		var view: Node3D = (load(model_path) as PackedScene).instantiate()
		view.name = "Модель"
		# «розмір» — множник до власної висоти моделі; нуль означає
		# старий шлях (підтягти під задану висоту), яким досі живе ліс
		# світу версії 1.
		var by: float = float(spec.get("розмір", 0.0))
		if by <= 0.0:
			by = height / TREE_MODEL_HEIGHT
		view.scale = Vector3(by, by, by)
		view.rotation.y = spec["spin"]
		body.add_child(view)
		_no_shadows(view)
		_near_only(view)
		# Дерево-модель теж гойдається, тільки ледь: у стовбура інерція.
		if str(spec.get("вид", "")) != "камінь":
			_wind_up(view, height)
		return body

	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.22
	trunk.bottom_radius = 0.32
	trunk.height = height
	var trunk_view := MeshInstance3D.new()
	trunk_view.name = "Меш"
	trunk_view.mesh = trunk
	var dead: bool = str(spec.get("вид", "")) == "сухе дерево"
	trunk_view.set_surface_override_material(0,
			_paint("#6b625a" if dead else bark))
	trunk_view.position = Vector3(0, height * 0.5, 0)
	body.add_child(trunk_view)

	# Сухе дерево — стовбур із трьома голими гілками, без крони: у
	# наборі природи мертвих дерев немає, а вулканічна смуга й мертвий
	# схід на аркуші саме ними й помережані.
	if dead:
		for i in 3:
			var limb := MeshInstance3D.new()
			var stick := CylinderMesh.new()
			stick.top_radius = 0.06
			stick.bottom_radius = 0.12
			stick.height = height * 0.42
			limb.mesh = stick
			limb.set_surface_override_material(0, _paint("#6b625a"))
			var turn := TAU * float(i) / 3.0 + 0.4
			limb.position = Vector3(cos(turn) * height * 0.12,
					height * 0.72, sin(turn) * height * 0.12)
			limb.rotation = Vector3(0.7 * cos(turn), -turn, 0.7 * sin(turn))
			body.add_child(limb)
		return body

	var crown := CylinderMesh.new()
	crown.top_radius = 0.0
	crown.bottom_radius = height * 0.42
	crown.height = height * 0.9
	var green := MeshInstance3D.new()
	green.name = "Крона"
	green.mesh = crown
	green.set_surface_override_material(0, _paint(leaves))
	# Локально відносно `body` (не світова точка): без цього дерево без
	# моделі мало крону сиротою поруч, а не в собі — підвантаження мусить
	# мати ОДИН вузол на дерево, щоб вивантажувати його цілим.
	green.position = Vector3(0, height + crown.height * 0.35, 0)
	body.add_child(green)
	return body


## Моделі скель для гір — той самий пак, що й дерева.
const MOUNTAIN_MODELS := [
	"res://models/nature/Rock_Medium_1.gltf",
	"res://models/nature/Rock_Medium_2.gltf",
	"res://models/nature/Rock_Medium_3.gltf",
]
## Висота моделі скелі в наборі, заміряно (1,9…2,3 м).
const ROCK_MODEL_HEIGHT := 2.3


## Гори: скелі на краю світу, підняті до потрібної висоти. Через них не
## пройти — вони й є межа.
func _mountains() -> void:
	for hill: Dictionary in data.get("гори", []):
		var height := float(hill.get("висота", 20))
		var radius := float(hill.get("радіус", 15))
		var body := StaticBody3D.new()
		body.name = _named("Гора")
		body.position = _on_ground(_point(hill["де"]))
		add_child(body)
		var wall := CollisionShape3D.new()
		wall.name = "Стіна"
		var shape := CylinderShape3D.new()
		shape.radius = radius * 0.7
		shape.height = height
		wall.shape = shape
		wall.position = Vector3(0, height * 0.5, 0)
		body.add_child(wall)

		var model_path: String = MOUNTAIN_MODELS[randi() % MOUNTAIN_MODELS.size()]
		if ResourceLoader.exists(model_path):
			var view: Node3D = (load(model_path) as PackedScene).instantiate()
			view.name = "Модель"
			var scale := height / ROCK_MODEL_HEIGHT
			view.scale = Vector3(scale, scale, scale)
			view.rotation.y = randf() * TAU
			body.add_child(view)
			_no_shadows(view)
			continue

		var mesh := CylinderMesh.new()
		mesh.top_radius = radius * 0.06
		mesh.bottom_radius = radius
		mesh.height = height
		mesh.radial_segments = 12
		var mesh_view := MeshInstance3D.new()
		mesh_view.name = "Меш"
		mesh_view.mesh = mesh
		mesh_view.set_surface_override_material(0,
				_paint(str(hill.get("колір", "#6a6f74"))))
		mesh_view.position = Vector3(0, height * 0.5, 0)
		body.add_child(mesh_view)


static func _point(from: Variant) -> Vector3:
	var list: Array = from
	return Vector3(float(list[0]), float(list[1]), float(list[2]))


## Туман по зоні бачення (П-65).
##
## Сервер шле лише те, що гравець бачить, — за межею просто порожнеча.
## Туман має ховати рівно цю межу: інакше або видно, як істоти
## з'являються з нізвідки, або туман з'їдає те, що ще видно.
func fog_to_vision(radius: float) -> void:
	if _air == null:
		return
	var spare: float = float(data.get("туман", {}).get("запас", 1.15))
	# Туман ЗА ВІДСТАННЮ, а не за щільністю: у нього є початок і кінець,
	# і кінець можна поставити рівно на межу бачення. Щільнісний туман
	# такого не вміє — перша спроба з ним залила все молоком уже за
	# п'ять кроків.
	_air.fog_mode = Environment.FOG_MODE_DEPTH
	_air.fog_depth_end = radius * spare
	# Туман починається не з половини відстані, а з двох третин: при 0,45
	# він з'їдав колір землі вже за двадцять чотири метри, і краєвид
	# виглядав як біла пляма з тінями.
	_air.fog_depth_begin = _air.fog_depth_end * 0.66
	_air.fog_depth_curve = 1.4
	# Небо туман не чіпає: інакше зникає обрій, і світ стає коробкою.
	_air.fog_sky_affect = 0.25
