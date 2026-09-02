class_name Skill
extends RefCounted
## Один скіл: те, що вчиться руною й росте рівнями (П-94, П-106).
##
## Скіл — це ДАНІ, а не код: усе, що нижче, приходить із
## `data/skills.json`. Нове вміння має бути рядком у файлі, а не новим
## `match` у диспетчері — інакше десяте вміння коштує двох годин.
##
## Каст і відкат тут у ПОІНТАХ (П-98). У секунди їх переводить `Stats`:
## каст ріже Чуття, відкат — тільки бафи й спорядження (П-35).

## Ключ у файлі: "енергетичний-промінь".
var key := ""
var name := ""
## Грейд за спільною шкалою E · D · C · B · A · S · SS (П-106).
var grade := "E"
## Кого можна бити: "жива" · "усі-поруч" · "труп" · "себе" · "союзник".
var target := "жива"
## З якого рівня персонажа скіл узагалі доступний.
var from_level := 1
var cast_points := 1.0
var cooldown_points := 1.0
## Скільки коштує вивчити: руна плюс досвід (П-94).
var rune := ""
var learn_cost := 0
## Рівні ВСЕРЕДИНІ грейду. Кожен — словник: мана, дальність, шкода.
var levels: Array = []


static func from_data(of_key: String, data: Dictionary) -> Skill:
	var s := Skill.new()
	s.key = of_key
	s.name = data.get("назва", of_key)
	s.grade = data.get("грейд", "E")
	s.target = data.get("ціль", "жива")
	s.from_level = int(data.get("з рівня", 1))
	s.cast_points = float(data.get("каст", 1.0))
	s.cooldown_points = float(data.get("відкат", 1.0))
	var learn: Dictionary = data.get("вивчення", {})
	s.rune = learn.get("руна", "")
	s.learn_cost = int(learn.get("досвід", 0))
	s.levels = data.get("рівні", [])
	return s


func max_level() -> int:
	return levels.size()


## Рядок таблиці рівнів. Рівні рахуються з 1; поза межами беремо крайній,
## щоб зіпсовані дані не роняли бій.
func at(level: int) -> Dictionary:
	if levels.is_empty():
		return {}
	return levels[clampi(level - 1, 0, levels.size() - 1)]


func mana(level: int) -> int:
	return int(at(level).get("мана", 0))


func range_at(level: int) -> float:
	return float(at(level).get("дальність", 0.0))


## Скільки магічної атаки йде в удар: 1,4 — сто сорок відсотків.
func power_share(level: int) -> float:
	return float(at(level).get("шкода", 0.0))


## Стан, який скіл вішає на зачеплених. Порожній — скіл лише б'є.
func state_at(level: int) -> Dictionary:
	return at(level).get("стан", {})


func hits_many() -> bool:
	return target == "усі-поруч" or target == "свої-поруч"


## Скіл на своїх (бафи монстра на сусідів) чи на ворогів.
func hits_friends() -> bool:
	return target == "свої-поруч"
