class_name Portal
extends Area3D
## Портал у підземелля (П-153) — «старовинне коло з рунними написами по
## колу», словами замовника.
##
## ТЕСТОВИЙ ВАРІАНТ: тут коло, написи й визначення «гравець усередині».
## Самого переходу, підземелля за ним і вікна запрошення ще немає — план
## у `spec/dungeons.md`.
##
## Чому окремим файлом, а не частиною святині. Рішення розводить їх
## прямо: «(портал·брама·врата) біля святині не є самою святинею, а є
## окремою сутністю для телепорту і активується саме при виконанні умов
## святині» (П-153, уточнення 05.09.2026). Тобто святиня може стояти без
## портала, а портал з'являється лише після активації ключем.
##
## Запрошення на телепорт (прийняти · відмовитись · проігнорувати) —
## окреме від запрошення активувати ключем: це ДВА різні вікна. Тут
## живе лише умова, за якої показувати друге: `has_point()`.
##
## Відмовився — щоб побачити запрошення знову, треба вийти з кола й
## зайти повторно. Саме тому потрібне `left()`: без пам'яті про те, хто
## вже всередині, вікно вискакувало б щокадру.

## Радіус кола, метрів. Гравець має ЗАЙТИ в нього — тож не менший за
## пару кроків, інакше в коло треба цілитись.
const RING := 2.6
const RUNES := 12
## Наскільки коло піднято над землею, щоб не блимало крізь неї.
const LIFT := 0.06

@export var grade := "E"

## Хто вже стоїть у колі. Без цього запрошення показувалось би щокадру,
## а «відмовитись» не мало б сенсу — воно вискакувало б знову негайно.
var _inside: Dictionary = {}


func _ready() -> void:
	monitoring = false
	monitorable = false
	collision_layer = 0
	collision_mask = 0
	input_ray_pickable = false
	build()


func grade_color() -> Color:
	return ItemIcon.grade_color(grade)


func build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	var tone := grade_color()
	var glow := StandardMaterial3D.new()
	glow.albedo_color = tone
	glow.emission_enabled = true
	glow.emission = tone
	glow.emission_energy_multiplier = 2.6
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Саме коло.
	var ring := MeshInstance3D.new()
	ring.name = "Коло"
	var band := TorusMesh.new()
	band.inner_radius = RING - 0.16
	band.outer_radius = RING
	ring.mesh = band
	ring.set_surface_override_material(0, glow)
	ring.position = Vector3(0, LIFT, 0)
	add_child(ring)

	# Написи по колу — стільки ж засічок, що й на святині за формою:
	# абетки замовник не називав, тож знаки геометричні (див. shrine.gd).
	for i in RUNES:
		var turn := TAU * float(i) / float(RUNES)
		var mark := MeshInstance3D.new()
		var bar := BoxMesh.new()
		bar.size = Vector3(0.1, 0.02, 0.34 if i % 3 == 0 else 0.2)
		mark.mesh = bar
		mark.set_surface_override_material(0, glow)
		mark.position = Vector3(cos(turn), LIFT, sin(turn)) * (RING - 0.55)
		mark.rotation.y = -turn
		add_child(mark)

	# Стовп світла: видно здалеку, і саме він каже, що портал живий.
	var beam := OmniLight3D.new()
	beam.name = "Сяйво"
	beam.light_color = tone
	beam.light_energy = 3.4
	beam.omni_range = 9.0
	beam.position = Vector3(0, 1.4, 0)
	add_child(beam)


## Чи стоїть точка в колі. Плоско, по горизонталі: висота тут ні до
## чого — у коло заходять, а не залітають.
func has_point(point: Vector3) -> bool:
	var flat := Vector2(point.x - global_position.x,
			point.z - global_position.z)
	return flat.length() <= RING


## Гравець щойно зайшов у коло — чи час показувати запрошення.
## Другий раз поспіль (він усе ще всередині) відповідає `false`.
func entered(who: int, point: Vector3) -> bool:
	if not has_point(point):
		_inside.erase(who)
		return false
	if _inside.has(who):
		return false
	_inside[who] = true
	return true


## Вийшов із кола — наступний вхід знову покаже запрошення. Саме цього
## й вимагає рішення: «відмовився — вийди з кола й зайди повторно».
func left(who: int) -> void:
	_inside.erase(who)
