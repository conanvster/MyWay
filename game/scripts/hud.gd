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

## Дві комірки черги дій поруч зі здоров'ям/маною (П-149): координати
## лівого верхнього кута відносно тієї самої `box`, що й смуги.
const QUEUE_SIDE := 34.0
const QUEUE_GAP := WIDE + 10.0
const QUEUE_CELLS := [
	Vector2(QUEUE_GAP, 0.0), Vector2(QUEUE_GAP + QUEUE_SIDE + 4.0, 0.0)]

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


## Бафи й дебафи (замовник 13.09.2026: «хочу бачити, на кого я наклав
## баф; якщо на себе — трохи нижче черги, якщо на монстрах — під іменем
## монстра з кількістю хп»). Комірка — значок скіла, від якого стан, у
## зеленій рамці баф, у червоній дебаф, унизу секунди.
const STATE_SIDE := 28.0
const STATE_GAP := 4.0
const BUFF_EDGE := Color(0.36, 0.78, 0.34)
const DEBUFF_EDGE := Color(0.86, 0.26, 0.2)
const STAT_TITLES := {"strength": "сила", "agility": "спритність",
		"stamina": "витривалість", "intellect": "інтелект", "sense": "чуття",
		"move_speed": "швидкість", "physical_attack": "фіз. атака",
		"physical_defence": "фіз. захист"}

var _my_states: Control
var _target_states: Control

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
## Дві комірки черги дій поруч зі здоров'ям/маною (П-149).
## Кожен елемент — `{"label": Label, "icon": TextureRect}`.
var _queue_cells: Array[Dictionary] = []
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
var _coords_text: Label


func setup(world: Node) -> void:
	_world = world
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_vitals()
	_build_coords()
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
	_build_warehouse()
	_build_guild()
	_build_map()
	# Останнім: підтвердження має лежати ПОВЕРХ вікна, з якого його
	# викликали, інакше «Так» довелось би шукати під прилавком.
	_build_confirm()


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


## Теплий пергаментний текст для вікон «камінь і золото» (П-150): білий
## з чорним обрисом сюди не пасує, а на темному камені губиться.
const PARCHMENT := Color(0.86, 0.79, 0.62)
const PARCHMENT_DIM := Color(0.52, 0.47, 0.38)


func _gothic_text(size: int, parent: Control,
		color: Color = PARCHMENT) -> Label:
	var label := _text(size, parent)
	label.add_theme_constant_override("outline_size", 0)
	label.add_theme_color_override("font_color", color)
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
			["Речі", _toggle_things], ["Карта", _toggle_map],
			["Вийти", _quit]]
	# Кнопок стало п'ять — рядок їде лівіше рівно на одну ширину, щоб
	# «Вийти» лишалась у тому самому куті, де до неї звикли.
	_menu_box.position = Vector2(-460 - 112, -46)
	for i in buttons.size():
		var press := Button.new()
		press.text = str(buttons[i][0])
		press.position = Vector2(i * 112, 0)
		press.size = Vector2(104, 32)
		press.pressed.connect(buttons[i][1])
		_menu_box.add_child(press)


## Не закриваємо вікно — вертаємось на стартову сторінку. Сервер і базу
## лишаємо жити: там, звідки прийшли, є кнопка «Зупинити сервер», і
## гравець зупиняє сам, коли хоче, а не щоразу наосліп при виході.
##
## Від'єднання те саме, що й було: закриваємо мережевого одноранга
## самі — сервер бачить його й зберігає персонажа (`_on_left`), так само,
## як при закритті вікна.
func _quit() -> void:
	var tree := _world.get_tree()
	var peer := _world.multiplayer.multiplayer_peer
	if peer != null:
		peer.close()
	_world.multiplayer.multiplayer_peer = null
	Net.joined = false
	var launcher: Node = load("res://scenes/launcher.tscn").instantiate()
	var old_world := _world
	launcher.tree_entered.connect(func() -> void:
			tree.current_scene = launcher
			old_world.queue_free(), CONNECT_ONE_SHOT)
	tree.root.add_child.call_deferred(launcher)


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
const STATS_INNER := Vector2(276, 344)

## Скільки місця на групу: рядок і повітря під смужкою.
const STAT_ROW := 21.0
const STAT_GAP := 14.0

## Стати, у які можна вкладати очки (П-147) — саме ці рядки й отримують
## кнопку «+», решта (рівень, здоров'я, атака...) тільки показуються.
const SPENDABLE := ["сила", "спритність", "витривалість", "інтелект", "чуття"]

var _stats_box: WindowBox
var _stats_fields: Dictionary = {}
var _stats_spend: Dictionary = {}
var _stats_who: Label
var _stats_points := 0


