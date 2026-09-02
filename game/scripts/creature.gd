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

## Відновлення здоров'я й мани (числа — пропозиція П-101), частка
## максимуму за секунду:
const REGEN_FIGHT := 0.01    ## у бою
const REGEN_REST := 0.02     ## стоячи, поза боєм
const REGEN_SIT := 0.06      ## сидячи — утричі швидше, ніж стоячи
## Скільки після удару вважається «в бою».
const FIGHT_TIME := 3.0
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
## Рівень персонажа: його дає ПОВАГА (крок 3). Поки не росте, але скіли
## вже питають, бо вчаться з певного рівня.
var level := 1
## Досвід — валюта на навчання скілів (не повага, яка дає рівні).
var experience := 0
## Повага — те, що дає рівні. За смерть втрачається 10% обсягу рівня.
var respect := 0
## Нерозподілені очки статів: по стільки за кожен рівень.
var stat_points := 0
## Раса й стать: від них залежить і сітка поваги, і базові стати (П-89).
var race := "людина"
var sex := "чоловік"
## Речі: ім'я -> скільки. Руни живуть тут-таки, поки немає інвентаря
## (крок 4). Заглушка навмисно проста: правила рун від неї не залежать.
var items: Dictionary = {}

## Вивчені скіли: ключ -> рівень усередині грейду (П-106).
var learned: Dictionary = {}
## Відкати скілів: ключ -> скільки секунд лишилось.
var skill_ready_in: Dictionary = {}
var attack_ready_in := 0.0
var busy_in := 0.0
## Що зараз читається: ключ скіла, скільки лишилось і скільки тривало.
## Порожній ключ означає, що каст не йде (крок 2.3).
var casting_key := ""
var casting_left := 0.0
var casting_full := 0.0
## Кого мітив, коли починав. Ціль могли змінити посеред читання, а скіл
## має влучити в того, на кого його починали (П-42).
var casting_target := 0
## Скільки ще лічиться «в бою»: оновлюється кожним ударом по тобі й твоїм.
var in_fight := 0.0
## Сидить: відновлює швидше, але встає від першого ж удару (П-101).
var sitting := false
## Залишки, що не дотягли до цілої одиниці. Без них при 1% на секунду й
## тіку 1/60 не відновлювалось би нічого взагалі: roundi(0,016) = 0.
var _hp_left := 0.0
var _mp_left := 0.0
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
	sitting = false
	stop_cast()
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
	in_fight = maxf(0.0, in_fight - delta)
	_regen(delta)

	for key in skill_ready_in.keys():
		var left: float = skill_ready_in[key] - delta
		if left <= 0.0:
			skill_ready_in.erase(key)
		else:
			skill_ready_in[key] = left

	# Строк станів спливає на сервері; що скінчилось — перераховуємо.
	if not states.tick(delta).is_empty():
		refresh_stats()


## Чи знає істота цей скіл і чи минув його відкат.
func knows(key: String) -> bool:
	return learned.has(key)


func skill_ready(key: String) -> bool:
	return not skill_ready_in.has(key)


func has_item(name: String) -> bool:
	return name == "" or int(items.get(name, 0)) > 0


## Забрати одну штуку. Руна витрачається при використанні (П-50).
func take_item(name: String) -> void:
	if name == "":
		return
	var left: int = int(items.get(name, 0)) - 1
	if left > 0:
		items[name] = left
	else:
		items.erase(name)


func give_item(name: String, count: int = 1) -> void:
	items[name] = int(items.get(name, 0)) + count


## Вивчити скіл одразу потрібного рівня. Руни й досвід — крок 2.5; поки
## це шлях, яким скіл потрапляє в істоту (і в монстра теж).
func learn(key: String, level: int = 1) -> void:
	learned[key] = level


## Відновлення здоров'я й мани. Швидкість залежить від того, чи ти в бою
## і чи сидиш (П-93, П-101). Монстри користуються тим самим кодом —
## у них це «здоров'я потроху відновлюється» з П-109.
func _regen(delta: float) -> void:
	if not is_alive():
		return
	var rate := REGEN_FIGHT
	if in_fight <= 0.0:
		rate = REGEN_SIT if sitting else REGEN_REST
	_hp_left += stats.max_hp() * rate * delta
	_mp_left += stats.max_mp() * rate * delta
	if _hp_left >= 1.0:
		hp = mini(stats.max_hp(), hp + int(_hp_left))
		_hp_left -= int(_hp_left)
	if _mp_left >= 1.0:
		mp = mini(stats.max_mp(), mp + int(_mp_left))
		_mp_left -= int(_mp_left)


## Сісти або встати. Сидячи відновлюєшся втричі швидше, але від першого
## удару підводишся.
func sit(down: bool) -> void:
	sitting = down and is_alive()


func is_casting() -> bool:
	return casting_key != ""


## Почати читання.
func start_cast(key: String, seconds: float, target: int) -> void:
	casting_key = key
	casting_left = seconds
	casting_full = seconds
	casting_target = target


## Кинути читання — і коли дочитав, і коли збили.
func stop_cast() -> void:
	casting_key = ""
	casting_left = 0.0
	casting_full = 0.0
	casting_target = 0


func is_alive() -> bool:
	return hp > 0


func vision_radius() -> float:
	return stats.vision_radius()
