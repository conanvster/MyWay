class_name SkinnedModel
extends Node3D
## Тіло з готової моделі: те, що завантажене з набору (П-15).
##
## Уміє два різні випадки, і це не примха:
##
##   **у моделі є анімації** — граємо їх (ходьба, стояння, удар). Так у
##   наборах KayKit і в «LowPoly Animated Animals».
##   **анімацій немає, але є кістяк** — гойдаємо кістки самі: стегна й
##   плечі навперемін. Так у безкоштовній частині «Bestiary»: моделі
##   там із кістяком, а рухів до них не додали.
##
## Назви кісток у наборах Quaternius звичні для Unreal: `thigh_l`,
## `upperarm_r`, `spine_01`. На них і спираємось, а як не знайдемо —
## просто стоїмо, і це не помилка.

const STEP := deg_to_rad(26.0)      ## розмах кроку, коли гойдаємо самі
const SWING_TIME := 0.4

var path := ""
var height := 1.0
var tint := Color(1, 1, 1)

var _skeleton: Skeleton3D
var _player: AnimationPlayer
var _bones: Dictionary = {}
var _rest: Dictionary = {}
var _phase := 0.0
var _speed := 0.0
var _swing_left := 0.0


func build() -> void:
	if path == "" or not ResourceLoader.exists(path):
		return
	var scene: PackedScene = load(path)
	if scene == null:
		return
	var body: Node3D = scene.instantiate()
	body.name = "Тіло"
	add_child(body)
	scale = Vector3(height, height, height)

	_player = body.find_child("AnimationPlayer", true, false)
	_skeleton = body.find_child("*Skeleton3D*", true, false)
	if _skeleton == null:
		for child in body.find_children("*", "Skeleton3D", true, false):
			_skeleton = child
			break
	if _skeleton != null:
		for name: String in ["thigh_l", "thigh_r", "upperarm_l", "upperarm_r"]:
			var at := _skeleton.find_bone(name)
			if at != -1:
				_bones[name] = at
				_rest[name] = _skeleton.get_bone_pose_rotation(at)
	if _player != null:
		_play_if_has(["Idle", "idle", "Idle_A"])


## Пофарбувати. У готових моделей уже свої текстури, тож фарба лише
## підмішується — інакше з вовка вийшла б однотонна пляма.
func dress(color: Color, size: float) -> void:
	tint = color
	height = size
	scale = Vector3(size, size, size)


func animate(speed: float) -> void:
	_speed = speed
	if _player != null:
		if speed > 0.35:
			_play_if_has(["Walk", "walk", "Run", "Walk_A"])
		else:
			_play_if_has(["Idle", "idle", "Idle_A"])
		return
	_swing_bones(speed)


func swing() -> void:
	_swing_left = SWING_TIME
	if _player != null:
		_play_if_has(["Attack", "attack", "Punch", "Attack_A"], false)


func _process(delta: float) -> void:
	_swing_left = maxf(0.0, _swing_left - delta)
	if _player == null and _skeleton != null:
		_phase += delta * clampf(_speed, 0.0, 6.0) * 2.2
		_swing_bones(_speed)


## Своя хода для моделей без анімацій: стегна навперемін, руки — навпаки.
func _swing_bones(speed: float) -> void:
	if _skeleton == null or _bones.is_empty():
		return
	var wide: float = STEP if speed > 0.35 else deg_to_rad(2.0)
	var swing := sin(_phase) * wide
	_bend("thigh_l", swing)
	_bend("thigh_r", -swing)
	_bend("upperarm_l", -swing * 0.6)
	# Права рука або гойдається, або б'є.
	_bend("upperarm_r", deg_to_rad(-70.0) if _swing_left > 0.0
			else swing * 0.6)


func _bend(name: String, by: float) -> void:
	if not _bones.has(name):
		return
	var at: int = _bones[name]
	_skeleton.set_bone_pose_rotation(at,
			_rest[name] * Quaternion(Vector3.RIGHT, by))


func _play_if_has(names: Array, loop: bool = true) -> void:
	if _player == null:
		return
	for name: String in names:
		if _player.has_animation(name):
			if _player.current_animation == name and loop:
				return
			_player.play(name)
			return