func _build_stats() -> void:
	_stats_box = WindowBox.new()
	_stats_box.name = "СторінкаСтатів"
	_stats_box.setup("Стати", STATS_INNER, true)
	_stats_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_stats_box.position = Vector2(-_stats_box.size.x - 24,
			-_stats_box.size.y - 52)
	_root.add_child(_stats_box)
	var page: Control = _stats_box.body

	_stats_who = _gothic_text(13, page, WindowBox.GOTHIC_GOLD)
	_stats_who.name = "Хто"
	_stats_who.text = "—"

	var at := 26.0
	var groups: Array = [
			["рівень", "вільних очок"],
			["сила", "спритність", "витривалість", "інтелект", "чуття"],
			["здоров'я", "мана"],
			["фіз. атака", "маг. атака", "фіз. захист", "маг. захист"]]
	for group_at in groups.size():
		for field: String in groups[group_at]:
			var name_text := _gothic_text(13, page, PARCHMENT_DIM)
			name_text.text = field
			name_text.position = Vector2(2, at)
			var value := _gothic_text(13, page)
			value.name = field
			value.text = "—"
			value.position = Vector2(STATS_INNER.x - 98, at)
			value.size = Vector2(70, 18)
			value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			_stats_fields[field] = value
			if SPENDABLE.has(field):
				var plus := Button.new()
				plus.text = "+"
				plus.position = Vector2(STATS_INNER.x - 24, at - 2)
				plus.size = Vector2(22, 22)
				plus.custom_minimum_size = plus.size
				plus.disabled = true
				plus.add_theme_color_override(
						"font_color", WindowBox.GOTHIC_GOLD)
				plus.pressed.connect(
						func() -> void: wants_spend_stat.emit(field))
				page.add_child(plus)
				_stats_spend[field] = plus
			at += STAT_ROW
		# Смужка між групами: саме повітря око не розділяє, і чотири
		# групи читались як один довгий стовпчик.
		if group_at < groups.size() - 1:
			var line := _plate(Vector2(STATS_INNER.x, 1),
					WindowBox.GOTHIC_GOLD_DIM, page)
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
	_stats_points = int(data.get("очки", 0))
	_put("вільних очок", "%d" % _stats_points,
			WindowBox.GOTHIC_GOLD if _stats_points > 0 else PARCHMENT)
	# Чинне значення, а в дужках базове — коли спорядження чи баф їх
	# зсунули. Так одразу видно, що твоє власне, а що від речей.
	for field in SPENDABLE:
		var now: int = int(data.get(field, 0))
		var base: int = int(data.get(field + " базова", now))
		_put(field, "%d" % now if base == now else "%d  (%d)" % [now, base],
				PARCHMENT if base == now else Color(0.62, 0.82, 0.58))
		var plus: Button = _stats_spend.get(field)
		if plus != null:
			plus.disabled = _stats_points <= 0
	_put("здоров'я", "%d" % int(data.get("здоров'я", 0)))
	_put("мана", "%d" % int(data.get("мана", 0)))
	_put("фіз. атака", "%.1f" % float(data.get("атака", 0.0)))
	_put("маг. атака", "%.1f" % float(data.get("магічна атака", 0.0)))
	_put("фіз. захист", "%.1f" % float(data.get("захист", 0.0)))
	_put("маг. захист", "%.1f" % float(data.get("магічний захист", 0.0)))


func _put(field: String, value: String, tint: Color = PARCHMENT) -> void:
	var label: Label = _stats_fields.get(field)
	if label != null:
		label.text = value
		label.add_theme_color_override("font_color", tint)


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
## Рядок закладок «Скіли»/«Дії» (П-155) над підказкою.
const SKILLS_TABS_H := 22.0
const SKILLS_TAB_NAMES := ["Скіли", "Дії"]
## Голі уміння (П-155): тих самих 8, що в `actions.gd`, немає де взяти
## перекладу назви/примітки — це не дані з файлу, це самі правила гри,
## тож короткий перелік лежить тут, а не в JSON.
const BARE_ACTIONS := [
	{"код": "attack", "назва": "удар",
			"нота": "звичайна атака зброєю"},
	{"код": "next_mob", "назва": "наступний монстр",
			"нота": "перебір видимих монстрів"},
	{"код": "next_player", "назва": "наступний гравець",
			"нота": "перебір видимих гравців"},
	{"код": "next_mob_corpse", "назва": "наступний труп монстра",
			"нота": "Shift + наступний монстр"},
	{"код": "next_player_corpse", "назва": "наступний труп гравця",
			"нота": "Shift + наступний гравець"},
	{"код": "taunt", "назва": "агресія",
			"нота": "перемикає монстра на себе"},
	{"код": "corpse_skill", "назва": "дія по трупу",
			"нота": "оживити чи підняти, залежно від класу"},
	{"код": "sit", "назва": "сісти",
			"нота": "утричі швидше відновлення, встаєш від удару"},
]

var _skills_box: WindowBox
var _skills_grid: GridContainer
var _skills: Array = []
var _skills_tab := 0
var _skills_tabs_ui: Array = []


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

	var tab_w := (SKILLS_WIDE - 4.0) / SKILLS_TAB_NAMES.size()
	for i in SKILLS_TAB_NAMES.size():
		var tab := Button.new()
		tab.text = SKILLS_TAB_NAMES[i]
		tab.add_theme_font_size_override("font_size", 11)
		tab.size = Vector2(tab_w, SKILLS_TABS_H)
		tab.position = Vector2(i * (tab_w + 4.0), 0)
		tab.pressed.connect(func() -> void: _pick_skills_tab(i))
		page.add_child(tab)
		_skills_tabs_ui.append(tab)

	var hint := _text(11, page)
	hint.name = "Підказка"
	hint.text = "тягни на комірку 1–7"
	hint.position = Vector2(0, SKILLS_TABS_H)
	hint.modulate = Color(0.72, 0.76, 0.68)

	_skills_grid = GridContainer.new()
	_skills_grid.name = "Сітка"
	_skills_grid.columns = SKILLS_COLUMNS
	_skills_grid.position = Vector2(0, SKILLS_TABS_H + SKILLS_TOP)
	_skills_grid.add_theme_constant_override("h_separation", 6)
	_skills_grid.add_theme_constant_override("v_separation", 6)
	page.add_child(_skills_grid)


func _toggle_skills() -> void:
	if _skills_box != null:
		_skills_box.toggle()


func _pick_skills_tab(i: int) -> void:
	_skills_tab = i
	_render_skills_tab()


## Лаконічна підказка про скіл (П-154): тип, вартість, сила, стихія,
## опис — усе, крім тіла клітинки, що й так показує назву й грейд.
func _skill_tooltip_extra(row: Dictionary) -> String:
	var lines: PackedStringArray = []
	var element: String = str(row.get("стихія", ""))
	lines.append("тип: магічний · стихія: %s"
			% (element if element != "" else "не задана"))
	var power: float = float(row.get("шкода", 0.0))
	var effect: Dictionary = row.get("ефект", {})
	if power > 0.0:
		lines.append("сила: %.0f%% магічної атаки" % (power * 100.0))
	elif not effect.is_empty():
		var stat_key: String = str(effect.get("стат", ""))
		var stat_ua: Variant = Stats.STAT_FIELDS.find_key(stat_key)
		lines.append("ефект: %s ×%.2f, %.0f с" % [
				stat_ua if stat_ua != null else stat_key,
				float(effect.get("множник", 1.0)),
				float(effect.get("строк", 0.0))])
	var opis: String = str(row.get("опис", ""))
	if opis != "":
		lines.append("опис: %s" % opis)
	return "\n".join(lines)


