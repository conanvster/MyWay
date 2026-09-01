extends Creature
## Монстр.
##
## Поведінка за П-66: блукає біля свого місця, пасивний або агресивний,
## аґро веде таблиця загрози (П-71), при нападі кличе своїх на поміч.
##
## Числа поки з пропозиції в П-72 — вони для налаштування, важливий
## вигляд самих правил.

## З якої відстані агресивний узагалі помічає гравця.
const NOTICE_RANGE := 15.0
## Скільки монстр «думає» перед нападом: на самому краю і впритул.
## Між ними — лінійно, тому що ближче гравець, то швидше реакція.
const REACT_FAR := 2.0
const REACT_NEAR := 0.2
## Далі цього від свого місця монстр не жене: розвертається й забуває.
## Прив'язано до того, наскільки далеко його самого видно, щоб не
## виходило, ніби гравця б'є хтось невидимий.
const LEASH := 22.0
## На якій відстані чути поклик на поміч.
const HELP_RANGE := 12.0
## Наскільки далеко від свого місця відходить, коли блукає.
const WANDER_RADIUS := 6.0
## Частка швидкості під час блукання: монстр саме «повільно блукає».
const WANDER_PACE := 0.3
## Скільки загрози додає удар понад завдану шкоду.
const THREAT_PER_HIT := 1.0

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


func setup(at: Vector3, of_kind: int, is_aggressive: bool) -> void:
	home = at
	kind = of_kind
	aggressive = is_aggressive
	_wander_to = at
	# Заглушка до балансування: трохи слабший за гравця.
	stats.strength = 7
	stats.stamina = 4
	stats.agility = 7
	hp = stats.max_hp()


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
	var near_dist := NOTICE_RANGE
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
		_react_left = lerpf(REACT_NEAR, REACT_FAR, near_dist / NOTICE_RANGE)
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
		var r := randf() * WANDER_RADIUS
		_wander_to = home + Vector3(cos(a) * r, 0.0, sin(a) * r)
	if _wander_wait > 0.0:
		wanted = Vector2.ZERO
		return
	head_to(_wander_to, WANDER_PACE)


func head_to(point: Vector3, pace: float) -> void:
	var d := point - global_position
	d.y = 0.0
	if d.length() < 0.2:
		wanted = Vector2.ZERO
		return
	d = d.normalized() * pace
	wanted = Vector2(d.x, d.z)


func too_far_from_home() -> bool:
	return home.distance_to(global_position) > LEASH


## Чи це свій: поклик на поміч чують лише монстри того самого виду.
func hears(other: Node, from: Vector3) -> bool:
	return other != self and other.kind == kind \
			and other.global_position.distance_to(from) <= HELP_RANGE
