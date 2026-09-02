class_name Combat
extends RefCounted
## Бій: удар, шкода, загроза, смерть і строк трупа.
##
## Про мережу знає рівно стільки, скільки вміє гонець. Тому удар тепер
## викликається окремо — і надбавку за удар зі спини (П-40, числа П-85)
## нарешті видно пробою наскрізь, а не по частинах.

var _creatures: Dictionary
var _link: Messenger


func _init(creatures: Dictionary = {}, link: Messenger = null) -> void:
	_creatures = creatures
	_link = link if link != null else Messenger.new()


## Повертає true, якщо удар справді відбувся.
func attack(me: int) -> bool:
	if not _creatures.has(me):
		return false
	var a: Node = _creatures[me]
	if not a.is_alive():
		return false
	if a.attack_ready_in > 0.0:
		return false  # відкат не минув — дія викидається (П-35, П-38)
	var victim: Node = _creatures.get(a.target_id)
	if victim == null:
		_link.notice(me, "немає цілі")
		return false
	if not victim.is_alive():
		_link.notice(me, "неможливо застосувати на даному типі цілі")
		return false
	var dist: float = a.global_position.distance_to(victim.global_position)
	if dist > a.ATTACK_RANGE:
		_link.notice(me, "задалеко")
		return false

	# Куди дивиться жертва — брати ДО того, як нападник розвернеться до
	# неї, інакше в бік себе самого (П-40).
	var behind := Stats.from_behind(
			victim.facing, victim.global_position, a.global_position)
	# Розвертається до цілі миттю (П-85): у того, хто вже б'ється, за
	# спину не зайти.
	a.face_point(victim.global_position)

	a.attack_ready_in = a.stats.attack_cooldown()
	var power: float = a.stats.physical_attack()
	if behind:
		# Чуття жертви зрізає надбавку: сприйняття захищає від удару в
		# спину (П-37, правка 3). Числа зрізання — пропозиція П-90.
		power *= 1.0 + Stats.back_bonus_against(victim.stats)
	var hit: int = Stats.damage_through(power, victim.stats.physical_defence())
	victim.hp = maxi(0, victim.hp - hit)
	# Удар по монстру додає загрози: саме за нею він обирає, кого бити.
	if a.target_id < 0 and me > 0:
		victim.add_threat(me, hit + victim.threat_per_hit)
	# Про зміну здоров'я знають лише ті, хто бачить постраждалого.
	_link.to_watchers(a.target_id, &"client_hp", [a.target_id, victim.hp])
	# Число шкоди над головою бачать ті самі, хто бачить постраждалого.
	_link.to_watchers(a.target_id, &"client_damage",
			[a.target_id, hit, behind])
	print("[бій] %d вдарив %d%s, лишилось %d"
			% [me, a.target_id, " ЗІ СПИНИ" if behind else "", victim.hp])
	if victim.hp <= 0:
		victim.die()
		print("[бій] %d загинув, труп лежатиме %.0f с"
				% [a.target_id, victim.corpse_left])
		_link.to_watchers(a.target_id, &"client_died", [a.target_id])
	return true


## Трупи, яким вийшов строк. Монстра треба прибрати зі світу — його номер
## і повертається; гравець підводиться сам, із 30% (П-69, П-70).
##
## Прибирає не цей клас: створення й знищення вузлів — робота світу, а
## бій має лишатися перевірним без сцени.
func clear_corpses() -> Array:
	var remove: Array = []
	for id in _creatures.keys():
		var c: Node = _creatures[id]
		if c.is_alive() or c.corpse_left > 0.0:
			continue
		if id < 0:
			remove.append(id)
			continue
		# Не оживили за 20 хвилин — підводиться сам (П-69, П-70).
		# Втрат за смерть (П-27) поки немає: немає ні досвіду, ні речей.
		c.hp = maxi(1, roundi(c.stats.max_hp() * c.REVIVE_SHARE))
		c.place_at(Vector3(0, 1.5, 0), 0.0)
		_link.to_watchers(id, &"client_revive", [id, c.hp])
		# Окремим повідомленням, бо переставляння має бути стрибком:
		# інакше труп проїде через усю мапу (вада 3 з ПЛАН.md).
		_link.to_watchers(id, &"client_place", [id, c.global_position, c.facing])
	return remove


