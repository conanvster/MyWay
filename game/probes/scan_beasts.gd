extends SceneTree
## Демо звірів, зроблених за референсом (шлях А, `spec/генерація-3d-
## моделей-монстрів.md`): заєць, вовк, кажан, скорпіон — кожен рух окремою фігурою,
## з хутром шарами, як у грі.
##
## Ганяти так:
##     ./run.sh --звірі-скан
##     ./run.sh --звірі-скан --знімок /шлях/основа   # знімок і вийти
##
## Слово замовника 23.09.2026: «зроби окреме демо для зайця, вовка та
## кажана і підніми моделі вище підлоги». Загальний `--рухи-монстрів` ці
## моделі не показував: там кожна фігура — фізичний моб на плиті БЕЗ
## колізії, тож, поки вантажились 925 фігур, звірі провалювались під
## підлогу, і на знімку лишались самі підписи. Тут — голий
## `SkinnedModel` (те саме, з чого моб складає вигляд: модель, зріст,
## хутро з `data/mobs.json`), без фізики, і кожна фігура стоїть на
## підставці над підлогою.
##
## Камера (слово замовника 23.09.2026: «хочу роздивитися модель — додай
## змогу керувати камерою»):
##   ліва кнопка + тягнути — обертати довкола точки огляду;
##   права / середня + тягнути — зсувати точку огляду;
##   колесо — ближче/далі (аж до морди впритул);
##   W A S D — точку вперед/ліворуч/назад/праворуч, Q E — вниз/вгору;
##   клік по фігурі — навести на неї; 1 2 3 4 — ряд зайця/вовка/кажана/скорпіона;
##   R — загальний вид і самообертання; пробіл — знімок; Esc — вийти.
##
## Одна довільна модель (11.10.2026, слово замовника «додай в гру, я
## перевірю, які рухи у цієї орчихи є») — усі її рухи, не лише MOVES:
##     ./run.sh --звірі-скан --модель res://models/own/<файл>.glb [--зріст 1.9]
## Щойно людина торкнулась керування — камера сама вже не ходить.

const KINDS := ["заєць", "вовк", "кажан", "скорпіон"]
## Порядок рухів; яких у моделі немає — пропускаються.
const MOVES := ["Idle", "Walk", "Flying", "Attack", "Death"]
const STEP_X := 1.8
const STEP_Z := 2.4
## Підставка: верх на цій висоті, звір стоїть на ній.
const STAND := 0.25
## Над підставкою (метри). Кажан теж на ній (кінчиком хвоста): у
## повітрі з камери згори він здавався відлетілим на ряд назад.
const HOVER := {}
## Поворот до камери: 180 — мордою, ще трохи — три чверті.
const FACE := 205.0
## Колесо множить відстань на це (ближче — ділить): крок відчутний і
## здалеку, і впритул.
const ZOOM_FACTOR := 1.15
const ZOOM_NEAR := 0.25
const ORBIT_SPEED := 0.3        ## градусів на піксель
const MOVE_SPEED := 1.2         ## метрів за секунду на кожен метр відстані


