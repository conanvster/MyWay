class_name SelectMark
extends RefCounted
## Помітка «ось кого вибрано»: пульсуюче коло під ногами й стрілка над
## головою, що погойдується.
##
## Слово замовника 13.09.2026: «потрібно додати маркер, щоб користувач
## розумів, кого він зараз вибрав». Стрілка «▼» над монстром (П-156) уже
## була, але дрібна й лише в монстрів — мешканця й святиню вибрати було
## видно тільки в рамці HUD. Тепер одна помітка на всіх трьох.
##
## Коло не ховається за землею й стінами (`no_depth_test`): у тісному
## ході підземелля вибраного монстра за рогом інакше не знайти.

const NAME := "ПоміткаВибору"
const TONE := Color(1.0, 0.84, 0.18)
## Монстр під штрафом світу (П-213): «при виділенні підсвічуються
## фіолетовим».
const CURSED := Color(0.72, 0.3, 1.0)


static func put(on: Node3D, radius: float, height: float) -> void:
	clear(on)
	var holder := Node3D.new()
	holder.name = NAME
	on.add_child(holder)

	var ring := MeshInstance3D.new()
	ring.name = "Коло"
	var band := TorusMesh.new()
	band.inner_radius = radius * 0.84
	band.outer_radius = radius
	band.rings = 48
	band.ring_segments = 8
	ring.mesh = band
	var paint := StandardMaterial3D.new()
	paint.albedo_color = TONE
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.no_depth_test = true
	paint.render_priority = 1
	ring.material_override = paint
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = Vector3(0.0, 0.08, 0.0)
	holder.add_child(ring)

	var arrow := Label3D.new()
	arrow.name = "Стрілка"
	arrow.text = "▼"
	arrow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	arrow.fixed_size = true
	arrow.pixel_size = 0.0013
	arrow.font_size = 96
	arrow.outline_size = 18
	arrow.outline_modulate = Color(0, 0, 0, 0.9)
	arrow.modulate = TONE
	arrow.no_depth_test = true
	arrow.position = Vector3(0.0, height + 0.5, 0.0)
	holder.add_child(arrow)

	# Рух ловить око швидше за колір. На сервері без вікна не треба.
	if DisplayServer.get_name() == "headless":
		return
	var pulse := ring.create_tween().set_loops()
	pulse.tween_property(ring, "scale", Vector3(1.18, 1.0, 1.18), 0.45) \
			.set_trans(Tween.TRANS_SINE)
	pulse.tween_property(ring, "scale", Vector3.ONE, 0.45) \
			.set_trans(Tween.TRANS_SINE)
	var bob := arrow.create_tween().set_loops()
	bob.tween_property(arrow, "position:y", height + 0.85, 0.45) \
			.set_trans(Tween.TRANS_SINE)
	bob.tween_property(arrow, "position:y", height + 0.5, 0.45) \
			.set_trans(Tween.TRANS_SINE)


static func clear(on: Node) -> void:
	if on == null or not is_instance_valid(on):
		return
	var old := on.get_node_or_null(NAME)
	if old != null:
		on.remove_child(old)
		old.queue_free()


## Перефарбувати наявну помітку, не будуючи її заново: стани цілі
## приходять уже після вибору, і пульсація не має збиватись.
static func tint(on: Node, tone: Color) -> void:
	if on == null or not is_instance_valid(on):
		return
	var holder := on.get_node_or_null(NAME)
	if holder == null:
		return
	var ring := holder.get_node_or_null("Коло") as MeshInstance3D
	if ring != null and ring.material_override is StandardMaterial3D:
		(ring.material_override as StandardMaterial3D).albedo_color = tone
	var arrow := holder.get_node_or_null("Стрілка") as Label3D
	if arrow != null:
		arrow.modulate = tone