## Що вміє гравець — приходить від сервера.
func set_skills(list: Array) -> void:
	_skills = list
	_render_skills_tab()


## Перемальовує сітку під поточну закладку: скіли з `_skills`, або
## незмінний перелік голих умінь (П-155) — той самий рядок, СВОЯ дія
## без префікса `скіл:`, без підказки типу/сили/стихії (тим уміння й
## відрізняються від скілів — вони не мають цих даних).
func _render_skills_tab() -> void:
	if _skills_grid == null:
		return
	for i in _skills_tabs_ui.size():
		var tab: Button = _skills_tabs_ui[i]
		tab.disabled = i == _skills_tab

	for old_cell in _skills_grid.get_children():
		_skills_grid.remove_child(old_cell)
		old_cell.queue_free()

	var count := 0
	if _skills_tab == 0:
		for row: Dictionary in _skills:
			var cell := SkillCell.new()
			cell.setup(str(row.get("ключ", "")), str(row.get("назва", "?")),
					"%s · рівень %d з %d · %d мани · %.0f м"
							% [str(row.get("грейд", "E")),
							   int(row.get("рівень", 1)),
							   int(row.get("рівнів", 1)),
							   int(row.get("мана", 0)),
							   float(row.get("дальність", 0.0))],
					"", null, _skill_tooltip_extra(row))
			_skills_grid.add_child(cell)
		count = _skills.size()
	else:
		for row: Dictionary in BARE_ACTIONS:
			var cell := SkillCell.new()
			cell.setup(str(row["код"]), str(row["назва"]), str(row["нота"]),
					str(row["код"]), ActionIcons.of(str(row["код"])))
			_skills_grid.add_child(cell)
		count = BARE_ACTIONS.size()

	# Вікно росте під кількість рядків: порожній чорний прямокутник на пів
	# екрана виглядав так, ніби воно не догрузилось. Перебудова оболонки
	# дешевша за окреме «змінити розмір»: вікон три, а вміст міняється
	# рідко — на руну, на рівень, чи перемиканням закладки.
	_skills_box.resize(Vector2(SKILLS_WIDE,
			SKILLS_TABS_H + SKILLS_TOP + count * (SkillCell.HIGH + 6.0)))


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
	# Карту теж: інакше її, як колись вікно речей, ніхто не побачить на
	# знімку — рук у показу немає, а руками її ніхто не відкриє.
	if _map_box != null and not _map_box.visible:
		_toggle_map()


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


## Ім'я для пошуку значка. Поодинока річ несе «база» окремо від
## «назва» — «назва» може мати афікс («легкий меч з кори дуба»), а
## малюнок намальовано на базову річ; складана афіксів не має, і в неї
## «база» просто немає — тоді береться «назва».
func _art_name(row: Dictionary) -> String:
	return str(row.get("база", row.get("назва", "")))


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
					str(row.get("грейд", "E")), _art_name(row))
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
				str(row.get("грейд", "")), _art_name(row))
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

## Склад і гільдія (крок 5, П-145) — та сама «спитай сервер, він
## вирішить» логіка, що й у прилавка.
signal wants_warehouse(at: int)
signal wants_store_thing(at: int, thing_at: int)
signal wants_store_stack(at: int, name: String)
signal wants_withdraw_thing(at: int, thing_at: int)
signal wants_withdraw_stack(at: int, name: String)
signal wants_guild(at: int)
signal wants_bless(at: int)
signal wants_learn_skill(at: int, key: String)
signal wants_raise_skill(at: int, key: String)

## Розподілити одне вільне очко в стат (П-147).
signal wants_spend_stat(field: String)

const TALK_INNER := Vector2(240, 212)
## Прилавок: та сама комірка, що в торбі, по чотири в ряд.
const SHOP_COLUMNS := 4
const SHOP_ROWS := 6
const HINT_H := 26.0

var _talk_box: WindowBox
var _talk_title: Label
var _talk_trade: Button
var _talk_warehouse: Button
var _talk_guild: Button
var _talk_bless: Button
var _talk_with := -1

## Підтвердження дії (П-159). Одне вікно на всі випадки: питання
## складає той, хто його показує, а «Так» несе вже готовий виклик.
## Модальним робити не довелось — воно й так поверх усього, а закрити
## його можна і хрестиком, і «Скасувати».
const CONFIRM_INNER := Vector2(300, 96)

var _confirm_box: WindowBox
var _confirm_text: Label
var _confirm_yes: Button
var _confirm_no: Button
## Що зробити на «Так». Порожній — вікно ні до чого не прив'язане.
var _confirm_does := Callable()

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

	_talk_warehouse = Button.new()
	_talk_warehouse.text = "Склад"
	_talk_warehouse.position = Vector2(0, 80)
	_talk_warehouse.size = Vector2(TALK_INNER.x, 32)
	_talk_warehouse.custom_minimum_size = _talk_warehouse.size
	_talk_warehouse.pressed.connect(func() -> void:
			if _talk_with >= 0:
				wants_warehouse.emit(_talk_with))
	page.add_child(_talk_warehouse)

	_talk_guild = Button.new()
	_talk_guild.text = "Гільдія"
	_talk_guild.position = Vector2(0, 120)
	_talk_guild.size = Vector2(TALK_INNER.x, 32)
	_talk_guild.custom_minimum_size = _talk_guild.size
	_talk_guild.pressed.connect(func() -> void:
			if _talk_with >= 0:
				wants_guild.emit(_talk_with))
	page.add_child(_talk_guild)

	_talk_bless = Button.new()
	_talk_bless.text = "Благословення"
	_talk_bless.position = Vector2(0, 160)
	_talk_bless.size = Vector2(TALK_INNER.x, 32)
	_talk_bless.custom_minimum_size = _talk_bless.size
	_talk_bless.pressed.connect(func() -> void:
			if _talk_with >= 0:
				wants_bless.emit(_talk_with))
	page.add_child(_talk_bless)


## Карта світу: скільки точок на бік. Квадратна, бо квадратний і світ.
const MAP_SIDE := 480.0

