extends Node
## Низькорівневі підземелля (П-190): десять шаблонів — мапи, числа, знімки.
##
## Ганяти сценою (потрібні автозавантаження):
##     ./run.sh --підземелля
##         показ: 1…9, 0 — котре підземелля; Tab — прохід / згори як у грі;
##         пробіл — знімок; Esc — вийти
##     godot --path game res://scenes/dungeons.tscn -- --мапи <тека>
##         мапи PNG у стилі «Forge of the Gods» і числа; можна --headless
##     godot --path game res://scenes/dungeons.tscn -- --знімки <тека>
##         те саме плюс чотири знімки на підземелля з вікна
##
## Що друкує, щоб підземелля було видно й без картинки: чи все прохідне
## зв'язане (не лізучи на кручі), скільки кроків від входу до боса, яка
## найкрутіша сходинка підлоги, скільки зграй і хто за воротами E, D, C.

const SEED := 20260913
const GATES := ["E", "D", "C"]
const PX := 5

var _book: DungeonBook
var _mobs: Dictionary = {}


func _ready() -> void:
	_go()


func _arg(name: String) -> String:
	var args := OS.get_cmdline_user_args()
	var at := args.find(name)
	if at >= 0 and at + 1 < args.size():
		return args[at + 1]
	return ""


func _seed_of(i: int) -> int:
	return SEED + i * 7919


func _go() -> void:
	await get_tree().process_frame
	var windowed := DisplayServer.get_name() != "headless"
	var data := GameData.new()
	data.load_all()
	_mobs = data.mobs
	_book = DungeonBook.load_book()
	if _book.templates.is_empty():
		print("‼ шаблонів немає — нема чого показувати")
		get_tree().quit(1)
		return

	var maps := _arg("--мапи")
	var shots := _arg("--знімки")
	var into := shots if shots != "" else maps
	if OS.get_cmdline_user_args().has("--стіни"):
		_walls()
		get_tree().quit()
		return
	var bad := _report(into)
	if shots != "" and windowed:
		# Лише для знімків: синхронізація на заблокованому екрані дає рівно
		# 1 кадр/с (пастка 11.09.2026). У показі — НІ: без неї карта малює
		# сотні кадрів на секунду й стоїть на 100% (замовник 13.09.2026:
		# «графічна карта не тягне», nvidia-smi — 166 Вт, 100%).
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		await _shots(shots)
	if into != "":
		get_tree().quit(1 if bad > 0 else 0)
		return
	await _interactive()


func _ordered() -> Array:
	var all := _book.ids()
	all.sort_custom(func(a, b): return int(_book.templates[a].get("№", 0)) \
			< int(_book.templates[b].get("№", 0)))
	return all


# --- числа й мапи ---------------------------------------------------------

func _report(into: String) -> int:
	var bad := 0
	print("\n— низькорівневі підземелля (П-190) —")
	var ids := _ordered()
	for i in ids.size():
		var id: String = ids[i]
		var started := Time.get_ticks_msec()
		var plan := _book.make(id, _seed_of(i))
		var spent := Time.get_ticks_msec() - started
		var open := plan.open_count()
		var reach := plan.reachable_count()
		var slope := plan.max_slope()
		var steps := plan.main_path.size()
		print("\n  %d · %s «%s» · %s · складність %d · %d×%d м · план %d мс"
				% [i + 1, id, plan.title, plan.style, plan.tier, plan.size,
				   plan.size, spent])
		print("    палат %d · прохідних %d (%.0f%% сітки) · у ходах %.0f%% · "
				% [plan.rooms.size(), open,
				   100.0 * open / float(plan.size * plan.size),
				   100.0 * plan.tunnel_count() / maxf(open, 1)]
				+ "тупиків %d · ніш %d · колон %d"
				% [plan.dead_ends, plan.niches.size(), plan.pillars.size()])
		var whole := reach == open
		var sane := slope <= DungeonPlan.STEEP
		var path_ok := steps > 0
		if not (whole and sane and path_ok):
			bad += 1
		print(("    зв'язано %d з %d (%s) · вхід→бос %s · "
				+ "найкрутіше %.2f м/м (%s)")
				% [reach, open, "усе" if whole else "‼ Є ВІДРІЗАНЕ",
				   "%d кроків" % steps if path_ok else "‼ НЕ ДІЙТИ",
				   slope, "гаразд" if sane else "‼ КРУЧА"])
		for gate: String in GATES:
			var rng := RandomNumberGenerator.new()
			rng.seed = _seed_of(i) + gate.unicode_at(0)
			var slots := _book.populate(plan, gate, _mobs, rng)
			print("    ворота %s: %s" % [gate, _describe(plan, slots)])
			if gate == "E" and into != "":
				_save_map(plan, slots, into.path_join("мапа-%02d-%s.png"
						% [i + 1, id]))
	print("\n  підсумок: %s" % ("усі %d без вад" % ids.size() if bad == 0
			else "‼ з вадами: %d" % bad))
	return bad


