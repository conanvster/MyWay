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
## Гравець — червоний, як і замовлено 05.09.2026; з 11.09.2026 не крапка,
## а стрілка, повернута туди, куди дивиться персонаж (слово замовника:
## «зроби точку на мінікарті у вигляді стрілки з напрямком, куди дивиться
## аватар»).
const ME := Color(0.95, 0.16, 0.16)
const ME_RING := Color(1, 1, 1, 0.85)
## Від середини до вістря, точок екрана.
const ME_ARROW := 11.0

## Мапа світу (`GameData.map`). Порожня — карта чесно каже, що даних нема.
var map: Dictionary = {}
## Наближення: скільки точок екрана на метр світу. 0 — «весь аркуш у
## вікні», рахується при першому малюванні.
var _zoom := 0.0
## Куди дивимось: світові координати в середині вікна.
var _look := Vector2.ZERO
## Уже завантажені частини аркуша: шлях -> Texture2D. Плитка 1408² важить
## близько 8 МіБ у відеопамʼяті, тож тримаємо лише ті, що дивились.
var _sheets: Dictionary = {}
var _dragging := false
## Де гравець, у СВІТОВИХ координатах. Оновлює HUD щокадру.
var me := Vector3.ZERO
## Куди гравець дивиться: поворот навколо вертикалі, як `rotation.y`.
var me_facing := 0.0
var has_me := false

var _font: Font


func _ready() -> void:
	# Аркуш можна тягати й наближати, тож миша потрібна. Вікно від цього
	# не перестає тягатись: `window_box.gd` ловить перетягування на
	# заголовку, а не на тілі.
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_font = ThemeDB.fallback_font


## Намальований аркуш карти (світ версії 2). Порожньо — карта
## малюється кодом, як і була.
func _sheet() -> Dictionary:
	return map.get("аркуш", {})


## Ліва-верхня точка світу в метрах. Версія 1 центрована в (0,0),
## версія 2 зсунута під столицю.
func _from() -> Vector2:
	var earth: Dictionary = map.get("земля", {})
	if earth.has("початок"):
		var at: Array = earth["початок"]
		return Vector2(float(at[0]), float(at[1]))
	var side := float(earth.get("сторона", 240))
	return Vector2(-side * 0.5, -side * 0.5)


## Наближення, при якому весь світ уміщається у вікні.
func _fit() -> float:
	var side := float(map.get("земля", {}).get("сторона", 240))
	return minf(size.x, size.y) / maxf(side, 1.0)


## Світові координати -> точка на карті.
func _spot(x: float, z: float) -> Vector2:
	return size * 0.5 + (Vector2(x, z) - _look) * _scale()


func _scale() -> float:
	return _zoom if _zoom > 0.0 else _fit()


## Перший показ: увесь світ у вікні, погляд у його середину.
func _ensure_view() -> void:
	if _zoom > 0.0:
		return
	_zoom = _fit()
	var side := float(map.get("земля", {}).get("сторона", 240))
	_look = _from() + Vector2(side, side) * 0.5


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
	_ensure_view()
	if not _sheet().is_empty():
		_draw_sheet()
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
		_draw_me(_spot(me.x, me.z))


## Гравець на карті: червона стрілка в білому обідку, вістрям туди, куди
## дивиться персонаж. Вістря з вирізом ззаду, а не трикутник: трикутник
## на дрібній карті читається як іще одна крапка, а стрілку видно одразу.
func _draw_me(dot: Vector2) -> void:
	# На карті x світу — праворуч, z — донизу. Вузол дивиться своїм −Z
	# (той самий кут, що в `Creature.face_to`), тож уперед — це
	# (−sin, −cos) кута.
	var ahead := Vector2(-sin(me_facing), -cos(me_facing))
	var side := Vector2(-ahead.y, ahead.x)
	var shape := PackedVector2Array([
		dot + ahead * ME_ARROW,
		dot - ahead * ME_ARROW * 0.6 + side * ME_ARROW * 0.62,
		dot - ahead * ME_ARROW * 0.25,
		dot - ahead * ME_ARROW * 0.6 - side * ME_ARROW * 0.62,
	])
	var ring := PackedVector2Array()
	for point in shape:
		ring.append(dot + (point - dot) * 1.4)
	draw_colored_polygon(ring, ME_RING)
	draw_colored_polygon(shape, ME)


## Оновити позицію й напрямок. Перемальовуємо лише коли стрілка справді
## зрушила чи повернулась: на карті 480 точок крок у сантиметр не видно,
## а `queue_redraw()` щокадру — це малювання всієї карти щокадру.
func show_me(at: Vector3, look: float = 0.0) -> void:
	if has_me and me.distance_to(at) < 1.0 \
			and absf(angle_difference(me_facing, look)) < deg_to_rad(4.0):
		return
	me = at
	me_facing = look
	has_me = true
	queue_redraw()


# ── Намальований аркуш (світ версії 2) ─────────────────────────────
#
# Дві подачі того самого світу, як і просив замовник: цілий аркуш —
# щоб бачити, де ти в світі, і збільшений вигляд — щоб подорожувати
# картою. Це не два малюнки: плитки — той самий аркуш, розрізаний на
# 4×4 з учетверо більшою деталізацією, тож стик між ними непомітний.
#
# Далі за який масштаб беремо плитки, а не цілий аркуш. Нижче цього
# порогу плитка все одно стиснулась би до розміру цілого аркуша —
# сенсу вантажити 16 картинок замість однієї немає.
const TILE_FROM := 0.22
## Наскільки міняє масштаб один крок колеса.
const ZOOM_STEP := 1.35


