class_name SkillIcons
extends RefCounted
## Малюнки скілів: ключ файлу — точний ключ скіла з `data/skills.json`
## (наприклад «енергетичний-вибух»). Підклав
## `assets/icons/skills/<ключ>.png` — скіл дістав значок сам, код
## міняти не треба. Той самий принцип, що й малюнки речей
## (`item_icon.gd`).
##
## Немає малюнка (ще не намальований скіл) — виклик просто повертає
## `null`, і той, хто питав, лишається на своєму текстовому запасному
## варіанті.

const ART_DIR := "res://assets/icons/skills/"

static var _art: Dictionary = {}
static var _loaded := false


## Малюнок скіла за ключем або `null`, якщо його ще не намальовано.
static func of(key: String) -> Texture2D:
	_load()
	return _art.get(key)


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var dir := DirAccess.open(ART_DIR)
	if dir == null:
		return
	for file in dir.get_files():
		if file.get_extension() != "png":
			continue
		var tex := load(ART_DIR + file) as Texture2D
		if tex != null:
			_art[file.get_basename()] = tex
