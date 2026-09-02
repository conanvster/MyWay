class_name HUD
extends CanvasLayer
## Те, що бачить гравець поверх світу (крок 1.3).
##
## Досі гра не показувала нічого: ні свого здоров'я, ні здоров'я цілі, ні
## відкатів, ні черги, а повідомлення йшли в консоль. Без цього вміння
## (крок 2) не було б на чому ні відчути, ні налагодити.
##
## Будується кодом, а не сценою: .tscn для такої кількості дрібних вузлів
## руками не пишеться, а редактором його однаково довелося б перебирати
## після кожної зміни панелі (П-58).
##
## HUD нічого не вирішує і нікуди не шле — тільки показує те, що надіслав
## сервер (П-08).

const WIDE := 260.0        ## ширина смуг здоров'я
const CELL := 56.0         ## сторона комірки панелі
const GAP := 6.0
const MESSAGES := 5        ## скільки повідомлень тримати на екрані
const MESSAGE_TIME := 6.0
const FLOAT_TIME := 1.1    ## скільки летить число шкоди
const FLOAT_RISE := 46.0

const BACK := Color(0, 0, 0, 0.55)
const HP_COLOR := Color(0.72, 0.21, 0.18)
const MP_COLOR := Color(0.24, 0.42, 0.76)
const TARGET_COLOR := Color(0.78, 0.62, 0.22)
const CAST_COLOR := Color(0.35, 0.55, 0.85)
const RESPECT_COLOR := Color(0.55, 0.72, 0.35)

## Колір імені за різницею рівнів (погоджено 02.09.2026).
##
## Це не прикраса: з одного погляду має бути видно, по кому ти влучиш, а
## від кого краще піти. Різниця рахується як «рівень цілі мінус мій».
##
##   -6 і нижче   темно-синій    нічого не дасть
##   -5 .. -3     голубий        легкий
##   -2 ..  2     білий          рівня
##    3 ..  4     помаранчовий   уже небезпечний
##    5 ..  6     червоний       дуже небезпечний
##    7 і вище    яскраво-червоний  не чіпай
static func level_color(diff: int) -> Color:
	if diff >= 7:
		return Color(1.0, 0.12, 0.10)
	if diff >= 5:
		return Color(0.88, 0.26, 0.20)
	if diff >= 3:
		return Color(1.0, 0.64, 0.20)
	if diff >= -2:
		return Color(1, 1, 1)
	if diff >= -5:
		return Color(0.45, 0.76, 1.0)
	return Color(0.24, 0.38, 0.82)


var _world: Node
## Скільки в кого здоров'я всього: сервер шле це, коли істота з'являється.
var _max_hp: Dictionary = {}
var _hp: Dictionary = {}
var _target := 0
var _bar: Array[String] = []

var _root: Control
var _hp_fill: ColorRect
var _mp_fill: ColorRect
var _vitals_text: Label
var _target_box: Control
var _target_name: Label
var _target_fill: ColorRect
var _queue_text: Label
var _cast_box: Control
var _cast_fill: ColorRect
var _cast_text: Label
var _respect_fill: ColorRect
var _level_text: Label
var _cast_left := 0.0
var _cast_full := 0.0
var _messages: VBoxContainer
var _cells: Array = []
var _floats: Array = []


func setup(world: Node) -> void:
	_world = world
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_vitals()
	_build_target()
	_build_panel()
	_build_cast()
	_build_messages()
	_build_dead()
	_build_menu()
	_build_stats()
	_build_skills()
	_build_things()
	_build_talk()
	_build_shop()


# ── збирання ──────────────────────────────────────────────────────────

func _plate(size: Vector2, color: Color, parent: Control) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.size = size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect


func _text(size: int, parent: Control) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


## Вікно смерті.
##
## Досі труп гравця лежав **двадцять хвилин** і підводився сам (П-69):
## гра після смерті просто спинялась, і зробити з цим не можна було
## нічого. Кнопка не міняє правил — вона робить те саме, що зробив би
## строк, тільки одразу.
signal wants_revive

var _dead_box: Control


func _build_dead() -> void:
	_dead_box = Control.new()
	_dead_box.name = "ВікноСмерті"
	_dead_box.set_anchors_preset(Control.PRESET_CENTER)
	_dead_box.position = Vector2(-170, -80)
	_dead_box.visible = false
	_root.add_child(_dead_box)

	_plate(Vector2(340, 150), Color(0, 0, 0, 0.78), _dead_box)
	var title := _text(26, _dead_box)
	title.text = "Тебе вбито"
	title.position = Vector2(0, 22)
	title.size.x = 340
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var lost := _text(15, _dead_box)
	lost.text = "повага втрачена, речі могли випасти"
	lost.position = Vector2(0, 60)
	lost.size.x = 340
	lost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lost.modulate = Color(0.85, 0.8, 0.75)

	var press := Button.new()
	press.name = "ВМісто"
	press.text = "Повернутися в місто"
	press.position = Vector2(50, 96)
	press.custom_minimum_size = Vector2(240, 38)
	press.size = Vector2(240, 38)
	press.pressed.connect(func() -> void: wants_revive.emit())
	_dead_box.add_child(press)


func died() -> void:
	if _dead_box != null:
		_dead_box.visible = true
		# Кнопку треба МОЖНА натиснути: показ загалом миші не ловить
		# (`MOUSE_FILTER_IGNORE` на корені), і без цього вікно було б
		# намальоване, але мертве.
		_root.mouse_filter = Control.MOUSE_FILTER_PASS


func revived() -> void:
	if _dead_box != null:
		_dead_box.visible = false
		_root.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Меню внизу праворуч: вийти й подивитись стати.
##
## Миша до показу доходить лише там, де вона потрібна: корінь показу
## наскрізний (`MOUSE_FILTER_IGNORE`), інакше клік по землі перестав би
## працювати взагалі. Тому кнопки живуть у своєму вузлі, і саме він
## мишу ловить.
var _menu_box: Control


func _build_menu() -> void:
	_menu_box = Control.new()
	_menu_box.name = "Меню"
	_menu_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_menu_box.position = Vector2(-460, -46)
	_menu_box.mouse_filter = Control.MOUSE_FILTER_PASS
	_root.add_child(_menu_box)

	var buttons := [["Стати", _toggle_stats], ["Скіли", _toggle_skills],
			["Речі", _toggle_things], ["Вийти", _quit]]
	for i in buttons.size():
		var press := Button.new()
		press.text = str(buttons[i][0])
		press.position = Vector2(i * 112, 0)
		press.size = Vector2(104, 32)
		press.pressed.connect(buttons[i][1])
		_menu_box.add_child(press)


