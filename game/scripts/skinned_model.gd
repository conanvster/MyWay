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
## Аватари зі сканів (02.10.2026, `tools/blender/avatar_build.py`):
## скелет манекена з тими самими назвами кісток, але суглоби зсунуті туди,
## де вони в скані, — так сітка лишається такою, як на референсі. Рухи UAL1
## задають і ПОЛОЖЕННЯ кожної кістки й повертали б суглоби на манекенові
## місця, тож для цих моделей доріжки положення лишаються лише в `root` і
## `pelvis` (переміщення тіла); решта — тільки повороти.
const OWN_SKELETON_DIR := "res://models/own/avatary/"
const KEEP_POSITION := ["root", "pelvis"]
## Фонове завантаження моделей (18.10.2026, слово замовника: «під бафом
## бігаю й бачу лаг підвантаження, необхідно зробити якесь
## передбачення»). Заміряно: перша поява виду монстра читала .glb з
## диска прямо в кадрі — 0,4…0,9 с стоп-кадру (35 моделей, у середньому
## 447 мс); повторна — ~0 мс. Клієнт світу вмикає це й просить моделі
## у фоні по одній, коли наближається до зони виду (`world._preload_step`);
## поки модель не готова, істота стоїть фігуркою й міняється на модель,
## щойно та довантажиться. Сервер і проби — на старому, синхронному шляху.
static var background_loads := false


## Попросити модель у фоні. Уже в пам'яті чи вже просили — нічого.
static func warm(file: String) -> void:
	if file == "" or ResourceLoader.has_cached(file) \
			or not ResourceLoader.exists(file):
		return
	if ResourceLoader.load_threaded_get_status(file) \
			!= ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		return
	ResourceLoader.load_threaded_request(file)


## Чи можна будувати без очікування диска.
static func is_loaded(file: String) -> bool:
	if file == "" or ResourceLoader.has_cached(file):
		return true
	var state := ResourceLoader.load_threaded_get_status(file)
	return state == ResourceLoader.THREAD_LOAD_LOADED \
			or state == ResourceLoader.THREAD_LOAD_FAILED \
			or state == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE \
			and not ResourceLoader.exists(file)


## Очищені бібліотеки рухів, щоб не дублювати 43 рухи на кожен аватар:
## шлях рухів -> {ім'я бібліотеки -> AnimationLibrary}.
static var _own_moves: Dictionary = {}

## Одяг на моделі гравця (19.09.2026, слово замовника: «моделі
## роздягнені, і коли в інвентарі вдягаю одяг — та частина, яку вдягаю,
## вдягається в моделі; при купівлі різних сетів вигляд аватара
## змінюється»). Комірка спорядження -> частини моделі
## (`tools/blender/make_races.py`, вузли «Одяг-…»). Окремої комірки для
## ніг у грі немає — штани йдуть із «тілом» разом із сорочкою (П-215).
const PIECES := {
	"тіло": ["Сорочка", "Штани"],
	"ремінь": ["Пасок"],
	"взуття": ["Чоботи"],
	"рукавиці": ["Рукавиці"],
	"голова": ["Шолом"],
}
const PIECE_PREFIX := "Одяг-"
## Що тримається в руках, а не вдягається (11.10.2026): комірка ->
## кістка кисті. Лук — у лівій, як його тримають; решта зброї — у правій.
const HELD := {"зброя": "hand_r", "щит": "hand_l"}
const BOW_HAND := "hand_l"
## Ті самі кисті на скелеті Mixamo (аватари зі сканів, 18.10.2026).
const MIXAMO_HANDS := {"hand_r": "mixamorig_RightHand",
		"hand_l": "mixamorig_LeftHand"}
## Як лягає річ у кисть: клинок `WeaponLook` іде вздовж +Y, а кість
## кисті в моделі людини дивиться інакше. Підібрано на знімку.
const GRIP_TURN := Vector3(0, 0, -90)
## Ліва кисть — дзеркало правої.
const LEFT_GRIP_TURN := Vector3(0, 0, 180)
const SHIELD_TURN := Vector3(0, -90, 0)
const HELD_PREFIX := "Тримає-"

var path := ""
var height := 1.0
var tint := Color(1, 1, 1)
## Окремий набір рухів (П-150): база й анімації часто йдуть різними
## файлами (Quaternius Base Characters + Animation Library), той самий
## кістяк, той самий шлях `Armature/Skeleton3D` від кореня. Порожньо —
## анімації беруться з `path`, як і раніше.
var anim_path := ""
## Хутро шарами (`fur_shell.gdshader`, 23.09.2026): `вигляд.хутро` у
## `data/mobs.json` — {"довжина" (метри в грі), "шари", "густота"}.
## Порожньо — моделі без ворсу, як і було.
var fur: Dictionary = {}
## Річ у руці (25.09.2026, лук скелета-лучника): `вигляд.в_руці` у
## `data/mobs.json` — {"модель" (res://…), "кістка" (типово `hand.L`),
## "поворот" [x, y, z] у градусах, "зсув" [x, y, z] в одиницях файла
## моделі}. Кістку кисті ставить `scan_lib.add_hands`. Немає кістки чи
## файла — у консоль попередження, звір лишається без речі (P3).
var held: Dictionary = {}

var _skeleton: Skeleton3D
var _player: AnimationPlayer
var _bones: Dictionary = {}
var _rest: Dictionary = {}
## Заміри капсул волосся з тіла (`_blocker_sizes`) — для проб і журналу.
var _hair_capsules: Dictionary = {}
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
	if not fur.is_empty():
		_grow_fur(body)

	_player = body.find_child("AnimationPlayer", true, false)
	if _player == null and anim_path != "" \
			and ResourceLoader.exists(anim_path):
		_player = _borrow_player(body, anim_path)
		if _player != null and path.begins_with(OWN_SKELETON_DIR):
			_rotations_only(_player)
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
	if _skeleton != null:
		_attach_hair_files()
	if _skeleton != null and not _hair_chains().is_empty():
		_hair_springs()
	_prepare_look()
	if not held.is_empty():
		_hold(held)
	if _player != null:
		_play_if_has(["Idle"])
	# Одяг сховано, доки нічого не вдягнуто.
	wear({}, null)


