class_name WeaponLook
extends RefCounted
## Зброя й щит у руках людини — з простих форм, кодом.
##
## Слово замовника 11.10.2026: «не бачу зброї в руках». Моделей зброї
## в проєкті немає (є лише лук скелета), а генерацію 3D зупинено
## (П-248), тож річ складається з коробок і циліндрів за ТИПОМ бази
## (`data/items.json`, поле «тип»), а колір дає грейд. Те саме робить
## уся гра там, де графіки ще нема: карти й заглушки малює код.
##
## Усе в МЕТРАХ гри; рукоять — у нулі, клинок іде вздовж +Y. Як
## повернути річ у кисті, вирішує `SkinnedModel` (кістки в різних
## моделей лежать по-різному).

## Колір металу (або дерева) за грейдом. E — кора дуба, далі метали.
const GRADE_COLORS := {
	"E": Color("#7a5a3a"), "D": Color("#8a8f96"), "C": Color("#c3cad2"),
	"B": Color("#9fc4e8"), "A": Color("#b48ae0"), "S": Color("#d9b54a"),
	"SS": Color("#e8643a"),
}
const GRIP_COLOR := Color("#4a3322")

static var _mats: Dictionary = {}


## Річ для бази `base`. Порожній вузол — коли тип незнайомий.
static func build(base: Dictionary) -> Node3D:
	var kind := str(base.get("тип", ""))
	var grade := str(base.get("грейд", "E"))
	var root := Node3D.new()
	root.name = "Річ-" + kind
	var metal := _mat(grade)
	var grip := _mat("руків'я")
	match kind:
		"меч":
			_box(root, Vector3(0.06, 0.78, 0.014), Vector3(0, 0.53, 0), metal)
			_box(root, Vector3(0.22, 0.03, 0.04), Vector3(0, 0.13, 0), metal)
			_rod(root, 0.017, 0.2, Vector3(0, 0.02, 0), grip)
		"кинджал":
			_box(root, Vector3(0.04, 0.3, 0.01), Vector3(0, 0.27, 0), metal)
			_box(root, Vector3(0.12, 0.025, 0.03), Vector3(0, 0.11, 0), metal)
			_rod(root, 0.015, 0.15, Vector3(0, 0.03, 0), grip)
		"сокира":
			_rod(root, 0.02, 0.8, Vector3(0, 0.25, 0), grip)
			_box(root, Vector3(0.2, 0.15, 0.025), Vector3(0.09, 0.56, 0),
					metal)
		"спис":
			_rod(root, 0.018, 1.9, Vector3(0, 0.3, 0), grip)
			_cone(root, 0.035, 0.24, Vector3(0, 1.37, 0), metal)
		"посох":
			_rod(root, 0.025, 1.6, Vector3(0, 0.3, 0), grip)
			_ball(root, 0.07, Vector3(0, 1.14, 0), metal)
		"лук":
			# Два плечі навскіс і тятива — лук видно з будь-якого боку.
			var upper := _box(root, Vector3(0.03, 0.62, 0.03),
					Vector3(0.06, 0.3, 0), metal)
			upper.rotation.z = deg_to_rad(12.0)
			var lower := _box(root, Vector3(0.03, 0.62, 0.03),
					Vector3(0.06, -0.3, 0), metal)
			lower.rotation.z = deg_to_rad(-12.0)
			_box(root, Vector3(0.006, 1.18, 0.006), Vector3(0.15, 0, 0),
					_mat("тятива"))
		"щит":
			var face := MeshInstance3D.new()
			var disc := CylinderMesh.new()
			disc.top_radius = 0.3
			disc.bottom_radius = 0.3
			disc.height = 0.035
			face.mesh = disc
			face.material_override = metal
			face.rotation.x = PI * 0.5
			root.add_child(face)
			_ball(root, 0.06, Vector3(0, 0, -0.03), _mat("руків'я"))
	return root


static func _box(at: Node3D, size: Vector3, pos: Vector3,
		m: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _put(at, mesh, pos, m)


static func _rod(at: Node3D, radius: float, length: float, pos: Vector3,
		m: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 10
	return _put(at, mesh, pos, m)


static func _cone(at: Node3D, radius: float, length: float, pos: Vector3,
		m: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 10
	return _put(at, mesh, pos, m)


static func _ball(at: Node3D, radius: float, pos: Vector3,
		m: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	return _put(at, mesh, pos, m)


static func _put(at: Node3D, mesh: Mesh, pos: Vector3,
		m: Material) -> MeshInstance3D:
	var one := MeshInstance3D.new()
	one.mesh = mesh
	one.material_override = m
	one.position = pos
	at.add_child(one)
	return one


## Матеріал на грейд — один на всю гру. Дерево E матове, метали блищать.
static func _mat(key: String) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	match key:
		"руків'я":
			m.albedo_color = GRIP_COLOR
			m.roughness = 0.9
		"тятива":
			m.albedo_color = Color("#d8d0b8")
			m.roughness = 1.0
		_:
			m.albedo_color = GRADE_COLORS.get(key, GRADE_COLORS["E"])
			m.metallic = 0.0 if key == "E" else 0.75
			m.roughness = 0.85 if key == "E" else 0.35
	_mats[key] = m
	return m