## Виходимо тим самим шляхом, що й закриття вікна: сервер побачить
## від'єднання і збереже персонажа сам (`_on_left`).
func _quit() -> void:
	_world.get_tree().quit()


## Вікно «Стати».
##
## Перша спроба була одним написом на дванадцять рядків, і він налазив на
## кнопки в куті. Друга стала стовпчиком «назва … число» — краще, але
## групи в ній нічим не відділялись, і вікно жило власним життям: ні
## заголовка, ні хрестика, ні змоги відсунути. Тепер це така сама
## `WindowBox`, як «Речі» й «Скіли» (рішення замовника 03.09.2026), а
## групи розділені смужкою, а не самим лише повітрям.
## Висота рахована під вміст, не на око: 26 на «хто це» плюс 13 рядків
## по 21 плюс три смужки по 14 = 341. На 330 останній рядок наполовину
## вилазив за край вікна.
const STATS_INNER := Vector2(248, 344)

## Скільки місця на групу: рядок і повітря під смужкою.
const STAT_ROW := 21.0
const STAT_GAP := 14.0

var _stats_box: WindowBox
var _stats_fields: Dictionary = {}
var _stats_who: Label


func _build_stats() -> void:
	_stats_box = WindowBox.new()
	_stats_box.name = "СторінкаСтатів"
	_stats_box.setup("Стати", STATS_INNER)
	_stats_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_stats_box.position = Vector2(-_stats_box.size.x - 24,
			-_stats_box.size.y - 52)
	_root.add_child(_stats_box)
	var page: Control = _stats_box.body

	_stats_who = _text(12, page)
	_stats_who.name = "Хто"
	_stats_who.text = "—"
	_stats_who.modulate = Color(0.72, 0.76, 0.68)

	var at := 26.0
	var groups: Array = [
			["рівень", "вільних очок"],
			["сила", "спритність", "витривалість", "інтелект", "чуття"],
			["здоров'я", "мана"],
			["фіз. атака", "маг. атака", "фіз. захист", "маг. захист"]]
	for group_at in groups.size():
		for field: String in groups[group_at]:
			var name_text := _text(13, page)
			name_text.text = field
			name_text.position = Vector2(2, at)
			name_text.modulate = Color(0.78, 0.8, 0.76)
			var value := _text(13, page)
			value.name = field
			value.text = "—"
			value.position = Vector2(STATS_INNER.x - 98, at)
			value.size = Vector2(96, 18)
			value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			_stats_fields[field] = value
			at += STAT_ROW
		# Смужка між групами: саме повітря око не розділяє, і чотири
		# групи читались як один довгий стовпчик.
		if group_at < groups.size() - 1:
			var line := _plate(Vector2(STATS_INNER.x, 1),
					Color(0.28, 0.29, 0.27, 0.7), page)
			line.position = Vector2(0, at + STAT_GAP * 0.5)
			at += STAT_GAP


func _toggle_stats() -> void:
	if _stats_box != null:
		_stats_box.toggle()


## Стати від сервера. Клієнт їх не рахує — тільки показує (П-08).
func set_stats(data: Dictionary) -> void:
	if _stats_box == null:
		return
	_stats_who.text = "%s, %s" % [str(data.get("раса", "?")),
			str(data.get("стать", "?"))]
	_put("рівень", "%d" % int(data.get("рівень", 1)))
	_put("вільних очок", "%d" % int(data.get("очки", 0)))
	# Чинне значення, а в дужках базове — коли спорядження чи баф їх
	# зсунули. Так одразу видно, що твоє власне, а що від речей.
	for field in ["сила", "спритність", "витривалість", "інтелект", "чуття"]:
		var now: int = int(data.get(field, 0))
		var base: int = int(data.get(field + " базова", now))
		_put(field, "%d" % now if base == now else "%d  (%d)" % [now, base],
				Color(1, 1, 1) if base == now else Color(0.62, 0.88, 0.62))
	_put("здоров'я", "%d" % int(data.get("здоров'я", 0)))
	_put("мана", "%d" % int(data.get("мана", 0)))
	_put("фіз. атака", "%.1f" % float(data.get("атака", 0.0)))
	_put("маг. атака", "%.1f" % float(data.get("магічна атака", 0.0)))
	_put("фіз. захист", "%.1f" % float(data.get("захист", 0.0)))
	_put("маг. захист", "%.1f" % float(data.get("магічний захист", 0.0)))


func _put(field: String, value: String, tint: Color = Color(1, 1, 1)) -> void:
	var label: Label = _stats_fields.get(field)
	if label != null:
		label.text = value
		label.modulate = tint


## Вікно «Скіли»: усе вивчене, звідки скіл тягнуть мишею на панель.
##
## Навіщо. Розкладка 1–7 досі бралась із `data/bar.json` і була однакова
## в усіх, а замовник хоче класти під себе. Тягнути мишею — найкоротший
## шлях: не треба ні команд, ні вікна налаштувань.
##
## Панель зберігається в базі разом із персонажем, тож розкладка переживає
## вихід із гри.
signal wants_slot(where: int, action: String)
signal wants_slot_used(where: int)

const SKILLS_COLUMNS := 1
## Скільки місця під заголовком: підказка про перетягування.
const SKILLS_TOP := 22.0
const SKILLS_WIDE := 250.0

var _skills_box: WindowBox
var _skills_grid: GridContainer
var _skills: Array = []


func _build_skills() -> void:
	_skills_box = WindowBox.new()
	_skills_box.name = "ВікноСкілів"
	_skills_box.setup("Скіли", Vector2(SKILLS_WIDE, SKILLS_TOP))
	# Праворуч УГОРІ, попід самим краєм. «Стати» стоять праворуч унизу й
	# займають 398 точок з 648 — тобто на найменшому вікні гри між ними
	# лишається рівно стільки місця, скільки лишається. На 96 від верху
	# вікна накривали одне одного заголовками, на 8 — розходяться.
	_skills_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_skills_box.position = Vector2(-_skills_box.size.x - 24, 8)
	_root.add_child(_skills_box)
	var page: Control = _skills_box.body

	var hint := _text(11, page)
	hint.name = "Підказка"
	hint.text = "тягни скіл на комірку 1–7"
	hint.modulate = Color(0.72, 0.76, 0.68)

	_skills_grid = GridContainer.new()
	_skills_grid.name = "Сітка"
	_skills_grid.columns = SKILLS_COLUMNS
	_skills_grid.position = Vector2(0, SKILLS_TOP)
	_skills_grid.add_theme_constant_override("h_separation", 6)
	_skills_grid.add_theme_constant_override("v_separation", 6)
	page.add_child(_skills_grid)


