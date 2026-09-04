extends Node
## Печери-підземелля (П-153, Ф5) — подивитись і порівняти зі зразком,
## який дав замовник («Forge of the Gods: Lower Level»).
##
## Ганяти так (сценою, бо потрібні автозавантаження):
##     ./run.sh --печери
##
## Показує шість печер згори, як на зразку: жовта крапка — вихід нагору,
## кольорова — палата боса (колір грейду). Друкує заразом числа, за
## якими печеру видно й без картинки: скільки прохідних клітинок, чи всі
## вони зв'язані між собою (у печеру, куди не дійти, гравця не пустиш) і
## яка частка сітки зайнята.
##
## Esc — вийти, пробіл — знімок, колесо миші — ближче/далі.

const SHOWN := 6
const STEP := 140.0
const ZOOM_STEP := 12.0


class InputCatcher extends Node:
	var zoom := 0.0

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				zoom -= ZOOM_STEP
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				zoom += ZOOM_STEP


@onready var root: Window = get_tree().root


func _ready() -> void:
	_go()


func _go() -> void:
	await get_tree().process_frame
	var world := Node3D.new()
	root.add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-64, -28, 0)
	sun.light_energy = 1.0
	world.add_child(sun)
	var air := Environment.new()
	air.background_mode = Environment.BG_COLOR
	air.background_color = Color(0.03, 0.03, 0.04)
	air.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	air.ambient_light_color = Color(0.5, 0.5, 0.55)
	air.ambient_light_energy = 0.8
	air.glow_enabled = true
	var holder := WorldEnvironment.new()
	holder.environment = air
	world.add_child(holder)

	var grades: Array = ItemBook.GRADES
	print("\n— печери (П-153, Ф5) —")
	print("  сітка %d×%d по %.0f м = %.0f×%.0f м на печеру"
			% [Cave.GRID, Cave.GRID, Cave.CELL, Cave.GRID * Cave.CELL,
			   Cave.GRID * Cave.CELL])
	for i in SHOWN:
		var cave := Cave.new()
		cave.name = "Печера%d" % i
		world.add_child(cave)
		cave.build(20260905 + i * 7717, str(grades[i % grades.size()]), i + 1)
		cave.raise_walls()
		cave.position = Vector3((i % 3) * STEP - STEP, 0.0,
				float(i / 3) * STEP - STEP * 0.5)

		_mark(world, cave.position + cave.exit_at, Color(0.98, 0.86, 0.35))
		_mark(world, cave.position + cave.boss_at,
				ItemIcon.grade_color(cave.grade))

		var open := cave.open_count()
		var reach := _reachable(cave)
		print("  %d · грейд %-2s · прохідних %4d (%.0f%% сітки) · "
				% [i + 1, cave.grade, open,
				   100.0 * open / float(Cave.GRID * Cave.GRID)]
				+ "зв'язано %d (%s) · вихід↔бос %.0f м"
				% [reach, "усе" if reach == open else "‼ Є ВІДРІЗАНЕ",
				   cave.exit_at.distance_to(cave.boss_at)])

	_report_apart()

	var catcher := InputCatcher.new()
	world.add_child(catcher)
	var high := 300.0
	var eye := Camera3D.new()
	eye.fov = 70
	world.add_child(eye)
	eye.current = true
	eye.position = Vector3(0, high, 1.0)
	eye.look_at(Vector3.ZERO)

	for i in 10:
		await get_tree().process_frame
	Shot.take(world)

	print("\n  Esc — вийти · пробіл — знімок · колесо — вище/нижче")
	root.close_requested.connect(get_tree().quit)
	var shot_held := false
	while true:
		await get_tree().process_frame
		if Input.is_key_pressed(KEY_ESCAPE):
			break
		if Input.is_key_pressed(KEY_SPACE):
			if not shot_held:
				Shot.take(world)
			shot_held = true
		else:
			shot_held = false
		if catcher.zoom != 0.0:
			high = clampf(high + catcher.zoom, 60.0, 700.0)
			catcher.zoom = 0.0
			eye.position = Vector3(0, high, 1.0)
			eye.look_at(Vector3.ZERO)
	get_tree().quit()


## Чи справді підземелля стоять «поруч, але не перетинаються» — це
## пряма вимога замовника, і перевіряти її треба числом, а не вірою.
func _report_apart() -> void:
	var side := Cave.GRID * Cave.CELL
	print("\n— де вони стоять (вимога: поруч, але не перетинатись) —")
	print("  світ 600×600, тобто край суші на 300 м від центру")
	var first := Cave.spot_for(0)
	print("  перше підземелля в (%.0f, %.0f, %.0f) — до суші %.0f м"
			% [first.x, first.y, first.z, absf(first.z) - 300.0])
	print("  крок між підземеллями %.0f м при розмірі печери %.0f м — "
			% [Cave.APART, side]
			+ "запас %.0f м" % (Cave.APART - side))
	print("  перекриття: %s"
			% ("немає" if Cave.APART > side else "‼ Є"))


## Чи всі прохідні клітинки з'єднані: заливка від першої знайденої.
func _reachable(cave: Cave) -> int:
	var start := Vector2i(-1, -1)
	for z in Cave.GRID:
		for x in Cave.GRID:
			if cave.is_open(x, z):
				start = Vector2i(x, z)
				break
		if start.x >= 0:
			break
	if start.x < 0:
		return 0
	var seen := {}
	var wave: Array[Vector2i] = [start]
	seen[start] = true
	while not wave.is_empty():
		var at: Vector2i = wave.pop_back()
		for side: Array in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var next := Vector2i(at.x + side[0], at.y + side[1])
			if seen.has(next) or not cave.is_open(next.x, next.y):
				continue
			seen[next] = true
			wave.append(next)
	return seen.size()


func _mark(world: Node3D, at: Vector3, tone: Color) -> void:
	var pin := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 2.4
	ball.height = 4.8
	pin.mesh = ball
	var glow := StandardMaterial3D.new()
	glow.albedo_color = tone
	glow.emission_enabled = true
	glow.emission = tone
	glow.emission_energy_multiplier = 3.0
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pin.set_surface_override_material(0, glow)
	pin.position = at + Vector3(0, 3.0, 0)
	world.add_child(pin)