var _map_box: WindowBox
var _map_view: WorldMap


## Карта світу (пряме слово замовника 05.09.2026). Малює `world_map.gd`
## із тих самих даних, з яких збудовано землю, — розійтися зі світом їй
## нема з чого.
func _build_map() -> void:
	_map_box = WindowBox.new()
	_map_box.name = "ВікноКарти"
	_map_box.setup("Карта", Vector2(MAP_SIDE, MAP_SIDE))
	_map_box.set_anchors_preset(Control.PRESET_CENTER)
	_map_box.position = -_map_box.size * 0.5
	_root.add_child(_map_box)

	_map_view = WorldMap.new()
	_map_view.name = "Карта"
	_map_view.size = Vector2(MAP_SIDE, MAP_SIDE)
	_map_view.custom_minimum_size = _map_view.size
	_map_box.body.add_child(_map_view)


func _toggle_map() -> void:
	if _map_box == null:
		return
	_map_box.visible = not _map_box.visible
	if _map_box.visible:
		# Дані беремо в мить відкриття, а не на старті: числа правляться
		# на ходу (крок 1.2), і карта має показувати теперішні.
		if _world != null and _world.data != null:
			_map_view.map = _world.data.map
		if _world != null:
			_map_view.dungeons = _world.dungeons
			_map_view.world = _world
		# На світі версії 2 аркуш більший за вікно в дванадцять разів:
		# відкрити його на середині світу означало б щоразу шукати себе
		# вручну. Тому відкривається на гравцеві.
		_map_view.center_on_me()
		_map_view.queue_redraw()
		_map_box._keep_on_screen()


## Вікно підтвердження (П-159). Будується раз, показується щоразу з
## новим питанням і новою дією на «Так».
func _build_confirm() -> void:
	_confirm_box = WindowBox.new()
	_confirm_box.name = "ВікноПідтвердження"
	_confirm_box.setup("Підтвердь", CONFIRM_INNER)
	_confirm_box.set_anchors_preset(Control.PRESET_CENTER)
	_confirm_box.position = -_confirm_box.size * 0.5
	_root.add_child(_confirm_box)
	var page: Control = _confirm_box.body

	_confirm_text = _text(14, page)
	_confirm_text.text = "—"
	_confirm_text.size = Vector2(CONFIRM_INNER.x, 48)
	_confirm_text.custom_minimum_size = _confirm_text.size
	_confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var half := (CONFIRM_INNER.x - 8.0) * 0.5
	_confirm_yes = Button.new()
	_confirm_yes.text = "Так"
	_confirm_yes.position = Vector2(0, CONFIRM_INNER.y - 32.0)
	_confirm_yes.size = Vector2(half, 32)
	_confirm_yes.custom_minimum_size = _confirm_yes.size
	_confirm_yes.pressed.connect(_confirm_done)
	page.add_child(_confirm_yes)

	_confirm_no = Button.new()
	_confirm_no.text = "Скасувати"
	_confirm_no.position = Vector2(half + 8.0, CONFIRM_INNER.y - 32.0)
	_confirm_no.size = Vector2(half, 32)
	_confirm_no.custom_minimum_size = _confirm_no.size
	_confirm_no.pressed.connect(hide_confirm)
	page.add_child(_confirm_no)


## Спитати перед дією. `does` виконається лише на «Так» (П-159).
func ask_confirm(question: String, does: Callable) -> void:
	if _confirm_box == null:
		# Вікна немає — питати нема чим, але дію ковтати мовчки не можна
		# (P3): краще виконати, ніж загубити натиск гравця.
		does.call()
		return
	_confirm_text.text = question
	_confirm_does = does
	_confirm_box.visible = true
	_confirm_box._keep_on_screen()


func hide_confirm() -> void:
	if _confirm_box != null:
		_confirm_box.visible = false
	_confirm_does = Callable()


func _confirm_done() -> void:
	var does := _confirm_does
	# Ховаємо ПЕРЕД викликом: дія може відкрити своє вікно, і воно не
	# має закритись услід за цим.
	hide_confirm()
	if does.is_valid():
		does.call()


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


func show_talk(at: int, title: String, trades: bool,
		warehouse_keeper: bool = false, guild_master: bool = false,
		priest: bool = false) -> void:
	if _talk_box == null:
		return
	_talk_with = at
	_talk_title.text = title
	_talk_trade.visible = trades
	_talk_warehouse.visible = warehouse_keeper
	_talk_guild.visible = guild_master
	_talk_bless.visible = priest
	# Видимі кнопки — підряд згори: у кожного мешканця своя одна-дві, і
	# на сталих місцях кнопка священика висіла б під трьома порожніми.
	var row := 0
	for button: Button in [_talk_trade, _talk_warehouse, _talk_guild,
			_talk_bless]:
		if button.visible:
			button.position.y = 40 + row * 40
			row += 1
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
				str(row.get("слот", "")), str(row.get("грейд", "")),
				_art_name(row))
		cell["count"].text = ""
		press.disabled = false
		press.tooltip_text = "%s\nкупити за %d" % [name, price]
		_cell_look(press, true)
		_hover(press, "%s — купити за %d" % [name, price])
		# Купівля питає підтвердження, і воно підкріплене сумою (П-159).
		press.pressed.connect(func() -> void:
				ask_confirm("Купити «%s» за %d?" % [name, price],
						func() -> void: wants_buy.emit(_shop_with, name)))


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
				str(row.get("слот", "")), str(row.get("грейд", "")),
				_art_name(row))
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


# ── склад (крок 5, П-145) ────────────────────────────────────────────
#
## Простий список кнопок, не сітка з іконками, як у прилавка: склад не
## про вигляд, а про «куди це поділось» — рядок з назвою й кількістю
## досить, щоб знайти річ.

const WAREHOUSE_ROWS := 10
const ROW_H := 26.0

var _warehouse_box: WindowBox
var _bag_rows: Array = []       ## кнопки зліва — з торби на склад
var _kept_rows: Array = []      ## кнопки справа — зі складу в торбу
var _warehouse_with := -1
var _warehouse_things: Array = []
var _warehouse_stacks: Array = []


