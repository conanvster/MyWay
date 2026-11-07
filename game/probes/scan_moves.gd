extends Node
## Рухи аватарів зі сканів за діями й темпом (07.11.2026, слово замовника:
## «не реалізовані рухи — зробити їх відповідаючими діям та швидкості дій
## в залежності від статів та бафів»).
##
##     godot --headless --path game res://scenes/scan_moves.tscn
##
## Орчиха s1303 (10 рухів Mixamo), справжній `ClientView`. Міряється, ЩО
## грає (`_current_name`) і в якому темпі (`speed_scale`).

const AVATAR := preload("res://scenes/avatar.tscn")
var _bad := 0


func _expect(what: String, ok: bool) -> void:
	if not ok:
		_bad += 1
	print("  %s %s" % ["✓" if ok else "✗", what])


func _ready() -> void:
	_go()


func _go() -> void:
	Net.joined = true
	await get_tree().process_frame
	var data := GameData.new()
	data.load_all()
	var world := Node3D.new()
	get_tree().root.add_child(world)
	var a: Node = AVATAR.instantiate()
	world.add_child(a)
	a.apply_sex("жінка", "орк")
	await get_tree().process_frame
	var view := ClientView.new({7: a}, world)
	var body: SkinnedModel = a.model()
	var player: AnimationPlayer = body._player
	var step := 1.0 / 60.0
	var still := Vector3.ZERO
	print("    модель: %s" % body.path.get_file())

	print("\n— лук: постріл, не замах —")
	a.wear({"зброя": "ясеновий лук"}, data.items)
	view._anim.erase(7)
	view.swung(7, true, 1.2)
	print("    у руці «%s», грає %s, темп %.2f" % [a.held_kind(),
			body._current_name, player.speed_scale])
	_expect("лук → Bow_Shot", body._current_name == "Bow_Shot")
	a.wear({"зброя": "залізний меч"}, data.items)
	view._anim.erase(7)
	view.swung(7, true, 1.2)
	var slash: float = body.move_length("Sword_Attack")
	print("    меч: грає %s (%.2f с), темп %.2f" % [body._current_name, slash,
			player.speed_scale])
	_expect("меч → Sword_Slash, увесь рух у паузу 1,2 с",
			body._current_name == "Sword_Slash"
			and absf(player.speed_scale * 1.2 - slash) < 0.05)
	view.swung(7, true, 0.4)
	_expect("баф атаки (пауза 0,4 с) — темп %.2f ≥ 3" % player.speed_scale,
			player.speed_scale >= 2.99)

	print("\n— каст: темп від часу читання —")
	var cast_clip: float = body.move_length("Spell_Simple_Idle")
	for seconds: float in [1.4, 0.7, 0.3]:
		view._anim.erase(7)
		a.start_cast("проба", seconds, 0)
		view.cast_started(7, seconds)
		view._human_state(7, a, body, 0.0, still, step)
		print("    читання %.1f с: грає %s, темп %.2f (рух %.2f с → %.2f с)"
				% [seconds, body._current_name, player.speed_scale, cast_clip,
				   cast_clip / player.speed_scale])
		var want := maxf(seconds, cast_clip / ClientView.CAST_TEMPO_MAX)
		_expect("каст скінчиться разом із читанням %.1f с (межа ×%.0f)"
				% [seconds, ClientView.CAST_TEMPO_MAX],
				body._current_name == "Cast"
				and absf(cast_clip / player.speed_scale - want) < 0.05)
		a.stop_cast()

	print("\n— влучання не застигає; щит — блок —")
	a.wear({}, data.items)
	view._anim.erase(7)
	view._anim[7] = {"hp": a.hp + 10}
	view._human_state(7, a, body, 0.0, still, step)
	var t0: float = player.current_animation_position
	for i in 10:
		view._human_state(7, a, body, 0.0, still, step)
		player.advance(step)
	print("    без щита: грає %s, позиція %.2f → %.2f с" % [body._current_name,
			t0, player.current_animation_position])
	_expect("Hit іде вперед (раніше перезапускався щокадру)",
			body._current_name == "Hit"
			and player.current_animation_position > t0 + 0.1)
	a.wear({"щит": "щит з кори дуба"}, data.items)
	view._anim.erase(7)
	view._anim[7] = {"hp": a.hp + 10}
	view._human_state(7, a, body, 0.0, still, step)
	print("    зі щитом: грає %s" % body._current_name)
	_expect("щит → Block", body._current_name == "Block")

	print("\nпомилок: %d" % _bad)
	get_tree().quit(1 if _bad > 0 else 0)
