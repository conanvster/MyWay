extends SceneTree
## Проба до кроку 0: чотири вади й напрямок істот.
##
## Ганяти так:
##     godot --headless --path game --script res://probes/крок0.gd
##
## Числа друкуються, а не ховаються за «пройдено»: у цьому проєкті
## перевіряють числами.

const MOB := preload("res://scenes/mob.tscn")


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	# Кожна проба, у якій є await, сама є корутиною — без await тут вона
	# лише запуститься, а quit() встигне раніше за її друк.
	await _help_range()
	await _facing_from_move()
	_back_arc()
	_back_damage()
	await _revive()
	quit()


## Вада 1. Поклик на поміч (help_range = 12) має відсікати далеких.
func _help_range() -> void:
	print("\n— поклик на поміч (вада 1) —")
	var a: Node3D = MOB.instantiate()
	var b: Node3D = MOB.instantiate()
	root.add_child(a)
	root.add_child(b)
	await process_frame
	a.setup(Vector3.ZERO, 1, true)
	b.setup(Vector3.ZERO, 1, true)
	var other_kind: Node3D = MOB.instantiate()
	root.add_child(other_kind)
	await process_frame
	other_kind.setup(Vector3.ZERO, 2, true)
	a.global_position = Vector3(0, 1.5, 0)
	for d: float in [4.24, 11.9, 12.1, 30.0, 1000.0]:
		b.global_position = Vector3(d, 1.5, 0)
		other_kind.global_position = Vector3(1, 1.5, 0)
		await process_frame
		print("  вiдстань %7.2f  поклик %.0f  чує: %s"
				% [d, b.help_range, b.hears(a, a.global_position)])
	print("  чужий вид за 1,0: чує: %s (має бути false)"
			% other_kind.hears(a, a.global_position))
	a.queue_free()
	b.queue_free()
	other_kind.queue_free()


## Вада 4. Біжить — дивиться туди, куди біжить.
func _facing_from_move() -> void:
	print("\n— напрямок із руху (вада 4) —")
	var m: Node3D = MOB.instantiate()
	root.add_child(m)
	await process_frame
	m.setup(Vector3.ZERO, 1, false)
	m.global_position = Vector3(0, 1.5, 0)
	for pair: Array in [[Vector2(0, -1), "на пiвнiч -Z"], [Vector2(1, 0), "на схiд +X"],
			[Vector2(0, 1), "на пiвдень +Z"], [Vector2(-1, 0), "на захiд -X"]]:
		m.wanted = pair[0]
		m.server_step(0.016)
		# Куди дивиться: -Z вузла, повернуте на кут.
		var look := Vector3(-sin(m.facing), 0.0, -cos(m.facing))
		print("  намiр %-10s -> кут %7.1f°  погляд (%.2f, %.2f)  %s"
				% [str(pair[0]), rad_to_deg(m.facing), look.x, look.z, pair[1]])
	m.queue_free()


## Вада 4 + П-40. Задній сектор 120°: 0° спереду, 180° ззаду.
func _back_arc() -> void:
	print("\n— задній сектор (П-40, числа з П-85) —")
	print("  BACK_ARC_DEG %.0f  межа %.0f°  BACK_BONUS %.0f%%"
			% [Stats.BACK_ARC_DEG, 180.0 - Stats.BACK_ARC_DEG * 0.5,
			   Stats.BACK_BONUS * 100.0])
	var victim := Vector3.ZERO
	# Жертва дивиться на -Z, тобто кут 0.
	for deg: float in [0.0, 90.0, 119.0, 121.0, 180.0]:
		# Нападник під кутом deg від погляду жертви.
		var rad := deg_to_rad(deg)
		var at := Vector3(-sin(rad), 0.0, -cos(rad)) * 2.0
		print("  нападник пiд %5.0f° вiд погляду -> зi спини: %s"
				% [deg, Stats.from_behind(0.0, victim, at)])


## Скільки насправді дає бонус на статах, з якими гра живе зараз.
func _back_damage() -> void:
	print("\n— шкода спереду і ззаду —")
	var hero := Stats.new()
	var mob := Stats.new()
	mob.strength = 7
	mob.stamina = 4
	mob.agility = 7
	var power := hero.physical_attack()
	var front := Stats.damage_through(power, mob.physical_defence())
	# Надбавка залежить від Чуття жертви (П-37, правка 3; числа П-90).
	var bonus := Stats.back_bonus_against(mob)
	var back := Stats.damage_through(power * (1.0 + bonus),
			mob.physical_defence())
	print("  атака %.1f  захист монстра %.1f" % [power, mob.physical_defence()])
	print("  надбавка ззаду по Чуттю %d: %.0f%%" % [mob.sense, bonus * 100.0])
	print("  спереду %d  ззаду %d  рiзниця %+d" % [front, back, back - front])


## Вади 2 і 3. Оживлений має встати й опинитись на місці, а не їхати.
func _revive() -> void:
	print("\n— оживлення (вади 2 і 3) —")
	var m: Node3D = MOB.instantiate()
	root.add_child(m)
	await process_frame
	m.setup(Vector3.ZERO, 1, false)
	m.global_position = Vector3(40, 1.5, 40)
	m.server_position = m.global_position
	m.lay_down()
	var mesh: Node3D = m.get_node("Mesh")
	print("  труп: нахил меша %.0f°, висота %.1f"
			% [rad_to_deg(mesh.rotation.x), mesh.position.y])
	m.stand_up()
	print("  пiдвiвся: нахил меша %.0f°, висота %.1f"
			% [rad_to_deg(mesh.rotation.x), mesh.position.y])
	var was := m.global_position
	m.place_at(Vector3(0, 1.5, 0), 0.0)
	print("  переставлено з %s у %s" % [was, m.global_position])
	print("  server_position %s — збiгається: %s (інакше клієнт поїде)"
			% [m.server_position, m.server_position == m.global_position])
	m.queue_free()
