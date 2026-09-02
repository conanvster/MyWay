class_name State
extends RefCounted
## Один стан: баф або дебаф.
##
## Стан завжди має строк (погоджено 02.09.2026) — вічних бафів немає ні в
## гравця, ні в монстра. Строк веде сервер; клієнт лише показує.
##
## Що стан міняє, задається парою: ім'я поля в `Stats` і множник. 1,2 —
## на п'ятину більше, 0,8 — на п'ятину менше. Множник, а не додаток,
## обрано тому, що так баф і дебаф на той самий стат гасять одне одного
## самі: 1,2 × 0,8 = 0,96 (П-108).

## Ім'я стану. Однакові не складаються, а поновлюють строк — тому воно й
## потрібне.
var name := ""
## Яке поле `Stats` міняє: "agility", "sense", "strength"…
var stat := ""
## Множник до цього поля.
var factor := 1.0
## Скільки ще триває, у секундах.
var left := 0.0
## Скільки тривав від початку — щоб показувати смужку.
var full := 0.0


func _init(of_name: String = "", of_stat: String = "", of_factor: float = 1.0,
		seconds: float = 0.0) -> void:
	name = of_name
	stat = of_stat
	factor = of_factor
	left = seconds
	full = seconds


## Стан із даних: {"назва", "стат", "множник", "строк"}.
## Строк 0 або менше означає «поки живий» — саме такий постійний баф
## монстр отримує при появі (погоджено 02.09.2026).
static func from_data(data: Dictionary) -> State:
	var seconds := float(data.get("строк", 0.0))
	var state := State.new(
			data.get("назва", "стан"),
			data.get("стат", ""),
			float(data.get("множник", 1.0)),
			seconds if seconds > 0.0 else INF)
	if seconds <= 0.0:
		state.full = INF
	return state


func is_forever() -> bool:
	return is_inf(left)


func is_buff() -> bool:
	return factor > 1.0


## Скільки лишилось, часткою від строку: 1,0 щойно повішений, 0,0 кінець.
func share() -> float:
	if is_forever():
		return 1.0
	return 0.0 if full <= 0.0 else clampf(left / full, 0.0, 1.0)