func _build_warehouse() -> void:
	var col := 220.0
	var inner := Vector2(col * 2.0 + 20.0,
			18.0 + WAREHOUSE_ROWS * (ROW_H + 2.0))
	_warehouse_box = WindowBox.new()
	_warehouse_box.name = "ВікноСкладу"
	_warehouse_box.setup("Склад", inner)
	_warehouse_box.set_anchors_preset(Control.PRESET_CENTER)
	_warehouse_box.position = -_warehouse_box.size * 0.5
	_root.add_child(_warehouse_box)
	var page: Control = _warehouse_box.body

	var left := _text(11, page)
	left.text = "торба — клікни, щоб покласти"
	left.modulate = CAPTION_COLOR
	var right := _text(11, page)
	right.text = "склад — клікни, щоб забрати"
	right.modulate = CAPTION_COLOR
	right.position = Vector2(col + 20.0, 0)

	for i in WAREHOUSE_ROWS:
		var y := 18.0 + i * (ROW_H + 2.0)
		var giving := Button.new()
		giving.size = Vector2(col, ROW_H)
		giving.custom_minimum_size = giving.size
		giving.position = Vector2(0, y)
		giving.alignment = HORIZONTAL_ALIGNMENT_LEFT
		page.add_child(giving)
		_bag_rows.append(giving)

		var keeping := Button.new()
		keeping.size = Vector2(col, ROW_H)
		keeping.custom_minimum_size = keeping.size
		keeping.position = Vector2(col + 20.0, y)
		keeping.alignment = HORIZONTAL_ALIGNMENT_LEFT
		page.add_child(keeping)
		_kept_rows.append(keeping)


## Ліворуч — торба (та сама, що й у прилавка): вдягнене й гроші не
## пропонуємо класти на склад — вдягнене спершу треба зняти, а гроші й
## так лежать в акаунті, окремий склад на них не потрібен.
func _fill_bag_side() -> void:
	var rows: Array = []
	for row: Dictionary in _things:
		if not bool(row.get("вдягнене", false)):
			rows.append(row)
	for row: Dictionary in _stacks:
		if str(row.get("назва", "")) != "гроші":
			rows.append(row)

	for i in _bag_rows.size():
		var press: Button = _bag_rows[i]
		_unlink(press)
		if i >= rows.size():
			press.text = ""
			press.disabled = true
			continue
		var row: Dictionary = rows[i]
		var name: String = str(row.get("назва", "?"))
		press.disabled = false
		# Перенесення в склад питає підтвердження (П-159). Забирання зі
		# складу — ні: там нічого не втрачається, а рішення назвало саме
		# «перенесення в склад».
		if row.has("номер"):
			var thing_at: int = int(row["номер"])
			press.text = name
			press.pressed.connect(func() -> void:
					ask_confirm("Перенести «%s» у склад?" % name,
							func() -> void:
								wants_store_thing.emit(
										_warehouse_with, thing_at)))
		else:
			var count: int = int(row.get("скільки", 0))
			press.text = "%s ×%d" % [name, count]
			press.pressed.connect(func() -> void:
					ask_confirm("Перенести «%s» ×%d у склад?" % [name, count],
							func() -> void:
								wants_store_stack.emit(
										_warehouse_with, name)))


func _fill_kept_side() -> void:
	var rows: Array = []
	rows.append_array(_warehouse_things)
	rows.append_array(_warehouse_stacks)

	for i in _kept_rows.size():
		var press: Button = _kept_rows[i]
		_unlink(press)
		if i >= rows.size():
			press.text = ""
			press.disabled = true
			continue
		var row: Dictionary = rows[i]
		var name: String = str(row.get("назва", "?"))
		press.disabled = false
		if row.has("номер"):
			var thing_at: int = int(row["номер"])
			press.text = name
			press.pressed.connect(func() -> void:
					wants_withdraw_thing.emit(_warehouse_with, thing_at))
		else:
			var count: int = int(row.get("скільки", 0))
			press.text = "%s ×%d" % [name, count]
			press.pressed.connect(func() -> void:
					wants_withdraw_stack.emit(_warehouse_with, name))


func show_warehouse(at: int) -> void:
	if _warehouse_box == null:
		return
	_warehouse_with = at
	if _talk_box != null:
		_talk_box.visible = false
	_warehouse_box.visible = true
	_fill_bag_side()
	_fill_kept_side()
	_warehouse_box._keep_on_screen()


## Сервер надіслав, що лежить на складі — після відкриття вікна і після
## кожної зміни (клали чи брали).
func set_warehouse(things: Array, stacks: Array) -> void:
	_warehouse_things = things
	_warehouse_stacks = stacks
	if _warehouse_box != null and _warehouse_box.visible:
		_fill_kept_side()


# ── гільдія: дерево скілів (крок 5, П-145; дерево П-150) ───────────────
#
## Вивчення й підняття рівня скіла через `Runes`. Дерево — три вкладки
## (спершу тільки людина), сітка 2×3 на кожну, лінії передумов; та сама
## сітка вузлів переставляється між вкладками — категорій три, а форма
## одна й та сама (П-150).

const TREE_CATEGORIES := ["Бойові кличі", "Бойові стійки", "Бойові навички"]
const TREE_COLS := 2
const TREE_ROWS := 3
const NODE := 48.0
const NODE_GAP := 30.0
const TREE_W := TREE_COLS * NODE + (TREE_COLS - 1) * NODE_GAP
const TREE_H := TREE_ROWS * NODE + (TREE_ROWS - 1) * NODE_GAP
const TREE_TOP := 40.0
const DETAIL_W := 220.0
const GUILD_INNER := Vector2(TREE_W + 24.0 + DETAIL_W, TREE_TOP + TREE_H)

var _guild_box: WindowBox
var _guild_with := -1
var _guild_data: Array = []          # останній перелік від сервера
var _guild_tab := 0
var _guild_selected := ""
var _guild_tabs_ui: Array = []
var _guild_nodes: Dictionary = {}    # Vector2i(колонка,ряд) -> Button
var _guild_icons: Dictionary = {}    # Vector2i(колонка,ряд) -> TextureRect
var _guild_lines: TreeLines
var _guild_detail_name: Label
var _guild_detail_info: Label
var _guild_detail_press: Button


