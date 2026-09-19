extends SceneTree
## Монстри не заходять одне в одного (слово замовника 19.09.2026), а
## гравця це не зачіпає, і труп на дорозі не стоїть.
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
	var through := await _run(hero, Vector2(0, -1), [still])
	_yes("гравець крізь монстра проходить: найближче %.2f м" % through,
			through < 0.3)

	still.die()
	runner.place_at(Vector3(4, 1, 0), 0.0)
	var over := await _run(runner, Vector2(-1, 0), [still])
	_yes("труп на дорозі не стоїть: найближче %.2f м" % over, over < 0.3)

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
func _run(who: Node3D, dir: Vector2, others: Array) -> float:
	var closest := INF
	for i in 180:
		who.wanted = dir
		await physics_frame
		who.server_step(1.0 / 60.0)
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
