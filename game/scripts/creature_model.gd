class_name CreatureModel
extends Node3D
## Тіло істоти: голова, тулуб, руки, ноги — і те, як воно рухається.
##
## Це **власні** моделі з примітивів, а не куплений пак. Причина проста:
## пак із itch роздається за «назви свою ціну», качати його має замовник,
## а ходити істоти мають уже зараз. Коли моделі з'являться, цей клас
## міняється на них цілком — решта коду про нього не знає нічого, крім
## трьох викликів: `dress`, `animate`, `swing`.
##
## Анімація зібрана кодом, бо вона проста: ноги й руки гойдаються
## навперемін, тулуб трохи піднімається. Двадцять рядків замість файлу,
## який довелось би відкривати в редакторі щоразу.

const IDLE := "idle"
const WALK := "walk"
const SWING := "swing"

var tint := Color(0.7, 0.7, 0.72)
var body_height := 1.0

var _player: AnimationPlayer
var _parts: Dictionary = {}
var _swinging := false


func build() -> void:
	var paint := StandardMaterial3D.new()
	paint.albedo_color = tint
	paint.roughness = 0.9

	# Тулуб і голова.
	_parts["тулуб"] = _limb(Vector3(0.46, 0.62, 0.30), Vector3(0, 0.95, 0),
			paint)
	var head := SphereMesh.new()
	head.radius = 0.20
	head.height = 0.40
	var skull := MeshInstance3D.new()
	skull.name = "Голова"
	skull.mesh = head
	skull.position = Vector3(0, 1.46, 0)
	skull.set_surface_override_material(0, paint)
	add_child(skull)
	_parts["голова"] = skull

	# Руки й ноги: у кожної свій вузол-завіса, щоб гойдалась від плеча.
	_parts["рука ліва"] = _hinge(Vector3(-0.34, 1.22, 0),
			Vector3(0.15, 0.55, 0.15), paint, "РукаЛіва")
	_parts["рука права"] = _hinge(Vector3(0.34, 1.22, 0),
			Vector3(0.15, 0.55, 0.15), paint, "РукаПрава")
	_parts["нога ліва"] = _hinge(Vector3(-0.15, 0.64, 0),
			Vector3(0.18, 0.62, 0.18), paint, "НогаЛіва")
	_parts["нога права"] = _hinge(Vector3(0.15, 0.64, 0),
			Vector3(0.18, 0.62, 0.18), paint, "НогаПрава")

	scale = Vector3(body_height, body_height, body_height)
	_build_animations()


func _limb(size: Vector3, at: Vector3, paint: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	part.set_surface_override_material(0, paint)
	add_child(part)
	return part


## Завіса: порожній вузол на місці плеча чи стегна, а сама кінцівка
## висить під ним. Обертати треба завісу — тоді рука гойдається від
## плеча, а не крутиться навколо власної середини.
func _hinge(at: Vector3, size: Vector3, paint: Material,
		name_of: String) -> Node3D:
	var hinge := Node3D.new()
	hinge.name = name_of
	hinge.position = at
	add_child(hinge)
	var mesh := BoxMesh.new()
	mesh.size = size
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = Vector3(0, -size.y * 0.5, 0)
	part.set_surface_override_material(0, paint)
	hinge.add_child(part)
	return hinge


func _build_animations() -> void:
	var shelf := AnimationLibrary.new()
	shelf.add_animation(IDLE, _idle())
	shelf.add_animation(WALK, _walk())
	shelf.add_animation(SWING, _swing())
	_player = AnimationPlayer.new()
	_player.name = "Рух"
	add_child(_player)
	_player.add_animation_library("", shelf)
	_player.animation_finished.connect(func(_name: StringName) -> void:
			_swinging = false)
	_player.play(IDLE)


## Стоїть: тулуб ледь дихає.
func _idle() -> Animation:
	var move := Animation.new()
	move.length = 2.4
	move.loop_mode = Animation.LOOP_LINEAR
	_track(move, "Голова:position:y", [[0.0, 1.46], [1.2, 1.48], [2.4, 1.46]])
	return move


## Іде: ноги й руки навперемін, тулуб трохи гойдається.
func _walk() -> Animation:
	var move := Animation.new()
	move.length = 0.8
	move.loop_mode = Animation.LOOP_LINEAR
	var swing := deg_to_rad(32.0)
	_track(move, "НогаЛіва:rotation:x", [[0.0, swing], [0.4, -swing],
			[0.8, swing]])
	_track(move, "НогаПрава:rotation:x", [[0.0, -swing], [0.4, swing],
			[0.8, -swing]])
	_track(move, "РукаЛіва:rotation:x", [[0.0, -swing * 0.7],
			[0.4, swing * 0.7], [0.8, -swing * 0.7]])
	_track(move, "РукаПрава:rotation:x", [[0.0, swing * 0.7],
			[0.4, -swing * 0.7], [0.8, swing * 0.7]])
	_track(move, "Голова:position:y", [[0.0, 1.46], [0.2, 1.50],
			[0.6, 1.50], [0.8, 1.46]])
	return move


## Б'є: права рука вниз і назад.
func _swing() -> Animation:
	var move := Animation.new()
	move.length = 0.45
	_track(move, "РукаПрава:rotation:x", [[0.0, 0.0],
			[0.15, deg_to_rad(-115.0)], [0.45, 0.0]])
	return move


func _track(move: Animation, path: String, keys: Array) -> void:
	var at := move.add_track(Animation.TYPE_VALUE)
	move.track_set_path(at, NodePath(path))
	for key: Array in keys:
		move.track_insert_key(at, float(key[0]), float(key[1]))


# ── те, що бачить решта коду ──────────────────────────────────────────

## Колір і зріст.
##
## Тіло НЕ перебудовується: міняється фарба на вже готових частинах і
## загальний масштаб. Перша спроба перебудовувала — і виходило, що старі
## вузли ще не зникли (`queue_free` відкладений), а нові діставали імена
## «РукаЛіва2». Анімація після цього не знаходила ні рук, ні ніг:
## «couldn't resolve track 'РукаЛіва:rotation:x'».
func dress(color: Color, height: float) -> void:
	tint = color
	body_height = height
	if _parts.is_empty():
		return                      # ще не збудовано — колір візьме build
	var paint := StandardMaterial3D.new()
	paint.albedo_color = tint
	paint.roughness = 0.9
	for name in _parts:
		var part: Node3D = _parts[name]
		if part is MeshInstance3D:
			part.set_surface_override_material(0, paint)
		else:
			for child in part.get_children():
				if child is MeshInstance3D:
					child.set_surface_override_material(0, paint)
	scale = Vector3(body_height, body_height, body_height)


## Іде чи стоїть. Швидкість підганяє темп кроку: біжить — швидше.
func animate(speed: float) -> void:
	if _player == null or _swinging:
		return
	if speed > 0.35:
		if _player.current_animation != WALK:
			_player.play(WALK)
		_player.speed_scale = clampf(speed / 5.0, 0.5, 2.0)
	elif _player.current_animation != IDLE:
		_player.play(IDLE)
		_player.speed_scale = 1.0


## Замахнутись. Перебиває ходьбу, а після себе вертає її сама.
func swing() -> void:
	if _player == null:
		return
	_swinging = true
	_player.play(SWING)
