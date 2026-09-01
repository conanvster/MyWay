extends CharacterBody3D
## Персонаж.
##
## Рух рахує ТІЛЬКИ сервер (П-08). Клієнт надсилає намір — куди хоче
## бігти — і малює те, що сервер відповів. Своєї позиції клієнт не
## вигадує: передбачення руху це окреме питання (П-55).

const SPEED := 5.0
## Радіус, у якому персонаж бачить інших (П-40). Тримає СЕРВЕР — це
## частина правил гри, а не налаштування клієнта. Поки стала; на кроці 8
## її почне рахувати стат Чуття, а дебафи — знижувати.
const VISION_RADIUS := 18.0
## Щоб на самій межі персонажі не блимали, зникають вони трохи далі,
## ніж з'являються.
const VISION_HYSTERESIS := 1.12

## ЗАГЛУШКИ до кроку 8, коли числа почнуть рахуватись зі статів.
## Швидкість атаки за П-35 задають стати, а не темп кліків, тому удар
## має відкат, і зайві натискання просто пропадають.
const ATTACK_COOLDOWN := 1.2
const ATTACK_RANGE := 2.5
const ATTACK_DAMAGE := 7
const MAX_HP := 100

## Панель за П-20: сім комірок, куди призначаються дії. Уміння з'являться
## пізніше, поки тут лише те, що вже вирішено — удар і вибір цілі.
const BAR := ["attack", "next_player", "next_mob", "", "", "", ""]

## Черга дій за П-38: 4-6 натискань. Не скидається ані за часом, ані
## при зміні цілі. Точне число підбирається при налаштуванні.
const QUEUE_MAX := 5
## Скільки персонаж зайнятий після удару, перш ніж почне наступну дію.
## Заглушка до кроку 8: замах теж має рахуватись зі статів.
const SWING_TIME := 0.35

## Що чекає на виконання. Тримає СЕРВЕР.
var queue: Array[String] = []
## Доки персонаж зайнятий попередньою дією.
var busy_in := 0.0

var hp := MAX_HP
## Кого б'ємо. 0 — нікого.
var target_id := 0
## Скільки лишилось до наступного удару.
var attack_ready_in := 0.0

## Куди персонаж біжить зараз. Камера бере це, щоб доводитись за рухом.
var move_direction := Vector3.ZERO
## Намір, надісланий клієнтом. Заповнює сервер із мережі.
var wanted := Vector2.ZERO
## Куди сервер сказав стати. Клієнт плавно підтягується сюди.
var server_position := Vector3.ZERO

var is_local := false

@onready var _rig: Node3D = $CameraRig


func _ready() -> void:
	# Камера є в кожного аватара, але працює тільки у свого.
	_rig.set_process(false)
	_rig.set_process_unhandled_input(false)


func become_local() -> void:
	is_local = true
	_rig.set_process(true)
	_rig.set_process_unhandled_input(true)
	$CameraRig/Camera3D.current = true


## Крок руху. Викликає лише сервер.
func server_step(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
	else:
		velocity.y = 0.0

	# Обрізаємо довжину: інакше підроблений намір дав би надшвидкість.
	var dir := Vector3(wanted.x, 0.0, wanted.y).limit_length(1.0)
	move_direction = dir
	velocity.x = dir.x * SPEED
	velocity.z = dir.z * SPEED
	move_and_slide()
	attack_ready_in = maxf(0.0, attack_ready_in - delta)
	busy_in = maxf(0.0, busy_in - delta)


func is_alive() -> bool:
	return hp > 0


## Намір цього клієнта у СВІТОВИХ осях: перерахунок за поворотом камери
## робить клієнт, бо тільки він знає, куди дивиться.
func sample_intent() -> Vector2:
	var input := Vector2.ZERO
	# input.y — це «скільки вперед», тому W додатний. Множиться на вектор
	# forward, і зі знаком навпаки W вів би назад.
	if Input.is_key_pressed(KEY_W):
		input.y += 1.0
	if Input.is_key_pressed(KEY_S):
		input.y -= 1.0
	if Input.is_key_pressed(KEY_A):
		input.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		input.x += 1.0
	input = input.normalized()

	var cam := _rig.global_transform.basis
	var forward := Vector3(-cam.z.x, 0.0, -cam.z.z).normalized()
	var right := Vector3(cam.x.x, 0.0, cam.x.z).normalized()
	var dir := right * input.x + forward * input.y
	if dir.length() > 0.0:
		dir = dir.normalized()

	# Камера доводиться за рухом одразу, не чекаючи відповіді сервера.
	move_direction = dir
	return Vector2(dir.x, dir.z)
