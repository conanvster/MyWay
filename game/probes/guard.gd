extends Node
## Тонкі налаштування охорони святинь (слово замовника 20.09.2026:
## «хочу тонкі налаштування охорони, скільки монстрів, як далеко від
## святині»).
##
## Перевіряємо не «начебто працює», а самі числа: що кожен із трьох
## шарів справді перекриває попередній і лише тими ключами, які назвав,
## і що з них виходить кільце потрібного радіуса, а не натовп збоку.
##
##     godot --headless --path game res://scenes/guard.tscn

const LAND := preload("res://scripts/landscape.gd")

var _ok := 0
var _bad := 0


func _ready() -> void:
	_go()


func _yes(text: String, is_ok: bool) -> void:
	_ok += 1 if is_ok else 0
	_bad += 0 if is_ok else 1
	print("  %s %s" % ["✓" if is_ok else "✗", text])


func _go() -> void:
	await get_tree().process_frame
	_layers()
	_ring()
	_data()
	print("  підсумок: %s" % ("усе гаразд" if _bad == 0
			else "‼ вад: %d" % _bad))
	get_tree().quit(1 if _bad > 0 else 0)


func _land() -> Node:
	var land: Node = LAND.new()
	add_child(land)
	return land


func _layers() -> void:
	print("\n— три шари налаштувань —")
	var land := _land()
	var guard := {
		"скільки": 3, "відстань": 14.0, "розкид": 4.0, "кілець": 4,
		"аґресивна": false,
		"за грейдом": {
			"SS": {"вид": 206, "скільки": 8, "відстань": 28.0,
				   "аґресивна": true},
		},
	}
	var база: Dictionary = land._guard_for(guard, "E", {})
	print("    E без свого рядка: %s" % [база])
	_yes("грейд без свого рядка бере загальні числа",
			int(база["скільки"]) == 3 and float(база["відстань"]) == 14.0)

	var вищий: Dictionary = land._guard_for(guard, "SS", {})
	print("    SS за грейдом: %s" % [вищий])
	_yes("грейд перекриває назване (скільки 8, відстань 28)",
			int(вищий["скільки"]) == 8 and float(вищий["відстань"]) == 28.0)
	_yes("а неназване лишає загальним (розкид 4, кілець 4)",
			float(вищий["розкид"]) == 4.0 and int(вищий["кілець"]) == 4)
	_yes("аґресивність теж перекривається", bool(вищий["аґресивна"]))

	# Третій шар: одна окрема святиня.
	var своя: Dictionary = land._guard_for(guard, "SS",
			{"скільки": 12, "відстань": 40.0})
	print("    SS плюс своя святиня: %s" % [своя])
	_yes("святиня перекриває грейд (12 монстрів, 40 м)",
			int(своя["скільки"]) == 12 and float(своя["відстань"]) == 40.0)
	_yes("вид із грейду лишився (206)", int(своя["вид"]) == 206)
	land.queue_free()


func _ring() -> void:
	print("\n— купки з главарями —")
	var land := _land()
	var shrine := Shrine.new()
	shrine.grade = "C"
	land.add_child(shrine)
	land._shrine_guard(shrine, {"вид": 1, "купок": 8, "главарів": 1,
			"помічників": 2, "відстань": 28.0, "розкид": 3.0,
			"вертається через": 200.0})
	var zones: Array = shrine.find_children("*", "MobZone", false, false)
	var chiefs: Array = []
	var helpers: Array = []
	for zone: Node in zones:
		if zone.name.begins_with("Главар"):
			chiefs.append(zone)
		else:
			helpers.append(zone)
	print("    зон %d: главарів %d, купок помічників %d"
			% [zones.size(), chiefs.size(), helpers.size()])
	_yes("купок стільки, скільки замовлено (8)", chiefs.size() == 8)
	_yes("у кожній купці свій главар", chiefs.size() == helpers.size())
	var всього := 0
	for zone: Node in zones:
		всього += zone.count
	_yes("усього монстрів 8×(1+2) = 24", всього == 24)
	var злих := 0
	for zone: Node in chiefs:
		if zone.aggressive:
			злих += 1
	var спокійних := 0
	for zone: Node in helpers:
		if not zone.aggressive:
			спокійних += 1
	_yes("главарі кидаються самі", злих == 8)
	_yes("помічники чекають на поклик", спокійних == 8)

	# Головне число: між сусідніми купками має бути БІЛЬШЕ, ніж поклик
	# на поміч, інакше один главар підіймає всю святиню.
	var точки: Array = []
	for zone: Node in helpers:
		for shape: CollisionShape3D in zone.find_children("*",
				"CollisionShape3D", false, false):
			точки.append(Vector2(shape.position.x, shape.position.z))
	точки.sort_custom(func(a: Vector2, b: Vector2) -> bool:
			return a.angle() < b.angle())
	var найближчі := INF
	for i in точки.size():
		var a: Vector2 = точки[i]
		var b: Vector2 = точки[(i + 1) % точки.size()]
		найближчі = minf(найближчі, a.distance_to(b))
	var spread := 3.0
	var чисто := найближчі - spread * 2.0
	var data := GameData.new()
	data.load_all()
	var поклик := float(data.for_kind(1).get("поклик", 12.0))
	print("    між сусідніми купками %.1f м, чистого %.1f, поклик %.0f м"
			% [найближчі, чисто, поклик])
	_yes("купки не перетинаються: чистого більше за поклик",
			чисто > поклик)
	var далеко := 0.0
	for точка: Vector2 in точки:
		далеко = maxf(далеко, точка.length())
	_yes("кільце саме на 28 м", absf(далеко - 28.0) < 0.01)
	land.queue_free()


