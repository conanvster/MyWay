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
signal wants_new_character(name: String, race: String, sex: String)
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
	_list = VBoxContainer.new()
	_pick_box.add_child(_list)
	_new_name = _field(_pick_box, "ім'я нового персонажа", false)
	_race = _choice(_pick_box, ["людина", "орк", "ельф"])
	_sex = _choice(_pick_box, ["чоловік", "жінка"])
	_new_name.text_submitted.connect(func(_t: String) -> void: _create_now())
	_create = _button(_pick_box, "Створити", func() -> void: _create_now())
	# «Назад» — на випадок, коли ввійшли не на той акаунт: без неї єдиний
	# спосіб передумати — перезапустити клієнта цілком.
	_back = _button(_pick_box, "← Назад", func() -> void:
			_pick_box.visible = false
			_sign_box.visible = true
			_password.text = ""
			_why.text = ""
			_sign_in.disabled = false
			_sign_up.disabled = false)

	_why = Label.new()
	_why.add_theme_color_override("font_color", Color(1, 0.6, 0.5))
	_why.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_why.position = Vector2(-WIDE * 0.5, -80)
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
			_sex.get_item_text(_sex.selected))


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
