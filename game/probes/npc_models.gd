extends SceneTree
## Моделі NPC ремесел (28.11.2026, tools/npc_3d.sh): для кожного ремесла з
## map.json і обох статей — шлях `Landscape.npc_model`, файл є, SkinnedModel
## збирає його зі скелетом і грає Idle_Talking, зріст як заданий.
##
##     godot --headless --path game --script res://probes/npc_models.gd

const CRAFTS := ["коваль", "крамар", "крамарка", "священик", "вартовий",
		"гільдмайстер", "завідувач складу", "майстер магії"]


func _init() -> void:
	var bad := 0
	var root := Node3D.new()
	get_root().add_child.call_deferred(root)
	await process_frame
	for craft: String in CRAFTS:
		for female: bool in [false, true]:
			var p: String = Landscape.npc_model(craft, female)
			var tag := "%s/%s" % [craft, "жінка" if female else "чоловік"]
			if not ResourceLoader.exists(p):
				print("‼ ", tag, ": немає ", p)
				bad += 1
				continue
			var m := SkinnedModel.new()
			m.path = p
			m.anim_path = "res://models/player/animations/UAL1_Standard.glb"
			m.height = 1.68 if female else 1.75
			root.add_child(m)
			m.build()
			m.show_move("Idle_Talking")
			await process_frame
			var sk: Skeleton3D = m.find_child("*Skeleton3D*", true, false)
			if sk == null:
				for c in m.find_children("*", "Skeleton3D", true, false):
					sk = c
			var ap: AnimationPlayer = m.find_child("AnimationPlayer", true, false)
			var ok := sk != null and ap != null and ap.has_animation("Idle_Talking")
			print("%s %s: кісток %d, Idle_Talking %s" % ["✓" if ok else "‼", tag,
					sk.get_bone_count() if sk else 0, ap != null and ap.has_animation("Idle_Talking")])
			if not ok:
				bad += 1
			m.queue_free()
	print("NPC-моделі: %s" % ("усі ✓" if bad == 0 else "‼ вад %d" % bad))
	quit(1 if bad else 0)
