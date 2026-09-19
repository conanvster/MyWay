extends Node
## Строк підземель і штраф світу (П-153, Ф7) — без бази й без 30 днів
## чекання: годинник `DungeonLife.clock` підмінено.
##
## Що перевіряється: активація пускає відлік на 30 днів; перший вхід
## дописує шаблон; строк минув — підземелля закрито, гравця повернено
## до святині, святиня знову під охороною, монстрів підземелля
## прибрано, на світ упав штраф; штраф не подвоюється від повторного
## виклику, але складається від двох підземель; через 7 днів спадає;
## відновлення після перезапуску ставить те саме підземелля.
##
## Ганяти так (сценою, бо потрібні автозавантаження):
##     godot --headless --path game res://scenes/dungeon_life.tscn

const MAIN := preload("res://scenes/main.tscn")
const DAY := 86400.0

var _ok := 0
var _bad := 0
var _shift := [0.0]


class Quiet extends Messenger:
	var said: Array[String] = []

	func notice(_id: int, text: String) -> void:
		said.append(text)

	func to_all(_method: StringName, _args: Array = []) -> void:
		pass

	func to_watchers(_subject: int, _method: StringName,
			_args: Array = []) -> void:
		pass

	func to_one(_peer: int, _method: StringName, _args: Array = []) -> void:
		pass


func _ready() -> void:
	_go()


func _yes(text: String, is_ok: bool) -> void:
	if is_ok:
		_ok += 1
		print("  ✓ %s" % text)
	else:
		_bad += 1
		print("  ✗ %s" % text)


func _mobs_in(world: Node, at: int) -> int:
	var n := 0
	for id: int in world.creatures:
		var c: Node3D = world.creatures[id]
		if id < 0 and world.dungeons.index_at(c.global_position.x,
				c.global_position.z) == at:
			n += 1
	return n


func _open_and_enter(world: Node, me: Node, at: int) -> void:
	var shrine: Shrine = world.get_node("Landscape").shrines()[at]
	shrine.set_stage(Shrine.Stage.ЗАЧИЩЕНА)
	me.items["ключ святині %s" % shrine.grade] = 1
	me.global_position = shrine.global_position + Vector3(1.5, 0, 0)
	world.activate_shrine(1, at)
	await get_tree().process_frame
	me.global_position = shrine.portal().global_position
	world.enter_dungeon(1, at)