func _toggle_skills() -> void:
	if _skills_box != null:
		_skills_box.toggle()


## Що вміє гравець — приходить від сервера.
func set_skills(list: Array) -> void:
	_skills = list
	if _skills_grid == null:
		return
	for old_cell in _skills_grid.get_children():
		_skills_grid.remove_child(old_cell)
		old_cell.queue_free()
	for row: Dictionary in list:
		var cell := SkillCell.new()
		cell.setup(str(row.get("ключ", "")), str(row.get("назва", "?")),
				"%s · рівень %d з %d · %d мани · %.0f м"
						% [str(row.get("грейд", "E")),
						   int(row.get("рівень", 1)),
						   int(row.get("рівнів", 1)),
						   int(row.get("мана", 0)),
						   float(row.get("дальність", 0.0))])
		_skills_grid.add_child(cell)
	# Вікно росте під кількість скілів: порожній чорний прямокутник на пів
	# екрана виглядав так, ніби воно не догрузилось. Перебудова оболонки
	# дешевша за окреме «змінити розмір»: вікон три, а скіли міняються
	# рідко — на руну чи на рівень.
	_skills_box.resize(Vector2(SKILLS_WIDE,
			SKILLS_TOP + list.size() * (SkillCell.HIGH + 6.0)))


## Кинули щось на комірку панелі.
##
## Тягли з іншої комірки — міняємо місцями: інакше «перекласти» означало б
## «загубити те, що там лежало».
func _on_dropped(where: int, action: String, from: int) -> void:
	if from >= 0 and from != where:
		var was: String = _bar[where] if where < _bar.size() else ""
		wants_slot.emit(from, was)
	wants_slot.emit(where, action)


## Вікно «Речі»: паперова лялька зі слотами навколо силуету, торба сіткою.
##
## Спершу слоти були переліком рядків «голова —», «підвіска —»; замовник
## назвав це незручним, і слушно: перелік однаково довгий незалежно від
## того, що вдягнено, і щоб знайти зброю, його треба ЧИТАТИ. На ляльці
## зброя завжди в одному місці — ліворуч від силуету, — тож її видно, не
## читаючи жодного слова. Так зроблено в L2 і D2, і обране замовником
## 03.09.2026.
##
## Річ у комірці показує значок (`item_icon.gd`): форма каже, що це,
## колір — грейд. Назва лишається в підказці, бо в комірку 54 точки вона
## однаково не влазить, а на значок вистачає одного погляду.
##
## Гроші винесені зовсім окремо: вони не річ, їх не вдягнути й не
## викинути по одній, і в сітці торби вони лише займали б комірку.
signal wants_wear(at: int, slot: String)
signal wants_take_off(slot: String)
signal wants_use(name: String)

## Комірка — квадрат і в тілі, і в торбі: дві різні мови в одному вікні
## читаються гірше за одну.
const CELL_SIDE := 54.0
const CELL_GAP := 6.0
const ICON_SIDE := 40.0
## Підпис слота під коміркою тіла: порожню комірку інакше не назвати.
const CAPTION_H := 14.0
const BODY_ROW := CELL_SIDE + CAPTION_H

## Сітка торби.
const BAG_COLUMNS := 5
const BAG_ROWS := 6

## Ширина силуету між двома стовпчиками слотів.
const DOLL_WIDE := 100.0

const PANEL := Color(0.07, 0.07, 0.09, 0.92)
const CELL_EMPTY := Color(0.13, 0.13, 0.15, 0.9)
const CELL_FULL := Color(0.18, 0.20, 0.17, 0.95)
const CAPTION_COLOR := Color(0.55, 0.57, 0.54)

## Де на ляльці стоїть кожен слот: стовпчик і ряд.
##
## Ліворуч те, що в руках і на руках, праворуч — щит і те, що носять на
## собі. Порядок не випадковий: у бою дивишся ліворуч, бо там зброя.
const DOLL_PLACES := {
	"голова": ["центр", -1],
	"зброя": ["ліво", 0],
	"щит": ["право", 0],
	"рукавиці": ["ліво", 1],
	"підвіска": ["право", 1],
	"ремінь": ["ліво", 2],
	"взуття": ["право", 2],
	"перстень-1": ["ліво", 3],
	"перстень-2": ["право", 3],
}

var _things_box: WindowBox
var _body_cells: Dictionary = {}
var _bag_cells: Array = []
var _money_text: Label


## Вигляд комірки: рамка й тло замість типової кнопки Godot.
##
## Без цього порожня комірка не малюється взагалі — на знімку торба
## виглядала як чорна діра. А комірка мусить бути видно навіть порожньою:
## саме порожні й кажуть, скільки ще влізе.
func _cell_look(press: Button, filled: bool) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = CELL_FULL if filled else CELL_EMPTY
	box.set_border_width_all(1)
	box.border_color = Color(0.32, 0.33, 0.3, 0.9) if filled \
			else Color(0.22, 0.22, 0.24, 0.9)
	box.set_corner_radius_all(3)
	var lit := box.duplicate()
	lit.bg_color = box.bg_color.lightened(0.12)
	lit.border_color = Color(0.62, 0.66, 0.5)
	for state in ["normal", "disabled"]:
		press.add_theme_stylebox_override(state, box)
	for state in ["hover", "pressed", "focus"]:
		press.add_theme_stylebox_override(state, lit)


## Комірка зі значком усередині. Значок миші не ловить — інакше натиск по
## самій речі не доходив би до кнопки, тобто вдягнути можна було б лише
## повз річ.
func _make_cell(parent: Control, at: Vector2, box: Vector2,
		icon_side: float = ICON_SIDE) -> Dictionary:
	var press := Button.new()
	press.position = at
	press.size = box
	press.custom_minimum_size = box
	_cell_look(press, false)
	parent.add_child(press)

	var icon := ItemIcon.new()
	icon.size = Vector2(icon_side, icon_side)
	icon.position = (box - icon.size) * 0.5
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	press.add_child(icon)

	var count := _text(11, press)
	count.position = Vector2(4, box.y - 18)
	count.size = Vector2(box.x - 8, 14)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.text = ""
	return {"press": press, "icon": icon, "count": count}


