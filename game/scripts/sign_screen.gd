class_name SignScreen
extends CanvasLayer
## Екран входу й вибору персонажа (крок 5, П-12, П-13).
##
## Будується кодом, як і HUD: полів тут десяток, і в редакторі їх довелось
## би перебирати після кожної зміни.
##
## Екран нічого не вирішує сам: він лише збирає введене й віддає його
## серверові. Пароль перевіряє база, і навіть сервер гри його не знає
## далі за один виклик (П-114).

signal wants_sign_in(login: String, password: String, register: bool)
signal wants_new_character(name: String, race: String, sex: String,
		look: Dictionary)
signal wants_enter(character: String)

const WIDE := 380.0
const BACK := Color(0.06, 0.07, 0.09, 0.92)

var _root: Control
var _login: LineEdit
var _password: LineEdit
var _why: Label
var _sign_box: VBoxContainer
var _sign_in: Button
var _sign_up: Button
var _pick_box: VBoxContainer
var _list: VBoxContainer
var _new_name: LineEdit
var _race: OptionButton
var _sex: OptionButton
var _create: Button
var _back: Button
## Зовнішність (07.11.2026): модель, що обертається, і вибір під нею.
var _look_box: VBoxContainer
var _pick_line: HBoxContainer
var _look_grid: GridContainer
var _look_note: Label
var _variant: OptionButton
var _stage: SubViewport
var _turntable: Node3D
var _preview: SkinnedModel
var _chosen: Dictionary = {"варіант": 1}
const LOOK_WIDE := 300.0
const AVATAR := preload("res://scripts/avatar.gd")


func setup() -> void:
	layer = 20
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var back := ColorRect.new()
	back.color = Color(0.02, 0.03, 0.05, 0.96)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(back)

	_sign_box = _column("Вхід", 0)
	_login = _field(_sign_box, "акаунт", false)
	_password = _field(_sign_box, "пароль", true)
	_login.text_submitted.connect(func(_t: String) -> void: _send(false))
	_password.text_submitted.connect(func(_t: String) -> void: _send(false))
	_sign_in = _button(_sign_box, "Увійти", func() -> void: _send(false))
	_sign_up = _button(_sign_box, "Завести акаунт",
			func() -> void: _send(true))

	_pick_box = _column("Персонажі", 0)
	_pick_box.visible = false
	# Поля й зовнішність — один рядок посередині (прив'язка «до центру» з
	# ручним зсувом з'їжджала за лівий край вікна).
	var middle := CenterContainer.new()
	middle.set_anchors_preset(Control.PRESET_FULL_RECT)
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(middle)
	_pick_line = HBoxContainer.new()
	_pick_line.add_theme_constant_override("separation", 24)
	middle.add_child(_pick_line)
	_root.remove_child(_pick_box)
	_pick_box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_pick_box.position = Vector2.ZERO
	_pick_line.add_child(_pick_box)
	_list = VBoxContainer.new()
	_pick_box.add_child(_list)
	_new_name = _field(_pick_box, "ім'я нового персонажа", false)
	_race = _choice(_pick_box, ["людина", "орк", "ельф"])
	_sex = _choice(_pick_box, ["чоловік", "жінка"])
	_variant = _choice(_pick_box, [])
	_race.item_selected.connect(func(_i: int) -> void: _refresh_preview())
	_sex.item_selected.connect(func(_i: int) -> void: _refresh_preview())
	_variant.item_selected.connect(func(i: int) -> void:
			_chosen = {"варіант": i + 1}
			_refresh_preview())
	_build_look_box()
	_new_name.text_submitted.connect(func(_t: String) -> void: _create_now())
	_create = _button(_pick_box, "Створити", func() -> void: _create_now())
	# «Назад» — на випадок, коли ввійшли не на той акаунт: без неї єдиний
	# спосіб передумати — перезапустити клієнта цілком.
	_back = _button(_pick_box, "← Назад", func() -> void:
			_pick_box.visible = false
			_look_box.visible = false
			_sign_box.visible = true
			_password.text = ""
			_why.text = ""
			_sign_in.disabled = false
			_sign_up.disabled = false)

	_why = Label.new()
	_why.add_theme_color_override("font_color", Color(1, 0.6, 0.5))
	_why.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_why.position = Vector2(-WIDE * 0.5, -60)
	_why.size = Vector2(WIDE, 24)
	_why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_why)


