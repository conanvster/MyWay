class_name Fx
extends Node3D
## Ефекти бою на клієнті: підсвічування касту й прості частинки (П-33,
## погоджено 01.09.2026; що саме показувати — П-272).
##
## Суто вигляд. Сервер нічого про це не знає й нічого не перевіряє: ефект
## запускається з тих самих повідомлень, що й раніше (`client_cast`,
## `client_cast_end`, `client_damage`, `client_died`), плюс одне нове —
## `client_skill` (хто, який скіл, кого зачепило), бо миттєві скіли досі
## не слали клієнтові нічого, крім числа шкоди.
##
## Що показується:
##   каст      — коло під ногами кольором скіла, світло, що росте до кінця
##               читання, і частинки, що стягуються до кастера;
##   скіл      — на одну ціль летить згусток зі слідом; «усі-поруч» — хвиля
##               від кастера; баф/лік — частинки здіймаються довкола цілі;
##   удар      — іскри й короткий спалах на тілі цілі;
##   смерть    — пил під тілом (труп лишається за П-68).
##
## Колір — за родом скіла, не за стихією: у `skills.json` поле «стихія»
## порожнє в усіх 192 скілів (06.11.2026). З'явиться стихія — колір
## братиметься з неї (`TONE_OF_ELEMENT`).
##
## Вузли ефектів короткі й самі себе прибирають таймером. Одночасно живих —
## не більше `MAX_LIVE`: на масовій бійці зайве просто не з'являється.

const MAX_LIVE := 96

const TONE_HIT := Color(1.0, 0.78, 0.45)
const TONE_ATTACK := Color(0.55, 0.45, 1.0)
const TONE_BUFF := Color(1.0, 0.82, 0.35)
const TONE_HEAL := Color(0.4, 1.0, 0.55)
const TONE_CURSE := Color(0.85, 0.3, 0.7)
const TONE_DUST := Color(0.45, 0.4, 0.33)
const TONE_OF_ELEMENT := {
	"вогонь": Color(1.0, 0.45, 0.15),
	"вода": Color(0.35, 0.65, 1.0),
	"вітер": Color(0.75, 1.0, 0.85),
	"земля": Color(0.7, 0.55, 0.3),
	"блискавка": Color(0.7, 0.85, 1.0),
	"темрява": Color(0.6, 0.25, 0.8),
	"світло": Color(1.0, 0.95, 0.7),
}

## Скільки секунд після ефекту скіла на цілі звичайні іскри удару не
## показуються: число шкоди від скіла приходить слідом за `client_skill`,
## і без цього на цілі спалахувало б двічі.
const SKILL_SHADOW := 0.25
const BOLT_TIME := 0.28

var creatures: Dictionary = {}
var skills: SkillBook = null

var _live := 0
var _casts: Dictionary = {}       # id → {"nodes": [...], "light": OmniLight3D}
var _skill_mark: Dictionary = {}  # id → коли на ньому був ефект скіла (с)
var _by_name: Dictionary = {}     # назва скіла → Skill (client_cast шле назву)
var _quiet := false


func _ready() -> void:
	name = "Ефекти"
	_quiet = DisplayServer.get_name() == "headless"


# ─── каст ─────────────────────────────────────────────────────────────

## Хтось почав читати. `skill_name` — назва, як шле сервер (`skill.name`).
func cast_start(id: int, skill_name: String, seconds: float) -> void:
	cast_end(id, false)
	var who := _body(id)
	if who == null or _quiet:
		return
	var tone := tone_of(_skill_named(skill_name))
	var nodes: Array = []

	var ring := _ring_mesh(tone, 0.75, 0.05)
	who.add_child(ring)
	ring.position.y = 0.04 - _feet(who)
	ring.scale = Vector3.ONE * 0.4
	var grow := ring.create_tween()
	grow.tween_property(ring, "scale", Vector3.ONE, minf(0.35, seconds))
	var spin := ring.create_tween().set_loops()
	spin.tween_property(ring, "rotation:y", TAU, 2.4).as_relative()
	nodes.append(ring)

	var glow := OmniLight3D.new()
	glow.light_color = tone
	glow.light_energy = 0.0
	glow.omni_range = 3.5
	glow.shadow_enabled = false
	who.add_child(glow)
	glow.position.y = _chest(who)
	var rise := glow.create_tween()
	rise.tween_property(glow, "light_energy", 2.2, maxf(0.1, seconds)) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	nodes.append(glow)

	var motes := _particles(tone, 48, 0.9, 0.1)
	var motion := motes.process_material as ParticleProcessMaterial
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	motion.emission_ring_axis = Vector3.UP
	motion.emission_ring_radius = 1.1
	motion.emission_ring_inner_radius = 0.8
	motion.emission_ring_height = 0.1
	motion.direction = Vector3.UP
	motion.spread = 5.0
	motion.initial_velocity_min = 0.8
	motion.initial_velocity_max = 1.4
	motion.radial_accel_min = -2.2
	motion.radial_accel_max = -1.6
	motion.gravity = Vector3.ZERO
	motes.local_coords = true
	who.add_child(motes)
	motes.position.y = 0.1 - _feet(who)
	nodes.append(motes)

	_live += nodes.size()
	_casts[id] = {"nodes": nodes, "tone": tone}


