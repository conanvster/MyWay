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
