extends SceneTree
## Світ версії 2 згори: знімок усієї землі, щоб порівняти з аркушем.
##
## Це не заміна пробі `world2.gd` (та звіряє числа) — це відповідь на
## інше питання: чи ВИГЛЯДАЄ побудований світ тим самим світом, що
## намальований. Одна картинка поруч з іншою — і видно, чи там ті самі
## береги, ті самі зони й ті самі гори.
##
## Ганяти так:
##     ./run.sh --світ2-згори
##
## Туман тут навмисно вимкнено: він зроблений під зону бачення 18 м
## (П-65) і згори з'їв би все, крім плями під камерою.

const MAIN := preload("res://scenes/main.tscn")
const MAP2 := "res://data/map2.json"


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	var text := FileAccess.get_file_as_string(MAP2)
	if text.is_empty():
		print("‼ немає %s — спершу `python3 tools/svit2.py`" % MAP2)
		quit(1)
		return
	var map: Dictionary = JSON.parse_string(text)
	var earth: Dictionary = map["земля"]
	var side := float(earth["сторона"])
	var start := Vector2(float(earth["початок"][0]),
			float(earth["початок"][1]))
	var middle := Vector3(start.x + side * 0.5, 0.0, start.y + side * 0.5)

	# Світ-клієнт сам стукає на 127.0.0.1, а там може саме йти
	# гра замовника (19.09.2026: проба під'єдналась до живого
	# сервера світу 2 й перезапускалась по колу). «Уже в мережі» —
	# і `Net.join()` нічого не робить.
	var net: Node = root.get_node_or_null("Net")
	if net != null:
		net.joined = true
	var world: Node3D = MAIN.instantiate()
	root.add_child(world)
	await process_frame
	var land: Node = world.get_node("Landscape")
	var started := Time.get_ticks_msec()
	land.build(map)
	print("[згори] світ збудовано за %d мс" % (Time.get_ticks_msec() - started))
	await process_frame

	# Туман і небо — геть: дивимось на землю, не на погоду.
	for child in land.get_children():
		if child is WorldEnvironment:
			var air: Environment = (child as WorldEnvironment).environment
			air.fog_enabled = false
			air.background_mode = Environment.BG_COLOR
			air.background_color = Color("#14202a")
			air.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			air.ambient_light_color = Color(1, 1, 1)
			air.ambient_light_energy = 0.9

	var sun := DirectionalLight3D.new()
	# Низьке сонце навмисно: на 5632 м увесь перепад висот — 95 м, і при
	# високому сонці рельєфу згори не видно взагалі. Тінь під кутом
	# показує хребти так само, як відмивка на самому аркуші.
	sun.rotation_degrees = Vector3(-24, -35, 0)
	sun.light_energy = 1.1
	root.add_child(sun)

	var eye := Camera3D.new()
	eye.projection = Camera3D.PROJECTION_ORTHOGONAL
	eye.size = side
	eye.near = 1.0
	eye.far = side * 2.0
	eye.position = middle + Vector3(0, side * 0.6, 0)
	eye.rotation_degrees = Vector3(-90, 0, 0)
	root.add_child(eye)
	eye.make_current()

	# Кілька кадрів на те, щоб рушій справді намалював усе, що додано.
	for i in 12:
		await process_frame
	Shot.take(root)
	# Знімок робиться після наступного намальованого кадру, тож даємо
	# рушієві їх намалювати, перш ніж виходити.
	for i in 6:
		await process_frame
	quit()
