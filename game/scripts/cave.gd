class_name Cave
extends Node3D
## Печера-підземелля (П-153, Ф5) — за зразком, що дав замовник
## 05.09.2026: мапа «Forge of the Gods: Lower Level» з Lineage 2.
##
## Що на тому зразку й що з цього тут:
##   · неправильної форми палати-«кляксі», не кімнати з кутами — так
##   · вузькі криві переходи між ними — так
##   · вихід «To Upper» на краю — так (`exit_at`)
##   · велика палата з окремим входом під боса — так (`boss_at`)
##
## Де воно стоїть. Замовник сказав: «поруч, але щоб світи не
## перетиналися». Саме так і зроблено — і це заразом найдешевша
## відповідь на «телепорти відрізають видимість» (П-153): бачення в грі
## рахується ВІДСТАННЮ (`vision.gd`, 18 м із гістерезисом), тож
## підземелля за кілометр від суші невидиме саме собою. Ніякого другого
## сервера, окремої сцени чи поля «де ти» не потрібно — питання П-167
## знімається саме цим.
##
## Форма береться так: кілька палат неправильної форми, з'єднані
## коридорами по кістяку (кожна наступна — до найближчої вже з'єднаної),
## потім три проходи «клітинного автомата», які згладжують кути й
## роблять межі рваними. Саме автомат і дає ту органічність, якої не
## буває в прямокутниках.

## Скільки метрів на клітинку сітки. Дрібніше — плавніші межі, дорожча
## сітка; 2 м дає межу, помітну оком, і сітку 60×60 на печеру.
const CELL := 2.0
## Скільки клітинок на бік.
const GRID := 60
## Висота стін, метрів.
const WALL_HEIGHT := 6.0

## Наскільки далеко від суші живуть підземелля. Світ — 600×600, тобто
## край на 300; кілометр лишає запас, якого вистачить, навіть якщо суша
## колись подвоїться.
const FAR_AWAY := Vector3(0, 0, -4000)
## Крок між сусідніми підземеллями. Печера займає GRID*CELL = 120 м,
## тож 400 лишає між ними втричі більше, ніж вони самі.
const APART := 400.0

## Скільки палат. Менше — коридорна кишка, більше — суцільна порожнина.
const ROOMS := 9
## Радіус палати в клітинках. Підібрано за зразком замовника: там палата
## завширшки приблизно як шоста частина мапи, а перехід між ними —
## удесятеро вужчий. Перша спроба (4,0-7,5) дала не палати з ходами, а
## павутину тріщин: палати були завбільшки з коридори, і око їх не
## розрізняло.
const ROOM_MIN := 6.0
const ROOM_MAX := 11.0
## Проходів згладжування. Один майже нічого не міняє, чотири й більше
## з'їдають вузькі переходи разом із формою.
const SMOOTH_PASSES := 3

var grade := "E"
var level := 1

## Сітка: true — де можна ходити.
var open_cells: Array[bool] = []
## Де вхід (він же вихід нагору) і де палата боса, у місцевих метрах.
var exit_at := Vector3.ZERO
var boss_at := Vector3.ZERO

var _rng := RandomNumberGenerator.new()
## Центри палат — потрібні й для ходів, які копаються пізніше.
var _centers: Array[Vector2i] = []


## Де стоїть підземелля номер `at`. Рядком уздовж осі X, далеко від суші.
static func spot_for(at: int) -> Vector3:
	return FAR_AWAY + Vector3(float(at) * APART, 0.0, 0.0)


func _index(x: int, z: int) -> int:
	return z * GRID + x


func is_open(x: int, z: int) -> bool:
	if x < 0 or z < 0 or x >= GRID or z >= GRID:
		return false
	return open_cells[_index(x, z)]


## Клітинка -> місцеві метри (центр клітинки).
func _at(x: int, z: int) -> Vector3:
	return Vector3((float(x) - GRID * 0.5 + 0.5) * CELL, 0.0,
			(float(z) - GRID * 0.5 + 0.5) * CELL)


func build(with_seed: int, at_grade: String = "E",
		at_level: int = 1) -> void:
	grade = at_grade
	level = at_level
	_rng.seed = with_seed
	_carve()
	# ПОРЯДОК ВАЖИТЬ. Згладжуємо самі палати, і аж ПОТІМ копаємо ходи.
	# Навпаки не можна: автомат з'їдає все, що вужче за три клітинки, і
	# вузький хід просто зникає разом зі зв'язністю — проба 05.09.2026
	# спіймала печеру, де 154 клітинки з 907 виявились відрізані. Тепер
	# зв'язність не перевіряється навмання, а випливає з побудови.
	for i in SMOOTH_PASSES:
		_smooth()
	_tunnels()
	_raise()


