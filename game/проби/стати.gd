extends SceneTree
## Проба до рішень 02.09.2026: П-85 (кого можна вдарити в спину) і
## П-37 (стати).
##
## Ганяти так:
##     godot --headless --path game --script res://проби/стати.gd

const MOB := preload("res://scenes/mob.tscn")
const AVATAR := preload("res://scenes/avatar.tscn")


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	await _back_before_aggro()
	await _no_back_after_aggro()
	_stats()
	_speeds()
	_skill_time()
	_races()
	quit()


## Двоє в світі й усе, що потрібно бою. Монстр стоїть у центрі й дивиться
## на -Z; гравець — за його спиною, на +Z.
func _world(aggressive: bool) -> Array:
	var hero: Node3D = AVATAR.instantiate()
	var mob: Node3D = MOB.instantiate()
	root.add_child(hero)
	root.add_child(mob)
	await process_frame
	mob.setup(Vector3.ZERO, 1, aggressive)
	mob.place_at(Vector3(0, 1.5, 0), 0.0)
	hero.place_at(Vector3(0, 1.5, 2.0), 0.0)
	hero.target_id = -1
	var creatures := {1: hero, -1: mob}
	var vision := Vision.new(creatures)
	vision.watch(1)
	vision.update(1)
	var link := Messenger.new(null, vision)
	var combat := Combat.new(creatures, link)
	return [creatures, hero, mob, combat, MobAI.new(creatures, combat)]


## Правило П-85: спину показує той, хто тебе ще не помітив.
func _back_before_aggro() -> void:
	print("\n— пасивний монстр, який тебе не помітив (П-85) —")
	var w: Array = await _world(false)
	var hero: Node3D = w[1]
	var mob: Node3D = w[2]
	var combat: Combat = w[3]
	var mobs: MobAI = w[4]

	# Монстр блукає й на гравця поруч не зважає.
	for i in 10:
		mobs.think(-1, 1.0 / 60.0)
		mob.global_position = Vector3(0, 1.5, 0)
	print("  гравець стоїть за 2,0 позаду; монстр узяв його ціллю: %s"
			% [mob.target_id != 0])

	var full: int = mob.hp
	hero.attack_ready_in = 0.0
	combat.attack(1)
	print("  перший удар: шкода %d, зі спини: %s"
			% [full - mob.hp, Stats.from_behind(0.0, Vector3.ZERO,
			   Vector3(0, 1.5, 2.0))])

	# Удар дав загрозу — тепер монстр розвертається до кривдника.
	mobs.think(-1, 1.0 / 60.0)
	print("  після удару монстр цілиться в %d, дивиться під %.0f°"
			% [mob.target_id, rad_to_deg(mob.facing)])
	var before: int = mob.hp
	hero.attack_ready_in = 0.0
	combat.attack(1)
	print("  другий удар із того самого місця: шкода %d (уже спереду)"
			% [before - mob.hp])
	hero.queue_free()
	mob.queue_free()


## Аґреного обійти не можна: він розвертається миттю.
func _no_aggro_shows_back() -> void:
	pass


func _no_back_after_aggro() -> void:
	print("\n— агресивний монстр, який тебе помітив —")
	var w: Array = await _world(true)
	var hero: Node3D = w[1]
	var mob: Node3D = w[2]
	var mobs: MobAI = w[4]

	# Гравець бігає по колу впритул — найшвидший можливий обхід.
	var radius := 1.0
	var angle := 0.0
	var before_aggro := 0
	var after_aggro := 0
	var frames_before := 0
	var most := 0.0
	for i in 300:
		mobs.think(-1, 1.0 / 60.0)
		mob.server_step(1.0 / 60.0)
		# Підлоги в пробі немає, і без цього рядка монстр просто падає в
		# порожнечу: за півтори секунди він на -21 і гравця вже не бачить
		# (стара пастка з КОНТЕКСТ.md — проба ламається частіше за код).
		mob.global_position = Vector3(0, 1.5, 0)
		mob.velocity.y = 0.0
		angle += 5.0 / radius * (1.0 / 60.0)
		hero.place_at(Vector3(sin(angle) * radius, 1.5,
				-cos(angle) * radius), 0.0)
		var behind: bool = Stats.from_behind(mob.facing, mob.global_position,
				hero.global_position)
		if mob.target_id == 0:
			frames_before += 1
			if behind:
				before_aggro += 1
		else:
			if behind:
				after_aggro += 1
			most = maxf(most, rad_to_deg(absf(angle_difference(mob.facing,
					atan2(-hero.global_position.x,
					-hero.global_position.z)))))
	print("  поки не помітив (%d кадрів, %.2f с): зі спини %d кадрів"
			% [frames_before, frames_before / 60.0, before_aggro])
	print("  після того, як помітив (%d кадрів): зі спини %d, відстає щонайбільше на %.1f°"
			% [300 - frames_before, after_aggro, most])
	hero.queue_free()
	mob.queue_free()


