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
