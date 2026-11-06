class_name GameData
extends RefCounted
## Числа, які можна крутити без перезапуску сервера.
##
## Сервер раз на кілька секунд дивиться на час зміни файлів; змінився —
## перечитує й роздає живим монстрам. Тобто баланс правиться в
## `data/*.json` під час гри, і зміну видно на наступному ж ударі.
##
## Помилку не ковтаємо: зіпсований файл друкує, ЩО саме не так, і
## лишається чинним попереднє значення, а не нулі.

const MOBS_PATH := "res://data/mobs.json"
const BAR_PATH := "res://data/bar.json"
const SKILLS_PATH := "res://data/skills.json"
const LEVELS_PATH := "res://data/levels.json"
const ITEMS_PATH := "res://data/items.json"
const PROFS_PATH := "res://data/professions.json"
## Коваль: міцність зброї, ремонт, зачарування (21.09.2026).
const SMITH_PATH := "res://data/smith.json"
const MAP_PATH := "res://data/map.json"
## Світ версії 2 — згенерована карта (`tools/svit2.py`). Береться замість
## `map.json`, коли серверові дано `-- --світ2`. Версія 1 лишається за
## замовчуванням і не міняється від самої наявності цього файлу.
const MAP2_PATH := "res://data/map2.json"
## Як часто перевіряти, чи файли змінились.
const WATCH_EVERY := 2.0

## Світ, обраний на стартовій сторінці (П-204). Порожньо — беремо з
## прапорця, як і раніше.
##
## Чому статична змінна, а не аргумент: `map_path()` кличуть з п'яти
## місць у трьох файлах, і всі вони питають одне й те саме — «який світ
## у ЦЬОМУ процесі». Сервер — окремий процес, і він як був, так і
## лишається на прапорці: стартова сторінка піднімає його з `--світ2`
## чи без нього.
static var chosen_map := ""


## Який світ будувати. Прапорець читається один раз при кожному читанні
## даних, тож і сервер, і клієнт беруть той самий файл: обидва бачать ті
## самі аргументи після `--`.
##
## **Основний світ — версії 2** (П-205, слово замовника 19.09.2026:
## «хочу перевести Світ 1 в неактивний — використовувати тільки для
## тесту чогось, а основним зробити Світ 2»). Тому замовчування
## перевернуто: без прапорців береться `map2.json`, а світ 600 м
## вмикається окремим `--світ1`. З 06.11.2026 перевірки (`check.sh`,
## проби) ганяються на світі 2 — слово замовника: «перенеси всі типи
## тестів на нову карту, щоб не тестували автоматично на застарілому
## функціоналі». Світ 1 лишився лише для ручного перегляду.
##
## `--світ2` лишається чинним, хоч тепер і зайвим: його дають десятки
## рядків у скриптах, документах і звичках, і ламати їх заради
## однакового результату нема сенсу.
static func map_path() -> String:
	if chosen_map != "":
		return chosen_map
	return MAP_PATH if OS.get_cmdline_user_args().has("--світ1") \
			else MAP2_PATH


## Як світ зветься в базі й у звірці між сервером і клієнтом: іменем
## свого файлу («map.json» / «map2.json»). Другої схеми найменування не
## заводимо — цю вже знають і мітка готовності, і `client_which_world`.
static func world_key() -> String:
	return map_path().get_file()


## Числа за видами: "1" -> { помічає, повідець, ... }.
var mobs: Dictionary = {}
## Розкладка панелі за замовчуванням (П-58).
var bar: Array[String] = []
## Скіли: ключ -> Skill.
var skills := SkillBook.new()
## З чим персонаж заходить у світ: ключ скіла -> рівень. Заглушка до рун
## і крамниць (П-97).
var starting_skills: Dictionary = {}
## Сітка поваги й множники за різницю рівнів (крок 3).
var levels: Dictionary = {}
## Речі: бази й таблиця афіксів (крок 4).
var items := ItemBook.new()

## Коваль: міцність, ремонт і рунне посилення (21.09.2026).
var smith := Smith.new()

## Професії, етапи, квести переходу й приховані гілки (П-224).
var professions := Professions.new()
## Краєвид: місто, ліс, гори (крок 5, побажання замовника).
var map: Dictionary = {}

var _stamps: Dictionary = {}
var _since_check := 0.0


