class_name HitchLog
## Журнал підвисань клієнта (слово замовника 27.11.2026: «коли я біжу по
## місцевості і добігаю до нових монстрів, вони починають підвантажуватись і
## зображення на секунду завмирає» → «так, я заміряю на iMac»).
##
## Кожен кадр довший за `SLOW_MS` пишеться в `user://pidvysannia.log` разом із
## тим, що сталося перед ним (`note`): зібрано модель, перший показ моделі
## тощо. Так видно, який крок винен: збирання сцени, завантаження у
## відеокарту чи підготовка шейдерів. Кадр без жодної позначки — «причина
## невідома» (підвантаження землі, лісу, щось інше).

const SLOW_MS := 50.0
const FILE := "user://pidvysannia.log"
## Скільки останніх подій тримати: підвисання видно на НАСТУПНОМУ кадрі
## після того, що його спричинило.
const KEEP := 12

static var _events: Array[String] = []
static var _last_usec := 0
static var _file: FileAccess = null
static var _count := 0
static var _worst := 0.0


static func start(version: String) -> void:
	_file = FileAccess.open(FILE, FileAccess.WRITE)
	if _file == null:
		print("[підвисання] ‼ не відкрити %s: %s" % [FILE,
				error_string(FileAccess.get_open_error())])
		return
	var size := DisplayServer.window_get_size()
	_write("═══ %s · гра %s · %s · %s (%s) · вікно %dx%d · масштаб %.2f" % [
			Time.get_datetime_string_from_system(false, true), version,
			OS.get_name(), RenderingServer.get_video_adapter_name(),
			RenderingServer.get_current_rendering_driver_name(),
			size.x, size.y, DisplayServer.screen_get_scale()])
	_write("Кадри довші за %d мс. Формат: час · тривалість кадру · що було перед ним" % SLOW_MS)
	print("[підвисання] журнал: %s" % ProjectSettings.globalize_path(FILE))


## Позначити подію (з часом у мс, якщо міряли).
static func note(text: String) -> void:
	_events.append("%s" % text)
	if _events.size() > KEEP:
		_events.remove_at(0)


## Раз на кадр (клієнт світу).
static func tick() -> void:
	var now := Time.get_ticks_usec()
	if _last_usec == 0:
		_last_usec = now
		return
	var ms := (now - _last_usec) / 1000.0
	_last_usec = now
	if ms >= SLOW_MS:
		_count += 1
		_worst = maxf(_worst, ms)
		_write("%s · %4.0f мс · %s" % [Time.get_time_string_from_system(), ms,
				"; ".join(_events) if not _events.is_empty()
				else "причина невідома"])
	_events.clear()


## Підсумок — при виході зі світу.
static func finish() -> void:
	if _file == null:
		return
	_write("─── підвисань: %d, найдовше %.0f мс" % [_count, _worst])
	_file.close()
	_file = null


## Міряти виклик: `HitchLog.timed("вовк: збирання", func(): …)`.
static func timed(what: String, work: Callable) -> void:
	var from := Time.get_ticks_usec()
	work.call()
	note("%s %.0f мс" % [what, (Time.get_ticks_usec() - from) / 1000.0])


static func _write(line: String) -> void:
	if _file == null:
		return
	_file.store_line(line)
	_file.flush()