## Дочитав (`done`) або збили. Дочитав — короткий спалах на кастері.
func cast_end(id: int, done: bool) -> void:
	var row: Dictionary = _casts.get(id, {})
	if row.is_empty():
		return
	_casts.erase(id)
	for node: Node in row["nodes"]:
		if is_instance_valid(node):
			node.get_parent().remove_child(node)
			node.queue_free()
		_live -= 1
	if done and not _quiet:
		var who := _body(id)
		if who != null:
			_burst(who.global_position + Vector3.UP * _chest(who),
					row["tone"], 18, 2.2)


# ─── скіл спрацював ──────────────────────────────────────────────────

## Скіл застосовано: `key` — ключ скіла, `victims` — номери зачеплених.
func skill_landed(id: int, key: String, victims: Array) -> void:
	var now := _now()
	for v in victims:
		_skill_mark[int(v)] = now
	if _quiet:
		return
	var skill: Skill = skills.get_skill(key) if skills != null else null
	var tone := tone_of(skill)
	var caster := _body(id)
	var target := "" if skill == null else skill.target
	var harms := skill != null and _harms(skill)

	if target == "усі-поруч" and caster != null:
		_wave(caster, tone, skill.range_at(1) if skill != null else 4.0)
	for v in victims:
		var who := _body(int(v))
		if who == null:
			continue
		if harms and target == "жива" and caster != null and who != caster:
			_bolt(caster, who, tone)
		elif harms:
			_burst(who.global_position + Vector3.UP * _chest(who),
					tone, 20, 3.0)
			_flash(who, tone)
		else:
			_aura(who, tone)


# ─── удар і смерть ───────────────────────────────────────────────────

## Прийшло число шкоди. Іскри — лише якщо це не наслідок скіла, що вже
## показав свій ефект (`SKILL_SHADOW`).
func hit(id: int, amount: int, behind: bool) -> void:
	if _quiet or amount <= 0:
		return
	if _now() - float(_skill_mark.get(id, -10.0)) < SKILL_SHADOW:
		return
	var who := _body(id)
	if who == null:
		return
	var tone := Color(1.0, 0.5, 0.3) if behind else TONE_HIT
	_burst(who.global_position + Vector3.UP * _chest(who), tone,
			22 if behind else 14, 7.0)
	_flash(who, Color(1, 1, 1))


func death(id: int) -> void:
	cast_end(id, false)
	if _quiet:
		return
	var who := _body(id)
	if who == null:
		return
	var dust := _particles(TONE_DUST, 32, 1.3, 0.45, false)
	var motion := dust.process_material as ParticleProcessMaterial
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	motion.emission_ring_axis = Vector3.UP
	motion.emission_ring_radius = 0.6
	motion.emission_ring_inner_radius = 0.1
	motion.emission_ring_height = 0.05
	motion.direction = Vector3(0, 0.3, 0)
	motion.spread = 80.0
	motion.initial_velocity_min = 0.6
	motion.initial_velocity_max = 1.6
	motion.damping_min = 1.5
	motion.damping_max = 2.5
	motion.gravity = Vector3(0, 0.15, 0)
	_one_shot(dust, who.global_position + Vector3.UP * (0.05 - _feet(who)))


# ─── колір ───────────────────────────────────────────────────────────

static func tone_of(skill: Skill) -> Color:
	if skill == null:
		return TONE_ATTACK
	if TONE_OF_ELEMENT.has(skill.element):
		return TONE_OF_ELEMENT[skill.element]
	if skill.heals():
		return TONE_HEAL
	if _harms(skill):
		return TONE_ATTACK
	if skill.target == "жива":
		return TONE_CURSE
	return TONE_BUFF


