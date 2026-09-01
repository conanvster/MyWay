extends CharacterBody3D
## Тимчасовий рух для перевірки. Рух поки рахує КЛІЄНТ — авторитетний
## сервер це крок 3 у П-52, тут його свідомо ще немає.

const SPEED := 5.0

## Напрямок бігу зараз. Камера бере його, щоб повільно доводитись
## за рухом (П-47).
var move_direction := Vector3.ZERO

@onready var _rig: Node3D = $CameraRig


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
	else:
		velocity.y = 0.0

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

	# Рух відносно камери, а не світових осей: із поверненою камерою
	# «вперед» інакше вело б убік.
	var cam := _rig.global_transform.basis
	var forward := Vector3(-cam.z.x, 0.0, -cam.z.z).normalized()
	var right := Vector3(cam.x.x, 0.0, cam.x.z).normalized()

	move_direction = (right * input.x + forward * input.y)
	if move_direction.length() > 0.0:
		move_direction = move_direction.normalized()

	velocity.x = move_direction.x * SPEED
	velocity.z = move_direction.z * SPEED
	move_and_slide()
