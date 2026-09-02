extends SceneTree
## Проба до кроку 2.1: стани (бафи й дебафи).
##
## Ганяти так:
##     godot --headless --path game --script res://probes/стани.gd
##
## Перевіряє правила П-108 числами: однакові поновлюють строк, різні
## множаться, баф із дебафом гасяться, строк спливає — стат вертається.

const MOB := preload("res://scenes/mob.tscn")


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	_stacking()
	_expiry()
	await _on_creature()
	_cooldown_buff()
	quit()


## Правила складання.
func _stacking() -> void:
	print("\n— як складаються стани (П-108) —")
	var base := Stats.new()          # усі стати 10
	var states := States.new()

	states.apply(State.new("лють", "strength", 1.2, 10.0))
	print("  один баф +20%%: сила %d -> %d"
			% [base.strength, states.applied_to(base).strength])

	states.apply(State.new("лють", "strength", 1.2, 10.0))
	print("  той самий удруге: сила %d, станів %d (мав лишитись один)"
			% [states.applied_to(base).strength, states.count()])

	states.apply(State.new("напуття", "strength", 1.2, 10.0))
	print("  другий, інший, теж +20%%: сила %d (1,2 x 1,2 = 1,44)"
			% states.applied_to(base).strength)

	states.apply(State.new("слабкість", "strength", 0.8, 10.0))
	print("  плюс дебаф -20%%: сила %d (1,44 x 0,8 = 1,152)"
			% states.applied_to(base).strength)

	states.remove("напуття")
	states.remove("слабкість")
	print("  зняли обидва: сила %d (лишився перший баф)"
			% states.applied_to(base).strength)

	# Дебаф на чутливість — те, заради чого механізм і робився (П-40).
	var vision := States.new()
	vision.apply(State.new("сліпота", "sense", 0.5, 10.0))
	var dark := vision.applied_to(base)
	print("  дебаф на чутливість -50%%: Чуття %d -> %d, зона бачення %.1f -> %.1f"
			% [base.sense, dark.sense, base.vision_radius(),
			   dark.vision_radius()])


## Строк спливає сам.
func _expiry() -> void:
	print("\n— строк (П-108: вічних бафів немає) —")
	var base := Stats.new()
	var states := States.new()
	states.apply(State.new("лють", "agility", 1.5, 1.0))
	for step: float in [0.0, 0.5, 0.4, 0.2]:
		var gone: Array = states.tick(step)
		print("  минуло %.1f с: спритність %d, лишилось %.1f с%s"
				% [step, states.applied_to(base).agility,
				   states.all()[0].left if states.count() > 0 else 0.0,
				   "  ← скінчився: %s" % [gone] if not gone.is_empty() else ""])


## На живій істоті: базові стати лишаються цілими, чинні міняються.
func _on_creature() -> void:
	print("\n— на живому монстрі —")
	var m: Node3D = MOB.instantiate()
	root.add_child(m)
	await process_frame
	m.setup(Vector3.ZERO, 1, false)
	print("  базові: сила %d, спритність %d; здоров'я %d, відкат %.2f"
			% [m.base_stats.strength, m.base_stats.agility, m.hp,
			   m.stats.attack_cooldown()])
	m.add_state(State.new("лють", "strength", 1.5, 0.5))
	print("  під бафом сили +50%%: чинна сила %d, базова %d (не зіпсована)"
			% [m.stats.strength, m.base_stats.strength])
	print("  атака %.1f проти %.1f без бафа"
			% [m.stats.physical_attack(), m.base_stats.physical_attack()])
	# Пів секунди — і строк вийде просто в ході сервера.
	m.server_step(0.6)
	print("  через 0,6 с: чинна сила %d, станів %d"
			% [m.stats.strength, m.states.count()])
	m.queue_free()


## Баф на відкат іде повз стати — інакше теза П-35 не втрималась би.
func _cooldown_buff() -> void:
	print("\n— баф на відкат (П-35: стати відкат не ріжуть) —")
	var base := Stats.new()
	var states := States.new()
	states.apply(State.new("натхнення", "cooldown_cut", 0.25, 10.0))
	var buffed := states.applied_to(base)
	print("  скіл 6 поінтів: %.2f с без бафа, %.2f с під бафом"
			% [base.skill_cooldown(6.0), buffed.skill_cooldown(6.0)])
	states.apply(State.new("лють", "agility", 2.0, 10.0))
	print("  плюс подвійна спритність: відкат скіла %.2f с (не зрушив),"
			% states.applied_to(base).skill_cooldown(6.0))
	print("  а темп звичайних ударів %.2f -> %.2f (оце стат і ріже)"
			% [base.attack_cooldown(),
			   states.applied_to(base).attack_cooldown()])
