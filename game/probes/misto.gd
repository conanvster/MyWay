extends SceneTree
## Текстури міст і сіл (CC0, `tools/mista_aseti.py`) — на справжніх
## формах, щоб вибирати очима, а не з кульок на аркуші.
##
## Слово замовника 17.10.2026: «пошукай гарні текстури для будинків,
## парканів та іншого щоб зібрати міста та села як це зображено на мапі».
## На мапі місто — мур із баштами й брамою, донжон, бруківка; село — хати
## під стріхою. Тут по одному зразку кожного:
##   - сільська хата: модулі Quaternius, мазанка + стріха;
##   - міський дім: біла штукатурка з фахверком + черепиця;
##   - цегляний дім + сланцевий дах;
##   - ланка муру з баштою й брамою, донжон;
##   - речі двору: бочка, ящики, відро, стіл, ослін, вогнище, ліхтар;
##   - тин і паркан з дощок.
##
## Ганяти так:
##     ./run.sh --місто     вікно, знімки в user://
##
## Модулі Quaternius мають свої мультяшні текстури; тут вони підмінені
## фото за назвою матеріалу (MI_Plaster → штукатурка тощо), трипланарно
## у світових координатах — UV модулів для фото не годяться.
##
## Esc — вийти.

const TOWN := "res://models/town/"
const WALL := "res://models/village/Wall_%s.gltf"
const MODULE := 2.0
const WALL_HEIGHT := 3.12

var _shots := [
	["загальний", Vector3(4, 14, 38), Vector3(4, 2, 0)],
	["село", Vector3(-17, 3, 12), Vector3(-14, 2, 0)],
	["місто", Vector3(2, 4, 13), Vector3(2, 2.5, 0)],
	["мур і брама", Vector3(26, 5, 18), Vector3(26, 4, -2)],
	["двір", Vector3(-10, 2.2, 0.5), Vector3(-6, 0.4, 3.6)],
]
var _clock := 0.0
var _next := 0
var _eye: Camera3D
var _page: Node3D
var _paints := {}


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(1600, 1000)
	_page = Node3D.new()
	root.add_child(_page)
	_stage()
	# Село: хата 3×2, мазанка, стріха.
	_house(Vector3(-14, 0, 0), 3, 2, {"MI_Plaster": "clay_plaster",
			"MI_WoodTrim": "dark_wooden_planks",
			"MI_RoundTiles": "thatch_roof_angled"}, false)
	_house(Vector3(-22, 0, -2), 2, 2, {"MI_Plaster": "worn_mossy_plasterwall",
			"MI_WoodTrim": "weathered_planks",
			"MI_RoundTiles": "reed_roof_04"}, false)
	_wattle(Vector3(-19, 0, 5), 10.0)
	# Місто: фахверк під черепицею й цегляний під сланцем.
	_house(Vector3(-2, 0, 0), 2, 3, {"MI_Plaster": "plastered_wall_02",
			"MI_WoodTrim": "dark_wooden_planks",
			"MI_RoundTiles": "clay_roof_tiles_02"}, true)
	_house(Vector3(6, 0, 0), 3, 2, {"MI_UnevenBrick": "medieval_red_brick",
			"MI_Plaster": "plastered_wall_02",
			"MI_WoodTrim": "dark_wooden_planks",
			"MI_RoundTiles": "roof_slates_03"}, false, true)
	_planks_fence(Vector3(-6, 0, 5.5), 8.0)
	_yard(Vector3(-6, 0, 3.5))
	# Мур, башта, брама, донжон.
	_wall(Vector3(18, 0, -2), 8.0)
	_tower(Vector3(23.5, 0, -2))
	_gate(Vector3(28.5, 0, -2))
	_tower(Vector3(33.5, 0, -2))
	_wall(Vector3(39, 0, -2), 8.0)
	_keep(Vector3(28, 0, -18))
	_eye = Camera3D.new()
	_page.add_child(_eye)
	_aim(0)


func _process(delta: float) -> bool:
	_clock += delta
	if _eye != null and _clock > 2.0:
		_clock = 0.0
		Shot.take(_page)
		print("[місто] знімок: %s" % _shots[_next][0])
		_next += 1
		if _next >= _shots.size():
			quit()
		else:
			_aim(_next)
	if Input.is_key_pressed(KEY_ESCAPE):
		quit()
	return false


func _aim(i: int) -> void:
	_eye.look_at_from_position(_shots[i][1], _shots[i][2])


