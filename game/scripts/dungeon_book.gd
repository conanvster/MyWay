class_name DungeonBook
extends RefCounted
## Бібліотека підземель (П-190): шаблони, вибір при відкритті й заселення.
##
## Слово замовника 13.09.2026: підземелля «будуть випадковим чином
## випадати при відкритті підземелля та заселятися монстрами з рівнем в
## залежності від того, які за рівнем ворота були відкриті».
##
## Хто заселяє ворота якого грейду — НЕ окрема таблиця. Береться той
## самий знак, який уже веде гравця до воріт: ключ святині грейду G падає
## з певних монстрів (`data/mobs.json`, «дроп»), і саме ці монстри живуть
## за воротами G. Отже ворота E — заєць, вовк, кажан; D — кабан, слиз,
## паглін; C — імп, ведмідь. Додасться монстр із ключем — він сам стане в
## підземелля свого грейду, без правки тут.
##
## Шаблони й стилі — `data/dungeons.json`, правляться без коду.

const PATH := "res://data/dungeons.json"

## id -> шаблон.
var templates: Dictionary = {}
## стиль -> як малювати й кого пускати.
var styles: Dictionary = {}
## Строк і штраф світу (Ф7): {"строк_днів", "штраф_днів", "штраф"}.
var life: Dictionary = {}
## Ваги статів і глибина (П-191, Ф5′).
var weights: Dictionary = {}


static func load_book() -> DungeonBook:
	var book := DungeonBook.new()
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		print("[підземелля] ‼ не прочитано %s: %s"
				% [PATH, error_string(FileAccess.get_open_error())])
		return book
	var raw: Variant = JSON.parse_string(file.get_as_text())
	if not raw is Dictionary:
		print("[підземелля] ‼ %s — не JSON-об'єкт" % PATH)
		return book
	book.templates = raw.get("шаблони", {})
	book.styles = raw.get("стилі", {})
	book.life = raw.get("життя", {})
	book.weights = raw.get("ваги", {})
	return book


func ids() -> Array:
	var found := templates.keys()
	found.sort()
	return found


## Рівно випадково — запасний шлях, коли сили гравця не знаємо.
func pick(rng: RandomNumberGenerator) -> String:
	var all := ids()
	return str(all[rng.randi_range(0, all.size() - 1)])


# ── Ваги статів (П-191: слово замовника 19.09.2026 — «з вагами статів») ─
#
# Випадково, як і сказано 13.09.2026, але сильнішому частіше випадає
# складніше: у шаблону складності t вага exp(−(t − бажана)² / 2), де
# бажана складність росте з силою гравця й з глибиною рівня. Числа
# (кроки, розкид) — виконавця, у `dungeons.json → ваги`.

## Сила гравця для підземелля: сума БАЗОВИХ статів — те, що він виростив,
## без бафів і речей. На старті 50 (п'ять статів по 10), +3 за рівень.
static func power_of(who: Node) -> int:
	var b: Stats = who.base_stats
	return b.strength + b.agility + b.stamina + b.intellect + b.sense


## Бажана складність шаблону (1…5) для сили `power` на рівні `level`.
func wanted_tier(power: int, level: int) -> float:
	var w: Dictionary = weights
	var from := float(w.get("сила_старту", 50))
	var per_tier := float(w.get("сили_на_складність", 6))
	var per_level := float(w.get("складність_на_рівень", 0.5))
	return clampf(1.0 + (power - from) / per_tier + level * per_level,
			1.0, 5.0)


## Скільки рівнів у підземеллі, яке відкриває гравець сили `power`.
func depth_for(power: int) -> int:
	var w: Dictionary = weights
	var from := float(w.get("сила_старту", 50))
	var per_level := float(w.get("сили_на_рівень_глибини", 9))
	return clampi(int(w.get("рівнів_мінімум", 2))
			+ floori(maxf(0.0, power - from) / per_level), 1,
			Dungeons.MAX_DEPTH)


func pick_weighted(rng: RandomNumberGenerator, power: int,
		level: int) -> String:
	var aim := wanted_tier(power, level)
	var spread := float(weights.get("розкид", 1.0))
	var all := ids()
	var total := 0.0
	var each: Array[float] = []
	for id: String in all:
		var t := float(templates[id].get("складність", 1))
		var w := exp(-pow(t - aim, 2.0) / (2.0 * spread * spread))
		each.append(w)
		total += w
	var roll := rng.randf() * total
	for i in all.size():
		roll -= each[i]
		if roll <= 0.0:
			return str(all[i])
	return str(all[all.size() - 1])


func make(template_id: String, with_seed: int) -> DungeonPlan:
	return DungeonPlan.make(template_id, templates[template_id], with_seed)


func style_of(plan: DungeonPlan) -> Dictionary:
	return styles.get(plan.style, {})


## Види, з яких падає ключ цього грейду. Порожньо (A, S — П-169) — беремо
## найближчий нижчий грейд, і кажемо про це вголос.
static func band(mobs: Dictionary, grade: String) -> Array[int]:
	var grades: Array = ItemBook.GRADES
	var at := grades.find(grade)
	while at >= 0:
		var key := "ключ святині %s" % grades[at]
		var kinds: Array[int] = []
		var anyone: Array[int] = []
		for kind: String in mobs.keys():
			if not kind.is_valid_int():
				continue
			for drop: Dictionary in mobs[kind].get("дроп", []):
				if drop.get("що") == key:
					anyone.append(int(kind))
					# Слово замовника 20.09.2026: «для підземелля будуть
					# інші монстри». Види з поміткою `підземелля` на мапі
					# не стоять (їх туди не ставить `розселення.md`), а
					# тут мають перевагу; немає своїх на цей грейд —
					# беремо загальних і кажемо про це вголос (P3).
					if bool(mobs[kind].get("підземелля", false)):
						kinds.append(int(kind))
		if kinds.is_empty() and not anyone.is_empty():
			print("[підземелля] ‼ своїх монстрів на ворота %s немає — "
					% grades[at] + "беру звичайних")
			kinds = anyone
		if not kinds.is_empty():
			if grades[at] != grade:
				print("[підземелля] ‼ для воріт %s монстрів немає — беру %s"
						% [grade, grades[at]])
			kinds.sort()
			return kinds
		at -= 1
	return []


