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
##   скіл      — на одну ціль летить згусток зі слідом, а якщо назва скіла
##               каже інше (`LOOK_BY_WORD`) — промінь, блискавка чи стріла;
##               «усі-поруч» — хвиля від кастера, блискавки з неба, град
##               стріл або удар об землю з пилом і трусінням камери;
##               баф/лік — частинки здіймаються довкола цілі;
##   удар      — іскри й короткий спалах на тілі цілі;
##   смерть    — пил під тілом (труп лишається за П-68).
##
## Колір — за стихією скіла; вона порожня в усіх 192 скілів (06.11.2026),
## тож спершу — стихія, вгадана з назви («вогняний спис» → вогонь), далі —
## за родом скіла (атака, баф, лік, дебаф).
##
## Критів і промахів у бою немає (`combat.gd`), тож і показувати їх нічим.
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

## Вигляд скіла за назвою (26.11.2026, П-272 залишок). У `skills.json` немає
## ні поля «вигляд», ні заповненої «стихії», тож що летить — промінь,
## блискавка, стріла чи згусток — і якого кольору, вгадується за словами
## назви. Перший збіг виграє. Сервер про це не знає: це лише показ.
##   look — "промінь" | "блискавка" | "стріла" | "земля" | "" (згусток/хвиля)
##   element — колір із `TONE_OF_ELEMENT`, якщо в самому скілі стихії немає
const LOOK_BY_WORD := [
	["промін", "промінь", ""],
	["блискав", "блискавка", "блискавка"],
	["гнів небес", "блискавка", "блискавка"],
	["грім", "земля", "блискавка"],
	["стріл", "стріла", ""],
	["постріл", "стріла", ""],
	["ударна хвиля", "земля", "земля"],
	["хвиля сили", "земля", ""],
	["землетрус", "земля", "земля"],
	["вогн", "", "вогонь"],
	["полум", "", "вогонь"],
	["віри", "", "світло"],
	["гнил", "", "темрява"],
]
const ARROW_SPEED := 32.0
const BEAM_TIME := 0.45
## Трусіння камери від удару об землю: найсильніше поруч, нуль далі за
## `SHAKE_REACH` метрів від камери.
const SHAKE_REACH := 22.0
const SHAKE_POWER := 0.22

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
	var look := look_of(skill)

	if target == "усі-поруч" and caster != null:
		var reach := skill.range_at(1) if skill != null else 4.0
		_wave(caster, tone, reach)
		if look == "земля":
			_slam(caster, reach)
	for v in victims:
		var who := _body(int(v))
		if who == null:
			continue
		var aimed := harms and caster != null and who != caster
		if aimed and target == "жива":
			match look:
				"промінь": _ray(caster, who, tone)
				"блискавка": _lightning(caster, who, tone, false)
				"стріла": _arrow(caster, who, tone)
				_: _bolt(caster, who, tone)
		elif aimed and look == "блискавка":
			_lightning(caster, who, tone, true)
		elif aimed and look == "стріла":
			_arrow(caster, who, tone)
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
	var guessed: String = _look_row(skill)[1]
	if TONE_OF_ELEMENT.has(guessed):
		return TONE_OF_ELEMENT[guessed]
	if skill.heals():
		return TONE_HEAL
	if _harms(skill):
		return TONE_ATTACK
	if skill.target == "жива":
		return TONE_CURSE
	return TONE_BUFF


## Що летить: "промінь", "блискавка", "стріла", "земля" або "" (див.
## `LOOK_BY_WORD`).
static func look_of(skill: Skill) -> String:
	return "" if skill == null else str(_look_row(skill)[0])


static var _look_cache: Dictionary = {}


static func _look_row(skill: Skill) -> Array:
	if _look_cache.has(skill.name):
		return _look_cache[skill.name]
	var row := ["", ""]
	var name_low := skill.name.to_lower()
	for rule: Array in LOOK_BY_WORD:
		if name_low.contains(rule[0]):
			row = [rule[1], rule[2]]
			break
	_look_cache[skill.name] = row
	return row


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


