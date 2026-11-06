class_name Combat
extends RefCounted
## Бій: удар, шкода, загроза, смерть і строк трупа.
##
## Про мережу знає рівно стільки, скільки вміє гонець. Тому удар тепер
## викликається окремо — і надбавку за удар зі спини (П-40, числа П-85)
## нарешті видно пробою наскрізь, а не по частинах.

var _creatures: Dictionary
var _link: Messenger

## Висота землі в точці підйому. Світ підставляє свій `ground_at`; проба
## лишає нульову — землі там і так нема. Без цього тут стояв голий
## `Vector3(0, 1.5, 0)`, і коли сушу підняли на 5 м (П-140), оживлений
## опинявся на 3,5 м під новою землею.
var ground_height: Callable = func(_x: float, _z: float) -> float: return 0.0
## Де стоїть місто, куди вертають. Світ підставляє центр столиці з
## мапи; за замовчуванням — (0,0), як було жорстко зашито раніше.
var home_spot := Vector2.ZERO


func _init(creatures: Dictionary = {}, link: Messenger = null) -> void:
	_creatures = creatures
	_link = link if link != null else Messenger.new()


## Рядок у журнал подій — для поведінки монстрів і прикликань, що свого
## гінця не мають, а йдуть через бій.
func report(subject: int, text: String) -> void:
	_link.report(subject, text)


## Обидва тепер у бою, і той, хто сидів, підводиться (П-101).
func _mark_fight(a: Node, victim: Node) -> void:
	a.in_fight = a.FIGHT_TIME
	victim.in_fight = victim.FIGHT_TIME
	victim.sit(false)
	a.sit(false)


## Повертає true, якщо удар справді відбувся.
func attack(me: int) -> bool:
	if not _creatures.has(me):
		return false
	var a: Node = _creatures[me]
	if not a.is_alive():
		return false
	if a.attack_ready_in > 0.0:
		return false  # відкат не минув — дія викидається (П-35, П-38)
	# Себе не б'ють. Перевірка стоїть і тут, а не лише у виборі цілі:
	# сервер не вірить клієнтові двічі, а ціль може лишитись своєю з
	# минулого — наприклад, після чужої правки в переборі.
	if a.target_id == me:
		a.target_id = 0
		_link.to_one(me, &"client_target", [0])
		_link.notice(me, "себе не вдариш")
		return false
	var victim: Node = _creatures.get(a.target_id)
	if victim == null:
		_link.notice(me, "немає цілі")
		return false
	if not victim.is_alive():
		_link.notice(me, "неможливо застосувати на даному типі цілі")
		return false
	if _forbidden(me, a.target_id):
		_link.notice(me, "своїх не б'ють")
		return false
	var dist: float = a.global_position.distance_to(victim.global_position)
	if dist > a.ATTACK_RANGE:
		_out_of_reach(me, "attack")
		return false
	if not _pvp_ok(me, a.target_id):
		return false

	# Куди дивиться жертва — брати ДО того, як нападник розвернеться до
	# неї, інакше в бік себе самого (П-40).
	var behind := Stats.from_behind(
			victim.facing, victim.global_position, a.global_position)
	# Розвертається до цілі миттю (П-85): у того, хто вже б'ється, за
	# спину не зайти.
	a.face_point(victim.global_position)

	a.attack_ready_in = a.stats.attack_cooldown()
	# Замах бачать ті, хто бачить того, хто б'є. Зброя — тут же: чи
	# показати Sword_Attack, чи Punch_Jab/Punch_Cross (П-162), знає лише
	# сервер (`worn_in`) — клієнту чуже спорядження не шлють узагалі.
	# Третє — пауза між ударами: з неї клієнт рахує темп замаху.
	_link.to_watchers(me, &"client_swing", [me, a.worn_in("зброя") != null,
			a.attack_ready_in])
	var power: float = a.stats.physical_attack()
	if behind:
		# Чуття жертви зрізає надбавку: сприйняття захищає від удару в
		# спину (П-37, правка 3). Числа зрізання — пропозиція П-90.
		power *= 1.0 + Stats.back_bonus_against(victim.stats)
	var hit: int = Stats.damage_through(power, victim.stats.physical_defence())
	victim.hp = maxi(0, victim.hp - hit)
	_mark_fight(a, victim)
	_try_interrupt(victim, a.target_id, hit)
	# Зброя тупиться від кожного удару, що влучив (слово замовника
	# 21.09.2026), а на нулі ламається на матеріали (П-234). Монстрів не
	# стосується: у них речей немає.
	if me > 0 and a.wear_weapon(smith.wear_per_hit()):
		var broke: Dictionary = smith.break_weapon(a, goods)
		if not broke.is_empty():
			_link.notice(me, "‼ «%s» зламалась — у торбі: %s"
					% [broke["назва"], Smith.yield_text(broke["лишила"])])
			_link.report(me, "[бій] %d зламав зброю %s, лишилось %s"
					% [me, broke["назва"], broke["лишила"]])
			if on_bag_changed.is_valid():
				on_bag_changed.call(me)
	# Удар по монстру додає загрози: саме за нею він обирає, кого бити.
	if side(a.target_id) < 0 and side(me) > 0:
		victim.add_threat(me, hit + victim.threat_per_hit)
	# Про зміну здоров'я знають лише ті, хто бачить постраждалого.
	_link.to_watchers(a.target_id, &"client_hp", [a.target_id, victim.hp])
	# Число шкоди над головою бачать ті самі, хто бачить постраждалого.
	_link.to_watchers(a.target_id, &"client_damage",
			[a.target_id, hit, behind])
	_link.report(a.target_id, "[бій] %d вдарив %d%s, лишилось %d"
			% [me, a.target_id, " ЗІ СПИНИ" if behind else "", victim.hp])
	if victim.hp <= 0:
		_kill(me, a, victim, a.target_id)
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
		revive(id)
	return remove