func _build_things() -> void:
	var body_wide := CELL_SIDE * 2.0 + DOLL_WIDE + CELL_GAP * 2.0
	var body_high := BODY_ROW * 5.0 + CELL_GAP * 4.0
	var bag_wide := BAG_COLUMNS * CELL_SIDE + (BAG_COLUMNS - 1) * CELL_GAP
	var bag_high := BAG_ROWS * CELL_SIDE + (BAG_ROWS - 1) * CELL_GAP
	var inner := Vector2(body_wide + 24.0 + bag_wide,
			18.0 + maxf(body_high, bag_high) + 12.0 + 30.0)

	_things_box = WindowBox.new()
	_things_box.name = "ВікноРечей"
	# Якір і місце — ДО додавання в дерево. Якщо навпаки, відступи
	# рахуються від уже відомого розміру батька і вікно виїжджає на
	# середину екрана: саме так і сталось на першому знімку.
	_things_box.setup("Речі", inner)
	_things_box.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_things_box.position = Vector2(24, -_things_box.size.y * 0.5)
	_root.add_child(_things_box)
	var page: Control = _things_box.body

	var left := _text(11, page)
	left.text = "на тілі"
	left.modulate = CAPTION_COLOR
	var right := _text(11, page)
	right.text = "торба"
	right.position = Vector2(body_wide + 24.0, 0)
	right.modulate = CAPTION_COLOR

	# Силует посередині — це й є комірка «тіло»: кіраса надягається саме
	# на нього. Окрема маленька комірка поверх силуету виглядала як
	# помилка малювання, і замовник це побачив на першому ж знімку.
	var doll_x := CELL_SIDE + CELL_GAP
	var doll_y := 18.0 + BODY_ROW + CELL_GAP
	var doll_high := body_high - BODY_ROW - CELL_GAP

	var columns := {
		"ліво": 0.0,
		"центр": doll_x + (DOLL_WIDE - CELL_SIDE) * 0.5,
		"право": doll_x + DOLL_WIDE + CELL_GAP,
	}
	for slot: String in ItemBook.BODY_SLOTS:
		var at: Vector2
		var box := Vector2(CELL_SIDE, CELL_SIDE)
		var icon_side := ICON_SIDE
		if slot == "тіло":
			at = Vector2(doll_x, doll_y)
			box = Vector2(DOLL_WIDE, doll_high)
			icon_side = DOLL_WIDE * 0.8
		else:
			var place: Array = DOLL_PLACES[slot]
			at = Vector2(float(columns[str(place[0])]),
					18.0 + float(int(place[1]) + 1) * (BODY_ROW + CELL_GAP))
		var cell := _make_cell(page, at, box, icon_side)
		# Ім'я вузла — сам слот: за ним його знаходять проби.
		cell["press"].name = slot
		cell["press"].pressed.connect(
				func() -> void: wants_take_off.emit(slot))
		var caption := _text(9, page)
		caption.text = slot
		caption.position = Vector2(at.x, at.y + box.y + 1)
		caption.size = Vector2(box.x, CAPTION_H)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.modulate = CAPTION_COLOR
		_body_cells[slot] = cell

	# Праворуч — сітка. Порожні комірки лишаються на місці: так видно,
	# скільки ще влізе, а речі не стрибають по вікну після кожної здобичі.
	for i in BAG_COLUMNS * BAG_ROWS:
		var at := Vector2(
				body_wide + 24.0 + (i % BAG_COLUMNS) * (CELL_SIDE + CELL_GAP),
				18.0 + int(i / BAG_COLUMNS) * (CELL_SIDE + CELL_GAP))
		_bag_cells.append(_make_cell(page, at,
				Vector2(CELL_SIDE, CELL_SIDE)))

	# Гроші — окремим рядком унизу, як просив замовник.
	var purse := _plate(Vector2(inner.x, 30), Color(0.16, 0.14, 0.08, 0.95),
			page)
	purse.position = Vector2(0, inner.y - 30)
	var coins := ItemIcon.new()
	coins.size = Vector2(22, 22)
	coins.position = Vector2(6, inner.y - 26)
	coins.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(coins)
	coins.show_item("гроші", "", "")
	_money_text = _text(15, page)
	_money_text.name = "Гроші"
	_money_text.text = "гроші: 0"
	_money_text.position = Vector2(34, inner.y - 25)
	_money_text.modulate = Color(0.95, 0.85, 0.45)


func _toggle_things() -> void:
	if _things_box != null:
		_things_box.toggle()


## Відкрити обидва вікна одразу. Потрібно показу (`--демо --вікна`): без
## цього їх нічим відкрити, бо рук у показу немає, і на жоден знімок вони
## не потрапляють — саме тому вигляд вікна речей і прожив непобаченим.
func show_windows() -> void:
	if _things_box != null:
		_things_box.visible = true
	if _stats_box != null:
		_stats_box.visible = true


## Що в торбі — приходить від сервера.
func set_things(things: Array, stacks: Array) -> void:
	if _things_box == null:
		return
	_things = things
	_stacks = stacks
	_fill_body(things)
	_fill_bag(things, stacks)
	# Вікно торгівлі показує ту саму торбу. Продав річ — і вона зникає
	# звідти теж, без перевідкривання прилавка.
	if _shop_box != null and _shop_box.visible:
		_fill_mine()


func _fill_body(things: Array) -> void:
	var worn := {}
	for row: Dictionary in things:
		if bool(row.get("вдягнене", false)):
			worn[str(row.get("де", row.get("слот", "")))] = row
	for slot: String in ItemBook.BODY_SLOTS:
		var cell: Dictionary = _body_cells[slot]
		var press: Button = cell["press"]
		var icon: ItemIcon = cell["icon"]
		var row: Dictionary = worn.get(slot, {})
		if row.is_empty():
			# Порожній силует лишається видно блідим: без нього лялька
			# розсипається на два стовпчики квадратів.
			if slot == "тіло":
				icon.modulate = Color(1, 1, 1, 0.28)
				icon.show_item("обладунок", "тіло", "E")
			else:
				icon.clear_item()
			press.tooltip_text = "%s: порожньо" % slot
			press.disabled = true
			_cell_look(press, false)
		else:
			icon.modulate = Color(1, 1, 1, 1)
			icon.show_item(str(row.get("вид", "")), slot,
					str(row.get("грейд", "E")))
			press.tooltip_text = "%s\n%s\n%s\nнатисни, щоб зняти" % [
					str(row["назва"]), slot, str(row.get("стати", ""))]
			press.disabled = false
			_cell_look(press, true)


