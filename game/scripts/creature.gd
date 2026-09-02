class_name Creature
extends CharacterBody3D
## Спільне для всього живого: гравців і монстрів.
##
## Рух і бій рахує ТІЛЬКИ сервер (П-08). Клієнт лише малює те, що
## сервер надіслав.

## Дальність удару від статів не залежить — її задасть зброя.
const ATTACK_RANGE := 2.5
## Щоб на самій межі персонажі не блимали, зникають вони трохи далі,
## ніж з'являються.
const VISION_HYSTERESIS := 1.12
## Черга дій за П-38: 4-6 натискань.
const QUEUE_MAX := 5
## Правило повороту (П-85, погоджено 02.09.2026):
##
##   є ціль (аґро)  — розвертається до неї МИТТЮ, обійти не вийде;
##   немає цілі     — напрямок дає рух, і тільки він.
##
## Тому спину відкриває не той, хто повільно крутиться, а той, хто тебе
## ЩЕ НЕ ПОМІТИВ: пасивний монстр блукає, дивлячись куди йде, і поки його
## не вдарили — на гравця поруч не повертається.

## Скільки лежить труп (П-45). Без застосованого вміння — коротко,
## із застосованим — довго. Числа взяті з середини погоджених меж
## 3-5 і 15-30 секунд.
const CORPSE_SHORT := 4.0
const CORPSE_LONG := 20.0
## Труп гравця лежить незрівнянно довше за монстрячий: до 20 хвилин,
## щоб хтось устиг його оживити (П-70).
const CORPSE_PLAYER := 1200.0
## З яким запасом здоров'я гравець підводиться (П-69).
const REVIVE_SHARE := 0.30

## Стати БАЗОВІ: раса, стать, рівень. Їх міняє тільки розвиток.
var base_stats := Stats.new()
## Стати ЧИННІ: базові плюс усе, що зараз висить (крок 2.1). Саме їх
## питає бій — щоб дебаф на чутливість чи баф на відкат діяли самі собою,
## без окремої перевірки в кожній формулі.
var stats := Stats.new()
## Бафи й дебафи. Кожен зі строком (П-108).
var states := States.new()
var hp := 0
## Мана. Витрачати її поки нічим — заглушка до вмінь (крок 2.2), але HUD
## показує справжнє число, а не намальоване.
var mp := 0
## Скільки труп ще лежатиме. 0 у живого.
var corpse_left := 0.0

## Куди істота біжить зараз. Камера бере це, щоб доводитись за рухом.
var move_direction := Vector3.ZERO
## Куди істота ДИВИТЬСЯ: поворот навколо вертикалі, у радіанах.
## Веде сервер — з напрямку руху, а при ударі з напрямку на ціль.
## Без цього поля нема на чому рахувати удар зі спини (П-40, П-81):
## капсули на екрані були повернуті випадково.
var facing := 0.0
## Куди сервер сказав дивитись. Клієнт плавно довертається сюди.
var server_facing := 0.0
## Намір, надісланий клієнтом. Заповнює сервер із мережі.
var wanted := Vector2.ZERO
## Куди сервер сказав стати. Клієнт плавно підтягується сюди.
var server_position := Vector3.ZERO

var target_id := 0
var attack_ready_in := 0.0
var busy_in := 0.0
var queue: Array[String] = []


func _ready() -> void:
	refresh_stats()
	if hp == 0:
		hp = stats.max_hp()
	if mp == 0:
		mp = stats.max_mp()


## Перерахувати чинні стати. Кликати після кожної зміни станів або
## базових статів; сам бій цього не робить — він просто читає `stats`.
func refresh_stats() -> void:
	stats = states.applied_to(base_stats)


## Повісити баф або дебаф і одразу перерахувати стати.
func add_state(state: State) -> void:
	states.apply(state)
	refresh_stats()


func die() -> void:
	hp = 0
	corpse_left = CORPSE_SHORT
	queue.clear()
	wanted = Vector2.ZERO
	target_id = 0


## Вміння, застосоване до трупа, продовжує йому строк (П-45).
func extend_corpse() -> void:
	corpse_left = maxf(corpse_left, CORPSE_LONG)


func is_corpse() -> bool:
	return hp <= 0 and corpse_left > 0.0


## Труп лягає. Викликає клієнт — це суто вигляд.
func lay_down() -> void:
	var mesh := get_node_or_null("Mesh")
	if mesh != null:
		mesh.rotation = Vector3(PI / 2.0, 0.0, 0.0)
		mesh.position = Vector3(0.0, -0.5, 0.0)


## Зворотне до `lay_down`. Теж суто вигляд, теж викликає клієнт.
## Без цього оживлений лишався лежати на екрані в усіх, хто його бачить
## — з повним здоров'ям і на ходу.
func stand_up() -> void:
	var mesh := get_node_or_null("Mesh")
	if mesh != null:
		mesh.rotation = Vector3.ZERO
		mesh.position = Vector3.ZERO


## Розвернутись у бік напрямку. Кут той самий, що й у камери: -Z вузла
## дивиться туди, куди показує `dir`.
func face_to(dir: Vector3) -> void:
	if dir.x * dir.x + dir.z * dir.z < 0.0001:
		return
	facing = atan2(-dir.x, -dir.z)


## Розвернутись до точки. Миттю — так вирішено в П-85.
func face_point(point: Vector3) -> void:
	face_to(point - global_position)


## Переставити БЕЗ плавності: поява, оживлення, майбутні телепорти.
## Інакше клієнт тягне капсулу до нової позиції з SMOOTHING = 14, і
## оживлений проїжджає через усю мапу за пів секунди, крізь будинки.
func place_at(pos: Vector3, look: float) -> void:
	global_position = pos
	server_position = pos
	facing = look
	server_facing = look
	rotation.y = look


func server_step(delta: float) -> void:
	if not is_alive():
		corpse_left = maxf(0.0, corpse_left - delta)
		return
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
	else:
		velocity.y = 0.0

	# Обрізаємо довжину: інакше підроблений намір дав би надшвидкість.
	var dir := Vector3(wanted.x, 0.0, wanted.y).limit_length(1.0)
	move_direction = dir
	# Біжить — дивиться туди, куди біжить: бігти боком не можна. Стоїть —
	# тримає бік; розвертає його тільки ціль (`face_point` у бою та в
	# mob_ai.gd), і саме тому непомічений гравець заходить у спину.
	face_to(dir)
	var speed := stats.move_speed()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	move_and_slide()

	attack_ready_in = maxf(0.0, attack_ready_in - delta)
	busy_in = maxf(0.0, busy_in - delta)

	# Строк станів спливає на сервері; що скінчилось — перераховуємо.
	if not states.tick(delta).is_empty():
		refresh_stats()


func is_alive() -> bool:
	return hp > 0


func vision_radius() -> float:
	return stats.vision_radius()
