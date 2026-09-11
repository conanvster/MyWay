extends SceneTree
## Показ рослин: усе, що є в наборі природи, в ряд і з підписами.
##
## Замовник сказав, що дерева виглядають непереконливо, і попросив
## пошукати природніші — разом із травою й кущами. Шукати не довелось:
## `Stylized Nature MegaKit` (Quaternius, CC0), з якого в грі стояло
## шість дерев, має двадцять дерев чотирьох родів, кущі, папороть,
## чотири трави, конюшину, квіти, гриби й камінці. Ця проба показує їх
## усі — щоб вибирати очима, а не за іменами файлів.
##
## Заразом друкує ЗМІРЯНУ висоту кожної моделі: без неї масштабування
## «під потрібну висоту» бреше, бо трава й дерево міряються по-різному.
##
## Ганяти так:
##     ./run.sh --рослини
##
## Пробіл — знімок, Esc — вийти.

const HERE := "res://models/nature/"

## Фотографічні хвойні: не моделі, а картинки з альфою на схрещених
## площинах. Показуємо їх першим рядом — саме про них ішлося.
const PHOTO := [
	["хвойні фото — літні", ["Conifer1", "Conifer4", "Conifer5",
			"Conifer6", "Conifer7"], 20.0],
	["хвойні фото — у снігу (лише крижана північ)",
			["Conifer2", "Conifer3"], 18.0],
	# Фотоскани Poly Haven, зняті збоку в картки (11.09.2026, слово
	# замовника «знайди більше дерев, і більших, і таких самих за
	# розміром, але більш різноманітних»).
	["скани: великі ялиці й сосни", ["Scan_fir_tree_01_a_0",
			"Scan_fir_tree_01_b_60", "Scan_fir_tree_01_c_120",
			"Scan_pine_tree_01_a_0", "Scan_pine_tree_01_b_60",
			"Scan_pine_tree_01_c_120"], 18.0],
	["скани: середні ялиці й сосни, листяне", ["Scan_fir_sapling_medium_a_0",
			"Scan_fir_sapling_medium_b_60", "Scan_fir_sapling_medium_c_120",
			"Scan_pine_sapling_medium_a_0", "Scan_pine_sapling_medium_b_60",
			"Scan_pine_sapling_medium_c_120", "Scan_tree_small_02_0"], 8.0],
	["сухі хвойні фото", ["ConiferDead1", "ConiferDead2", "ConiferDead3",
			"ConiferDead5", "ConiferDead6", "ConiferDead7",
			"ConiferDead8", "ConiferDead9"], 16.0],
]

const ROWS := [
	["дерева листяні", ["CommonTree_1", "CommonTree_2", "CommonTree_3",
			"CommonTree_4", "CommonTree_5"]],
	["сосни", ["Pine_1", "Pine_2", "Pine_3", "Pine_4", "Pine_5"]],
	["криві (гори, вітер)", ["TwistedTree_1", "TwistedTree_2",
			"TwistedTree_3", "TwistedTree_4", "TwistedTree_5"]],
	["сухі", ["DeadTree_1", "DeadTree_2", "DeadTree_3", "DeadTree_4",
			"DeadTree_5"]],
	["кущі й папороть", ["Bush_Common", "Bush_Common_Flowers", "Fern_1",
			"Plant_1_Big", "Plant_7_Big", "Plant_1", "Plant_7"]],
	["трава", ["Grass_Common_Short", "Grass_Common_Tall",
			"Grass_Wispy_Short", "Grass_Wispy_Tall", "Clover_1", "Clover_2"]],
	["квіти й гриби", ["Flower_3_Group", "Flower_4_Group",
			"Mushroom_Common"]],
	["каміння", ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3",
			"Pebble_Round_1", "Pebble_Round_2", "Pebble_Round_3"]],
]

## Крок між сусідами в ряду й між рядами, метрів.
const GAP := 7.0
const ROW_GAP := 11.0

