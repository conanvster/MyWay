class_name ItemIcon
extends Control
## Значок речі. Є справжній малюнок (`assets/icons/items/`) — показуємо
## його; немає (гроші, сирий ресурс, ще не намальована річ) — форма
## каже, ЩО це, колір — якого воно грейду, як і раніше (П-131).
##
## Малюнок шукається за ІМ'ЯМ речі, точно як у `data/items.json`:
## підклав `assets/icons/items/<назва>.png` — річ дістала значок сама,
## код міняти не треба. Рамка кольором грейду лишається й на малюнку:
## так грейд читається з одного погляду, як і на кодовій фігурі.
##
## Форма (коли малюнка немає) береться зі СЛОТА, коли він є (меч і шолом
## обидва «обладунок» або «зброя», але вдягаються в різні комірки),
## інакше — з виду: руна, кристал, ресурс, гроші.
##
## Кольори грейдів — пропозиція П-131, не рішення. Якщо замовник назве
## свої, міняється рівно `GRADE_COLORS`.

## Тека з малюнками. Ключ файлу — точна назва речі з `data/items.json`.
const ART_DIR := "res://assets/icons/items/"

static var _art: Dictionary = {}
static var _art_loaded := false

const GRADE_COLORS := {
	"E": Color(0.60, 0.62, 0.60),    ## сірий — початковий
	"D": Color(0.90, 0.92, 0.90),    ## білий
	"C": Color(0.42, 0.78, 0.44),    ## зелений
	"B": Color(0.36, 0.58, 0.92),    ## синій
	"A": Color(0.68, 0.45, 0.92),    ## фіолетовий
	"S": Color(0.96, 0.62, 0.24),    ## помаранчевий
	"SS": Color(0.98, 0.85, 0.35),   ## золотий
}
const NO_GRADE := Color(0.55, 0.57, 0.55)
## Гроші грейду не мають, а сірими виглядають як сміття.
const MONEY_COLOR := Color(0.95, 0.82, 0.35)

## Темніша заливка тієї самої барви: обрис лишається чистим кольором
## грейду, а нутро не сліпить.
const FILL_DIM := 0.45
const LINE := 2.0

var _shape := ""
var _tint := NO_GRADE
var _tex: Texture2D = null


static func grade_color(grade: String) -> Color:
	return GRADE_COLORS.get(grade, NO_GRADE)


## Малюнок речі за точною назвою (`data/items.json`) або `null`, коли
## його ще не намальовано. Для місць, яким сам `ItemIcon`-вузол
## завеликий — панель 1-7 показує лише текстуру, без форми й рамки.
static func of(name: String) -> Texture2D:
	_load_art()
	return _art.get(name)


## Читає теку раз за життя гри — не за кожен показ речі.
static func _load_art() -> void:
	if _art_loaded:
		return
	_art_loaded = true
	var dir := DirAccess.open(ART_DIR)
	if dir == null:
		return
	for file in dir.get_files():
		if file.get_extension() != "png":
			continue
		var tex := load(ART_DIR + file) as Texture2D
		if tex != null:
			_art[file.get_basename()] = tex


## Що малювати. `slot` порожній у складаних речей — тоді вирішує `kind`.
func shape_of(kind: String, slot: String) -> String:
	if slot != "":
		return "перстень" if slot.begins_with("перстень") else slot
	return kind


## `name` — точна назва речі (`data/items.json`); порожня там, де
## малюнок не потрібен (порожній силует тіла).
func show_item(kind: String, slot: String, grade: String,
		name: String = "") -> void:
	_load_art()
	_shape = shape_of(kind, slot)
	_tint = MONEY_COLOR if kind == "гроші" else grade_color(grade)
	_tex = _art.get(name)
	queue_redraw()


func clear_item() -> void:
	_shape = ""
	_tex = null
	queue_redraw()