func _fill_bag(things: Array, stacks: Array) -> void:
	var rows: Array = []
	for row: Dictionary in things:
		if not bool(row.get("вдягнене", false)):
			rows.append(row)
	for row: Dictionary in stacks:
		# Гроші — не річ: їм окремий рядок унизу.
		if str(row.get("назва", "")) == "гроші":
			_money_text.text = "гроші: %d" % int(row.get("скільки", 0))
			continue
		rows.append(row)

	for i in _bag_cells.size():
		var cell: Dictionary = _bag_cells[i]
		var press: Button = cell["press"]
		var icon: ItemIcon = cell["icon"]
		var count: Label = cell["count"]
		# Старий зв'язок знімаємо руками. `CONNECT_ONE_SHOT` тут не
		# годиться: якщо сервер відмовить (щит при дворучній), оновлення
		# не прийде, і комірка лишиться мертвою назавжди.
		for link in press.pressed.get_connections():
			press.pressed.disconnect(link["callable"])
		if i >= rows.size():
			icon.clear_item()
			count.text = ""
			press.tooltip_text = ""
			press.disabled = true
			_cell_look(press, false)
			continue
		var row: Dictionary = rows[i]
		var name: String = str(row.get("назва", "?"))
		press.disabled = false
		_cell_look(press, true)
		icon.show_item(str(row.get("вид", "")), str(row.get("слот", "")),
				str(row.get("грейд", "")))
		if row.has("номер"):
			var at: int = int(row["номер"])
			var places: Array = row.get("комірки", [])
			count.text = ""
			press.tooltip_text = "%s\n%s\n%s\n%s" % [name,
					"·".join(PackedStringArray(places)) if not places.is_empty()
							else "не вдягається",
					str(row.get("стати", "")),
					"натисни, щоб вдягти" if not places.is_empty() else ""]
			if places.is_empty():
				press.disabled = true
			else:
				press.pressed.connect(func() -> void:
						wants_wear.emit(at, ""))
		else:
			count.text = "×%d" % int(row.get("скільки", 0))
			var useful: bool = bool(row.get("придатна", false))
			press.tooltip_text = "%s ×%d\n%s" % [name,
					int(row.get("скільки", 0)),
					"натисни, щоб ужити" if useful else "просто лежить"]
			press.disabled = not useful
			if useful:
				press.pressed.connect(func() -> void: wants_use.emit(name))


## Розмова з мешканцем і торгівля (П-132).
##
## Мешканець відкривається тією самою дією, якою б'ють монстра: вибрав,
## підійшов, «удар». Замість шкоди приходить це вікно — з кнопками того,
## що він уміє. Поки вміє тільки крамар, але кнопок може стати більше, і
## тоді вікно не доведеться переробляти.
##
## Ціни ПРИ НАВЕДЕННІ, як просив замовник: не підписом під кожною коміркою
## (тоді сітка стає стіною чисел), а одним рядком унизу, що міняється,
## коли ведеш мишею. Рядок ще й каже, що саме станеться від натиску —
## «купити за 120» проти «продати за 48».
signal wants_shop(at: int)
signal wants_buy(at: int, name: String)
signal wants_sell(at: int, thing_at: int)
signal wants_sell_stack(at: int, name: String)

const TALK_INNER := Vector2(240, 96)
## Прилавок: та сама комірка, що в торбі, по чотири в ряд.
const SHOP_COLUMNS := 4
const SHOP_ROWS := 6
const HINT_H := 26.0

var _talk_box: WindowBox
var _talk_title: Label
var _talk_trade: Button
var _talk_with := -1

var _shop_box: WindowBox
var _shop_title: Label
var _shop_hint: Label
var _shop_money: Label
var _mine_cells: Array = []
var _stock_cells: Array = []
var _shop_with := -1
var _buyback := 40
## Що зараз у торбі — щоб вікно торгівлі малювало те саме, що й «Речі».
var _things: Array = []
var _stacks: Array = []


func _build_talk() -> void:
	_talk_box = WindowBox.new()
	_talk_box.name = "ВікноРозмови"
	_talk_box.setup("Розмова", TALK_INNER)
	_talk_box.set_anchors_preset(Control.PRESET_CENTER)
	_talk_box.position = -_talk_box.size * 0.5
	_root.add_child(_talk_box)
	var page: Control = _talk_box.body

	_talk_title = _text(15, page)
	_talk_title.text = "—"

	_talk_trade = Button.new()
	_talk_trade.text = "Торгувати"
	_talk_trade.position = Vector2(0, 40)
	_talk_trade.size = Vector2(TALK_INNER.x, 32)
	_talk_trade.custom_minimum_size = _talk_trade.size
	_talk_trade.pressed.connect(func() -> void:
			if _talk_with >= 0:
				wants_shop.emit(_talk_with))
	page.add_child(_talk_trade)


## Мешканця вибрано ціллю: показуємо ім'я там-таки, де ім'я монстра.
##
## Смуги здоров'я в мешканця немає й бути не повинно: він не б'ється, і
## порожня смуга обіцяла б бій, якого не буде.
func aim_resident(title: String, trades: bool) -> void:
	if _target_box == null:
		return
	if title == "":
		_target_box.visible = _target != 0
		return
	_target_box.visible = true
	_target_name.text = title + ("  ·  торгує" if trades else "")
	_target_name.modulate = Color(0.86, 0.9, 0.72)
	_target_fill.size.x = 0.0


func show_talk(at: int, title: String, trades: bool) -> void:
	if _talk_box == null:
		return
	_talk_with = at
	_talk_title.text = title
	_talk_trade.visible = trades
	_talk_box.visible = true
	_talk_box._keep_on_screen()


