class_name MobAI
extends RefCounted
## Поведінка монстрів (П-66, П-71).
##
## Самі правила живуть у `mob.gd` — блукання, вдача, таблиця загрози.
## Тут тільки порядок, у якому вони застосовуються, і те, для чого
## монстрові потрібен решта світу: кого він бачить і кого гукає.

var _creatures: Dictionary
var _combat: Combat


func _init(creatures: Dictionary = {}, combat: Combat = null) -> void:
	_creatures = creatures
	_combat = combat if combat != null else Combat.new(creatures)


func think(id: int, delta: float) -> void:
	var m: Node = _creatures[id]
	if not m.is_alive():
		return

	var players := {}
	for other in _creatures:
		if other > 0 and _creatures[other].is_alive():
			players[other] = _creatures[other]

	# Відбіг задалеко від дому — розвертається й геть забуває кривдника.
	if m.too_far_from_home():
		m.forget()
		m.target_id = 0
		m.head_to(m.home, 1.0)
		return

	# Кого ненавидить найбільше; якщо нікого — агресивний виглядає жертву.
	var victim: int = m.top_threat(players)
	if victim == 0:
		victim = m.notice(players, delta)
		if victim != 0:
			m.add_threat(victim, 1.0)

	if victim == 0:
		m.target_id = 0
		m.wander(delta)
		return

	# Уперше завів ціль — гукає своїх (П-66).
	if not m._had_target:
		m._had_target = true
		call_for_help(id, victim)

	m.target_id = victim
	var target: Node3D = _creatures[victim]
	var d: float = m.global_position.distance_to(target.global_position)
	if d > m.ATTACK_RANGE:
		m.head_to(target.global_position, 1.0)
	else:
		m.wanted = Vector2.ZERO
		# Стоїть і дивиться на того, з ким б'ється, — увесь час, а не
		# тільки в мить удару (П-85). Аґрений монстр спини не показує.
		m.face_point(target.global_position)
		_combat.attack(id)


## Монстр гукає своїх — тільки того самого виду й тільки поблизу.
## Відстань міряє той, ХТО ЧУЄ (`hears` у mob.gd): саме там була вада 1.
## Повертає, скільки збіглося, — щоб пробі було що показати.
func call_for_help(id: int, victim: int) -> int:
	var m: Node = _creatures[id]
	var called := 0
	for other in _creatures:
		if other >= 0:
			continue
		var o: Node = _creatures[other]
		if o.is_alive() and o.hears(m, m.global_position):
			o.add_threat(victim, 1.0)
			called += 1
	if called > 0:
		print("[монстр] %d покликав своїх: %d" % [id, called])
	return called
