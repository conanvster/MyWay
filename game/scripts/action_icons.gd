class_name ActionIcons
extends RefCounted
## Малюнки голих умінь (удар, наступна ціль...): ключ файлу — точний
## код дії з `actions.gd` (наприклад «attack», «next_mob»). Той самий
## принцип, що й малюнки речей і скілів — підклав
## `assets/icons/actions/<код>.png`, код міняти не треба.
##
## Скіл і витратна річ мають своє (`skill_icon.gd`, `item_icon.gd`);
## сюди йде решта — те, що в панелі досі було лише текстом.

const ART_DIR := "res://assets/icons/actions/"

static var _art: Dictionary = {}
static var _loaded := false


static func of(action: String) -> Texture2D:
	_load()
	return _art.get(action)


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
