extends SceneTree
## Парад рухів моделі людини: по одній фігурі на кожен рух із бібліотеки
## (43 штуки, `UAL1_Standard.glb`) — кожна сама по колу грає СВІЙ рух і
## підписана його назвою. Той самий принцип, що й `parade.gd` для
## монстрів, тільки тут одиниця — рух, не вид.
##
## Ганяти так:
##     ./run.sh --рухи-людини
##
## Інша модель на тому самому скелеті (аватар зі скану):
##     godot --path game --script res://probes/human_moves.gd -- \
##         --модель res://models/own/avatary/lyudyna-cholovik-z-nulia/людина.glb
##
## Esc — вийти, пробіл — знімок, колесо миші — ближче/далі (до 1,2 м),
## ліва чи права кнопка затиснута — крутити камеру й піднімати/опускати, ←/→ —
## наблизитись до однієї фігури (Home — увесь стрій), R — увімкнути чи
## спинити облітання (слово замовника 01.10.2026: «дуже швидко
## крутиться… немає змоги роздивитися модель, треба щоб можна було
## наблизити»). Облітання рахується за часом, не за кадрами: на сотнях
## кадрів без синхронізації воно інакше мчало. Камера облітає стрій; підписи не фіксованого розміру (як над
## монстрами в грі), а зменшуються з відстанню — інакше 43 підписи
## зливаються в кашу на загальному плані.

const AVATAR := preload("res://scenes/avatar.tscn")
const COLUMNS := 7
const STEP_X := 3.2
const STEP_Z := 4.2
const LABEL_HEIGHT := 2.15
const ZOOM_MIN := 1.2
## Колесо міняє відстань на частку від поточної — і впритул, і здалеку
## однаково плавно.
const ZOOM_SHARE := 0.12
## Облітання, радіан за секунду (повний оберт — ~50 с).
const SPIN := 0.12
## Права кнопка миші: радіан на піксель.
const DRAG := 0.006


## Колесо миші — подія, не стан; ловимо окремим вузлом (SceneTree сама
## `_unhandled_input` не має).
class InputCatcher extends Node:
	var zoom := 0.0
	var drag := Vector2.ZERO
	var step := 0          ## ←/→: −1/+1 до сусідньої фігури
	var whole := false     ## Home: увесь стрій
	var spin_toggle := false

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				zoom -= 1.0
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				zoom += 1.0
		elif event is InputEventMouseMotion and (event.button_mask
				& (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_LEFT)):
			drag += event.relative
		elif event is InputEventKey and event.pressed and not event.echo:
			match event.keycode:
				KEY_LEFT: step -= 1
				KEY_RIGHT: step += 1
				KEY_HOME: whole = true
				KEY_R: spin_toggle = true


## `--модель <res://…>` — показати рухи на іншій моделі з тим самим скелетом.
func _model() -> String:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--модель")
	return args[at + 1] if at >= 0 and at + 1 < args.size() else ""