func _data() -> void:
	print("\n— що в даних —")
	var data := GameData.new()
	data.load_all()
	var guard: Dictionary = data.map.get("охорона святинь", {})
	_yes("блок охорони є", not guard.is_empty())
	var за: Dictionary = guard.get("за грейдом", {})
	_yes("є рядок на кожен із семи грейдів", за.size() == 7)
	var mobs: Dictionary = data.mobs
	var усі := true
	for grade: String in за:
		var kind := str(int(за[grade].get("вид", 0)))
		if not mobs.has(kind):
			усі = false
			print("    ‼ %s: виду %s немає в mobs.json" % [grade, kind])
	_yes("вид сторожа кожного грейду існує", усі)
	# Числа мають рости з грейдом — інакше SS охороняє менше за E.
	# Рахуємо ЗАГАЛЬНУ кількість: купок × (главар + помічники).
	var ряд: Array = ["E", "D", "C", "B", "A", "S", "SS"]
	var разом := func(g: String) -> int:
		var row: Dictionary = за[g]
		return int(row.get("купок", 1)) * (int(row.get("главарів", 0))
				+ int(row.get("помічників", 0)))
	var росте := true
	for i in ряд.size() - 1:
		if разом.call(ряд[i + 1]) < разом.call(ряд[i]):
			росте = false
	_yes("монстрів не меншає з грейдом", росте)
	var скільки: Array = []
	for grade: String in ряд:
		var row: Dictionary = за[grade]
		скільки.append("%s:%d×(%d+%d)=%d/%.0fм" % [grade,
				int(row.get("купок", 1)), int(row.get("главарів", 0)),
				int(row.get("помічників", 0)), разом.call(grade),
				float(row.get("відстань", 0.0))])
	print("    %s" % " ".join(PackedStringArray(скільки)))

	# Поклик главаря не має діставати до сусідньої купки в жодному
	# грейді — «не пересікаються» (слово замовника).
	var перетини: Array = []
	for grade: String in ряд:
		var row: Dictionary = за[grade]
		var куп: int = maxi(1, int(row.get("купок", 1)))
		var far: float = float(row.get("відстань", 14.0))
		var spread3: float = float(row.get("розкид", 4.0))
		var поклик3 := float(mobs[str(int(row.get("вид", 1)))].get(
				"поклик", 12.0))
		var сусід := 2.0 * far * sin(PI / float(куп))
		if куп > 1 and сусід - spread3 * 2.0 <= поклик3:
			перетини.append("%s (%.1f м проти поклику %.0f)"
					% [grade, сусід - spread3 * 2.0, поклик3])
	if not перетини.is_empty():
		print("    ‼ %s" % " ".join(PackedStringArray(перетини)))
	_yes("у жодному грейді купки не перетинаються поклику",
			перетини.is_empty())

	var грейди := {}
	for shrine: Dictionary in data.map.get("святині", []):
		var g := str(shrine.get("грейд", "?"))
		грейди[g] = int(грейди.get(g, 0)) + 1
	print("    святинь у світі: %s" % [грейди])
	_yes("святині є всіх семи грейдів", грейди.size() == 7)
	var замовлено := {"E": 2, "D": 4, "C": 6, "B": 8, "A": 8, "S": 4,
			"SS": 1}
	var збіг := true
	for g: String in замовлено:
		if int(грейди.get(g, 0)) != int(замовлено[g]):
			збіг = false
			print("    ‼ %s: %d замість %d" % [g, int(грейди.get(g, 0)),
					int(замовлено[g])])
	_yes("підземель кожного грейду стільки, скільки замовлено", збіг)

	# Кожна купка мусить лишати чисте коло довкола каменя: інакше
	# охорона стоїть упритул і бити її доводиться з самої святині.
	var тісно: Array = []
	for grade: String in за:
		var far: float = float(за[grade].get("відстань", 14.0))
		var spread2: float = float(за[grade].get("розкид", 4.0))
		if far - spread2 < 8.0:
			тісно.append(grade)
	_yes("біля самої святині скрізь чисто (≥8 м)", тісно.is_empty())
