extends SceneTree
## Куди дивиться зброя в кулаці (20.11.2026): напрям леза (+Y речі) і кромки (+X) відносно
## погляду персонажа, верху й правого боку — у спокої й у бойовій позі.
##     godot --headless --path game --script res://probes/zbroia_hvat.gd

const AVATAR := preload("res://scenes/avatar.tscn")


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	var hero: Node3D = AVATAR.instantiate()
	root.add_child(hero)
	await process_frame
	hero.appearance = Appearance.preset("людина", "чоловік", 1)
	hero.apply_sex("чоловік", "людина")
	await process_frame
	var goods := ItemBook.new()
	goods.load_from(JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json")))
	hero.wear({"зброя": "сталевий меч", "щит": "сталевий щит"}, goods)
	var skin: SkinnedModel = hero.model()
	var all_sk := skin.find_children("*", "Skeleton3D", true, false)
	print("скелетів: ", all_sk.size(), " ", all_sk.map(func(x): return str(x.get_path())))
	for mi: MeshInstance3D in skin.find_children("*", "MeshInstance3D", true, false):
		if mi.skin != null and str(mi.name).begins_with("Тіло"):
			print("тіло прив'язане до: ", mi.get_node(mi.skeleton).get_path())
	var skq: Skeleton3D = all_sk[0]
	var mod: Node = skq.get_node_or_null("Хват")
	print("модифікатор: ", mod, " фаланг: ", (mod.get("_curl") as Array).size() if mod else -1,
			" active=", mod.get("active") if mod else null)
	var tip := skq.find_bone("index_03_r")
	var hnd := skq.find_bone("hand_r")
	for on: bool in [true, false, true]:
		mod.set("active", on)
		for i in 5:
			await process_frame
		var d := skq.get_bone_global_pose(tip).origin.distance_to(skq.get_bone_global_pose(hnd).origin)
		var ln := skq.get_bone_global_rest(tip).origin.distance_to(skq.get_bone_global_rest(hnd).origin)
		print("викликів: ", mod.get("calls"))
		print("модифікатор %s: кінчик вказівного від кисті %.3f (у спокої %.3f)" % [on, d, ln])
	var ix := skq.find_bone("index_02_r")
	for i in 5:
		await process_frame
	print("index_02_r поворот (поза, після модифікатора?): ", skq.get_bone_pose_rotation(ix),
			" спокій: ", skq.get_bone_rest(ix).basis.get_rotation_quaternion())
	for ruh: String in ["Idle", "Sword_Idle"]:
		skin.show_move(ruh)
		for i in 30:
			await process_frame
		var held: Node3D = null
		for n in skin.find_children("Тримає-зброя", "", true, false):
			held = (n as Node3D).get_child(0)
		if held == null:
			print("немає зброї"); quit(1); return
		var b := held.global_transform.basis.orthonormalized()
		var hb := skin.global_transform.basis.orthonormalized()
		# погляд — від п'яти до пальців ноги (ball_r попереду foot_r), без висоти
		var sk: Skeleton3D = skin.find_children("*", "Skeleton3D", true, false)[0]
		var gt := sk.global_transform
		var foot := gt * sk.get_bone_global_pose(sk.find_bone("foot_r")).origin
		var ball := gt * sk.get_bone_global_pose(sk.find_bone("ball_r")).origin
		var up := Vector3.UP
		var fwd := (ball - foot); fwd.y = 0; fwd = fwd.normalized()
		var right := fwd.cross(up).normalized()
		print("%s: лезо → вперед %.2f, вгору %.2f, вправо %.2f; кромка → вперед %.2f, вгору %.2f, вправо %.2f"
				% [ruh, b.y.dot(fwd), b.y.dot(up), b.y.dot(right), b.x.dot(fwd), b.x.dot(up), b.x.dot(right)])
	quit(0)
