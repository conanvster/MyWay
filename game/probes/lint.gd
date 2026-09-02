extends Node
## Лінтер: чи ВЕСЬ код узагалі компілюється, і чи не порушено домовленостей.
##
## Ганяти так (через сцену, не `--script`):
##     godot --headless --path game res://scenes/lint.tscn
##
## Чому саме сценою. У режимі `--script` автозавантажень немає, і
## `world.gd` не компілюється через `Net` — тобто половина коду не
## перевіряється взагалі, а помилки виглядають як справжні. Запуск сцени
## автозавантаження підіймає, і `load()` каже правду.
##
## Це та сама діра, через яку в репозиторій потрапив код, що не
## компілювався: `godot --headless --path game --quit` відколи головною
## сценою стала стартова сторінка, відкриває саме її, а решту не чіпає.
##
## Виходить з кодом 1, якщо є хоч одна помилка. Зауваження коду не міняють:
## їх 55 на 8158 рядків, і зупиняти через них коміт — це вчити обходити
## перевірку.

## Довжина рядка, якої тримається проєкт.
const LINE_LIMIT := 79

var _errors: Array[String] = []
var _warnings: Array[String] = []
var _scripts := 0


func _ready() -> void:
	print("\n── лінтер ───────────────────────────────────────────────")
	var files: Array[String] = []
	_collect("res://", files)
	files.sort()
	for path in files:
		_compile(path)
		_read(path)
	_shell()

	print("\n  перевірено скриптів: %d" % _scripts)
	if not _warnings.is_empty():
		print("\n  зауваження (%d):" % _warnings.size())
		for line in _warnings:
			print("    · %s" % line)
	if _errors.is_empty():
		print("\n  ✓ помилок немає")
	else:
		print("\n  ✗ помилок: %d" % _errors.size())
		for line in _errors:
			print("    ‼ %s" % line)
	get_tree().quit(0 if _errors.is_empty() else 1)


func _collect(at: String, out: Array[String]) -> void:
	var dir := DirAccess.open(at)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var path: String = at.path_join(name)
		if dir.current_is_dir():
			if not name.begins_with("."):
				_collect(path, out)
		elif name.ends_with(".gd"):
			out.append(path)
		name = dir.get_next()
	dir.list_dir_end()


## Чи компілюється.
##
## Пильнувати: `load()` віддає скрипт НАВІТЬ із помилками розбору — на
## цьому перша ж перевірка мовчки пропустила зламаний `combat.gd`, хоч
## Godot друкував «Parse Error» поруч. Чесна ознака — `reload()`, вона
## вертає код помилки, і `can_instantiate()`, що на зламаному дає false.
func _compile(path: String) -> void:
	_scripts += 1
	var script: Script = load(path)
	if script == null:
		_errors.append("%s не вантажиться (текст помилки вище)" % path)
		return
	# `ERR_ALREADY_IN_USE` — не вада: так відповідають скрипти, що просто
	# зараз працюють (сам лінтер і автозавантаження `net.gd`). Ознака
	# зламаного — `can_instantiate() == false`.
	var err := script.reload()
	var broken: bool = not script.can_instantiate() \
			or (err != OK and err != ERR_ALREADY_IN_USE)
	if broken:
		_errors.append("%s не компілюється: %s (текст помилки вище)"
				% [path, error_string(err)])


func _read(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return
	var lines := text.split("\n")
	var rpc_above := false
	for i in lines.size():
		var line: String = lines[i]
		var at := "%s:%d" % [path, i + 1]

		# Лазівок у мережі не лишати: `test_teleport` дозволяв будь-якому
		# клієнтові переставити себе куди завгодно (CONTEXT.md).
		if rpc_above and line.begins_with("func "):
			var func_name: String = line.substr(5).split("(")[0]
			if func_name.begins_with("test_") or func_name.begins_with("тест"):
				_errors.append("%s: мережева лазівка `%s` — @rpc на пробу"
						% [at, func_name])
		# Зворотне: `client_*` БЕЗ позначки. Такий виклик мовчки не
		# доходить, а сервер отримує «Unable to get the RPC
		# configuration» — і клієнт просто не з'являється у світі.
		# Спіймано вручну: перестановка коментаря відірвала `@rpc` від
		# `client_spawn`, і гра перестала пускати гравця.
		if line.begins_with("func client_") and not rpc_above:
			_errors.append("%s: `%s` без @rpc — виклик нікуди не піде"
					% [at, line.substr(5).split("(")[0]])
		rpc_above = line.begins_with("@rpc")

		# Вічний цикл на `queue_free`. Видалення відкладене: доки кадр не
		# скінчився, вузол лишається в дереві, `get_child_count()` не
		# меншає — і `while` крутиться вічно. Ця вада поклала машину
		# двічі, тож нехай її ловить машина, а не людина.
		#
		# Дивимось ТІЛО циклу цілком, а не рядки поодинці: правильний код
		# виносить вузол `remove_child` одним рядком і зве `queue_free`
		# наступним, і по одному рядку його не відрізнити від хибного.
		if line.strip_edges().begins_with("while ") \
				and line.contains("get_child_count()"):
			var body := ""
			for step in range(i + 1, mini(i + 7, lines.size())):
				body += lines[step]
			if body.contains("queue_free()") and not body.contains("remove_child"):
				_errors.append("%s: вічний цикл — `queue_free` відкладений,"
						% at + " get_child_count() не змінюється;"
						+ " спершу remove_child")

		if line.ends_with(" ") or line.ends_with("\t"):
			_warnings.append("%s: пробіли в кінці рядка" % at)
		if line.begins_with("    "):
			_warnings.append("%s: відступ пробілами, а не табуляцією" % at)
		# Рахуємо ЗНАКИ, не байти: кирилиця важить два байти, і `awk` на
		# цьому місці показував 1290 задовгих рядків замість 55.
		var width: int = line.replace("\t", "    ").length()
		if width > LINE_LIMIT:
			_warnings.append("%s: рядок на %d знаків (межа %d)"
					% [at, width, LINE_LIMIT])


## Оболонкові скрипти: змінні лише латиницею.
##
## Кирилична назва змінної в bash тихо ламає масиви й `for` — на це вже
## наступали. Самі рядки й повідомлення українською лишаються.
func _shell() -> void:
	var root: String = ProjectSettings.globalize_path("res://").path_join("..")
	var dir := DirAccess.open(root)
	if dir == null:
		return
	for name in dir.get_files():
		if not name.ends_with(".sh"):
			continue
		var text := FileAccess.get_file_as_string(root.path_join(name))
		var lines := text.split("\n")
		for i in lines.size():
			var line: String = lines[i].strip_edges()
			var mark: int = line.find("=")
			if mark <= 0 or line.begins_with("#"):
				continue
			var left: String = line.substr(0, mark)
			if left.contains(" ") or left.contains("\""):
				continue
			for symbol in left:
				if symbol.unicode_at(0) > 127:
					_errors.append("%s:%d: кирилиця в імені змінної `%s`"
							% [name, i + 1, left])
					break
