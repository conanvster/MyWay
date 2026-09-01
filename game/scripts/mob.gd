extends Creature
## Монстр.
##
## На кроці 9 він СТОЇТЬ: не ходить, не переслідує. Б'ється у відповідь
## — б'є того, хто підійшов на дальність удару. Переслідування, блукання
## і зграї це окреме питання (П-66).

## Кого монстр помітить. Менше, ніж у гравця: інакше він реагував би
## на те, чого гравець ще не бачить.
const NOTICE_RANGE := 12.0


func _ready() -> void:
	# Заглушка до балансування: трохи слабший за гравця.
	stats.strength = 7
	stats.stamina = 4
	stats.agility = 7
	super()


## Кого бити зараз. Повертає 0, якщо нікого.
func pick_victim(players: Dictionary) -> int:
	if not is_alive():
		return 0
	var best := 0
	var best_dist := NOTICE_RANGE
	for id in players:
		var p: Node3D = players[id]
		if not p.is_alive():
			continue
		var d := global_position.distance_to(p.global_position)
		if d < best_dist:
			best_dist = d
			best = id
	return best