## Фото-матеріал: трипланарно у світових координатах, `size` — метрів
## на повтор. ORM — це `arm` Poly Haven (AO, шорсткість, метал).
func _paint(name: String, size: float = 2.5) -> ORMMaterial3D:
	var key := "%s:%.1f" % [name, size]
	if not _paints.has(key):
		var paint := ORMMaterial3D.new()
		paint.albedo_texture = load(TOWN + name + "_diff.jpg")
		paint.normal_enabled = true
		paint.normal_texture = load(TOWN + name + "_nor_gl.jpg")
		paint.orm_texture = load(TOWN + name + "_arm.jpg")
		paint.uv1_triplanar = true
		paint.uv1_world_triplanar = true
		paint.uv1_scale = Vector3.ONE / size
		_paints[key] = paint
	return _paints[key]


func _stage() -> void:
	var air := WorldEnvironment.new()
	var sky := Environment.new()
	sky.background_mode = Environment.BG_SKY
	var made := Sky.new()
	made.sky_material = ProceduralSkyMaterial.new()
	sky.sky = made
	sky.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	sky.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	sky.ssao_enabled = true
	air.environment = sky
	_page.add_child(air)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 35, 0)
	sun.shadow_enabled = true
	_page.add_child(sun)
	# Бруківка вулиці міста й ґрунт під селом.
	_slab(Vector3(8, -0.05, 2), Vector3(44, 0.1, 22), "cobblestone_floor_08", 2.0)
	_slab(Vector3(-18, -0.04, 2), Vector3(14, 0.1, 22), "clay_plaster", 4.0)
	_slab(Vector3(28, -0.03, -18), Vector3(18, 0.1, 18), "stone_pathway_02", 3.0)


func _slab(at: Vector3, size: Vector3, paint: String, tile: float) -> void:
	var view := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	view.mesh = box
	view.material_override = _paint(paint, tile)
	view.position = at
	_page.add_child(view)


## Будинок із модулів Quaternius, як `Landscape._kit_house`, але з
## підміною матеріалів. `grid` — фахверк замість частини глухих стін.
func _house(at: Vector3, wide: int, deep: int, swap: Dictionary,
		grid: bool, brick: bool = false) -> void:
	var holder := Node3D.new()
	holder.position = at
	_page.add_child(holder)
	var kind := "UnevenBrick" if brick else "Plaster"
	var straight := WALL % (kind + "_Straight")
	var window := WALL % (kind + "_Window_Wide_Round")
	var door := WALL % "Plaster_Door_Round"
	var timber := WALL % "Plaster_WoodGrid"
	var half_x := (wide - 1) * MODULE * 0.5
	var half_z := (deep - 1) * MODULE * 0.5
	for i in wide:
		var x := -half_x + i * MODULE
		_piece(holder, door if i == wide / 2 else window,
				Vector3(x, 0, deep * MODULE * 0.5), 0.0)
		_piece(holder, timber if grid else straight,
				Vector3(x, 0, -deep * MODULE * 0.5), 180.0)
	for i in deep:
		var z := -half_z + i * MODULE
		_piece(holder, timber if grid and i % 2 == 0 else window,
				Vector3(-wide * MODULE * 0.5, 0, z), 270.0)
		_piece(holder, straight, Vector3(wide * MODULE * 0.5, 0, z), 90.0)
	for ix in range(0, wide, 2):
		for iz in range(0, deep, 2):
			_piece(holder, "res://models/village/Roof_RoundTiles_4x4.gltf",
					Vector3(-half_x + (ix + minf(1, wide - ix - 1)) * MODULE
					* 0.5, WALL_HEIGHT + 0.5, -half_z + (iz + minf(1,
					deep - iz - 1)) * MODULE * 0.5), 0.0)
	_piece(holder, "res://models/village/Prop_Chimney.gltf",
			Vector3(half_x * 0.6, WALL_HEIGHT + 1.2, 0), 0.0)
	for child in holder.find_children("*", "MeshInstance3D", true, false):
		var view: MeshInstance3D = child
		for s in view.mesh.get_surface_count():
			var was: Material = view.mesh.surface_get_material(s)
			var name := was.resource_name if was != null else ""
			if swap.has(name):
				var tile := 3.0 if name == "MI_RoundTiles" else 2.0
				view.set_surface_override_material(s,
						_paint(swap[name], tile))


func _piece(parent: Node3D, path: String, at: Vector3, turn: float) -> void:
	if not ResourceLoader.exists(path):
		print("[місто] ‼ нема %s" % path)
		return
	var part: Node3D = (load(path) as PackedScene).instantiate()
	part.position = at
	part.rotation.y = deg_to_rad(turn)
	parent.add_child(part)


func _block(at: Vector3, size: Vector3, paint: String, tile: float) -> void:
	_slab(at + Vector3(0, size.y * 0.5, 0), size, paint, tile)


