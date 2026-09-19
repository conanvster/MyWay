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
	# Замах бачать ті, хто бачить того, хто б'є. Зброя — тут же: чи
	# показати Sword_Attack, чи Punch_Jab/Punch_Cross (П-162), знає лише
	# сервер (`worn_in`) — клієнту чуже спорядження не шлють узагалі.
	_link.to_watchers(me, &"client_swing", [me, a.worn_in("зброя") != null])
	var power: float = a.stats.physical_attack()
	if behind:
		# Чуття жертви зрізає надбавку: сприйняття захищає від удару в
		# спину (П-37, правка 3). Числа зрізання — пропозиція П-90.
		power *= 1.0 + Stats.back_bonus_against(victim.stats)
	var hit: int = Stats.damage_through(power, victim.stats.physical_defence())
	victim.hp = maxi(0, victim.hp - hit)
	_mark_fight(a, victim)
	_try_interrupt(victim, a.target_id, hit)
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
	var c: Node = _creatures.get(id)
	if c == null:
		return
	var high: float = ground_height.call(home_spot.x, home_spot.y)
	c.place_at(Vector3(home_spot.x, high + 6.0, home_spot.y), 0.0)
	print("[дім] %d поставлено в місто (%.0f, %.0f) на висоті %.2f"
			% [id, home_spot.x, home_spot.y, c.global_position.y])
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
	var state: Dictionary = skill.state_at(level)
	for victim: Node in victims:
		if power > 0.0:
			_land(me, a, victim, power)
		# Баф або дебаф зі скіла — тим самим механізмом станів, що й усе
		# інше (крок 2.1). Окремого коду для монстрів немає.
		if not state.is_empty() and victim.is_alive():
			victim.add_state(State.from_data(state))
	# Переніс у місто — не шкода й не стан, тож окремо. Діє на того,
	# хто читав: ціль скіла — «себе».
	if skill.sends_home(level):
		send_home(me)
		_link.notice(me, "ти в місті")
	print("[скіл] %d застосував %s рівня %d, цілей %d, мани лишилось %d"
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
		var level: int = a.learned.get(a.casting_key, 1)
		# Ціль беремо ту, на кого починали (П-42).
		a.target_id = a.casting_target if a.casting_target != 0 else a.target_id
		a.stop_cast()
		if skill == null:
			continue
		var victims: Array = _victims_for(a, id, skill, level)
		_link.to_watchers(id, &"client_cast_end", [id, not victims.is_empty()])
		if victims.is_empty():
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
	print("[каст] %d збито ударом на %d (опір %.0f, шанс %.0f%%)"
			% [id, hit, guard, chance * 100.0])
	victim.stop_cast()
	victim.busy_in = 0.0
	_link.notice(id, "читання перервано")
	_link.to_watchers(id, &"client_cast_end", [id, false])


## Кого зачепить скіл. Тут-таки й повідомлення про невдачу, бо причина
## залежить від типу цілі (П-42).
func _victims_for(a: Node, me: int, skill: Skill, level: int) -> Array:
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
			if id == me or ((id < 0) == (me < 0)) != friends:
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
	_mark_fight(a, victim)
	_try_interrupt(victim, id, hit)
	if id < 0 and me > 0:
		victim.add_threat(me, hit + victim.threat_per_hit)
	_link.to_watchers(id, &"client_hp", [id, victim.hp])
	_link.to_watchers(id, &"client_damage", [id, hit, false])
	if victim.hp <= 0:
		_kill(me, a, victim, id)


## Хтось загинув. Тут-таки й винагорода вбивці: повага, досвід і дроп
## (крок 3). Гравець за гравця поки не отримує нічого — це PvP, і воно
## має свої правила (П-88).
## Кому сказати про смерть, крім клієнтів: світ ловить так боса
## підземелля (Ф6). (victim_id, victim) -> void.
var on_kill: Callable


func _kill(me: int, killer: Node, victim: Node, victim_id: int) -> void:
	victim.die()
	# Гравець за смерть втрачає повагу: рівно 10% обсягу поточного рівня
	# (П-27, числа замовника). Досвід не втрачається.
	if victim_id > 0:
		var lost: int = progress.death_loss(victim)
		_link.notice(victim_id, "втрачено %d поваги" % lost)
		print("[смерть] %d втратив %d поваги, лишилось %d"
				% [victim_id, lost, victim.respect])
		# І частина речей (друга половина П-27). Поки вони просто
		# зникають: «на землі» вимагає предметів у світі, яких ще немає —
		# записано в П-112.
		var gone_all: Array = progress.lose_items(victim, goods)
		for gone: String in gone_all:
			_link.notice(victim_id, "загублено: %s" % gone)
			print("[смерть] %d загубив %s" % [victim_id, gone])
	print("[бій] %d загинув, труп лежатиме %.0f с"
			% [victim_id, victim.corpse_left])
	_link.to_watchers(victim_id, &"client_died", [victim_id])
	if me > 0 and victim_id < 0:
		_reward(me, killer, victim)
	if on_kill.is_valid():
		on_kill.call(victim_id, victim)


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
		_link.notice(me, "рівень %d! очок статів: %d"
				% [killer.level, killer.stat_points])
		print("[рівень] %d узяв %d рівень" % [me, killer.level])

	for row: Dictionary in victim.drop_table:
		if randf() > float(row.get("шанс", 0.0)) * mult:
			continue
		var count: int = randi_range(int(row.get("від", 1)),
				int(row.get("до", 1)))
		if count <= 0:
			continue
		_give(me, killer, str(row["що"]), count)


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
