class_name Summons
extends RefCounted
## Прикликані істоти (П-41): з'являються від скіла, б'ються за господаря,
## розсипаються за строком.
##
## Живе на СЕРВЕРІ. Прикликаний — звичайний `Mob` (модель, стати, рух —
## усе те саме) з `owner_id` господаря; бік йому дає `Combat.side`, а
## думає він тут, не в `MobAI`: монстр шукає жертву серед гравців, а
## прикликаний — ціль свого господаря.
##
## Що саме кличе який скіл — поле «прикликає» в `data/skills.json`
## (`tools/profesii.py → ПРИКЛИКАННЯ`). Вибір видів і чисел — пропозиція
## виконавця, форк П-251.

## Номери прикликаних — окремий діапазон: спавнер іде від −1 униз по
## одному, і до мільйона йому не дійти.
const FIRST_ID := -1000000
## Ближче за це до господаря не підходить — стоїть поруч, не в ньому.
const FOLLOW := 3.0
## Ціль далі за це від господаря прикликаний покидає: не біжить за
## монстром через пів карти, поки господар стоїть.
const LEASH := 25.0
## Господар відійшов далі за це (телепорт, підземелля) — прикликаний
## з'являється біля нього знову, а не біжить крізь світ.
const CATCH_UP := 40.0

var _creatures: Dictionary
var _combat: Combat
var _data: GameData
## (id, позиція) -> вузол; (id) -> void. Вузли створює й прибирає світ.
var _spawn: Callable
var _remove: Callable
var _made := 0
## Прохання, що прийшли від скіла. Ставимо їх у `tick`, не одразу: скіл
## дочитується посеред обходу `creatures` (`Combat.tick_casts`), а
## додавати й прибирати записи словника під час обходу не можна.
var _asked: Array = []


func _init(creatures: Dictionary, combat: Combat, data: GameData,
		spawn: Callable, remove: Callable) -> void:
	_creatures = creatures
	_combat = combat
	_data = data
	_spawn = spawn
	_remove = remove


func is_summon(id: int) -> bool:
	var c: Node = _creatures.get(id)
	return id < 0 and c != null and "owner_id" in c and int(c.owner_id) > 0


## Прикликані цього господаря.
func of_owner(owner: int) -> Array:
	var out: Array = []
	for id: int in _creatures:
		if is_summon(id) and int(_creatures[id].owner_id) == owner:
			out.append(id)
	return out


## Прикликати за даними скіла. Старі цього господаря розсипаються: нове
## читання — це нові, а не ще стільки ж зверху. Повертає номери.
func call_up(owner: int, what: Dictionary) -> Array:
	var master: Node3D = _creatures.get(owner)
	if master == null or not master.is_alive():
		return []
	var kind := int(what.get("вид", 0))
	var row: Dictionary = _data.for_kind(kind)
	if row.is_empty():
		push_warning("[прикликання] виду %d немає в mobs.json" % kind)
		print("[прикликання] ‼ виду %d немає в mobs.json" % kind)
		return []
	dismiss(owner)
	var count := maxi(1, int(what.get("скільки", 1)))
	var made: Array = []
	for i in count:
		_made += 1
		var id := FIRST_ID - _made
		# Півколом за спиною господаря, щоб не з'являтись у ньому.
		var angle := master.rotation.y + PI + (i - (count - 1) * 0.5) * 0.9
		var at: Vector3 = master.global_position \
				+ Vector3(sin(angle), 0.0, cos(angle)) * 1.8
		var m: Node3D = _spawn.call(id, at)
		m.setup(at, kind, false, row)
		m.owner_id = owner
		m.summon_left = float(what.get("строк", 60.0))
		_fit_to(m, master, int(row.get("рівень", 1)))
		made.append(id)
	_combat.report(owner, "[прикликання] %d прикликав %s ×%d на %.0f с"
			% [owner, row.get("назва", "?"), count,
			   float(what.get("строк", 60.0))])
	return made


## Сила — під рівень господаря, а не виду: голем 43 рівня біля некроманта
## 52-го інакше був би слабший за кожного монстра довкола. Стати виду
## множаться на відношення рівнів; рівень стає господаревим.
func _fit_to(m: Node, master: Node, kind_level: int) -> void:
	var times := float(maxi(1, master.level)) / float(maxi(1, kind_level))
	m.base_stats.strength = maxi(1, roundi(m.base_stats.strength * times))
	m.base_stats.stamina = maxi(1, roundi(m.base_stats.stamina * times))
	m.base_stats.agility = maxi(1, roundi(m.base_stats.agility * times))
	m.level = master.level
	m.refresh_stats()
	m.hp = m.stats.max_hp()
	m.mp = m.stats.max_mp()


## Скіл когось прикликав — поставимо на наступному `tick`.
func request(owner: int, what: Dictionary) -> void:
	_asked.append([owner, what])


func dismiss(owner: int) -> void:
	for id: int in of_owner(owner):
		_remove.call(id)


## Кожен кадр сервера.
func tick(delta: float) -> void:
	var asked := _asked
	_asked = []
	for one: Array in asked:
		call_up(int(one[0]), one[1])
	for id: int in _creatures.keys():
		if not is_summon(id):
			continue
		var m: Node3D = _creatures[id]
		var master: Node3D = _creatures.get(int(m.owner_id))
		m.summon_left -= delta
		var gone: bool = m.summon_left <= 0.0 or master == null \
				or not master.is_alive()
		if gone and m.is_alive():
			_remove.call(id)
			continue
		if not m.is_alive():
			continue          # труп прибере `Combat.clear_corpses`
		_think(id, m, master)


func _think(id: int, m: Node3D, master: Node3D) -> void:
	if m.global_position.distance_to(master.global_position) > CATCH_UP:
		m.place_at(master.global_position + Vector3(1.5, 0, 0), m.facing)
	var target := _target_for(m, master)
	m.target_id = target
	if target == 0:
		var far: float = m.global_position.distance_to(master.global_position)
		if far > FOLLOW:
			m.head_to(master.global_position, 1.0)
		else:
			m.wanted = Vector2.ZERO
		return
	var victim: Node3D = _creatures[target]
	if m.global_position.distance_to(victim.global_position) > m.ATTACK_RANGE:
		m.head_to(victim.global_position, 1.0)
		return
	m.wanted = Vector2.ZERO
	m.face_point(victim.global_position)
	_combat.attack(id)


## Кого бити: ціль господаря, якщо це ворог; інакше — того, з ким уже
## б'ється, доки той живий і недалеко від господаря. Гравців — ніколи.
func _target_for(m: Node3D, master: Node3D) -> int:
	for want: int in [int(master.target_id), int(m.target_id)]:
		if want == 0 or _combat.side(want) > 0:
			continue
		var c: Node3D = _creatures.get(want)
		if c == null or not c.is_alive():
			continue
		if c.global_position.distance_to(master.global_position) > LEASH:
			continue
		return want
	return 0