## Ланка муру з зубцями. Мур на мапі — суцільна лінія, тут 6 м заввишки.
func _wall(at: Vector3, long: float) -> void:
	_block(at, Vector3(long, 6.0, 1.6), "castle_wall_varriation", 3.0)
	var n := int(long / 1.6)
	for i in n:
		if i % 2 == 0:
			_block(at + Vector3(-long * 0.5 + 0.8 + i * 1.6, 6.0, 0.55),
					Vector3(0.9, 0.9, 0.5), "castle_wall_varriation", 3.0)


## Кругла башта по куту муру, з конусом сланцю.
func _tower(at: Vector3) -> void:
	var view := MeshInstance3D.new()
	var round := CylinderMesh.new()
	round.top_radius = 2.6
	round.bottom_radius = 2.9
	round.height = 10.0
	view.mesh = round
	view.material_override = _paint("castle_brick_07", 2.5)
	view.position = at + Vector3(0, 5, 0)
	_page.add_child(view)
	var cap := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 3.3
	cone.height = 4.0
	cap.mesh = cone
	cap.material_override = _paint("roof_slates_03", 2.0)
	cap.position = at + Vector3(0, 12, 0)
	_page.add_child(cap)


## Брама: два стовпи й перемичка, прохід 4 м — дорога заходить сюди.
func _gate(at: Vector3) -> void:
	_block(at + Vector3(-2.6, 0, 0), Vector3(1.2, 7.5, 2.4), "castle_brick_07", 2.5)
	_block(at + Vector3(2.6, 0, 0), Vector3(1.2, 7.5, 2.4), "castle_brick_07", 2.5)
	_block(at + Vector3(0, 5.2, 0), Vector3(6.4, 2.3, 2.4), "castle_brick_07", 2.5)
	_block(at + Vector3(0, -0.04, 0), Vector3(4.0, 0.08, 2.4), "brown_planks_05", 2.0)


## Донжон у центрі міста: квадратна вежа з зубцями.
func _keep(at: Vector3) -> void:
	_block(at, Vector3(10, 16, 10), "medieval_blocks_03", 3.5)
	for i in 5:
		for side: Vector3 in [Vector3(1, 0, 0), Vector3(0, 0, 1)]:
			var along := -4.0 + i * 2.0
			var off := Vector3(along, 16, 4.6) if side.x > 0 \
					else Vector3(4.6, 16, along)
			_block(at + off, Vector3(1, 1.1, 0.8) if side.x > 0
					else Vector3(0.8, 1.1, 1), "medieval_blocks_03", 3.5)


## Тин села: кілки й поперечки з обвітрених дощок.
func _wattle(at: Vector3, long: float) -> void:
	for i in int(long / 1.2) + 1:
		_block(at + Vector3(-long * 0.5 + i * 1.2, 0, 0),
				Vector3(0.12, 1.3, 0.12), "weathered_planks", 1.5)
	for h in [0.45, 0.95]:
		_block(at + Vector3(0, h, 0), Vector3(long, 0.14, 0.08),
				"weathered_planks", 1.5)


## Паркан з дощок у місті: дошка до дошки.
func _planks_fence(at: Vector3, long: float) -> void:
	_block(at, Vector3(long, 1.6, 0.06), "weathered_planks", 1.2)
	for i in int(long / 2.0) + 1:
		_block(at + Vector3(-long * 0.5 + i * 2.0, 0, 0.08),
				Vector3(0.14, 1.75, 0.14), "dark_wooden_planks", 1.2)


## Речі двору з Poly Haven.
func _yard(at: Vector3) -> void:
	var things := [
		["wine_barrel_01", Vector3(-3, 0, 0), 0.0],
		["wooden_crate_01", Vector3(-2, 0, -0.5), 20.0],
		["wooden_crate_02", Vector3(-2.2, 0, 0.6), -10.0],
		["wooden_bucket_01", Vector3(-0.8, 0, 0.6), 0.0],
		["wooden_picnic_table", Vector3(1.0, 0, 0), 90.0],
		["wooden_stool_01", Vector3(2.4, 0, 0.6), 0.0],
		["stone_fire_pit", Vector3(4.0, 0, 0.3), 0.0],
		["wooden_lantern_01", Vector3(1.0, 0.75, 0), 0.0],
		["wooden_ladder", Vector3(-4.5, 0, -1.2), 0.0],
		["spinning_wheel_01", Vector3(3.2, 0, -0.9), 30.0],
	]
	for one: Array in things:
		var path := TOWN + "rechi/%s/%s_1k.gltf" % [one[0], one[0]]
		if not ResourceLoader.exists(path):
			print("[місто] ‼ нема %s" % path)
			continue
		var made: Node3D = (load(path) as PackedScene).instantiate()
		made.position = at + one[1]
		made.rotation.y = deg_to_rad(one[2])
		_page.add_child(made)
