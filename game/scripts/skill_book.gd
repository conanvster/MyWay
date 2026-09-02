class_name SkillBook
extends RefCounted
## Усі скіли, прочитані з `data/skills.json`.
##
## Живе поруч із `game_data.gd` і перечитується разом із ним: правиш
## число в файлі — бачиш його в грі без перезапуску сервера (крок 1.2).

var _by_key: Dictionary = {}


func load_from(raw: Dictionary) -> void:
	_by_key.clear()
	for key in raw:
		if str(key).begins_with("_"):
			continue
		_by_key[key] = Skill.from_data(key, raw[key])


func has(key: String) -> bool:
	return _by_key.has(key)


func get_skill(key: String) -> Skill:
	return _by_key.get(key)


func keys() -> Array:
	return _by_key.keys()


func count() -> int:
	return _by_key.size()