## Підняти труп гравця й поставити в місто.
##
## Одне місце на два випадки: строк у двадцять хвилин і кнопка
## «Повернутися в місто» з вікна смерті. Якби вони жили окремо, числа
## розійшлися б із першою ж правкою.
##
## Живого не піднімає — інакше кнопка стала б безплатним телепортом
## додому просто посеред бою.
func revive(id: int) -> bool:
	var c: Node = _creatures.get(id)
	if c == null or id < 0 or c.is_alive():
		return false
	c.hp = maxi(1, roundi(c.stats.max_hp() * c.REVIVE_SHARE))
	c.corpse_left = 0.0
	send_home(id)
	_link.to_watchers(id, &"client_revive", [id, c.hp])
	return true


## Поставити в місто. Спільне для оживлення з вікна смерті й для скіла
## «повернутися в місто» — щоб місце посадки було одне на обидва шляхи,
## а не два числа, які розійдуться першою ж правкою.
##
## 6 м запасу над землею, як і при вході (`world.gd`) та спавні монстрів
## (`spawner.gd`): падає сам і сідає на видиму поверхню, а не в ґрунт.
func send_home(id: int) -> void:
	send_to(id, home_spot, "дім")


## Поставити в будь-яке місце на землі: те саме, що `send_home`, тільки
## точку дає той, хто кличе (майстер магії, 20.09.2026). Одна дорога на
## обидва випадки — інакше запас над землею розійшовся б першою правкою.
func send_to(id: int, spot: Vector2, why: String = "перенос") -> void:
	var c: Node = _creatures.get(id)
	if c == null:
		return
	var high: float = ground_height.call(spot.x, spot.y)
	c.teleport_to(Vector3(spot.x, high + 6.0, spot.y), 0.0)
	print("[%s] %d поставлено в (%.0f, %.0f) на висоті %.2f"
			% [why, id, spot.x, spot.y, c.global_position.y])
	# Окремим повідомленням, бо переставляння має бути стрибком:
	# інакше труп проїде через усю мапу (вада 3 з PLAN.md).
	_link.to_watchers(id, &"client_place", [id, c.global_position, c.facing])


