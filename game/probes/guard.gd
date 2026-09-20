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
	print("\n— з чисел виходить кільце —")
	var land := _land()
	var shrine := Shrine.new()
	shrine.grade = "SS"
	land.add_child(shrine)
	land._shrine_guard(shrine, {"вид": 1, "скільки": 8, "відстань": 28.0,
			"розкид": 7.0, "кілець": 8, "аґресивна": true,
			"вертається через": 300.0})
	var zone: Node = shrine.get_node_or_null("Охорона")
	_yes("зона охорони з'явилась", zone != null)
	if zone == null:
		land.queue_free()
		return
	_yes("монстрів у зоні 8", zone.count == 8)
	_yes("зона аґресивна", zone.aggressive)
	_yes("вертається через 300 с", is_equal_approx(zone.respawn_after,
			300.0))
	var куп := 0
	var найдалі := 0.0
	var найближче := INF
	for shape: CollisionShape3D in zone.find_children("*",
			"CollisionShape3D", false, false):
		куп += 1
		var far: float = Vector2(shape.position.x, shape.position.z).length()
		найдалі = maxf(найдалі, far)
		найближче = minf(найближче, far)
	print("    куп %d, від осі %.1f…%.1f м, радіус купи %.1f"
			% [куп, найближче, найдалі, 7.0])
	_yes("куп рівно стільки, скільки «кілець» (8)", куп == 8)
	_yes("усі купи на однаковій відстані — це кільце, а не натовп",
			absf(найдалі - найближче) < 0.01)
	_yes("кільце саме на 28 м", absf(найдалі - 28.0) < 0.01)
	# Впритул до святині ніхто не стоїть: купа радіуса 7 на 28 м лишає
	# 21 м чистого кола довкола каменя.
	_yes("біля самої святині чисто (%.0f м)" % (найдалі - 7.0),
			найдалі - 7.0 > 10.0)
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
	var ряд: Array = ["E", "D", "C", "B", "A", "S", "SS"]
	var росте := true
	for i in ряд.size() - 1:
		var a: int = int(за[ряд[i]].get("скільки", 0))
		var b: int = int(за[ряд[i + 1]].get("скільки", 0))
		if b < a:
			росте = false
	_yes("монстрів не меншає з грейдом", росте)
	var скільки: Array = []
	for grade: String in ряд:
		скільки.append("%s:%d/%.0fм" % [grade,
				int(за[grade].get("скільки", 0)),
				float(за[grade].get("відстань", 0.0))])
	print("    %s" % " ".join(PackedStringArray(скільки)))

	var грейди := {}
	for shrine: Dictionary in data.map.get("святині", []):
		var g := str(shrine.get("грейд", "?"))
		грейди[g] = int(грейди.get(g, 0)) + 1
	print("    святинь у світі: %s" % [грейди])
	_yes("святині є всіх семи грейдів", грейди.size() == 7)
