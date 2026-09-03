extends SceneTree
## Проба до моделей: що прийшло з наборів і чи є в них рухи.
##
## Ганяти так:
##     godot --headless --path game --script res://probes/models.gd

const AVATAR := preload("res://scenes/avatar.tscn")

func _init() -> void:
	call_deferred("_go")

func _go() -> void:
	await process_frame
	await _player()
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


## Модель людини (П-150): Quaternius Base Characters + Animation Library,
## пересаджений `AnimationPlayer` (skinned_model.gd::_borrow_player) — тут
## і перевіряється, що пересадка й досі приживається, обома статями.
func _player() -> void:
	print("— модель гравця (П-150) —")
	for sex: String in ["чоловік", "жінка"]:
		var hero: Node3D = AVATAR.instantiate()
		root.add_child(hero)
		await process_frame
		hero.apply_sex(sex)
		await process_frame
		var body: Node3D = hero.model()
		var player: AnimationPlayer = null
		if body != null:
			player = body.find_child("AnimationPlayer", true, false)
		if player == null:
			print("  %-8s ‼ AnimationPlayer не знайдено" % sex)
			hero.queue_free()
			continue
		var moves := player.get_animation_list().size()
		body.animate(3.0)
		await process_frame
		await process_frame
		var walking: String = player.current_animation
		body.swing()
		await process_frame
		var swung: String = player.current_animation
		print("  %-8s рухів %d, ходьба: %s, удар: %s"
				% [sex, moves, walking, swung])
		hero.queue_free()