# ── скіли (крок 2.2) ──────────────────────────────────────────────────

## Книга скілів. Ставить світ при створенні; проба підставляє свою.
var skills := SkillBook.new()
## Повага, рівні й винагорода за різницю рівнів (крок 3).
var progress := Progress.new()
## Речі: бази й афікси (крок 4).
var goods := ItemBook.new()
## Коваль: скільки тупиться зброя за удар, що лишає зламана (П-234) і що
## дає бос (21.09.2026).
var smith := Smith.new()
## Речі на землі (П-160): туди лягає загублене при смерті. Ставить світ;
## без нього (проби) — зникає.
var ground: Ground = null


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

	var level: int = a.skill_level(key)
	var cost: int = skill.mana(level)
	# «Не вистачає мани — скіл неактивний» (П-93).
	if a.mp < cost:
		_link.notice(me, "не вистачає мани")
		return false

	var victims: Array = _victims_for(a, me, skill, level,
			Actions.SKILL_PREFIX + key)
	# Скіл, що ще й прикликає (П-41), читається й без ворогів поруч: «море
	# праху» в порожньому полі не б'є нікого, але мертві однаково встають.
	if victims.is_empty() and not _summons_anyway(skill):
		return false

	# Мана списується НА ПОЧАТКУ читання. Якщо каст переб'ють, вона не
	# вертається — це і є ціна того, що тебе дістали (пропозиція П-111).
	a.mp -= cost

	var seconds: float = a.stats.skill_cast(skill.cast_points)
	if seconds > 0.0:
		# Довгий скіл читається, а не спрацьовує миттю (крок 2.3). Відкат
		# піде тільки після того, як дочитає: збитий каст не садить скіл
		# на відкат, інакше перервання карало б двічі.
		a.start_cast(key, seconds, a.target_id, skill.move_while_casting)
		a.busy_in = seconds
		_link.to_watchers(me, &"client_cast", [me, skill.name, seconds])
		return true

	_apply(me, a, skill, level, victims)
	return true


## Дочитав — б'є. Спільне для миттєвих скілів і для тих, що читалися.
func _apply(me: int, a: Node, skill: Skill, level: int, victims: Array) -> void:
	a.skill_ready_in[skill.key] = a.stats.skill_cooldown(skill.cooldown_points)
	var power: float = a.stats.magical_attack() * skill.power_share(level)
	var mend: float = a.stats.magical_attack() * skill.heal_share(level)
	var state: Dictionary = skill.state_at(level)
	# Ефект на клієнтах (П-272) — ДО чисел шкоди, щоб клієнт знав, що
	# число прийшло від скіла, і не малював ще й іскри звичайного удару.
	var hit_ids: Array = []
	for victim: Node in victims:
		hit_ids.append(_id_of(victim))
	_link.to_watchers(me, &"client_skill", [me, skill.key, hit_ids])
	for victim: Node in victims:
		if power > 0.0:
			_land(me, a, victim, power)
		if mend > 0.0:
			_mend(victim, mend)
		# Баф або дебаф зі скіла — тим самим механізмом станів, що й усе
		# інше (крок 2.1). Окремого коду для монстрів немає.
		if not state.is_empty() and victim.is_alive():
			victim.add_state(State.from_data(state))
	# Переніс у місто — не шкода й не стан, тож окремо. Діє на того,
	# хто читав: ціль скіла — «себе».
	if skill.sends_home(level):
		send_home(me)
		_link.notice(me, "ти в місті")
	if not skill.summon.is_empty() and on_summon.is_valid():
		on_summon.call(me, skill.summon)
	_link.report(me, "[скіл] %d застосував %s рівня %d, цілей %d, мани лишилось %d"
			% [me, skill.name, level, victims.size(), a.mp])


