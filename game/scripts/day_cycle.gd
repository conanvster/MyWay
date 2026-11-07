class_name DayCycle
extends Node
## Зміна доби — ранок, день, вечір, ніч (П-274, слово замовника 07.11.2026:
## «я хотів додати зміну ранок, день, вечір, ніч — із своїми ефектами,
## анімацією»).
##
## Лише в клієнта: правила від пори доби поки нічого не залежать. Час —
## від годинника системи (`data/doba.json`: скільки хвилин триває доба),
## тож у всіх гравців він однаковий без жодного повідомлення сервера.
##
## Що міняється: сонце ходить по небу й міняє колір і силу; небо, обрій,
## розсіяне світло й туман — множниками до денного вигляду світу (удень
## світ точно такий, як погоджено раніше); уночі — місяць, зорі на небі,
## світлячки довкола гравця; уранці — густий туман.
##
## Перевірка: `./run.sh --доба [тека]` — знімки тієї самої місцини о
## восьмій порі; у грі прапорець `--година 19.5` спиняє час на годині, а
## `--доба-хвилин 4` пришвидшує добу (подивитись захід за хвилину).

const PATH := "res://data/doba.json"
## Як часто перераховувати: світло міняється повільно, щокадру не треба.
const EVERY := 0.25

var land: Node = null
var sun: DirectionalLight3D = null
var moon: DirectionalLight3D = null
## Година, яку показувати замість годинника (NAN — годинник).
var fixed_hour := NAN
var _rules: Dictionary = {}
var _points: Array = []
var _air: Environment = null
var _sky: ProceduralSkyMaterial = null
## Денний вигляд світу — від нього рахуються множники.
var _base: Dictionary = {}
var _clock := 0.0
var _flies: CPUParticles3D = null
var _fly_glow: StandardMaterial3D = null
## Що показано зараз — для годинника в HUD і проби.
var hour_now := 12.0
var part_now := "день"


func setup(with_land: Node, with_sun: DirectionalLight3D) -> void:
	land = with_land
	sun = with_sun
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not parsed is Dictionary:
		print("[доба] ‼ %s не прочитався — доба стоїть" % PATH)
		return
	_rules = parsed
	_points = _rules.get("точки", [])
	_points.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["година"]) < float(b["година"]))
	var args := OS.get_cmdline_user_args()
	var at := args.find("--година")
	if at >= 0 and at + 1 < args.size():
		fixed_hour = float(args[at + 1])
	at = args.find("--доба-хвилин")
	if at >= 0 and at + 1 < args.size():
		_rules["доба, хвилин"] = float(args[at + 1])
	_remember()
	moon = DirectionalLight3D.new()
	moon.name = "Місяць"
	moon.light_color = Color(0.62, 0.72, 1.0)
	moon.light_energy = 0.0
	moon.shadow_enabled = false
	add_child(moon)
	_build_flies()
	apply(hour())


## Денний вигляд — яким світ збудував краєвид. Береться раз, на старті.
func _remember() -> void:
	var holder := land.get_node_or_null("Небо") as WorldEnvironment if land != null \
			else null
	if holder == null:
		return
	_air = holder.environment
	_sky = _air.sky.sky_material as ProceduralSkyMaterial if _air.sky != null \
			else null
	_base = {
		"небо": _sky.sky_top_color if _sky != null else Color.WHITE,
		"обрій": _sky.sky_horizon_color if _sky != null else Color.WHITE,
		"земля обрій": _sky.ground_horizon_color if _sky != null else Color.WHITE,
		"довкілля": _air.ambient_light_color,
		"сила довкілля": _air.ambient_light_energy,
		"туман": _air.fog_light_color,
		"об'ємний": _air.volumetric_fog_albedo,
		"густина": _air.volumetric_fog_density,
		"експозиція": _air.tonemap_exposure,
		"сонце": sun.light_color if sun != null else Color.WHITE,
		"сила сонця": sun.light_energy if sun != null else 1.0,
	}
	if _sky != null:
		_sky.sky_cover = _stars()
		_sky.sky_cover_modulate = Color(1, 1, 1, 0)


## Година доби 0…24 за годинником системи.
func hour() -> float:
	if not is_nan(fixed_hour):
		return fposmod(fixed_hour, 24.0)
	var length := maxf(0.1, float(_rules.get("доба, хвилин", 120.0))) * 60.0
	var now := Time.get_unix_time_from_system()
	return fposmod(fposmod(now, length) / length * 24.0
			+ float(_rules.get("зсув, годин", 0.0)), 24.0)


func part_of(h: float) -> String:
	for row: Array in _rules.get("пори", []):
		var from := float(row[1])
		var to := float(row[2])
		if (from <= to and h >= from and h < to) \
				or (from > to and (h >= from or h < to)):
			return str(row[0])
	return ""


func _process(delta: float) -> void:
	_clock -= delta
	if _clock > 0.0 or _points.is_empty():
		return
	_clock = EVERY
	apply(hour())