## Промінь: світна труба від рук кастера до цілі, по ній «тече» світло.
## Іде за обома, доки світить (`BEAM_TIME`).
func _ray(from: Node3D, to: Node3D, tone: Color) -> void:
	if _live >= MAX_LIVE:
		return
	var holder := Node3D.new()
	add_child(holder)
	_live += 1
	var tube := MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.top_radius = 0.09
	shape.bottom_radius = 0.09
	shape.height = 1.0
	shape.radial_segments = 12
	shape.rings = 1
	shape.cap_top = false
	shape.cap_bottom = false
	tube.mesh = shape
	var paint := ShaderMaterial.new()
	paint.shader = _flow_shader()
	paint.set_shader_parameter("tone", Vector3(tone.r, tone.g, tone.b))
	paint.set_shader_parameter("power", 1.0)
	tube.material_override = paint
	tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Вісь циліндра — Y; повертаємо на −Z вузла, щоб `look_at` її наводив.
	tube.rotation.x = -PI / 2.0
	holder.add_child(tube)
	var lamp := OmniLight3D.new()
	lamp.light_color = tone
	lamp.light_energy = 2.0
	lamp.omni_range = 3.5
	holder.add_child(lamp)
	var place := func(_t: float) -> void:
		if not (is_instance_valid(from) and is_instance_valid(to)):
			holder.visible = false
			return
		var a := from.global_position + Vector3.UP * _chest(from)
		var b := to.global_position + Vector3.UP * _chest(to)
		var length := maxf(0.1, a.distance_to(b))
		holder.global_position = a
		if not a.is_equal_approx(b) and absf((b - a).normalized().y) < 0.999:
			holder.look_at(b, Vector3.UP)
		tube.scale = Vector3(1.0, length, 1.0)
		tube.position = Vector3(0, 0, -length / 2.0)
		lamp.position = Vector3(0, 0, -length)
	place.call(0.0)
	var shine := holder.create_tween()
	shine.tween_method(place, 0.0, 1.0, BEAM_TIME)
	shine.parallel().tween_property(paint, "shader_parameter/power", 0.0,
			0.18).set_delay(BEAM_TIME - 0.18)
	shine.tween_callback(func() -> void:
		_live -= 1
		holder.queue_free())
	_burst(from.global_position + Vector3.UP * _chest(from), tone, 10, 1.6)
	_burst(to.global_position + Vector3.UP * _chest(to), tone, 24, 3.4)
	_flash(to, tone)


## Блискавка: ламана стрічка, двічі перемальована за 0,2 с, і спалах
## світла. `from_sky` — б'є з неба в ціль (скіли «усі-поруч»), інакше — від
## кастера.
func _lightning(from: Node3D, to: Node3D, tone: Color, from_sky: bool) -> void:
	if _live >= MAX_LIVE:
		return
	var end := to.global_position + Vector3.UP * _chest(to)
	var start: Vector3
	if from_sky:
		start = end + Vector3(randf_range(-2.0, 2.0), 14.0, randf_range(-2.0, 2.0))
	else:
		start = from.global_position + Vector3.UP * _chest(from)
	var bolt := MeshInstance3D.new()
	var lines := ImmediateMesh.new()
	bolt.mesh = lines
	bolt.material_override = _glow_paint(tone.lightened(0.35), 2.5)
	(bolt.material_override as StandardMaterial3D).cull_mode = \
			BaseMaterial3D.CULL_DISABLED
	bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bolt)
	_live += 1
	_jag(lines, start, end)
	var lamp := OmniLight3D.new()
	lamp.light_color = tone.lightened(0.3)
	lamp.light_energy = 6.0
	lamp.omni_range = 9.0
	add_child(lamp)
	lamp.global_position = end + Vector3.UP * 0.5
	var strike := bolt.create_tween()
	strike.tween_interval(0.07)
	strike.tween_callback(func() -> void: _jag(lines, start, end))
	strike.tween_interval(0.07)
	strike.tween_callback(func() -> void:
		_jag(lines, start, end)
		lamp.light_energy = 3.0)
	strike.tween_interval(0.08)
	strike.tween_callback(func() -> void:
		_live -= 1
		bolt.queue_free()
		lamp.queue_free())
	_burst(end, tone.lightened(0.3), 26, 5.0)
	_flash(to, Color(1, 1, 1))