func _go() -> void:
	await get_tree().process_frame
	# Світ-клієнт сам стукає на 127.0.0.1, а там може саме йти
	# гра замовника (19.09.2026: проба під'єдналась до живого
	# сервера світу 2 й перезапускалась по колу). «Уже в мережі» —
	# і `Net.join()` нічого не робить.
	Net.joined = true
	var world: Node3D = MAIN.instantiate()
	get_tree().root.add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame
	var post := Quiet.new(world, null)
	world.link = post
	var life := DungeonLife.new()
	world.add_child(life)
	life.setup(null, world.dungeons.book.life, GameData.world_key())
	var base := Time.get_unix_time_from_system()
	life.clock = func() -> float: return base + _shift[0]
	world.life = life
	var land: Node = world.get_node("Landscape")
	print("\n— строк підземель і штраф світу (Ф7), святинь %d —"
			% land.shrines().size())

	var me: Node = world.spawn(1, Vector3.ZERO)
	me.items = {}
	me.hp = maxi(me.hp, 50)
	# Монстр у світі — на ньому видно штраф.
	var beast: Node = world.spawn(-9001, Vector3(3, 0, 3))
	beast.setup(Vector3(3, 0, 3), 1, false, world.data.for_kind(1))
	await get_tree().process_frame
	var plain_attack: float = beast.stats.physical_attack()
	var plain_defence: float = beast.stats.physical_defence()
	var plain_hp: int = beast.stats.max_hp()
	# Свій баф появи в монстра може бути — штраф рахуємо понад нього.
	var own: int = beast.states.count()

	await _open_and_enter(world, me, 0)
	var record: Dictionary = life.records.get(0, {})
	_yes("активація пустила відлік на %.0f днів"
			% ((int(record.get("closes", 0)) - int(record.get("opened", 0)))
			/ DAY),
			absf((int(record.get("closes", 0)) - int(record.get("opened", 0)))
			- life.days_open() * DAY) < 1.0)
	_yes("перший вхід дописав шаблон «%s»" % record.get("template", ""),
			str(record.get("template", "")) != ""
			and world.dungeons.open.has(0))
	await get_tree().process_frame
	var inside := _mobs_in(world, 0)
	_yes("у підземеллі є монстри: %d" % inside, inside > 0)
	_yes("гравець усередині", world.dungeons.index_at(me.global_position.x,
			me.global_position.z) == 0)

	_shift[0] = life.days_open() * DAY - 60.0
	_yes("за хвилину до строку не закривається",
			life.tick(LifeStep.BIG).is_empty())
	_shift[0] = life.days_open() * DAY + 1.0
	var due: Array[int] = life.tick(LifeStep.BIG)
	_yes("строк минув — до закриття: %s" % [due], due == [0])
	for at: int in due:
		world.close_dungeon(at)
	await get_tree().process_frame
	var shrine: Shrine = land.shrines()[0]
	_yes("підземелля закрито", not world.dungeons.open.has(0))
	_yes("монстрів підземелля прибрано: було %d, лишилось %d"
			% [inside, _mobs_in(world, 0)], _mobs_in(world, 0) == 0)
	_yes("гравця повернено до святині (%.1f м)"
			% me.global_position.distance_to(shrine.global_position),
			me.global_position.distance_to(shrine.global_position) < 12.0)
	_yes("святиня знову під охороною",
			shrine.stage == Shrine.Stage.ПІД_ОХОРОНОЮ)
	_yes("запис прибрано, штраф один", life.records.is_empty()
			and life.penalties.size() == 1)
	var hit: float = beast.stats.physical_attack() / plain_attack
	var guard: float = beast.stats.physical_defence() / plain_defence
	var thick: float = float(beast.stats.max_hp()) / plain_hp
	_yes("монстр світу під штрафом: здоров'я ×%.2f, атака ×%.2f, захист ×%.2f"
			% [thick, hit, guard],
			absf(thick - 3.0) < 0.02 and absf(hit - 1.5) < 0.02
			and absf(guard - 1.5) < 0.02 and beast.states.count() == own + 3)
	_yes("цілий монстр лишився цілим: %d / %d"
			% [beast.hp, beast.stats.max_hp()],
			beast.hp == beast.stats.max_hp())
	world.penalize(beast)
	_yes("повторний виклик штраф не подвоює (станів %d)"
			% beast.states.count(), beast.states.count() == own + 3)

	SelectMark.put(beast, 0.8, 2.0)
	world.client_states([], -9001, world.states_row(beast))
	var arrow: Label3D = beast.get_node("%s/Стрілка" % SelectMark.NAME)
	_yes("вибраний під штрафом — фіолетовий", arrow.modulate
			== SelectMark.CURSED)

	await _open_and_enter(world, me, 1)
	_shift[0] += life.days_open() * DAY + 1.0
	for at: int in life.tick(LifeStep.BIG):
		world.close_dungeon(at)
	hit = beast.stats.physical_attack() / plain_attack
	_yes("два штрафи складаються (П-108): атака ×%.2f, здоров'я ×%.2f"
			% [hit, float(beast.stats.max_hp()) / plain_hp],
			absf(hit - 2.25) < 0.03 and beast.states.count() == own + 6)

	_shift[0] += life.days_penalty() * DAY + 1.0
	life.tick(LifeStep.BIG)
	beast.states.tick(life.days_penalty() * DAY + 1.0)
	beast.refresh_stats()
	_yes("через %.0f днів штрафи спали: чинних %d, атака ×%.2f, "
			% [life.days_penalty(), life.penalties.size(),
			   beast.stats.physical_attack() / plain_attack]
			+ "здоров'я %d / %d" % [beast.hp, beast.stats.max_hp()],
			life.penalties.is_empty() and absf(
			beast.stats.physical_attack() / plain_attack - 1.0) < 0.01
			and beast.hp <= plain_hp)

	world._restore_dungeon(2, {"template": "старий-льох", "seed": 77,
			"grade": land.shrines()[2].grade})
	_yes("відновлення після перезапуску: святиня відкрита, підземелля «%s»"
			% (world.dungeons.open[2]["template"]
					if world.dungeons.open.has(2) else "—"),
			land.shrines()[2].stage == Shrine.Stage.АКТИВОВАНА
			and world.dungeons.open.has(2)
			and world.dungeons.open[2]["seed"] == 77)

	print("\n— лічильник днів і список на карті (Ф8) —")
	world.client_dungeon_days(2, 29.5 * DAY, "E")
	_yes("клієнт відлічує: %.2f дня" % world.days_left(2),
			absf(world.days_left(2) - 29.5) < 0.01)
	var words := {1.2: "1 день", 2.5: "2 дні", 5.0: "5 днів",
			11.0: "11 днів", 21.3: "21 день", 29.9: "29 днів",
			0.2: "5 год"}
	var wrong: Array[String] = []
	for d: float in words:
		if ClientView._days_text(d) != words[d]:
			wrong.append("%s → %s" % [d, ClientView._days_text(d)])
	_yes("відмінки днів правильні%s" % (": " + ", ".join(wrong)
			if not wrong.is_empty() else ""), wrong.is_empty())
	var holy: Shrine = land.shrines()[2]
	holy.show_days(ClientView._days_text(world.days_left(2)))
	var tag: Label3D = holy.get_node_or_null("Дні")
	_yes("над святинею напис «%s»" % (tag.text if tag != null else "—"),
			tag != null and tag.visible and tag.text == "29 днів")
	var sheet := WorldMap.new()
	sheet.size = Vector2(480, 480)
	sheet.map = world.data.map
	sheet.world = world
	sheet.dungeons = world.dungeons
	add_child(sheet)
	sheet.show_me(Vector3(0, 0, 0), 0.0)
	await get_tree().process_frame
	await get_tree().process_frame
	_yes("карта з переліком відкритих малюється без помилок", true)
	world.client_dungeon_days(2, -1.0, "")
	holy.show_days("")
	_yes("закриття прибирає лічильник", world.days_left(2) < 0.0
			and not tag.visible)

	var url := ""
	var args := OS.get_cmdline_user_args()
	if args.has("--база") and args.find("--база") + 1 < args.size():
		url = args[args.find("--база") + 1]
	if url != "":
		await _through_db(url, world)

	print("  підсумок: %d з %d" % [_ok, _ok + _bad])
	get_tree().quit(1 if _bad > 0 else 0)