func _describe(plan: DungeonPlan, slots: Array[Dictionary]) -> String:
	var packs := 0
	var total := 0
	var by_name := {}
	var boss := "‼ немає"
	var unreachable := 0
	var from_exit := plan.distances(plan.room_cell(plan.exit_room))
	for s in slots:
		var cell: Vector2i = s["cell"]
		if from_exit[plan.index(cell.x, cell.y)] < 0:
			unreachable += 1
		if s["boss"]:
			boss = "%s %d рів." % [s["name"], s["level"]]
			continue
		packs += 1
		total += int(s["count"])
		var key := "%s %d" % [s["name"], s["level"]]
		by_name[key] = int(by_name.get(key, 0)) + int(s["count"])
	var parts: Array[String] = []
	for key: String in by_name.keys():
		parts.append("%s×%d" % [key, by_name[key]])
	return "%d зграй, %d монстрів (%s) · бос: %s%s" % [packs, total,
			", ".join(parts), boss,
			"" if unreachable == 0
			else " · ‼ недосяжних місць %d" % unreachable]


## Мапа як на зразку замовника: чорне тло, сіра порода з білим обрисом.
## Глибина підлоги — яскравістю: що нижче, то темніше. Вода — буро-синя,
## ніші — кістяні, вхід — жовтий, бос — червоне кільце, зграї — червоні
## крапки (більша — більша зграя), шлях до боса — пунктиром.
func _save_map(plan: DungeonPlan, slots: Array[Dictionary],
		path: String) -> void:
	var side := plan.size * PX
	var img := Image.create(side, side, false, Image.FORMAT_RGB8)
	img.fill(Color.BLACK)
	var low := 1e9
	var high := -1e9
	for i in plan.open.size():
		if plan.open[i] == 1:
			low = minf(low, plan.floor_y[i])
			high = maxf(high, plan.floor_y[i])
	var span := maxf(high - low, 0.01)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.25
	for z in plan.size:
		for x in plan.size:
			if not plan.is_open(x, z):
				continue
			var i := plan.index(x, z)
			var depth := (plan.floor_y[i] - low) / span
			for pz in PX:
				for px in PX:
					var grain := noise.get_noise_2d(x * PX + px, z * PX + pz)
					var v := 0.26 + 0.24 * depth + grain * 0.06
					var tone := Color(v, v, v)
					if plan.water and plan.tunnel[i] == 1:
						tone = Color(v * 0.55, v * 0.62, v * 0.75)
					if plan.room_of[i] < 0 and plan.tunnel[i] == 0:
						tone = Color(0.62, 0.55, 0.42)
					img.set_pixel(x * PX + px, z * PX + pz, tone)
	for z in plan.size:
		for x in plan.size:
			if not plan.is_open(x, z):
				continue
			for s: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0),
					Vector2i(0, 1), Vector2i(0, -1)]:
				if plan.is_open(x + s.x, z + s.y):
					continue
				for t in PX:
					var px := x * PX + (PX - 1 if s.x == 1 else 0 if s.x == -1
							else t)
					var pz := z * PX + (PX - 1 if s.y == 1 else 0 if s.y == -1
							else t)
					img.set_pixel(px, pz, Color(0.92, 0.92, 0.92))
	for n in range(0, plan.main_path.size(), 3):
		var c: Vector2i = plan.main_path[n]
		_dot(img, c, 1, Color(0.85, 0.75, 0.3))
	for s in slots:
		var c: Vector2i = s["cell"]
		if s["boss"]:
			_ring(img, c, 11, Color(0.95, 0.2, 0.15))
		else:
			_dot(img, c, 2 + int(s["count"]), Color(0.9, 0.15, 0.1))
	_dot(img, plan.room_cell(plan.exit_room), 7, Color(0.98, 0.86, 0.35))
	var err := img.save_png(path)
	print("    мапа: %s%s" % [ProjectSettings.globalize_path(path),
			"" if err == OK else " ‼ не збереглась: " + error_string(err)])