## Поставити світ на годину `h`.
func apply(h: float) -> void:
	if _points.is_empty() or _base.is_empty():
		return
	hour_now = h
	part_now = part_of(h)
	var k := _blend(h)
	# Сонце: висота з точок, по колу за годиною (схід — уранці на сході).
	var high := deg_to_rad(float(k["висота"]))
	var turn := (h / 24.0) * TAU - PI * 0.5
	var toward := Vector3(cos(turn) * cos(high), sin(high),
			sin(turn) * cos(high))
	if sun != null:
		sun.look_at_from_position(Vector3.ZERO, -toward, Vector3.UP
				if absf(toward.y) < 0.99 else Vector3.FORWARD)
		sun.light_color = _mul(_base["сонце"], k["сонце"])
		sun.light_energy = float(_base["сила сонця"]) * float(k["сила сонця"])
		sun.shadow_enabled = sun.light_energy > 0.05
	if moon != null:
		var moon_at := Vector3(-toward.x, absf(toward.y) * 0.8 + 0.35, -toward.z) \
				.normalized()
		moon.look_at_from_position(Vector3.ZERO, -moon_at, Vector3.UP)
		moon.light_energy = float(k["місяць"])
		moon.visible = land == null or land.visible
	if _sky != null:
		_sky.sky_top_color = _mul(_base["небо"], k["небо"])
		_sky.sky_horizon_color = _mul(_base["обрій"], k["обрій"])
		_sky.ground_horizon_color = _mul(_base["земля обрій"], k["обрій"])
		_sky.sky_cover_modulate = Color(1, 1, 1, float(k["зорі"]))
	if _air != null:
		_air.ambient_light_color = _mul(_base["довкілля"], k["довкілля"])
		_air.ambient_light_energy = float(_base["сила довкілля"]) \
				* float(k["сила довкілля"])
		_air.fog_light_color = _mul(_base["туман"], k["туман"])
		_air.volumetric_fog_albedo = _mul(_base["об'ємний"], k["туман"])
		_air.volumetric_fog_density = float(_base["густина"]) * float(k["густина"])
		_air.tonemap_exposure = float(_base["експозиція"]) * float(k["експозиція"])
	if _flies != null:
		var glow := clampf(float(k["світлячки"]), 0.0, 1.0)
		_fly_glow.albedo_color.a = glow
		_fly_glow.emission_energy_multiplier = 3.0 * glow
		_flies.emitting = glow > 0.02 and (land == null or land.visible)


## «вечір 19:40» — для HUD.
func clock_text() -> String:
	var minutes := int(hour_now * 60.0) % (24 * 60)
	return "%s %02d:%02d" % [part_now, minutes / 60, minutes % 60]


## Світлячки ходять за гравцем: `follow` кличе клієнт щокадру.
func follow(at: Vector3) -> void:
	if _flies != null:
		_flies.global_position = at


## Точка між двома сусідніми точками доби (по колу через північ).
func _blend(h: float) -> Dictionary:
	var n := _points.size()
	var after := 0
	while after < n and float(_points[after]["година"]) <= h:
		after += 1
	var a: Dictionary = _points[(after - 1 + n) % n]
	var b: Dictionary = _points[after % n]
	var ha := float(a["година"])
	var hb := float(b["година"])
	var span := fposmod(hb - ha, 24.0)
	var t := 0.0 if span <= 0.0 else fposmod(h - ha, 24.0) / span
	t = t * t * (3.0 - 2.0 * t)
	var out := {}
	for key: String in a:
		var va: Variant = a[key]
		var vb: Variant = b.get(key, va)
		if va is Array:
			out[key] = [lerpf(float(va[0]), float(vb[0]), t),
					lerpf(float(va[1]), float(vb[1]), t),
					lerpf(float(va[2]), float(vb[2]), t)]
		else:
			out[key] = lerpf(float(va), float(vb), t)
	return out


static func _mul(c: Color, by: Array) -> Color:
	return Color(c.r * float(by[0]), c.g * float(by[1]), c.b * float(by[2]), c.a)


## Зоряне небо: крапки на чорному (небо — рівнокутна розгортка), яскраві
## рідше, Чумацький Шлях — густішою смугою.
static func _stars() -> ImageTexture:
	var w := 2048
	var h := 1024
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color.BLACK)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for i in 5200:
		var x := rng.randi() % w
		# лише верхня половина — під обрієм зір немає
		var y := int(pow(rng.randf(), 1.3) * float(h) * 0.5)
		var band := absf(float(x) / float(w) * 2.0 - 1.0 - float(y) / float(h))
		if band > 0.25 and rng.randf() < 0.45:
			continue
		var b := pow(rng.randf(), 3.0) * 0.9 + 0.1
		var tone := Color(b, b, b * rng.randf_range(0.9, 1.15))
		img.set_pixel(x, y, tone)
		if b > 0.75:
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1),
					Vector2i(0, -1)]:
				var p := Vector2i(x, y) + d
				if p.x >= 0 and p.x < w and p.y >= 0 and p.y < h:
					img.set_pixel(p.x, p.y, tone * 0.45)
	return ImageTexture.create_from_image(img)


## Світлячки: жовто-зелені іскри, що повільно блукають довкола гравця.
func _build_flies() -> void:
	_flies = CPUParticles3D.new()
	_flies.name = "Світлячки"
	_flies.amount = 70
	_flies.lifetime = 6.0
	_flies.preprocess = 6.0
	_flies.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_flies.emission_box_extents = Vector3(16, 2.5, 16)
	_flies.direction = Vector3(0, 1, 0)
	_flies.spread = 180.0
	_flies.gravity = Vector3.ZERO
	_flies.initial_velocity_min = 0.1
	_flies.initial_velocity_max = 0.5
	_flies.local_coords = false
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0))
	curve.add_point(Vector2(0.2, 1))
	curve.add_point(Vector2(0.8, 1))
	curve.add_point(Vector2(1, 0))
	_flies.scale_amount_curve = curve
	var dot := QuadMesh.new()
	dot.size = Vector2(0.09, 0.09)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glow.albedo_color = Color(0.85, 1.0, 0.45)
	glow.emission_enabled = true
	glow.emission = Color(0.8, 1.0, 0.4)
	glow.emission_energy_multiplier = 3.0
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fly_glow = glow
	dot.material = glow
	_flies.mesh = dot
	_flies.position = Vector3(0, 1.5, 0)
	_flies.emitting = false
	add_child(_flies)