## Зачіски окремими файлами поруч із моделлю (П6, 06.11.2026,
## `tools/avatar_rozdilyty.py`): `<модель>_волосся-<стиль>.glb` — той самий
## скелет, одна сітка. Сітку переносимо на скелет тіла — далі пружини,
## вибір зачіски й колір працюють із нею, як із вбудованою.
func _attach_hair_files() -> void:
	var stem := path.get_file().get_basename() + "_волосся-"
	var dir := path.get_base_dir()
	var seen := {}
	for raw: String in DirAccess.get_files_at(dir):
		var file := raw.trim_suffix(".import").trim_suffix(".remap")
		if seen.has(file) or not file.begins_with(stem) \
				or file.get_extension() != "glb":
			continue
		seen[file] = true
		var scene := load(dir.path_join(file)) as PackedScene
		if scene == null:
			continue
		var holder: Node = scene.instantiate()
		for m: MeshInstance3D in holder.find_children("Волосся-*",
				"MeshInstance3D", true, false):
			var keep := m.transform
			m.owner = null
			m.get_parent().remove_child(m)
			_skeleton.add_child(m)
			m.transform = keep
			m.skeleton = m.get_path_to(_skeleton)
		holder.free()


## Вкласти річ у руку: `BoneAttachment3D` на кістці кисті. Масштаб і
## розворот тіла річ успадковує від кістяка, тож модель речі — в тих
## самих одиницях, що й файл звіра.
func _hold(what: Dictionary) -> void:
	var bone := str(what.get("кістка", "hand.L"))
	var file := str(what.get("модель", ""))
	if _skeleton == null or _skeleton.find_bone(bone) == -1:
		push_warning("в_руці: у %s немає кістки %s" % [path, bone])
		return
	if file == "" or not ResourceLoader.exists(file):
		push_warning("в_руці: немає файла %s" % file)
		return
	var grip := BoneAttachment3D.new()
	grip.name = "ВРуці"
	grip.bone_name = bone
	_skeleton.add_child(grip)
	var thing: Node3D = (load(file) as PackedScene).instantiate()
	var turn: Array = what.get("поворот", [0, 0, 0])
	var move: Array = what.get("зсув", [0, 0, 0])
	thing.rotation_degrees = Vector3(turn[0], turn[1], turn[2])
	thing.position = Vector3(move[0], move[1], move[2])
	grip.add_child(thing)


## Забрати `AnimationPlayer` із окремого файла (П-150): пряма пересадка,
## не перецілювання (retarget) — працює, бо в обох файлів однаковий
## кістяк на однаковій глибині (`Armature/Skeleton3D` від кореня), а
## Godot зберігає шляхи кісткових доріжок відносно `root_node`
## (тут — `".."`, тобто «батько програвача»). Переставивши сам вузол
## програвача на те саме місце в НОВОМУ дереві, шляхи лишаються
## правильними без жодної ручної підміни.
func _rotations_only(player: AnimationPlayer) -> void:
	if not _own_moves.has(anim_path):
		var libs := {}
		for lib_name: StringName in player.get_animation_library_list():
			var lib := player.get_animation_library(lib_name)
			var clean := AnimationLibrary.new()
			for move: StringName in lib.get_animation_list():
				var anim: Animation = lib.get_animation(move).duplicate(true)
				for t in range(anim.get_track_count() - 1, -1, -1):
					if anim.track_get_type(t) != Animation.TYPE_POSITION_3D:
						continue
					var bone := str(anim.track_get_path(t).get_concatenated_subnames())
					if not KEEP_POSITION.has(bone):
						anim.remove_track(t)
				clean.add_animation(move, anim)
			libs[lib_name] = clean
		_own_moves[anim_path] = libs
	var ready: Dictionary = _own_moves[anim_path]
	for lib_name: StringName in ready:
		player.remove_animation_library(lib_name)
		player.add_animation_library(lib_name, ready[lib_name])


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


## Вдягти: показати частини вдягнутих речей і пофарбувати їх за
## `вигляд` речі в `data/items.json` — {"колір", "текстура", "масштаб",
## "шорсткість"}. Решта частин ховається: модель без речей роздягнена.
## Вигляд — у даних, не в моделі: новий набір речей — новий вигляд без
## жодного перемальовування моделей.
func wear(look: Dictionary, goods: ItemBook) -> void:
	var shown := {}
	var sets := _detail_sets()
	for slot: String in look:
		var base: Dictionary = goods.base_of(look[slot]) if goods != null \
				else {}
		var vyhl: Dictionary = base.get("вигляд", {})
		var parts: Array = sets.get(slot, {}).get(str(base.get("тип", "")), [])
		if parts.is_empty():
			parts = PIECES.get(slot, [])
		for piece: String in parts:
			shown[piece] = vyhl
	for mesh: MeshInstance3D in find_children(PIECE_PREFIX + "*",
			"MeshInstance3D", true, false):
		var piece := str(mesh.name).trim_prefix(PIECE_PREFIX)
		mesh.visible = shown.has(piece)
		if mesh.visible:
			mesh.material_override = _cloth_on(mesh, _part_look(piece, shown[piece]))
	_hold_gear(look, goods)
	_hide_under(shown)
	# Волосся (19.09.2026) — під шоломом його не видно. Без шолома —
	# лише обрана зачіска: у моделі зі сканів їх кілька, і «показати
	# все волосся» вдягало всі зачіски одна на одну.
	var helmet := shown.has("Шолом")
	for piece: String in shown:
		helmet = helmet or piece.begins_with("голова-")
	for hair: Node in find_children("Волосся*", "MeshInstance3D", true,
			false):
		hair.visible = not helmet \
				and bool(hair.get_meta(HAIR_CHOSEN, true))
	_apply_part_sets(helmet)


## Набори деталей за типом речі (П-281, крок 4, 08.11.2026 — одяг двома
## шарами: тканина й об'ємні пластини, `spec/аватари-підходи.md`): сітки
## `Одяг-<комірка>-<тип>-<деталь>` (`Одяг-тіло-важка-нагрудник`) —
## {комірка: {тип: [«<комірка>-<тип>-<деталь>», …]}}. Річ показує деталі
## своєї комірки й свого `тип` з items.json; немає такого набору — старі
## частини `PIECES` (манекени, ельфійки).
func _detail_sets() -> Dictionary:
	if has_meta("detail_sets"):
		return get_meta("detail_sets")
	var sets := {}
	for mesh: MeshInstance3D in find_children(PIECE_PREFIX + "*",
			"MeshInstance3D", true, false):
		var piece := str(mesh.name).trim_prefix(PIECE_PREFIX)
		var bits := piece.split("-")
		if bits.size() < 3 or not PIECES.has(bits[0]):
			continue
		var by_kind: Dictionary = sets.get_or_add(bits[0], {})
		(by_kind.get_or_add(bits[1], []) as Array).append(piece)
	set_meta("detail_sets", sets)
	return sets


