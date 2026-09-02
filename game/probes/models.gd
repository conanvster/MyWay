extends SceneTree
## Проба до моделей: що прийшло з наборів і чи є в них рухи.
##
## Ганяти так:
##     godot --headless --path game --script res://probes/models.gd

func _init() -> void:
	call_deferred("_go")

func _go() -> void:
	await process_frame
	print("\n— моделі істот —")
	for name in DirAccess.get_files_at("res://models/creatures"):
		if not (name.ends_with(".fbx") or name.ends_with(".glb")):
			continue
		var path := "res://models/creatures/" + name
		var scene: PackedScene = load(path)
		if scene == null:
			print("  %-22s НЕ ЗАВАНТАЖИЛАСЬ" % name)
			continue
		var body: Node3D = scene.instantiate()
		root.add_child(body)
		await process_frame
		var player: AnimationPlayer = body.find_child("AnimationPlayer", true, false)
		var bones := 0
		for child in body.find_children("*", "Skeleton3D", true, false):
			bones = child.get_bone_count()
			break
		var moves: Array = []
		if player != null:
			moves = Array(player.get_animation_list())
		print("  %-22s кісток %3d, рухів %d: %s"
				% [name, bones, moves.size(), ", ".join(moves.slice(0, 6))])
		body.queue_free()
	quit()
