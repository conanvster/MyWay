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
## Фаза стоячи: без цього вона застигає рівно там, де швидкість впала
## до нуля, — а якщо істота ще й ЖОДНОГО разу не рухалась, це рівно
## нульова фаза, тобто спокійна Т-поза (П-120: у Imp.glb і Puglin.glb
## немає жодної анімації, лишається тільки цей шлях гойдання кістками).
const IDLE_PHASE_SPEED := 0.6

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
	# Моделі з наборів приходять кожна у своєму масштабі: свиня виходила
	# завбільшки з будинок, а імп — із долоню. Тому «зріст» означає
	# МЕТРИ, а модель підганяється під нього за власною висотою.
	_fit(body)

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
		_play_if_has(["Idle"])


## Пофарбувати. У готових моделей свої кольори, тож фарбу не чіпаємо —
## міняється тільки зріст, і той у метрах.
func dress(color: Color, size: float) -> void:
	tint = color
	height = size
	_fit(get_node_or_null("Тіло"))


## Підігнати модель під потрібну висоту в метрах.
func _fit(body: Node) -> void:
	if body == null:
		return
	body.scale = Vector3.ONE
	var box := AABB()
	var first := true
	for child in body.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = child
		if mesh.mesh == null:
			continue
		var part: AABB = mesh.global_transform * mesh.mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	var tall: float = box.size.y if not first else 1.0
	if tall < 0.01:
		return
	var times := height / tall
	body.scale = Vector3(times, times, times)
	# Ставимо на землю: у наборах початок то в ногах, то посередині.
	body.position.y = -box.position.y * times


func animate(speed: float) -> void:
	_speed = speed
	if _player != null:
		if speed > 0.35:
			_play_if_has(["Walk", "Running", "Run", "Flying"])
		else:
			_play_if_has(["Idle"])
		return
	_swing_bones(speed)


func swing() -> void:
	_swing_left = SWING_TIME
	if _player != null:
		_play_if_has(["Attack", "Punch"], false)


func _process(delta: float) -> void:
	_swing_left = maxf(0.0, _swing_left - delta)
	if _player == null and _skeleton != null:
		var rate := clampf(_speed, 0.0, 6.0) * 2.2 if _speed > 0.35 \
				else IDLE_PHASE_SPEED
		_phase += delta * rate
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


## Знайти рух за частиною імені.
##
## У наборах імена з приставкою від скелета: «Armature|Idle»,
## «SkeletonArmature|Skeleton_Running», «BatArmature|Bat_Flying». Точного
## збігу шукати марно — беремо за кінцівкою імені.
func _play_if_has(names: Array, loop: bool = true) -> void:
	if _player == null:
		return
	var have := _player.get_animation_list()
	for want: String in names:
		for name: String in have:
			if not name.to_lower().ends_with(want.to_lower()):
				continue
			if _player.current_animation == name and loop:
				return
			_player.play(name)
			_player.get_animation(name).loop_mode = Animation.LOOP_LINEAR \
					if loop else Animation.LOOP_NONE
			return
