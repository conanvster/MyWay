class_name Progress
extends RefCounted
## Повага, рівні й винагорода за вбивство (крок 3).
##
## Дві валюти, і вони різні (погоджено 02.09.2026):
##
##   ПОВАГА  дає рівні. Накопичується й не списується ніколи, крім
##           смерті: за смерть іде рівно 10% ОБСЯГУ поточного рівня, а
##           не частка накопиченого.
##   ДОСВІД  платиться за навчання скілів і за смерть не втрачається.
##
## Числа сітки — тимчасові (П-99, П-103): замовник лишив їх на пробу
## грою, і вони живуть у `дані/рівні.json`, тобто правляться без
## перезапуску.

var grid: Dictionary = {}


func _init(from_data: Dictionary = {}) -> void:
	grid = from_data


## Скільки поваги треба набрати, СТОЯЧИ на цьому рівні, щоб піти далі.
##
## Раса й стать зсувають вимогу: стать на ±2,5%, раса на ±5% — те саме
## «раса = 2 × стать», що й у статах (П-48).
func need_for(level: int, race: String = "людина",
		sex: String = "чоловік") -> int:
	var base: float = float(grid.get("основа", 1000))
	var power: float = float(grid.get("показник", 1.585))
	var shift: float = float(grid.get("раса", {}).get(race, 0.0)) \
			+ float(grid.get("стать", {}).get(sex, 0.0))
	return maxi(1, roundi(base * pow(maxi(1, level), power) * (1.0 + shift)))


## Множник винагороди за різницю рівнів (П-104).
##
## Точки задані в даних, між ними — лінійно. Різниця в 1–2 рівні нічого
## не міняє: інакше гравець рахував би рівні перед кожним ударом.
func reward_multiplier(mob_level: int, player_level: int) -> float:
	var diff: int = mob_level - player_level
	var points: Array = grid.get("різниця рівнів", [])
	if points.is_empty():
		return 1.0
	if diff <= int(points[0]["різниця"]):
		return float(points[0]["множник"])
	for i in range(points.size() - 1):
		var low: Dictionary = points[i]
		var high: Dictionary = points[i + 1]
		if diff >= int(low["різниця"]) and diff <= int(high["різниця"]):
			var span: float = float(int(high["різниця"]) - int(low["різниця"]))
			var part: float = (diff - int(low["різниця"])) / maxf(1.0, span)
			return lerpf(float(low["множник"]), float(high["множник"]), part)
	return float(points[-1]["множник"])


## Додати поваги. Повертає, скільки рівнів узято.
func add_respect(who: Node, amount: int) -> int:
	who.respect += amount
	var gained := 0
	while who.respect >= need_for(who.level, who.race, who.sex):
		who.respect -= need_for(who.level, who.race, who.sex)
		who.level += 1
		who.stat_points += int(grid.get("очок статів за рівень", 3))
		gained += 1
	return gained


## Втрата за смерть: рівно 10% обсягу поточного рівня, не нижче нуля.
## Рівень при цьому не падає — замовник цього не казав, а самому
## вигадувати пониження рівня не можна.
func death_loss(who: Node) -> int:
	var share: float = float(grid.get("втрата за смерть", 0.10))
	var loss: int = roundi(need_for(who.level, who.race, who.sex) * share)
	loss = mini(loss, who.respect)
	who.respect -= loss
	return loss


## Частка поточного рівня, від 0 до 1 — для смуги в HUD.
func share_of_level(who: Node) -> float:
	return clampf(float(who.respect)
			/ maxf(1.0, need_for(who.level, who.race, who.sex)), 0.0, 1.0)
