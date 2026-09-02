class_name Actions
extends RefCounted
## Черга дій і те, що з неї виходить (П-38, П-42, П-62).
##
## Далі це стане диспетчером умінь: `match` із рядками поступиться
## переліку ефектів із ресурсу (крок 2.2 у ПЛАН.md).

var _creatures: Dictionary
var _vision: Vision
var _combat: Combat
var _link: Messenger


func _init(creatures: Dictionary = {}, vision: Vision = null,
		combat: Combat = null, link: Messenger = null) -> void:
	_creatures = creatures
	_vision = vision if vision != null else Vision.new(creatures)
	_combat = combat if combat != null else Combat.new(creatures, link)
	_link = link if link != null else Messenger.new()


## Натискання стає в чергу. Переповнену чергу зайве натискання не
## розпихає — воно просто гине (П-38).
func enqueue(me: int, action: String) -> void:
	var a: Node = _creatures.get(me)
	if a == null:
		return
	if a.queue.size() >= a.QUEUE_MAX:
		return
	a.queue.append(action)


## Натиснута комірка панелі. `shift` за П-45 перемикає перебір на трупи.
func use_slot(me: int, slot: int, shift: bool) -> void:
	var a: Node = _creatures.get(me)
	if a == null or slot < 0 or slot >= a.bar.size():
		return
	var action: String = a.bar[slot]
	if action == "":
		return
	if shift and action.begins_with("next_"):
		action += "_corpse"
	enqueue(me, action)


## Взяти ціль мишею. Клієнт лише каже, у кого влучив променем; чи має він
## право її бачити, вирішує сервер.
func pick_target(me: int, id: int) -> void:
	if not _creatures.has(me):
		return
	if id != 0 and not _vision.sees(me, id):
		return  # цілі, якої не бачить, гравець узяти не може
	_creatures[me].target_id = id
	_link.to_one(me, &"client_target", [id])


## Розбір черги.
##
## Правило з П-38 і П-62 разом: шукаємо найпершу дію, готову ЗАРАЗ.
## Усе, що стоїть перед нею на відкаті, викидається — саме тому в
## `скіл1 скіл1 скіл2` другий скіл1 пропадає, а скіл2 спрацьовує.
## Якщо ж готової немає жодної, черга НЕ спорожнюється: голова чекає
## кінця відкату. Інакше п'ять натискань удару давали б один удар.
func pump(me: int) -> void:
	var a: Node = _creatures[me]
	if not a.is_alive():
		a.queue.clear()  # мертвий не діє
		return
	while a.busy_in <= 0.0 and not a.queue.is_empty():
		var at := -1
		for i in a.queue.size():
			if _off_cooldown(a, a.queue[i]):
				at = i
				break
		if at == -1:
			return  # ніхто не готовий — чекаємо, чергу лишаємо цілою
		for i in at:
			a.queue.pop_front()  # застаріле на відкаті викидається
		match a.queue.pop_front():
			"attack":
				if _combat.attack(me):
					a.busy_in = a.stats.swing_time()
			"next_player":
				cycle_target(me, false, false)
			"next_mob":
				cycle_target(me, true, false)
			"next_player_corpse":
				cycle_target(me, false, true)
			"next_mob_corpse":
				cycle_target(me, true, true)
			"corpse_skill":
				_corpse_skill(me)
			"taunt":
				_taunt(me)


## Чи минув відкат саме цієї дії. Інші причини невдачі (немає цілі,
## задалеко) сюди не входять — вони дають повідомлення й викидання.
func _off_cooldown(a: Node, action: String) -> bool:
	if action == "attack":
		return a.attack_ready_in <= 0.0
	return true


## Перебирає видимі цілі за віддаленістю, по колу. Монстри й гравці —
## окремі дії за П-31, тому й переліки окремі.
func cycle_target(me: int, mobs: bool, corpses: bool) -> void:
	var a: Node = _creatures[me]
	var list: Array = []
	for id in _vision.seen_by(me):
		if id == me or not _creatures.has(id):
			continue
		var c: Node = _creatures[id]
		# Звичайний перебір трупи пропускає: у бою ціль потрібна швидко,
		# і чіплятись за мертвих — найгірше, що може статись (П-45).
		if c.is_corpse() != corpses:
			continue
		if (id < 0) == mobs:
			list.append(id)
	if list.is_empty():
		a.target_id = 0
		_link.to_one(me, &"client_target", [0])
		return
	list.sort_custom(func(x, y):
			return a.global_position.distance_to(_creatures[x].global_position) \
					< a.global_position.distance_to(_creatures[y].global_position))
	var at := list.find(a.target_id)
	var next: int = list[(at + 1) % list.size()] if at != -1 else list[0]
	a.target_id = next
	_link.to_one(me, &"client_target", [next])


## Уміння «агресія»: піднімає загрозу так, щоб монстр перемкнувся (П-71).
func _taunt(me: int) -> void:
	var a: Node = _creatures[me]
	var t: Node = _creatures.get(a.target_id)
	if t == null or a.target_id >= 0 or not t.is_alive():
		_link.notice(me, "неможливо застосувати на даному типі цілі")
		return
	# Стати вище за найбільшу теперішню загрозу, а не додати трохи.
	var most := 0.0
	for id in t.threat:
		most = maxf(most, t.threat[id])
	t.add_threat(me, most - t.threat.get(me, 0.0) + 20.0)
	print("[монстр] %d перемкнувся на %d" % [a.target_id, me])


## Заглушка замість справжніх умінь по трупах — продовжує строк.
## Заодно показує правило П-42: до живого таке вміння не застосовне.
func _corpse_skill(me: int) -> void:
	var a: Node = _creatures[me]
	var t: Node = _creatures.get(a.target_id)
	if t == null:
		_link.notice(me, "немає цілі")
		return
	if not t.is_corpse():
		_link.notice(me, "неможливо застосувати на даному типі цілі")
		return
	t.extend_corpse()
	print("[труп] %d продовжено до %.0f с" % [a.target_id, t.corpse_left])
