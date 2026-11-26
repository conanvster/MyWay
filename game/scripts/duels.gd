class_name Duels
extends Node3D
## Погоджений PvP — виклик і арена (П-259, П-260, П-74).
##
## Слово замовника 10.10.2026: гравець кличе гравця вікном згоди (як на
## обмін); погодились — обох переносить на арену порталом, як у
## підземелля; там речі не губляться (П-259); після бою — назад, кожного
## туди, звідки його покликали.
##
## Що лишилось відкритим і взято за рекомендацією, поки замовник не
## сказав інакше (`spec/план.md`, Р-5):
## - на арені двоє — той, хто кличе, і той, кого кличуть (П-260, залишок);
## - повага за смерть на арені знімається, як за будь-яку (П-27): рішення
##   сказало лише «не втрачаючи речей» (П-260, залишок);
## - на відповідь 30 с, мовчання — те саме, що «ні», виклик згасає (П-74,
##   залишок; так само вже поводиться запрошення до обміну).
##
## Живе однаково на сервері й у клієнта, як `Dungeons`: арена — це лише
## номер місця, а з номера обидва будують ту саму підлогу й стіни
## (серверові — зіткнення, клієнтові — картинка). Хто з ким б'ється й
## що кому сказати, веде лише сервер.

## Де стоять арени: рядком на захід від підземель (ті — від x = 0 на
## схід, z = −9000 і глибше), за 5 км від обох світів. Висота — як у
## підземель: море світу рахує «під водою» за висотою.
const ORIGIN := Vector3(-9000.0, 40.0, -9000.0)
const APART := 200.0
## Півсторони квадрата арени й висота стін, м. Числа виконавця (P5).
const HALF := 15.0
const WALL := 4.0
## Скільки від середини ставити кожного: 16 м між бійцями — ще не в
## ударі, уже видно одне одного.
const START_GAP := 8.0
## Скільки чекає виклик (П-74, залишок: як у запрошення до обміну).
const INVITE_TIME := Trade.INVITE_TIME
## Кликати можна лише поруч — те саме «поруч», що в обміні.
const RANGE := Trade.RANGE
## Найдовший бій: вийшов час — нічия, обох назад (P5).
const FIGHT_TIME := 180.0
## Скільки стояти на арені після кінця бою, перш ніж повернуло (P5):
## щоб переможець побачив, що переміг, а не стрибнув за кадр.
const RETURN_AFTER := 5.0

## Кого кличуть -> {"від", "лишилось"}.
var _invites: Dictionary = {}
## Місце арени -> {"хто": [a, b], "назад": {id: Vector3}, "лишилось": с,
## "кінець": с до повернення (від'ємне — бій іде), "переміг": id або 0}.
var _duels: Dictionary = {}
## Гравець -> місце арени.
var _slot_of: Dictionary = {}
## Місце -> збудований вузол арени.
var _built: Dictionary = {}
var names: Dictionary = {}
## Гонець для журналу подій. Світ підставляє свого; без нього рядок
## іде лише в консоль, як і було.
var link: Messenger = Messenger.new()


func _name(id: int) -> String:
	return str(names.get(id, "гравець %d" % id))


static func spot_for(slot: int) -> Vector3:
	return ORIGIN + Vector3(-float(slot) * APART, 0.0, 0.0)


## Де ставити бійця: перший — на захід від середини, другий — на схід.
static func start_point(slot: int, side: int) -> Vector3:
	var x := -START_GAP if side == 0 else START_GAP
	return spot_for(slot) + Vector3(x, 1.0, 0.0)


## На якій арені точка, або −1. Будь-яке місце рядка, не лише відкрите:
## підлога потрібна й тому, хто вже стоїть там, коли арену ще будують.
static func slot_at(x: float, z: float) -> int:
	var slot := roundi((ORIGIN.x - x) / APART)
	if slot < 0:
		return -1
	var c := spot_for(slot)
	if absf(x - c.x) > HALF or absf(z - c.z) > HALF:
		return -1
	return slot


## Висота підлоги арени, або NAN — тут арени немає.
func floor_at(x: float, z: float) -> float:
	return ORIGIN.y if slot_at(x, z) >= 0 else NAN


func in_duel(id: int) -> bool:
	return _slot_of.has(id)


func opponent(id: int) -> int:
	if not _slot_of.has(id):
		return 0
	for one: int in _duels[_slot_of[id]]["хто"]:
		if one != id:
			return one
	return 0


## Чи це погоджений бій (П-259): обидва на одній арені, і бій ще йде.
## Цим `Combat.agreed_pvp` відрізняє арену від флагу.
func agreed(a: int, b: int) -> bool:
	if not _slot_of.has(a) or _slot_of.get(b, -1) != _slot_of[a]:
		return false
	return float(_duels[_slot_of[a]]["кінець"]) < 0.0


## Чому цим двом зараз не можна битися. Порожньо — можна.
func why_not(a: Node, b: Node, from: int, to: int) -> String:
	if a == null or b == null or to <= 0:
		return "на арену кличуть лише гравців"
	if a == b:
		return "сам із собою не б'ються"
	if a.hp <= 0 or b.hp <= 0:
		return "мертві не б'ються"
	if a.in_fight > 0.0 or b.in_fight > 0.0:
		return "у бою не кличуть"
	if in_duel(from):
		return "ти вже на арені"
	if in_duel(to):
		return "%s уже на арені" % _name(to)
	if a.global_position.distance_to(b.global_position) > RANGE:
		return "задалеко для виклику: підійди ближче"
	return ""


## А кличе Б. Порожньо — виклик пішов.
func invite(from: int, to: int, a: Node, b: Node) -> String:
	var why := why_not(a, b, from, to)
	if why != "":
		return why
	if _invites.has(to):
		return "%s уже має виклик — хай відповість" % _name(to)
	_invites[to] = {"від": from, "лишилось": INVITE_TIME}
	return ""