## Збирає, що зробила людина за кадр; головний цикл забирає й обнуляє.
class InputCatcher extends Node:
	var zoom_steps := 0
	var orbit := Vector2.ZERO
	var pan := Vector2.ZERO
	var click := Vector2(-1, -1)
	var keys: Array = []          ## натиснуті за кадр: KEY_1… KEY_R
	var _press_at := Vector2.ZERO
	var _dragged := false

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			if event.pressed:
				if event.button_index == MOUSE_BUTTON_WHEEL_UP:
					zoom_steps -= 1
				elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
					zoom_steps += 1
				elif event.button_index == MOUSE_BUTTON_LEFT:
					_press_at = event.position
					_dragged = false
			elif event.button_index == MOUSE_BUTTON_LEFT and not _dragged:
				click = event.position
		elif event is InputEventMouseMotion:
			if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
				orbit += event.relative
				if event.position.distance_to(_press_at) > 4.0:
					_dragged = true
			elif event.button_mask & (MOUSE_BUTTON_MASK_RIGHT
					| MOUSE_BUTTON_MASK_MIDDLE):
				pan += event.relative
		elif event is InputEventKey and event.pressed and not event.echo:
			keys.append(event.keycode)


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(1920, 1080)
	await process_frame
	var args := OS.get_cmdline_user_args()
	var data: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/mobs.json"))

	var world := Node3D.new()
	root.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	world.add_child(sun)
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var air := Environment.new()
	air.background_mode = Environment.BG_SKY
	air.sky = sky
	air.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	air.ambient_light_energy = 1.0
	air.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var holder := WorldEnvironment.new()
	holder.environment = air
	world.add_child(holder)

	var widest := 0
	var rows: Array = []
	var single := _single(args)
	if not single.is_empty():
		rows.append(single)
		widest = single["moves"].size()
	for kind: String in ([] if not single.is_empty() else KINDS):
		var look := _look(data, kind)
		if look.is_empty():
			print("  ‼ немає виду «%s» у data/mobs.json" % kind)
			continue
		var path := str(look.get("модель", ""))
		if not ResourceLoader.exists(path):
			print("  ‼ %s: немає моделі %s" % [kind, path])
			continue
		var probe: Node3D = (load(path) as PackedScene).instantiate()
		var player: AnimationPlayer = probe.find_child("AnimationPlayer",
				true, false)
		var moves: Array = []
		for m: String in MOVES:
			if player != null and player.has_animation(m):
				moves.append(m)
		probe.free()
		rows.append({"kind": kind, "look": look, "moves": moves})
		widest = maxi(widest, moves.size())

	if rows.is_empty():
		print("  ‼ показувати нічого")
		quit(1)
		return
	var ground := MeshInstance3D.new()
	var plate := BoxMesh.new()
	plate.size = Vector3(widest * STEP_X + 4.0, 0.2, rows.size() * STEP_Z + 4.0)
	ground.mesh = plate
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color("#4a5c3a")
	ground.set_surface_override_material(0, grass)
	ground.position = Vector3(0, -0.1, 0)
	world.add_child(ground)

	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("#8a8a86")
	var figures: Array = []     ## {centre, size, row}
	var from_x := -STEP_X * (widest - 1) * 0.5
	var from_z := -STEP_Z * (rows.size() - 1) * 0.5
	for r in rows.size():
		var row: Dictionary = rows[r]
		var look: Dictionary = row["look"]
		var size := float(look.get("зріст", 1.0))
		var lift: float = STAND + float(HOVER.get(row["kind"], 0.0))
		for c in row["moves"].size():
			var move: String = row["moves"][c]
			var at := Vector3(from_x + c * STEP_X, 0.0, from_z + r * STEP_Z)
			var stand := MeshInstance3D.new()
			var disc := CylinderMesh.new()
			disc.top_radius = 0.55
			disc.bottom_radius = 0.6
			disc.height = STAND
			stand.mesh = disc
			stand.set_surface_override_material(0, stone)
			stand.position = at + Vector3(0, STAND * 0.5, 0)
			world.add_child(stand)

			var skin := SkinnedModel.new()
			skin.path = str(look.get("модель", ""))
			skin.height = size
			skin.fur = look.get("хутро", {})
			world.add_child(skin)
			skin.build()
			skin.position = at + Vector3(0, lift, 0)
			figures.append({"centre": at + Vector3(0, lift + size * 0.5, 0),
					"size": size, "row": r})
			skin.rotation_degrees.y = FACE
			var player: AnimationPlayer = skin.find_child("AnimationPlayer",
					true, false)
			if player != null:
				player.get_animation(move).loop_mode = Animation.LOOP_LINEAR
				player.play(move)

			var tag := Label3D.new()
			tag.text = move if not single.is_empty() \
					else "%s: %s" % [row["kind"], move]
			tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			tag.font_size = 40
			tag.outline_size = 12
			tag.outline_modulate = Color(0, 0, 0, 0.9)
			tag.pixel_size = 0.004
			tag.position = at + Vector3(0, lift + size + 0.25, 0)
			world.add_child(tag)
			print("  %-8s %s" % [row["kind"], move])

	var catcher := InputCatcher.new()
	world.add_child(catcher)
	var span := maxf(widest * STEP_X, rows.size() * STEP_Z)
	var home_aim := Vector3(0, 0.7, 0)
	var home_distance := span * 0.9
	var home_pitch := -atan(0.3)        # як було: висота 0,3 відстані
	var aim := home_aim
	var distance := home_distance
	var yaw := 0.0
	var pitch := home_pitch
	var eye := Camera3D.new()
	eye.fov = 50
	eye.near = 0.02
	world.add_child(eye)
	eye.current = true
	_place(eye, aim, distance, yaw, pitch)

	var at := args.find("--знімок")
	if at >= 0 and at + 1 < args.size():
		# Знімок і вийти — для перевірки без людини біля вікна.
		for f in 60:
			await process_frame
		var image := root.get_texture().get_image()
		var out: String = args[at + 1] + ".png"
		var err := image.save_png(out)
		print("[знімок] %s%s" % [out, "" if err == OK else " ‼ " + error_string(err)])
		quit(0 if err == OK else 1)
		return

	var hint := Label.new()
	hint.text = ("ЛКМ — обертати · ПКМ/СКМ — зсувати · колесо — ближче/далі"
			+ "\nWASD/QE — рухати точку · клік по звірові — до нього"
			+ " · 1 2 3 4 — заєць/вовк/кажан/скорпіон\nR — загальний вид · пробіл — знімок"
			+ " · Esc — вийти")
	hint.position = Vector2(16, 12)
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	hint.add_theme_constant_override("outline_size", 6)
	var overlay := CanvasLayer.new()
	overlay.add_child(hint)
	world.add_child(overlay)

	for f in 30:
		await process_frame
	Shot.take(world)
	print("\n  ЛКМ — обертати · ПКМ — зсувати · колесо — ближче/далі · WASD/QE"
			+ " · клік — до звіра · 1 2 3 4 — ряди · R — загальний вид"
			+ " · пробіл — знімок · Esc — вийти")
	root.close_requested.connect(quit)
	var shot_held := false
	var auto := true
	var swing_clock := 0.0
	var last := Time.get_ticks_msec() / 1000.0
	while true:
		await process_frame
		var now := Time.get_ticks_msec() / 1000.0
		var delta := minf(now - last, 0.1)
		last = now
		if Input.is_key_pressed(KEY_ESCAPE):
			break
		if Input.is_key_pressed(KEY_SPACE):
			if not shot_held:
				Shot.take(world)
			shot_held = true
		else:
			shot_held = false

		var touched := false
		if catcher.zoom_steps != 0:
			distance = clampf(distance * pow(ZOOM_FACTOR, catcher.zoom_steps),
					ZOOM_NEAR, span * 3.0)
			catcher.zoom_steps = 0
			touched = true
		if catcher.orbit != Vector2.ZERO:
			yaw -= deg_to_rad(catcher.orbit.x * ORBIT_SPEED)
			pitch = clampf(pitch - deg_to_rad(catcher.orbit.y * ORBIT_SPEED),
					deg_to_rad(-85.0), deg_to_rad(85.0))
			catcher.orbit = Vector2.ZERO
			touched = true
		if catcher.pan != Vector2.ZERO:
			# Зсув у площині екрана, пропорційно відстані — щоб точка
			# йшла за мишею і здалеку, і впритул.
			var k := distance * 0.0015
			aim += (-eye.global_basis.x * catcher.pan.x
					+ eye.global_basis.y * catcher.pan.y) * k
			catcher.pan = Vector2.ZERO
			touched = true
		var move := Vector3.ZERO
		if Input.is_key_pressed(KEY_W):
			move.z -= 1
		if Input.is_key_pressed(KEY_S):
			move.z += 1
		if Input.is_key_pressed(KEY_A):
			move.x -= 1
		if Input.is_key_pressed(KEY_D):
			move.x += 1
		if Input.is_key_pressed(KEY_Q):
			move.y -= 1
		if Input.is_key_pressed(KEY_E):
			move.y += 1
		if move != Vector3.ZERO:
			# Вперед/убік — по землі в напрямку погляду, не в небо.
			var flat := Basis(Vector3.UP, yaw)
			aim += (flat * Vector3(move.x, 0, move.z) + Vector3(0, move.y, 0)) \
					* MOVE_SPEED * maxf(distance, 0.5) * delta
			touched = true
		for key in catcher.keys:
			if key == KEY_R:
				aim = home_aim
				distance = home_distance
				yaw = 0.0
				pitch = home_pitch
				auto = true
				swing_clock = 0.0
			elif key >= KEY_1 and key <= KEY_9:
				var row := int(key - KEY_1)
				var picked: Array = figures.filter(func(f): return f["row"] == row)
				if not picked.is_empty():
					var centre := Vector3.ZERO
					var tall := 0.0
					for f in picked:
						centre += f["centre"]
						tall = maxf(tall, f["size"])
					aim = centre / picked.size()
					distance = maxf(tall * 2.0, picked.size() * STEP_X * 0.9)
					touched = true
		catcher.keys.clear()
		if catcher.click.x >= 0:
			var hit := _pick(eye, catcher.click, figures)
			if not hit.is_empty():
				aim = hit["centre"]
				distance = hit["size"] * 2.2
				touched = true
			catcher.click = Vector2(-1, -1)
		if touched:
			auto = false
		if auto:
			# Сама ходить дугою спереду (±35°), доки людина не взялась.
			swing_clock += delta
			yaw = sin(swing_clock * 0.24) * deg_to_rad(35.0)
		_place(eye, aim, distance, yaw, pitch)
	quit()


