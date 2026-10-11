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

## Смуг панелі по сім комірок (слово замовника 21.09.2026, П-232):
## «більше грейд — більше полосок… 2 грейд 2 полоски, 3 грейд 3, 4 грейд
## 4». Грейд рахується від ременя: E — перший, D — другий і так далі;
## без ременя — одна смуга, як і було. Комірки всіх чотирьох смуг живуть
## у `bar` завжди, а ремінь лише вирішує, скількома з них можна
## користуватись: зняв ремінь — розкладка не губиться.
const STRIP := 7
const MAX_STRIPS := 4


func strips() -> int:
	var belt: Item = worn_in("ремінь")
	if belt == null:
		return 1
	return clampi(ItemBook.GRADES.find(belt.grade) + 1, 1, MAX_STRIPS)


## Панель завжди на всі чотири смуги: розкладка, збережена до
## 21.09.2026, мала сім комірок.
func pad_bar() -> void:
	while bar.size() < STRIP * MAX_STRIPS:
		bar.append("")
	if bar.size() > STRIP * MAX_STRIPS:
		bar.resize(STRIP * MAX_STRIPS)


## Чи можна тиснути цю комірку з тим ременем, що зараз на тобі.
func slot_open(slot: int) -> bool:
	return slot >= 0 and slot < STRIP * strips()

## Модель людини (П-150): Quaternius Universal Base Characters + Universal
## Animation Library, обидва CC0 (game/models/player/LICENSE_CC0_*.txt).
## Лише «Superhero» statура є в безкоштовному рівні набору — «Regular» і
## «Teen» лишаються за платною версією (звідси не всі шість тіл).
const MODEL_MALE := "res://models/player/Superhero_Male_FullBody.gltf"
const MODEL_FEMALE := "res://models/player/Superhero_Female_FullBody.gltf"
const MODEL_ANIM := "res://models/player/animations/UAL1_Standard.glb"
## Людина, ельф і орк обох статей, одягнені (19.09.2026, слово замовника:
## «на базі моделі людини зробити ельфа й орка з рухами як у людини, і
## хоча б 1 комплект одягу для всіх»). Зроблені з тієї самої моделі
## людини з тим самим скелетом (`tools/blender/make_races.py`), тож рухи
## UAL1 пересаджуються на них так само. Немає файлу — лишається гола
## модель людини вище.
const RACE_MODEL := "res://models/own/races/%s-%s.gltf"
## Зріст раси, метрів. Числа виконавця, замовник не називав.
const RACE_HEIGHT := {"людина": 1.75, "ельф": 1.85, "орк": 1.9}

var is_local := false
## Куди йти, коли ведуть мишею: клік по землі ставить сюди точку, і
## персонаж іде до неї сам. Порожній вектор — веде клавіатура.
##
## Намір іде тими самими шляхами, що й від клавіш, і сервер перевіряє
## його так само: миша не дає нічого, чого не дають WASD.
var walk_to := Vector3.ZERO
## Наскільки близько треба підійти, щоб рахувати, що дійшов.
const ARRIVED := 0.8
## Скільки секунд сервер ще везе після того, як клієнт сказав «стій»:
## знімок раз на 0,05 с (20 Гц) плюс намір, що вже в дорозі.
const LEAD := 0.12

## Швидкість за знімками сервера, м/с — для запасу на зупинку.
##
## Слово замовника 11.10.2026: «під великим бафом на швидкість аватар
## пригає через 3-4 метри, а потім повертається назад; до монстра
## підходиш наскрізь, а потім тебе відкидає». Клієнт вирішував «дійшов»
## за НАМАЛЬОВАНОЮ позицією, а вона через згладжування й знімки
## відстає на ~0,15 с: на 5 м/с це пів метра, під бафом — метри. Сервер
## тим часом проскакував точку, а фігура потім поверталась.
var server_speed := 0.0
var _seen_at := Vector3.ZERO
var _seen_time := 0.0

@onready var _rig: Node3D = $CameraRig


