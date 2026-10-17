class_name Tree3DLook
## Дерева Tree3D (план §3в): процедурні, з гілок і гілочок з листям.
##
## Слово замовника 12.10.2026: «використай для дерев asset 3141». Пакет —
## GDExtension `addons/Tree3D` (JekSun97, MIT), вузол `Tree3D` сам будує
## дві сітки: стовбур із гілками й картки-гілочки.
##
## Вузол Tree3D на кожне дерево світу не ставимо: він будує сітку ~8 мс,
## а дерев на світі 2 десятки тисяч. Тож кожен сорт вирощується кількома
## зернами ОДИН раз, сітки забираються з вузла, а вузол викидається.
## Дерева світу ділять ці сітки й матеріали — як ділять картки ялин.
##
## Заміряно 17.10.2026 (`./run.sh --дерева3д`): числа — у шапці проби.
## Сегментів стовбура 4 замість 6: стовбур удвічі легший, а на відстані
## гравця різниці в обриси не видно.
##
## Текстури — `tools/tree3d_hilochky.py` (листя ambientCG, кора Poly
## Haven, CC0). Демо-текстури пакета без походження, тож у гру не йдуть.

const HERE := "res://models/nature/tree3d/"
## Скільки зерен на сорт. Шість — досить, щоб у гаю сусіди не були
## близнюками, і досить мало, щоб вирощування не відчувалось (~50 мс).
const SEEDS := 6

## Сорти: параметри вузла Tree3D, кора й гілочка. Параметри — з демо
## пакета (`demo/tree_3d.tscn`, вузли 1, 2, 4, 5), підправлені лише там,
## де демо-дерево не пасувало: берест у демо з волосинку завтовшки.
const KINDS := {
	"клен": {
		"кора": "kora_brunatna", "листя": "lystia_klen", "висота": 9.0,
		"trunk_height": 9, "trunk_branch_length": 0.79,
		"trunk_max_radius": 0.22, "trunk_length": 3.21, "twig_scale": 0.55,
	},
	"дуб": {
		"кора": "kora_dub", "листя": "lystia_dub", "висота": 9.0,
		# У демо 7 гілок — 14 тис. трикутників; гілки множаться степенем,
		# і 6 дає 7 тис. при тій самій ширині крони (заміряно 17.10.2026).
		"trunk_branches_count": 6, "trunk_branch_length": 0.59,
		"trunk_branch_length_falloff": 0.95, "trunk_drop_amount": -0.3,
		"trunk_grow_amount": 0.03, "trunk_max_radius": 0.18,
		"trunk_radius_falloff_rate": 0.61, "trunk_climb_rate": 0.2,
		"trunk_kink": -0.37, "trunk_twist": 1.41, "trunk_length": 7.05,
		"twig_scale": 0.65,
	},
	"берест": {
		"кора": "kora_brunatna", "листя": "lystia_berest", "висота": 7.0,
		"trunk_branches_count": 4, "trunk_height": 9,
		"trunk_branch_length": 0.59, "trunk_branch_length_falloff": 0.57,
		"trunk_drop_amount": 0.4, "trunk_max_radius": 0.12,
		"trunk_radius_falloff_rate": 0.7, "trunk_twist": 2.62,
		"trunk_length": 1.79, "twig_scale": 0.45,
	},
}

## "сорт:зерно" -> [сітка стовбура, сітка гілочок, висота в метрах]
static var _grown: Dictionary = {}
static var _paints: Dictionary = {}


static func available() -> bool:
	return ClassDB.class_exists("Tree3D")


## Сітки одного дерева. Порожньо — пакета нема (гра мусить іти й без
## нього) або сорт невідомий; про це кажемо, не мовчимо (P3).
static func grown(kind: String, seed: int) -> Array:
	var key := "%s:%d" % [kind, seed % SEEDS]
	if _grown.has(key):
		return _grown[key]
	if not KINDS.has(kind):
		push_warning("[дерева3д] невідомий сорт «%s»" % kind)
		return []
	if not available():
		push_warning("[дерева3д] пакета Tree3D нема — addons/Tree3D")
		return []
	var spec: Dictionary = KINDS[kind]
	var tree: Node3D = ClassDB.instantiate("Tree3D")
	tree.set("trunk_segments", 4)
	for field: String in spec:
		if field.begins_with("trunk_") or field.begins_with("twig_"):
			tree.set(field, spec[field])
	tree.set("seed", 100 + seed % SEEDS * 37)
	tree.set("material_trunk", _bark(str(spec["кора"])))
	tree.set("material_twig", _twig(str(spec["листя"])))
	var meshes: Array = []
	var box := AABB()
	for child in tree.get_children(true):
		if child is MeshInstance3D and (child as MeshInstance3D).mesh:
			var shown: MeshInstance3D = child
			# Матеріал Tree3D вішає на свій вузол, а не в сітку; вузол
			# викидаємо, тож кладемо матеріал у саму сітку — інакше дерево
			# біле (знімок 17.10.2026).
			var mesh: ArrayMesh = shown.mesh
			var paint: Material = shown.material_override
			if paint == null:
				paint = shown.get_surface_override_material(0)
			if paint != null:
				mesh.surface_set_material(0, paint)
			meshes.append(mesh)
			box = mesh.get_aabb() if box.size == Vector3.ZERO \
					else box.merge(mesh.get_aabb())
	tree.free()
	if meshes.size() != 2:
		push_warning("[дерева3д] «%s» дав %d сіток замість двох"
				% [kind, meshes.size()])
		return []
	var made := [meshes[0], meshes[1], box.end.y]
	_grown[key] = made
	return made


## Готовий вигляд дерева заданої висоти: Node3D з двома сітками.
## Матеріали — звичайні StandardMaterial3D; вітер на них накладає
## `Landscape._wind_up()`, як і на решту рослин.
static func view(kind: String, seed: int, tall: float) -> Node3D:
	var made := grown(kind, seed)
	if made.is_empty():
		return null
	var holder := Node3D.new()
	holder.name = "Tree3D"
	var by: float = tall / maxf(float(made[2]), 0.5)
	holder.scale = Vector3(by, by, by)
	for i in 2:
		var part := MeshInstance3D.new()
		part.name = "Стовбур" if i == 0 else "Гілочки"
		part.mesh = made[i]
		holder.add_child(part)
	return holder


static func _bark(name: String) -> StandardMaterial3D:
	var key := "кора:" + name
	if not _paints.has(key):
		var paint := StandardMaterial3D.new()
		paint.albedo_texture = load(HERE + name + ".jpg")
		paint.normal_enabled = true
		paint.normal_texture = load(HERE + name + "_n.jpg")
		paint.roughness = 0.95
		_paints[key] = paint
	return _paints[key]


static func _twig(name: String) -> StandardMaterial3D:
	var key := "листя:" + name
	if not _paints.has(key):
		var paint := StandardMaterial3D.new()
		paint.albedo_texture = load(HERE + name + ".png")
		paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		paint.alpha_scissor_threshold = 0.5
		paint.cull_mode = BaseMaterial3D.CULL_DISABLED
		paint.roughness = 1.0
		_paints[key] = paint
	return _paints[key]