## Час іде: хто дочитав — б'є, і про це дізнаються ті, хто його бачить.
func tick_casts(delta: float) -> void:
	for id in _creatures:
		var a: Node = _creatures[id]
		if not a.is_casting():
			continue
		a.casting_left -= delta
		if a.casting_left > 0.0:
			continue
		var skill: Skill = skills.get_skill(a.casting_key)
		var level: int = maxi(1, a.skill_level(a.casting_key))
		# Ціль беремо ту, на кого починали (П-42).
		a.target_id = a.casting_target if a.casting_target != 0 else a.target_id
		a.stop_cast()
		if skill == null:
			continue
		var victims: Array = _victims_for(a, id, skill, level)
		var lands := not victims.is_empty() or _summons_anyway(skill)
		_link.to_watchers(id, &"client_cast_end", [id, lands])
		if not lands:
			continue
		_apply(id, a, skill, level, victims)


## Спроба збити каст ударом (П-111).
##
## Опір — концентрація плюс магічний захист. Концентрацію дає Чуття й баф
## «концентрація уваги»; магічний захист — Витривалість, спорядження й
## свої бафи. Тобто збити мага тим важче, що більше він у це вклав.
func _try_interrupt(victim: Node, id: int, hit: int) -> void:
	if not victim.is_casting():
		return
	var guard: float = victim.stats.concentration() \
			+ victim.stats.magical_defence()
	var chance: float = Stats.interrupt_chance(hit, guard)
	if randf() >= chance:
		return
	_link.report(id, "[каст] %d збито ударом на %d (опір %.0f, шанс %.0f%%)"
			% [id, hit, guard, chance * 100.0])
	victim.stop_cast()
	victim.busy_in = 0.0
	_link.notice(id, "читання перервано")
	_link.to_watchers(id, &"client_cast_end", [id, false])


## Кого зачепить скіл. Тут-таки й повідомлення про невдачу, бо причина
## залежить від типу цілі (П-42).
##
## `chase` — дія, яку треба догнати, якщо ціль вийшла з-під руки (В-2).
## Порожня — наприкінці читання: мана вже списана, доганяти пізно.
func _victims_for(a: Node, me: int, skill: Skill, level: int,
		chase: String = "") -> Array:
	# Клич чи стійка (П-150): б'є самого себе, дальність тут ні до чого.
	if skill.target == "себе":
		return [a]
	var reach: float = skill.range_at(level)
	if skill.hits_many():
		# Вибух б'є все вороже навколо. Гравець зачіпає монстрів, монстр —
		# гравців: PvP по площі це окреме питання (П-110), і мовчки
		# вирішувати його за замовника не можна.
		#
		# «Свої-поруч» — навпаки: монстр бафить сусідів свого боку.
		var friends: bool = skill.hits_friends()
		var found: Array = []
		for id in _creatures:
			if id == me or (side(id) == side(me)) != friends:
				continue
			var other: Node = _creatures[id]
			if not other.is_alive():
				continue
			if a.global_position.distance_to(other.global_position) <= reach:
				found.append(other)
		if found.is_empty() and not friends:
			_link.notice(me, "поруч нікого немає")
		return found

	var victim: Node = _creatures.get(a.target_id)
	if victim == null:
		_link.notice(me, "немає цілі")
		return []
	if not victim.is_alive():
		_link.notice(me, "неможливо застосувати на даному типі цілі")
		return []
	if skill.power_share(level) > 0.0 and _forbidden(me, a.target_id):
		_link.notice(me, "своїх не б'ють")
		return []
	var near: bool = a.global_position.distance_to(
			victim.global_position) <= reach
	if skill.power_share(level) > 0.0 and near \
			and not _pvp_ok(me, a.target_id):
		return []
	if a.global_position.distance_to(victim.global_position) > reach:
		if chase != "":
			_out_of_reach(me, chase)
		else:
			_link.notice(me, "задалеко")
		return []
	a.face_point(victim.global_position)
	return [victim]


