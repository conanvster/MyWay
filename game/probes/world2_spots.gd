extends SceneTree
## Світ версії 2 з землі: кілька місць, по знімку на кожне.
##
## Питання, на які відповідає: чи межа зон читається переходом, а не
## ножем · чи стоять орієнтири на ґрунті · чи є на схилах ліс і чи
## тече в руслі вода · чи видно небо.
##
## Ганяти так:
##     ./run.sh --світ2-місця

const MAIN := preload("res://scenes/main.tscn")
const MAP2 := "res://data/map2.json"

## Куди дивимось: назва · точка на землі · куди повернуто · нахил.
const SPOTS := [
	["гай на рівнині, з висоти людини", Vector3(-240, 0, -560), 30.0, -2.0],
	["межа рівнини й вулканічної смуги", Vector3(64, 0, -1232), 270.0, -6.0],
	["гори заходу, схил", Vector3(-2032, 0, -1064), 270.0, -4.0],
	["русло в горах", Vector3(-1296, 0, -896), 20.0, -8.0],
	["мертвий схід", Vector3(1456, 0, -2260), 180.0, -4.0],
	["крижана північ", Vector3(1464, 0, -2912), 200.0, -6.0],
]


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	var text := FileAccess.get_file_as_string(MAP2)
	if text.is_empty():
		print("‼ немає %s — спершу `python3 tools/svit2.py`" % MAP2)
		quit(1)
		return
	var world: Node3D = MAIN.instantiate()
	root.add_child(world)
	await process_frame
	var land: Node = world.get_node("Landscape")
	# З підвантаженням, як у справжнього клієнта: інакше проба тягне у
	# памʼять усі рослини світу, а видно однаково лише ті, що поруч.
	land.build(JSON.parse_string(text), true)
	await process_frame

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -50, 0)
	sun.light_energy = 1.05
	root.add_child(sun)

	var eye := Camera3D.new()
	eye.far = 900.0
	root.add_child(eye)
	eye.make_current()

	for spot: Array in SPOTS:
		var at: Vector3 = spot[1]
		var ground: float = land.height_at(at.x, at.z)
		# Камера на зріст людини плюс трохи: дивимось так, як дивиться
		# гравець, а не з висоти пташиного лету.
		# Двадцять метрів над землею, а не зріст людини: з висоти очей
		# схил видно під таким кутом, що по ньому нічого не порахуєш —
		# перший підхід через це показував «голі гори», хоч дерева на
		# них стояли (05.09.2026).
		# Перше місце дивимось із висоти людини, решту — з двадцяти
		# метрів: зблизька видно ліс, згори — його розкид.
		var up: float = 2.5 if spot[0].begins_with("гай") else 20.0
		eye.position = Vector3(at.x, ground + up, at.z)
		eye.rotation_degrees = Vector3(float(spot[3]), float(spot[2]), 0)
		land.stream_to(eye.position)
		print("[місце] %s — земля %.1f м" % [spot[0], ground])
		for i in 20:
			await process_frame
		Shot.take(root)
		# Ім'я знімка з роздільністю в секунду: між двома має пройти
		# більше секунди, інакше другий затре перший.
		for i in 80:
			await process_frame
	print("[місця] знімки зроблено")
	quit()
