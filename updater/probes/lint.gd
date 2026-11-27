extends Node
## Лінтер апдейтера: чи компілюється кожен скрипт, плюс домовленості
## проєкту (табуляція, рядок до 79 знаків). Той самий підхід, що й
## `game/probes/lint.gd`:
##     godot --headless --path updater res://scenes/lint.tscn

const LINE_LIMIT := 79

var _errors: Array[String] = []
var _warnings: Array[String] = []


func _ready() -> void:
	var files: Array[String] = []
	_collect("res://", files)
	for path in files:
		var script: Script = load(path)
		var err := script.reload() if script != null else ERR_CANT_OPEN
		if script == null or not script.can_instantiate() \
				or (err != OK and err != ERR_ALREADY_IN_USE):
			_errors.append("%s не компілюється: %s" % [path,
					error_string(err)])
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			var line: String = lines[i]
			var at := "%s:%d" % [path, i + 1]
			if line.ends_with(" ") or line.ends_with("\t"):
				_warnings.append("%s: пробіли в кінці рядка" % at)
			if line.begins_with("    "):
				_warnings.append("%s: відступ пробілами" % at)
			if line.replace("\t", "    ").length() > LINE_LIMIT:
				_warnings.append("%s: рядок довший за %d" % [at, LINE_LIMIT])
	print("перевірено скриптів: %d" % files.size())
	for line in _warnings:
		print("    · %s" % line)
	for line in _errors:
		print("    ‼ %s" % line)
	print("✓ помилок немає" if _errors.is_empty()
			else "✗ помилок: %d" % _errors.size())
	get_tree().quit(0 if _errors.is_empty() else 1)


func _collect(at: String, out: Array[String]) -> void:
	var dir := DirAccess.open(at)
	if dir == null:
		return
	for name in dir.get_directories():
		if not name.begins_with("."):
			_collect(at.path_join(name), out)
	for name in dir.get_files():
		if name.ends_with(".gd"):
			out.append(at.path_join(name))
