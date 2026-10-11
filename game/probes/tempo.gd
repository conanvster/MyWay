extends Node
## Темп рухів людини від бафів (слово замовника 11.10.2026: «маю баф на
## швидкість бігу та атаки, а анімація не прискорюється»).
##
##     godot --headless --path game res://scenes/tempo.tscn
##
## Сценою: `ClientView` чіпає автозавантаження `Net`.
##
## Справжня модель людини й справжній `ClientView`, світ підставний.
## Міряється `speed_scale` програвача — це й є темп кліпа.

const AVATAR := preload("res://scenes/avatar.tscn")
var _bad := 0


func _expect(what: String, got: float, want: float) -> void:
	var ok := absf(got - want) < 0.02
	if not ok:
		_bad += 1
	print("  %s %s: %.2f%s" % ["✓" if ok else "✗", what, got,
			"" if ok else " (чекали %.2f)" % want])


func _ready() -> void:
	_go()


func _go() -> void:
	Net.joined = true
	await get_tree().process_frame
	var world := Node3D.new()
	get_tree().root.add_child(world)
	var a: Node = AVATAR.instantiate()
	world.add_child(a)
	a.apply_sex("чоловік")
	await get_tree().process_frame
	var view := ClientView.new({7: a}, world)
	var body: SkinnedModel = a.model()
	var player: AnimationPlayer = body._player
	var still := Vector3.ZERO
	var step := 1.0 / 60.0

	print("\n— біг —")
	for row: Array in [["хода без бафа", 5.0, 1.0], ["біг ×1,5", 7.5, 7.5 / 5.6],
			["біг ×2", 10.0, 10.0 / 5.6], ["хода з дебафом", 3.0, 0.6]]:
		view._anim.erase(7)
		view._human_state(7, a, body, row[1], Vector3(0, 0, -row[1] * step), step)
		_expect(row[0], player.speed_scale, row[2])

	print("\n— удар —")
	view._anim.erase(7)
	view.swung(7, true, 1.2)
	_expect("звичайний темп", player.speed_scale, 1.0)
	view.swung(7, true, 0.6)
	_expect("баф ×2 на атаку", player.speed_scale, 2.0)
	view._human_state(7, a, body, 0.0, still, step)
	_expect("поки б'є — темп удару", player.speed_scale, 2.0)
	view.swung(7, true, 3.0)
	_expect("повільний — не повільніше файла", player.speed_scale, 1.0)
	view._anim[7]["удар_до"] = 0.0
	view._anim[7]["бій_до"] = 0.0
	view._human_state(7, a, body, 0.0, still, step)
	_expect("після удару — знову як у файлі", player.speed_scale, 1.0)

	print("\nпомилок: %d" % _bad)
	get_tree().quit(1 if _bad > 0 else 0)
