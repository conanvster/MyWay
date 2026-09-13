class_name Portal
extends Area3D
## Портал у підземелля (П-153) — «старовинне коло з рунними написами по
## колу», словами замовника.
##
## Тут коло, написи й визначення «гравець усередині». Сам перехід — у
## `world.gd:enter_dungeon`, запрошення — у `client_view.gd:_watch_portals`
## (П-190, 13.09.2026). Той самий вузол стоїть і в підземеллі як «Вихід».
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
	glow.emission_energy_multiplier = 4.0
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Саме коло. Товще, ніж було (0,16 м): тонке з камери гри губилось
	# (замовник 13.09.2026 «портала візуально не побачив»).
	var ring := MeshInstance3D.new()
	ring.name = "Коло"
	var band := TorusMesh.new()
	band.inner_radius = RING - 0.3
	band.outer_radius = RING
	band.rings = 64
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

	# Вир у колі — видно, що в коло треба ЗАЙТИ.
	var shine := ShaderMaterial.new()
	shine.shader = SHADER
	shine.set_shader_parameter("tone", tone)
	shine.set_shader_parameter("power", 2.2)
	shine.set_shader_parameter("swirl", true)
	shine.set_shader_parameter("radius", RING)
	var disc := MeshInstance3D.new()
	disc.name = "Вир"
	var flat := PlaneMesh.new()
	flat.size = Vector2(RING * 2.0, RING * 2.0)
	disc.mesh = flat
	disc.material_override = shine
	disc.position = Vector3(0, LIFT + 0.02, 0)
	add_child(disc)

	# Стовп світла — видно здалеку, з-за дерев і з камери згори.
	var column := ShaderMaterial.new()
	column.shader = SHADER
	column.set_shader_parameter("tone", tone)
	column.set_shader_parameter("power", 1.8)
	column.set_shader_parameter("swirl", false)
	column.set_shader_parameter("height", BEAM_HEIGHT)
	var pillar := MeshInstance3D.new()
	pillar.name = "Стовп"
	var tube := CylinderMesh.new()
	tube.top_radius = RING * 0.55
	tube.bottom_radius = RING * 0.95
	tube.height = BEAM_HEIGHT
	tube.cap_top = false
	tube.cap_bottom = false
	tube.radial_segments = 32
	pillar.mesh = tube
	pillar.material_override = column
	pillar.position = Vector3(0, BEAM_HEIGHT * 0.5, 0)
	add_child(pillar)

	add_child(_sparks(tone))

	var beam := OmniLight3D.new()
	beam.name = "Сяйво"
	beam.light_color = tone
	beam.light_energy = 4.5
	beam.omni_range = 13.0
	beam.position = Vector3(0, 1.4, 0)
	add_child(beam)
	if DisplayServer.get_name() != "headless":
		var breath := beam.create_tween().set_loops()
		breath.tween_property(beam, "light_energy", 6.0, 1.1) \
				.set_trans(Tween.TRANS_SINE)
		breath.tween_property(beam, "light_energy", 3.5, 1.1) \
				.set_trans(Tween.TRANS_SINE)


const SHADER := preload("res://scripts/portal.gdshader")
const BEAM_HEIGHT := 7.0


## Іскри, що здіймаються з кола.
func _sparks(tone: Color) -> GPUParticles3D:
	var sparks := GPUParticles3D.new()
	sparks.name = "Іскри"
	sparks.amount = 48
	sparks.lifetime = 2.6
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	motion.emission_ring_axis = Vector3.UP
	motion.emission_ring_radius = RING - 0.15
	motion.emission_ring_inner_radius = RING * 0.3
	motion.emission_ring_height = 0.1
	motion.direction = Vector3.UP
	motion.spread = 10.0
	motion.initial_velocity_min = 0.6
	motion.initial_velocity_max = 1.7
	motion.gravity = Vector3(0, 0.3, 0)
	motion.scale_min = 0.5
	motion.scale_max = 1.3
	sparks.process_material = motion
	var dot := QuadMesh.new()
	dot.size = Vector2(0.1, 0.1)
	var paint := StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	paint.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	paint.albedo_color = tone * 2.0
	dot.material = paint
	sparks.draw_pass_1 = dot
	sparks.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 10, 8))
	return sparks


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