## Вигляд деталі за її роллю в імені (сталевий сет, П-281, 09.11.2026):
## `-підклад-` — стьобанка й кольчуга, `-шкіра-` — пояс і рукавички,
## `-тканина-` — шарф (колір `тканина` речі, інакше темно-червоний),
## `-оздоба` — обідки й заклепки (`оздоба` речі, інакше латунь). Решта —
## пластини: колір, шорсткість і `метал` самої речі.
static func _part_look(piece: String, look: Dictionary) -> Dictionary:
	if piece.contains("-підклад-"):
		return _under_tone(look)
	if piece.contains("-шкіра-"):
		return {"колір": str(look.get("шкіра", "#4a2e1c")), "шорсткість": 0.75}
	if piece.contains("-тканина-"):
		return {"колір": str(look.get("тканина", "#7a1c22")), "шорсткість": 0.9}
	if piece.ends_with("-оздоба"):
		return {"колір": str(look.get("оздоба", "#b48a48")), "шорсткість": 0.35,
				"метал": 0.85}
	return look


## Тканина під бронею (`…-підклад-…`) — темніший і тьмяніший тон кольору
## речі, без її плитки: пластини сталеві — стьобанка під ними не сталева.
static func _under_tone(look: Dictionary) -> Dictionary:
	var c := Color(str(look.get("колір", "#8a7a60")))
	var grey := (c.r + c.g + c.b) / 3.0
	c = Color(grey, grey, grey).lerp(c, 0.4).lerp(Color(0.13, 0.11, 0.09), 0.8)
	return {"колір": "#" + c.to_html(false), "шорсткість": 0.95}


## Тіло під вдягненою річчю — геть (людина MPFB, П-281, крок 4): інакше
## на русі шкіра пролазить крізь одяг. Модель несе на тілі кольори вершин
## `під_одяг` (R — під сорочкою, G — штанами, B — взуттям, A —
## рукавицями; `pilot_odiah.py`), шейдер шкіри відкидає ці місця. Без
## кольорів вершин (ельфійки, манекени) — нічого не ховається. Білизна
## під сорочкою й штанами теж ховається. Деталі наборів — за кінцем
## імені (`…-сорочка`, `…-штани`, `…-чоботи`, `…-поножі`, `…-наручі`,
## `…-рукавички`); під
## пластинами тіло не ховається — крізь проміжки його видно.
const HIDE_CHANNEL := {"Сорочка": 0, "Штани": 1, "Чоботи": 2, "Рукавиці": 3}
const HIDE_DETAIL := {"сорочка": 0, "штани": 1, "чоботи": 2, "поножі": 2,
		"наручі": 3, "рукавички": 3}
const UNDERWEAR := {"білизна-верх": 0, "білизна-низ": 1}


func _hide_under(shown: Dictionary) -> void:
	var hide := Vector4.ZERO
	for piece: String in shown:
		var ch: int = HIDE_CHANNEL.get(piece, HIDE_DETAIL.get(piece.get_slice("-",
				piece.get_slice_count("-") - 1), -1))
		if ch >= 0:
			hide[ch] = 1.0
	for m: MeshInstance3D in find_children("білизна-*", "MeshInstance3D", true, false):
		var under: int = UNDERWEAR.get(str(m.name), -1)
		m.visible = under < 0 or hide[under] < 0.5
	if _skin_mat == null or _body_mesh == null or _body_mesh.mesh == null:
		return
	if not (_body_mesh.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR):
		return
	_skin_mat.set_shader_parameter("hide_under", hide)


## Зброя й щит у руках — з `WeaponLook`. Щоразу наново: вдягання
## рідкісне, а старе тримання так не лишиться висіти після зняття.
func _hold_gear(look: Dictionary, goods: ItemBook) -> void:
	if _skeleton == null:
		return
	for old: Node in _skeleton.get_children():
		if str(old.name).begins_with(HELD_PREFIX):
			_skeleton.remove_child(old)
			old.queue_free()
	if goods == null:
		return
	for slot: String in HELD:
		if not look.has(slot):
			continue
		var base: Dictionary = goods.base_of(look[slot])
		var bone: String = BOW_HAND if str(base.get("тип", "")) == "лук" \
				else HELD[slot]
		var hand := bone
		if _skeleton.find_bone(hand) == -1:
			hand = MIXAMO_HANDS.get(bone, "")
		if hand == "" or _skeleton.find_bone(hand) == -1:
			continue
		var grip := BoneAttachment3D.new()
		grip.name = HELD_PREFIX + slot
		grip.bone_name = hand
		_skeleton.add_child(grip)
		var thing := WeaponLook.build(base, str(look[slot]))
		if slot == "щит":
			thing.rotation_degrees = SHIELD_TURN
		elif bone == "hand_l":
			thing.rotation_degrees = LEFT_GRIP_TURN
		else:
			thing.rotation_degrees = GRIP_TURN
		# Річ — у метрах гри, а кістяк — в одиницях файла, підігнаних
		# `_fit`. Ділимо на масштаб від кістяка до самої моделі.
		thing.scale = Vector3.ONE / _scale_down_to(_skeleton)
		grip.add_child(thing)


## Волосся на пружних кістках (12.10.2026, слово замовника: «перука
## потрібно зробити окремим із волоссям, яке на вітру або під час руху хоч
## трохи рухається»). Модель несе ланцюжки `hair_<ланцюжок>_<ланка>` під
## головою (`tools/blender/mixamo_zbirka.py --волосся`): у ельфійки
## v4 — L, C, R по 4 ланки (лише ззаду), з орчихи — 7 довкола голови
## (0…6, від лівого плеча через спину до правого: передні пасма на плечах
## ходили з заднім ланцюжком і проходили крізь груди). Тут — симулятор і
## капсули на тілі, щоб пасма не заходили в спину, плечі, руки й стегна.
const HAIR_STIFFNESS := 0.3
const HAIR_DRAG := 0.3
const HAIR_GRAVITY := 1.0
const HAIR_RADIUS := 0.02
## [кістка, радіус, висота, зсув уздовж кістки] — у метрах моделі (до
## `_fit`): запасні розміри (тонка ельфійка), якщо тіло не дало замірів.
## Справжні — з тіла моделі (`_blocker_sizes`): капсули на ельфійку
## пропускали волосся крізь широку орчиху (слово замовника 12.10.2026:
## «орчиха більша … ноги також ширші»). Не лише хребет: волосся проходило
## крізь плечі на бігу («крізь поверхню тіла ні одяг, ні волосся проходити
## не будуть»).
const HAIR_BLOCKERS := [
		["mixamorig_Hips", 0.13, 0.25, 0.05],
		["mixamorig_Spine", 0.11, 0.30, 0.05], ["mixamorig_Spine1", 0.11, 0.30, 0.05],
		["mixamorig_Spine2", 0.12, 0.32, 0.06], ["mixamorig_Neck", 0.055, 0.14, 0.04],
		["mixamorig_Head", 0.10, 0.22, 0.09],
		["mixamorig_LeftShoulder", 0.06, 0.16, 0.06], ["mixamorig_RightShoulder", 0.06, 0.16, 0.06],
		["mixamorig_LeftArm", 0.055, 0.30, 0.13], ["mixamorig_RightArm", 0.055, 0.30, 0.13],
		["mixamorig_LeftForeArm", 0.045, 0.26, 0.12], ["mixamorig_RightForeArm", 0.045, 0.26, 0.12],
		["mixamorig_LeftUpLeg", 0.08, 0.40, 0.2], ["mixamorig_RightUpLeg", 0.08, 0.40, 0.2],
		# Скелет MPFB `game_engine` (пілот П-281, 08.11.2026) — ті самі місця
		# тіла; розміри однаково беруться з тіла (`_blocker_sizes`).
		["pelvis", 0.13, 0.25, 0.05],
		["spine_01", 0.11, 0.20, 0.03], ["spine_02", 0.11, 0.26, 0.05],
		["spine_03", 0.12, 0.32, 0.08], ["neck_01", 0.055, 0.14, 0.06],
		["head", 0.10, 0.22, 0.09],
		["clavicle_l", 0.06, 0.16, 0.07], ["clavicle_r", 0.06, 0.16, 0.07],
		["upperarm_l", 0.055, 0.30, 0.13], ["upperarm_r", 0.055, 0.30, 0.13],
		["lowerarm_l", 0.045, 0.26, 0.12], ["lowerarm_r", 0.045, 0.26, 0.12],
		["thigh_l", 0.08, 0.40, 0.2], ["thigh_r", 0.08, 0.40, 0.2]]