func _draw() -> void:
	if _shape == "":
		return
	# Малюємо в квадраті 0..1 і множимо на бік — тоді ті самі числа
	# годяться і для комірки тіла, і для торби, і для майбутніх розмірів.
	var side: float = minf(size.x, size.y)
	var off := Vector2((size.x - side) * 0.5, (size.y - side) * 0.5)
	if _tex != null:
		draw_texture_rect(_tex, Rect2(off, Vector2(side, side)), false)
		draw_rect(Rect2(off, Vector2(side, side)), _tint, false, LINE)
		return
	var fill := Color(_tint.r * FILL_DIM, _tint.g * FILL_DIM,
			_tint.b * FILL_DIM, 0.95)
	match _shape:
		"зброя": _sword(side, off, fill)
		"голова": _helmet(side, off, fill)
		"тіло": _armour(side, off, fill)
		"ремінь": _belt(side, off, fill)
		"рукавиці": _glove(side, off, fill)
		"взуття": _boot(side, off, fill)
		"щит": _shield(side, off, fill)
		"підвіска": _amulet(side, off, fill)
		"перстень": _ring(side, off, fill)
		"руна": _rune(side, off, fill)
		"витратне": _crystal(side, off, fill)
		"ресурс": _lump(side, off, fill)
		"гроші": _coins(side, off, fill)
		_: _lump(side, off, fill)


## Замкнена фігура: заливка темнішим, обрис кольором грейду.
func _figure(points: PackedVector2Array, fill: Color) -> void:
	draw_colored_polygon(points, fill)
	var loop := points.duplicate()
	loop.append(points[0])
	draw_polyline(loop, _tint, LINE, true)


## Точка в частках сторони: (0,0) — лівий верх значка, (1,1) — правий низ.
func _at(side: float, off: Vector2, x: float, y: float) -> Vector2:
	return off + Vector2(x * side, y * side)


func _sword(s: float, o: Vector2, fill: Color) -> void:
	# Клинок вістрям угору, гарда впоперек, руків'я вниз.
	_figure(PackedVector2Array([
			_at(s, o, 0.50, 0.06), _at(s, o, 0.60, 0.22),
			_at(s, o, 0.60, 0.62), _at(s, o, 0.40, 0.62),
			_at(s, o, 0.40, 0.22)]), fill)
	draw_line(_at(s, o, 0.24, 0.64), _at(s, o, 0.76, 0.64), _tint, LINE + 1.0)
	draw_line(_at(s, o, 0.50, 0.64), _at(s, o, 0.50, 0.92), _tint, LINE + 1.0)


func _helmet(s: float, o: Vector2, fill: Color) -> void:
	# Купол із прорізом для очей.
	_figure(PackedVector2Array([
			_at(s, o, 0.18, 0.80), _at(s, o, 0.18, 0.44),
			_at(s, o, 0.30, 0.20), _at(s, o, 0.70, 0.20),
			_at(s, o, 0.82, 0.44), _at(s, o, 0.82, 0.80),
			_at(s, o, 0.66, 0.80), _at(s, o, 0.66, 0.58),
			_at(s, o, 0.34, 0.58), _at(s, o, 0.34, 0.80)]), fill)


func _armour(s: float, o: Vector2, fill: Color) -> void:
	# Кіраса: плечі ширші за пояс.
	_figure(PackedVector2Array([
			_at(s, o, 0.30, 0.18), _at(s, o, 0.70, 0.18),
			_at(s, o, 0.86, 0.30), _at(s, o, 0.76, 0.44),
			_at(s, o, 0.74, 0.84), _at(s, o, 0.26, 0.84),
			_at(s, o, 0.24, 0.44), _at(s, o, 0.14, 0.30)]), fill)


func _belt(s: float, o: Vector2, fill: Color) -> void:
	_figure(PackedVector2Array([
			_at(s, o, 0.08, 0.40), _at(s, o, 0.92, 0.40),
			_at(s, o, 0.92, 0.60), _at(s, o, 0.08, 0.60)]), fill)
	# Пряжка.
	draw_rect(Rect2(_at(s, o, 0.42, 0.34), Vector2(s * 0.16, s * 0.32)),
			_tint, false, LINE)


func _glove(s: float, o: Vector2, fill: Color) -> void:
	# Долоня з відставленим великим пальцем.
	_figure(PackedVector2Array([
			_at(s, o, 0.34, 0.16), _at(s, o, 0.68, 0.16),
			_at(s, o, 0.68, 0.44), _at(s, o, 0.86, 0.50),
			_at(s, o, 0.80, 0.66), _at(s, o, 0.68, 0.62),
			_at(s, o, 0.68, 0.86), _at(s, o, 0.34, 0.86)]), fill)


