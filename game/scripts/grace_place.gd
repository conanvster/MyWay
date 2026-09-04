class_name GracePlace
extends Area3D
## Благодатне місце: зона, де швидко відновлюють здоров'я й ману.
##
## Це «священик у місті» зі слів замовника — але поки не NPC, а **місце**
## (П-113). Стоїш у ньому й не в бою — відновлюєшся швидко; вийшов —
## як завжди. Ніякої розмови й ніякого вікна: міста ще немає, а користь
## уже потрібна.
##
## Не плутати зі «святинею» (П-153) — точками-порталами в підземелля
## (обеліски/дерева/камені/руїни): те саме українське слово раніше
## позначало обидва об'єкти, розведено 05.09.2026 (П-158).
##
## Форму задають дочірні `CollisionShape3D`, як і в зон появи, тож межі
## тягнуться мишею в редакторі.

## Частка максимуму за секунду, поки стоїш усередині.
@export var restore := 0.20
## Чи лікує в бою. За замовчуванням ні: інакше це стало б місцем,
## куди затягують монстрів.
@export var in_fight := false


func _ready() -> void:
	monitoring = false
	monitorable = false
	collision_layer = 0
	collision_mask = 0
	input_ray_pickable = false


## Чи ця точка всередині. Той самий спосіб, що й у зоні появи.
func has_point(point: Vector3) -> bool:
	for child in find_children("*", "CollisionShape3D", true, false):
		var shape: CollisionShape3D = child
		if shape.shape == null or shape.disabled:
			continue
		var local: Vector3 = shape.global_transform.affine_inverse() * point
		if shape.shape is BoxShape3D:
			var half: Vector3 = shape.shape.size * 0.5
			if absf(local.x) <= half.x and absf(local.y) <= half.y \
					and absf(local.z) <= half.z:
				return true
		elif shape.shape is CylinderShape3D:
			if Vector2(local.x, local.z).length() <= shape.shape.radius \
					and absf(local.y) <= shape.shape.height * 0.5:
				return true
		elif shape.shape is SphereShape3D:
			if local.length() <= shape.shape.radius:
				return true
	return false