## Ламана від `a` до `b`: дві схрещені стрічки (видно з будь-якого боку),
## кожна точка зсунута вбік на частку довжини.
func _jag(lines: ImmediateMesh, a: Vector3, b: Vector3) -> void:
	lines.clear_surfaces()
	var dir := (b - a)
	var length := dir.length()
	if length < 0.01:
		return
	dir /= length
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.1:
		side = dir.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(dir).normalized()
	var steps := clampi(int(length / 0.8), 4, 18)
	var points: Array[Vector3] = [a]
	for i in range(1, steps):
		var t := float(i) / float(steps)
		var swing := length * 0.06
		points.append(a.lerp(b, t) + side * randf_range(-swing, swing)
				+ up * randf_range(-swing, swing))
	points.append(b)
	lines.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for across: Vector3 in [side, up]:
		for i in points.size() - 1:
			var w0 := across * 0.05
			var w1 := across * 0.05
			var p0 := points[i]
			var p1 := points[i + 1]
			lines.surface_add_vertex(p0 - w0)
			lines.surface_add_vertex(p0 + w0)
			lines.surface_add_vertex(p1 + w1)
			lines.surface_add_vertex(p0 - w0)
			lines.surface_add_vertex(p1 + w1)
			lines.surface_add_vertex(p1 - w1)
	lines.surface_end()


## Стріла: тонке древко з ледь світним слідом, летить пологою дугою зі
## швидкістю `ARROW_SPEED` і влучає туди, де ціль на кінці польоту.
func _arrow(from: Node3D, to: Node3D, tone: Color) -> void:
	if _live >= MAX_LIVE:
		return
	var start := from.global_position + Vector3.UP * _chest(from)
	var holder := Node3D.new()
	add_child(holder)
	holder.global_position = start
	_live += 1
	var shaft := MeshInstance3D.new()
	var stick := BoxMesh.new()
	stick.size = Vector3(0.025, 0.025, 0.75)
	shaft.mesh = stick
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.55, 0.45, 0.32)
	wood.emission_enabled = true
	wood.emission = tone
	wood.emission_energy_multiplier = 0.6
	shaft.material_override = wood
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(shaft)
	var trail := _particles(tone, 30, 0.25, 0.05)
	var motion := trail.process_material as ParticleProcessMaterial
	motion.initial_velocity_min = 0.0
	motion.initial_velocity_max = 0.1
	motion.gravity = Vector3.ZERO
	motion.scale_curve = _fade_curve()
	holder.add_child(trail)
	var end0 := to.global_position + Vector3.UP * _chest(to)
	var flight := clampf(start.distance_to(end0) / ARROW_SPEED, 0.08, 0.9)
	var lift := start.distance_to(end0) * 0.06
	var fly := holder.create_tween()
	fly.tween_method(func(t: float) -> void:
		if not (is_instance_valid(to) and is_instance_valid(holder)):
			return
		var end := to.global_position + Vector3.UP * _chest(to)
		var arc := func(s: float) -> Vector3:
			return start.lerp(end, s) + Vector3.UP * (lift * 4.0 * s * (1.0 - s))
		var at: Vector3 = arc.call(t)
		var ahead: Vector3 = arc.call(t + 0.05)
		holder.global_position = at
		if not at.is_equal_approx(ahead):
			holder.look_at(ahead, Vector3.UP), 0.0, 1.0, flight)
	fly.tween_callback(func() -> void:
		if is_instance_valid(to):
			_burst(to.global_position + Vector3.UP * _chest(to), TONE_HIT, 12, 4.0)
			_flash(to, Color(1, 1, 1))
		shaft.visible = false
		trail.emitting = false)
	fly.tween_interval(0.3)
	fly.tween_callback(func() -> void:
		_live -= 1
		holder.queue_free())