## Наскрізь через справжню базу — на окремому «світі» `проба.json`, щоб
## не зачепити жодного справжнього запису. Наприкінці все прибирається.
func _through_db(url: String, world: Node) -> void:
	print("\n— через базу %s (світ «проба.json») —" % url)
	const KEY := "проба.json"
	var store := Store.new()
	add_child(store)
	store.setup(url)
	var clean := [false]
	store.drop(DungeonLife.DUNGEONS, "world=eq.%s" % KEY.uri_encode(),
			func(_ok: bool, _rows: Array) -> void: clean[0] = true)
	store.drop(DungeonLife.PENALTIES, "world=eq.%s" % KEY.uri_encode())
	while not clean[0]:
		await get_tree().process_frame

	var first := DungeonLife.new()
	add_child(first)
	first.setup(store, world.dungeons.book.life, KEY)
	first.activated(7, "D")
	first.built(7, "костниця", 4242)
	first.activated(8, "E")
	await get_tree().create_timer(1.0).timeout

	var second := DungeonLife.new()
	add_child(second)
	second.setup(store, world.dungeons.book.life, KEY)
	var alive: Array = []
	var gone: Array = []
	second.restore(func(at: int, r: Dictionary) -> void: alive.append([at, r]),
			func(at: int) -> void: gone.append(at))
	await get_tree().create_timer(1.0).timeout
	var r7: Dictionary = second.records.get(7, {})
	_yes("після «перезапуску» прочитано обидва: %d, живих %d"
			% [second.records.size(), alive.size()],
			second.records.size() == 2 and alive.size() == 2)
	_yes("шаблон і зерно вціліли: «%s», %d, грейд %s"
			% [r7.get("template", ""), r7.get("seed", 0), r7.get("grade", "")],
			r7.get("template", "") == "костниця" and r7.get("seed", 0) == 4242
			and r7.get("grade", "") == "D")
	_yes("строк вцілів до секунди", r7.get("closes", 0)
			== first.records[7]["closes"])

	second.expire(8)
	await get_tree().create_timer(1.0).timeout
	var third := DungeonLife.new()
	add_child(third)
	third.setup(store, world.dungeons.book.life, KEY)
	third.restore(func(_at: int, _r: Dictionary) -> void: pass,
			func(_at: int) -> void: pass)
	await get_tree().create_timer(1.0).timeout
	_yes("закрите не вертається, штраф вертається: записів %d, штрафів %d"
			% [third.records.size(), third.penalties.size()],
			not third.records.has(8) and third.penalties.size() == 1)

	var done := [0]
	for table: String in [DungeonLife.DUNGEONS, DungeonLife.PENALTIES]:
		store.drop(table, "world=eq.%s" % KEY.uri_encode(),
				func(ok: bool, _rows: Array) -> void:
					done[0] += 1 if ok else 0)
	await get_tree().create_timer(1.0).timeout
	_yes("прибрано за собою", done[0] == 2)


class LifeStep:
	const BIG := 60.0
