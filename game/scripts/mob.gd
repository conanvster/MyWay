extends Creature
## Монстр.
##
## Поведінка за П-66: блукає біля свого місця, пасивний або агресивний,
## аґро веде таблиця загрози (П-71), при нападі кличе своїх на поміч.
##
## Числа — не сталі, а поля: їх роздає `data/mobs.json` через
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
## Як він виглядає, поки немає моделей: колір і зріст (П-105). Вовк
## сірий і в повний зріст, заєць рудуватий і низенький — щоб з одного
## погляду було видно, хто є хто.
var look: Dictionary = {}

## Що з нього падає: повага, досвід і таблиця речей (крок 3).
var respect_range: Array = [0, 0]
var experience_range: Array = [0, 0]
var drop_table: Array = []

## Місце, де монстр з'явився, і куди повертається.
var home := Vector3.ZERO
## Вид: поклик на поміч чують лише свої.
var kind := 0
## Бос рівня підземелля (Ф6) — ставить спавнер із зони.
var is_boss := false
## Поселення, яке вартує (П-262); -1 — звичайний монстр. Ставить
## `Wardens.post_guards`.
var settlement := -1
var aggressive := false

## Хто скільки нашкодив. Монстр б'є того, у кого число найбільше (П-71).
var threat: Dictionary = {}

var _react_left := 0.0
var _wander_to := Vector3.ZERO
var _wander_wait := 0.0
var _had_target := false


## Чий це прикликаний (П-41). 0 — звичайний монстр. Прикликаний живе в
## тих самих від'ємних номерах, але воює на боці гравців (`Combat.side`).
var owner_id := 0
## Скільки ще стоїть, перш ніж розсипатись.
var summon_left := 0.0


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


## Роздати числа з `data/mobs.json`. Викликається і при появі, і коли
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
	level = int(tuning.get("рівень", level))
	respect_range = tuning.get("повага", respect_range)
	experience_range = tuning.get("досвід", experience_range)
	drop_table = tuning.get("дроп", drop_table)
	look = tuning.get("вигляд", look)
	_apply_look()
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


## Пофарбувати й змінити зріст. Робиться і на сервері, і на клієнті: на
## сервері воно нікому не заважає, а клієнтові саме це й потрібно.
func _apply_look() -> void:
	if look.is_empty():
		return
	# Якщо для виду названо готову модель — ставимо її замість фігурки з
	# примітивів. Немає файла — лишається фігурка, і гра йде далі.
	var made := str(look.get("модель", ""))
	var moves := str(look.get("анімації", ""))
	# Модель ще читається у фоні — не чекати її в кадрі: поки фігурка,
	# модель — коли довантажиться (`SkinnedModel.background_loads`).
	if SkinnedModel.background_loads and made != "" \
			and not (SkinnedModel.is_loaded(made)
					and SkinnedModel.is_loaded(moves)):
		SkinnedModel.warm(made)
		SkinnedModel.warm(moves)
		_look_later(made, moves)
		made = ""
	if made != "" and ResourceLoader.exists(made):
		var old_body := get_node_or_null("Mesh")
		if old_body != null and not (old_body is SkinnedModel):
			old_body.name = "СтараФігурка"
			old_body.queue_free()
			var skin := SkinnedModel.new()
			skin.name = "Mesh"
			skin.path = made
			skin.height = float(look.get("зріст", 1.0))
			skin.fur = look.get("хутро", {})
			skin.held = look.get("в_руці", {})
			# Окремий набір рухів — для моделі людини (вартовий, П-262):
			# у неї рухи лежать не в самому файлі, як у сканів звірів.
			skin.anim_path = moves
			add_child(skin)
			skin.build()
	var body := model()
	if body == null:
		return
	body.dress(Color(str(look.get("колір", "#6b6b73"))),
			float(look.get("зріст", 1.0)))
	var shape: Node3D = get_node_or_null("Collision")
	if shape != null:
		var size := float(look.get("зріст", 1.0))
		shape.scale = Vector3(size, size, size)
	seat_model()


## Дочекатись фонової моделі й поставити її (див. `_apply_look`).
var _look_waiting := false


func _look_later(made: String, moves: String) -> void:
	if _look_waiting:
		return
	_look_waiting = true
	while is_inside_tree() and not (SkinnedModel.is_loaded(made)
			and SkinnedModel.is_loaded(moves)):
		await get_tree().process_frame
	_look_waiting = false
	if is_inside_tree() and str(look.get("модель", "")) == made:
		_apply_look()


## Шар «монстри» (5). Монстр стоїть на ньому й натикається на нього та
## на шар «гравці» (6) — тож не заходить ні в іншого монстра, ні в
## гравця, а гравець — у нього (слово замовника 19.09.2026: «зроби щоб
## монстри не могли заходити один в одного», «гравець теж не може
## проходити крізь монстра»). Гравці між собою проходять, як і раніше.
## Стоїть монстр ще й на шарі «істоти» (2) — по ньому його вибирає миша.
const MOB_LAYER := 5


## Труп на дорозі не стоїть: живі проходять крізь нього, як і раніше.
## Оживляють лише гравців (`combat.revive`), тож назад шар не вертається.
func die() -> void:
	super()
	set_collision_layer_value(MOB_LAYER, false)


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