## Ланцюжки пасом: [назва, ланок] — усі `hair_<назва>_1` у кістяку.
func _hair_chains() -> Array:
	var out := []
	for i in _skeleton.get_bone_count():
		var n := _skeleton.get_bone_name(i)
		if n.begins_with("hair_") and n.ends_with("_1"):
			var c := n.substr(5, n.length() - 7)
			var k := 1
			while _skeleton.find_bone("hair_%s_%d" % [c, k + 1]) != -1:
				k += 1
			out.append([c, k])
	return out


## Розміри капсул з тіла: вершини, де кістка має найбільшу вагу, — у
## просторі кістки (bind pose); радіус — процентиль відстані від осі
## кістки (Y): 80-й на руках і ногах, медіана на тулубі й голові (тулуб
## плаский — бік далі за спину, кругла капсула відсувала б волосся від
## спини; на голові — вуха); висота й зсув — 5…95-й процентилі вздовж
## осі. Кістка без замірів (шия орчихи) — запасний розмір × відношення
## тулуба до запасного. Повертає {кістка: [радіус, висота, зсув]}.
func _blocker_sizes() -> Dictionary:
	var tilo: MeshInstance3D = null
	var naib := -1
	for m: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if not _could_be_body(str(m.name)) or m.skin == null or m.mesh == null:
			continue
		var n := 0
		for s in m.mesh.get_surface_count():
			n += m.mesh.surface_get_array_len(s)
		if n > naib:
			naib = n
			tilo = m
	var out := {}
	if tilo == null:
		return out
	var skin := tilo.skin
	var potribni := {}
	for b: Array in HAIR_BLOCKERS:
		potribni[b[0]] = true
	var bind_kistka := {}       # індекс прив'язки → назва кістки
	for i in skin.get_bind_count():
		var nazva := str(skin.get_bind_name(i))
		if nazva == "" and skin.get_bind_bone(i) >= 0:
			nazva = _skeleton.get_bone_name(skin.get_bind_bone(i))
		if potribni.has(nazva):
			bind_kistka[i] = nazva
	var r := {}                 # кістка → [відстані], [y]
	for s in tilo.mesh.get_surface_count():
		var a := tilo.mesh.surface_get_arrays(s)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var kb: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var kw: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		if kb.is_empty() or v.is_empty():
			continue
		var na := kb.size() / v.size()
		for i in range(0, v.size(), 3):          # кожна третя — досить
			var best := 0
			for j in na:
				if kw[i * na + j] > kw[i * na + best]:
					best = j
			var bi := kb[i * na + best]
			if not bind_kistka.has(bi):
				continue
			var p := skin.get_bind_pose(bi) * v[i]
			var k: String = bind_kistka[bi]
			if not r.has(k):
				r[k] = [PackedFloat32Array(), PackedFloat32Array()]
			r[k][0].append(Vector2(p.x, p.z).length())
			r[k][1].append(p.y)
	for k: String in r:
		var d: PackedFloat32Array = r[k][0]
		var y: PackedFloat32Array = r[k][1]
		if d.size() < 30:
			continue
		d.sort()
		y.sort()
		var tulub := k in ["mixamorig_Hips", "mixamorig_Spine", "mixamorig_Spine1",
				"mixamorig_Spine2", "mixamorig_Neck", "mixamorig_Head",
				"neck_01", "head"]
		# Тулуб MPFB: вісь хребта ближче до спини, а груди й живіт далеко
		# попереду — медіана давала капсулу 0,14 м, ширшу за спину, і вона
		# відштовхувала косу (пілот П-281, 08.11.2026). 30-й процентиль.
		var tulub_mpfb := k in ["pelvis", "spine_01", "spine_02", "spine_03"]
		var rad := d[int(d.size() * (0.3 if tulub_mpfb else (0.5 if tulub else 0.8)))]
		var y0 := y[int(y.size() * 0.05)]
		var y1 := y[int(y.size() * 0.95)]
		out[k] = [rad, maxf(y1 - y0 + rad, 2.0 * rad), (y0 + y1) * 0.5]
	var grudy := "mixamorig_Spine2" if out.has("mixamorig_Spine2") else "spine_03"
	if out.has(grudy):
		var kf: float = out[grudy][0] / 0.12
		for b: Array in HAIR_BLOCKERS:
			if not out.has(b[0]):
				out[b[0]] = [b[1] * kf, b[2] * kf, b[3] * kf]
	return out


## Тіло — найбільша сітка, але не волосся, білизна чи одяг: боксери
## чоловіка MPFB (згладжені й стовщені) мають більше вершин, ніж тіло, і
## шейдер шкіри йшов на них (09.11.2026).
static func _could_be_body(n: String) -> bool:
	for p: String in ["Волосся", "Борода", "білизна", "Брови", "Вії", "Ікла", "Одяг"]:
		if n.begins_with(p):
			return false
	return true


## Сітки з пасом-карток: зачіски й борода (однаковий матеріал і колір).
func _hair_meshes() -> Array:
	return find_children("Волосся-*", "MeshInstance3D", true, false) \
			+ find_children("Борода-*", "MeshInstance3D", true, false)


