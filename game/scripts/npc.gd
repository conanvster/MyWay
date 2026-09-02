class_name NPC
extends StaticBody3D
## Мешканець міста: коваль, священик, крамар (крок 5, П-113).
##
## Поки він **не говорить**: вікна розмови немає, і вигадувати його за
## замовника не можна. Він стоїть на своєму місці, має ім'я й ремесло,
## і сервер знає, де він, — цього досить, щоб місто перестало бути
## порожнім, а крамниця мала куди прийти.

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


## Пофарбувати. Кликати ПІСЛЯ того, як з'явився меш: у `_ready` його ще
## немає, якщо вузол збирається кодом, — на цьому я вже раз попався, і
## мешканці міста вийшли всі білі.
func repaint() -> void:
	var mesh := get_node_or_null("Mesh")
	if mesh == null or mesh.mesh == null:
		return
	var paint := StandardMaterial3D.new()
	paint.albedo_color = tint
	paint.roughness = 0.9
	mesh.set_surface_override_material(0, paint)


func _ready() -> void:
	repaint()


func title() -> String:
	return who if craft == "" else "%s, %s" % [who, craft]


func trades() -> bool:
	return not goods.is_empty()
