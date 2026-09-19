extends SceneTree
## Власні моделі замовника з Blender (`models/own/`): чи підхопить їх гра.
##
## Для кожного .glb: чи є рухи, яких шукає гра (Idle, Walk або Run,
## Attack; Death — бажано), чи стоїть ногами на землі й чи дивиться
## ВПЕРЕД (−Z), а не задом. Перед — за найдальшою від осі точкою на
## висоті голови: у заготовці це ніс; на своїй моделі тримай морду
## спереду, і проба скаже правду.
##
## Ганяти так:
##     godot --headless --path game --script res://probes/own_models.gd

const DIR := "res://models/own/"
const MOB := preload("res://scenes/mob.tscn")

var _bad := 0


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	print("\n— власні моделі (%s) —" % DIR)
	var found := 0
	for name in DirAccess.get_files_at(DIR):
		if not name.ends_with(".glb"):
			continue
		found += 1
		await _check(DIR + name)
	if found == 0:
		print("  моделей немає — поклади .glb у game/models/own/")
	print("  підсумок: %s" % ("усе гаразд" if _bad == 0
			else "‼ вад: %d" % _bad))
	quit(1 if _bad > 0 else 0)


func _check(path: String) -> void:
	var skin := SkinnedModel.new()
	skin.path = path
	skin.height = 1.6
	root.add_child(skin)
	skin.build()
	await process_frame
	var player: AnimationPlayer = skin.find_child("AnimationPlayer", true,
			false)
	var moves: Array = []
	if player != null:
		moves = Array(player.get_animation_list())
	var walk: bool = moves.has("Walk") or moves.has("Run")
	var need_ok: bool = moves.has("Idle") and walk and moves.has("Attack")
	if not need_ok:
		_bad += 1
	print("  %s %s · рухи: %s%s" % ["✓" if need_ok else "✗",
			path.get_file(), ", ".join(moves),
			"" if moves.has("Death") else " (без Death — труп ляже боком)"])

	var low := INF
	var high := -INF
	var nose := Vector3.ZERO
	var far := -1.0
	for mesh: MeshInstance3D in skin.find_children("*", "MeshInstance3D",
			true, false):
		var box: AABB = mesh.global_transform * mesh.mesh.get_aabb()
		low = minf(low, box.position.y)
		high = maxf(high, box.end.y)
	for mesh: MeshInstance3D in skin.find_children("*", "MeshInstance3D",
			true, false):
		var faces := mesh.mesh.get_faces()
		for v: Vector3 in faces:
			var w := mesh.global_transform * v
			if w.y < low + (high - low) * 0.82:
				continue
			var off := Vector2(w.x, w.z).length()
			if off > far:
				far = off
				nose = w
	var standing := absf(low) < 0.03
	var ahead := nose.z < 0.0
	if not standing:
		_bad += 1
	if not ahead:
		_bad += 1
	print("    %s зріст %.2f м, низ %.3f · %s морда на z %.2f — %s"
			% ["✓" if standing else "✗", high - low, low,
			   "✓" if ahead else "✗", nose.z,
			   "дивиться вперед" if ahead else "‼ дивиться НАЗАД"])
	skin.queue_free()