## Удар об землю: пил колом від ніг і трусіння камери, якщо вона поруч.
func _slam(caster: Node3D, reach: float) -> void:
	var feet := caster.global_position + Vector3.UP * (0.05 - _feet(caster))
	var dust := _particles(TONE_DUST, 48, 0.9, 0.5, false)
	var motion := dust.process_material as ParticleProcessMaterial
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	motion.emission_ring_axis = Vector3.UP
	motion.emission_ring_radius = 0.8
	motion.emission_ring_inner_radius = 0.4
	motion.emission_ring_height = 0.05
	motion.direction = Vector3(0, 0.15, 0)
	motion.spread = 15.0
	motion.radial_accel_min = reach * 2.5
	motion.radial_accel_max = reach * 3.5
	motion.initial_velocity_min = 0.5
	motion.initial_velocity_max = 1.2
	motion.damping_min = 1.0
	motion.damping_max = 2.0
	motion.gravity = Vector3(0, -0.5, 0)
	_one_shot(dust, feet)
	shake_near(feet, SHAKE_POWER)


## Трусить камеру гравця, якщо подія поруч з нею. Камера — та, що зараз
## поточна у вікні; трусить її `CameraRig.shake`, якщо він є.
func shake_near(at: Vector3, power: float) -> void:
	var view := get_viewport()
	var cam := view.get_camera_3d() if view != null else null
	if cam == null:
		return
	var near := 1.0 - cam.global_position.distance_to(at) / SHAKE_REACH
	if near <= 0.0:
		return
	var rig := cam.get_parent()
	if rig != null and rig.has_method("shake"):
		rig.call("shake", power * near, 0.35)


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


## Новий рівень (14.11.2026). Півтори секунди: золотий стовп світла з
## неба, три кільця здіймаються від ніг до голови, іскри йдуть угору
## спіраллю, спалах на тілі й світло довкола, наостанок — сніп іскор над
## головою. Бачать усі, хто бачить гравця (`client_level_up`).
const TONE_LEVEL := Color(1.0, 0.82, 0.38)
const LEVEL_TIME := 1.6