## Частина аркуша — картинкою з файлу, а не ресурсом рушія.
##
## `load()` тут не годиться: аркуш і плитки лежать у `data/` поруч із
## числами світу й рушієм НЕ ІМПОРТОВАНІ, тож `ResourceLoader.exists()`
## на них хибний, і карта мовчки лишалась порожньою синьою плямою
## (спіймано знімком 05.09.2026). Читаємо байти й робимо текстуру самі
## — тим самим шляхом, яким гра читає `map.json`.
func _texture(path: String) -> Texture2D:
	if _sheets.has(path):
		return _sheets[path]
	var made: Texture2D = null
	var raw := FileAccess.get_file_as_bytes(path)
	if raw.is_empty():
		print("[карта] ‼ немає %s" % path)
	else:
		var picture := Image.new()
		var err := picture.load_jpg_from_buffer(raw)
		if err != OK:
			print("[карта] ‼ %s не прочитався: %s" % [path, error_string(err)])
		else:
			made = ImageTexture.create_from_image(picture)
	# Плитка 1408² важить близько 8 МіБ у відеопамʼяті. Тримаємо
	# небагато: за раз видно щонайбільше чотири, решта — минуле.
	if _sheets.size() > 6:
		_sheets.clear()
	_sheets[path] = made
	return made


func _draw_sheet() -> void:
	var sheet := _sheet()
	var earth: Dictionary = map.get("земля", {})
	var side := float(earth.get("сторона", 240))
	var at := _from()
	var k := _scale()
	draw_rect(Rect2(Vector2.ZERO, size), SEA)

	if k < TILE_FROM:
		var whole := _texture(str(sheet.get("ціла", "")))
		if whole != null:
			draw_texture_rect(whole, Rect2(_spot(at.x, at.y),
					Vector2(side, side) * k), false)
	else:
		var rows := int(sheet.get("рядків", 4))
		var cols := int(sheet.get("стовпців", 4))
		var tile := Vector2(side / cols, side / rows)
		for row in rows:
			for col in cols:
				var corner := at + Vector2(col * tile.x, row * tile.y)
				var box := Rect2(_spot(corner.x, corner.y), tile * k)
				# Малюємо лише те, що справді видно: інакше кожен кадр
				# тягнув би у відеопамʼять усі шістнадцять плиток.
				if not box.intersects(Rect2(Vector2.ZERO, size)):
					continue
				var path: String = str(sheet.get("плитка", "")) \
						% [row + 1, col + 1]
				var part := _texture(path)
				if part != null:
					draw_texture_rect(part, box, false)

	# Іменні місця поверх аркуша: на самому аркуші написів немає
	# навмисно, а знати, як зветься місто, треба.
	if k >= TILE_FROM * 0.5:
		for group: String in ["міста", "села"]:
			for place: Dictionary in map.get(group, []):
				var centre: Array = place.get("центр", [0, 0, 0])
				var spot := _spot(float(centre[0]), float(centre[2]))
				if not Rect2(Vector2.ZERO, size).has_point(spot):
					continue
				draw_circle(spot, 3.0, TOWN)
				draw_string(_font, spot + Vector2(6, 4),
						str(place.get("назва", "")),
						HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TOWN)

	if has_me:
		_draw_me(_spot(me.x, me.z))

	var hint := "×%.1f · колесо — наблизити · тягни — рухати" % (k / _fit())
	draw_string(_font, Vector2(8, size.y - 8), hint,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, EDGE)


func _gui_input(event: InputEvent) -> void:
	if _sheet().is_empty():
		return
	if event is InputEventMouseButton:
		var press := event as InputEventMouseButton
		if press.button_index == MOUSE_BUTTON_WHEEL_UP and press.pressed:
			_zoom_at(press.position, ZOOM_STEP)
			accept_event()
		elif press.button_index == MOUSE_BUTTON_WHEEL_DOWN and press.pressed:
			_zoom_at(press.position, 1.0 / ZOOM_STEP)
			accept_event()
		elif press.button_index == MOUSE_BUTTON_LEFT:
			_dragging = press.pressed
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var move := event as InputEventMouseMotion
		_look -= move.relative / _scale()
		_clamp_look()
		queue_redraw()


## Наблизити так, щоб точка під курсором лишилась на місці — інакше
## карта тікає з-під миші щоразу, як крутнеш колесо.
func _zoom_at(where: Vector2, by: float) -> void:
	_ensure_view()
	var before := _look + (where - size * 0.5) / _zoom
	# Далі за 1 метр на точку не наближаємо: плитка намальована саме в
	# такій щільності, більше — просто розмиті пікселі.
	_zoom = clampf(_zoom * by, _fit(), 1.0)
	_look = before - (where - size * 0.5) / _zoom
	_clamp_look()
	queue_redraw()


## Не давати виїхати за аркуш: за його краєм немає нічого, і порожній
## екран читався б як «карта зламалась».
func _clamp_look() -> void:
	var side := float(map.get("земля", {}).get("сторона", 240))
	var at := _from()
	var half := size * 0.5 / _scale()
	_look.x = clampf(_look.x, at.x + half.x, at.x + side - half.x)
	_look.y = clampf(_look.y, at.y + half.y, at.y + side - half.y)


## Показати гравця посередині — коли вікно щойно відкрили.
func center_on_me() -> void:
	if not has_me or _sheet().is_empty():
		return
	_ensure_view()
	_look = Vector2(me.x, me.z)
	_clamp_look()
	queue_redraw()
