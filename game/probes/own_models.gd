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
	# Людиноподібні монстри — `.gltf` зі спільними текстурами в
	# `humanoids/` (19.09.2026).
	for folder in [DIR, DIR + "humanoids/"]:
		for name in DirAccess.get_files_at(folder):
			if not (name.ends_with(".glb") or name.ends_with(".gltf")):
				continue
			found += 1
			await _check(folder + name)
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
	var humanoid := path.contains("/humanoids/")
	# Смуга голови людиноподібних — від кістки голови на скелеті, а не від
	# висоти моделі: крила драконіда-вартового вищі за голову.
	var head_y := NAN
	var k := 1.0
	for sk: Skeleton3D in skin.find_children("*", "Skeleton3D", true, false):
		var at := sk.find_bone("Head")
		if at >= 0:
			head_y = (sk.global_transform * sk.get_bone_global_rest(at)).origin.y
			k = sk.global_transform.basis.get_scale().y
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
			# Людиноподібні (19.09.2026): крила, роги, корона й зброя теж
			# угорі — морду шукаємо у вузькій смузі по центру голови.
			if humanoid and not is_nan(head_y):
				if absf(w.x) > 0.035 * k or w.y < head_y - 0.02 * k \
						or w.y > head_y + 0.12 * k:
					continue
			elif w.y < low + (high - low) * 0.82:
				continue
			var off := Vector2(w.x, w.z).length()
			if off > far:
				far = off
				nose = w
	# Людська голова (зомбі, вампіри): потилиця майже так само далеко від
	# осі, як ніс, — тож беремо очі, вони лишаються окремим вузлом «Eyes».
	for eyes: MeshInstance3D in skin.find_children("Eyes*", "MeshInstance3D",
			true, false):
		nose = eyes.global_transform * eyes.mesh.get_aabb().get_center()
	# Звірі й змії (19.09.2026): у скелеті є кістка «head» — перед там,
	# де вона відносно середини скелета. Пошук морди по сітці ламався на
	# зміях: низьке довге тіло, розтягнуте до 1,6 м заввишки.
	if not humanoid:
		for sk: Skeleton3D in skin.find_children("*", "Skeleton3D", true,
				false):
			var at := sk.find_bone("head")
			if at < 0:
				continue
			var middle := Vector3.ZERO
			for b in sk.get_bone_count():
				middle += (sk.global_transform
						* sk.get_bone_global_pose(b)).origin
			middle /= sk.get_bone_count()
			var off: Vector3 = (sk.global_transform
					* sk.get_bone_global_pose(at)).origin \
					- Vector3(middle.x, 0.0, middle.z)
			# Двонога заготовка: голова рівно над серединою — тоді лишається
			# пошук морди по сітці.
			if absf(off.z) > 0.05:
				nose = off
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