func _hair_springs() -> void:
	# Пасма — смужки з прозорою текстурою волосинок: без відсікання прозорого
	# зачіска виглядала суцільною сірою шторою (12.10.2026).
	for m: MeshInstance3D in _hair_meshes():
		for i in m.get_surface_override_material_count():
			var src := m.get_active_material(i)
			if src is BaseMaterial3D:
				var mat: BaseMaterial3D = src.duplicate()
				# свій колір зачіски з файла (пілот MPFB) — до нього вертається
				# `customize`, коли колір у меню не вибрано
				mat.set_meta("base_albedo", src.albedo_color)
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				mat.alpha_scissor_threshold = 0.45
				mat.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				m.set_surface_override_material(i, mat)
	var sim := SpringBoneSimulator3D.new()
	sim.name = "Волосся-пружини"
	_skeleton.add_child(sim)
	var chains := _hair_chains()
	sim.set_setting_count(chains.size())
	for i in chains.size():
		var c: String = chains[i][0]
		sim.set_root_bone_name(i, "hair_%s_1" % c)
		sim.set_end_bone_name(i, "hair_%s_%d" % [c, chains[i][1]])
		sim.set_extend_end_bone(i, true)
		sim.set_end_bone_length(i, 0.06)
		sim.set_stiffness(i, HAIR_STIFFNESS)
		sim.set_drag(i, HAIR_DRAG)
		sim.set_gravity(i, HAIR_GRAVITY)
		sim.set_radius(i, HAIR_RADIUS)
		sim.set_enable_all_child_collisions(i, true)
	var mirky := _blocker_sizes()
	for b: Array in HAIR_BLOCKERS:
		if _skeleton.find_bone(b[0]) == -1:
			continue
		var m: Array = mirky.get(b[0], [b[1], b[2], b[3]])
		var cap := SpringBoneCollisionCapsule3D.new()
		cap.name = "Капсула-" + str(b[0]).trim_prefix("mixamorig_")
		cap.set_bone_name(b[0])
		cap.set_radius(m[0])
		cap.set_height(m[1])
		cap.set_position_offset(Vector3(0, m[2], 0))
		sim.add_child(cap)
	_hair_capsules = mirky


## Зовнішність аватара (12.10.2026, слово замовника: «зачіски та колір
## зачіски, Очі, Вуха, Ніс, Губи, Колір скіна»). Модель може нести:
##   * кілька зачісок — сітки `Волосся-<стиль>` (видно одну);
##   * форм-ключі рис — `Ніс-…`, `Губи-…`, `Очі-…`, `Вуха-…`
##     (`tools/blender/elf_rysy.py`);
##   * маски `<модель>_маски.png` поруч із файлом моделі — тоді тіло
##     малюється `avatar_skin.gdshader` (колір шкіри, очей, губ, скальпу).
## `customize()` бере словник:
##   «зачіска» (стиль або «без»), «колір_волосся», «колір_шкіри»,
##   «колір_очей», «колір_губ» (Color або null — як у текстурі),
##   «підводка» (0…1), «ніс», «губи», «очі», «вуха» (назва варіанта після
##   дефіса в імені ключа або «звичайні»).
const SKIN_SHADER := preload("res://shaders/avatar_skin.gdshader")
const EYE_SHADER := preload("res://shaders/avatar_eye.gdshader")
var _body_mesh: MeshInstance3D
var _skin_mat: ShaderMaterial
var _look: Dictionary = {}


## Що з вибору зовнішності ця модель уміє: {«зачіски»: […],
## «риси»: {«ніс»: […], …}, «маски»: bool}.
func look_options() -> Dictionary:
	var styles: Array = []
	for m: MeshInstance3D in find_children("Волосся-*", "MeshInstance3D", true, false):
		var st := str(m.name).trim_prefix("Волосся-")
		if not st in styles and st != "пружини":
			styles.append(st)
	var rysy := {}
	if _body_mesh != null and _body_mesh.mesh is ArrayMesh:
		var am: ArrayMesh = _body_mesh.mesh
		for i in am.get_blend_shape_count():
			var n := str(am.get_blend_shape_name(i))
			var parts := n.split("-", true, 1)
			if parts.size() == 2:
				var k := parts[0].to_lower()
				if not rysy.has(k):
					rysy[k] = []
				rysy[k].append(parts[1])
	var nabory := {}
	for k: String in PART_SETS:
		var vs := _part_set(k)
		if not vs.is_empty():
			nabory[k] = vs.map(func(m: MeshInstance3D) -> String:
				return str(m.name).trim_prefix(PART_SETS[k]))
			if k == "борода":
				(nabory[k] as Array).append(NO_PART)
	return {"зачіски": styles, "риси": rysy, "маски": _skin_mat != null,
			"шкіри": _variant_files("шкіра"), "очі_текстури": _variant_files("очі"),
			"набори": nabory}


## Набори окремих сіток, з яких видно одну (людина MPFB, П-281): брови й
## вії — у кожного варіанта MPFB своя сітка й розгортка. Сітки
## `Брови-<n>-<назва>`, `Вії-<n>-<назва>`; типово видно першу за номером.
## Борода (09.11.2026, чоловіки всіх рас): `Борода-<n>-<назва>`, колір —
## як у волосся, у меню є «немає»; під шоломом не видно.
const PART_SETS := {"брови": "Брови-", "вії": "Вії-", "борода": "Борода-"}
const NO_PART := "немає"


func _apply_part_sets(helmet := false) -> void:
	for k: String in PART_SETS:
		var want := str(_look.get(k, ""))
		var vs := _part_set(k)
		for i in vs.size():
			var m: MeshInstance3D = vs[i]
			m.visible = (str(m.name) == PART_SETS[k] + want if want != "" else i == 0) \
					and not (helmet and k == "борода")


func _part_set(kind: String) -> Array:
	var out: Array = find_children(PART_SETS[kind] + "*", "MeshInstance3D", true, false)
	out.sort_custom(func(a: Node, b: Node) -> bool: return str(a.name) < str(b.name))
	return out


## Окремі картинки-варіанти поруч із моделлю: `<модель>_<вид>-<назва>.png`
## (людина MPFB, П-281: шкіри й текстури очей MakeHuman — одна розгортка).
func _variant_files(kind: String) -> Array:
	var out: Array = []
	var stem := path.get_file().get_basename() + "_" + kind + "-"
	var d := DirAccess.open(path.get_base_dir())
	if d == null:
		return out
	for f in d.get_files():
		f = f.trim_suffix(".import")
		if f.begins_with(stem) and (f.ends_with(".png") or f.ends_with(".jpg")):
			var n := f.trim_prefix(stem).get_basename()
			if not n in out:
				out.append(n)
	out.sort()
	return out


func _variant_texture(kind: String, variant: String) -> Texture2D:
	for ext: String in [".png", ".jpg"]:
		var p: String = path.get_basename() + "_" + kind + "-" + variant + ext
		if ResourceLoader.exists(p):
			return load(p)
	return null