## П-37: магічний захист із Витривалості, Чуття ріже чужий бонус зі спини.
func _stats() -> void:
	print("\n— стати за П-37 —")
	var s := Stats.new()
	print("  при всіх 10: маг. захист %.1f, фіз. захист %.1f (обидва з Витривалості)"
			% [s.magical_defence(), s.physical_defence()])
	s.stamina = 20
	print("  Витривалість 20: маг. захист %.1f" % s.magical_defence())
	s.stamina = 10
	print("  надбавка за удар зі спини по жертві з Чуттям (П-90):")
	for value: int in [5, 10, 15, 20, 30, 40]:
		s.sense = value
		var bonus := Stats.back_bonus_against(s)
		print("    Чуття %2d -> надбавка %4.1f%%, шкода ззаду %d (спереду %d)"
				% [value, bonus * 100.0,
				   Stats.damage_through(7.0 * (1.0 + bonus), s.physical_defence()),
				   Stats.damage_through(7.0, s.physical_defence())])


## П-86: швидкості логарифмічні, кількості прямі.
func _speeds() -> void:
	print("\n— форма формул за П-86 —")
	print("  стат | біг  | відкат | замах | каст | старе віднімання")
	var s := Stats.new()
	for value: int in [1, 10, 20, 30, 50, 70, 100]:
		s.agility = value
		s.sense = value
		# Стара форма — для порівняння: 1,8 - стат × 0,06, межа 0,4.
		var was := maxf(0.4, 1.8 - value * 0.06)
		print("  %4d | %.2f | %6.2f | %5.2f | %4.2f | %.2f%s"
				% [value, s.move_speed(), s.attack_cooldown(), s.swing_time(),
				   s.cast_time(), was, "  ← у межі" if was <= 0.4 else ""])
	s.agility = 10
	s.sense = 10
	print("  кількості лишились прямими: здоров'я %d, атака %.1f, захист %.1f"
			% [s.max_hp(), s.physical_attack(), s.physical_defence()])


## П-89: шість типів на теперішніх формулах (логарифм, стати за П-37).
func _races() -> void:
	print("\n— шість типів за П-89 —")
	var types := [
		["Людина чоловiк", 11, 11, 10, 9, 9],
		["Людина жiнка", 9, 9, 10, 11, 11],
		["Орк чоловiк", 13, 9, 12, 7, 9],
		["Орк жiнка", 11, 7, 12, 9, 11],
		["Ельф чоловiк", 9, 13, 8, 9, 11],
		["Ельф жiнка", 7, 11, 8, 11, 13],
	]
	print("  тип               |  бiг вiдкат   HP  MP  атака  каст  зона  маг.захист")
	for row: Array in types:
		var s := Stats.new()
		s.strength = row[1]
		s.agility = row[2]
		s.stamina = row[3]
		s.intellect = row[4]
		s.sense = row[5]
		print("  %-17s | %.2f  %5.2f  %3d %3d   %4.1f  %4.2f  %4.1f   %5.1f"
				% [row[0], s.move_speed(), s.attack_cooldown(), s.max_hp(),
				   s.max_mp(), s.physical_attack(), s.cast_time(),
				   s.vision_radius(), s.magical_defence()])
	print("  сума статів у кожного однакова: %d" % 50)


## П-98 і П-35: відкат скіла статами не ріжеться, каст — ріжеться.
func _skill_time() -> void:
	print("\n— поінти скіла в секунди (П-98) —")
	print("  промінь: каст 3 поінти, відкат 6 поінтів")
	var s := Stats.new()
	for value: int in [10, 30, 70]:
		s.sense = value
		s.agility = value
		print("    Чуття й Спритність %2d -> каст %.2f с, відкат %.2f с"
				% [value, s.skill_cast(3.0), s.skill_cooldown(6.0)])
	s.sense = 10
	s.agility = 10
	print("  той самий скіл під бафом на чверть відкату:")
	s.cooldown_cut = 0.25
	print("    каст %.2f с, відкат %.2f с (стат не змінився, баф змінив)"
			% [s.skill_cast(3.0), s.skill_cooldown(6.0)])
