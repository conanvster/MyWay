extends Node3D
## Камера за П-47.
##
## Висить згори, тримає заданий напрямок. Права кнопка миші — вільне
## наведення. Під час бігу повільно доводиться в напрямок руху.
##
## ГОЛОВНЕ ПРАВИЛО П-47: камера не показує далі, ніж зона бачення
## персонажа. Інакше відмотка стала б безкоштовним бафом на Чуття.
## Поки статів немає (крок 8 у П-52), радіус береться з `vision_radius`
## — це заглушка, яку замінить стат.
##
## Упор у геометрію — за П-39: тверді перешкоди підтягують камеру до
## гравця, косметичні (трава, дерева) не мають тіла зіткнення взагалі,
## тому промінь їх не помічає.

## Заглушка замість стата Чуття.
@export var vision_radius: float = 18.0
## На скільки камера висить вище точки, за якою стежить.
@export var pivot_height: float = 1.2

const PITCH_MIN := 30.0
const PITCH_MAX := 75.0
const DISTANCE_MIN := 3.0
## Частка зони бачення, далі якої камеру не відпускаємо.
const DISTANCE_OF_VISION := 0.55
const MOUSE_SENSITIVITY := 0.004
const ZOOM_STEP := 1.0
## Наскільки швидко камера доводиться за бігом. Менше — повільніше.
const DRIFT_SPEED := 1.2
## Запас, щоб камера не влипала в саму стіну.
const WALL_MARGIN := 0.3

var yaw: float = 0.0
var pitch: float = deg_to_rad(50.0)
var distance: float = 10.0
var free_aim: bool = false

@onready var _camera: Camera3D = $Camera3D
@onready var _target: Node3D = get_parent()


func _ready() -> void:
	top_level = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				free_aim = event.pressed
				Input.mouse_mode = (Input.MOUSE_MODE_CAPTURED if free_aim
						else Input.MOUSE_MODE_VISIBLE)
			MOUSE_BUTTON_WHEEL_UP:
				distance -= ZOOM_STEP
			MOUSE_BUTTON_WHEEL_DOWN:
				distance += ZOOM_STEP
	elif event is InputEventMouseMotion and free_aim:
		yaw -= event.relative.x * MOUSE_SENSITIVITY
		pitch += event.relative.y * MOUSE_SENSITIVITY


func _process(delta: float) -> void:
	if _target == null:
		return

	# Доведення за бігом — тільки коли гравець не наводить камеру сам.
	var dir: Vector3 = _target.get("move_direction")
	if not free_aim and dir != null and dir.length() > 0.1:
		var wanted := atan2(-dir.x, -dir.z)
		yaw = lerp_angle(yaw, wanted, 1.0 - exp(-DRIFT_SPEED * delta))

	pitch = clamp(pitch, deg_to_rad(PITCH_MIN), deg_to_rad(PITCH_MAX))
	distance = clamp(distance, DISTANCE_MIN, max_distance())

	var pivot: Vector3 = _target.global_position + Vector3.UP * pivot_height
	global_position = pivot

	var offset := Vector3(
			sin(yaw) * cos(pitch),
			sin(pitch),
			cos(yaw) * cos(pitch)) * distance
	_camera.global_position = _clear_of_walls(pivot, pivot + offset)
	_camera.look_at(pivot, Vector3.UP)


## Межа відмотки: камера не бачить далі, ніж персонаж.
func max_distance() -> float:
	return maxf(DISTANCE_MIN, vision_radius * DISTANCE_OF_VISION)


## Тверда перешкода між гравцем і камерою підтягує камеру (П-39).
func _clear_of_walls(from: Vector3, to: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	# Тільки шар «світ». Косметика тіл зіткнення не має і сюди не потрапляє.
	query.collision_mask = 1
	query.exclude = [_target.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return to
	return hit["position"] + (from - to).normalized() * WALL_MARGIN