func _build_shop() -> void:
	var grid := Vector2(SHOP_COLUMNS * CELL_SIDE
			+ (SHOP_COLUMNS - 1) * CELL_GAP,
			SHOP_ROWS * CELL_SIDE + (SHOP_ROWS - 1) * CELL_GAP)
	var inner := Vector2(grid.x * 2.0 + 28.0,
			18.0 + grid.y + 10.0 + HINT_H + 4.0 + 26.0)

	_shop_box = WindowBox.new()
	_shop_box.name = "ВікноТоргівлі"
	_shop_box.setup("Торгівля", inner)
	_shop_box.set_anchors_preset(Control.PRESET_CENTER)
	_shop_box.position = -_shop_box.size * 0.5
	_root.add_child(_shop_box)
	var page: Control = _shop_box.body

	var mine := _text(11, page)
	mine.text = "твоє — натисни, щоб продати"
	mine.modulate = CAPTION_COLOR
	_shop_title = _text(11, page)
	_shop_title.text = "прилавок"
	_shop_title.position = Vector2(grid.x + 28.0, 0)
	_shop_title.modulate = CAPTION_COLOR

	for i in SHOP_COLUMNS * SHOP_ROWS:
		var at := Vector2((i % SHOP_COLUMNS) * (CELL_SIDE + CELL_GAP),
				18.0 + int(i / SHOP_COLUMNS) * (CELL_SIDE + CELL_GAP))
		_mine_cells.append(_make_cell(page, at,
				Vector2(CELL_SIDE, CELL_SIDE)))
		var to := at + Vector2(grid.x + 28.0, 0)
		_stock_cells.append(_make_cell(page, to,
				Vector2(CELL_SIDE, CELL_SIDE)))

	# Рядок ціни: те, заради чого все й затівалось.
	var strip := _plate(Vector2(inner.x, HINT_H),
			Color(0.13, 0.12, 0.09, 0.95), page)
	strip.position = Vector2(0, 18.0 + grid.y + 10.0)
	_shop_hint = _text(13, page)
	_shop_hint.name = "Ціна"
	_shop_hint.text = "наведи річ — покаже ціну"
	_shop_hint.position = Vector2(8, 18.0 + grid.y + 14.0)
	_shop_hint.modulate = Color(0.88, 0.86, 0.7)

	_shop_money = _text(14, page)
	_shop_money.name = "ГрошіТоргівлі"
	_shop_money.text = "гроші: 0"
	_shop_money.position = Vector2(0, inner.y - 22.0)
	_shop_money.modulate = Color(0.95, 0.85, 0.45)


func show_shop(at: int, title: String, goods: Array, buyback: int) -> void:
	if _shop_box == null:
		return
	_shop_with = at
	_buyback = buyback
	_shop_title.text = "%s — прилавок" % title
	# Частку кажемо ОДИН раз, у рядку підказки: у кожній комірці стоїть
	# уже пораховане число, і повторювати відсоток там ні до чого.
	_shop_hint.text = "наведи річ — покаже ціну · викуповує за %d%%" \
			% _buyback
	_fill_stock(goods)
	_fill_mine()
	if _talk_box != null:
		_talk_box.visible = false
	_shop_box.visible = true
	_shop_box._keep_on_screen()


func _fill_stock(goods: Array) -> void:
	for i in _stock_cells.size():
		var cell: Dictionary = _stock_cells[i]
		var press: Button = cell["press"]
		_unlink(press)
		if i >= goods.size():
			_blank(cell)
			continue
		var row: Dictionary = goods[i]
		var name: String = str(row["назва"])
		var price: int = int(row["ціна"])
		cell["icon"].modulate = Color(1, 1, 1, 1)
		cell["icon"].show_item(str(row.get("вид", "")),
				str(row.get("слот", "")), str(row.get("грейд", "")))
		cell["count"].text = ""
		press.disabled = false
		press.tooltip_text = "%s\nкупити за %d" % [name, price]
		_cell_look(press, true)
		_hover(press, "%s — купити за %d" % [name, price])
		press.pressed.connect(func() -> void:
				wants_buy.emit(_shop_with, name))


## Ліворуч — те саме, що у вікні «Речі», тільки вдягнене не показуємо:
## продати його однаково не можна, поки не знімеш.
func _fill_mine() -> void:
	var rows: Array = []
	for row: Dictionary in _things:
		if not bool(row.get("вдягнене", false)):
			rows.append(row)
	for row: Dictionary in _stacks:
		if str(row.get("назва", "")) != "гроші":
			rows.append(row)
	_shop_money.text = "гроші: %d" % _money()

	for i in _mine_cells.size():
		var cell: Dictionary = _mine_cells[i]
		var press: Button = cell["press"]
		_unlink(press)
		if i >= rows.size():
			_blank(cell)
			continue
		var row: Dictionary = rows[i]
		var name: String = str(row.get("назва", "?"))
		cell["icon"].modulate = Color(1, 1, 1, 1)
		cell["icon"].show_item(str(row.get("вид", "")),
				str(row.get("слот", "")), str(row.get("грейд", "")))
		press.disabled = false
		_cell_look(press, true)
		# Ціну викупу рахує сервер і шле разом із річчю: клієнт її не
		# знає й знати не повинен.
		var paid: int = int(row.get("продати за", 0))
		if row.has("номер"):
			var thing_at: int = int(row["номер"])
			cell["count"].text = ""
			if paid <= 0:
				press.tooltip_text = "%s\nкрамар цього не бере" % name
				press.disabled = true
				_hover(press, "%s — крамар цього не бере" % name)
				continue
			press.tooltip_text = "%s\nпродати за %d" % [name, paid]
			_hover(press, "%s — продати за %d" % [name, paid])
			press.pressed.connect(func() -> void:
					wants_sell.emit(_shop_with, thing_at))
		else:
			var count: int = int(row.get("скільки", 0))
			cell["count"].text = "×%d" % count
			if paid <= 0:
				press.tooltip_text = "%s\nкрамар цього не бере" % name
				press.disabled = true
				_hover(press, "%s — крамар цього не бере" % name)
				continue
			press.tooltip_text = "%s ×%d\nпродати весь стос за %d" \
					% [name, count, paid * count]
			_hover(press, "%s ×%d — продати весь стос за %d"
					% [name, count, paid * count])
			press.pressed.connect(func() -> void:
					wants_sell_stack.emit(_shop_with, name))


func _blank(cell: Dictionary) -> void:
	cell["icon"].clear_item()
	cell["count"].text = ""
	cell["press"].disabled = true
	cell["press"].tooltip_text = ""
	_cell_look(cell["press"], false)