static func _harms(skill: Skill) -> bool:
	for row: Dictionary in skill.levels:
		if float(row.get("шкода", 0.0)) > 0.0:
			return true
	return false


# ─── будівельні цеглинки ─────────────────────────────────────────────

func _bolt(from: Node3D, to: Node3D, tone: Color) -> void:
	if _live >= MAX_LIVE:
		return
	var start := from.global_position + Vector3.UP * _chest(from)
	var bolt := Node3D.new()
	add_child(bolt)
	bolt.global_position = start
	_live += 1
	var core := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.13
	ball.height = 0.26
	ball.radial_segments = 12
	ball.rings = 6
	core.mesh = ball
	core.material_override = _glow_paint(tone, 3.0)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bolt.add_child(core)
	var lamp := OmniLight3D.new()
	lamp.light_color = tone
	lamp.light_energy = 1.6
	lamp.omni_range = 3.0
	bolt.add_child(lamp)
	var trail := _particles(tone, 40, 0.35, 0.09)
	var motion := trail.process_material as ParticleProcessMaterial
	motion.initial_velocity_min = 0.0
	motion.initial_velocity_max = 0.3
	motion.spread = 180.0
	motion.gravity = Vector3.ZERO
	motion.scale_curve = _fade_curve()
	trail.local_coords = false
	bolt.add_child(trail)
	var fly := bolt.create_tween()
	# Ціль може йти — летимо туди, де вона буде на кінці польоту.
	fly.tween_method(func(t: float) -> void:
		if is_instance_valid(to) and is_instance_valid(bolt):
			var end := to.global_position + Vector3.UP * _chest(to)
			bolt.global_position = start.lerp(end, t), 0.0, 1.0, BOLT_TIME)
	fly.tween_callback(func() -> void:
		if is_instance_valid(to):
			_burst(to.global_position + Vector3.UP * _chest(to), tone, 22, 3.2)
			_flash(to, tone)
		trail.emitting = false
		core.visible = false
		lamp.visible = false)
	fly.tween_interval(0.5)
	fly.tween_callback(func() -> void:
		_live -= 1
		bolt.queue_free())


func _wave(caster: Node3D, tone: Color, reach: float) -> void:
	if _live >= MAX_LIVE:
		return
	var ring := _ring_mesh(tone, 1.0, 0.035)
	add_child(ring)
	ring.global_position = caster.global_position \
			+ Vector3.UP * (0.15 - _feet(caster))
	ring.scale = Vector3.ONE * 0.3
	_live += 1
	var paint := ring.material_override as StandardMaterial3D
	var go := ring.create_tween().set_parallel()
	go.tween_property(ring, "scale", Vector3.ONE * maxf(1.0, reach), 0.45) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	go.tween_property(paint, "albedo_color:a", 0.0, 0.45)
	go.chain().tween_callback(func() -> void:
		_live -= 1
		ring.queue_free())
	var flash := OmniLight3D.new()
	flash.light_color = tone
	flash.light_energy = 3.0
	flash.omni_range = maxf(3.0, reach * 1.3)
	add_child(flash)
	flash.global_position = caster.global_position + Vector3.UP * 1.0
	var dim := flash.create_tween()
	dim.tween_property(flash, "light_energy", 0.0, 0.4)
	dim.tween_callback(flash.queue_free)


func _aura(who: Node3D, tone: Color) -> void:
	var motes := _particles(tone, 48, 1.3, 0.16)
	var motion := motes.process_material as ParticleProcessMaterial
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	motion.emission_ring_axis = Vector3.UP
	motion.emission_ring_radius = 0.7
	motion.emission_ring_inner_radius = 0.5
	motion.emission_ring_height = 0.2
	motion.direction = Vector3.UP
	motion.spread = 8.0
	motion.initial_velocity_min = 1.0
	motion.initial_velocity_max = 2.0
	motion.gravity = Vector3.ZERO
	motion.scale_curve = _fade_curve()
	motes.explosiveness = 0.3
	_one_shot(motes, who.global_position + Vector3.UP * (0.1 - _feet(who)))
	_flash(who, tone)


## Вибух іскор у точці.
func _burst(at: Vector3, tone: Color, count: int, speed: float) -> void:
	var sparks := _particles(tone, count, 0.5, 0.11)
	var motion := sparks.process_material as ParticleProcessMaterial
	motion.spread = 180.0
	motion.initial_velocity_min = speed * 0.5
	motion.initial_velocity_max = speed
	motion.gravity = Vector3(0, -6.0, 0)
	motion.damping_min = speed * 0.8
	motion.damping_max = speed * 1.4
	motion.scale_curve = _fade_curve()
	_one_shot(sparks, at)