## Шкода одній цілі: те саме, що й в ударі, тільки крізь МАГІЧНИЙ захист.
func _land(me: int, a: Node, victim: Node, power: float) -> void:
	var id: int = _id_of(victim)
	var hit: int = Stats.damage_through(power, victim.stats.magical_defence())
	victim.hp = maxi(0, victim.hp - hit)
	_mark_fight(a, victim)
	_try_interrupt(victim, id, hit)
	if side(id) < 0 and side(me) > 0:
		victim.add_threat(me, hit + victim.threat_per_hit)
	_link.to_watchers(id, &"client_hp", [id, victim.hp])
	_link.to_watchers(id, &"client_damage", [id, hit, false])
	if victim.hp <= 0:
		_kill(me, a, victim, id)


## Лікування (П-224). Окремо від шкоди: крізь магічний захист воно не
## йде — захищатися від власного цілителя нема сенсу, — і мертвого не
## піднімає: оживлення це інше питання (П-68).
func _mend(victim: Node, power: float) -> void:
	if not victim.is_alive():
		return
	var id: int = _id_of(victim)
	var was: int = victim.hp
	victim.hp = mini(victim.stats.max_hp(), victim.hp + int(power))
	if victim.hp == was:
		return
	_link.to_watchers(id, &"client_hp", [id, victim.hp])
	_link.to_watchers(id, &"client_damage", [id, victim.hp - was, false])


## Хтось загинув. Тут-таки й винагорода вбивці: повага, досвід і дроп
## (крок 3). Гравець за гравця поки не отримує нічого — це PvP, і воно
## має свої правила (П-88).
## Кому сказати про смерть, крім клієнтів: світ ловить так боса
## підземелля (Ф6). (victim_id, victim) -> void.
var on_kill: Callable
## Кличеться після того, як убивця отримав своє (досвід, повага, дроп).
## Бій не знає ні про професії, ні про квести — рахунок убитих веде світ.
var on_reward: Callable
## Ціль вийшла з-під руки, поки летіла команда (В-2): (me, дія) -> void.
## Світ каже клієнтові «доганяй» — рухом гравця керує клієнт, і саме він
## доводить до цілі й тисне ту саму дію вдруге. Без цього дія тихо
## викидалась із «задалеко», а гравець стояв, хоч ціль ступила лише крок.
var on_out_of_reach: Callable


## Скіл когось прикликав (П-41): (хто читав, {"вид","скільки","строк"}).
## Ставить істот світ — бій вузлів не створює.
var on_summon: Callable
## Торба гравця змінилась посеред бою (зброя зламалась, П-234): світ
## шле клієнтові торбу й стати.
var on_bag_changed: Callable


## Бік істоти: +1 — гравці й їхні прикликані, −1 — монстри. Раніше бік
## був просто знаком номера; прикликаний — від'ємний номер, але свій.
func side(id: int) -> int:
	if id > 0:
		return 1
	var c: Node = _creatures.get(id)
	if c != null and "owner_id" in c and int(c.owner_id) > 0:
		return 1
	return -1


## Прикликання по площі не потребує ворогів. По одній цілі — потребує:
## такий скіл спершу б'є ціль, і без неї читати нема що.
func _summons_anyway(skill: Skill) -> bool:
	return not skill.summon.is_empty() and skill.target != "жива"


## Хто отримує винагороду за вбивство: гравець — сам, прикликаний — його
## господар. 0 — ніхто (монстр).
func payee(id: int) -> int:
	if id > 0:
		return id
	var c: Node = _creatures.get(id)
	if c != null and "owner_id" in c:
		return int(c.owner_id)
	return 0


## Прикликаного не б'ють свої, і він не б'є своїх. Гравець гравця —
## можна: це PvP зі своїми правилами (П-26).
func _forbidden(me: int, victim_id: int) -> bool:
	if me > 0 and victim_id > 0:
		return false
	return side(me) == side(victim_id)


func _out_of_reach(me: int, action: String) -> void:
	if me > 0 and on_out_of_reach.is_valid():
		on_out_of_reach.call(me, action)
	else:
		_link.notice(me, "задалеко")


