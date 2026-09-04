class_name Shrine
extends StaticBody3D
## Святиня (П-153) — точка, біля якої відкривають портал у підземелля.
##
## ТЕСТОВИЙ ВАРІАНТ: тут лише сама святиня та її три стани. Генерації
## підземель, ключів, лічильника днів і штрафів світу ще немає — план
## їхньої появи в `spec/dungeons.md`.
##
## Не плутати з «благодатним місцем» (`grace_place.gd`, П-113): те саме
## українське слово раніше позначало обидва об'єкти, розведено П-158.
## Портал — теж окрема сутність (`portal.gd`), а не частина святині:
## він з'являється ЛИШЕ після успішної активації ключем.
##
## Три стани, і кожен видно здалеку — саме за виглядом гравець і має
## розуміти, що тут робити:
##
##   ПІД_ОХОРОНОЮ  скупчення монстрів живе · у ґрунті довкола сині або
##                 червоні уламки-вкраплення (підказка близькості)
##   ЗАЧИЩЕНА      монстрів немає · уламки гаснуть, натомість вмикається
##                 вертикальний рунний напис — знак «можна активувати»
##   АКТИВОВАНА    ключ прийнято · поруч запалено портал
##
## Форма — НЕ спільна: обеліск, велике дерево, камінь, скеля, руїни
## (пряме слово замовника). Кожна форма береться з того, що вже лежить
## у репозиторії; обеліск і руїни складаються з деталей, бо готових
## моделей саме для них у наборах немає.

enum Stage { ПІД_ОХОРОНОЮ, ЗАЧИЩЕНА, АКТИВОВАНА }

## Форми з рішення. Ключ — те, що пишеться в даних мапи.
const FORMS := ["обеліск", "дерево", "камінь", "скеля", "руїни"]

const TREE_MODELS := [
	"res://models/nature/CommonTree_1.gltf",
	"res://models/nature/Pine_1.gltf",
]
const ROCK_MODELS := [
	"res://models/nature/Rock_Medium_1.gltf",
	"res://models/nature/Rock_Medium_2.gltf",
	"res://models/nature/Rock_Medium_3.gltf",
]
const WALL_MODEL := "res://models/village/Wall_UnevenBrick_Straight.gltf"
const FLOOR_MODEL := "res://models/village/Floor_Brick.gltf"
## Заміряні висоти моделей у наборах (ті самі числа, що в `landscape.gd`).
const TREE_MODEL_HEIGHT := 8.0
const ROCK_MODEL_HEIGHT := 2.3

## Скільки уламків розкидати довкола й на якому радіусі.
const SHARDS := 14
const SHARD_RING := 7.0
## Висота рунного напису над землею.
const RUNE_HEIGHT := 3.4
## Скільки рун у стовпці. Сам напис геометричний, не літерами: якої саме
## абетки хоче замовник — не сказано, а вигадувати її не можна.
const RUNE_MARKS := 5

@export var grade := "E"
@export var form := "камінь"
## Синій чи червоний. Замовник назвав обидва рівноправними, тож колір
## береться від святині, а не один на весь світ.
@export var shard_red := false

var stage: Stage = Stage.ПІД_ОХОРОНОЮ

var _shards: Node3D
var _runes: Node3D
var _glow: OmniLight3D


func _ready() -> void:
	collision_layer = 1
	build()


## Колір грейду беремо той самий, яким пофарбовані значки речей
## (`ItemIcon.GRADE_COLORS`) — гравець уже вивчив цю шкалу на речах, і
## друга шкала для того самого поняття тільки б заплутала.
func grade_color() -> Color:
	return ItemIcon.grade_color(grade)


func build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	var body := _figure()
	body.name = "Постать"
	add_child(body)

	# Світіння кольором грейду — видно здалеку й уночі, і саме воно
	# каже, який ключ потрібен.
	_glow = OmniLight3D.new()
	_glow.name = "Світіння"
	_glow.light_color = grade_color()
	_glow.light_energy = 2.4
	_glow.omni_range = 12.0
	_glow.position = Vector3(0, 2.0, 0)
	add_child(_glow)

	var block := CollisionShape3D.new()
	block.name = "Перепона"
	var shape := CylinderShape3D.new()
	shape.radius = 1.2
	shape.height = 4.0
	block.shape = shape
	block.position = Vector3(0, 2.0, 0)
	add_child(block)

	_shards = _shard_ring()
	_shards.name = "Уламки"
	add_child(_shards)

	_runes = _rune_column()
	_runes.name = "Руни"
	add_child(_runes)

	_show_stage()