## Камера на сфері довкола `aim`: yaw — довкола вертикалі (0 — спереду,
## з +Z), pitch — нахил (від'ємний — дивимось згори).
func _place(eye: Camera3D, aim: Vector3, distance: float, yaw: float,
		pitch: float) -> void:
	var dir := Vector3(sin(yaw) * cos(pitch), -sin(pitch),
			cos(yaw) * cos(pitch))
	eye.position = aim + dir * distance
	eye.look_at(aim)


## Яку фігуру влучив клік: найближча до променя з камери, якщо промінь
## пройшов від її середини ближче, ніж на пів її зросту.
func _pick(eye: Camera3D, at: Vector2, figures: Array) -> Dictionary:
	var from := eye.project_ray_origin(at)
	var dir := eye.project_ray_normal(at)
	var best := {}
	var best_along := INF
	for f: Dictionary in figures:
		var to: Vector3 = f["centre"] - from
		var along := to.dot(dir)
		if along <= 0.0:
			continue
		var off := (to - dir * along).length()
		if off < f["size"] * 0.6 and along < best_along:
			best = f
			best_along = along
	return best


func _look(data: Dictionary, kind: String) -> Dictionary:
	for key in data:
		var row = data[key]
		if row is Dictionary and str(row.get("назва", "")) == kind:
			return row.get("вигляд", {})
	return {}


## `--модель <шлях> [--зріст N]` → рядок з усіма рухами файлу. Порожньо —
## ключа немає; файлу немає — гучно й порожньо.
func _single(args: PackedStringArray) -> Dictionary:
	var at := args.find("--модель")
	if at < 0 or at + 1 >= args.size():
		return {}
	var path := args[at + 1]
	if not ResourceLoader.exists(path):
		print("  ‼ немає моделі %s" % path)
		return {}
	var tall := 1.0
	var h := args.find("--зріст")
	if h >= 0 and h + 1 < args.size():
		tall = float(args[h + 1])
	var probe: Node3D = (load(path) as PackedScene).instantiate()
	var player: AnimationPlayer = probe.find_child("AnimationPlayer", true,
			false)
	var moves: Array = []
	if player != null:
		for m: String in player.get_animation_list():
			if m != "RESET":
				moves.append(m)
	probe.free()
	print("  %s: рухів %d — %s" % [path.get_file(), moves.size(),
			", ".join(PackedStringArray(moves))])
	if moves.is_empty():
		moves.append("RESET")
	return {"kind": path.get_file().get_basename(),
			"look": {"модель": path, "зріст": tall}, "moves": moves}