## Палати й переходи. Спершу палати, тоді кістяк коридорів: кожна
## наступна палата тягне коридор до НАЙБЛИЖЧОЇ вже з'єднаної — так
## виходить дерево без окремих шматків, у яке не можна не потрапити.
func _carve() -> void:
	open_cells.clear()
	open_cells.resize(GRID * GRID)
	open_cells.fill(false)

	var centers: Array[Vector2i] = []
	var sizes: Array[float] = []
	var edge := 7
	for i in ROOMS:
		var c := Vector2i(_rng.randi_range(edge, GRID - 1 - edge),
				_rng.randi_range(edge, GRID - 1 - edge))
		# Не впритул одна до одної, інакше зіллються в пляму.
		var too_near := false
		for was: Vector2i in centers:
			if Vector2(c - was).length() < 9.0:
				too_near = true
				break
		if too_near:
			continue
		centers.append(c)
		sizes.append(_rng.randf_range(ROOM_MIN, ROOM_MAX))

	for i in centers.size():
		_blob(centers[i], sizes[i])
	_centers = centers

	if centers.is_empty():
		return

	# Бос — у найбільшій палаті. Вихід — у НАЙДАЛЬШІЙ ВІД БОСА, а не
	# просто найдальшій від центру: інакше вони раз у раз випадали в одну
	# й ту саму палату, і гравець з'являвся б просто на босові (спіймано
	# пробою 05.09.2026 — дві печери з шести мали «вихід↔бос 0 м»).
	var big_at := 0
	var big_by := -1.0
	for i in centers.size():
		if sizes[i] > big_by:
			big_by = sizes[i]
			big_at = i
	var far_at := big_at
	var far_by := -1.0
	for i in centers.size():
		if i == big_at:
			continue
		var from_boss := Vector2(centers[i] - centers[big_at]).length()
		if from_boss > far_by:
			far_by = from_boss
			far_at = i

	exit_at = _at(centers[far_at].x, centers[far_at].y)
	boss_at = _at(centers[big_at].x, centers[big_at].y)
	# Палату боса робимо помітно більшою: на зразку вона теж найбільша.
	_blob(centers[big_at], big_by * 1.5)


## Ходи між палатами — копаються ПІСЛЯ згладжування (див. `build`).
##
## Кістяк: кожна палата тягнеться до найближчої вже приєднаної — так
## виходить дерево без окремих шматків. Плюс одна-дві зайві петлі: на
## зразку замовника теж не дерево, а є обходи.
func _tunnels() -> void:
	var centers := _centers
	if centers.size() < 2:
		return
	var joined: Array[int] = [0]
	while joined.size() < centers.size():
		var best_from := -1
		var best_to := -1
		var best := 1e9
		for a: int in joined:
			for b in centers.size():
				if b in joined:
					continue
				var far := Vector2(centers[a] - centers[b]).length()
				if far < best:
					best = far
					best_from = a
					best_to = b
		if best_to < 0:
			break
		_tunnel(centers[best_from], centers[best_to])
		joined.append(best_to)

	for i in mini(2, centers.size() / 4):
		var a := _rng.randi_range(0, centers.size() - 1)
		var b := _rng.randi_range(0, centers.size() - 1)
		if a != b:
			_tunnel(centers[a], centers[b])


## Палата неправильної форми: круг, радіус якого гуляє по куту.
func _blob(at: Vector2i, size: float) -> void:
	var wobble := _rng.randf() * TAU
	for z in GRID:
		for x in GRID:
			var d := Vector2(x - at.x, z - at.y)
			var far := d.length()
			if far > size * 1.6:
				continue
			var angle := atan2(d.y, d.x)
			var edge: float = size * (0.72 + 0.34 * sin(angle * 3.0 + wobble)
					+ 0.16 * sin(angle * 5.0 - wobble * 2.0))
			if far <= edge:
				open_cells[_index(x, z)] = true


## Вузький кривий перехід. Спершу по одній осі, тоді по другій, з
## випадковим зсувом — рівних коридорів у печері не буває.
func _tunnel(from: Vector2i, to: Vector2i) -> void:
	var at := from
	var guard := 0
	# Хід має бути ПОМІТНО вужчий за палату, інакше печера читається як
	# суцільна павутина (див. ROOM_MIN).
	var wide := 0 if _rng.randf() < 0.7 else 1
	_dig(at, wide)
	while at != to and guard < GRID * 4:
		guard += 1
		if at.x != to.x and (at.y == to.y or _rng.randf() < 0.5):
			at.x += signi(to.x - at.x)
		elif at.y != to.y:
			at.y += signi(to.y - at.y)
		# Копати ПІСЛЯ КОЖНОГО кроку, і після зсуву теж. Інакше хід
		# завширшки в одну клітинку йде «сходинками», сусідні клітинки
		# торкаються лише кутами — і пройти ним не можна, хоч на око він
		# суцільний. Проба 05.09.2026 показала це числом: 123 зв'язані
		# клітинки з 1272 при цілком пристойній картинці.
		_dig(at, wide)
		# Легке зміщення вбік — саме воно й робить хід кривим.
		if _rng.randf() < 0.18:
			at.y += _rng.randi_range(-1, 1)
			at.y = clampi(at.y, 2, GRID - 3)
			_dig(at, wide)
	_dig(to, wide)


