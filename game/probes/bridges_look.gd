extends Node
## Мости світу 2 — кандидати на вибір замовника (П-174, слово 06.11.2026:
## «для кожного переходу я б хотів обирати вручну дизайни мостів»).
##
##     ./run.sh --мости [тека]
##
## На кожен із 6 переходів — кожен дизайн `BridgeLook.DESIGNS` у справжньому
## світі, знімок збоку з берега: `<тека>/міст-<n>-<дизайн>.png`, і аркуш
## на перехід. Вибір пишеться в `data/svit2/мости-вибір.json`.

const MAIN := preload("res://scenes/main.tscn")
const MAP2 := "res://data/map2.json"

var _dir := "user://мости"


func _ready() -> void:
	get_tree().create_timer(900.0).timeout.connect(func() -> void:
		print("‼ проба не скінчилась за 15 хв")
		get_tree().quit(1))
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and not args[0].begins_with("--"):
		_dir = args[0]
	DirAccess.make_dir_recursive_absolute(_dir)
	call_deferred("_go")


func _go() -> void:
	await get_tree().process_frame
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var net: Node = get_tree().root.get_node_or_null("Net")
	if net != null:
		net.joined = true
	var world: Node3D = MAIN.instantiate()
	get_tree().root.add_child(world)
	await get_tree().process_frame
	var land: Landscape = world.get_node("Landscape")
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAP2))
	land.build(map, true)
	land.fog_to_vision(120.0)
	var eye := Camera3D.new()
	eye.far = 900.0
	eye.fov = 55.0
	get_tree().root.add_child(eye)
	eye.make_current()
	var count: int = map.get("мости", []).size()
	# `--лише 0,1` — лише ці переходи; `--старі` — лише старіші дизайни.
	var args := OS.get_cmdline_user_args()
	var only: Array = []
	if args.find("--лише") >= 0 and args.find("--лише") + 1 < args.size():
		for n: String in args[args.find("--лише") + 1].split(","):
			only.append(int(n))
	var designs: Array = BridgeLook.OLD_DESIGNS if args.has("--старі") \
			else BridgeLook.DESIGNS
	for i in count:
		if not only.is_empty() and not i in only:
			continue
		var span := BridgeLook.span_of(land, i, "арка")
		if span.is_empty():
			print("[міст] %d — перетину немає" % i)
			continue
		var at: Vector2 = span["де"]
		var along: Vector2 = span["уздовж"]
		var side := Vector2(-along.y, along.x)
		var mid := Vector3(at.x, (float(span["висота_а"])
				+ float(span["висота_б"])) * 0.5, at.y)
		print("[міст] %d · ширина річки %.1f м · проліт %.1f м · береги %.1f / "
				% [i, span["ширина"], span["довжина"], span["висота_а"]]
				+ "%.1f м · вода %.1f м" % [span["висота_б"], span["вода"]])
		for design: String in designs:
			BridgeLook.build_one(land, i, design)
			var from := mid + Vector3(side.x, 0, side.y) * 15.0 \
					- Vector3(along.x, 0, along.y) * 6.0 + Vector3.UP * 4.0
			from.y = maxf(from.y, land.surface_y(from.x, from.z) + 2.5)
			eye.position = from
			eye.look_at(mid + Vector3.DOWN * 1.0)
			land.stream_to(eye.position)
			for f in 25:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var path := "%s/міст-%d-%s.png" % [_dir, i, design]
			get_viewport().get_texture().get_image().save_png(path)
	print("[мости] знімки: %s" % _dir)
	get_tree().quit()