## Старі зв'язки знімаємо руками — і натиску, і наведення. Прилавок
## перемальовується після кожної покупки, і без цього одна комірка
## продавала б усе, що в ній колись лежало.
func _unlink(press: Button) -> void:
	for link in press.pressed.get_connections():
		press.pressed.disconnect(link["callable"])
	for link in press.mouse_entered.get_connections():
		press.mouse_entered.disconnect(link["callable"])


func _hover(press: Button, text: String) -> void:
	press.mouse_entered.connect(func() -> void:
			if _shop_hint != null:
				_shop_hint.text = text)


func _money() -> int:
	for row: Dictionary in _stacks:
		if str(row.get("назва", "")) == "гроші":
			return int(row.get("скільки", 0))
	return 0


## Свої здоров'я й мана — ліворуч угорі.
func _build_vitals() -> void:
	var box := Control.new()
	box.position = Vector2(16, 16)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)

	_plate(Vector2(WIDE, 18), BACK, box)
	_hp_fill = _plate(Vector2(WIDE, 18), HP_COLOR, box)
	var mp_back := _plate(Vector2(WIDE, 10), BACK, box)
	mp_back.position = Vector2(0, 22)
	_mp_fill = _plate(Vector2(WIDE, 10), MP_COLOR, box)
	_mp_fill.position = Vector2(0, 22)

	_vitals_text = _text(13, box)
	_vitals_text.position = Vector2(6, 0)

	# Рівень і повага: тонка смуга під маною (крок 3).
	var respect_back := _plate(Vector2(WIDE, 6), BACK, box)
	respect_back.position = Vector2(0, 36)
	_respect_fill = _plate(Vector2(0, 6), RESPECT_COLOR, box)
	_respect_fill.position = Vector2(0, 36)
	_level_text = _text(12, box)
	_level_text.position = Vector2(0, 44)


## Рамка цілі — угорі посередині. Ховається, коли цілі немає (П-31).
func _build_target() -> void:
	_target_box = Control.new()
	_target_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_target_box.position = Vector2(-WIDE * 0.5, 16)
	_target_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_target_box.visible = false
	_root.add_child(_target_box)

	var frame := _plate(Vector2(WIDE + 8, 44), BACK, _target_box)
	frame.position = Vector2(-4, -4)
	_target_name = _text(14, _target_box)
	_plate(Vector2(WIDE, 14), Color(0.15, 0.05, 0.05, 0.9), _target_box) \
			.position = Vector2(0, 22)
	_target_fill = _plate(Vector2(WIDE, 14), TARGET_COLOR, _target_box)
	_target_fill.position = Vector2(0, 22)


## Панель 1-7 і черга дій — унизу посередині (П-20, П-38, П-58).
func _build_panel() -> void:
	var wide := CELL * 7 + GAP * 6
	var box := Control.new()
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.position = Vector2(-wide * 0.5, -CELL - 16)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)

	for i in 7:
		var at := Vector2(i * (CELL + GAP), 0)
		# Комірка ловить мишу: на неї тягнуть скіли, і по ній клацають.
		var cell := BarCell.new()
		cell.setup(i, CELL)
		cell.position = at
		cell.dropped.connect(_on_dropped)
		cell.pressed.connect(func(where: int) -> void: wants_slot_used.emit(where))
		box.add_child(cell)
		_plate(Vector2(CELL, CELL), BACK, cell)
		var name_text := _text(11, cell)
		name_text.position = Vector2(4, CELL - 20)
		name_text.size = Vector2(CELL - 8, 16)
		var key := _text(11, cell)
		key.text = str(i + 1)
		key.position = Vector2(4, 2)
		# Затемнення на відкаті: спадає згори вниз, як пісок.
		var shade := _plate(Vector2(CELL, CELL), Color(0, 0, 0, 0.62), cell)
		shade.visible = false
		var left := _text(16, cell)
		left.position = Vector2(CELL * 0.5 - 10, CELL * 0.5 - 12)
		_cells.append({"cell": cell, "name": name_text, "shade": shade,
				"left": left})

	_queue_text = _text(13, box)
	_queue_text.position = Vector2(0, -24)


## Смуга читання — над панеллю. Видно, скільки лишилось і що саме
## читається; зникає, щойно дочитав або збили (крок 2.3).
func _build_cast() -> void:
	_cast_box = Control.new()
	_cast_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_cast_box.position = Vector2(-WIDE * 0.5, -CELL - 62)
	_cast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cast_box.visible = false
	_root.add_child(_cast_box)
	_plate(Vector2(WIDE, 16), BACK, _cast_box)
	_cast_fill = _plate(Vector2(0, 16), CAST_COLOR, _cast_box)
	_cast_text = _text(12, _cast_box)
	_cast_text.position = Vector2(6, 0)


## Рядок повідомлень — ліворуч унизу. Старі зникають самі.
func _build_messages() -> void:
	_messages = VBoxContainer.new()
	_messages.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_messages.position = Vector2(16, -140)
	_messages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_messages)


# ── те, що надсилає сервер ────────────────────────────────────────────

func set_bar(bar: Array) -> void:
	_bar.assign(bar)
	for i in _cells.size():
		var action: String = _bar[i] if i < _bar.size() else ""
		_cells[i]["name"].text = _title(action)
		# Комірка мусить знати свою дію: інакше її не перетягнути.
		_cells[i]["cell"].action = action


## Назви дій українською. Уміння з кроку 2 принесуть свої.
func _title(action: String) -> String:
	if action.begins_with("скіл:"):
		# У панелі стоїть ключ скіла; показуємо коротку назву.
		return action.substr(5).replace("енергетичний-", "енерг. ")
	match action:
		"attack": return "удар"
		"next_player": return "гравець"
		"next_mob": return "монстр"
		"corpse_skill": return "труп"
		"taunt": return "агресія"
		"": return ""
	return action


func set_vitals(id: int, hp: int, max_hp: int) -> void:
	_max_hp[id] = max_hp
	_hp[id] = hp


func set_hp(id: int, hp: int) -> void:
	_hp[id] = hp


func set_target(id: int) -> void:
	_target = id
	_target_box.visible = id != 0
	if id != 0:
		# Ім'я й колір беремо в світу: він знає, хто це і якої різниці
		# рівнів. Показ не рахує нічого сам (П-08).
		_target_name.text = _world.title_of(id)
		_target_name.modulate = _world.tint_of(id)


func forget(id: int) -> void:
	_max_hp.erase(id)
	_hp.erase(id)
	if _target == id:
		set_target(0)


