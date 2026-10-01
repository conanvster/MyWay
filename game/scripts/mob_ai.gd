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


## Сон далеких монстрів (12.09.2026). Світ версії 2 заселено по всій
## суші — сотні монстрів, і думати щокадру за кожного, кого ніхто не
## бачить, серверові ні до чого: монстр без цілі, удома й далі
## `SLEEP_RANGE` від усіх гравців стоїть і не рахується зовсім. Вмикає
## це світ (`world.gd`); проби, що кличуть `think` напряму, — ні.
var sleep_far := false
## Далі за це від кожного гравця монстр спить. З запасом за туман і за
## те, звідки агресивний помічає, — прокидається раніше, ніж його видно.
const SLEEP_RANGE := 90.0
## Живі гравці — раз на кадр фізики, а не для кожного монстра окремо:
## інакше це монстри × істоти обходів щокадру.
var _players := {}
var _players_frame := -1


func _refresh_players() -> void:
	var frame := Engine.get_physics_frames()
	if frame == _players_frame:
		return
	_players_frame = frame
	_players.clear()
	for other in _creatures:
		if _is_player_side(other) and _creatures[other].is_alive():
			_players[other] = _creatures[other]


## Гравець або чийсь прикликаний (П-41): монстр мітить і тих, і тих —
## інакше прикликаний бив би його безкарно.
func _is_player_side(id: int) -> bool:
	if id > 0:
		return true
	var c: Node = _creatures.get(id)
	return c != null and "owner_id" in c and int(c.owner_id) > 0


func _far_from_all(m: Node3D, players: Dictionary) -> bool:
	for p: Node3D in players.values():
		if p.global_position.distance_to(m.global_position) < SLEEP_RANGE:
			return false
	return true


func think(id: int, delta: float) -> void:
	var m: Node = _creatures[id]
	if not m.is_alive():
		return

	var players := {}
	if sleep_far:
		_refresh_players()
		players = _players
		if m.target_id == 0 and not m.too_far_from_home() \
				and _far_from_all(m, players):
			m.wanted = Vector2.ZERO
			m.asleep = true
			return
		m.asleep = false
	else:
		for other in _creatures:
			if _is_player_side(other) and _creatures[other].is_alive():
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

	# Уперше завів ціль — гукає своїх (П-66) і, якщо вміє, підбадьорює
	# їх скілом: «якщо його атакували, він за власну ману бафить сусідів»
	# (погоджено 02.09.2026).
	if not m._had_target:
		m._had_target = true
		call_for_help(id, victim)
		_use(m, id, "у відповідь")

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
		# Спершу пробує кинути дебаф на кривдника; не вийшло (відкат,
		# мана, задалеко) — б'є як завжди.
		if not _use(m, id, "по кривднику"):
			_combat.attack(id)


## Застосувати скіл із того випадку, якщо він у монстра прописаний.
func _use(m: Node, id: int, case: String) -> bool:
	var key: String = m.skills_by_case.get(case, "")
	if key == "" or m.is_casting():
		return false
	return _combat.cast(id, key)


## Монстр гукає своїх — тільки того самого виду й тільки поблизу.
## Відстань міряє той, ХТО ЧУЄ (`hears` у mob.gd): саме там була вада 1.
## Повертає, скільки збіглося, — щоб пробі було що показати.
func call_for_help(id: int, victim: int) -> int:
	var m: Node = _creatures[id]
	var called := 0
	for other in _creatures:
		if _is_player_side(other):
			continue
		var o: Node = _creatures[other]
		if o.is_alive() and o.hears(m, m.global_position):
			o.add_threat(victim, 1.0)
			called += 1
	if called > 0:
		print("[монстр] %d покликав своїх: %d" % [id, called])
	return called