# ── скіли (крок 2.2) ──────────────────────────────────────────────────

## Книга скілів. Ставить світ при створенні; проба підставляє свою.
var skills := SkillBook.new()


## Застосувати скіл. Повертає true, якщо він справді спрацював.
##
## Порядок перевірок навмисне такий: спершу те, що взагалі неможливе
## (не вивчений, мертвий), далі відкат, далі мана, і аж потім ціль —
## щоб повідомлення казало найточнішу причину, а не першу-ліпшу.
func cast(me: int, key: String) -> bool:
	var a: Node = _creatures.get(me)
	if a == null or not a.is_alive():
		return false
	var skill: Skill = skills.get_skill(key)
	if skill == null:
		_link.notice(me, "такого вміння немає")
		return false
	if not a.knows(key):
		_link.notice(me, "%s не вивчено" % skill.name)
		return false
	if not a.skill_ready(key):
		return false  # відкат — дія просто викидається (П-38)

	var level: int = a.learned[key]
	var cost: int = skill.mana(level)
	# «Не вистачає мани — скіл неактивний» (П-93).
	if a.mp < cost:
		_link.notice(me, "не вистачає мани")
		return false

	var victims: Array = _victims_for(a, me, skill, level)
	if victims.is_empty():
		return false

	a.mp -= cost
	a.skill_ready_in[key] = a.stats.skill_cooldown(skill.cooldown_points)
	a.busy_in = a.stats.skill_cast(skill.cast_points)

	var power: float = a.stats.magical_attack() * skill.power_share(level)
	for victim: Node in victims:
		_land(me, a, victim, power)
	print("[скіл] %d застосував %s рівня %d, цілей %d, мани лишилось %d"
			% [me, skill.name, level, victims.size(), a.mp])
	return true


## Кого зачепить скіл. Тут-таки й повідомлення про невдачу, бо причина
## залежить від типу цілі (П-42).
func _victims_for(a: Node, me: int, skill: Skill, level: int) -> Array:
	var reach: float = skill.range_at(level)
	if skill.hits_many():
		# Вибух б'є все вороже навколо. Гравець зачіпає монстрів, монстр —
		# гравців: PvP по площі це окреме питання (П-110), і мовчки
		# вирішувати його за замовника не можна.
		var found: Array = []
		for id in _creatures:
			if id == me or (id < 0) == (me < 0):
				continue
			var other: Node = _creatures[id]
			if not other.is_alive():
				continue
			if a.global_position.distance_to(other.global_position) <= reach:
				found.append(other)
		if found.is_empty():
			_link.notice(me, "поруч нікого немає")
		return found

	var victim: Node = _creatures.get(a.target_id)
	if victim == null:
		_link.notice(me, "немає цілі")
		return []
	if not victim.is_alive():
		_link.notice(me, "неможливо застосувати на даному типі цілі")
		return []
	if a.global_position.distance_to(victim.global_position) > reach:
		_link.notice(me, "задалеко")
		return []
	a.face_point(victim.global_position)
	return [victim]


## Шкода одній цілі: те саме, що й в ударі, тільки крізь МАГІЧНИЙ захист.
func _land(me: int, a: Node, victim: Node, power: float) -> void:
	var id: int = _id_of(victim)
	var hit: int = Stats.damage_through(power, victim.stats.magical_defence())
	victim.hp = maxi(0, victim.hp - hit)
	if id < 0 and me > 0:
		victim.add_threat(me, hit + victim.threat_per_hit)
	_link.to_watchers(id, &"client_hp", [id, victim.hp])
	_link.to_watchers(id, &"client_damage", [id, hit, false])
	if victim.hp <= 0:
		victim.die()
		_link.to_watchers(id, &"client_died", [id])
		print("[бій] %d загинув від уміння" % id)


func _id_of(node: Node) -> int:
	for id in _creatures:
		if _creatures[id] == node:
			return id
	return 0