## Погоджений PvP (П-259): обидва погодились на бій чи це івент, і бій
## іде в спеціальній зоні — там речі не губляться. Самої зони в грі ще
## немає (форк П-260), тож світ поставить сюди перевірку, коли вона
## з'явиться: (вбивця, убитий) -> bool. Порожній — погодженого PvP нема.
var agreed_pvp: Callable


## Флаг і позначка вбивця (П-26/П-87). Ставить світ; без нього (проби
## бою) PvP іде, як ішов.
var outlaws: Outlaws = null


## Удар гравця (чи його прикликаного) по гравцю: у місті не діє (П-88),
## інакше — флаг. Погоджений бій (арена, П-259) — поза флагом.
func _pvp_ok(me: int, victim_id: int) -> bool:
	var attacker := payee(me)
	if outlaws == null or attacker <= 0 or victim_id <= 0 \
			or _agreed(me, victim_id):
		return true
	if outlaws.allow_hit(attacker, victim_id):
		return true
	_link.notice(me, "у місті удар по гравцю не діє")
	return false


func _agreed(me: int, victim_id: int) -> bool:
	var killer := payee(me)
	if killer <= 0 or victim_id <= 0 or not agreed_pvp.is_valid():
		return false
	return bool(agreed_pvp.call(killer, victim_id))


func _kill(me: int, killer: Node, victim: Node, victim_id: int) -> void:
	victim.die()
	# Гравець за смерть втрачає повагу: рівно 10% обсягу поточного рівня
	# (П-27, числа замовника). Досвід не втрачається. На арені (погоджений
	# бій) — ні: бій за домовленістю без кари (П-260, слово замовника
	# 17.10.2026 — рекомендацію прийнято).
	if victim_id > 0 and _agreed(me, victim_id):
		_link.report(victim_id, "[смерть] %d на арені — повага не знімається"
				% victim_id)
	elif victim_id > 0:
		var was_level: int = victim.level
		var lost: int = progress.death_loss(victim)
		if victim.level < was_level:
			_link.notice(victim_id, "втрачено рівень: тепер %d" % victim.level)
			_link.report(victim_id, "[смерть] %d втратив рівень %d -> %d"
					% [victim_id, was_level, victim.level])
		else:
			_link.notice(victim_id, "втрачено %d поваги" % lost)
		_link.report(victim_id, "[смерть] %d втратив %d поваги, лишилось %d"
				% [victim_id, lost, victim.respect])
	if victim_id > 0:
		# І частина речей (друга половина П-27). Лягають на землю біля
		# трупа (П-160) — підняти може будь-хто. PvP двох видів (П-259,
		# слово замовника 10.10.2026): у ПОГОДЖЕНОМУ — у спеціальній зоні —
		# речі не падають; у непогодженому (флаг, П-26/П-64) — падають, як
		# від монстра.
		var gone_all: Array = []
		var agreed := _agreed(me, victim_id)
		if not agreed:
			# Позначений вбивця губить більше: ×1,1 за кожне своє вбивство
			# (П-261) — рахунок ДО цієї смерті.
			var more: float = outlaws.loss_multiplier(victim) \
					if outlaws != null else 1.0
			gone_all = progress.lose_items(victim, goods, ground, more)
			if more > 1.0:
				_link.report(victim_id, "[pvp] %d позначений — речей падає ×%.2f"
						% [victim_id, more])
		# Убитий бачить факт, а не ім'я вбивці (П-88).
		if not agreed and outlaws != null \
				and outlaws.on_kill(payee(me), victim_id):
			_link.notice(victim_id, "тебе вбито; вбивця позначений")
		for gone: String in gone_all:
			_link.notice(victim_id, "загублено, лежить на землі: %s" % gone)
			_link.report(victim_id, "[смерть] %d загубив %s" % [victim_id, gone])
	_link.report(victim_id, "[бій] %d загинув, труп лежатиме %.0f с"
			% [victim_id, victim.corpse_left])
	_link.to_watchers(victim_id, &"client_died", [victim_id])
	# Гравець або його прикликаний убив монстра — винагорода гравцеві.
	var paid := payee(me)
	# Вартовий поселення (П-262) — не здобич: убивця дістає не повагу, а
	# «чорний список» поселення (`Wardens.on_kill`).
	var guard: bool = victim.get("settlement") != null \
			and int(victim.get("settlement")) >= 0
	if paid > 0 and side(victim_id) < 0 and not guard \
			and _creatures.has(paid):
		_reward(paid, _creatures[paid], victim)
	if on_kill.is_valid():
		on_kill.call(victim_id, victim, paid)


