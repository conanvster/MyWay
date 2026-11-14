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

	# Кинув погоню, бо не міг обійти стіну, — іде додому й поки нікого
	# не бачить: інакше за кадр знову помітив би того самого гравця.
	if m.calm_left > 0.0:
		m.calm_left -= delta
		m.target_id = 0
		m.head_to(m.home, 1.0)
		return

	# Відбіг задалеко від дому — розвертається й геть забуває кривдника.
	if m.too_far_from_home():
		m.forget()
		m.target_id = 0
		m.best_reach = INF
		m.blocked_for = 0.0
		m.detour_side = 0
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
		_chase(m, target, delta)
	else:
		m.blocked_for = 0.0
		m.best_reach = INF
		m.detour_side = 0
		m.wanted = Vector2.ZERO
		# Стоїть і дивиться на того, з ким б'ється, — увесь час, а не
		# тільки в мить удару (П-85). Аґрений монстр спини не показує.
		m.face_point(target.global_position)
		# Спершу пробує кинути дебаф на кривдника; не вийшло (відкат,
		# мана, задалеко) — б'є як завжди.
		if not _use(m, id, "по кривднику"):
			_combat.attack(id)


## Погоня з обходом стін (14.11.2026). Монстр біжить прямою на ціль; на
## перегородках дерев-велетів (до 35 м) він упирався в стіну впритул і
## стояв так хвилинами — рефлекс «крок назад, тоді вбік» у creature.gd
## виводить лише з-за кута, не з-за довгої стіни. Тепер: пряму перекрито
## нерухомим тілом зблизька — іде вздовж стіни в той бік, звідки пряма
## на ціль вільна (уперся й там — у другий), доки пряма не звільниться.
## GIVE_UP секунд не ближчає до цілі — кидає погоню й іде додому (а за
## 22 м від дому й так спрацьовує повідок, `leash`): від монстра можна
## сховатися (слово замовника 13.11.2026: «сховатися або втекти»).
const DETOUR_LOOK := 4.0
const DETOUR_STEP := 1.2
const GIVE_UP := 12.0
const CALM := 6.0
const CLEAR_KEEP := 1.5
const PROBE_SIDE := 8.0


func _chase(m: Node3D, target: Node3D, delta: float) -> void:
	var goal := target.global_position
	# Кидає погоню, коли GIVE_UP секунд не ближчає до цілі ні на пів метра.
	# Не «скільки стіна на шляху»: між шматками перегородки пряма на мить
	# звільнялась, і такий лічильник обнулявся без кінця (проба tree_fight:
	# монстр 25 с ходив туди-сюди за стіною, 14.11.2026).
	var reach := m.global_position.distance_to(goal)
	if reach < m.best_reach - 0.5:
		m.best_reach = reach
		m.blocked_for = 0.0
	else:
		m.blocked_for += delta
	if m.blocked_for >= GIVE_UP:
		m.blocked_for = 0.0
		m.best_reach = INF
		m.detour_side = 0
		m.forget()
		m.target_id = 0
		m.calm_left = CALM
		m.head_to(m.home, 1.0)
		return
	var wall := _wall_between(m, target, m.global_position, goal)
	if wall.is_empty():
		# Бік обходу пам'ятаємо, доки пряма не вільна CLEAR_KEEP секунд:
		# між шматками перегородки вона звільнялась на мить, монстр звертав
		# на стіну, знову обирав бік — і ходив туди-сюди.
		m.clear_for += delta
		if m.clear_for >= CLEAR_KEEP:
			m.detour_side = 0
		m.head_to(goal, 1.0)
		return
	m.clear_for = 0.0
	# Обхід — поперек прямої на ціль, а не вздовж нормалі стіни: стіна
	# складена з брусів, і на стику куля била в торець, нормаль якого
	# дивиться вздовж стіни — «вздовж стіни» ставало «геть від цілі».
	var to_goal := goal - m.global_position
	to_goal.y = 0.0
	to_goal = to_goal.normalized()
	var along := to_goal.cross(Vector3.UP).normalized()
	var normal := -to_goal
	if m.detour_side == 0:
		m.detour_side = _open_side(m, target, along, goal)
		m.detour_dir = m.global_position
		m.detour_left = DETOUR_STEP
	else:
		m.detour_left -= delta
		if m.detour_left <= 0.0:
			# Не зрушив за крок уздовж стіни — там кут чи інша стіна: в інший бік.
			if m.global_position.distance_to(m.detour_dir) < 0.6:
				m.detour_side = -m.detour_side
			m.detour_left = DETOUR_STEP
			m.detour_dir = m.global_position
	# Убік і трохи назад від стіни, щоб не тертися об неї.
	var go := along * float(m.detour_side) + normal * 0.2
	m.head_to(m.global_position + go * 4.0, 1.0)


## У який бік уздовж стіни обходити: звідки пряма на ціль вільна (чи
## перекрита далі). Дві проби з точок за PROBE_SIDE м ліворуч і праворуч.
func _open_side(m: Node3D, target: Node3D, along: Vector3, goal: Vector3) -> int:
	var best := 0
	var far := -1.0
	for side: int in [1, -1]:
		var from := m.global_position + along * float(side) * PROBE_SIDE
		var hit := _wall_between(m, target, from, goal, 40.0)
		var reach := 1e6 if hit.is_empty() else (hit["point"] as Vector3) \
				.distance_to(from)
		if reach > far + 0.5:
			far = reach
			best = side
	if best == 0:
		return 1 if randf() < 0.5 else -1
	return best


## Нерухома перешкода на шляху до цілі ближче за `look`: {"normal", "point"}
## або порожньо. Пробує не промінь, а кулю завтовшки з капсулу: промінь на
## висоті грудей не бачив низького, у що монстр упирався ногами, і
## «пряма вільна» тримала його на місці (14.11.2026). Похила земля — не
## стіна.
func _wall_between(m: Node3D, target: Node3D, start: Vector3, goal: Vector3,
		look := DETOUR_LOOK) -> Dictionary:
	if not m.is_inside_tree():
		return {}
	var from := start + Vector3.UP * 0.1
	var flat := goal - start
	flat.y = 0.0
	if flat.length() < 0.5:
		return {}
	var move := flat.normalized() * minf(look, flat.length())
	var ball := SphereShape3D.new()
	ball.radius = 0.5
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = ball
	q.transform = Transform3D(Basis(), from)
	q.motion = move
	q.collide_with_areas = false
	q.exclude = [m.get_rid(), target.get_rid()]
	var space := m.get_world_3d().direct_space_state
	var part := space.cast_motion(q)
	if part.is_empty() or part[1] >= 1.0:
		return {}
	q.transform = Transform3D(Basis(), from + move * part[1])
	q.motion = Vector3.ZERO
	var info := space.get_rest_info(q)
	if info.is_empty():
		return {}
	var normal: Vector3 = info["normal"]
	if absf(normal.y) > 0.6:
		return {}
	if instance_from_id(int(info["collider_id"])) is CharacterBody3D:
		return {}
	return {"normal": normal, "point": info["point"]}


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
		_combat.report(id, "[монстр] %d покликав своїх: %d" % [id, called])
	return called
