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
## Підказка гравцю (П-154): коротко, що робить скіл. Замовник пише сам —
## порожній рядок, поки не заповнене.
var description := ""
## Стихія скіла (П-154), теж слово замовника. Порожня — «не задана».
var element := ""
## Грейд за спільною шкалою E · D · C · B · A · S · SS (П-106).
var grade := "E"
## Кого можна бити: "жива" · "усі-поруч" · "труп" · "себе" · "союзник".
var target := "жива"
## З якого рівня персонажа скіл узагалі доступний.
var from_level := 1
var cast_points := 1.0
var cooldown_points := 1.0
## Наскільки швидко рухається той, хто читає цей скіл: 0 — стоїть, 0,5 —
## удвічі повільніше. Слово замовника 13.09.2026: читання «повинно або
## сповільнювати кастуючого, або повністю зупиняти», залежно від скіла,
## і для всіх — монстрів теж (П-200). Повної швидкості не буває, тому
## стеля 0,9, а без поля в даних — стоїть.
var move_while_casting := 0.0
## Скільки коштує вивчити: руна плюс досвід (П-94).
var rune := ""
var learn_cost := 0
## Рівні ВСЕРЕДИНІ грейду. Кожен — словник: мана, дальність, шкода.
var levels: Array = []

## Дерево скілів (П-150): вкладка, місце в сітці й ключ скіла, який
## треба знати ПЕРШИМ. Порожня передумова — корінь гілки. Тільки один
## батько на скіл: розгалуження тут «одне дерево», не «і те, і те».
var category := ""
var position := Vector2i.ZERO
var requires := ""
## Кому скіл узагалі показується (П-221, 20.09.2026: дерево для всіх
## рас і статей). Порожньо — усім; інакше перелік рас чи статей, і
## гільдмайстер такого скіла чужій расі просто не покаже.
var races: Array = []
var sexes: Array = []
## Звідки скіл береться: "дерево" (вчиться в гільдії), "річ" (діє,
## доки річ удягнена), "амулет" (випав з амулета). Порожньо — дерево.
var source := "дерево"


static func from_data(of_key: String, data: Dictionary) -> Skill:
	var s := Skill.new()
	s.key = of_key
	s.name = data.get("назва", of_key)
	s.description = data.get("опис", "")
	s.element = data.get("стихія", "")
	s.grade = data.get("грейд", "E")
	s.target = data.get("ціль", "жива")
	s.from_level = int(data.get("з рівня", 1))
	s.cast_points = float(data.get("каст", 1.0))
	s.cooldown_points = float(data.get("відкат", 1.0))
	s.move_while_casting = clampf(float(data.get("рух при читанні", 0.0)),
			0.0, 0.9)
	var learn: Dictionary = data.get("вивчення", {})
	s.rune = learn.get("руна", "")
	s.learn_cost = int(learn.get("досвід", 0))
	s.levels = data.get("рівні", [])
	s.category = data.get("вкладка", "")
	var at: Array = data.get("місце", [0, 0])
	s.position = Vector2i(int(at[0]), int(at[1])) if at.size() >= 2 \
			else Vector2i.ZERO
	s.requires = data.get("передумова", "")
	s.races = data.get("раси", [])
	s.sexes = data.get("статі", [])
	s.source = str(data.get("джерело", "дерево"))
	return s


## Чи годиться цей скіл такому персонажеві. Порожній перелік — годиться
## всім: більшість скілів спільні, і писати їм усі три раси означало б
## правити три місця щоразу, як з'явиться четверта.
func fits(race: String, sex: String) -> bool:
	if not races.is_empty() and not races.has(race):
		return false
	if not sexes.is_empty() and not sexes.has(sex):
		return false
	return true


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


## Чи переносить скіл того, хто читав, у місто. Не шкода й не стан,
## тож і поле своє: «переніс»: «місто» в рівні скіла.
func sends_home(level: int) -> bool:
	return str(at(level).get("переніс", "")) == "місто"


func hits_many() -> bool:
	return target == "усі-поруч" or target == "свої-поруч"


## Скіл на своїх (бафи монстра на сусідів) чи на ворогів.
func hits_friends() -> bool:
	return target == "свої-поруч"