func _build_guild() -> void:
	_guild_box = WindowBox.new()
	_guild_box.name = "ВікноГільдії"
	_guild_box.setup("Гільдія", GUILD_INNER, true)
	_guild_box.set_anchors_preset(Control.PRESET_CENTER)
	_guild_box.position = -_guild_box.size * 0.5
	_root.add_child(_guild_box)
	var page: Control = _guild_box.body

	var tab_w := (TREE_W + 24.0 + DETAIL_W - 8.0) / 3.0
	for i in TREE_CATEGORIES.size():
		var tab := Button.new()
		tab.text = TREE_CATEGORIES[i]
		tab.add_theme_font_size_override("font_size", 11)
		tab.size = Vector2(tab_w, 26.0)
		tab.position = Vector2(i * (tab_w + 4.0), 0)
		tab.pressed.connect(func() -> void: _pick_guild_tab(i))
		page.add_child(tab)
		_guild_tabs_ui.append(tab)

	_guild_lines = TreeLines.new()
	_guild_lines.position = Vector2(0, TREE_TOP)
	_guild_lines.size = Vector2(TREE_W, TREE_H)
	_guild_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_guild_lines)

	for row in TREE_ROWS:
		for col in TREE_COLS:
			var press := Button.new()
			press.size = Vector2(NODE, NODE)
			press.position = Vector2(col * (NODE + NODE_GAP),
					TREE_TOP + row * (NODE + NODE_GAP))
			press.add_theme_font_size_override("font_size", 13)
			press.visible = false
			page.add_child(press)
			_guild_nodes[Vector2i(col, row)] = press

			# Значок скіла (`assets/icons/skills/`) поверх плитки; немає
			# малюнка — лишаються ініціали в самій кнопці (нижче).
			var icon := TextureRect.new()
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_SCALE
			icon.size = Vector2(NODE, NODE) * 0.72
			icon.position = (Vector2(NODE, NODE) - icon.size) * 0.5
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon.visible = false
			press.add_child(icon)
			_guild_icons[Vector2i(col, row)] = icon

	var detail_x := TREE_W + 24.0
	_guild_detail_name = _gothic_text(14, page, WindowBox.GOTHIC_GOLD)
	_guild_detail_name.position = Vector2(detail_x, TREE_TOP)
	_guild_detail_name.size = Vector2(DETAIL_W, 40)
	_guild_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD

	_guild_detail_info = _gothic_text(12, page)
	_guild_detail_info.position = Vector2(detail_x, TREE_TOP + 42.0)
	_guild_detail_info.size = Vector2(DETAIL_W, TREE_H - 76.0)
	_guild_detail_info.autowrap_mode = TextServer.AUTOWRAP_WORD

	_guild_detail_press = Button.new()
	_guild_detail_press.position = Vector2(detail_x, TREE_TOP + TREE_H - 30.0)
	_guild_detail_press.size = Vector2(DETAIL_W, 28.0)
	page.add_child(_guild_detail_press)


func _pick_guild_tab(i: int) -> void:
	_guild_tab = i
	_guild_selected = ""
	_render_guild_tree()


## Осередок вузла в сітці — центр, для лінії передумови.
func _node_center(at: Vector2i) -> Vector2:
	return Vector2(at.x * (NODE + NODE_GAP),
			TREE_TOP + at.y * (NODE + NODE_GAP)) + Vector2(NODE, NODE) * 0.5


func show_guild(at: int, rows: Array) -> void:
	if _guild_box == null:
		return
	_guild_with = at
	_guild_data = rows
	if _talk_box != null:
		_talk_box.visible = false
	_guild_box.visible = true
	_render_guild_tree()
	_guild_box._keep_on_screen()


## Перемальовує сітку й лінії для поточної вкладки — тими самими вузлами,
## що й інші вкладки, лише з іншим наповненням (форма спільна, П-150).
func _render_guild_tree() -> void:
	if _guild_box == null:
		return
	for i in _guild_tabs_ui.size():
		var tab: Button = _guild_tabs_ui[i]
		tab.disabled = i == _guild_tab

	var category: String = TREE_CATEGORIES[_guild_tab]
	var by_place: Dictionary = {}     # Vector2i -> row
	var by_key: Dictionary = {}       # ключ -> row
	for row: Dictionary in _guild_data:
		if str(row.get("вкладка", "")) != category:
			continue
		var at: Array = row.get("місце", [0, 0])
		var place := Vector2i(int(at[0]), int(at[1]))
		by_place[place] = row
		by_key[str(row["ключ"])] = row

	for place: Vector2i in _guild_nodes:
		var press: Button = _guild_nodes[place]
		_unlink(press)
		var row: Dictionary = by_place.get(place, {})
		if row.is_empty():
			press.visible = false
			continue
		press.visible = true
		var key: String = str(row["ключ"])
		var known: bool = bool(row["вивчено"])
		var open: bool = bool(row.get("передумова відома", true))
		var name: String = str(row["назва"])
		var icon: TextureRect = _guild_icons[place]
		var tex := SkillIcons.of(key)
		icon.visible = tex != null
		if tex != null:
			icon.texture = tex
			icon.modulate = Color(1, 1, 1, 1) if known else \
					(Color(1, 1, 1, 0.85) if open else Color(1, 1, 1, 0.35))
			press.text = ""
		else:
			var initials := ""
			for word in name.split(" "):
				if word.length() > 0:
					initials += word.substr(0, 1).to_upper()
			press.text = initials.substr(0, 2)
		press.add_theme_stylebox_override(
				"normal", _node_style(known, open))
		press.add_theme_stylebox_override(
				"hover", _node_style(known, open, true))
		press.add_theme_color_override("font_color",
				WindowBox.GOTHIC_GOLD if known else
				(PARCHMENT if open else PARCHMENT_DIM))
		press.pressed.connect(func() -> void: _select_guild_skill(key))

	var lines: Array = []
	for key: String in by_key:
		var row: Dictionary = by_key[key]
		var req: String = str(row.get("передумова", ""))
		if req == "" or not by_key.has(req):
			continue
		var parent_row: Dictionary = by_key[req]
		var parent_at: Array = parent_row.get("місце", [0, 0])
		var here_at: Array = row.get("місце", [0, 0])
		lines.append({
			"a": _node_center(Vector2i(int(parent_at[0]), int(parent_at[1]))),
			"b": _node_center(Vector2i(int(here_at[0]), int(here_at[1]))),
			"color": WindowBox.GOTHIC_GOLD if bool(parent_row["вивчено"])
					else WindowBox.GOTHIC_GOLD_DIM,
		})
	_guild_lines.set_segments(lines)

	if not by_key.has(_guild_selected):
		_guild_selected = by_key.keys()[0] if not by_key.is_empty() else ""
	_select_guild_skill(_guild_selected)