## Перше читання. Повертає false, якщо щось не прочиталось: тоді працюють
## сталі значення в коді, і про це сказано вголос.
func load_all() -> bool:
	var ok := true
	var read_mobs: Variant = _read(MOBS_PATH)
	if read_mobs is Dictionary:
		mobs = _only_data(read_mobs)
		print("[дані] видів монстрів: %d (%s)"
				% [mobs.size(), ", ".join(_names())])
	else:
		ok = false

	var read_skills: Variant = _read(SKILLS_PATH)
	if read_skills is Dictionary:
		skills.load_from(read_skills)
		print("[дані] скілів: %d (%s)" % [skills.count(), ", ".join(skills.keys())])
	else:
		ok = false

	var read_levels: Variant = _read(LEVELS_PATH)
	if read_levels is Dictionary:
		levels = read_levels
		print("[дані] сітка рівнів: основа %s, показник %s, очок статів %s"
				% [levels.get("основа"), levels.get("показник"),
				   levels.get("очок статів за рівень")])
	else:
		ok = false

	var read_items: Variant = _read(ITEMS_PATH)
	if read_items is Dictionary:
		items.load_from(read_items)
		print("[дані] речей: %d" % items.count())
	else:
		ok = false

	var read_smith: Variant = _read(SMITH_PATH)
	if read_smith is Dictionary:
		smith.load_from(read_smith)
		items.weapon_durability = int(read_smith.get("міцність", {})
				.get("зброя", 0))
		print("[дані] коваль: міцність зброї %d, зачарування %s"
				% [items.weapon_durability,
				   "є" if smith.has_rules() else "‼ немає"])
	else:
		ok = false

	var read_profs: Variant = _read(PROFS_PATH)
	if read_profs is Dictionary:
		professions.load_from(read_profs)
		print("[дані] професій: %d на %d етапах"
				% [professions.rows.size(), professions.stages.size()])
	else:
		ok = false

	var read_map: Variant = _read(map_path())
	if read_map is Dictionary:
		map = read_map
		# Рахуємо по списках (`міста`/`ліси`), але й старі одиничні
		# ключі (`місто`/`ліс`) досі читаються: світ виріс 05.09.2026, а
		# дані, збережені до того, лишились чинними. Без цього рядок
		# журналу тихо друкував нулі на живій мапі — а мовчазна неправда
		# в журналі гірша за помилку.
		var towns: Array = map.get("міста", [])
		if towns.is_empty() and map.has("місто"):
			towns = [map["місто"]]
		var woods: Array = map.get("ліси", [])
		if woods.is_empty() and map.has("ліс"):
			woods = [map["ліс"]]
		var houses := 0
		var folk := 0
		for town: Dictionary in towns:
			houses += Array(town.get("будинки", [])).size()
			folk += Array(town.get("мешканці", [])).size()
		var trees := 0
		for wood: Dictionary in woods:
			trees += int(wood.get("дерев", 0))
		print("[дані] мапа: %s — міст %d, будинків %d, мешканців %d, "
				% [map_path().get_file(), towns.size(), houses, folk]
				+ "лісів %d (дерев %d), гір %d, святинь %d"
				% [woods.size(), trees, map.get("гори", []).size(),
				   Array(map.get("святині", [])).size()])
		if int(map.get("версія", 1)) >= 2:
			var earth: Dictionary = map.get("земля", {})
			print("[дані] світ версії 2: сторона %s м, сітка %s, "
					% [earth.get("сторона"), earth.get("точок")]
					+ "сіл %d, орієнтирів %d, доріг %d, мостів %d"
					% [Array(map.get("села", [])).size(),
					   Array(map.get("орієнтири", [])).size(),
					   Array(map.get("дороги", [])).size(),
					   Array(map.get("мости", [])).size()])
	else:
		ok = false

	var read_bar: Variant = _read(BAR_PATH)
	if read_bar is Dictionary and read_bar.has("панель"):
		bar.assign(read_bar["панель"])
		starting_skills = read_bar.get("стартові скіли", {})
		print("[дані] панель: %s" % [bar])
		print("[дані] стартові скіли: %s" % [starting_skills])
	else:
		if read_bar is Dictionary:
			push_error("[дані] %s: немає ключа \"панель\"" % BAR_PATH)
			print("[дані] ‼ %s: немає ключа \"панель\"" % BAR_PATH)
		ok = false
	return ok


## Раз на WATCH_EVERY секунд дивиться, чи файли не змінились.
## Повертає true, якщо перечитав, — світові тоді треба роздати нові числа.
func poll(delta: float) -> bool:
	_since_check += delta
	if _since_check < WATCH_EVERY:
		return false
	_since_check = 0.0
	var changed := false
	for path in [MOBS_PATH, BAR_PATH, SKILLS_PATH, LEVELS_PATH, ITEMS_PATH,
			PROFS_PATH, SMITH_PATH, map_path()]:
		var stamp := _stamp(path)
		if stamp != 0 and _stamps.get(path, 0) != stamp:
			changed = true
	if not changed:
		return false
	print("[дані] файли змінились — перечитую")
	load_all()
	return true


## Числа одного виду. Немає такого виду — гучно кажемо й даємо порожнє:
## монстр тоді працює на сталих значеннях mob.gd.
func for_kind(kind: int) -> Dictionary:
	# Вартовий поселення (П-262) — роль, а не вид бестіарію: його числа в
	# мапі, а не в `mobs.json`.
	if kind == Wardens.GUARD_KIND:
		return map.get("охорона поселень", {}).get("вартовий", {})
	var key := str(kind)
	if not mobs.has(key):
		push_error("[дані] виду %d немає в %s" % [kind, MOBS_PATH])
		print("[дані] ‼ виду %d немає в %s — беру сталі числа коду"
				% [kind, MOBS_PATH])
		return {}
	return mobs[key]


func _names() -> Array:
	var out: Array = []
	for key in mobs:
		out.append("%s=%s" % [key, mobs[key].get("назва", "?")])
	return out


## Ключі, що починаються з «_», — це пояснення для людини, не дані.
func _only_data(raw: Dictionary) -> Dictionary:
	var out := {}
	for key in raw:
		if not str(key).begins_with("_"):
			out[key] = raw[key]
	return out


func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("[дані] немає файлу %s" % path)
		print("[дані] ‼ немає файлу %s" % path)
		return null
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("[дані] %s, рядок %d: %s"
				% [path, json.get_error_line(), json.get_error_message()])
		print("[дані] ‼ %s, рядок %d: %s — лишаю попередні числа"
				% [path, json.get_error_line(), json.get_error_message()])
		return null
	_stamps[path] = _stamp(path)
	return json.data


func _stamp(path: String) -> int:
	return FileAccess.get_modified_time(path)
