class_name Stats
extends RefCounted
## Стати персонажа й усе, що з них рахується (крок 8 у П-52).
##
## Набір статів поки ПРОПОЗИЦІЯ з П-37 — п'ять замість шести в L2.
## Якщо набір зміниться, міняти доведеться тільки цей файл: більше
## ніде голих чисел бою немає.
##
## Числа у формулах — заглушки для налаштування. Підібрані так, щоб при
## усіх статах по 10 виходили ті самі значення, з якими гра жила до
## цього кроку: швидкість 5,0, відкат 1,2, здоров'я 100, зона бачення 18.

## Значення, від якого рахується "звичайний" персонаж.
const AVERAGE := 10

var strength := AVERAGE      ## Сила: фізична атака
var agility := AVERAGE       ## Спритність: швидкість руху й атаки
var stamina := AVERAGE       ## Витривалість: здоров'я, фізичний захист
var intellect := AVERAGE     ## Інтелект: мана, магічна атака
var sense := AVERAGE         ## Чуття: швидкість касту, магічний захист, зона бачення

## Бафи (П-... «Стати персонажа»): підвищують швидкість касту й
## знижують відкат. 0.0 — без бафів, 0.25 — на чверть коротший відкат.
var cooldown_cut := 0.0
var cast_speed_bonus := 0.0


func move_speed() -> float:
	return 4.0 + agility * 0.1


func attack_cooldown() -> float:
	var base := 1.8 - agility * 0.06
	return maxf(0.4, base * (1.0 - clampf(cooldown_cut, 0.0, 0.7)))


func swing_time() -> float:
	return maxf(0.15, 0.55 - agility * 0.02)


## Час читання заклять. Бафи на швидкість касту скорочують його.
func cast_time() -> float:
	var base := 2.0 - sense * 0.06
	return maxf(0.2, base / (1.0 + maxf(0.0, cast_speed_bonus)))


func max_hp() -> int:
	return 40 + stamina * 6


func max_mp() -> int:
	return 20 + intellect * 5


func physical_attack() -> float:
	return 3.0 + strength * 0.4


func physical_defence() -> float:
	return stamina * 1.5


func magical_defence() -> float:
	return sense * 1.5


## Скільки персонаж бачить (П-40). Дебафи на чутливість знижують `sense`,
## і разом із зоною стискається камера (П-47) та туман (П-65).
func vision_radius() -> float:
	return 12.0 + sense * 0.6


## Скільки шкоди дійде крізь захист. Захист не віднімається, а ділить:
## інакше при великому захисті шкода стала б нулем.
static func damage_through(attack: float, defence: float) -> int:
	return maxi(1, roundi(attack * 100.0 / (100.0 + defence)))
