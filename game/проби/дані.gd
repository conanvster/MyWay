extends SceneTree
## Проба до кроку 1.2: числа в даних, зони в редакторі.
##
## Ганяти так:
##     godot --headless --path game --script res://проби/дані.gd
##
## Перевіряє три речі, кожну числами:
##   1. зони зі сцени справді мають форму, і випадкові точки лежать у ній;
##   2. числа монстрів приходять із `дані/монстри.json`, а не з коду;
##   3. зіпсований файл не робить нулів — числа лишаються попередні.

const MAIN := preload("res://scenes/main.tscn")
const MOB := preload("res://scenes/mob.tscn")


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	await _zones()
	_data()
	_tuning()
	_broken_file()
	quit()


## Зони: скільки, якої форми, і чи точки лежать усередині.
func _zones() -> void:
	print("\n— зони появи зі сцени —")
	# Вище в журналі буде «Identifier not found: Net» — так і має бути:
	# у режимі --script автозавантажень немає, тому `world.gd` не
	# компілюється. Зони від нього не залежать: вони окремі вузли.
	var world: Node3D = MAIN.instantiate()
	root.add_child(world)
	await process_frame
	var zones := world.find_children("*", "MobZone", true, false)
	print("  знайдено зон: %d (сцена без world.gd — див. про Net вище)"
			% zones.size())
	for zone in zones:
		var shapes: int = zone.find_children("*", "CollisionShape3D", true,
				false).size()
		var inside := 0
		var lo := Vector3(1e9, 1e9, 1e9)
		var hi := Vector3(-1e9, -1e9, -1e9)
		for i in 500:
			var p: Vector3 = zone.random_point()
			if zone.has_point(p):
				inside += 1
			lo = lo.min(p)
			hi = hi.max(p)
		print("  %-7s вид %d, штук %d, форм %d: у зоні %d з 500, межі x %.1f..%.1f  z %.1f..%.1f"
				% [zone.name, zone.kind, zone.count, shapes, inside,
				   lo.x, hi.x, lo.z, hi.z])
	# Пастка з КОНТЕКСТ.md: у .tscn Transform3D записується РЯДКАМИ
	# матриці, тому дев'ять чисел, узятих як вектори осей, дають поворот
	# у протилежний бік. Тут це вже враховано — коліна повернуті на -45°
	# і -90°, і саме з такими знаками вони стикуються.
	print("  тунель по колінах (початок -> кінець кожного):")
	for part: Node3D in world.get_node("MobZones/Tunnel").get_children():
		var half: float = part.shape.size.x * 0.5
		var axis: Vector3 = part.global_transform.basis.x.normalized()
		var a: Vector3 = part.global_position - axis * half
		var b: Vector3 = part.global_position + axis * half
		print("    %-8s поворот %4.0f°  (%6.1f, %6.1f) -> (%6.1f, %6.1f)"
				% [part.name, part.rotation_degrees.y, a.x, a.z, b.x, b.z])
	world.queue_free()


## Числа приходять із файлу.
func _data() -> void:
	print("\n— дані/монстри.json —")
	var data := GameData.new()
	print("  прочитано повністю: %s" % data.load_all())
	for kind: int in [1, 2]:
		var t: Dictionary = data.for_kind(kind)
		print("  вид %d (%s): помічає %.0f, повідець %.0f, поклик %.0f, темп %.2f"
				% [kind, t.get("назва", "?"), t["помічає"], t["повідець"],
				   t["поклик"], t["блукання_темп"]])
	print("  панель: %s" % [data.bar])


## Монстр бере числа з даних, а не зі своїх запасних.
func _tuning() -> void:
	print("\n— число з файлу доходить до монстра —")
	var data := GameData.new()
	data.load_all()
	var m: Node3D = MOB.instantiate()
	root.add_child(m)
	m.setup(Vector3.ZERO, 1, true, data.for_kind(1))
	print("  із файлу: поклик %.0f, повідець %.0f, сила %d"
			% [m.help_range, m.leash, m.stats.strength])
	# Правку файлу вдаємо словником: сервер робить те саме після poll().
	m.apply_tuning({"поклик": 30.0, "повідець": 40.0,
			"стати": {"сила": 12}})
	print("  після правки: поклик %.0f, повідець %.0f, сила %d"
			% [m.help_range, m.leash, m.stats.strength])
	print("  здоров'я не перераховано на ходу: %d (стати діють із появи)"
			% m.hp)
	m.queue_free()


## Зіпсований файл: гучна помилка, але числа лишаються попередні.
func _broken_file() -> void:
	print("\n— зіпсований файл —")
	var data := GameData.new()
	data.load_all()
	var was: float = data.for_kind(1)["поклик"]
	var broken := "{ це не json "
	var json := JSON.new()
	var err := json.parse(broken)
	print("  розбір зіпсованого рядка: помилка %s, рядок %d"
			% [error_string(err), json.get_error_line()])
	print("  поклик до й після: %.0f -> %.0f (числа не занулились)"
			% [was, data.for_kind(1)["поклик"]])
	print("  невідомий вид: %s (має бути порожньо, з гучним рядком вище)"
			% [data.for_kind(99)])