func _column(title: String, shift: float) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-WIDE * 0.5 + shift, -150)
	box.custom_minimum_size = Vector2(WIDE, 0)
	box.add_theme_constant_override("separation", 10)
	_root.add_child(box)
	var head := Label.new()
	head.text = title
	head.add_theme_font_size_override("font_size", 22)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	return box


func _field(box: VBoxContainer, hint: String, secret: bool) -> LineEdit:
	var line := LineEdit.new()
	line.placeholder_text = hint
	line.secret = secret
	line.custom_minimum_size = Vector2(WIDE, 34)
	box.add_child(line)
	return line


func _choice(box: VBoxContainer, options: Array) -> OptionButton:
	var pick := OptionButton.new()
	for text: String in options:
		pick.add_item(text)
	pick.custom_minimum_size = Vector2(WIDE, 32)
	box.add_child(pick)
	return pick


func _button(box: VBoxContainer, text: String, action: Callable) -> Button:
	var press := Button.new()
	press.text = text
	press.custom_minimum_size = Vector2(WIDE, 34)
	press.pressed.connect(action)
	box.add_child(press)
	return press


func _send(register: bool) -> void:
	var login := _login.text.strip_edges()
	if login == "" or _password.text == "":
		_why.text = "акаунт і пароль не можуть бути порожні"
		return
	_why.text = "…"
	_sign_in.disabled = true
	_sign_up.disabled = true
	wants_sign_in.emit(login, _password.text, register)


func _create_now() -> void:
	if _new_name.text.strip_edges() == "":
		return
	_why.text = "…"
	_create.disabled = true
	wants_new_character.emit(_new_name.text.strip_edges(),
			_race.get_item_text(_race.selected),
			_sex.get_item_text(_sex.selected), _chosen.duplicate())


## Сервер відповів «не вдалось» — кажемо чому, поле лишаємо як є.
##
## Кнопки, вимкнені на час очікування, вмикаємо назад: без цього після
## однієї відмови (не той пароль, зайняте ім'я) екран лишався б мертвим,
## поки людина не здогадається, що можна перезапустити клієнта.
func failed(why: String) -> void:
	_why.text = why
	_sign_in.disabled = false
	_sign_up.disabled = false
	_create.disabled = false


## Увійшли: показуємо персонажів. Порожній перелік — теж відповідь, просто
## значить, що першого треба створити.
func show_characters(list: Array) -> void:
	_sign_box.visible = false
	_pick_box.visible = true
	_look_box.visible = true
	if _preview == null:
		_refresh_preview()
	_why.text = "" if not list.is_empty() else "персонажів ще немає — створи"
	_create.disabled = false
	_new_name.text = ""
	for child in _list.get_children():
		child.queue_free()
	for who: Dictionary in list:
		var name: String = str(who.get("name", "?"))
		var press := Button.new()
		press.text = "%s — %s %s, рівень %d" % [name,
				who.get("race", "?"), who.get("sex", "?"),
				int(who.get("level", 1))]
		press.custom_minimum_size = Vector2(WIDE, 34)
		press.pressed.connect(func() -> void: wants_enter.emit(name))
		_list.add_child(press)


## Зайшли у світ — екран більше не потрібен.
func done() -> void:
	queue_free()


# ── зовнішність ─────────────────────────────────────────────────────────


## Панель праворуч: сцена з моделлю (своє 3D-місце — у світі ще нічого
## немає) і сітка «назва — вибір».
func _build_look_box() -> void:
	# Три колонки: поля, модель, вибір.
	_look_box = VBoxContainer.new()
	_look_box.add_theme_constant_override("separation", 6)
	_look_box.visible = false
	_pick_line.add_child(_look_box)
	var head := Label.new()
	head.text = "Зовнішність"
	head.add_theme_font_size_override("font_size", 22)
	_look_box.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	_look_box.add_child(row)
	var frame := SubViewportContainer.new()
	frame.custom_minimum_size = Vector2(260, 440)
	frame.stretch = true
	row.add_child(frame)
	_stage = SubViewport.new()
	_stage.own_world_3d = true
	_stage.transparent_bg = true
	frame.add_child(_stage)
	var sky := WorldEnvironment.new()
	sky.environment = Environment.new()
	sky.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	sky.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	sky.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_stage.add_child(sky)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	sun.light_energy = 1.3
	_stage.add_child(sun)
	var eye := Camera3D.new()
	eye.fov = 28.0
	eye.position = Vector3(0, 1.0, 4.6)
	eye.look_at_from_position(eye.position, Vector3(0, 0.95, 0))
	_stage.add_child(eye)
	_turntable = Node3D.new()
	_stage.add_child(_turntable)
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(LOOK_WIDE, 0)
	side.add_theme_constant_override("separation", 8)
	row.add_child(side)
	_look_grid = GridContainer.new()
	_look_grid.columns = 2
	_look_grid.add_theme_constant_override("h_separation", 8)
	side.add_child(_look_grid)
	_look_note = Label.new()
	_look_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_look_note.custom_minimum_size = Vector2(LOOK_WIDE, 0)
	_look_note.add_theme_color_override("font_color", Color(0.85, 0.8, 0.6))
	side.add_child(_look_note)


