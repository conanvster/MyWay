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

## Моделі, змонтовані обличчям у +Z замість -Z, яким рушій усюди (face_to,
## camera_rig) рахує вперед (П-150/П-162, заміряно прямою камерою на
## кожен файл окремо — 05.09.2026: конвенція не спільна для всього
## проєкту, а йде по НАБОРУ. Bestiary (Skeleton/Bat/Dragon/Slime/Imp/
## Puglin) розвернутий, набір тварин (Cow/Pig/Sheep/Pug) — ні, і
## Superhero (гравець) розвернутий так само, як Bestiary. Без цього
## списку йшла б лише людина — а розвернутими виявились і монстри.
const REVERSED_MOUNTS := {
	"res://models/player/Superhero_Male_FullBody.gltf": true,
	"res://models/player/Superhero_Female_FullBody.gltf": true,
	"res://models/creatures/Skeleton.fbx": true,
	"res://models/creatures/Bat.fbx": true,
	"res://models/creatures/Dragon.fbx": true,
	"res://models/creatures/Slime.fbx": true,
	"res://models/monsters/Imp.glb": true,
	"res://models/monsters/Puglin.glb": true,
}

## Власні моделі замовника з Blender (19.09.2026, `art/monsters/`,
## `tools/blender/`). Blender ставить перед моделі на −Y, і після
## експорту вона дивиться на +Z — задом до руху, як і більшість наборів
## вище. Щоб кожну нову модель не дописувати в перелік, уся тека
## розвертається сама.
const OWN_DIR := "res://models/own/"

var path := ""
var height := 1.0
var tint := Color(1, 1, 1)
## Окремий набір рухів (П-150): база й анімації часто йдуть різними
## файлами (Quaternius Base Characters + Animation Library), той самий
## кістяк, той самий шлях `Armature/Skeleton3D` від кореня. Порожньо —
## анімації беруться з `path`, як і раніше.
var anim_path := ""

var _skeleton: Skeleton3D
var _player: AnimationPlayer
var _bones: Dictionary = {}
var _rest: Dictionary = {}
var _phase := 0.0
var _speed := 0.0
var _swing_left := 0.0
## Що зараз реально грає — своє, не через `AnimationPlayer.get_playing_speed()`
## (П-162, спіймано наживо: хода «рвалась», кліп перезапускався по кілька
## разів на секунду — прапорець «назад» тремтить кадр-до-кадру на межі
## порогу, а без свого запису кожне тремтіння сприймалось як нову зміну).
var _current_name := ""
var _current_reverse := false


func build() -> void:
	if path == "" or not ResourceLoader.exists(path):
		return
	var scene: PackedScene = load(path)
	if scene == null:
		return
	var body: Node3D = scene.instantiate()
	body.name = "Тіло"
	add_child(body)
	if REVERSED_MOUNTS.get(path, false) or path.begins_with(OWN_DIR):
		body.rotation.y = PI
	# Моделі з наборів приходять кожна у своєму масштабі: свиня виходила
	# завбільшки з будинок, а імп — із долоню. Тому «зріст» означає
	# МЕТРИ, а модель підганяється під нього за власною висотою.
	_fit(body)

	_player = body.find_child("AnimationPlayer", true, false)
	if _player == null and anim_path != "" \
			and ResourceLoader.exists(anim_path):
		_player = _borrow_player(body, anim_path)
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


## Забрати `AnimationPlayer` із окремого файла (П-150): пряма пересадка,
## не перецілювання (retarget) — працює, бо в обох файлів однаковий
## кістяк на однаковій глибині (`Armature/Skeleton3D` від кореня), а
## Godot зберігає шляхи кісткових доріжок відносно `root_node`
## (тут — `".."`, тобто «батько програвача»). Переставивши сам вузол
## програвача на те саме місце в НОВОМУ дереві, шляхи лишаються
## правильними без жодної ручної підміни.
func _borrow_player(body: Node, from_path: String) -> AnimationPlayer:
	var scene: PackedScene = load(from_path)
	if scene == null:
		return null
	var donor: Node = scene.instantiate()
	var found: AnimationPlayer = \
			donor.find_child("AnimationPlayer", true, false)
	if found == null:
		donor.queue_free()
		return null
	donor.remove_child(found)
	found.owner = null      # був власником вузол-донор, якого зараз звільнимо
	body.add_child(found)
	donor.queue_free()
	return found


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
	# Рахувати відносно `body`, А НЕ світу (П-150, спіймано наживо: гравець
	# спавниться за 6 м над землею й ще падає, коли `build()` уже кличе
	# `_fit()` — `global_transform` у ту мить несе в собі ці тимчасові
	# 6 метрів, і вони назавжди застигали в локальному зсуві моделі. Раз
	# на кожен спавн — і кожен новий гравець опинявся закопаним на ту
	# саму глибину, з якої щойно впав).
	var from_body: Transform3D = body.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for child in body.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = child
		if mesh.mesh == null:
			continue
		var here: Transform3D = from_body * mesh.global_transform
		var part: AABB = here * mesh.mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	var tall: float = box.size.y if not first else 1.0
	if tall < 0.01:
		return
	var times := height / tall
	body.scale = Vector3(times, times, times)
	# Ставимо на землю: у наборах початок то в ногах, то посередині.
	body.position.y = -box.position.y * times