func _dig(at: Vector2i, wide: int) -> void:
	for z in range(at.y - wide, at.y + wide + 1):
		for x in range(at.x - wide, at.x + wide + 1):
			if x < 1 or z < 1 or x >= GRID - 1 or z >= GRID - 1:
				continue
			open_cells[_index(x, z)] = true


## Клітинний автомат: клітинка стає такою, якою є більшість сусідів.
## Це й перетворює рублені краї на печерні.
func _smooth() -> void:
	var was := open_cells.duplicate()
	for z in range(1, GRID - 1):
		for x in range(1, GRID - 1):
			var around := 0
			for dz in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if dx == 0 and dz == 0:
						continue
					if was[_index(x + dx, z + dz)]:
						around += 1
			if around >= 5:
				open_cells[_index(x, z)] = true
			elif around <= 2:
				open_cells[_index(x, z)] = false


## Край сітки завжди камінь: інакше з печери можна вийти в порожнечу.
func _raise() -> void:
	for i in GRID:
		open_cells[_index(i, 0)] = false
		open_cells[_index(i, GRID - 1)] = false
		open_cells[_index(0, i)] = false
		open_cells[_index(GRID - 1, i)] = false


## Скільки клітинок прохідні — для проби й для звіту.
func open_count() -> int:
	var n := 0
	for cell: bool in open_cells:
		if cell:
			n += 1
	return n


## Збудувати видиме й непрохідне з готової сітки.
##
## Підлога — по квадрату на прохідну клітинку; стіни — по стінці на межу
## між прохідною й каменем. Зіткнення знімається з тієї самої геометрії
## (`create_trimesh_collision`), тож пройти крізь стіну не можна за
## означенням: те, що видно, і є те, що тримає.
func raise_walls() -> void:
	var floor_mesh := SurfaceTool.new()
	floor_mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wall_mesh := SurfaceTool.new()
	wall_mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := CELL * 0.5

	for z in GRID:
		for x in GRID:
			if not is_open(x, z):
				continue
			var at := _at(x, z)
			_quad(floor_mesh,
					at + Vector3(-half, 0, -half),
					at + Vector3(half, 0, -half),
					at + Vector3(half, 0, half),
					at + Vector3(-half, 0, half))
			# Стінка стає там, де сусід — камінь.
			for side: Array in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				var dx: int = side[0]
				var dz: int = side[1]
				if is_open(x + dx, z + dz):
					continue
				var mid := at + Vector3(dx, 0, dz) * half
				var along := Vector3(dz, 0, -dx) * half
				var up := Vector3(0, WALL_HEIGHT, 0)
				_quad(wall_mesh, mid - along, mid + along,
						mid + along + up, mid - along + up)

	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.30, 0.29, 0.31)
	rock.roughness = 0.95
	var dust := StandardMaterial3D.new()
	dust.albedo_color = Color(0.22, 0.21, 0.23)
	dust.roughness = 1.0

	var ground := MeshInstance3D.new()
	ground.name = "Підлога"
	floor_mesh.generate_normals()
	ground.mesh = floor_mesh.commit()
	ground.set_surface_override_material(0, dust)
	add_child(ground)
	ground.create_trimesh_collision()

	var walls := MeshInstance3D.new()
	walls.name = "Стіни"
	wall_mesh.generate_normals()
	walls.mesh = wall_mesh.commit()
	walls.set_surface_override_material(0, rock)
	add_child(walls)
	walls.create_trimesh_collision()

	# Світло: у печері його нема звідки взяти, а без нього не видно
	# нічого взагалі. Кольором грейду — той самий знак, що й на святині.
	var lamp := OmniLight3D.new()
	lamp.name = "Сяйво"
	lamp.light_color = ItemIcon.grade_color(grade)
	lamp.light_energy = 3.0
	lamp.omni_range = 40.0
	lamp.position = boss_at + Vector3(0, 5, 0)
	add_child(lamp)

	var door := OmniLight3D.new()
	door.name = "Вихід"
	door.light_color = Color(0.95, 0.88, 0.62)
	door.light_energy = 2.4
	door.omni_range = 26.0
	door.position = exit_at + Vector3(0, 4, 0)
	add_child(door)


func _quad(to: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		d: Vector3) -> void:
	to.add_vertex(a)
	to.add_vertex(b)
	to.add_vertex(c)
	to.add_vertex(a)
	to.add_vertex(c)
	to.add_vertex(d)
