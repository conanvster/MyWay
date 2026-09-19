extends SceneTree
## Чи стоїть гравець НА землі, а не над нею (слово замовника 19.09.2026:
## «аватар висить над поверхнею… зроби, щоб аватар біг по поверхні, а
## не над»).
##
## Тіло падає на пласку підлогу під вагою, як на сервері
## (`server_step`), і, коли вляглося, міряємо найнижчу точку моделі
## проти підлоги. Добре — зазор у межах кількох сантиметрів.
##
## Ганяти так:
##     godot --headless --path game --script res://probes/feet.gd

const AVATAR := preload("res://scenes/avatar.tscn")
const MOB := preload("res://scenes/mob.tscn")
## Скільки зазору ще не видно оком (підошва моделі, шкіра капсули).
const FINE := 0.05

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
	print("\n— ноги гравця й підлога —")
	for sex: String in ["чоловік", "жінка"]:
		var hero: Node3D = AVATAR.instantiate()
		root.add_child(hero)
		await process_frame
		hero.apply_sex(sex)
		hero.place_at(Vector3(0, 3.0, 0), 0.0)
		for i in 180:
			await physics_frame
			hero.server_step(1.0 / 60.0)
		var low := _lowest(hero.model())
		var gap: float = low
		var good: bool = absf(gap) <= FINE and hero.is_on_floor()
		if not good:
			_bad += 1
		print("  %s %-8s тіло на висоті %.3f, стопа %.3f — %s"
				% ["✓" if good else "✗", sex, hero.global_position.y, gap,
				   "стоїть на підлозі" if good
						else "‼ зазор %.0f см" % (gap * 100.0)])
		hero.queue_free()
	# Монстр: капсула масштабується зростом, тож і зсув мусить.
	var beast: Node3D = MOB.instantiate()
	beast.look = {"зріст": 1.4}
	root.add_child(beast)
	await process_frame
	beast._apply_look()
	beast.place_at(Vector3(4, 3.0, 0), 0.0)
	for i in 180:
		await physics_frame
		beast.server_step(1.0 / 60.0)
	var paw := _lowest(beast.model())
	var fine: bool = absf(paw) <= FINE and beast.is_on_floor()
	if not fine:
		_bad += 1
	print("  %s монстр зросту 1,4: тіло на %.3f, низ моделі %.3f"
			% ["✓" if fine else "✗", beast.global_position.y, paw])
	print("  підсумок: %s" % ("усе на землі" if _bad == 0
			else "‼ %d не на землі" % _bad))
	quit(1 if _bad > 0 else 0)


## Найнижча точка видимої моделі у світі (за коробками мешів).
func _lowest(body: Node) -> float:
	var low := INF
	if body == null:
		return low
	for child in body.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = child
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		var box: AABB = mesh.global_transform * mesh.mesh.get_aabb()
		low = minf(low, box.position.y)
	return low
