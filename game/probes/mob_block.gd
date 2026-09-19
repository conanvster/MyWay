extends SceneTree
## Монстри не заходять одне в одного, гравець — у монстра, монстр — у
## гравця (слово замовника 19.09.2026); мертві на дорозі не стоять.
##
## Ганяти так:
##     godot --headless --path game --script res://probes/mob_block.gd

const MOB := preload("res://scenes/mob.tscn")
const AVATAR := preload("res://scenes/avatar.tscn")

var _bad := 0


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	var floor := StaticBody3D.new()
	var plane := CollisionShape3D.new()
	plane.shape = WorldBoundaryShape3D.new()
	floor.add_child(plane)
	root.add_child(floor)
	print("\n— монстри не заходять одне в одного —")

	var still := await _mob(Vector3(0, 1, 0))
	var runner := await _mob(Vector3(4, 1, 0))
	var closest := await _run(runner, Vector2(-1, 0), [still])
	_yes("монстр на монстра: найближче %.2f м (капсули 0,5 + 0,5)" % closest,
			closest > 0.9)

	var hero: Node3D = AVATAR.instantiate()
	root.add_child(hero)
	await process_frame
	hero.place_at(Vector3(0, 1, 4), 0.0)
	for i in 30:
		await physics_frame
		hero.server_step(1.0 / 60.0)
	var into := await _run(hero, Vector2(0, -1), [still])
	_yes("гравець на монстра: найближче %.2f м" % into, into > 0.9)

	# Монстра, що стоїть, прибрати з дороги — інакше бігун упреться в
	# нього, а не в гравця (перший прогін: «3,01 м» — до гравця).
	still.place_at(Vector3(0, 1, 12), 0.0)
	hero.place_at(Vector3(-4, 1, 0), 0.0)
	runner.place_at(Vector3(4, 1, 0), 0.0)
	for i in 10:
		await physics_frame
		hero.server_step(1.0 / 60.0)
	var at_hero := await _run(runner, Vector2(-1, 0), [hero], [still])
	_yes("монстр на гравця: найближче %.2f м" % at_hero, at_hero > 0.9)

	hero.die()
	runner.place_at(Vector3(-8, 1, 0), 0.0)
	var over_hero := await _run(runner, Vector2(1, 0), [hero], [hero])
	_yes("крізь мертвого гравця монстр проходить: найближче %.2f м"
			% over_hero, over_hero < 0.3)

	# Оживлення (`combat.revive` лише ставить здоров'я) — шар вертається
	# на першому ж кроці.
	hero.hp = 10
	hero.corpse_left = 0.0
	hero.server_step(1.0 / 60.0)
	_yes("оживлений гравець знову заважає монстрам",
			hero.get_collision_layer_value(hero.PLAYER_LAYER))

	still.die()
	runner.place_at(Vector3(4, 1, 12), 0.0)
	var over := await _run(runner, Vector2(-1, 0), [still])
	_yes("крізь мертвого монстра живий проходить: найближче %.2f м" % over,
			over < 0.3)

	print("  підсумок: %s" % ("усе гаразд" if _bad == 0
			else "‼ вад: %d" % _bad))
	quit(1 if _bad > 0 else 0)


func _mob(at: Vector3) -> Node3D:
	var m: Node3D = MOB.instantiate()
	root.add_child(m)
	await process_frame
	m.setup(at, 1, false, {})
	m.place_at(at, 0.0)
	for i in 30:
		await physics_frame
		m.server_step(1.0 / 60.0)
	return m


## Бігти в напрямку 3 с; найменша відстань по горизонталі до `others`.
## `stepping` — хто ще живе своїм кроком (гравцеві шар оновлює саме
## `server_step`).
func _run(who: Node3D, dir: Vector2, others: Array,
		stepping: Array = []) -> float:
	var closest := INF
	for i in 180:
		who.wanted = dir
		await physics_frame
		who.server_step(1.0 / 60.0)
		for o: Node3D in stepping:
			o.server_step(1.0 / 60.0)
		for o: Node3D in others:
			var d := Vector2(who.global_position.x - o.global_position.x,
					who.global_position.z - o.global_position.z).length()
			closest = minf(closest, d)
	who.wanted = Vector2.ZERO
	return closest


func _yes(text: String, ok: bool) -> void:
	if not ok:
		_bad += 1
	print("  %s %s" % ["✓" if ok else "✗", text])
