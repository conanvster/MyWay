extends SceneTree
## Карта світу версії 2: цілий аркуш і збільшений вигляд.
##
## Замовник просив саме дві подачі: «є ціла карта та збільшений її
## вигляд для подорожей картою». Проба показує обидві й знімає їх, щоб
## було що покласти поруч із самим аркушем.
##
## Ганяти так:
##     ./run.sh --світ2-карта
##
## Esc — вийти, колесо — наблизити, тягни мишею — рухати.

const MAP2 := "res://data/map2.json"
## Де стоїть уявний гравець: центр столиці.
const ME := Vector3.ZERO

var _view: WorldMap
var _shots := 0


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	var text := FileAccess.get_file_as_string(MAP2)
	if text.is_empty():
		print("‼ немає %s — спершу `python3 tools/svit2.py`" % MAP2)
		quit(1)
		return

	var page := Control.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(page)
	var back := ColorRect.new()
	back.color = Color("#1b1712")
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_child(back)

	var box := WindowBox.new()
	box.setup("Карта", Vector2(640, 640))
	box.position = Vector2(60, 4)
	# Вікна гри народжуються схованими (`window_box.gd:setup`) — їх
	# показує натиск на панель. Тут панелі немає, тож показуємо самі.
	box.visible = true
	page.add_child(box)

	_view = WorldMap.new()
	_view.size = Vector2(640, 640)
	_view.custom_minimum_size = _view.size
	_view.map = JSON.parse_string(text)
	box.body.add_child(_view)
	_view.show_me(ME)
	_view.center_on_me()
	await process_frame

	var earth: Dictionary = _view.map["земля"]
	print("[карта] аркуш %s, плитки %s"
			% [_view.map["аркуш"]["ціла"], _view.map["аркуш"]["плитка"]])
	print("[карта] світ %s м у вікні 640 точок — увесь аркуш"
			% earth["сторона"])
	Shot.take(root)
	# Ім'я знімка має роздільність у секунду, тож між двома знімками
	# мусить пройти більше секунди — інакше другий тихо затре перший
	# (спіймано 05.09.2026: обидва лягли в один файл).
	for i in 100:
		await process_frame

	# А тепер збільшений вигляд: те саме місце, але плитками.
	for i in 8:
		_view._zoom_at(_view.size * 0.5, 1.35)
		await process_frame
	print("[карта] наближено до %.2f точки на метр — це вже плитки"
			% _view._scale())
	Shot.take(root)
	for i in 8:
		await process_frame
	print("[карта] обидва знімки зроблено. Вікно лишається відкритим —"
			+ " колесо наближає, миша тягне; закрити вікном.")
