class_name GraphicsQuality
## Якість графіки: Авто / Висока / Середня / Низька.
##
## Слово замовника 27.11.2026 після журналу підвисань з iMac (AMD Radeon Pro
## 570, 2560×1440): 328 з 365 повільних кадрів — 50–100 мс, тобто гра просто
## ледве тягне на цій відеокарті. «так» на налаштування якості. Висока — це
## саме те, як гра виглядала досі (тому проби й знімки не міняються); нижчі
## прибирають найдорожче: роздільність 3D (з підтягуванням FSR), SSAO і
## SSR, об'ємний туман (лишається звичайний), тіні та дальність рослин.
##
## «Авто» вибирає за назвою відеокарти. Вибір — у `user://settings.cfg`
## (`GameSettings`, секція «графіка»), міняється у вікні «Налаштування» одразу,
## без перезапуску: усе, що налаштовується, тут і реєструється.

const AUTO := "авто"
const LEVELS: Array[String] = ["авто", "висока", "середня", "низька"]
const TITLES := {"авто": "Авто", "висока": "Висока", "середня": "Середня",
		"низька": "Низька"}
const PRESET := {
	"висока": {"рендер": 1.0, "ssao": true, "ssr": true, "обємний": true,
			"тіні": true, "тіні_до": 100.0, "рослини": 110.0},
	"середня": {"рендер": 0.77, "ssao": false, "ssr": false, "обємний": true,
			"тіні": true, "тіні_до": 50.0, "рослини": 85.0},
	"низька": {"рендер": 0.59, "ssao": false, "ssr": false, "обємний": false,
			"тіні": false, "тіні_до": 30.0, "рослини": 65.0},
}
## Слабкі відеокарти — за частиною назви (нижній регістр). Вбудовані Intel,
## старі мобільні Radeon Pro в iMac/MacBook, програмний рендер.
const WEAK := ["intel", "radeon pro 4", "radeon pro 5", "llvmpipe",
		"swiftshader", "radeon r9 m", "geforce gt ", "geforce mx"]
const MIDDLE := ["radeon pro", "apple m1", "apple m2", "radeon(tm) graphics",
		"radeon vega", "geforce gtx 9", "geforce gtx 10"]

static var _envs: Array[WeakRef] = []
static var _suns: Array[WeakRef] = []
static var _views: Array[WeakRef] = []
static var _landscapes: Array[WeakRef] = []


static func chosen() -> String:
	var level := str(GameSettings.get_value("графіка", "якість", AUTO))
	return level if LEVELS.has(level) else AUTO


## Те, що діє зараз: «авто» розкрите в рівень.
static func level() -> String:
	return auto_level() if chosen() == AUTO else chosen()


static func auto_level() -> String:
	var card := RenderingServer.get_video_adapter_name().to_lower()
	if card == "":
		return "висока"
	for part: String in WEAK:
		if card.contains(part):
			return "низька"
	for part: String in MIDDLE:
		if card.contains(part):
			return "середня"
	return "висока"


static func preset() -> Dictionary:
	return PRESET[level()]


static func plant_distance(wanted: float) -> float:
	return minf(wanted, float(preset()["рослини"]))


static func set_chosen(new_level: String) -> void:
	if not LEVELS.has(new_level):
		return
	GameSettings.set_value("графіка", "якість", new_level)
	apply_all()
	HitchLog.note("якість графіки: %s (%s)" % [TITLES[new_level], TITLES[level()]])


## Довкілля світу чи підземелля. Що воно хотіло (SSAO, SSR, об'ємний туман),
## запам'ятовується при першій реєстрації: якість лише вимикає задумане,
## але не вмикає того, чого в цьому місці й не було.
static func tune_environment(air: Environment) -> void:
	if air == null:
		return
	if not air.has_meta("quality_intent"):
		air.set_meta("quality_intent", {"ssao": air.ssao_enabled,
				"ssr": air.ssr_enabled, "обємний": air.volumetric_fog_enabled,
				"туман": air.fog_enabled})
		_envs.append(weakref(air))
	var want: Dictionary = air.get_meta("quality_intent")
	var p := preset()
	air.ssao_enabled = want["ssao"] and p["ssao"]
	air.ssr_enabled = want["ssr"] and p["ssr"]
	air.volumetric_fog_enabled = want["обємний"] and p["обємний"]
	# Без об'ємного туману далечінь має все одно танути — звичайний туман.
	air.fog_enabled = want["туман"] or (want["обємний"] and not p["обємний"])


static func tune_sun(sun: DirectionalLight3D) -> void:
	if sun == null:
		return
	if not _has(_suns, sun):
		_suns.append(weakref(sun))
	sun.directional_shadow_max_distance = float(preset()["тіні_до"])
	if not shadows():
		sun.shadow_enabled = false


## Чи можна тіні (day_cycle вмикає їх щокадру, коли сонце світить).
static func shadows() -> bool:
	return bool(preset()["тіні"])


static func tune_viewport(view: Viewport) -> void:
	if view == null:
		return
	if not _has(_views, view):
		_views.append(weakref(view))
	var k := float(preset()["рендер"])
	if k >= 0.99:
		view.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		view.scaling_3d_scale = 1.0
	else:
		view.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		view.scaling_3d_scale = k


## Краєвид сам перерахує дальність рослин (`landscape.retune_plants`).
static func register_landscape(land: Node) -> void:
	if not _has(_landscapes, land):
		_landscapes.append(weakref(land))


static func apply_all() -> void:
	for ref in _envs:
		var air: Environment = ref.get_ref()
		if air != null:
			tune_environment(air)
	for ref in _suns:
		var sun: DirectionalLight3D = ref.get_ref()
		if sun != null:
			tune_sun(sun)
	for ref in _views:
		var view: Viewport = ref.get_ref()
		if view != null:
			tune_viewport(view)
	for ref in _landscapes:
		var land: Node = ref.get_ref()
		if land != null and land.has_method("retune_plants"):
			land.retune_plants()


static func _has(list: Array[WeakRef], thing: Object) -> bool:
	for ref in list:
		if ref.get_ref() == thing:
			return true
	return false