func level_up(id: int) -> void:
	if _quiet:
		return
	var who := _body(id)
	if who == null:
		return
	var feet := who.global_position + Vector3.UP * (0.05 - _feet(who))
	# Стовп: циліндр, що розгоряється й гасне, трохи ширшаючи.
	var pillar := MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = 0.55
	tube.bottom_radius = 0.95
	tube.height = 14.0
	tube.cap_top = false
	tube.cap_bottom = false
	tube.radial_segments = 32
	pillar.mesh = tube
	# М'який промінь: яскравий посередині, тане до країв і догори (свій
	# шейдер — з простим матеріалом стовп був суцільною жовтою трубою).
	var paint := ShaderMaterial.new()
	paint.shader = _beam_shader()
	paint.set_shader_parameter("tone", TONE_LEVEL)
	paint.set_shader_parameter("power", 0.0)
	pillar.material_override = paint
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pillar)
	pillar.global_position = feet + Vector3.UP * 7.0
	pillar.scale = Vector3(0.6, 1.0, 0.6)
	_live += 1
	var glow := pillar.create_tween()
	glow.tween_property(paint, "shader_parameter/power", 1.0, 0.25)
	glow.parallel().tween_property(pillar, "scale", Vector3(1.0, 1.0, 1.0), 0.25)
	glow.tween_interval(0.5)
	glow.tween_property(paint, "shader_parameter/power", 0.0, LEVEL_TIME - 0.75)
	glow.parallel().tween_property(pillar, "scale", Vector3(1.4, 1.0, 1.4),
			LEVEL_TIME - 0.75)
	glow.tween_callback(func() -> void:
		_live -= 1
		pillar.queue_free())
	# Три кільця від ніг угору, одне за одним.
	for i in 3:
		var ring := _ring_mesh(TONE_LEVEL, 0.9, 0.05)
		add_child(ring)
		ring.global_position = feet + Vector3.UP * 0.1
		ring.scale = Vector3.ONE * 0.6
		var ring_paint := ring.material_override as StandardMaterial3D
		ring_paint.albedo_color.a = 0.0
		_live += 1
		var rise := ring.create_tween()
		rise.tween_interval(0.18 * float(i))
		rise.tween_property(ring_paint, "albedo_color:a", 1.0, 0.08)
		rise.parallel().tween_property(ring, "global_position",
				feet + Vector3.UP * 2.3, 0.7).set_ease(Tween.EASE_OUT) \
				.set_trans(Tween.TRANS_CUBIC)
		rise.parallel().tween_property(ring, "scale", Vector3.ONE * 1.25, 0.7)
		rise.tween_property(ring_paint, "albedo_color:a", 0.0, 0.25)
		rise.tween_callback(func() -> void:
			_live -= 1
			ring.queue_free())
	# Іскри спіраллю вгору.
	var motes := _particles(TONE_LEVEL, 90, 1.4, 0.13)
	var motion := motes.process_material as ParticleProcessMaterial
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	motion.emission_ring_axis = Vector3.UP
	motion.emission_ring_radius = 0.9
	motion.emission_ring_inner_radius = 0.6
	motion.emission_ring_height = 0.1
	motion.direction = Vector3.UP
	motion.spread = 6.0
	motion.initial_velocity_min = 1.8
	motion.initial_velocity_max = 3.2
	motion.orbit_velocity_min = 0.45
	motion.orbit_velocity_max = 0.7
	motion.gravity = Vector3.ZERO
	motion.scale_curve = _fade_curve()
	motes.explosiveness = 0.4
	_one_shot(motes, feet)
	# Спалах на тілі й світло довкола.
	_flash(who, TONE_LEVEL)
	var light := OmniLight3D.new()
	light.light_color = TONE_LEVEL
	light.light_energy = 0.0
	light.omni_range = 7.0
	add_child(light)
	light.global_position = feet + Vector3.UP * 1.6
	var shine := light.create_tween()
	shine.tween_property(light, "light_energy", 5.0, 0.2)
	shine.tween_property(light, "light_energy", 0.0, LEVEL_TIME - 0.2)
	shine.tween_callback(light.queue_free)
	# Сніп іскор над головою, коли кільця дійшли догори.
	get_tree().create_timer(0.75).timeout.connect(func() -> void:
		if is_instance_valid(who):
			_burst(who.global_position + Vector3.UP * (2.2 - _feet(who)),
					TONE_LEVEL, 40, 5.0))


static var _beam: Shader = null


static func _beam_shader() -> Shader:
	if _beam == null:
		_beam = Shader.new()
		_beam.code = """shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 tone = vec3(1.0, 0.82, 0.38);
uniform float power = 1.0;
void fragment() {
	float face = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float soft = pow(face, 2.5);
	float up = 1.0 - UV.y;
	float fade = smoothstep(0.0, 0.15, UV.y) * (0.25 + 0.75 * pow(UV.y, 1.5));
	ALBEDO = tone * (0.8 + 0.6 * soft);
	ALPHA = clamp(soft * fade * power * 0.75, 0.0, 1.0);
}
"""
	return _beam


static var _flow: Shader = null


## Промінь: яскраве серце, м'які краї й смуги, що біжать від кастера до цілі.
static func _flow_shader() -> Shader:
	if _flow == null:
		_flow = Shader.new()
		_flow.code = """shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 tone = vec3(0.55, 0.45, 1.0);
uniform float power = 1.0;
void fragment() {
	float face = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float core = pow(face, 1.8);
	float stripes = 0.65 + 0.35 * sin(UV.y * 40.0 + TIME * 30.0);
	ALBEDO = tone * (1.0 + 1.2 * core);
	ALPHA = clamp(core * stripes * power, 0.0, 1.0);
}
"""
	return _flow


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