func invited_by(to: int) -> int:
	return int(_invites[to]["від"]) if _invites.has(to) else 0


func decline(to: int) -> void:
	_invites.erase(to)


## Б погодився. Повертає {"місце": n} або {"чому": текст}. Переносить
## світ — тут лише хто де стоїть і куди їх потім вертати.
func accept(to: int, a: Node, b: Node) -> Dictionary:
	var from := invited_by(to)
	_invites.erase(to)
	if from == 0:
		return {"чому": "виклик уже згас"}
	var why := why_not(a, b, from, to)
	if why != "":
		return {"чому": why}
	var slot := 0
	while _duels.has(slot):
		slot += 1
	_duels[slot] = {
		"хто": [from, to],
		"назад": {from: a.global_position, to: b.global_position},
		"лишилось": FIGHT_TIME,
		"кінець": -1.0,
		"переміг": 0,
	}
	_slot_of[from] = slot
	_slot_of[to] = slot
	link.report(from, "[арена] %s проти %s, місце %d" % [_name(from), _name(to), slot])
	# В-12: де сервер запам'ятав кожного — з цим звіряє клієнт.
	print("[арена] назад запам'ятав: %d (%.1f, %.1f), %d (%.1f, %.1f)"
			% [from, a.global_position.x, a.global_position.z,
			   to, b.global_position.x, b.global_position.z])
	return {"місце": slot, "хто": [from, to]}


## Боєць загинув. Повертає переможця (0 — це не бій на арені або вже
## скінчений).
func on_death(id: int) -> int:
	if not _slot_of.has(id):
		return 0
	var duel: Dictionary = _duels[_slot_of[id]]
	if float(duel["кінець"]) >= 0.0:
		return 0
	var winner := opponent(id)
	duel["кінець"] = RETURN_AFTER
	duel["переміг"] = winner
	link.report(winner, "[арена] %s переміг %s" % [_name(winner), _name(id)])
	return winner


## Гравець вийшов із гри. Повертає, куди його поставити ДО збереження
## (інакше зайде посеред порожньої арени), або null. Суперник перемагає.
func forget(id: int) -> Variant:
	_invites.erase(id)
	for to: int in _invites.keys():
		if int(_invites[to]["від"]) == id:
			_invites.erase(to)
	if not _slot_of.has(id):
		return null
	var slot: int = _slot_of[id]
	var duel: Dictionary = _duels[slot]
	var back: Vector3 = duel["назад"][id]
	if float(duel["кінець"]) < 0.0:
		duel["кінець"] = RETURN_AFTER
		duel["переміг"] = opponent(id)
	duel["хто"].erase(id)
	_slot_of.erase(id)
	return back


## Час іде. Повертає, що світові зробити:
## - "прострочені": [[хто кликав, кого]] — виклик згас без відповіді;
## - "нічия": [[a, b]] — вийшов час бою;
## - "назад": [[id, Vector3]] — повернути туди, звідки покликали.
func tick(delta: float) -> Dictionary:
	var out := {"прострочені": [], "нічия": [], "назад": []}
	for to: int in _invites.keys():
		_invites[to]["лишилось"] = float(_invites[to]["лишилось"]) - delta
		if _invites[to]["лишилось"] <= 0.0:
			out["прострочені"].append([int(_invites[to]["від"]), to])
			_invites.erase(to)
	for slot: int in _duels.keys():
		var duel: Dictionary = _duels[slot]
		if float(duel["кінець"]) < 0.0:
			duel["лишилось"] = float(duel["лишилось"]) - delta
			if duel["лишилось"] <= 0.0:
				duel["кінець"] = RETURN_AFTER
				out["нічия"].append(duel["хто"].duplicate())
				print("[арена] місце %d: вийшов час — нічия" % slot)
			continue
		duel["кінець"] = float(duel["кінець"]) - delta
		if duel["кінець"] > 0.0:
			continue
		for id: int in duel["хто"]:
			out["назад"].append([id, duel["назад"][id]])
			_slot_of.erase(id)
		_duels.erase(slot)
	return out


## Збудувати арену на місці `slot` (або нічого, якщо вже стоїть): плита
## підлоги й чотири стіни. Однаково на сервері й у клієнта.
func raise(slot: int) -> Node3D:
	if _built.has(slot):
		return _built[slot]
	var arena := Node3D.new()
	arena.name = "Арена%d" % slot
	add_child(arena)
	arena.position = spot_for(slot)
	var side := HALF * 2.0
	_box(arena, Vector3(side + 2.0, 1.0, side + 2.0), Vector3(0, -0.5, 0),
			Color(0.42, 0.36, 0.28))
	for dir: Vector3 in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD,
			Vector3.BACK]:
		var along_x := dir.z != 0.0
		var size := Vector3(side + 2.0, WALL, 1.0) if along_x \
				else Vector3(1.0, WALL, side + 2.0)
		_box(arena, size, dir * (HALF + 0.5) + Vector3(0, WALL * 0.5, 0),
				Color(0.30, 0.27, 0.24))
	_built[slot] = arena
	return arena


func _box(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = at
	var holder := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	holder.shape = shape
	body.add_child(holder)
	var look := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var paint := StandardMaterial3D.new()
	paint.albedo_color = color
	paint.roughness = 0.9
	mesh.material = paint
	look.mesh = mesh
	body.add_child(look)
	parent.add_child(body)


## Відкриті арени — щоб гравець, що щойно зайшов, бачив ту, на яку його
## можуть покликати, такою ж, як усі.
func open_slots() -> Array:
	return _duels.keys()
