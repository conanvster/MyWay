class_name GameSettings
extends RefCounted
## Налаштування гравця: розмір вікна, повний екран, масштаб показу й
## розкладка блоків показу (слово замовника 27.11.2026: «додати в панелі
## кнопку налаштування, де можна вибрати бажану роздільну здатність та
## перемкнути в повноекранний режим; елементи інтерфейсу зробити
## рухливими з можливістю згорнути та пересунути»).
##
## Лежить у `user://settings.cfg` — у теці користувача, не в грі: гра
## оновлюється апдейтером, а налаштування мають це пережити.
##
## Проби й сервер цього файлу не читають і не пишуть: `active` вмикає лише
## стартова сторінка, коли її бачить живий гравець. Інакше знімок проби
## залежав би від того, як гравець розклав собі екран.

const PATH := "user://settings.cfg"

## Розміри вікна на вибір. Більші за екран у список не потрапляють.
const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1366, 768),
		Vector2i(1600, 900), Vector2i(1728, 972), Vector2i(1920, 1080),
		Vector2i(2560, 1440), Vector2i(3840, 2160)]
## Масштаб показу: у project.godot стоїть 1,5. На вузькому вікні менший
## масштаб дає більше місця, на великому екрані більший — дрібноту видно.
const SCALES: Array[float] = [1.0, 1.25, 1.5, 1.75, 2.0]
const DEFAULT_SCALE := 1.5

static var active := false
static var _cfg: ConfigFile


static func _file() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		if active:
			_cfg.load(PATH)
	return _cfg


static func get_value(section: String, key: String,
		fallback: Variant) -> Variant:
	return _file().get_value(section, key, fallback)


static func set_value(section: String, key: String, value: Variant) -> void:
	_file().set_value(section, key, value)
	if active:
		_cfg.save(PATH)


static func forget(section: String) -> void:
	if _file().has_section(section):
		_cfg.erase_section(section)
		if active:
			_cfg.save(PATH)


## Розміри, що вміщаються на поточний екран (рамка вікна теж їсть місце,
## тож рівний екранові розмір лишаємо — він для повного екрана).
static func sizes_for_screen() -> Array[Vector2i]:
	var screen := DisplayServer.screen_get_size()
	var out: Array[Vector2i] = []
	for one in SIZES:
		if one.x <= screen.x and one.y <= screen.y:
			out.append(one)
	if out.is_empty():
		out.append(SIZES[0])
	return out


## Поставити збережене: викликає стартова сторінка один раз.
static func apply_saved(window: Window) -> void:
	active = true
	_cfg = null
	var scale := float(get_value("екран", "масштаб", DEFAULT_SCALE))
	window.content_scale_factor = scale
	if bool(get_value("екран", "повний", false)):
		window.mode = Window.MODE_FULLSCREEN
	else:
		var want: Vector2i = get_value("екран", "розмір", Vector2i.ZERO)
		if want != Vector2i.ZERO:
			set_window_size(window, want, false)


static func set_fullscreen(window: Window, on: bool) -> void:
	set_value("екран", "повний", on)
	if on:
		window.mode = Window.MODE_FULLSCREEN
	else:
		window.mode = Window.MODE_WINDOWED
		var want: Vector2i = get_value("екран", "розмір", window.size)
		set_window_size(window, want, false)


## Новий розмір вікна — і посередині екрана, бо інакше збільшене вікно
## вилазить за правий нижній край.
static func set_window_size(window: Window, want: Vector2i,
		remember: bool = true) -> void:
	if remember:
		set_value("екран", "розмір", want)
	if window.mode != Window.MODE_WINDOWED:
		return
	window.size = want
	var screen := DisplayServer.screen_get_usable_rect(window.current_screen)
	window.position = screen.position + (screen.size - want) / 2


static func set_scale(window: Window, scale: float) -> void:
	set_value("екран", "масштаб", scale)
	window.content_scale_factor = scale
