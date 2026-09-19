class_name Dungeons
extends Node3D
## Відкриті підземелля (П-190, Ф4′): де стоять, що в них, куди ставити
## гравця й звідки виходити.
##
## Живе однаково на сервері й у клієнта. Сервер обирає шаблон і зерно й
## розсилає їх (`client_dungeon`); клієнт будує те саме з тих самих двох
## чисел — план детермінований, розійтися нема з чого. Серверові з
## побудованого потрібні зіткнення й висота підлоги, клієнтові — картинка.
##
## Де стоять — як і вирішено 05.09.2026 (П-167): «поруч, але щоб світи не
## перетиналися». Рядком далеко від суші, по одному місцю на святиню, і
## на 40 м угорі: море світу на своєму рівні рахує «під водою» за висотою,
## і підлога на −7 м топила б гравця посеред сухого склепу.
##
## Було z = −4000: під світ версії 1 (600 м) це 4 км від берега, а світ
## версії 2 починається з z = −3992 — підземелля стояли впритул до його
## краю. −9000 — за 5 км від обох. Кого вийшло посеред підземелля, після
## перезапуску сервера все одно вертає в місто перевірка П-202.

const ORIGIN := Vector3(0.0, 40.0, -9000.0)
## Найбільше підземелля — 150 клітинок по `DungeonPlan.CELL` = 300 м;
## 600 лишає між сусідніми понад 300.
const APART := 600.0
## Рівні одного підземелля (П-153, Ф5′, 19.09.2026) — рядком углиб по z,
## з тим самим кроком. Адреса рівня — одне число: святиня × LEVELS +
## рівень (рівень 0 — той, куди веде портал святині). Так усе, що вже
## знало підземелля за номером, лишилось працювати з рівнем 0.
const LEVELS := 16
const MAX_DEPTH := 10
## На скільки кроків шляху від виходу ставити гравця: не в самому колі
## виходу, інакше одразу вискочило б «вийти?».
const ENTRY_STEP := 8
## Через скільки вертається вбитий у підземеллі монстр. У полі — 12 с; тут
## зачистка має бути зачисткою. Число моє, не слово замовника.
const RESPAWN := 600.0

var book: DungeonBook
## Адреса рівня (`key`) -> {"template", "seed", "grade", "plan", "view",
## "exit", "zones", "depth", "down"}. `down` — портал «Далі» в палаті
## боса, запалюється смертю боса (Ф6); на останньому рівні його немає.
var open: Dictionary = {}


func _ready() -> void:
	book = DungeonBook.load_book()


static func key(shrine: int, level: int) -> int:
	return shrine * LEVELS + level


static func shrine_of(at: int) -> int:
	return at / LEVELS


static func level_of(at: int) -> int:
	return at % LEVELS


static func spot_for(at: int) -> Vector3:
	return ORIGIN + Vector3(float(shrine_of(at)) * APART, 0.0,
			-float(level_of(at)) * APART)


## Збудувати рівень підземелля `at` (адреса — `key`), або повернути вже
## збудований. `depth` — скільки рівнів у всьому підземеллі.
func raise(at: int, template_id: String, with_seed: int,
		grade: String, depth: int = 1) -> Dictionary:
	if open.has(at):
		return open[at]
	if not book.templates.has(template_id):
		print("[підземелля] ‼ немає шаблону «%s»" % template_id)
		return {}
	var started := Time.get_ticks_msec()
	var plan := book.make(template_id, with_seed)
	var view := DungeonView.new()
	view.name = "Підземелля%d" % at
	add_child(view)
	view.position = spot_for(at)
	view.build(plan, book.style_of(plan))
	var exit := Portal.new()
	exit.name = "Вихід"
	exit.grade = grade
	view.add_child(exit)
	exit.position = plan.at(plan.room_cell(plan.exit_room))
	var entry := {"template": template_id, "seed": with_seed,
			"grade": grade, "plan": plan, "view": view, "exit": exit,
			"zones": [], "depth": depth, "down": null}
	open[at] = entry
	print("[підземелля] %d: «%s» (%s), грейд %s, зерно %d — %d мс"
			% [at, plan.title, template_id, grade, with_seed,
			   Time.get_ticks_msec() - started])
	return entry