func _dot(img: Image, c: Vector2i, r: int, tone: Color) -> void:
	var cx := c.x * PX + PX / 2
	var cz := c.y * PX + PX / 2
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dz * dz <= r * r:
				_put(img, cx + dx, cz + dz, tone)


func _ring(img: Image, c: Vector2i, r: int, tone: Color) -> void:
	var cx := c.x * PX + PX / 2
	var cz := c.y * PX + PX / 2
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var d := dx * dx + dz * dz
			if d <= r * r and d >= (r - 2) * (r - 2):
				_put(img, cx + dx, cz + dz, tone)


func _put(img: Image, x: int, y: int, tone: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, tone)


## Чи кожна стіна дивиться в хід, а не в камінь — числом, без вікна.
func _walls() -> void:
	print("\n— стіни: лицем у хід чи в камінь —")
	var world := Node3D.new()
	add_child(world)
	var holder := WorldEnvironment.new()
	world.add_child(holder)
	var ids := _ordered()
	for i in ids.size():
		var view := _raise(world, holder, i)
		print("    стін %d · лицем у камінь %d · не туди, куди просили %d%s"
				% [view.walls_total, view.walls_into_rock,
				   view.walls_against_want,
				   "" if view.wall_samples.is_empty()
				   else " · напр. %s" % str(view.wall_samples)])
		view.free()


# --- знімки з вікна -------------------------------------------------------

func _stage() -> Array:
	var world := Node3D.new()
	add_child(world)
	var holder := WorldEnvironment.new()
	world.add_child(holder)
	var eye := Camera3D.new()
	eye.fov = 70
	eye.near = 0.05
	world.add_child(eye)
	eye.current = true
	# Ліхтар над місцем, куди дивимось, — як світло довкола гравця. Без
	# нього вид згори майже чорний (знімки 13.09.2026): свічки світять на
	# 5 м, а камера гри дивиться з 15.
	var lantern := OmniLight3D.new()
	lantern.name = "Ліхтар"
	lantern.light_color = Color(1.0, 0.9, 0.75)
	lantern.light_energy = 1.0
	lantern.omni_range = 9.0
	world.add_child(lantern)
	return [world, holder, eye, lantern]


func _raise(world: Node3D, holder: WorldEnvironment, i: int) -> DungeonView:
	var id: String = _ordered()[i]
	var plan := _book.make(id, _seed_of(i))
	var view := DungeonView.new()
	view.name = id
	world.add_child(view)
	var started := Time.get_ticks_msec()
	view.build(plan, _book.style_of(plan))
	holder.environment = DungeonView.environment(_book.style_of(plan))
	print("  %d · %s: 3D за %d мс · трикутників %d · світел %d · оздоби %d"
			% [i + 1, id, Time.get_ticks_msec() - started, view.triangles,
			   view.lights_made, view.props_made])
	# Налагодження вигляду: чорна грань — вивернута чи просто неосвітлена?
	# Двобічно — рушій малює й зворотний бік; без світла — колір текстури
	# як є, без жодної нормалі.
	var args := OS.get_cmdline_user_args()
	var both := args.has("--двобічно")
	var flat := args.has("--без-світла")
	if both or flat:
		for node in view.find_children("*", "GeometryInstance3D", true, false):
			var geo := node as GeometryInstance3D
			var m := geo.material_override as BaseMaterial3D
			if m == null:
				continue
			m = m.duplicate()
			if both:
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
			if flat:
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			geo.material_override = m
	return view