func _place(eye: Camera3D, aim: Vector3, angle: float, pitch: float,
		radius: float) -> void:
	eye.position = aim + Vector3(sin(angle) * cos(pitch), sin(pitch),
			cos(angle) * cos(pitch)) * radius
	eye.look_at(aim)


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame

	var world := Node3D.new()
	root.add_child(world)

	var ground := MeshInstance3D.new()
	var plate := BoxMesh.new()
	plate.size = Vector3(COLUMNS * STEP_X + 6.0, 1, 40)
	ground.mesh = plate
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("#4a5c3a")
	ground.set_surface_override_material(0, paint)
	ground.position = Vector3(0, -0.5, 0)
	world.add_child(ground)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.light_energy = 1.2
	world.add_child(sun)

	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var air := Environment.new()
	air.background_mode = Environment.BG_SKY
	air.sky = sky
	air.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	air.ambient_light_energy = 1.2
	var holder := WorldEnvironment.new()
	holder.environment = air
	world.add_child(holder)

	# Перший, лише щоб дістати список рухів із його AnimationPlayer.
	var scout: Node3D = AVATAR.instantiate()
	world.add_child(scout)
	await process_frame
	scout.apply_sex("чоловік", "людина", _model())
	await process_frame
	var scout_body: Node3D = scout.model()
	var scout_player: AnimationPlayer = \
			scout_body.find_child("AnimationPlayer", true, false)
	var moves: Array = Array(scout_player.get_animation_list())
	moves.sort()
	scout.queue_free()
	await process_frame

	print("рухів у бібліотеці: %d" % moves.size())

	var rows := ceili(float(moves.size()) / COLUMNS)
	var from_x := -STEP_X * (COLUMNS - 1) * 0.5
	var from_z := -STEP_Z * (rows - 1) * 0.5

	var lineup: Array = []
	for i in moves.size():
		var name: String = moves[i]
		var hero: Node3D = AVATAR.instantiate()
		world.add_child(hero)
		await process_frame
		hero.apply_sex("чоловік", "людина", _model())
		await process_frame
		var col := i % COLUMNS
		var row := i / COLUMNS
		var at := Vector3(from_x + col * STEP_X, 0.0, from_z + row * STEP_Z)
		# Вузол аватара — центр капсули; модель зсунута вниз на
		# `foot_drop()`. Без підйому фігури стояли по пояс у землі.
		hero.place_at(at + Vector3(0, hero.foot_drop(), 0), 0.0)

		var body: Node3D = hero.model()
		var player: AnimationPlayer = null
		if body != null:
			player = body.find_child("AnimationPlayer", true, false)
		var has := player != null and player.has_animation(name)
		if has:
			player.get_animation(name).loop_mode = Animation.LOOP_LINEAR
			player.play(name)

		var tag := Label3D.new()
		tag.text = name
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.font_size = 40
		tag.outline_size = 12
		tag.outline_modulate = Color(0, 0, 0, 0.9)
		# НЕ fixed_size, навмисно: на нашпигу з 43 постатей однаковий
		# екранний розмір зливає всі підписи в кашу здалеку — звичайна
		# перспектива (менше далі) тут читається краще.
		tag.pixel_size = 0.0055
		tag.position = at + Vector3(0, LABEL_HEIGHT, 0)
		world.add_child(tag)

		print("  %-20s %s" % [name, "є" if has else "‼ немає AnimationPlayer"])

		lineup.append({"hero": hero, "name": name})

	var catcher := InputCatcher.new()
	world.add_child(catcher)

	var eye := Camera3D.new()
	eye.fov = 70
	world.add_child(eye)
	eye.current = true

	var full_radius: float = maxf(COLUMNS * STEP_X, rows * STEP_Z) * 0.9 + 10.0
	# Стартуємо БЛИЗЬКО (видно кілька перших постатей чітко), не одразу
	# на весь стрій.
	var radius: float = 14.0
	var pitch := 0.5            ## кут камери над обрієм, радіан
	var angle := 0.0
	var spinning := true
	var focus := -1             ## −1 — увесь стрій, інакше номер фігури
	var aim := Vector3(0, 1.0, 0)

	# Без лямбди: лямбда GDScript захоплює локальні змінні за значенням
	# у мить створення, і камера лишалась на першому місці назавжди
	# («вікно все ще без управління», 01.10.2026).
	_place(eye, aim, angle, pitch, radius)
	for i in 8:
		await process_frame
	Shot.take(world)

	print("\n  Esc — вийти · пробіл — знімок · колесо — ближче/далі · миша затиснута — крутити")
	print("  ←/→ — до фігури · Home — увесь стрій · R — облітання вкл/викл")
	print("  %d людей, кожна грає свій рух по колу" % lineup.size())
	root.close_requested.connect(quit)
	var shot_held := false
	var last := Time.get_ticks_msec()
	while true:
		await process_frame
		var now := Time.get_ticks_msec()
		var delta := (now - last) / 1000.0
		last = now
		if Input.is_key_pressed(KEY_ESCAPE):
			break
		if Input.is_key_pressed(KEY_SPACE):
			if not shot_held:
				Shot.take(world)
			shot_held = true
		else:
			shot_held = false
		if catcher.zoom != 0.0:
			radius = clampf(radius * (1.0 + ZOOM_SHARE * catcher.zoom),
					ZOOM_MIN, full_radius * 1.6)
			catcher.zoom = 0.0
		if catcher.drag != Vector2.ZERO:
			angle -= catcher.drag.x * DRAG
			pitch = clampf(pitch + catcher.drag.y * DRAG, -0.05, 1.45)
			catcher.drag = Vector2.ZERO
			spinning = false
		if catcher.spin_toggle:
			spinning = not spinning
			catcher.spin_toggle = false
		if catcher.step != 0:
			focus = posmod(focus + catcher.step, lineup.size()) \
					if focus >= 0 else (0 if catcher.step > 0 else lineup.size() - 1)
			catcher.step = 0
			radius = 3.2
			pitch = 0.25
			spinning = false
			print("  → %s" % lineup[focus]["name"])
		if catcher.whole:
			focus = -1
			radius = 14.0
			pitch = 0.5
			catcher.whole = false
		var target := Vector3(0, 1.0, 0)
		if focus >= 0:
			var hero: Node3D = lineup[focus]["hero"]
			target = Vector3(hero.global_position.x, 1.0, hero.global_position.z)
		aim = aim.lerp(target, minf(1.0, delta * 6.0))
		if spinning:
			angle += SPIN * delta
		_place(eye, aim, angle, pitch, radius)
	quit()