var _eye: Camera3D
var _turn := 0.0
## Знімки роблю сам на цих секундах: щоб було що показати замовникові,
## не чекаючи, поки хтось натисне пробіл.
var _clock := 0.0
var _shots := [2.0, 12.0, 20.0, 30.0]


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	var page := Node3D.new()
	root.add_child(page)

	var air := WorldEnvironment.new()
	var sky := Environment.new()
	sky.background_mode = Environment.BG_SKY
	var made := Sky.new()
	made.sky_material = ProceduralSkyMaterial.new()
	sky.sky = made
	sky.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	sky.ambient_light_energy = 0.85
	air.environment = sky
	page.add_child(air)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = 1.0
	page.add_child(sun)

	# Земля: просто зелений майданчик, щоб було видно, де що стоїть.
	var floor_view := MeshInstance3D.new()
	var plate := PlaneMesh.new()
	plate.size = Vector2(220, 160)
	floor_view.mesh = plate
	var green := StandardMaterial3D.new()
	green.albedo_color = Color("#6f8a52")
	green.roughness = 1.0
	floor_view.set_surface_override_material(0, green)
	page.add_child(floor_view)

	var font := ThemeDB.fallback_font
	print("\n— фотографічні дерева (чотири трикутники на дерево) —")
	var z := -float(ROWS.size() + PHOTO.size()) * ROW_GAP * 0.5
	for row: Array in PHOTO:
		var names: Array = row[1]
		var tall: float = float(row[2])
		var x := -float(names.size() - 1) * GAP * 1.6 * 0.5
		print("  %s:" % row[0])
		for one: String in names:
			var cross := _photo_cross(one, tall)
			if cross == null:
				print("    ‼ немає %s" % one)
				x += GAP * 1.6
				continue
			cross.position = Vector3(x, 0, z)
			page.add_child(cross)
			print("    %-22s заввишки %.1f м" % [one, tall])
			var mark := Label3D.new()
			mark.text = one
			mark.font = font
			mark.font_size = 48
			mark.pixel_size = 0.006
			mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			mark.position = Vector3(x, tall + 1.2, z)
			mark.outline_size = 14
			page.add_child(mark)
			x += GAP * 1.6
		var head := Label3D.new()
		head.text = "◄ " + str(row[0])
		head.font = font
		head.font_size = 64
		head.pixel_size = 0.008
		head.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		head.position = Vector3(x + 4.0, 3.0, z)
		head.modulate = Color(1.0, 0.92, 0.6)
		head.outline_size = 16
		page.add_child(head)
		z += ROW_GAP * 2.2

	print("\n— що є в наборі природи —")
	for row: Array in ROWS:
		var names: Array = row[1]
		var x := -float(names.size() - 1) * GAP * 0.5
		print("  %s:" % row[0])
		for one: String in names:
			var path := HERE + one + ".gltf"
			if not ResourceLoader.exists(path):
				print("    ‼ немає %s" % path)
				x += GAP
				continue
			var model: Node3D = (load(path) as PackedScene).instantiate()
			model.position = Vector3(x, 0, z)
			page.add_child(model)
			var tall := _height_of(model)
			print("    %-22s заввишки %.2f м" % [one, tall])
			var sign := Label3D.new()
			sign.text = one
			sign.font = font
			sign.font_size = 48
			sign.pixel_size = 0.006
			sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sign.position = Vector3(x, maxf(tall, 0.6) + 0.7, z)
			sign.modulate = Color(1, 1, 1)
			sign.outline_size = 14
			page.add_child(sign)
			x += GAP
		var caption := Label3D.new()
		caption.text = "◄ " + str(row[0])
		caption.font = font
		caption.font_size = 64
		caption.pixel_size = 0.008
		caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		caption.position = Vector3(x + 3.0, 2.0, z)
		caption.modulate = Color(1.0, 0.92, 0.6)
		caption.outline_size = 16
		page.add_child(caption)
		z += ROW_GAP

	_eye = Camera3D.new()
	_eye.far = 500.0
	page.add_child(_eye)
	_eye.make_current()
	_place_eye()
	print("\n  камера обходить сама · пробіл — знімок · Esc — вийти")


## Хрест із двох площин під фотографію дерева — те саме, що робить
## `landscape.gd`, тільки без зіткнення: тут ми лише дивимось.
func _photo_cross(name_of: String, tall: float) -> Node3D:
	var path := "res://models/nature/photo/%s.png" % name_of
	var picture := Image.new()
	var raw := FileAccess.get_file_as_bytes(path)
	if not raw.is_empty():
		if picture.load_png_from_buffer(raw) != OK:
			return null
	else:
		raw = FileAccess.get_file_as_bytes(path.get_basename() + ".webp")
		if raw.is_empty() or picture.load_webp_from_buffer(raw) != OK:
			return null
	var wide: float = float(picture.get_width()) / float(picture.get_height())
	var paint := StandardMaterial3D.new()
	paint.albedo_texture = ImageTexture.create_from_image(picture)
	paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	paint.alpha_scissor_threshold = 0.45
	paint.cull_mode = BaseMaterial3D.CULL_DISABLED
	paint.roughness = 1.0
	paint.backlight_enabled = true
	paint.backlight = Color(0.16, 0.22, 0.12)
	paint.specular = 0.05
	# Меш будує сам краєвид — щоб показ і гра не розійшлися формою.
	var view := MeshInstance3D.new()
	view.mesh = Landscape._crown_mesh(wide)
	view.set_surface_override_material(0, paint)
	view.scale = Vector3(tall, tall, tall)
	return view


## Заміряна висота моделі: беремо всі меші й дивимось на верх коробки.
func _height_of(node: Node) -> float:
	var top := 0.0
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var view: MeshInstance3D = child
		if view.mesh == null:
			continue
		var box := view.mesh.get_aabb()
		top = maxf(top, (view.global_transform * box.position).y
				+ box.size.y * view.scale.y)
	return top


## Спершу обходимо весь показ, потім підходимо до фотографічних дерев —
## саме про них ішлося, і здалеку вони читаються силуетами.
func _place_eye() -> void:
	if _clock < 16.0:
		var far := 46.0
		_eye.position = Vector3(sin(_turn) * far, 16.0, cos(_turn) * far)
		_eye.look_at(Vector3(0, 3.0, 0), Vector3.UP)
		return
	var at := Vector3(0, 0, -float(ROWS.size() + PHOTO.size())
			* ROW_GAP * 0.5 - 4.0)
	_eye.position = at + Vector3(sin(_turn) * 34.0, 9.0, cos(_turn) * 34.0)
	_eye.look_at(at + Vector3(0, 9.0, 0), Vector3.UP)


func _process(delta: float) -> bool:
	if _eye != null:
		_turn += delta * 0.12
		_place_eye()
	_clock += delta
	if not _shots.is_empty() and _clock > float(_shots[0]):
		_shots.pop_front()
		Shot.take(root)
	if Input.is_key_pressed(KEY_ESCAPE):
		quit()
	if Input.is_key_pressed(KEY_SPACE):
		Shot.take(root)
	return false