## Скільки дісталось убивці. Множник за різницю рівнів (П-104) б'є по
## всьому одразу — і по повазі, і по досвіду, і по дропу: інакше вбивати
## дрібних монстрів заради речей лишалось би вигідним.
func _reward(me: int, killer: Node, victim: Node) -> void:
	var mult: float = progress.reward_multiplier(victim.level, killer.level)
	if mult <= 0.0:
		_link.notice(me, "монстр надто слабкий — нічого не дав")
		return

	var respect: int = roundi(_roll(victim.respect_range) * mult)
	var experience: int = roundi(_roll(victim.experience_range) * mult)
	killer.experience += experience
	var levels: int = progress.add_respect(killer, respect)
	var tail := "" if is_equal_approx(mult, 1.0) 			else "  (×%.2f за різницю рівнів)" % mult
	_link.notice(me, "повага +%d, досвід +%d%s" % [respect, experience, tail])
	if levels > 0:
		_link.notice(me, ("рівень %d! здоров'я й мана відновлені, "
				+ "очок статів: %d") % [killer.level, killer.stat_points])
		_link.report(me, "[рівень] %d узяв %d рівень" % [me, killer.level])

	for row: Dictionary in victim.drop_table:
		if randf() > float(row.get("шанс", 0.0)) * mult:
			continue
		var count: int = randi_range(int(row.get("від", 1)),
				int(row.get("до", 1)))
		if count <= 0:
			continue
		_give(me, killer, str(row["що"]), count)
	# Бос понад свою таблицю дає рунну есенцію свого грейду — інгредієнт
	# для зачарування в коваля («дропаються з босів», 21.09.2026). Не
	# рядком у `mobs.json`: бос — це роль у підземеллі, а не вид.
	if victim.get("is_boss"):
		var rule: Dictionary = smith.rules.get("есенція з боса", {})
		if randf() <= float(rule.get("шанс", 0.0)) * mult:
			var essence := "рунна есенція %s" \
					% goods.grade_for_level(victim.level)
			if goods.has(essence):
				_give(me, killer, essence, randi_range(int(rule.get("від", 1)),
						int(rule.get("до", 1))))
	if outlaws != null:
		outlaws.monster_killed(killer, victim.level)
	if on_reward.is_valid():
		on_reward.call(me, killer, victim)


## Покласти здобуте. Складані речі йдуть кількістю, поодинокі — кожна
## окремо, і на кожну кидаються свої афікси (П-83).
func _give(me: int, who: Node, name: String, count: int) -> void:
	if not goods.has(name) or goods.is_stackable(name):
		who.give_item(name, count)
		_link.notice(me, "здобуто: %s ×%d" % [name, count])
		return
	for i in count:
		var item: Item = goods.make(name)
		if item == null:
			continue
		var at: int = who.add_thing(item)
		_link.notice(me, "здобуто: %s" % item.title())
		# Порожній слот заповнюється сам: новачкові не треба шукати, де
		# вдягається перша в житті куртка. Зайняте не чіпаємо — вибір
		# лишається за гравцем.
		if item.slot != "" and not who.gear.has(item.slot):
			who.equip(at)
			_link.notice(me, "вдягнено: %s" % item.title())


func _roll(pair: Array) -> int:
	if pair.size() < 2:
		return 0
	return randi_range(int(pair[0]), int(pair[1]))


func _id_of(node: Node) -> int:
	for id in _creatures:
		if _creatures[id] == node:
			return id
	return 0
