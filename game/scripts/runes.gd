class_name Runes
extends RefCounted
## Вивчення й підняття рівня скілів (крок 2.5).
##
## Правила замовника (02.09.2026):
##
##   вивчити скіл    — одна руна цього скіла + досвід;
##   підняти рівень  — одна руна ІНШОГО типу: руна підняття відповідного
##                     грейду, плюс досвід;
##   грейди          — E · D · C · B · A · S · SS, спільні зі зброєю.
##
## Клас нічого не знає ні про мережу, ні про вузли: вирішує «можна чи ні»
## і повертає причину словами, які видно гравцеві.

## Ім'я руни підняття для грейду. Руна вивчення в кожного скіла своя й
## записана в `data/skills.json`.
const LEVEL_RUNE := "руна підняття %s грейду"

var _skills: SkillBook


func _init(book: SkillBook = null) -> void:
	_skills = book if book != null else SkillBook.new()


static func level_rune_for(grade: String) -> String:
	return LEVEL_RUNE % grade


## Вивчити скіл. Повертає порожній рядок, якщо вийшло, або причину.
##
## Перевірки йдуть від найдешевшої до найдорожчої, а найголовніше — від
## тієї, що взагалі неможлива, до тієї, що поправна: спершу «немає такого
## скіла», далі «зарано за рівнем», і аж потім руна й досвід, бо їх
## гравець може піти й здобути.
func learn(who: Node, key: String) -> String:
	var skill: Skill = _skills.get_skill(key)
	if skill == null:
		return "такого вміння немає"
	if who.knows(key):
		return "%s уже вивчено" % skill.name
	if who.level < skill.from_level:
		return "%s вивчається з %d рівня" % [skill.name, skill.from_level]
	if skill.requires != "" and not who.knows(skill.requires):
		var need: Skill = _skills.get_skill(skill.requires)
		return "спершу потрібно: %s" \
				% (need.name if need != null else skill.requires)
	if skill.rune != "" and not who.has_item(skill.rune):
		return "потрібна %s" % skill.rune
	if who.experience < skill.learn_cost:
		return "бракує досвіду: %d із %d" % [who.experience, skill.learn_cost]

	who.take_item(skill.rune)
	who.experience -= skill.learn_cost
	who.learn(key, 1)
	return ""


## Підняти рівень скіла на один. Потрібна руна підняття ТОГО грейду, у
## якому скіл зараз, і досвід.
func raise(who: Node, key: String) -> String:
	var skill: Skill = _skills.get_skill(key)
	if skill == null:
		return "такого вміння немає"
	if not who.knows(key):
		return "%s не вивчено" % skill.name
	var level: int = who.learned[key]
	if level >= skill.max_level():
		return "%s уже найвищого рівня в %s грейді" % [skill.name, skill.grade]

	var rune := level_rune_for(skill.grade)
	if not who.has_item(rune):
		return "потрібна %s" % rune
	var cost: int = raise_cost(skill, level)
	if who.experience < cost:
		return "бракує досвіду: %d із %d" % [who.experience, cost]

	who.take_item(rune)
	who.experience -= cost
	who.learn(key, level + 1)
	return ""


## Скільки досвіду коштує наступний рівень.
##
## Правило замовника: досвіду має **завжди трохи бракувати** — 20–40%
## після того, як щось стало доступним. Тому підняття коштує частку від
## вивчення, і частка росте з рівнем: перший крок дешевий, останній
## відчутний.
const RAISE_SHARE := 0.35


static func raise_cost(skill: Skill, from_level: int) -> int:
	return maxi(1, roundi(skill.learn_cost * RAISE_SHARE * from_level))
