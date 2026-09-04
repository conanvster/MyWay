extends SceneTree
## Парад рухів моделі людини: по одній фігурі на кожен рух із бібліотеки
## (43 штуки, `UAL1_Standard.glb`) — кожна сама по колу грає СВІЙ рух і
## підписана його назвою. Той самий принцип, що й `parade.gd` для
## монстрів, тільки тут одиниця — рух, не вид.
##
## Ганяти так:
##     ./run.sh --рухи-людини
##
## Esc — вийти, пробіл — знімок, колесо миші — ближче/далі. Камера
## повільно облітає стрій; підписи не фіксованого розміру (як над
## монстрами в грі), а зменшуються з відстанню — інакше 43 підписи
## зливаються в кашу на загальному плані.

const AVATAR := preload("res://scenes/avatar.tscn")
const COLUMNS := 7
const STEP_X := 3.2
const STEP_Z := 4.2
const LABEL_HEIGHT := 2.15
const ZOOM_STEP := 2.0
const ZOOM_MIN := 6.0


## Колесо миші — подія, не стан; ловимо окремим вузлом (SceneTree сама
## `_unhandled_input` не має).
class InputCatcher extends Node:
	var zoom := 0.0

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				zoom -= ZOOM_STEP
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				zoom += ZOOM_STEP


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
	scout.apply_sex("чоловік")
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
		hero.apply_sex("чоловік")
		await process_frame
		var col := i % COLUMNS
		var row := i / COLUMNS
		var at := Vector3(from_x + col * STEP_X, 0.0, from_z + row * STEP_Z)
		hero.place_at(at, 0.0)

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
	# на весь стрій — увесь загальний план і так зливає підписи, ближче
	# скролом розжене.
	var radius: float = ZOOM_MIN + 8.0
	var height: float = radius * 0.55

	eye.position = Vector3(0, height, radius)
	eye.look_at(Vector3(0, 1.0, 0))
	for i in 8:
		await process_frame
	Shot.take(world)

	print("\n  Esc — вийти · пробіл — знімок · колесо — ближче/далі")
	print("  %d людей, кожна грає свій рух по колу" % lineup.size())
	root.close_requested.connect(quit)
	var angle := 0.0
	var shot_held := false
	while true:
		await process_frame
		if Input.is_key_pressed(KEY_ESCAPE):
			break
		if Input.is_key_pressed(KEY_SPACE):
			if not shot_held:
				Shot.take(world)
			shot_held = true
		else:
			shot_held = false
		if catcher.zoom != 0.0:
			radius = clampf(radius + catcher.zoom, ZOOM_MIN, full_radius * 1.6)
			height = radius * 0.55
			catcher.zoom = 0.0
		angle += 0.0025
		eye.position = Vector3(sin(angle) * radius, height,
				cos(angle) * radius)
		eye.look_at(Vector3(0, 1.0, 0))
	quit()
