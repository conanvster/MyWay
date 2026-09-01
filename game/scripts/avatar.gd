extends Creature
## Персонаж гравця.
##
## Клієнт надсилає намір — куди хоче бігти — і малює те, що сервер
## відповів. Своєї позиції клієнт не вигадує: передбачення руху це
## окреме питання (П-55).

## Панель за П-20: сім комірок, куди призначаються дії. Уміння
## з'являться пізніше; поки тут лише те, що вже вирішено (П-58).
## `corpse_skill` — заглушка замість справжніх умінь по трупах
## (оживити, підірвати). Вона лише продовжує трупу строк, щоб правило
## з П-45 було на чому перевірити. Які саме вміння це робитимуть — П-68.
const BAR := ["attack", "next_player", "next_mob", "corpse_skill", "", "", ""]

var is_local := false

@onready var _rig: Node3D = $CameraRig


func _ready() -> void:
	super()
	# Камера є в кожного аватара, але працює тільки у свого.
	_rig.set_process(false)
	_rig.set_process_unhandled_input(false)


func become_local() -> void:
	is_local = true
	_rig.set_process(true)
	_rig.set_process_unhandled_input(true)
	$CameraRig/Camera3D.current = true


func die() -> void:
	super()
	# Гравцеві дається час на оживлення, монстрові — ні (П-70).
	corpse_left = CORPSE_PLAYER


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