## Де й хто. Кожен запис: клітинка, вид, рівень, скільки, чи бос.
##
## Числа (скільки зграй на палату, скільки в зграї, крок по ходу, тиша
## біля входу) — мої, не слово замовника; зведені в один шаблон
## «складність», щоб правити одним числом.
func populate(plan: DungeonPlan, grade: String, mobs: Dictionary,
		rng: RandomNumberGenerator, level: int = 0) -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	# Глибина — на пів сходинки смуги за рівень (як і шаблон, П-191):
	# рівень 0 — своя смуга, 1 — своя з наступною, 2 — наступна, …
	# Досі всі рівні брали смугу воріт, і замовник 19.09.2026 закрив
	# підземелля, де «монстри що на першому що на другому рівні були
	# однакові».
	var grades: Array = ItemBook.GRADES
	var low := mini(grades.find(grade) + level / 2, grades.size() - 1)
	var kinds := band(mobs, grades[low])
	if level % 2 == 1 and low + 1 < grades.size():
		for kind in band(mobs, grades[low + 1]):
			if not kind in kinds:
				kinds.append(kind)
	if kinds.is_empty():
		print("[підземелля] ‼ ні для %s, ні нижче немає монстрів із ключем"
				% grade)
		return slots
	var liked: Array = style_of(plan).get("монстри", [])
	var fit: Array[int] = []
	for kind in kinds:
		if str(mobs[str(kind)].get("назва", "")) in liked:
			fit.append(kind)
	# Один «свій» вид на всю смугу — це рівень із самих кажанів: тоді
	# стиль лише додає своїх, а зграї беруться з усієї смуги.
	if fit.size() < 2:
		fit = kinds
	var strongest := _strongest(mobs, kinds)
	# Бос — найсильніший вид НАСТУПНОЇ смуги (П-192, слово замовника
	# 19.09.2026: «бос із наступної смуги»); за воротами E — з тих, з
	# кого падає ключ D. Наступної — від смуги цього рівня. Наступної
	# смуги немає — лишається своя.
	var boss := strongest
	var up := low + 1 + (level % 2)
	if up < grades.size():
		var next := band(mobs, grades[up])
		if not next.is_empty() and not _strongest(mobs, next) in kinds:
			boss = _strongest(mobs, next)

	var tier := plan.tier
	var from_exit := plan.distances(plan.room_cell(plan.exit_room))
	# Біля входу тихо: гравець не має з'являтися посеред зграї.
	var quiet := 14

	for r in plan.rooms.size():
		if r == plan.exit_room:
			continue
		var cell := plan.room_cell(r)
		if from_exit[plan.index(cell.x, cell.y)] < quiet:
			continue
		if r == plan.boss_room:
			slots.append(_slot(mobs, cell, boss, 1, true))
			slots.append(_slot(mobs, _near(plan, cell, rng), fit[0],
					1 + tier, false))
			continue
		var packs := 1 + (1 if tier >= 3 else 0) \
				+ (1 if float(plan.rooms[r]["reach"]) > 7.0 else 0)
		for p in packs:
			slots.append(_slot(mobs, _near(plan, cell, rng),
					fit[rng.randi_range(0, fit.size() - 1)],
					rng.randi_range(2, 2 + tier / 2), false))

	# Ходи: зграйка через кожні `gap` клітинок ходу, дальших від входу.
	var gap := 34 - tier * 2
	var last: Array[Vector2i] = []
	for z in plan.size:
		for x in plan.size:
			var i := plan.index(x, z)
			if plan.open[i] == 0 or plan.tunnel[i] == 0 \
					or from_exit[i] < quiet:
				continue
			var c := Vector2i(x, z)
			var crowded := false
			for was in last:
				if Vector2(c - was).length() < gap:
					crowded = true
					break
			if crowded:
				continue
			last.append(c)
			var kind := fit[rng.randi_range(0, fit.size() - 1)]
			slots.append(_slot(mobs, c, kind,
					rng.randi_range(1, 1 + tier / 2), false))
	return slots


static func _strongest(mobs: Dictionary, kinds: Array[int]) -> int:
	var best := kinds[0]
	for kind in kinds:
		if int(mobs[str(kind)].get("рівень", 1)) \
				> int(mobs[str(best)].get("рівень", 1)):
			best = kind
	return best


func _slot(mobs: Dictionary, cell: Vector2i, kind: int, count: int,
		boss: bool) -> Dictionary:
	return {"cell": cell, "kind": kind, "count": count, "boss": boss,
			"level": int(mobs[str(kind)].get("рівень", 1)),
			"name": str(mobs[str(kind)].get("назва", "?"))}


## Прохідна клітинка поруч із палатою — щоб зграї не ставали в одну точку.
func _near(plan: DungeonPlan, cell: Vector2i,
		rng: RandomNumberGenerator) -> Vector2i:
	for attempt in 20:
		var c := cell + Vector2i(rng.randi_range(-4, 4),
				rng.randi_range(-4, 4))
		if plan.is_open(c.x, c.y):
			return c
	return cell