func _node_style(known: bool, open: bool, hover: bool = false) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(4)
	box.set_border_width_all(2)
	if known:
		box.bg_color = Color(0.28, 0.21, 0.09, 0.95 if not hover else 1.0)
		box.border_color = WindowBox.GOTHIC_GOLD
	elif open:
		box.bg_color = WindowBox.GOTHIC_INSET
		box.border_color = WindowBox.GOTHIC_GOLD_DIM
	else:
		box.bg_color = Color(0.05, 0.045, 0.04, 0.95)
		box.border_color = Color(0.22, 0.2, 0.16)
	return box


func _select_guild_skill(key: String) -> void:
	_guild_selected = key
	_unlink(_guild_detail_press)
	if key == "":
		_guild_detail_name.text = ""
		_guild_detail_info.text = ""
		_guild_detail_press.text = ""
		_guild_detail_press.disabled = true
		return
	var row: Dictionary = {}
	for r: Dictionary in _guild_data:
		if str(r["ключ"]) == key:
			row = r
			break
	if row.is_empty():
		return
	var known: bool = bool(row["вивчено"])
	var open: bool = bool(row.get("передумова відома", true))
	var level: int = int(row["рівень"])
	var max_level: int = int(row["максимум"])
	_guild_detail_name.text = "%s (%s)" \
			% [str(row["назва"]), str(row["грейд"])]
	_guild_detail_info.text = "рівень: %d / %d\nз рівня персонажа: %d" \
			% [level, max_level, int(row["з рівня"])]
	if not open:
		var req: String = str(row.get("передумова", ""))
		var req_name := req
		for r: Dictionary in _guild_data:
			if str(r["ключ"]) == req:
				req_name = str(r["назва"])
		_guild_detail_info.text += "\n\nспершу: %s" % req_name
		_guild_detail_press.text = "недоступно"
		_guild_detail_press.disabled = true
	elif not known:
		_guild_detail_press.text = "Вивчити (%s)" % str(row["руна вивчення"])
		_guild_detail_press.disabled = false
		_guild_detail_press.pressed.connect(func() -> void:
				wants_learn_skill.emit(_guild_with, key))
	elif level < max_level:
		_guild_detail_press.text = "Підняти (%s)" % str(row["руна підняття"])
		_guild_detail_press.disabled = false
		_guild_detail_press.pressed.connect(func() -> void:
				wants_raise_skill.emit(_guild_with, key))
	else:
		_guild_detail_press.text = "найвищий рівень"
		_guild_detail_press.disabled = true


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

	# Черга дій — двома комірками поруч зі здоров'ям і маною (П-149):
	# ліва — те, що спрацює НАЙПЕРШИМ, права — те, що після нього.
	# Коли ліва спрацьовує й іде з черги, права сама займає її місце —
	# показ просто перемальовує обидві з тієї самої `queue` щотіку.
	for i in QUEUE_CELLS.size():
		var at: Vector2 = QUEUE_CELLS[i]
		var plate := _plate(Vector2(QUEUE_SIDE, QUEUE_SIDE), BACK, box)
		plate.position = at
		var label := _text(11, box)
		label.position = at + Vector2(2, 9)
		label.size = Vector2(QUEUE_SIDE - 4, QUEUE_SIDE)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# Значок дії (коли є) на всю комірку, як і в панелі 1-7 — той
		# самий `_bar_icon`. Нема малюнка (голе вміння без художки) —
		# лишається текст, як і раніше; це чинило враження, що черга
		# взагалі не малює, чим є дія.
		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.position = at
		icon.size = Vector2(QUEUE_SIDE, QUEUE_SIDE)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.visible = false
		box.add_child(icon)
		_queue_cells.append({"label": label, "icon": icon})

	# Свої бафи — рядком трохи нижче черги.
	_my_states = Control.new()
	_my_states.name = "Мої стани"
	_my_states.position = Vector2(QUEUE_GAP, QUEUE_SIDE + 6.0)
	_my_states.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_my_states)


## Координати гравця — праворуч угорі. Клієнт нічого не рахує: позицію
## бере з власного вузла, той самий `global_position`, за яким ходять і
## по якому сервер звіряє намір (П-08 тут ні до чого — це не число гри,
## а суто зручність для налагодження рельєфу).
func _build_coords() -> void:
	var box := Control.new()
	box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	box.position = Vector2(-166, 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)

	_plate(Vector2(150, 18), BACK, box)
	_coords_text = _text(12, box)
	_coords_text.position = Vector2(6, 1)
	_coords_text.text = "x 0,0  y 0,0  z 0,0"


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
	# Стани цілі — під її ім'ям і смугою здоров'я.
	_target_states = Control.new()
	_target_states.name = "Стани цілі"
	_target_states.position = Vector2(0, 46)
	_target_states.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_target_box.add_child(_target_states)


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
		# Значок скіла чи речі (коли є): фото на всю комірку, під ним ще
		# й текст ховається — 56 точок замало для обох. Немає малюнка
		# (голе вміння штибу «удар») — лишається текст, як і раніше.
		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.size = Vector2(CELL, CELL)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.visible = false
		cell.add_child(icon)
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
		_cells.append({"cell": cell, "icon": icon, "name": name_text,
				"shade": shade, "left": left})

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
		var title := _title(action)
		var tex := _bar_icon(action)
		var icon: TextureRect = _cells[i]["icon"]
		icon.visible = tex != null
		if tex != null:
			icon.texture = tex
		# Малюнок замінює текст — 56 точок замало для обох; тримається
		# в підказці, щоб дію не вгадувати з самого значка.
		_cells[i]["name"].text = "" if tex != null else title
		_cells[i]["cell"].tooltip_text = title
		# Комірка мусить знати свою дію: інакше її не перетягнути.
		_cells[i]["cell"].action = action


