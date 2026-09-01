extends CharacterBody3D
## Персонаж.
##
## Рух рахує ТІЛЬКИ сервер (П-08). Клієнт надсилає намір — куди хоче
## бігти — і малює те, що сервер відповів. Своєї позиції клієнт не
## вигадує: передбачення руху це окреме питання (П-55).

const SPEED := 5.0

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


## Намір цього клієнта у СВІТОВИХ осях: перерахунок за поворотом камери
## робить клієнт, бо тільки він знає, куди дивиться.
func sample_intent() -> Vector2:
	var input := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		input.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		input.y += 1.0
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