## Свої числа приходять щотіку, разом із відкатами й чергою.
func update_self(hp: int, max_hp: int, mp: int, max_mp: int,
		slots: PackedFloat32Array, busy_in: float, queue: Array) -> void:
	_hp_fill.size.x = WIDE * clampf(float(hp) / maxf(1.0, max_hp), 0.0, 1.0)
	_mp_fill.size.x = WIDE * clampf(float(mp) / maxf(1.0, max_mp), 0.0, 1.0)
	_vitals_text.text = "%d / %d      мана %d / %d" % [hp, max_hp, mp, max_mp]

	for i in _cells.size():
		var action: String = _bar[i] if i < _bar.size() else ""
		# Відкат кожної комірки рахує сервер: в удару свій, у скіла свій.
		var left: float = slots[i] if i < slots.size() else 0.0
		var cell: Dictionary = _cells[i]
		cell["shade"].visible = left > 0.0 or action == ""
		if action == "":
			cell["shade"].color = Color(0, 0, 0, 0.35)
			cell["left"].text = ""
			continue
		cell["shade"].color = Color(0, 0, 0, 0.62)
		cell["left"].text = "%.1f" % left if left > 0.0 else ""

	var names: Array[String] = []
	for action in queue:
		names.append(_title(action))
	var tail := "  ·  замах %.2f" % busy_in if busy_in > 0.0 else ""
	_queue_text.text = ("черга: " + " · ".join(names) + tail) \
			if not names.is_empty() else tail.strip_edges()


## Почалося читання. Чуже поки не показуємо окремо — своє важливіше, а
## чуже видно по тому, що істота стоїть (крок 2.4 додасть значок).
func cast_started(id: int, name: String, seconds: float) -> void:
	if id != _world.multiplayer.get_unique_id():
		return
	_cast_full = seconds
	_cast_left = seconds
	_cast_text.text = name
	_cast_box.visible = true


func cast_ended(id: int, done: bool) -> void:
	if id != _world.multiplayer.get_unique_id():
		return
	_cast_box.visible = false
	_cast_left = 0.0
	if not done:
		notice("читання перервано")


## Рівень і повага до наступного (крок 3).
func update_level(level: int, respect: int, need: int) -> void:
	_respect_fill.size.x = WIDE * clampf(float(respect) / maxf(1.0, need),
			0.0, 1.0)
	_level_text.text = "рівень %d      повага %d / %d" % [level, respect, need]


func notice(text: String) -> void:
	var line := _text(14, _messages)
	line.text = text
	line.modulate = Color(1, 0.86, 0.6)
	# Виносити З ДЕРЕВА одразу, а `queue_free` лишати на потім.
	#
	# Тут був вічний цикл, який клав машину. `queue_free` відкладений: до
	# кінця кадру дитина лишається в дереві, `get_child_count()` не
	# меншає — і умова циклу ніколи не стає хибною. Кожен оберт додавав
	# той самий вузол у чергу видалення, і пам'ять росла по 700 МіБ за
	# секунду. Заміряно 02.09.2026: клієнт із 168 МіБ за десять секунд
	# доходив до 4,9 ГіБ, а одного разу до 28 ГіБ — його вбив OOM-килер
	# разом із рештою робочого столу.
	#
	# Ловилось це погано, бо вмикалось лише на ШОСТОМУ повідомленні — тобто
	# рівно в мить убивства: «повага», «здобуто», «неможливо застосувати».
	while _messages.get_child_count() > MESSAGES:
		var oldest: Node = _messages.get_child(0)
		_messages.remove_child(oldest)
		oldest.queue_free()
	# Плавність прив'язана до самого рядка, а не до показу: коли рядок
	# приберуть раніше строку, вона згасне разом із ним і не сваритиметься
	# на звільнений об'єкт.
	var fade := line.create_tween()
	fade.tween_interval(MESSAGE_TIME)
	fade.tween_property(line, "modulate:a", 0.0, 0.8)
	fade.tween_callback(line.queue_free)


## Число шкоди над істотою. Летить угору й гасне.
func damage(id: int, amount: int, behind: bool) -> void:
	var who: Node3D = _world.creatures.get(id)
	if who == null:
		return
	var label := _text(20 if behind else 17, _root)
	label.text = ("%d у спину" % amount) if behind else str(amount)
	# Своя шкода червона, чужа біла: у бою треба з одного погляду бачити,
	# кому саме прилетіло. Удар зі спини помітний окремо.
	var mine: bool = id == _world.multiplayer.get_unique_id()
	if behind:
		label.modulate = Color(1.0, 0.55, 0.35)
	else:
		label.modulate = Color(1.0, 0.35, 0.3) if mine else Color(1, 1, 1)
	_floats.append({"label": label, "who": who, "left": FLOAT_TIME})


func _process(delta: float) -> void:
	if _target != 0 and _max_hp.has(_target):
		var share := float(_hp.get(_target, 0)) / maxf(1.0, _max_hp[_target])
		_target_fill.size.x = WIDE * clampf(share, 0.0, 1.0)
		_target_name.text = "%s   %d / %d" % [_world.title_of(_target),
				_hp.get(_target, 0), _max_hp[_target]]
	if _cast_box.visible:
		_cast_left = maxf(0.0, _cast_left - delta)
		var gone: float = 1.0 - _cast_left / maxf(0.01, _cast_full)
		_cast_fill.size.x = WIDE * clampf(gone, 0.0, 1.0)
		_cast_text.text = "%s   %.1f с" % [_cast_text.text.split("   ")[0],
				_cast_left]
	_move_floats(delta)


## Числа шкоди тримаються над головою тієї істоти, якій вони належать.
func _move_floats(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	for item in _floats.duplicate():
		item["left"] -= delta
		var label: Label = item["label"]
		if item["left"] <= 0.0 or camera == null \
				or not is_instance_valid(item["who"]):
			label.queue_free()
			_floats.erase(item)
			continue
		var gone: float = 1.0 - item["left"] / FLOAT_TIME
		var head: Vector3 = item["who"].global_position + Vector3(0, 1.6, 0)
		if camera.is_position_behind(head):
			label.visible = false
			continue
		label.visible = true
		label.position = camera.unproject_position(head) \
				- Vector2(label.size.x * 0.5, gone * FLOAT_RISE)
		label.modulate.a = 1.0 - gone * gone