## `backward` (П-150): набір рухів має лише ходу ВПЕРЕД (`Walk`, `Jog_Fwd`,
## `Sprint`... — усі явно «Fwd», назад немає жодної). Істота відступає,
## лишаючись обличчям до цілі (розворот до цілі під час бою вже
## вирішений) — тіло їде назад, ноги йшли б уперед. Той самий кліп,
## пущений у зворотний бік, — стандартний прийом за відсутності
## окремого рухи назад, дешевший за нову анімацію чи зміну правила
## розвороту.
func animate(speed: float, backward: bool = false) -> void:
	_speed = speed
	if _player != null:
		if speed > 0.35:
			_play_if_has(["Walk", "Running", "Run", "Flying"], true, backward)
		else:
			_play_if_has(["Idle"])
		return
	_swing_bones(speed)


func swing() -> void:
	_swing_left = SWING_TIME
	if _player != null:
		_play_if_has(["Attack", "Punch"], false)


## Рухи, що тримаються (loop) — решта програються раз і завершуються самі
## (П-162). Немає в цьому списку — неループимо; клип, якого в наборі
## взагалі нема — `_play_if_has` мовчки нічого не робить (монстри й
## Bestiary-моделі просто не мають цих імен, і це не помилка).
const LOOPING_MOVES := {
	"Idle": true, "Walk": true, "Jog_Fwd": true, "Swim_Fwd": true,
	"Sword_Idle": true, "Spell_Simple_Idle": true,
}


## Показати конкретний рух за точною назвою (П-162: падіння, каст, бій
## за зброєю тощо) — ЩО показати, вирішує той, хто кличе
## (`client_view._human_state`); тут лише програвання.
func show_move(name: String, reverse := false) -> void:
	_play_if_has([name], LOOPING_MOVES.get(name, false), reverse)


## Чи є такий рух точно (не за нечіткою відповідністю) в цієї моделі.
## Потрібно там, де викликач сам вирішує, чи є йому чим замінити старий
## спосіб показу — наприклад, смерть (`creature.lay_down`, П-162).
func has_move(name: String) -> bool:
	if _player == null:
		return false
	return _find_animation(_player.get_animation_list(), name, true) != ""


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
##
## Два проходи, не один (П-150, спіймано наживо — гравець «зникав»,
## насправді стояв у «Crouch_Idle» по коліна в землі). У наборі з 43
## рухами на «idle» закінчується сім назв одразу (Crouch_Idle,
## Pistol_Idle, Sword_Idle...), і перший-стрічний з чистого `ends_with`
## брав «Crouch_Idle» — він у списку раніше за просто «Idle» лише тому,
## що «C» стоїть перед «I». Спершу шукаємо ТОЧНИЙ збіг (ціле ім'я або
## після «|», як у «Armature|Idle»), і лише як його немає — стару
## нечітку відповідність за кінцівкою, для наборів на кшталт скелета
## («SkeletonArmature|Skeleton_Idle»), де точного варіанта нема взагалі.
func _play_if_has(names: Array, loop: bool = true,
		reverse: bool = false) -> void:
	if _player == null:
		return
	var have := _player.get_animation_list()
	for want: String in names:
		var exact := _find_animation(have, want, true)
		var found: String = exact if exact != "" \
				else _find_animation(have, want, false)
		if found == "":
			continue
		# Свій запис, не `AnimationPlayer.get_playing_speed()` — той не
		# годиться як прапорець «уже граю задом», тому щокадровий виклик
		# із тим самим `reverse` рестартував кліп заново. `loop` тут
		# важливий: неперервний рух (Walk, Idle) не рестартуємо, поки не
		# зміниться; одноразовий (удар, Hit_Chest) МАЄ рестартувати на
		# кожен новий виклик — інакше другий удар поспіль не покажеться.
		if loop and _current_name == found and _current_reverse == reverse:
			return
		if reverse:
			_player.play_backwards(found)
		else:
			_player.play(found)
		_player.get_animation(found).loop_mode = Animation.LOOP_LINEAR \
				if loop else Animation.LOOP_NONE
		_current_name = found
		_current_reverse = reverse
		return


func _find_animation(have: PackedStringArray, want: String,
		exact_only: bool) -> String:
	var low_want := want.to_lower()
	for name: String in have:
		var low_name := name.to_lower()
		if exact_only:
			if low_name == low_want or low_name.ends_with("|" + low_want):
				return name
		elif low_name.ends_with(low_want):
			return name
	return ""
