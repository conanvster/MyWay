extends Node
## Активація святині ключем (П-153, Ф3) — числами, без рук і без мережі.
##
## Ганяти так (сценою, бо потрібні автозавантаження):
##     godot --headless --path game res://scenes/shrine_key.tscn
##
## Перевіряє рівно те, що замовник назвав словами:
##   · без ключа — відмова «немає ключа відповідного рівня»
##   · з ключем НЕ ТОГО грейду — та сама відмова
##   · поки охорона жива — активувати не можна взагалі
##   · задалеко — не можна
##   · з правильним ключем — святиня активується, ключ ЗНИКАЄ з торби,
##     і поруч запалюється портал (окрема сутність, не сама святиня)
##
## Чому не через `--демо`: показ не носить ключів і не ходить до
## святинь, а вигадувати йому маршрут дорожче, ніж покликати серверні
## перевірки напряму. Мережі тут немає — гонця підставляємо свого, як і
## в решті проб, а саму перевірку кличемо через `activate_shrine()`, а
## не через `@rpc`: поза справжнім викликом `get_remote_sender_id()`
## дає 0, і проба перевіряла б порожнечу.

const MAIN := preload("res://scenes/main.tscn")

var _said: Array[String] = []
var _ok := 0
var _bad := 0


## Гонець, який нічого не шле, а записує — той самий прийом, що в
## `probes/step1.gd`.
class Recorder extends Messenger:
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


func _mobs(world: Node) -> int:
	var n := 0
	for id: int in world.creatures:
		if id < 0:
			n += 1
	return n


## Портал → підземелля → вихід (П-190): числами, без вікна.
func _dungeon(world: Node, me: Node, shrine: Shrine, gate: Portal, at: int,
		post: Recorder) -> void:
	print("\n— портал у підземелля (П-190) —")
	var dungeons: Dungeons = world.dungeons
	me.hp = maxi(me.hp, 50)

	me.global_position = gate.global_position + Vector3(20, 0, 0)
	post.said.clear()
	world.enter_dungeon(1, at)
	_yes("задалеко від кола не пускає: «%s»" % ", ".join(post.said),
			not dungeons.open.has(at))

	var before := _mobs(world)
	me.global_position = gate.global_position + Vector3(0.5, 0, 0.5)
	post.said.clear()
	world.enter_dungeon(1, at)
	await get_tree().process_frame
	_yes("підземелля відкрилось: «%s»" % ", ".join(post.said),
			dungeons.open.has(at))
	if not dungeons.open.has(at):
		return
	var pos: Vector3 = me.global_position
	_yes("гравця перенесено всередину (%.0f, %.0f, %.0f)"
			% [pos.x, pos.y, pos.z], dungeons.index_at(pos.x, pos.z) == at)
	var below: float = world.ground_at(pos.x, pos.z)
	_yes("земля під ним — підлога підземелля (%.2f, гравець %.2f)"
			% [below, pos.y], absf(pos.y - 1.0 - below) < 0.01)
	_yes("вище за море — не тоне (%.1f)" % pos.y, pos.y > 10.0)
	var after := _mobs(world)
	_yes("заселено: монстрів %d → %d" % [before, after], after > before)
	var bad_spawn := 0
	for id: int in world.creatures:
		if id >= 0:
			continue
		var m: Node3D = world.creatures[id]
		if dungeons.index_at(m.global_position.x, m.global_position.z) == at \
				and m.global_position.y < below - 20.0:
			bad_spawn += 1
	_yes("жоден монстр не під підлогою (%d)" % bad_spawn, bad_spawn == 0)

	var entry: Dictionary = dungeons.open[at]
	var exit: Portal = entry["exit"]
	me.global_position = exit.global_position + Vector3(0.4, 0.5, 0)
	post.said.clear()
	world.leave_dungeon(1)
	pos = me.global_position
	_yes("вийшов біля святині (%.0f м від неї): «%s»"
			% [pos.distance_to(shrine.global_position), ", ".join(post.said)],
			dungeons.index_at(pos.x, pos.z) < 0
			and pos.distance_to(shrine.global_position) < 15.0)

	var was_seed: int = entry["seed"]
	var mobs_was := _mobs(world)
	me.global_position = gate.global_position
	world.enter_dungeon(1, at)
	_yes("вдруге — те саме підземелля (зерно %d), не нове, монстрів не додано"
			% was_seed, int(dungeons.open[at]["seed"]) == was_seed
			and _mobs(world) == mobs_was)


