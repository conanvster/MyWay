extends CharacterBody3D

## Тимчасовий рух для перевірки, що проєкт живий.
##
## Рух поки рахує КЛІЄНТ. За рішенням від 02.09.2026 сервер має бути
## авторитетним — це крок 3 у П-52, тут його свідомо ще немає.
## Керування камерою (П-47) — крок 2.

const SPEED := 5.0

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
	else:
		velocity.y = 0.0

	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		dir.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		dir.z += 1.0
	if Input.is_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		dir.x += 1.0

	dir = dir.normalized()
	velocity.x = dir.x * SPEED
	velocity.z = dir.z * SPEED
	move_and_slide()
