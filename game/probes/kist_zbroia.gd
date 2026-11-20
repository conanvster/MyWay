extends SceneTree
## Проба (20.11.2026): де кулак сітки, де кістка кисті і де руків'я — для кожної раси.
##     godot --headless --path game --script res://probes/kist_zbroia.gd
const AVATAR := preload("res://scenes/avatar.tscn")

func _init() -> void:
	call_deferred("_go")

func _go() -> void:
	await process_frame
	for rs: Array in [["орк", "чоловік"], ["людина", "чоловік"], ["людина", "жінка"],
			["ельф", "чоловік"], ["ельф", "жінка"], ["орк", "жінка"]]:
		var hero: Node3D = AVATAR.instantiate()
		root.add_child(hero)
		await process_frame
		hero.appearance = Appearance.preset(rs[0], rs[1], 1)
		hero.apply_sex(rs[1], rs[0])
		await process_frame
		var goods := ItemBook.new()
		goods.load_from(JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json")))
		hero.wear({"зброя": "сталева сокира"}, goods)
		for i in 20:
			await process_frame
		var skin: SkinnedModel = hero.model()
		var sk: Skeleton3D = skin.find_children("*", "Skeleton3D", true, false)[0]
		var hb := sk.find_bone("hand_r")
		var hand := sk.global_transform * sk.get_bone_global_pose(hb).origin
		var held: Node3D = null
		for n: Node in skin.find_children("Тримає-*", "", true, false):
			held = n
		var heldp: Vector3 = (held.get_child(0) as Node3D).global_position if held and held.get_child_count() > 0 else Vector3.INF
		var fist := _palec(skin, sk)
		var cnt := 1 if fist != Vector3.ZERO else 0
		print("%s-%s: кисть %s; середній палець сітки %s (%d верш.); руків'я %s; від пальця до руків'я %.3f м; модель %s" % [rs[0], rs[1],
				hand, fist, cnt, heldp, fist.distance_to(heldp), skin.path.get_file()])
		hero.queue_free()
		await process_frame
	quit()


## Середина вершин тіла з вагою > 0,5 на middle_02_r, поскінена вручну.
func _palec(skin: Node, sk: Skeleton3D) -> Vector3:
	var b := sk.find_bone("hand_r")
	var sum := Vector3.ZERO
	var cnt := 0
	for mi: MeshInstance3D in skin.find_children("*", "MeshInstance3D", true, false):
		if mi.skin == null:
			continue
		var mid := -1
		for i in mi.skin.get_bind_count():
			var bn := mi.skin.get_bind_name(i)
			if bn == "" and mi.skin.get_bind_bone(i) >= 0:
				bn = sk.get_bone_name(mi.skin.get_bind_bone(i))
			if bn == "hand_r":
				mid = i
		if mid == -1:
			continue
		for si in mi.mesh.get_surface_count():
			var a := mi.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			if a[Mesh.ARRAY_BONES] == null or vs.is_empty():
				continue
			var bs: PackedInt32Array = a[Mesh.ARRAY_BONES]
			var ws: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
			var per := bs.size() / vs.size()
			for v in vs.size():
				for k in per:
					if bs[v * per + k] == mid and ws[v * per + k] > 0.5:
						sum += sk.global_transform * (sk.get_bone_global_pose(b)
								* mi.skin.get_bind_pose(mid) * vs[v])
						cnt += 1
	return sum / cnt if cnt > 0 else Vector3.ZERO
