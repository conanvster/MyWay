class_name WorldMap
extends Control
## Карта світу з червоною крапкою гравця (пряме слово замовника
## 05.09.2026: «карта миру з позицією гравця червоною крапкою»).
##
## Малюється кодом, без жодного файлу — тим самим шляхом, що значки
## речей (`item_icon.gd`) і лінії дерева скілів (`tree_lines.gd`).
## Причина не в економії: карта тоді не може розійтися зі світом. Вона
## бере ті самі `data/map.json`, з яких збудовано землю, тож переставив
## місто в даних — і на карті воно переставилось само, без окремого
## малюнка, який хтось забуде перемалювати.
##
## Клієнт нічого не вигадує (П-08): і мапа, і власна позиція в нього вже
## є — позицію дає сервер, а карта лише показує те, що клієнт і так знає.

## Кольори взяті з самої мапи там, де вони в ній є (земля, море, брук),
## решта — щоб читалось на цих трьох.
const SEA := Color(0.145, 0.314, 0.42)
const EDGE := Color(0.86, 0.84, 0.74, 0.5)
const TOWN := Color(0.93, 0.86, 0.62)
const MOUNTAIN := Color(0.42, 0.44, 0.46)
const WOOD := Color(0.18, 0.37, 0.20)
## Гравець — саме червона крапка, як і замовлено.
const ME := Color(0.95, 0.16, 0.16)
const ME_RING := Color(1, 1, 1, 0.85)
const ME_DOT := 5.0

## Мапа світу (`GameData.map`). Порожня — карта чесно каже, що даних нема.
var map: Dictionary = {}
## Де гравець, у СВІТОВИХ координатах. Оновлює HUD щокадру.
var me := Vector3.ZERO
var has_me := false

var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


## Світові координати -> точка на карті.
func _spot(x: float, z: float) -> Vector2:
	var side := float(map.get("земля", {}).get("сторона", 240))
	var scale: float = minf(size.x, size.y) / maxf(side, 1.0)
	return size * 0.5 + Vector2(x, z) * scale


func _scale() -> float:
	var side := float(map.get("земля", {}).get("сторона", 240))
	return minf(size.x, size.y) / maxf(side, 1.0)


func _towns() -> Array:
	var many: Array = map.get("міста", [])
	if not many.is_empty():
		return many
	var one: Dictionary = map.get("місто", {})
	return [] if one.is_empty() else [one]


func _woods() -> Array:
	var many: Array = map.get("ліси", [])
	if not many.is_empty():
		return many
	var one: Dictionary = map.get("ліс", {})
	return [] if one.is_empty() else [one]


func _draw() -> void:
	if map.is_empty():
		draw_string(_font, Vector2(12, 24), "карти немає: дані не прийшли",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, EDGE)
		return

	var side := float(map.get("земля", {}).get("сторона", 240))
	var k := _scale()

	# Море під усім: за краєм суші саме воно й лишається.
	draw_rect(Rect2(Vector2.ZERO, size), SEA)
	# Сама земля — квадрат сторони світу.
	var land_from := _spot(-side * 0.5, -side * 0.5)
	var land_to := _spot(side * 0.5, side * 0.5)
	draw_rect(Rect2(land_from, land_to - land_from),
			Color(map.get("земля", {}).get("колір", "#5c8a42")))

	for wood: Dictionary in _woods():
		var at: Array = wood.get("центр", [0, 0, 0])
		draw_circle(_spot(float(at[0]), float(at[2])),
				float(wood.get("радіус", 26)) * k, WOOD)

	for hill: Dictionary in map.get("гори", []):
		var at: Array = hill.get("де", [0, 0, 0])
		draw_circle(_spot(float(at[0]), float(at[2])),
				float(hill.get("радіус", 26)) * k, MOUNTAIN)

	# Святині — крапка кольору свого грейду (та сама шкала, що на речах).
	for shrine: Dictionary in map.get("святині", []):
		var at: Array = shrine.get("де", [0, 0, 0])
		draw_circle(_spot(float(at[0]), float(at[2])), 3.0,
				ItemIcon.grade_color(str(shrine.get("грейд", "E"))))

	# Міста — поверх усього, з назвою: по них і орієнтуються.
	for town: Dictionary in _towns():
		var at: Array = town.get("центр", [0, 0, 0])
		var where := _spot(float(at[0]), float(at[2]))
		var wide: float = maxf(float(town.get("радіус", 22)) * k, 4.0)
		draw_circle(where, wide, TOWN)
		var name_of := str(town.get("назва", ""))
		if name_of != "":
			draw_string(_font, where + Vector2(wide + 3.0, 4.0), name_of,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TOWN)

	draw_rect(Rect2(land_from, land_to - land_from), EDGE, false, 1.0)

	# Гравець — останнім, щоб його не перекрило нічим.
	if has_me:
		var dot := _spot(me.x, me.z)
		draw_circle(dot, ME_DOT + 2.0, ME_RING)
		draw_circle(dot, ME_DOT, ME)


## Оновити позицію. Перемальовуємо лише коли крапка справді зрушила: на
## карті 480 точок крок у сантиметр не видно, а `queue_redraw()` щокадру
## — це малювання всієї карти щокадру.
func show_me(at: Vector3) -> void:
	if has_me and me.distance_to(at) < 1.0:
		return
	me = at
	has_me = true
	queue_redraw()
