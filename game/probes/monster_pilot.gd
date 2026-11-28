extends SceneTree
## П-297 (28.11.2026): монстри з рухами — види, чия модель у mobs.json `models/own/<назва>.glb`
## (tools/monstr_v_hru.py). Чи гра бачить усі рухи, чи SkinnedModel грає біг, каст, влучання й
## варіанти смерті, зріст моделі.
##     godot --headless --path game --script res://probes/monster_pilot.gd

const DIR := "res://models/own/"
const MOVES := ["Idle", "Walk", "Run", "Attack", "Attack2", "Cast", "Hit", "Hit2", "Death", "Death2"]
var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("  ✓ " if ok else "  ✗ ") + what)
	if not ok:
		_fails += 1


func _initialize() -> void:
	await process_frame
	var mobs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/mobs.json"))
	var files := {}
	for k in mobs:
		var x = mobs[k]
		if x is Dictionary and x.has("вигляд") \
				and x["вигляд"].get("модель", "") == DIR + x["назва"] + ".glb":
			files[x["назва"] + ".glb"] = true
	for f in files:
		var m := SkinnedModel.new()
		m.path = DIR + f
		root.add_child(m)
		m.build()
		await process_frame
		# старі скани (до П-297) мають 3–4 рухи — їх не перевіряємо; нові завжди мають Death2
		if not m.has_move("Death2"):
			m.queue_free()
			continue
		print(f)
		var miss := []
		for mv in MOVES:
			if not m.has_move(mv):
				miss.append(mv)
		_check(miss.is_empty(), "усі 10 рухів" + ("" if miss.is_empty() else " — бракує " + str(miss)))
		var p: AnimationPlayer = m.find_children("*", "AnimationPlayer", true, false)[0]
		m.animate(5.0)
		_check(p.current_animation.ends_with("Run"), "женеться — Run (" + p.current_animation + ")")
		m.show_move("Cast")
		_check(p.current_animation.ends_with("Cast"), "каст — Cast")
		var hs := {}
		for i in 12:
			hs[m.variant("Hit")] = true
		_check(hs.size() == 2, "два варіанти влучання (%d)" % hs.size())
		var lo := INF
		var hi := -INF
		for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
			if mi.name.begins_with("Тримає-") or mi.get_parent().name.begins_with("Тримає-"):
				continue
			var b := mi.get_aabb()
			lo = minf(lo, b.position.y)
			hi = maxf(hi, b.end.y)
		print("  зріст сітки %.2f м" % (hi - lo))
		m.queue_free()
	print("monster_pilot: ", "OK" if _fails == 0 else "ВАДИ %d" % _fails)
	quit(_fails)
