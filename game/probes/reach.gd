extends SceneTree
## Проба В-2: ціль вийшла з-під руки, поки летів удар.
##
## Ганяти так:
##     godot --headless --path game --script res://probes/reach.gd
##
## Раніше сервер казав «задалеко» й викидав дію. Тепер він кличе
## `on_out_of_reach` (світ шле клієнтові «доганяй») — і лише гравцеві:
## монстр доганяє сам, своїм розумом.

const AVATAR := preload("res://scenes/avatar.tscn")

var _bad := 0


func _init() -> void:
	call_deferred("_go")


func _expect(what: String, got: Variant, want: Variant) -> void:
	var ok: bool = got == want
	if not ok:
		_bad += 1
	print("  %s %s: %s%s" % ["✓" if ok else "✗", what, str(got),
			"" if ok else " (чекали %s)" % str(want)])


func _go() -> void:
	await process_frame
	var data := GameData.new()
	data.load_all()
	var creatures := {}
	var combat := Combat.new(creatures)
	combat.skills = data.skills
	var asked: Array = []
	combat.on_out_of_reach = func(me: int, action: String) -> void:
			asked.append([me, action])

	var a: Node3D = AVATAR.instantiate()
	var b: Node3D = AVATAR.instantiate()
	root.add_child(a)
	root.add_child(b)
	await process_frame
	creatures[1] = a
	creatures[2] = b
	for one: Node3D in [a, b]:
		one.refresh_stats()
		one.hp = 100
	a.global_position = Vector3.ZERO
	a.target_id = 2

	print("\n— удар —")
	b.global_position = Vector3(Creature.ATTACK_RANGE + 0.4, 0, 0)
	_expect("ціль на 0,4 м за межею: удару немає",
			combat.attack(1), false)
	_expect("гравцеві сказано доганяти удар", asked, [[1, "attack"]])
	b.global_position = Vector3(Creature.ATTACK_RANGE - 0.4, 0, 0)
	a.attack_ready_in = 0.0
	_expect("догнав — удар є", combat.attack(1), true)

	print("\n— скіл —")
	asked.clear()
	a.learn("енергетичний-промінь", 1)
	a.mp = 1000
	var reach: float = data.skills.get_skill("енергетичний-промінь").range_at(1)
	b.global_position = Vector3(reach + 1.0, 0, 0)
	_expect("промінь задалеко — не почато", combat.cast(1, "енергетичний-промінь"),
			false)
	_expect("гравцеві сказано доганяти скіл", asked,
			[[1, "скіл:енергетичний-промінь"]])
	_expect("мана не списана", a.mp, 1000)

	print("\n— монстр —")
	asked.clear()
	creatures[-1] = b
	creatures.erase(2)
	b.target_id = 1
	b.global_position = Vector3(Creature.ATTACK_RANGE + 1.0, 0, 0)
	combat.attack(-1)
	_expect("монстрові не шлемо «доганяй»", asked, [])

	print("\nпомилок: %d" % _bad)
	quit()
