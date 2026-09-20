extends Node
## Супер-баф на проби (слово замовника 20.09.2026: «зроби супер баф для
## тесту — застосую у священника, окремим пунктом: +500% швидкості,
## +500% швидкості бою, +300% швидкість відкату вмінь»).
##
## Перевіряємо саме числа: чи справді вшестеро й учетверо, чи не
## впирається в нижню межу й чи не лишає слід після себе.
##
##     godot --headless --path game res://scenes/superbuff.tscn

var _ok := 0
var _bad := 0


func _ready() -> void:
	_go()


func _yes(text: String, is_ok: bool) -> void:
	_ok += 1 if is_ok else 0
	_bad += 0 if is_ok else 1
	print("  %s %s" % ["✓" if is_ok else "✗", text])


func _go() -> void:
	await get_tree().process_frame
	_numbers()
	await _data()
	print("  підсумок: %s" % ("усе гаразд" if _bad == 0
			else "‼ вад: %d" % _bad))
	get_tree().quit(1 if _bad > 0 else 0)


func _numbers() -> void:
	print("\n— що з числами —")
	var base := Stats.new()
	var states := States.new()
	var було := {
		"біг": base.move_speed(),
		"удар": base.attack_cooldown(),
		"замах": base.swing_time(),
		"відкат скіла": base.skill_cooldown(6.0),
	}
	var raw := FileAccess.get_file_as_string("res://data/blessings.json")
	var parsed: Variant = JSON.parse_string(raw)
	var buffs: Array = parsed.get("супер", {}).get("бафи", [])
	_yes("блок «супер» у blessings.json є", not buffs.is_empty())
	for one: Variant in buffs:
		states.apply(State.from_data(one))
	var with := states.applied_to(base)
	var стало := {
		"біг": with.move_speed(),
		"удар": with.attack_cooldown(),
		"замах": with.swing_time(),
		"відкат скіла": with.skill_cooldown(6.0),
	}
	for що: String in було:
		print("    %-14s %.3f → %.3f" % [що, було[що], стало[що]])
	_yes("біг ушестеро швидший (+500%)",
			absf(стало["біг"] / не_нуль(було["біг"]) - 6.0) < 0.01)
	_yes("удар ушестеро частіший (+500%)",
			absf(було["удар"] / не_нуль(стало["удар"]) - 6.0) < 0.05)
	_yes("замах ушестеро коротший",
			absf(було["замах"] / не_нуль(стало["замах"]) - 6.0) < 0.05)
	_yes("відкат скіла вчетверо коротший (+300%)",
			absf(було["відкат скіла"] / не_нуль(стало["відкат скіла"])
					- 4.0) < 0.05)
	# Межі не мають з'їсти баф: саме на це впирався старий `swing_time`
	# із порогом 0,15 с.
	_yes("замах не впирається в нижню межу", стало["замах"] > 0.051)
	_yes("удар не впирається в нижню межу", стало["удар"] > 0.081)

	# Баф не лишає сліду: `applied_to` вертає новий Stats.
	_yes("базові стати не зачеплені",
			absf(base.move_speed() - було["біг"]) < 0.001)


func не_нуль(v: float) -> float:
	return v if absf(v) > 0.0001 else 0.0001


func _data() -> void:
	print("\n— окремим пунктом —")
	var hud := HUD.new()
	add_child(hud)
	hud.setup(self)
	await get_tree().process_frame
	var просив: Array = []
	hud.wants_super_bless.connect(func(at: int) -> void: просив.append(at))
	hud.show_talk(2, "Мирон, священик", false, false, false, true, false,
			true)
	await get_tree().process_frame
	_yes("кнопка проби є і вона окрема від бафів",
			hud._talk_super.visible and hud._talk_bless.visible
			and hud._talk_super != hud._talk_bless)
	hud.show_talk(3, "Ліда, крамар", true)
	await get_tree().process_frame
	_yes("у крамаря кнопки проби немає", not hud._talk_super.visible)
	hud.show_talk(2, "Мирон, священик", false, false, false, true, false,
			true)
	await get_tree().process_frame
	hud._talk_super.pressed.emit()
	await get_tree().process_frame
	_yes("натиск просить саме супер-баф", просив == [2])
	hud.queue_free()
