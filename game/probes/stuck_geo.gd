extends SceneTree
## Геометрія довкола точки застрягання: промені вниз і в 8 боків, чи
## перетинає капсула гравця колізію в цій точці.
##     godot --headless --path game --script res://probes/stuck_geo.gd -- \
##         <шаблон> <зерно> <святиня> <x> <y> <z>

const AVATAR := preload("res://scenes/avatar.tscn")


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var at := Vector3(float(a[3]), float(a[4]), float(a[5]))
	var dungeons := Dungeons.new()
	root.add_child(dungeons)
	await process_frame
	var key := Dungeons.key(int(a[2]), 0)
	dungeons.raise(key, a[0], int(a[1]), "E")
	var hero: CharacterBody3D = AVATAR.instantiate()
	root.add_child(hero)
	await physics_frame
	await physics_frame
	var space := hero.get_world_3d().direct_space_state
	var down := PhysicsRayQueryParameters3D.create(at + Vector3(0, 3, 0),
			at - Vector3(0, 5, 0), 1)
	var hit := space.intersect_ray(down)
	print("вниз з +3 м: ", hit.get("position", "нічого"), " нормаль ",
			hit.get("normal", ""))
	for h in [0.1, 0.5, 1.0, 1.6]:
		var row := "висота +%.1f:" % h
		for turn in 8:
			var d := Vector3.FORWARD.rotated(Vector3.UP, TAU * turn / 8.0)
			var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, h, 0),
					at + Vector3(0, h, 0) + d * 3.0, 1)
			q.hit_from_inside = true
			var r := space.intersect_ray(q)
			row += "  %s" % ("—" if r.is_empty() else "%.2f" % (
					(r["position"] - at - Vector3(0, h, 0)).length()))
		print(row)
	for child in hero.get_children():
		if child is CollisionShape3D:
			var p := PhysicsShapeQueryParameters3D.new()
			p.shape = child.shape
			p.collision_mask = 1
			p.transform = Transform3D(Basis(), at) * child.transform
			var inside := space.collide_shape(p, 8)
			print("капсула (", child.shape, ") перетинає світ у %d точках"
					% (inside.size() / 2))
			for i in range(0, inside.size(), 2):
				print("   ", inside[i] - at)
	quit()
