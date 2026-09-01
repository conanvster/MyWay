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

var stats := Stats.new()
var hp := 0

## Куди істота біжить зараз. Камера бере це, щоб доводитись за рухом.
var move_direction := Vector3.ZERO
## Намір, надісланий клієнтом. Заповнює сервер із мережі.
var wanted := Vector2.ZERO
## Куди сервер сказав стати. Клієнт плавно підтягується сюди.
var server_position := Vector3.ZERO

var target_id := 0
var attack_ready_in := 0.0
var busy_in := 0.0
var queue: Array[String] = []


func _ready() -> void:
	if hp == 0:
		hp = stats.max_hp()


func server_step(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
	else:
		velocity.y = 0.0

	# Обрізаємо довжину: інакше підроблений намір дав би надшвидкість.
	var dir := Vector3(wanted.x, 0.0, wanted.y).limit_length(1.0)
	move_direction = dir
	var speed := stats.move_speed()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	move_and_slide()

	attack_ready_in = maxf(0.0, attack_ready_in - delta)
	busy_in = maxf(0.0, busy_in - delta)


func is_alive() -> bool:
	return hp > 0


func vision_radius() -> float:
	return stats.vision_radius()
