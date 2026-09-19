class_name NPC
extends StaticBody3D
## Мешканець міста: коваль, священик, крамар (крок 5, П-113).
##
## Поки він **не говорить**: вікна розмови немає, і вигадувати його за
## замовника не можна. Він стоїть на своєму місці, має ім'я й ремесло,
## і сервер знає, де він, — цього досить, щоб місто перестало бути
## порожнім, а крамниця мала куди прийти.

## Ремесла, за якими гра щось вмикає. Ті самі рядки лежать у
## `data/map.json` → `ремесло`; тримати їх копіями по всьому
## `world.gd` означало б, що перейменування в даних тихо вимкне вікно.
const WAREHOUSE := "завідувач складу"
const GUILD := "гільдмайстер"
const PRIEST := "священик"

@export var who := "мешканець"
@export var craft := ""
## Номер у переліку `map.json → місто → мешканці`. Ним клієнт і сервер
## називають одного й того самого мешканця: обидва будують місто з того
## самого файлу, тож порядок у них однаковий, а вигадувати ще одну
## нумерацію означало б тримати її узгодженою руками.
@export var at_index := -1
## Що продає. Порожньо — не крамар, і кнопки «Торгувати» не буде.
var goods: Array = []
## Колір, щоб їх було видно один від одного, поки немає моделей.
@export var tint := Color(0.75, 0.7, 0.6)


## Idle/Idle_Talking по черзі, кожні 3-5 с (слово замовника 05.09.2026)
## — самі й «дихають», і «говорять» одне з одним, а не всі разом в один
## такт. Свій таймер, бо NPC не проходить крізь client_view.smooth()
## (не Creature, не в `_creatures`).
var _switch_left := 0.0
var _talking := true


func _ready() -> void:
	_switch_left = randf_range(3.0, 5.0)


func _process(delta: float) -> void:
	_switch_left -= delta
	if _switch_left > 0.0:
		return
	_switch_left = randf_range(3.0, 5.0)
	_talking = not _talking
	var mesh := get_node_or_null("Mesh")
	if mesh is SkinnedModel:
		mesh.show_move("Idle_Talking" if _talking else "Idle")


## Ім'я над головою — той самий прийом, що й `Creature.show_tag` (П-126),
## тільки NPC не Creature, і зріст завжди 1,75 (модель людини, П-162), не
## `body_height()`. Клич ПІСЛЯ того, як Mesh уже додано.
const TAG_HEIGHT := 2.15


func show_name() -> void:
	var tag := Label3D.new()
	tag.name = "Підпис"
	tag.text = title()
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 40
	tag.outline_size = 12
	tag.outline_modulate = Color(0, 0, 0, 0.85)
	tag.fixed_size = true
	tag.pixel_size = 0.0009
	tag.position = Vector3(0.0, TAG_HEIGHT, 0.0)
	tag.modulate = Color(0.85, 0.85, 0.7)
	add_child(tag)


func title() -> String:
	return who if craft == "" else "%s, %s" % [who, craft]


func trades() -> bool:
	return not goods.is_empty()


## Чи бере на зберігання (П-145). Питати цим, а не рівністю рядків.
func keeps() -> bool:
	return craft == WAREHOUSE


## Чи вчить скілів за руни (П-145).
func teaches() -> bool:
	return craft == GUILD


## Чи дає бафи (`data/blessings.json`, слово замовника 19.09.2026).
func blesses() -> bool:
	return craft == PRIEST
