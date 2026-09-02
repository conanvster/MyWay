class_name Vision
extends RefCounted
## Зона бачення: хто кого бачить (П-43).
##
## Тут немає жодного `rpc`. Клас лише рахує, що змінилося для одного
## з'єднання, і повертає це списками; розсилає вже `world.gd`. Так зону
## бачення можна перевірити пробою на голих числах, без мережі.
##
## Гістерезис: щоб на самій межі персонаж не блимав щокадру, зникає він
## далі, ніж з'являється — межа появи `sense`, межа зникнення на 12%
## більша (Creature.VISION_HYSTERESIS).

## Кого кожне з'єднання зараз бачить: peer_id -> { чужий_id: true }.
var _seen: Dictionary = {}
var _creatures: Dictionary


func _init(creatures: Dictionary = {}) -> void:
	_creatures = creatures


## Нове з'єднання. Себе гравець бачить завжди — решту роздасть звірка.
func watch(peer: int) -> void:
	_seen[peer] = {peer: true}


## З'єднання пішло: більше нічого не бачить.
func drop_watcher(peer: int) -> void:
	_seen.erase(peer)


## Істота зникла зі світу. Викреслює її з усіх списків і повертає тих,
## хто її бачив, — саме їм треба сказати `client_despawn`.
func forget(id: int) -> Array:
	var was: Array = []
	for peer in _seen:
		if _seen[peer].erase(id):
			was.append(peer)
	return was


func sees(peer: int, id: int) -> bool:
	return _seen.get(peer, {}).has(id)


## Хто бачить цю істоту. Порядок довільний.
func watchers_of(id: int) -> Array:
	var who: Array = []
	for peer in _seen:
		if _seen[peer].has(id):
			who.append(peer)
	return who


## Кого бачить це з'єднання. Для перебору цілей (П-31).
func seen_by(peer: int) -> Dictionary:
	return _seen.get(peer, {})


## Звірка для одного з'єднання. Повертає:
##     appeared — кого щойно побачив,
##     gone     — кого щойно втратив,
##     snapshot — позиції всіх видимих: xyz позиція, w поворот.
##
## Одним `Vector4` замість словника з двох полів, щоб не слати другого
## словника на кожен тік (П-81).
func update(peer: int) -> Dictionary:
	var watcher: Node3D = _creatures.get(peer)
	if watcher == null:
		return {"appeared": [], "gone": [], "snapshot": {}}

	var seen: Dictionary = _seen.get(peer, {})
	var near: float = watcher.vision_radius()
	var far: float = near * watcher.VISION_HYSTERESIS

	var appeared: Array = []
	var gone: Array = []
	var snapshot := {}
	for id in _creatures:
		var other: Node3D = _creatures[id]
		var dist := watcher.global_position.distance_to(other.global_position)
		# Поріг залежить від того, чи бачили досі.
		var visible: bool = dist <= (far if seen.has(id) else near)
		if id == peer:
			visible = true

		if visible:
			if not seen.has(id):
				seen[id] = true
				appeared.append(id)
			snapshot[id] = Vector4(other.global_position.x,
					other.global_position.y, other.global_position.z,
					other.facing)
		elif seen.has(id):
			seen.erase(id)
			gone.append(id)

	_seen[peer] = seen
	return {"appeared": appeared, "gone": gone, "snapshot": snapshot}