func _process(delta: float) -> void:
	if _turntable != null and _look_box.visible:
		_turntable.rotation.y += delta * 0.5


## Раса, стать чи варіант змінились — нова модель і новий перелік виборів
## (зачіски й риси в кожної моделі свої).
func _refresh_preview() -> void:
	var race := _race.get_item_text(_race.selected)
	var sex := _sex.get_item_text(_sex.selected)
	var ready: int = Appearance.ready_variants(race, sex)
	var keep := int(_chosen.get("варіант", 1))
	_variant.clear()
	for v in Appearance.VARIANTS:
		_variant.add_item("варіант %d%s" % [v + 1,
				"" if v < ready else " — ще не зроблено"])
	_variant.select(clampi(keep - 1, 0, Appearance.VARIANTS - 1))
	if _preview != null:
		_preview.queue_free()
		_preview = null
	var scan: String = Appearance.model_of(race, sex, keep)
	var who := "жінка" if sex == "жінка" else "чоловік"
	_preview = SkinnedModel.new()
	_preview.path = scan if scan != "" else AVATAR.RACE_MODEL % [race, who]
	_preview.anim_path = AVATAR.MODEL_ANIM
	_preview.height = float(AVATAR.RACE_HEIGHT.get(race, 1.75))
	_turntable.add_child(_preview)
	_preview.build()
	_turntable.rotation.y = PI
	if scan == "":
		_look_note.text = "Сканованої моделі «%s, %s» ще немає — показано " \
				% [race, sex] + "просту; вибір зовнішності з'явиться з нею."
	elif keep > ready:
		_look_note.text = "Варіанта %d ще немає — показано варіант 1." % keep
	else:
		_look_note.text = ""
	_fill_choices(scan != "")


func _fill_choices(scanned: bool) -> void:
	for child in _look_grid.get_children():
		child.queue_free()
	if not scanned:
		return
	var o := _preview.look_options()
	var styles: Array = []
	for st: String in o["зачіски"]:
		styles.append([st, st])
	if not styles.is_empty():
		styles.append(["без волосся", "без"])
		_choice_row("Зачіска", styles, "зачіска")
	var pairs := func(palette: Array) -> Array:
		var out: Array = []
		for row: Array in palette:
			out.append([row[0], row[0]])
		return out
	if not styles.is_empty():
		_choice_row("Волосся", pairs.call(Appearance.HAIR), "волосся",
				Appearance.HAIR)
	if o["маски"]:
		_choice_row("Очі", pairs.call(Appearance.EYES), "очі", Appearance.EYES)
		_choice_row("Шкіра", pairs.call(Appearance.SKIN), "шкіра",
				Appearance.SKIN)
		_choice_row("Губи", pairs.call(Appearance.LIPS), "губи", Appearance.LIPS)
		_choice_row("Підводка", pairs.call(Appearance.LINER), "підводка")
	_preview.customize(Appearance.to_look(_chosen))


## Рядок сітки: підпис і список. `palette` — щоб показати зразок кольору.
func _choice_row(title: String, items: Array, key: String,
		palette: Array = []) -> void:
	var label := Label.new()
	label.text = title
	_look_grid.add_child(label)
	var pick := OptionButton.new()
	pick.custom_minimum_size = Vector2(LOOK_WIDE - 90, 28)
	pick.clip_text = true
	var at := 0
	for i in items.size():
		var colour: Variant = palette[i][1] if i < palette.size() else null
		if colour is Color:
			var img := Image.create(14, 14, false, Image.FORMAT_RGB8)
			img.fill(colour)
			pick.add_icon_item(ImageTexture.create_from_image(img),
					items[i][0], i)
		else:
			pick.add_item(items[i][0], i)
		if str(_chosen.get(key, "")) == str(items[i][1]):
			at = i
	pick.select(at)
	pick.item_selected.connect(func(i: int) -> void:
			_chosen[key] = items[i][1]
			_preview.customize(Appearance.to_look(_chosen)))
	_look_grid.add_child(pick)
