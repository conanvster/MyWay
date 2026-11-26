extends Node
## Зміна доби (П-274): та сама місцина світу 2 о восьмій порі.
##
##     ./run.sh --доба [тека] [--вулиця]
##
## `--вулиця` — не з висоти на місто, а з вулиці перед дверима дому з
## ліхтарем: видно скло вікон і ліхтар уночі (план §4.3).
##
## Знімки `<тека>/<година>-<пора>.png` і аркуш у журнал: сила сонця,
## місяць, зорі, світлячки — щоб перевірити не лише на око.

const MAIN := preload("res://scenes/main.tscn")
const MAP2 := "res://data/map2.json"
const HOURS := [0.5, 4.8, 6.5, 8.5, 12.0, 17.0, 19.0, 20.5]

var _dir := "user://доба"
var _bad := 0


func _ready() -> void:
	get_tree().create_timer(900.0).timeout.connect(func() -> void:
		print("‼ проба не скінчилась за 15 хв")
		get_tree().quit(1))
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and not args[0].begins_with("--"):
		_dir = args[0]
	DirAccess.make_dir_recursive_absolute(_dir)
	call_deferred("_go")


func _expect(what: String, ok: bool) -> void:
	if not ok:
		_bad += 1
	print("  %s %s" % ["✓" if ok else "✗", what])


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
	for old in land.find_children("Небо", "WorldEnvironment", false, false):
		old.free()
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAP2))
	land.build(map, true)
	land.fog_to_vision(140.0)
	if world.day != null:
		world.day.queue_free()
	var day := DayCycle.new()
	world.add_child(day)
	day.setup(land, world.get_node("Light") as DirectionalLight3D)
	var town: Dictionary = map["міста"][0]
	var mid: Array = town["центр"]
	var at := Vector3(float(mid[0]) + 60.0, 0.0, float(mid[2]) + 90.0)
	at.y = land.height_at(at.x, at.z) + 12.0
	var look := Vector3(float(mid[0]), land.height_at(float(mid[0]),
			float(mid[2])) + 6.0, float(mid[2]))
	if "--вулиця" in OS.get_cmdline_user_args():
		for house: Dictionary in town["будинки"]:
			if house.has("вид") or bool(house.get("відкрито", false)) \
					or bool(house.get("без дверей", false)) \
					or absi(hash(house["де"]) >> 7) % 2 != 0:
				continue
			var p: Array = house["де"]
			var turn := deg_to_rad(float(house.get("поворот", 0.0)))
			var front := Vector3(sin(turn), 0, cos(turn))
			var deep := float(house["модулі"][1]) * TownLook.MODULE * 0.5
			var door := Vector3(float(p[0]), 0, float(p[2])) + front * deep
			door.y = land.surface_y(door.x, door.z)
			look = door + Vector3(0, 1.8, 0)
			at = door + front * 5.0 + front.cross(Vector3.UP) * 2.0
			at.y = land.surface_y(at.x, at.z) + 1.9
			print("  дім з ліхтарем: %s, поворот %s"
					% [p, house.get("поворот")])
			break
	var eye := Camera3D.new()
	eye.far = 1200.0
	eye.fov = 62.0
	get_tree().root.add_child(eye)
	eye.make_current()
	eye.look_at_from_position(at, look, Vector3.UP)
	land.stream_to(at)
	day.follow(at + (look - at) * 0.3)
	var seen := {}
	for h: float in HOURS:
		day.fixed_hour = h
		day.apply(h)
		for i in 10:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var name := "%04.1f-%s" % [h, day.part_now]
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_dir,
				name])
		var sun: DirectionalLight3D = world.get_node("Light")
		print("  %s · сонце %.2f · місяць %.2f · зорі %.2f · світлячки %s · %s"
				% [name, sun.light_energy, day.moon.light_energy,
				day._sky.sky_cover_modulate.a, day._flies.emitting,
				day.clock_text()])
		seen[day.part_now] = true
		if h == 12.0:
			_expect("опівдні — денний вигляд світу без змін",
					is_equal_approx(sun.light_energy, float(day._base["сила сонця"]))
					and day._air.ambient_light_color.is_equal_approx(
					day._base["довкілля"]))
		if h == 0.5:
			_expect("уночі сонця немає, є місяць і зорі", sun.light_energy < 0.01
					and day.moon.light_energy > 0.2
					and day._sky.sky_cover_modulate.a > 0.8)
	_expect("усі чотири пори: %s" % [seen.keys()], seen.size() == 4)
	day.fixed_hour = NAN
	var a := day.hour()
	_expect("годинник іде: %.3f" % a, a >= 0.0 and a < 24.0)
	print("\nзнімки: %s\nпомилок: %d" % [ProjectSettings.globalize_path(_dir),
			_bad])
	get_tree().quit(1 if _bad > 0 else 0)
