extends SceneTree
## Людина, ельф, орк обох статей (19.09.2026): чи прижились на них рухи
## людини, чи стоять на землі, чи дивляться вперед і чи вдягнені.
##
## «Рухи прижились» — не «є в списку», а «кістки справді рушили»:
## пересадка (`skinned_model.gd:_borrow_player`) тихо не рухає нічого,
## якщо шлях до скелета в новому файлі інший.
##
## Ганяти так:
##     godot --headless --path game --script res://probes/races.gd

const AVATAR := preload("res://scenes/avatar.tscn")

var _bad := 0


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	var floor := StaticBody3D.new()
	var plane := CollisionShape3D.new()
	plane.shape = WorldBoundaryShape3D.new()
	floor.add_child(plane)
	root.add_child(floor)
	print("\n— раси й одяг —")
	for race: String in ["людина", "ельф", "орк"]:
		for sex: String in ["чоловік", "жінка"]:
			await _check(race, sex)
	print("  підсумок: %s" % ("усе гаразд" if _bad == 0
			else "‼ вад: %d" % _bad))
	quit(1 if _bad > 0 else 0)


func _check(race: String, sex: String) -> void:
	var hero: Node3D = AVATAR.instantiate()
	root.add_child(hero)
	await process_frame
	hero.apply_sex(sex, race)
	hero.place_at(Vector3(0, 2.0, 0), 0.0)
	for i in 120:
		await physics_frame
		hero.server_step(1.0 / 60.0)
	var skin: SkinnedModel = hero.model()
	var problems: Array[String] = []
	if skin == null or not skin.path.begins_with(SkinnedModel.OWN_DIR):
		problems.append("не своя модель: %s"
				% (skin.path if skin != null else "—"))
		_report(race, sex, problems, 0, 0.0)
		hero.queue_free()
		return
	var player: AnimationPlayer = skin.find_child("AnimationPlayer", true,
			false)
	var moves := player.get_animation_list().size() if player != null else 0
	var skel: Skeleton3D = null
	for s in skin.find_children("*", "Skeleton3D", true, false):
		skel = s
		break
	var thigh := skel.find_bone("thigh_l") if skel != null else -1
	var before := skel.get_bone_pose_rotation(thigh) if thigh >= 0 \
			else Quaternion()
	skin.animate(3.0)
	for i in 20:
		await process_frame
	var after := skel.get_bone_pose_rotation(thigh) if thigh >= 0 \
			else Quaternion()
	var moved := before.angle_to(after)
	if moves < 40:
		problems.append("рухів лише %d" % moves)
	if moved < 0.05:
		problems.append("ходьба не рушить ногу (%.3f рад)" % moved)
	var clothes := 0
	for mesh: MeshInstance3D in skin.find_children("*", "MeshInstance3D",
			true, false):
		if mesh.name.begins_with("Одяг"):
			clothes += 1
	if clothes < 4:
		problems.append("одягу %d речей з 4" % clothes)
	skin.animate(0.0)
	for i in 30:
		await process_frame
	var low := INF
	var tall := -INF
	for mesh: MeshInstance3D in skin.find_children("*", "MeshInstance3D",
			true, false):
		var box: AABB = mesh.global_transform * mesh.mesh.get_aabb()
		low = minf(low, box.position.y)
		tall = maxf(tall, box.end.y)
	if absf(low - 0.0) > 0.08:
		problems.append("низ моделі на %.2f м" % low)
	_report(race, sex, problems, moves, moved, tall - low)
	hero.queue_free()


func _report(race: String, sex: String, problems: Array[String],
		moves: int, moved: float, tall: float = 0.0) -> void:
	if not problems.is_empty():
		_bad += 1
	print("  %s %-7s %-8s рухів %d, нога в ході %.2f рад, зріст %.2f м%s"
			% ["✓" if problems.is_empty() else "✗", race, sex, moves, moved,
			   tall, "" if problems.is_empty()
					else " — ‼ " + "; ".join(problems)])