## Перевести в інший стан. Один вхід, щоб вигляд не розходився зі станом:
## саме на такому розходженні вже горіли інші вікна проєкту.
func set_stage(to: Stage) -> void:
	stage = to
	_show_stage()


func _show_stage() -> void:
	if _shards != null:
		# Уламки — підказка ДО зачистки; після неї гаснуть.
		_shards.visible = stage == Stage.ПІД_ОХОРОНОЮ
	if _runes != null:
		# Рунний напис — знак «можна активувати», тобто вже зачищено.
		_runes.visible = stage != Stage.ПІД_ОХОРОНОЮ
	if _glow != null:
		_glow.light_energy = 2.4 if stage == Stage.ПІД_ОХОРОНОЮ else 4.2


## Сама постать святині за формою.
func _figure() -> Node3D:
	match form:
		"дерево":
			return _from_model(TREE_MODELS, TREE_MODEL_HEIGHT, 11.0)
		"камінь":
			return _from_model(ROCK_MODELS, ROCK_MODEL_HEIGHT, 3.2)
		"скеля":
			return _from_model(ROCK_MODELS, ROCK_MODEL_HEIGHT, 7.5)
		"руїни":
			return _ruins()
		_:
			return _obelisk()


## Готова модель, підігнана під потрібну висоту — той самий прийом, що
## й у гір (`landscape.gd:_mountains`), разом із запасним примітивом
## (П-15), якщо набору на диску немає.
func _from_model(models: Array, made_height: float,
		want_height: float) -> Node3D:
	var holder := Node3D.new()
	var path: String = models[randi() % models.size()]
	if ResourceLoader.exists(path):
		var view: Node3D = (load(path) as PackedScene).instantiate()
		var scale := want_height / made_height
		view.scale = Vector3(scale, scale, scale)
		view.rotation.y = randf() * TAU
		holder.add_child(view)
		return holder
	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = want_height * 0.12
	cylinder.bottom_radius = want_height * 0.3
	cylinder.height = want_height
	mesh.mesh = cylinder
	mesh.position = Vector3(0, want_height * 0.5, 0)
	holder.add_child(mesh)
	return holder


## Обеліск: готової моделі в наборах немає, тож складаємо з примітивів —
## чотиригранний стовп зі зрізаною вершиною, як справжні обеліски.
func _obelisk() -> Node3D:
	var holder := Node3D.new()
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.34, 0.33, 0.36)
	stone.roughness = 0.85

	var shaft := MeshInstance3D.new()
	var body := BoxMesh.new()
	body.size = Vector3(1.0, 6.0, 1.0)
	shaft.mesh = body
	shaft.position = Vector3(0, 3.0, 0)
	shaft.set_surface_override_material(0, stone)
	holder.add_child(shaft)

	var tip := MeshInstance3D.new()
	var top := CylinderMesh.new()
	top.top_radius = 0.0
	top.bottom_radius = 0.72
	top.height = 1.1
	top.radial_segments = 4
	tip.mesh = top
	tip.position = Vector3(0, 6.55, 0)
	tip.rotation.y = PI * 0.25
	tip.set_surface_override_material(0, stone)
	holder.add_child(tip)

	var base := MeshInstance3D.new()
	var plate := BoxMesh.new()
	plate.size = Vector3(2.0, 0.5, 2.0)
	base.mesh = plate
	base.position = Vector3(0, 0.25, 0)
	base.set_surface_override_material(0, stone)
	holder.add_child(base)
	return holder


