extends SceneTree
## Смерть знімає стани, перенос — наміри (слово замовника 11.10.2026).
##
##     godot --headless --path game --script res://probes/forget.gd
##
## «Після смерті повинні зніматися бафи та дебафи, а після телепортації —
## цілевказівка останніх дій: бігти, бити». Числа, без мережі.

const AVATAR := preload("res://scenes/avatar.tscn")
var _bad := 0


func _expect(what: String, got: Variant, want: Variant) -> void:
	var ok: bool = got == want
	if not ok:
		_bad += 1
	print("  %s %s: %s%s" % ["✓" if ok else "✗", what, str(got),
			"" if ok else " (чекали %s)" % str(want)])


func _initialize() -> void:
	var a: Node = AVATAR.instantiate()
	root.add_child(a)
	await process_frame

	print("\n— смерть —")
	var base_speed: float = a.stats.move_speed()
	a.add_state(State.new("швидкість", "move_speed", 1.5, 60.0))
	a.add_state(State.new("отрута", "physical_attack", 0.8, 60.0))
	a.add_state(State.new("назавжди", "max_hp", 1.2, 0.0))
	_expect("до смерті станів", a.states.count(), 3)
	_expect("баф діє", is_equal_approx(a.stats.move_speed(), base_speed * 1.5),
			true)
	a.die()
	_expect("після смерті станів", a.states.count(), 0)
	_expect("швидкість без бафа", is_equal_approx(a.stats.move_speed(),
			base_speed), true)

	print("\n— перенос —")
	a.hp = 10
	a.queue.append("удар")
	a.wanted = Vector2(1, 0)
	a.target_id = -42
	a.place_at(Vector3(5, 1, 5), 0.0)
	_expect("виштовхування наміри не чіпає",
			[a.queue.size(), a.wanted, a.target_id], [1, Vector2(1, 0), -42])
	a.teleport_to(Vector3(100, 1, 100), 0.0)
	_expect("перенос: черга, напрямок, ціль",
			[a.queue.size(), a.wanted, a.target_id], [0, Vector2.ZERO, 0])
	_expect("і місце нове", a.global_position, Vector3(100, 1, 100))

	print("\nпомилок: %d" % _bad)
	quit(1 if _bad > 0 else 0)