## Значок дії: скіл, витратна річ і голе вміння (удар, наступна ціль...)
## шукають кожне у своїй теці. Немає малюнка ще ніде (новий скіл без
## художки) — комірка лишається на тексті, як і раніше.
func _bar_icon(action: String) -> Texture2D:
	if action.begins_with(Actions.SKILL_PREFIX):
		return SkillIcons.of(action.substr(Actions.SKILL_PREFIX.length()))
	if action.begins_with(Actions.ITEM_PREFIX):
		return ItemIcon.of(action.substr(Actions.ITEM_PREFIX.length()))
	return ActionIcons.of(action)


## Назви дій українською. Уміння з кроку 2 принесуть свої.
func _title(action: String) -> String:
	if action.begins_with("скіл:"):
		# У панелі стоїть ключ скіла; показуємо коротку назву.
		return action.substr(5).replace("енергетичний-", "енерг. ")
	match action:
		"attack": return "удар"
		"next_player": return "гравець"
		"next_mob": return "монстр"
		"next_player_corpse": return "труп гравця"
		"next_mob_corpse": return "труп монстра"
		"corpse_skill": return "труп"
		"taunt": return "агресія"
		"sit": return "сісти"
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


## Бафи й дебафи від сервера: свої й цілі. Стани цілі показуємо, лише
## якщо сервер говорить про ту саму ціль, що в рамці: відповідь могла
## розминутися з новим вибором.
func set_states(mine: Array, target: int, theirs: Array) -> void:
	if _my_states != null:
		_fill_states(_my_states, mine)
	if _target_states != null:
		_fill_states(_target_states, theirs if target == _target else [])


func _fill_states(holder: Control, row: Array) -> void:
	for child in holder.get_children():
		holder.remove_child(child)
		child.queue_free()
	for i in row.size():
		var one: Array = row[i]
		var title := str(one[0])
		var factor := float(one[2])
		var left := int(one[3])
		var cell := Control.new()
		cell.position = Vector2(i * (STATE_SIDE + STATE_GAP), 0.0)
		cell.size = Vector2(STATE_SIDE, STATE_SIDE)
		# PASS, а не IGNORE: інакше підказка під мишею не з'явиться.
		cell.mouse_filter = Control.MOUSE_FILTER_PASS
		cell.tooltip_text = "%s\n%s ×%.2f\n%s" % [title,
				STAT_TITLES.get(str(one[1]), str(one[1])), factor,
				"поки живий" if left < 0 else "лишилось %d с" % left]
		holder.add_child(cell)
		_plate(Vector2(STATE_SIDE, STATE_SIDE),
				BUFF_EDGE if factor >= 1.0 else DEBUFF_EDGE, cell)
		var inner := _plate(Vector2(STATE_SIDE - 4.0, STATE_SIDE - 4.0),
				Color(0, 0, 0, 0.8), cell)
		inner.position = Vector2(2, 2)
		# Значок того скіла, від якого стан: назва стану й ключ скіла
		# різняться лише пробілом і дефісом.
		var art := SkillIcons.of(title.replace(" ", "-"))
		if art == null:
			art = SkillIcons.of(title)
		if art != null:
			var icon := TextureRect.new()
			icon.texture = art
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_SCALE
			icon.position = Vector2(2, 2)
			icon.size = Vector2(STATE_SIDE - 4.0, STATE_SIDE - 4.0)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(icon)
		else:
			var letters := ""
			for word in title.split(" ", false):
				letters += word.substr(0, 1).to_upper()
			var mark := _text(12, cell)
			mark.text = letters.substr(0, 2)
			mark.position = Vector2(4, 4)
		if left >= 0:
			var seconds := _text(11, cell)
			seconds.text = str(left)
			seconds.position = Vector2(STATE_SIDE - 16.0, STATE_SIDE - 16.0)


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

	# Дві комірки поруч зі здоров'ям/маною: ліва — те, що спрацює
	# найпершим, права — наступне. Коли ліва йде з черги, права сама
	# посувається на її місце — це просто той самий масив на кадр пізніше.
	for i in _queue_cells.size():
		var action: String = queue[i] if i < queue.size() else ""
		var label: Label = _queue_cells[i]["label"]
		var icon: TextureRect = _queue_cells[i]["icon"]
		var tex := _bar_icon(action) if action != "" else null
		icon.visible = tex != null
		if tex != null:
			icon.texture = tex
		label.visible = tex == null
		label.text = _title(action)
	_queue_text.text = "замах %.2f" % busy_in if busy_in > 0.0 else ""


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
	if Net.connected():
		var me: Node3D = _world.creatures.get(_world.multiplayer.get_unique_id())
		if me != null:
			_coords_text.text = "x %.1f  y %.1f  z %.1f" \
					% [me.global_position.x, me.global_position.y,
					   me.global_position.z]
			# Червона крапка на карті — з тієї самої позиції, що й
			# координати в куті. Тільки коли карта відкрита: закрита
			# вона перемальовувалась би даремно.
			if _map_box != null and _map_box.visible:
				# Кут — той, на який персонаж повернутий на екрані
				# (`rotation.y` плавно доганяє те, що каже сервер).
				_map_view.show_me(me.global_position, me.rotation.y)
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
		var who: Node3D = item["who"]
		var head: Vector3 = who.global_position + Vector3(0,
				who.call("head_y") if who.has_method("head_y") else 1.6, 0)
		if camera.is_position_behind(head):
			label.visible = false
			continue
		label.visible = true
		label.position = camera.unproject_position(head) \
				- Vector2(label.size.x * 0.5, gone * FLOAT_RISE)
		label.modulate.a = 1.0 - gone * gone