func _go() -> void:
	await get_tree().process_frame
	var data := GameData.new()
	data.load_all()
	var world: Node3D = MAIN.instantiate()
	get_tree().root.add_child(world)
	await get_tree().process_frame
	var land: Node = world.get_node("Landscape")
	land.build(data.map)
	await get_tree().process_frame

	var all: Array = land.shrines()
	print("\n— активація святині ключем (П-153) —")
	if all.is_empty():
		print("  ‼ у мапі немає жодної святині")
		get_tree().quit(1)
		return

	# Беремо святиню й ставимо гравця впритул.
	var at := 0
	var shrine: Shrine = all[at]
	var post := Recorder.new(world, null)
	world.link = post
	var me: Node = world.spawn(1, shrine.global_position + Vector3(1.5, 0, 0))
	me.items = {}
	await get_tree().process_frame

	print("  святиня %d: форма «%s», грейд %s"
			% [at, shrine.form, shrine.grade])
	var key := "ключ святині %s" % shrine.grade

	# 1. Охорона ще жива — активувати не можна взагалі.
	shrine.set_stage(Shrine.Stage.ПІД_ОХОРОНОЮ)
	me.items[key] = 1
	post.said.clear()
	world.activate_shrine(1, at)
	_yes("під охороною не активується: «%s»"
			% ", ".join(post.said),
			shrine.stage == Shrine.Stage.ПІД_ОХОРОНОЮ)

	# 2. Зачищена, але ключа немає.
	shrine.set_stage(Shrine.Stage.ЗАЧИЩЕНА)
	me.items.erase(key)
	post.said.clear()
	world.activate_shrine(1, at)
	_yes("без ключа відмовляє словами замовника: «%s»"
			% ", ".join(post.said),
			shrine.stage == Shrine.Stage.ЗАЧИЩЕНА
			and post.said.has("немає ключа відповідного рівня"))

	# 3. Ключ є, але не того грейду.
	var other := "SS" if shrine.grade != "SS" else "E"
	me.items["ключ святині %s" % other] = 3
	post.said.clear()
	world.activate_shrine(1, at)
	_yes("чужий грейд (%s замість %s) не підходить: «%s»"
			% [other, shrine.grade, ", ".join(post.said)],
			shrine.stage == Shrine.Stage.ЗАЧИЩЕНА)

	# 4. Задалеко.
	me.items[key] = 1
	me.global_position = shrine.global_position + Vector3(40, 0, 0)
	post.said.clear()
	world.activate_shrine(1, at)
	_yes("задалеко не активується: «%s»" % ", ".join(post.said),
			shrine.stage == Shrine.Stage.ЗАЧИЩЕНА)

	# 5. Усе як треба.
	me.global_position = shrine.global_position + Vector3(1.5, 0, 0)
	post.said.clear()
	world.activate_shrine(1, at)
	await get_tree().process_frame
	_yes("з правильним ключем активується: «%s»" % ", ".join(post.said),
			shrine.stage == Shrine.Stage.АКТИВОВАНА)
	_yes("ключ витрачено (у торбі %d)" % int(me.items.get(key, 0)),
			int(me.items.get(key, 0)) == 0)
	_yes("чужі ключі не зачепило (%s: %d)"
			% [other, int(me.items.get("ключ святині %s" % other, 0))],
			int(me.items.get("ключ святині %s" % other, 0)) == 3)
	var gate: Portal = shrine.portal()
	_yes("портал запалено окремою сутністю", gate != null)
	if gate != null:
		_yes("портал того самого грейду (%s)" % gate.grade,
				gate.grade == shrine.grade)
		var ground: float = maxf(land.height_at(gate.global_position.x,
				gate.global_position.z), land.sea_level())
		_yes("портал стоїть на землі, не в ґрунті (коло %.2f, земля %.2f)"
				% [gate.global_position.y, ground],
				absf(gate.global_position.y - ground) < 0.05)
		var worst := 0.0
		for each: Shrine in all:
			var spot := each.position + Shrine.PORTAL_AT
			var under: float = maxf(land.height_at(spot.x, spot.z),
					land.sea_level())
			worst = maxf(worst, absf(each.position.y + each.portal_lift
					- under))
		_yes("усі %d порталів лягли б на землю (найбільша розбіжність %.3f м)"
				% [all.size(), worst], worst < 0.05)
		var inside := gate.global_position + Vector3(0.5, 0, 0.5)
		_yes("у коло можна зайти, і запрошення показується раз",
				gate.entered(1, inside) and not gate.entered(1, inside))

	# 6. Двічі не активується.
	me.items[key] = 1
	post.said.clear()
	world.activate_shrine(1, at)
	_yes("вдруге не активується, ключ цілий (%d): «%s»"
			% [int(me.items.get(key, 0)), ", ".join(post.said)],
			int(me.items.get(key, 0)) == 1)

	# 7. Вхід у підземелля за порталом (П-190, Ф4′).
	if gate != null:
		await _dungeon(world, me, shrine, gate, at, post)

	print("\n  пройдено %d · провалено %d" % [_ok, _bad])
	get_tree().quit(1 if _bad > 0 else 0)