func _boot(s: float, o: Vector2, fill: Color) -> void:
	_figure(PackedVector2Array([
			_at(s, o, 0.34, 0.12), _at(s, o, 0.60, 0.12),
			_at(s, o, 0.60, 0.60), _at(s, o, 0.86, 0.72),
			_at(s, o, 0.86, 0.88), _at(s, o, 0.34, 0.88)]), fill)


func _shield(s: float, o: Vector2, fill: Color) -> void:
	_figure(PackedVector2Array([
			_at(s, o, 0.18, 0.14), _at(s, o, 0.82, 0.14),
			_at(s, o, 0.82, 0.56), _at(s, o, 0.50, 0.90),
			_at(s, o, 0.18, 0.56)]), fill)


func _amulet(s: float, o: Vector2, fill: Color) -> void:
	# Ланцюжок і крапля.
	draw_line(_at(s, o, 0.24, 0.16), _at(s, o, 0.50, 0.48), _tint, LINE)
	draw_line(_at(s, o, 0.76, 0.16), _at(s, o, 0.50, 0.48), _tint, LINE)
	_figure(PackedVector2Array([
			_at(s, o, 0.50, 0.42), _at(s, o, 0.70, 0.64),
			_at(s, o, 0.50, 0.90), _at(s, o, 0.30, 0.64)]), fill)


func _ring(s: float, o: Vector2, fill: Color) -> void:
	var middle: Vector2 = _at(s, o, 0.50, 0.58)
	draw_circle(middle, s * 0.26, fill)
	draw_arc(middle, s * 0.26, 0.0, TAU, 32, _tint, LINE, true)
	draw_arc(middle, s * 0.14, 0.0, TAU, 24, _tint, LINE, true)
	# Камінь угорі.
	_figure(PackedVector2Array([
			_at(s, o, 0.50, 0.10), _at(s, o, 0.64, 0.24),
			_at(s, o, 0.50, 0.38), _at(s, o, 0.36, 0.24)]), fill)


func _rune(s: float, o: Vector2, fill: Color) -> void:
	# Стояча плитка з різьбленим знаком. Була шестикутником — і на
	# знімку не відрізнялась від грудки ресурсу, бо та теж шестикутна.
	_figure(PackedVector2Array([
			_at(s, o, 0.28, 0.10), _at(s, o, 0.72, 0.10),
			_at(s, o, 0.72, 0.78), _at(s, o, 0.50, 0.92),
			_at(s, o, 0.28, 0.78)]), fill)
	draw_line(_at(s, o, 0.50, 0.22), _at(s, o, 0.50, 0.70), _tint, LINE)
	draw_line(_at(s, o, 0.50, 0.40), _at(s, o, 0.66, 0.26), _tint, LINE)
	draw_line(_at(s, o, 0.50, 0.56), _at(s, o, 0.34, 0.42), _tint, LINE)


func _crystal(s: float, o: Vector2, fill: Color) -> void:
	_figure(PackedVector2Array([
			_at(s, o, 0.50, 0.08), _at(s, o, 0.76, 0.38),
			_at(s, o, 0.64, 0.90), _at(s, o, 0.36, 0.90),
			_at(s, o, 0.24, 0.38)]), fill)
	draw_line(_at(s, o, 0.50, 0.08), _at(s, o, 0.50, 0.90), _tint, LINE)


func _lump(s: float, o: Vector2, fill: Color) -> void:
	# Безформна грудка: кора, шкура, павутина, кістка. Кутів вісім і всі
	# різні — саме безформність і відрізняє її від рівної руни.
	_figure(PackedVector2Array([
			_at(s, o, 0.16, 0.46), _at(s, o, 0.30, 0.22),
			_at(s, o, 0.55, 0.14), _at(s, o, 0.74, 0.26),
			_at(s, o, 0.88, 0.48), _at(s, o, 0.80, 0.72),
			_at(s, o, 0.54, 0.88), _at(s, o, 0.26, 0.74)]), fill)


func _coins(s: float, o: Vector2, fill: Color) -> void:
	for place: Array in [[0.36, 0.62], [0.64, 0.62], [0.50, 0.38]]:
		var middle: Vector2 = _at(s, o, place[0], place[1])
		draw_circle(middle, s * 0.20, fill)
		draw_arc(middle, s * 0.20, 0.0, TAU, 28, _tint, LINE, true)