## Короткий спалах поверх усіх сіток моделі (`material_overlay`):
## працює і з фігуркою, і зі шкірою Mixamo, і з хутром.
func _flash(who: Node3D, tone: Color) -> void:
	var body: Node = who.call("model") if who.has_method("model") else who
	if body == null:
		return
	var paint := _glow_paint(tone, 1.0)
	paint.albedo_color.a = 0.3
	var meshes: Array = []
	for mesh: Node in body.find_children("*", "GeometryInstance3D",
			true, false):
		var g := mesh as GeometryInstance3D
		if g.material_overlay == null:
			g.material_overlay = paint
			meshes.append(g)
	if meshes.is_empty():
		return
	var fade := create_tween()
	fade.tween_property(paint, "albedo_color:a", 0.0, 0.14)
	fade.tween_callback(func() -> void:
		for g: GeometryInstance3D in meshes:
			if is_instance_valid(g) and g.material_overlay == paint:
				g.material_overlay = null)


func _one_shot(particles: GPUParticles3D, at: Vector3) -> void:
	if _live >= MAX_LIVE:
		particles.free()
		return
	particles.one_shot = true
	particles.explosiveness = maxf(particles.explosiveness, 0.85)
	add_child(particles)
	particles.global_position = at
	particles.emitting = true
	_live += 1
	get_tree().create_timer(particles.lifetime + 0.3).timeout.connect(
			func() -> void:
				_live -= 1
				if is_instance_valid(particles):
					particles.queue_free())


func _particles(tone: Color, amount: int, life: float, size: float,
		additive: bool = true) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	var motion := ParticleProcessMaterial.new()
	motion.direction = Vector3.UP
	p.process_material = motion
	var dot := QuadMesh.new()
	dot.size = Vector2(size, size)
	var paint := StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		paint.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		paint.albedo_color = Color(tone.r * 1.4, tone.g * 1.4,
				tone.b * 1.4)
	else:
		paint.albedo_color = Color(tone, 0.55)
	paint.vertex_color_use_as_albedo = true
	paint.albedo_texture = _soft_dot()
	dot.material = paint
	p.draw_pass_1 = dot
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-6, -2, -6), Vector3(12, 8, 12))
	return p


func _ring_mesh(tone: Color, radius: float, thick: float) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - thick
	torus.outer_radius = radius
	torus.rings = 48
	torus.ring_segments = 6
	ring.mesh = torus
	ring.material_override = _glow_paint(tone, 0.9)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return ring


static func _glow_paint(tone: Color, strength: float) -> StandardMaterial3D:
	var paint := StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	paint.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	paint.albedo_color = Color(tone.r * strength, tone.g * strength,
			tone.b * strength, 1.0)
	return paint


static var _dot: Texture2D = null
static var _curve: CurveTexture = null


## М'яка кругла цятка замість квадрата — частинки з квадратів виглядали б
## пікселями.
static func _soft_dot() -> Texture2D:
	if _dot == null:
		var shade := GradientTexture2D.new()
		shade.width = 32
		shade.height = 32
		shade.fill = GradientTexture2D.FILL_RADIAL
		shade.fill_from = Vector2(0.5, 0.5)
		shade.fill_to = Vector2(1.0, 0.5)
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		shade.gradient = g
		_dot = shade
	return _dot


static func _fade_curve() -> CurveTexture:
	if _curve == null:
		var c := Curve.new()
		c.add_point(Vector2(0.0, 1.0))
		c.add_point(Vector2(1.0, 0.0))
		_curve = CurveTexture.new()
		_curve.curve = c
	return _curve


# ─── довідкове ───────────────────────────────────────────────────────

func _body(id: int) -> Node3D:
	var who: Variant = creatures.get(id)
	return who as Node3D if who is Node3D and is_instance_valid(who) else null


func _chest(who: Node3D) -> float:
	var h := 1.75
	if who.has_method("body_height"):
		h = float(who.call("body_height"))
	return h * 0.6 - _feet(who)


func _feet(who: Node3D) -> float:
	return float(who.call("foot_drop")) if who.has_method("foot_drop") else 0.0


func _skill_named(skill_name: String) -> Skill:
	if skills == null:
		return null
	if _by_name.is_empty():
		for key in skills.keys():
			var s: Skill = skills.get_skill(key)
			_by_name[s.name] = s
	return _by_name.get(skill_name)


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
