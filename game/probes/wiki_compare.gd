extends SceneTree
## Вікі поруч із грою (07.11.2026): кожен скан у кожному варіанті — знімок
## у три чверті, як кадри `wiki/img/rasy/<тип>-v<n>.png`, і поряд сам кадр.
##
##     godot --path game --script res://probes/wiki_compare.gd -- <тека>
##
## Аркуш `<тека>/<тип>.png`: угорі кадри вікі, внизу гра. Потрібен, щоб
## замовник показав, ЩО саме «далеко від рендеру».

const WIKI := "res://../wiki/img/rasy/%s-v%d.png"
var _dir := "user://вікі-поруч"


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_dir = args[0]
	DirAccess.make_dir_recursive_absolute(_dir)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var stage := Node3D.new()
	root.add_child(stage)
	var sky := WorldEnvironment.new()
	sky.environment = Environment.new()
	sky.environment.background_mode = Environment.BG_COLOR
	sky.environment.background_color = Color(0.42, 0.45, 0.47)
	sky.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	sky.environment.ambient_light_color = Color(0.6, 0.62, 0.65)
	sky.environment.ambient_light_energy = 0.6
	sky.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	stage.add_child(sky)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 35, 0)
	sun.light_energy = 1.0
	stage.add_child(sun)
	var eye := Camera3D.new()
	eye.fov = 26.0
	stage.add_child(eye)
	eye.make_current()
	root.size = Vector2i(560, 820)
	for kind: String in Appearance.SCANS:
		var parts := kind.split("-")
		var shots: Array[Image] = []
		for v in range(1, Appearance.VARIANTS + 1):
			var m := SkinnedModel.new()
			m.path = Appearance.model_of(parts[0], parts[1], v)
			m.anim_path = preload("res://scripts/avatar.gd").MODEL_ANIM
			m.height = float(preload("res://scripts/avatar.gd").RACE_HEIGHT
					.get(parts[0], 1.75))
			stage.add_child(m)
			m.build()
			m.customize(Appearance.to_look(Appearance.preset(parts[0], parts[1], v)))
			# три чверті, трохи збоку, як у вікі
			m.rotation.y = deg_to_rad(205.0)
			var tall := m.height
			eye.look_at_from_position(Vector3(0.0, tall * 0.55, tall * 2.9),
					Vector3(0.0, tall * 0.5, 0.0), Vector3.UP)
			for i in 15:
				await process_frame
			await RenderingServer.frame_post_draw
			shots.append(root.get_texture().get_image())
			m.queue_free()
			await process_frame
		_sheet(kind, shots)
	print("готово: %s" % ProjectSettings.globalize_path(_dir))
	quit()


func _sheet(kind: String, shots: Array[Image]) -> void:
	var cell := Vector2i(400, 586)
	var sheet := Image.create(cell.x * 3, cell.y * 2, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.1, 0.1, 0.12))
	for v in 3:
		var wiki_path := ProjectSettings.globalize_path("res://").path_join(
				"../wiki/img/rasy/%s-v%d.png" % [kind, v + 1])
		var wiki := Image.load_from_file(wiki_path)
		if wiki != null:
			# кадр 1024² — фігура посередині: вирізати смугу під клітинку
			var w := int(1024.0 * float(cell.x) / float(cell.y))
			wiki = wiki.get_region(Rect2i((1024 - w) / 2, 0, w, 1024))
			wiki.resize(cell.x, cell.y)
			wiki.convert(Image.FORMAT_RGB8)
			sheet.blit_rect(wiki, Rect2i(Vector2i.ZERO, cell), Vector2i(v * cell.x, 0))
		var game := shots[v]
		game.convert(Image.FORMAT_RGB8)
		game.resize(cell.x, cell.y)
		sheet.blit_rect(game, Rect2i(Vector2i.ZERO, cell), Vector2i(v * cell.x,
				cell.y))
	sheet.save_png("%s/%s.png" % [_dir, kind])
