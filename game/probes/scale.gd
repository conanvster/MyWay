extends SceneTree
## Скільки землі витягує рушій: ціна побудови й памʼять за стороною світу.
##
## Питання, на яке ця проба відповідає: у якому масштабі можна класти
## згенеровану карту (5632 px) у гру. Число тут заміряне, не оцінене
## на око — принцип P2.
##
## Ганяти так:
##     godot --headless --path game --script res://probes/scale.gd

const MAIN := preload("res://scenes/main.tscn")

## сторона, метрів · крок сітки, метрів
const CASES := [
	[600, 4], [1200, 4], [1408, 4], [2400, 4], [2816, 4],
	[2816, 8], [5632, 8], [5632, 16],
]


func _init() -> void:
	call_deferred("_go")


func _rss_mib() -> float:
	var f := FileAccess.open("/proc/self/statm", FileAccess.READ)
	if f == null:
		return -1.0
	var parts := f.get_line().split(" ")
	return float(parts[1]) * 4096.0 / 1048576.0 if parts.size() > 1 else -1.0


func _go() -> void:
	await process_frame
	print("\n— ціна землі за стороною —")
	print("  %-8s %-6s %-9s %-8s %-9s %s"
			% ["сторона", "крок", "точок", "мс", "памʼять", "трикутників"])
	var before := _rss_mib()
	for case: Array in CASES:
		var side: int = case[0]
		var step: int = case[1]
		# Світ-клієнт сам стукає на 127.0.0.1, а там може саме йти
		# гра замовника (19.09.2026: проба під'єдналась до живого
		# сервера світу 2 й перезапускалась по колу). «Уже в мережі» —
		# і `Net.join()` нічого не робить.
		var net: Node = root.get_node_or_null("Net")
		if net != null:
			net.joined = true
		var world: Node3D = MAIN.instantiate()
		root.add_child(world)
		await process_frame
		var land: Node = world.get_node("Landscape")
		var data := {
			"земля": {"сторона": side, "крок": step, "колір": "#5c8a42",
					"розмах": 7.0, "частота": 0.012, "поле": 14},
			"море": {"рівень": 0.0, "колір": "#25506b"},
		}
		var started := Time.get_ticks_usec()
		land.build(data)
		var spent := (Time.get_ticks_usec() - started) / 1000.0
		await process_frame
		var points := int(side / step) + 1
		var body: Node = land.get_node_or_null("Земля")
		var tris := 0
		if body != null:
			for child in body.get_children():
				if child is MeshInstance3D:
					var mesh: Mesh = (child as MeshInstance3D).mesh
					if mesh != null and mesh.get_surface_count() > 0:
						tris += mesh.get_faces().size() / 3
		print("  %-8d %-6d %-9d %-8.0f %-9.0f %d"
				% [side, step, points * points, spent, _rss_mib(), tris])
		world.queue_free()
		await process_frame
		await process_frame
	print("  памʼять до першої побудови: %.0f МіБ" % before)
	quit()
