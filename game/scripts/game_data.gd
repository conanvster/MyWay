class_name GameData
extends RefCounted
## Числа, які можна крутити без перезапуску сервера.
##
## Сервер раз на кілька секунд дивиться на час зміни файлів; змінився —
## перечитує й роздає живим монстрам. Тобто баланс правиться в
## `дані/*.json` під час гри, і зміну видно на наступному ж ударі.
##
## Помилку не ковтаємо: зіпсований файл друкує, ЩО саме не так, і
## лишається чинним попереднє значення, а не нулі.

const MOBS_PATH := "res://дані/монстри.json"
const BAR_PATH := "res://дані/панель.json"
const SKILLS_PATH := "res://дані/скіли.json"
const LEVELS_PATH := "res://дані/рівні.json"
const ITEMS_PATH := "res://дані/речі.json"
## Як часто перевіряти, чи файли змінились.
const WATCH_EVERY := 2.0

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
	for path in [MOBS_PATH, BAR_PATH, SKILLS_PATH, LEVELS_PATH, ITEMS_PATH]:
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