## Камера на шляху до боса: `at` — частка шляху, `mode` — з очей чи
## згори під 50°, як дивиться камера гри.
func _aim(eye: Camera3D, lantern: OmniLight3D, plan: DungeonPlan, at: float,
		mode: String) -> void:
	var path := plan.main_path
	if path.size() < 2:
		return
	var k := clampi(roundi((path.size() - 1) * at), 0, path.size() - 2)
	var here := plan.at(path[k])
	lantern.position = here + Vector3(0, 2.0, 0)
	if mode == "згори":
		eye.position = here + Vector3(0, 12, 10)
		eye.look_at(here)
		return
	var ahead := plan.at(path[mini(k + 7, path.size() - 1)])
	if mode == "бос":
		ahead = plan.at(plan.room_cell(plan.boss_room))
	eye.position = here + Vector3(0, 1.6, 0)
	var target := ahead + Vector3(0, 1.2, 0)
	if target.distance_to(eye.position) < 0.5:
		target = eye.position + Vector3(0, 0, -1)
	eye.look_at(target)


func _shots(into: String) -> void:
	get_window().size = Vector2i(1280, 720)
	var stage := _stage()
	var world: Node3D = stage[0]
	var holder: WorldEnvironment = stage[1]
	var eye: Camera3D = stage[2]
	var lantern: OmniLight3D = stage[3]
	print("\n— знімки —")
	var ids := _ordered()
	var only := _arg("--лише").split(",", false)
	for i in ids.size():
		if not only.is_empty() and not str(i + 1) in only:
			continue
		var view := _raise(world, holder, i)
		for take: Array in [["хід", 0.3, "очі"], ["глибше", 0.62, "очі"],
				["бос", 0.9, "бос"], ["згори", 0.5, "згори"]]:
			_aim(eye, lantern, view.plan, take[1], take[2])
			var started := Time.get_ticks_msec()
			for f in 40:
				await get_tree().process_frame
			var fps := 40000.0 / maxf(Time.get_ticks_msec() - started, 1)
			var img := get_viewport().get_texture().get_image()
			var file := into.path_join("%02d-%s-%s.jpg"
					% [i + 1, ids[i], take[0]])
			img.save_jpg(file, 0.88)
			print("    %s · %.0f кадрів/с" % [file.get_file(), fps])
		view.queue_free()
		await get_tree().process_frame
	world.queue_free()


# --- показ ----------------------------------------------------------------

func _interactive() -> void:
	var stage := _stage()
	var world: Node3D = stage[0]
	var holder: WorldEnvironment = stage[1]
	var eye: Camera3D = stage[2]
	var lantern: OmniLight3D = stage[3]
	var chosen := 0
	var view := _raise(world, holder, chosen)
	var mode := "очі"
	var along := 0.0
	var held := {}
	# Показ не мусить малювати більше, ніж видно оку.
	Engine.max_fps = 60
	var rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var since_report := 0.0
	print("\n  1…9, 0 — підземелля · Tab — прохід/згори · "
			+ "пробіл — знімок · Esc")
	get_tree().root.close_requested.connect(get_tree().quit)
	while true:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		since_report += dt
		if since_report >= 2.0:
			since_report = 0.0
			# Чесне число: скільки мс кадр справді коштує відеокарті й
			# процесору, а не «кадрів за секунду», що впираються в межу.
			var gpu := RenderingServer.viewport_get_measured_render_time_gpu(rid)
			var cpu := RenderingServer.viewport_get_measured_render_time_cpu(rid)
			print("  [кадр] %.0f к/с · відеокарта %.2f мс · процесор %.2f мс"
					% [Engine.get_frames_per_second(), gpu, cpu])
		if Input.is_key_pressed(KEY_ESCAPE):
			break
		for n in 10:
			var key: Key = KEY_0 + ((n + 1) % 10) as Key
			if _pressed(held, key) and n < _ordered().size() and n != chosen:
				chosen = n
				view.queue_free()
				view = _raise(world, holder, chosen)
				along = 0.0
		if _pressed(held, KEY_TAB):
			mode = "згори" if mode == "очі" else "очі"
		if _pressed(held, KEY_SPACE):
			Shot.take(world)
		var steps := maxi(view.plan.main_path.size(), 2)
		along = fmod(along + dt * 2.5 / float(steps), 1.0)
		_aim(eye, lantern, view.plan, along, mode)
	get_tree().quit()


func _pressed(held: Dictionary, key: Key) -> bool:
	var down := Input.is_key_pressed(key)
	var was: bool = held.get(key, false)
	held[key] = down
	return down and not was