## Руїни: чотири уламки стін по колу, різної висоти й повороту. Стіни
## беремо ті самі, що й у будинках міста, — набір один.
func _ruins() -> Node3D:
	var holder := Node3D.new()
	var heights := [0.45, 0.8, 0.3, 0.65]
	for i in 4:
		var turn := TAU * float(i) / 4.0 + 0.3
		var at := Vector3(cos(turn), 0.0, sin(turn)) * 2.6
		var piece: Node3D
		if ResourceLoader.exists(WALL_MODEL):
			piece = (load(WALL_MODEL) as PackedScene).instantiate()
			# Обрізаємо по висоті масштабом: справжнього ламаного краю
			# в наборі немає, а натяк на висоту руїни дає вже це.
			piece.scale = Vector3(1.0, float(heights[i]), 1.0)
		else:
			piece = MeshInstance3D.new()
			var block := BoxMesh.new()
			block.size = Vector3(2.0, float(heights[i]) * 3.0, 0.3)
			piece.mesh = block
		piece.position = at
		piece.rotation.y = -turn
		holder.add_child(piece)
	if ResourceLoader.exists(FLOOR_MODEL):
		var floor_piece: Node3D = \
				(load(FLOOR_MODEL) as PackedScene).instantiate()
		floor_piece.position = Vector3(0, 0.02, 0)
		holder.add_child(floor_piece)
	return holder


## Уламки-вкраплення в ґрунті: підказка, що святиня поруч (П-153).
## Суто візуальні, без механіки — так і сказано в рішенні.
func _shard_ring() -> Node3D:
	var holder := Node3D.new()
	var vein := StandardMaterial3D.new()
	var tone := Color(0.86, 0.18, 0.32) if shard_red \
			else Color(0.42, 0.30, 0.88)
	vein.albedo_color = tone
	vein.emission_enabled = true
	vein.emission = tone
	vein.emission_energy_multiplier = 1.6
	vein.roughness = 0.25

	for i in SHARDS:
		var turn := TAU * float(i) / float(SHARDS) + randf() * 0.4
		var far := SHARD_RING * (0.55 + randf() * 0.75)
		var shard := MeshInstance3D.new()
		var stone := BoxMesh.new()
		var tall := 0.18 + randf() * 0.5
		stone.size = Vector3(0.22 + randf() * 0.2, tall,
				0.22 + randf() * 0.2)
		shard.mesh = stone
		shard.set_surface_override_material(0, vein)
		# Трохи втоплені в землю й нахилені: вкраплення в ґрунті, а не
		# розставлені стовпчики.
		shard.position = Vector3(cos(turn) * far, tall * 0.28,
				sin(turn) * far)
		shard.rotation = Vector3(randf_range(-0.4, 0.4),
				randf() * TAU, randf_range(-0.4, 0.4))
		holder.add_child(shard)
	return holder


## Вертикальний рунний напис — вмикається ПІСЛЯ зачистки.
##
## Навмисно геометричний, не літерами: якої абетки хоче замовник — не
## сказано, а вигадана абетка потім розповзеться по всій грі. Тут стовп
## із засічок кольору грейду; замінити на справжні знаки — одне місце.
func _rune_column() -> Node3D:
	var holder := Node3D.new()
	var glyph := StandardMaterial3D.new()
	glyph.albedo_color = grade_color()
	glyph.emission_enabled = true
	glyph.emission = grade_color()
	glyph.emission_energy_multiplier = 3.0
	# Напис читається з будь-якого боку й не гасне в тіні.
	glyph.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	for i in RUNE_MARKS:
		var mark := MeshInstance3D.new()
		var bar := BoxMesh.new()
		var wide := 0.5 if i % 2 == 0 else 0.32
		bar.size = Vector3(wide, 0.1, 0.06)
		mark.mesh = bar
		mark.set_surface_override_material(0, glyph)
		mark.position = Vector3(0, 1.1 + float(i) * (RUNE_HEIGHT / RUNE_MARKS),
				1.05)
		holder.add_child(mark)

		var tick := MeshInstance3D.new()
		var stroke := BoxMesh.new()
		stroke.size = Vector3(0.08, 0.34, 0.06)
		tick.mesh = stroke
		tick.set_surface_override_material(0, glyph)
		tick.position = Vector3(wide * 0.35 if i % 2 == 0 else -wide * 0.35,
				1.1 + float(i) * (RUNE_HEIGHT / RUNE_MARKS) + 0.16, 1.05)
		holder.add_child(tick)
	return holder
