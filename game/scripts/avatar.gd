extends Creature
## Персонаж гравця.
##
## Клієнт надсилає намір — куди хоче бігти — і малює те, що сервер
## відповів. Своєї позиції клієнт не вигадує: передбачення руху це
## окреме питання (П-55).

## Панель за П-20: сім комірок, куди призначаються дії. Розкладку роздає
## сервер із `data/bar.json` (П-58) — там її й правити.
## `corpse_skill` — заглушка замість справжніх умінь по трупах
## (оживити, підірвати). Вона лише продовжує трупу строк, щоб правило
## з П-45 було на чому перевірити. Які саме вміння це робитимуть — П-68.
## Значення нижче — запасне, на випадок, коли даних немає.
var bar: Array[String] = ["attack", "next_player", "next_mob",
		"corpse_skill", "taunt", "", ""]

var is_local := false
## Куди йти, коли ведуть мишею: клік по землі ставить сюди точку, і
## персонаж іде до неї сам. Порожній вектор — веде клавіатура.
##
## Намір іде тими самими шляхами, що й від клавіш, і сервер перевіряє
## його так само: миша не дає нічого, чого не дають WASD.
var walk_to := Vector3.ZERO
## Наскільки близько треба підійти, щоб рахувати, що дійшов.
const ARRIVED := 0.8

@onready var _rig: Node3D = $CameraRig


func _ready() -> void:
	super()
	var body := model()
	if body != null:
		body.dress(Color("#d8c04a"), 1.0)
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
	# Клавіатура старша за мишу: щойно натиснув WASD — наказ іти
	# скасовується. Інакше персонаж пручався б і йшов у свою точку.
	if input != Vector2.ZERO:
		walk_to = Vector3.ZERO
	elif walk_to != Vector3.ZERO:
		var to := walk_to - global_position
		to.y = 0.0
		if to.length() <= ARRIVED:
			walk_to = Vector3.ZERO
			move_direction = Vector3.ZERO
			return Vector2.ZERO
		move_direction = to.normalized()
		return Vector2(move_direction.x, move_direction.z)

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