func _prepare_look() -> void:
	var best := 0
	for m: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if not _could_be_body(str(m.name)) or m.mesh == null:
			continue
		var n := m.mesh.get_surface_count()
		var v := 0
		for i in n:
			v += m.mesh.surface_get_array_len(i)
		if v > best:
			best = v
			_body_mesh = m
	# одна зачіска видима — перша за абеткою в моделі (типово перша в збірці)
	var first := true
	for m: MeshInstance3D in find_children("Волосся-*", "MeshInstance3D", true, false):
		m.visible = first
		m.set_meta(HAIR_CHOSEN, first)
		first = false
	for k: String in PART_SETS:
		var vs := _part_set(k)
		for i in vs.size():
			(vs[i] as MeshInstance3D).visible = i == 0
			# прозорі картки MPFB — без тіні (у тіньовому проході вони суцільні)
			(vs[i] as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_prepare_eyes()
	var masks_path := path.get_basename() + "_маски.png"
	if _body_mesh == null or not ResourceLoader.exists(masks_path):
		return
	var src := _body_mesh.get_active_material(0)
	var albedo: Texture2D = src.albedo_texture if src is BaseMaterial3D else null
	if albedo == null:
		return
	_skin_mat = ShaderMaterial.new()
	_skin_mat.shader = SKIN_SHADER
	_skin_mat.set_shader_parameter("albedo_tex", albedo)
	_skin_mat.set_shader_parameter("masks_tex", load(masks_path))
	var ref := _skin_ref(albedo, load(masks_path))
	_skin_mat.set_shader_parameter("skin_ref", ref)
	_skin_mat.set_shader_parameter("skin_tint", ref)
	# людина MPFB: губи — та сама шкіра, темнішають разом із нею (у
	# ельфійок губи намальовані окремо — лишаються як є)
	_skin_mat.set_shader_parameter("lips_skin", 1.0 if _eye_mat != null else 0.0)
	if _eye_mat != null:        # людина MPFB: світлі текстури MakeHuman
		_skin_mat.set_shader_parameter("skin_gain", 0.75)
		_skin_mat.set_shader_parameter("sss", 0.25)
	_body_mesh.material_override = _skin_mat


## Очі MPFB — окрема сітка («high-poly»/«low-poly») зі своєю текстурою:
## маска `<модель>_маски-очі.png` (R — райдужка) і шейдер очей (прозора
## рогівка) — тоді колір очей фарбує райдужку, а не все яблуко (П-281).
var _eye_mesh: MeshInstance3D
var _eye_mat: ShaderMaterial


func _prepare_eyes() -> void:
	var masks_path := path.get_basename() + "_маски-очі.png"
	if not ResourceLoader.exists(masks_path):
		return
	for m: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		var n := str(m.name)
		if not (n.ends_with("high-poly") or n.ends_with("low-poly")) or m.mesh == null:
			continue
		var src := m.get_active_material(0)
		if not (src is BaseMaterial3D) or src.albedo_texture == null:
			continue
		_eye_mesh = m
		_eye_mat = ShaderMaterial.new()
		_eye_mat.shader = EYE_SHADER
		_eye_mat.set_shader_parameter("albedo_tex", src.albedo_texture)
		_eye_mat.set_shader_parameter("masks_tex", load(masks_path))
		_eye_mat.set_shader_parameter("roughness_v", 0.12)
		m.material_override = _eye_mat
		return


## Середній тон шкіри текстури: пікселі поза масками й не порожні.
static func _skin_ref(albedo: Texture2D, masks: Texture2D) -> Vector3:
	var img := albedo.get_image()
	var mi := masks.get_image()
	if img == null:
		return Vector3(0.8, 0.68, 0.62)
	if img.is_compressed():
		img.decompress()
	if mi != null and mi.is_compressed():
		mi.decompress()
	var s := Vector3.ZERO
	var n := 0
	for y in range(0, img.get_height(), img.get_height() / 96):
		for x in range(0, img.get_width(), img.get_width() / 96):
			var c := img.get_pixel(x, y)
			if c.get_luminance() < 0.25:
				continue
			if mi != null:
				var m := mi.get_pixel(x * mi.get_width() / img.get_width(),
						y * mi.get_height() / img.get_height())
				if maxf(maxf(m.r, m.b), m.a) > 0.1:
					continue
			s += Vector3(c.r, c.g, c.b)
			n += 1
	return s / maxf(n, 1) if n > 0 else Vector3(0.8, 0.68, 0.62)


func body_mesh() -> MeshInstance3D:
	return _body_mesh


func skin_material() -> ShaderMaterial:
	return _skin_mat


func customize(look: Dictionary) -> void:
	_look.merge(look, true)
	var style := str(_look.get("зачіска", ""))
	if style != "":
		for m: MeshInstance3D in find_children("Волосся-*", "MeshInstance3D", true, false):
			m.visible = str(m.name) == "Волосся-" + style
			m.set_meta(HAIR_CHOSEN, m.visible)
	_apply_part_sets()
	var hc: Variant = _look.get("колір_волосся")
	for m: MeshInstance3D in _hair_meshes():
		var mat := m.get_surface_override_material(0)
		if mat is BaseMaterial3D:
			(mat as BaseMaterial3D).albedo_color = hc if hc is Color \
					else mat.get_meta("base_albedo", Color.WHITE)
	if _skin_mat != null:
		var ref: Vector3 = _skin_mat.get_shader_parameter("skin_ref")
		var sc: Variant = _look.get("колір_шкіри")
		_skin_mat.set_shader_parameter("skin_tint",
				Vector3(sc.r, sc.g, sc.b) if sc is Color else ref)
		_skin_mat.set_shader_parameter("hair_mix", 1.0 if hc is Color else 0.0)
		if hc is Color:
			_skin_mat.set_shader_parameter("hair_color", Vector3(hc.r, hc.g, hc.b))
		var ec: Variant = _look.get("колір_очей")
		_skin_mat.set_shader_parameter("eye_mix", 1.0 if ec is Color else 0.0)
		if ec is Color:
			_skin_mat.set_shader_parameter("eye_color", Vector3(ec.r, ec.g, ec.b))
		var lc: Variant = _look.get("колір_губ")
		_skin_mat.set_shader_parameter("lips_mix", 0.85 if lc is Color else 0.0)
		if lc is Color:
			_skin_mat.set_shader_parameter("lips_color", Vector3(lc.r, lc.g, lc.b))
		_skin_mat.set_shader_parameter("liner", float(_look.get("підводка", 0.0)))
		# інша шкіра MakeHuman (та сама розгортка) — тон рахується заново
		var st := str(_look.get("текстура_шкіри", ""))
		var tex := _variant_texture("шкіра", st) if st != "" else null
		if tex == null and _skin_mat.has_meta("albedo_0"):
			tex = _skin_mat.get_meta("albedo_0")
		if tex != null:
			if not _skin_mat.has_meta("albedo_0"):
				_skin_mat.set_meta("albedo_0", _skin_mat.get_shader_parameter("albedo_tex"))
			_skin_mat.set_shader_parameter("albedo_tex", tex)
			var r2 := _skin_ref(tex, _skin_mat.get_shader_parameter("masks_tex"))
			_skin_mat.set_shader_parameter("skin_ref", r2)
			_skin_mat.set_shader_parameter("skin_tint",
					Vector3(sc.r, sc.g, sc.b) if sc is Color else r2)
	if _eye_mat != null:
		var ec: Variant = _look.get("колір_очей")
		_eye_mat.set_shader_parameter("eye_mix", 1.0 if ec is Color else 0.0)
		if ec is Color:
			_eye_mat.set_shader_parameter("eye_color", Vector3(ec.r, ec.g, ec.b))
		var et := str(_look.get("текстура_очей", ""))
		if not _eye_mat.has_meta("albedo_0"):
			_eye_mat.set_meta("albedo_0", _eye_mat.get_shader_parameter("albedo_tex"))
		var etex := _variant_texture("очі", et) if et != "" else null
		_eye_mat.set_shader_parameter("albedo_tex",
				etex if etex != null else _eye_mat.get_meta("albedo_0"))
	# Риси — на тіло й на все, що до нього прилаштоване з тими самими
	# ключами (очі, брови, вії MPFB — П-281).
	for m: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if not (m.mesh is ArrayMesh):
			continue
		var am: ArrayMesh = m.mesh
		for i in am.get_blend_shape_count():
			var parts := str(am.get_blend_shape_name(i)).split("-", true, 1)
			if parts.size() < 2:
				continue
			var want := str(_look.get(parts[0].to_lower(), ""))
			m.set_blend_shape_value(i, 1.0 if want == parts[1] else 0.0)


## Добуток масштабів від `node` угору до цієї моделі (не включно).
func _scale_down_to(node: Node) -> float:
	var k := 1.0
	var at: Node = node
	while at != null and at != self:
		if at is Node3D:
			k *= (at as Node3D).scale.x
		at = at.get_parent()
	return maxf(k, 0.0001)


static var _cloths: Dictionary = {}


## Матеріал речі за її `вигляд` — один на весь однаковий вигляд.
static func _cloth(look: Dictionary) -> StandardMaterial3D:
	var key := str(look)
	if _cloths.has(key):
		return _cloths[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(str(look.get("колір", "#8a7a60")))
	m.roughness = float(look.get("шорсткість", 0.9))
	m.metallic = float(look.get("метал", 0.0))
	var picture := str(look.get("текстура", ""))
	if picture != "":
		if ResourceLoader.exists(picture):
			m.albedo_texture = load(picture)
			m.uv1_scale = Vector3.ONE * float(look.get("масштаб", 4.0))
		else:
			print("[одяг] ‼ немає текстури ", picture)
	_cloths[key] = m
	return m


const CLOTH_SHADER := preload("res://shaders/avatar_cloth.gdshader")
static var _own_means: Dictionary = {}


## Річ на частині з власним кроєм (П-281, крок 4): у частини є своя
## картинка (шви, складки) чи карта нормалей — тоді шейдер тканини
## (`avatar_cloth.gdshader`): барва й матеріал від речі, світлотінь і
## рельєф від частини. Без них — звичайний `_cloth`, як у манекенів.
func _cloth_on(mesh: MeshInstance3D, look: Dictionary) -> Material:
	var src: Material = mesh.mesh.surface_get_material(0) if mesh.mesh != null else null
	var own: Texture2D = null
	var nrm: Texture2D = null
	if src is BaseMaterial3D:
		own = (src as BaseMaterial3D).albedo_texture
		if (src as BaseMaterial3D).normal_enabled:
			nrm = (src as BaseMaterial3D).normal_texture
	if own == null and nrm == null:
		return _cloth(look)
	var key := "%s|%s" % [mesh.get_instance_id(), str(look)]
	if mesh.has_meta("cloth_key") and mesh.get_meta("cloth_key") == key:
		return mesh.material_override
	var m := ShaderMaterial.new()
	m.shader = CLOTH_SHADER
	m.set_shader_parameter("item_color", Color(str(look.get("колір", "#8a7a60"))))
	m.set_shader_parameter("roughness_v", float(look.get("шорсткість", 0.9)))
	m.set_shader_parameter("metallic_v", float(look.get("метал", 0.0)))
	var picture := str(look.get("текстура", ""))
	if picture != "" and ResourceLoader.exists(picture):
		m.set_shader_parameter("item_tex", load(picture))
		m.set_shader_parameter("has_item_tex", true)
		m.set_shader_parameter("item_scale", float(look.get("масштаб", 4.0)))
	if own != null:
		m.set_shader_parameter("own_tex", own)
		m.set_shader_parameter("has_own_tex", true)
		m.set_shader_parameter("own_mean", _own_mean(own))
	if nrm != null:
		m.set_shader_parameter("own_normal", nrm)
		m.set_shader_parameter("has_own_normal", true)
	mesh.set_meta("cloth_key", key)
	return m


## Звична яскравість картинки (лінійна, як у шейдері) — 80-й перцентиль по
## дрібній копії: відкрита, незатулена тканина дає рівно колір речі. Середнє
## не годиться — у світлотіні (AO) штани під полами й халявами майже всі в
## тіні, у візерунку (смуги блузи MPFB) його тягнуть темні смуги.
static func _own_mean(tex: Texture2D) -> float:
	var k := tex.resource_path if tex.resource_path != "" else str(tex.get_rid())
	if _own_means.has(k):
		return _own_means[k]
	var img := tex.get_image()
	var mean := 0.5
	if img != null:
		if img.is_compressed():
			img.decompress()
		img.resize(48, 48)
		var vals: Array[float] = []
		for y in 48:
			for x in 48:
				var c := img.get_pixel(x, y)
				# поза розгорткою — прозоре чи чорне тло, не тканина
				if c.a < 0.5 or c.get_luminance() < 0.04:
					continue
				var l := c.srgb_to_linear()
				vals.append(l.r * 0.299 + l.g * 0.587 + l.b * 0.114)
		if not vals.is_empty():
			vals.sort()
			mean = vals[vals.size() * 4 / 5]
	_own_means[k] = mean
	return mean


const FUR_SHADER := preload("res://scripts/fur_shell.gdshader")


## Ворс: до кожного матеріалу з текстурою чіпляється ланцюжок `next_pass`
## — по шару на прохід, від кореня до кінчиків. Колір волосин — з тієї ж
## текстури, що й шкура під ними. Довжина в даних — метри в грі, а шейдер
## зсуває вершини в одиницях самого файла, тому ділимо на масштаб `_fit`.
func _grow_fur(body: Node3D) -> void:
	var layers := int(fur.get("шари", 16))
	var length := float(fur.get("довжина", 0.02)) / maxf(body.scale.x, 0.0001)
	for child in body.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = child
		if mesh.mesh == null:
			continue
		for i in mesh.mesh.get_surface_count():
			var skin: Material = mesh.get_active_material(i)
			if not (skin is BaseMaterial3D) or skin.albedo_texture == null:
				continue
			var top: BaseMaterial3D = skin.duplicate()
			var last: Material = top
			for n in range(1, layers + 1):
				var shell := ShaderMaterial.new()
				shell.shader = FUR_SHADER
				shell.set_shader_parameter("albedo_tex", skin.albedo_texture)
				shell.set_shader_parameter("layer", float(n) / layers)
				shell.set_shader_parameter("fur_length", length)
				shell.set_shader_parameter("density",
						float(fur.get("густота", 600.0)))
				# Необов'язкові (кажан, 23.09.2026): без них — типові з
				# шейдера, тож заєць і вовк не міняються. `товщина` —
				# thickness, `корінь` — root_shade, `нахил` — [x, y, z]
				# gravity у власних осях моделі (перед — +Z).
				if fur.has("товщина"):
					shell.set_shader_parameter("thickness",
							float(fur["товщина"]))
				if fur.has("корінь"):
					shell.set_shader_parameter("root_shade",
							float(fur["корінь"]))
				if fur.has("нахил"):
					var g: Array = fur["нахил"]
					shell.set_shader_parameter("gravity",
							Vector3(g[0], g[1], g[2]))
				last.next_pass = shell
				last = shell
			mesh.set_surface_override_material(i, top)


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
		# Лише свої скани: у наборів кістяк буває масштабований інакше
		# за вершини, і там правдиві межі — якраз «з кістками».
		var part: AABB = here * (_true_aabb(mesh)
				if path.begins_with(OWN_SKELETON_DIR) else mesh.mesh.get_aabb())
		box = part if first else box.merge(part)
		first = false
	var tall: float = box.size.y if not first else 1.0
	if tall < 0.01:
		return
	var times := height / tall
	body.scale = Vector3(times, times, times)
	# Ставимо на землю: у наборах початок то в ногах, то посередині.
	body.position.y = -box.position.y * times


## Межі сітки за самими вершинами. Шкірену сітку Godot міряє з кістками:
## у людини l2002 (07.11.2026) `get_aabb()` — 2,81 м заввишки при вершинах
## 1,82 м, і `_fit` стискав її до 0,62 — вдвічі менша за ельфійку. Обхід
## вершин — раз на сітку (кеш), лише для шкірених.
static var _aabbs: Dictionary = {}


static func _true_aabb(view: MeshInstance3D) -> AABB:
	var mesh := view.mesh
	if view.skin == null and view.skeleton == NodePath(""):
		return mesh.get_aabb()
	var key := mesh.get_instance_id()
	if _aabbs.has(key):
		return _aabbs[key]
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for i in mesh.get_surface_count():
		for v: Vector3 in mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
			lo = lo.min(v)
			hi = hi.max(v)
	var box := AABB(lo, hi - lo) if lo.x != INF else mesh.get_aabb()
	_aabbs[key] = box
	return box


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
## Підставні рухи для аватарів зі сканів на скелеті Mixamo (18.10.2026,
## слово замовника: «виправ, чому нема в грі досі орчихи нової»). У них
## 10 рухів (Idle, Walk, Run, Jump, Sword_Slash, Block, Bow_Shot, Cast,
## Hit, Death), а гра кличе рухи набору UAL1 — тут найближчий замінник.
## Немає в переліку (Spell_Simple_Enter) — нічого не міняється. Лише
## для `OWN_SKELETON_DIR`: монстрам підстановок не треба.
const STAND_INS := {
	"Jog_Fwd": "Run", "Swim_Fwd": "Walk", "Sword_Idle": "Idle",
	"Spell_Simple_Idle": "Cast", "Spell_Simple_Exit": "Idle",
	"Sword_Attack": "Sword_Slash", "Punch_Jab": "Sword_Slash",
	"Punch_Cross": "Sword_Slash", "Jump_Start": "Jump", "Jump_Land": "Idle",
	"Hit_Chest": "Hit", "Death01": "Death",
}
const HAIR_CHOSEN := "hair_chosen"

const LOOPING_MOVES := {
	"Idle": true, "Walk": true, "Jog_Fwd": true, "Swim_Fwd": true,
	"Sword_Idle": true, "Spell_Simple_Idle": true,
}


## Показати конкретний рух за точною назвою (П-162: падіння, каст, бій
## за зброєю тощо) — ЩО показати, вирішує той, хто кличе
## (`client_view._human_state`); тут лише програвання.
##
## Одноразовий рух (влучання, смерть, блок) показ стану кличе щокадру —
## перезапускати його можна лише на `restart` (новий удар), інакше він
## застигав на першому кадрі (знайдено 07.11.2026).
func show_move(name: String, reverse := false, restart := false) -> void:
	_play_if_has([_stand_in(name)], LOOPING_MOVES.get(name, false), reverse,
			restart)


## Свій рух, коли він є; інакше замінник зі `STAND_INS`.
func _stand_in(name: String) -> String:
	if _player == null or not path.begins_with(OWN_SKELETON_DIR) \
			or not STAND_INS.has(name):
		return name
	if _find_animation(_player.get_animation_list(), name, true) != "":
		return name
	return STAND_INS[name]


## Темп усіх рухів моделі: 1 — як у файлі, 2 — удвічі швидше. Баф на
## біг чи на атаку прискорює і ноги, і замах (слово замовника
## 11.10.2026: «баф на швидкість бігу та атаки, а анімація не
## прискорюється»). Що саме прискорити, вирішує той, хто кличе.
func set_tempo(k: float) -> void:
	if _player != null:
		_player.speed_scale = k


## Тривалість руху в секундах (з урахуванням заміни зі `STAND_INS`), 0 —
## руху немає. Темп удару й касту рахується від неї (07.11.2026): у
## сканів Mixamo удар мечем 1,52 с, а не як у наборі UAL.
func move_length(name: String) -> float:
	if _player == null:
		return 0.0
	var found := _find_animation(_player.get_animation_list(),
			_stand_in(name), true)
	return _player.get_animation(found).length if found != "" else 0.0


## Чи є такий рух точно (не за нечіткою відповідністю) в цієї моделі.
## Потрібно там, де викликач сам вирішує, чи є йому чим замінити старий
## спосіб показу — наприклад, смерть (`creature.lay_down`, П-162).
func has_move(name: String) -> bool:
	if _player == null:
		return false
	return _find_animation(_player.get_animation_list(), _stand_in(name),
			true) != ""


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
		reverse: bool = false, restart: bool = true) -> void:
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
		if (loop or not restart) and _current_name == found \
				and _current_reverse == reverse:
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
