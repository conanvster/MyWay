extends SceneTree
## Проба станів монстра (П-297, 28.11.2026): удар не обривається ходою,
## варіант смерті сталий для особини, без власного `Run` — хода, як було,
## особини одного виду мають різний темп.
##     godot --headless --path game --script res://probes/monster_state.gd

const MODEL := "res://models/own/гнол-мисливець.glb"

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("  ✓ " if ok else "  ✗ ") + what)
	if not ok:
		_fails += 1


func _make() -> SkinnedModel:
	var m := SkinnedModel.new()
	m.path = MODEL
	root.add_child(m)
	m.build()
	return m


func _anim(m: SkinnedModel) -> String:
	var p: AnimationPlayer = m.find_children("*", "AnimationPlayer", true, false)[0]
	return p.current_animation


func _initialize() -> void:
	await process_frame
	var m := _make()
	await process_frame
	m.animate(0.0)
	_check(_anim(m).ends_with("Idle"), "стоїть — Idle (" + _anim(m) + ")")
	m.swing()
	_check(_anim(m).ends_with("Attack"), "удар — Attack (" + _anim(m) + ")")
	_check(m.is_busy(), "удар тримається")
	m.animate(0.0)
	m.animate(4.0)
	_check(_anim(m).ends_with("Attack"), "хода не обриває удар (" + _anim(m) + ")")
	var d1 := m.variant("Death", true)
	var same := true
	for i in 10:
		same = same and m.variant("Death", true) == d1
	_check(same, "смерть сталого варіанта (" + d1 + ")")
	await create_timer(2.0).timeout
	_check(not m.is_busy(), "після удару вільний")
	m.animate(4.5)
	_check(_anim(m).ends_with("Walk"), "без Run — хода (" + _anim(m) + ")")
	var tempos := {}
	for i in 6:
		var o := _make()
		await process_frame
		o.animate(0.0)
		tempos[snappedf(o.find_children("*", "AnimationPlayer", true, false)[0].speed_scale, 0.001)] = true
	_check(tempos.size() > 1, "різний темп особин (%d різних із 6)" % tempos.size())
	print("monster_state: ", "OK" if _fails == 0 else "ВАДИ %d" % _fails)
	quit(_fails)
