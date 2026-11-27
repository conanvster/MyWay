class_name MobZone
extends Area3D
## Зона появи монстрів: де саме вони заводяться.
##
## Форму задають дочірні `CollisionShape3D` — прямо в редакторі Godot,
## мишею. Їх може бути скільки завгодно в одній зоні, і саме тому зона не
## зобов'язана бути квадратом: вигнутий тунель складається з кількох
## повернутих коробок, галявина — з кулі, коридор — із циліндра.
##
## Чому не список точок у файлі (як було `MOB_SPOTS`): точку в тунелі
## руками не порахуєш, а коробку видно очима й тягнеш за ріг.
##
## Числа поведінки сюди НЕ входять — вони спільні для виду й живуть у
## `data/mobs.json`. Тут лише «де» і «скільки».
##
## Чому `Area3D`, а не простий вузол: тільки в тіла з формами редактор
## показує форму й дає тягнути її мишею. У фізиці зона участі не бере —
## шари нульові, стеження вимкнене, промінь миші крізь неї проходить.

## Вид монстра: поклик на поміч чують лише свої (П-66).
@export var kind: int = 1
## Скільки монстрів цього виду тримати в зоні.
@export var count: int = 1
## Агресивний сам нападає, пасивний відповідає (П-66).
@export var aggressive: bool = false
## Через скільки з'являється заміна вбитому, і наскільки випадково.
@export var respawn_after: float = 12.0
@export var respawn_spread: float = 4.0
## Бос рівня підземелля (Ф6): один, не вертається, його смерть
## запалює прохід далі.
@export var boss := false
## Главар охорони святині (купка «Главар N»): дає рунну есенцію (П-296).
@export var chief := false
## Бос повалений — зона більше не заселяється, навіть коли прокинеться.
var spent := false
## Поверх дерева-велета (`giant_tree.gd`, 07.11.2026). `level_set` > 0 —
## рівень замість видового, `boost` — множник статів і дропу.
var level_set := 0
var boost := 1.0
## Висоти поверху: між ними має стояти гравець, щоб зона прокинулась
## (поверхи одне над одним, і по горизонталі вони всі «поруч»).
## NAN — звичайна зона.
var floor_y := NAN
var ceil_y := NAN
## Монстр з'являється на підлозі `floor_y`, а не на рельєфі під нею.
var on_floor := false


func _ready() -> void:
	# Зона нічого не зіштовхує й ні за чим не стежить: вона просто форма.
	monitoring = false
	monitorable = false
	collision_layer = 0
	collision_mask = 0
	input_ray_pickable = false


## Випадкова точка всередині зони.
##
## Форма обирається з-поміж дочірніх пропорційно об'єму: інакше в
## тунелі з трьох колін монстри купчились би в найменшому.
func random_point() -> Vector3:
	var shapes := _shapes()
	if shapes.is_empty():
		push_warning("[зона] %s без жодної форми — усі з'являться в центрі"
				% name)
		return global_position

	var total := 0.0
	var volumes: Array[float] = []
	for s in shapes:
		var v := _volume(s.shape)
		volumes.append(v)
		total += v
	if total <= 0.0:
		return shapes[0].global_position

	var pick := randf() * total
	for i in shapes.size():
		pick -= volumes[i]
		if pick <= 0.0:
			return _point_in(shapes[i])
	return _point_in(shapes[-1])


## Чи лежить точка в зоні. Потрібне пробі: інакше «випадкова точка»
## перевіряється на слово.
func has_point(point: Vector3) -> bool:
	for s in _shapes():
		var local: Vector3 = s.global_transform.affine_inverse() * point
		if _inside(s.shape, local):
			return true
	return false


func _shapes() -> Array[CollisionShape3D]:
	var found: Array[CollisionShape3D] = []
	for child in find_children("*", "CollisionShape3D", true, false):
		var s := child as CollisionShape3D
		if s.shape != null and not s.disabled:
			found.append(s)
	return found


func _volume(shape: Shape3D) -> float:
	if shape is BoxShape3D:
		var s: Vector3 = shape.size
		return s.x * s.y * s.z
	if shape is SphereShape3D:
		return 4.0 / 3.0 * PI * pow(shape.radius, 3.0)
	if shape is CylinderShape3D:
		return PI * shape.radius * shape.radius * shape.height
	if shape is CapsuleShape3D:
		# Капсулу беремо як циліндр на всю висоту: похибка на двох
		# півкулях по краях, для місця появи це непомітно.
		return PI * shape.radius * shape.radius * shape.height
	push_warning("[зона] форма %s не підтримана — беру її центр"
			% shape.get_class())
	return 0.0


func _point_in(node: CollisionShape3D) -> Vector3:
	return node.global_transform * _local_point(node.shape)


func _local_point(shape: Shape3D) -> Vector3:
	if shape is BoxShape3D:
		var s: Vector3 = shape.size
		return Vector3(randf_range(-s.x, s.x), randf_range(-s.y, s.y),
				randf_range(-s.z, s.z)) * 0.5
	if shape is SphereShape3D:
		# Відбором: рівномірно по об'єму, без перекосу до центра.
		var r: float = shape.radius
		while true:
			var p := Vector3(randf_range(-r, r), randf_range(-r, r),
					randf_range(-r, r))
			if p.length_squared() <= r * r:
				return p
	if shape is CylinderShape3D or shape is CapsuleShape3D:
		# sqrt — інакше половина точок сіла б у чверть площі кола.
		var a := randf() * TAU
		var rr: float = shape.radius * sqrt(randf())
		var h: float = shape.height
		return Vector3(cos(a) * rr, randf_range(-h, h) * 0.5, sin(a) * rr)
	return Vector3.ZERO


func _inside(shape: Shape3D, p: Vector3) -> bool:
	if shape is BoxShape3D:
		var s: Vector3 = shape.size * 0.5
		return absf(p.x) <= s.x and absf(p.y) <= s.y and absf(p.z) <= s.z
	if shape is SphereShape3D:
		return p.length() <= shape.radius
	if shape is CylinderShape3D or shape is CapsuleShape3D:
		return Vector2(p.x, p.z).length() <= shape.radius \
				and absf(p.y) <= shape.height * 0.5
	return false
