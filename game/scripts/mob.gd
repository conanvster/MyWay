extends Creature
## Монстр.
##
## Поведінка за П-66: блукає біля свого місця, пасивний або агресивний,
## аґро веде таблиця загрози (П-71), при нападі кличе своїх на поміч.
##
## Числа — не сталі, а поля: їх роздає `дані/монстри.json` через
## `apply_tuning`, і сервер перечитує файл на ходу (крок 1.2). Значення
## нижче — запасні, на випадок, коли даних немає; вони ті самі, з якими
## гра жила до кроку 1.2, і взяті з пропозиції П-72.

## З якої відстані агресивний узагалі помічає гравця.
var notice_range := 15.0
## Скільки монстр «думає» перед нападом: на самому краю і впритул.
## Між ними — лінійно, тому що ближче гравець, то швидше реакція.
var react_far := 2.0
var react_near := 0.2
## Далі цього від свого місця монстр не жене: розвертається й забуває.
## Прив'язано до того, наскільки далеко його самого видно, щоб не
## виходило, ніби гравця б'є хтось невидимий.
var leash := 22.0
## На якій відстані чути поклик на поміч.
var help_range := 12.0
## Наскільки далеко від свого місця відходить, коли блукає.
var wander_radius := 6.0
## Частка швидкості під час блукання: монстр саме «повільно блукає».
var wander_pace := 0.3
## Скільки загрози додає удар понад завдану шкоду.
var threat_per_hit := 1.0

## Скіли монстра з даних: "у відповідь" (бафить своїх, коли його
## зачепили) і "по кривднику" (дебаф на того, хто вдарив). Погоджено
## 02.09.2026: монстри воюють за тими самими правилами, що й гравець.
var skills_by_case: Dictionary = {}
## Постійний баф, який дається при появі. Строк 0 — поки живий.
var spawn_buff: Dictionary = {}

## Місце, де монстр з'явився, і куди повертається.
var home := Vector3.ZERO
## Вид: поклик на поміч чують лише свої.
var kind := 0
var aggressive := false

## Хто скільки нашкодив. Монстр б'є того, у кого число найбільше (П-71).
var threat: Dictionary = {}

var _react_left := 0.0
var _wander_to := Vector3.ZERO
var _wander_wait := 0.0
var _had_target := false


func setup(at: Vector3, of_kind: int, is_aggressive: bool,
		tuning: Dictionary = {}) -> void:
	home = at
	kind = of_kind
	aggressive = is_aggressive
	_wander_to = at
	# Заглушка до балансування: трохи слабший за гравця. Числа з даних,
	# якщо вони є.
	base_stats.strength = 7
	base_stats.stamina = 4
	base_stats.agility = 7
	# Перерахувати ОБОВ'ЯЗКОВО тут, а не тільки в apply_tuning: без даних
	# той повертається одразу, і монстр лишався б із чинними статами по
	# 10 — тобто зі здоров'ям 100 замість 64. Спіймано пробою 02.09.
	refresh_stats()
	apply_tuning(tuning)
	# Постійний баф вішається саме тут — при появі, як і сказано.
	if not spawn_buff.is_empty():
		add_state(State.from_data(spawn_buff))
	hp = stats.max_hp()
	mp = stats.max_mp()


## Роздати числа з `дані/монстри.json`. Викликається і при появі, і коли
## сервер помітив, що файл змінили: тоді монстр міняє вдачу на ходу.
##
## Здоров'я тут НЕ перераховується: живому монстрові посеред бою це
## додало б або відібрало життя без причини. Нові стати діють із
## наступної появи.
func apply_tuning(tuning: Dictionary) -> void:
	if tuning.is_empty():
		return
	notice_range = tuning.get("помічає", notice_range)
	react_far = tuning.get("реакція_далеко", react_far)
	react_near = tuning.get("реакція_близько", react_near)
	leash = tuning.get("повідець", leash)
	help_range = tuning.get("поклик", help_range)
	wander_radius = tuning.get("блукання_радіус", wander_radius)
	wander_pace = tuning.get("блукання_темп", wander_pace)
	threat_per_hit = tuning.get("загроза_за_удар", threat_per_hit)
	skills_by_case = tuning.get("скіли", skills_by_case)
	spawn_buff = tuning.get("баф при появі", spawn_buff)
	for key in skills_by_case.values():
		learn(key, 1)
	var from_data: Dictionary = tuning.get("стати", {})
	base_stats.strength = from_data.get("сила", base_stats.strength)
	base_stats.stamina = from_data.get("витривалість", base_stats.stamina)
	base_stats.agility = from_data.get("спритність", base_stats.agility)
	# Стати помінялись — чинні перерахувати, інакше баф лишиться на
	# старих числах.
	refresh_stats()


func add_threat(id: int, amount: float) -> void:
	threat[id] = threat.get(id, 0.0) + amount


## Кого монстр ненавидить найбільше з тих, хто ще живий і поруч.
func top_threat(players: Dictionary) -> int:
	var best := 0
	var most := 0.0
	for id in threat:
		var p: Node3D = players.get(id)
		if p == null or not p.is_alive():
			continue
		if threat[id] > most:
			most = threat[id]
			best = id
	return best


func forget() -> void:
	threat.clear()
	_react_left = 0.0
	_had_target = false


## Агресивний помічає найближчого й витримує паузу перед нападом.
## Повертає того, на кого напав, або 0.
func notice(players: Dictionary, delta: float) -> int:
	if not aggressive:
		return 0
	var near := 0
	var near_dist := notice_range
	for id in players:
		var p: Node3D = players[id]
		if not p.is_alive():
			continue
		var d := global_position.distance_to(p.global_position)
		if d < near_dist:
			near_dist = d
			near = id
	if near == 0:
		_react_left = 0.0
		return 0
	if _react_left <= 0.0:
		_react_left = lerpf(react_near, react_far, near_dist / notice_range)
	_react_left -= delta
	if _react_left > 0.0:
		return 0
	return near


## Блукання: неквапні переходи в межах своєї ділянки.
func wander(delta: float) -> void:
	_wander_wait -= delta
	if _wander_wait <= 0.0 and global_position.distance_to(_wander_to) < 1.0:
		_wander_wait = randf_range(2.0, 5.0)
		var a := randf() * TAU
		var r := randf() * wander_radius
		_wander_to = home + Vector3(cos(a) * r, 0.0, sin(a) * r)
	if _wander_wait > 0.0:
		wanted = Vector2.ZERO
		return
	head_to(_wander_to, wander_pace)


func head_to(point: Vector3, pace: float) -> void:
	var d := point - global_position
	d.y = 0.0
	if d.length() < 0.2:
		wanted = Vector2.ZERO
		return
	d = d.normalized() * pace
	wanted = Vector2(d.x, d.z)


func too_far_from_home() -> bool:
	return home.distance_to(global_position) > leash


## Чи це свій: поклик на поміч чують лише монстри того самого виду.
##
## Відстань міряється від ТОГО, ХТО ЧУЄ (`self`), до місця поклику. Тут
## була вада: міряли `other.global_position.distance_to(from)`, тобто
## відстань того, хто кличе, до самого себе — завжди нуль. help_range не
## діяв узагалі, збігалась уся мапа. Проба цього не бачила, бо обидва
## монстри виду 1 у MOB_SPOTS стоять за 4,24 один від одного — ближче за
## help_range, і хибний код давав той самий результат, що й правильний.
func hears(other: Node, from: Vector3) -> bool:
	return other != self and other.kind == kind \
			and global_position.distance_to(from) <= help_range