func _ready() -> void:
	super()
	var body := model()
	if body != null:
		body.dress(Color("#d8c04a"), 1.75)
	# Камера є в кожного аватара, але працює тільки у свого.
	_rig.set_process(false)
	_rig.set_process_unhandled_input(false)


## Поставити справжню модель замість капсули — той самий прийом, що й у
## `mob.gd::_apply_look()`, тільки за статтю, не за видом монстра.
##
## `path` — окрема модель аватара (01.10.2026: аватари зі сканів на тому
## самому скелеті, `tools/blender/avatar_build.py`); порожньо — модель
## раси.
func apply_sex(sex: String, race: String = "людина", path: String = "") -> void:
	var made := path if path != "" else \
			RACE_MODEL % [race, "жінка" if sex == "жінка" else "чоловік"]
	if not ResourceLoader.exists(made):
		made = MODEL_FEMALE if sex == "жінка" else MODEL_MALE
	if not ResourceLoader.exists(made):
		return
	var old_body := get_node_or_null("Mesh")
	if old_body is SkinnedModel and old_body.path == made:
		return          # уже та сама модель — нічого не робимо
	if old_body != null:
		old_body.name = "СтараФігурка"
		old_body.queue_free()
	var skin := SkinnedModel.new()
	skin.name = "Mesh"
	skin.path = made
	skin.anim_path = MODEL_ANIM
	skin.height = float(RACE_HEIGHT.get(race, 1.75))
	add_child(skin)
	skin.build()
	seat_model()
	# Нова модель — роздягнена; вдягаємо те, що вже було вдягнуто.
	skin.wear(_look, _goods)
	# Розворот обличчя (Superhero змонтований у +Z, рушій рахує вперед
	# як -Z) тепер робить сам build() — SkinnedModel.REVERSED_MOUNTS,
	# спільний список на всі змонтовані задом наперед моделі, не лише
	# людину (П-162: виявилось, що й частина монстрів така сама).


## Що вдягнуто, для показу: комірка -> назва речі (`world.look_of`).
var _look: Dictionary = {}
var _goods: ItemBook = null


func wear(look: Dictionary, goods: ItemBook) -> void:
	_look = look
	_goods = goods
	var skin := model()
	if skin is SkinnedModel:
		skin.wear(look, goods)


func become_local() -> void:
	is_local = true
	_rig.set_process(true)
	_rig.set_process_unhandled_input(true)
	$CameraRig/Camera3D.current = true


## Шар «гравці» (6): монстри на нього натикаються (`mob.gd:MOB_LAYER`),
## а гравець натикається на монстрів — маска в сцені. Мертвий гравець
## монстрам не заважає: шар живий, доки живий гравець. Оживлення
## (`combat.revive`) шар вертає саме, через `server_step`.
const PLAYER_LAYER := 6


func server_step(delta: float) -> void:
	if get_collision_layer_value(PLAYER_LAYER) != is_alive():
		set_collision_layer_value(PLAYER_LAYER, is_alive())
	super(delta)


func die() -> void:
	super()
	# Гравцеві дається час на оживлення, монстрові — ні (П-70).
	corpse_left = CORPSE_PLAYER


## Де я насправді — за сервером, без згладжування. До першого знімка —
## де намальований.
func where() -> Vector3:
	return server_position if _seen_time > 0.0 else global_position


## Скільки ще проїду після «стій» — на стільки раніше й зупинятись.
func lead() -> float:
	return server_speed * LEAD


## Оновити `server_speed` з нових знімків. Знімок без руху або тиша
## довше за три знімки — стою.
func _track_server() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if server_position != _seen_at:
		var dt := now - _seen_time
		var flat := Vector2(server_position.x - _seen_at.x,
				server_position.z - _seen_at.z).length()
		if _seen_time > 0.0 and dt > 0.0:
			server_speed = minf(flat / dt, 60.0)
		_seen_at = server_position
		_seen_time = now
	elif now - _seen_time > 0.15:
		server_speed = 0.0


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
	_track_server()
	if input != Vector2.ZERO:
		walk_to = Vector3.ZERO
	elif walk_to != Vector3.ZERO:
		var to := walk_to - where()
		to.y = 0.0
		if to.length() <= ARRIVED + lead():
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