## Прибрати все підземелля святині — усі його рівні (Ф7: строк минув;
## Ф6: зачищено). Монстрів зон спершу прибирає спавнер — зони лежать у
## показі й підуть разом із ним.
func close(shrine: int) -> void:
	for at: int in levels_of(shrine):
		var view: Node = open[at]["view"]
		open.erase(at)
		if is_instance_valid(view):
			view.queue_free()
	print("[підземелля] за святинею %d закрито" % shrine)


## Відкриті рівні підземелля святині, згори вниз.
func levels_of(shrine: int) -> Array[int]:
	var out: Array[int] = []
	for at: int in open:
		if shrine_of(at) == shrine:
			out.append(at)
	out.sort()
	return out


## Запалити портал «Далі» там, де був бос (Ф6). Той самий вузол, що й
## «Вихід», лише назва інша.
func light_down(at: int) -> Portal:
	var entry: Dictionary = open.get(at, {})
	if entry.is_empty():
		return null
	if entry["down"] != null and is_instance_valid(entry["down"]):
		return entry["down"]
	var plan: DungeonPlan = entry["plan"]
	var down := Portal.new()
	down.name = "Далі"
	down.grade = entry["grade"]
	entry["view"].add_child(down)
	down.position = plan.at(plan.room_cell(plan.boss_room))
	entry["down"] = down
	return down


## Куди ставити гравця, що зайшов.
func entry_point(at: int) -> Vector3:
	var plan: DungeonPlan = open[at]["plan"]
	var cell := plan.room_cell(plan.exit_room)
	if not plan.main_path.is_empty():
		cell = plan.main_path[mini(ENTRY_STEP, plan.main_path.size() - 1)]
	return spot_for(at) + plan.at(cell) + Vector3(0.0, 1.0, 0.0)


## У якому підземеллі точка (за горизонталлю), або -1.
func index_at(x: float, z: float) -> int:
	for at: int in open:
		var plan: DungeonPlan = open[at]["plan"]
		var half := plan.size * DungeonPlan.CELL * 0.5
		var spot := spot_for(at)
		if absf(x - spot.x) <= half and absf(z - spot.z) <= half:
			return at
	return -1


## Висота підлоги підземелля в точці світу; NAN — точка не в підземеллі.
func floor_at(x: float, z: float) -> float:
	var at := index_at(x, z)
	if at < 0:
		return NAN
	var plan: DungeonPlan = open[at]["plan"]
	var spot := spot_for(at)
	var cx := floori((x - spot.x) / DungeonPlan.CELL + plan.size * 0.5)
	var cz := floori((z - spot.z) / DungeonPlan.CELL + plan.size * 0.5)
	return spot.y + plan.height(cx, cz)


## Зони появи за заселенням `DungeonBook.populate` — лише серверові.
##
## Зона — вузьке коло на прохідній клітинці: ширше — і випадкова точка
## лягла б у камінь, звідки монстр падав би в порожнечу під підземеллям.
## `with_boss` — false для рівня, чий бос уже вбитий (відновлення після
## перезапуску): вдруге він не з'являється.
func zones_for(at: int, mobs: Dictionary, with_boss: bool = true) -> Array:
	var entry: Dictionary = open[at]
	var plan: DungeonPlan = entry["plan"]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(entry["seed"]) + 1
	var made: Array = []
	for slot: Dictionary in book.populate(plan, entry["grade"], mobs, rng,
			level_of(at)):
		if slot["boss"] and not with_boss:
			continue
		var zone := MobZone.new()
		zone.name = "Зграя%d" % made.size()
		zone.kind = int(slot["kind"])
		zone.count = int(slot["count"])
		# Чекати, доки гравець ударить першим, у склепі дивно; число
		# виконавця, П-192.
		zone.aggressive = true
		zone.respawn_after = RESPAWN
		zone.respawn_spread = 60.0
		# Бос (Ф6) не вертається: його смерть і є зачистка рівня.
		if slot["boss"]:
			zone.boss = true
			zone.respawn_after = INF
		var holder := CollisionShape3D.new()
		var ring := CylinderShape3D.new()
		ring.radius = 0.6
		ring.height = 1.0
		holder.shape = ring
		zone.add_child(holder)
		var view: Node3D = entry["view"]
		view.add_child(zone)
		zone.position = plan.at(slot["cell"])
		made.append(zone)
	entry["zones"] = made
	return made
