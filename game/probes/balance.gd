extends SceneTree
## Бот-прогін балансу перед першим плейтестом (P5, П-226).
##
## Ганяти так:
##     godot --headless --path game --script res://probes/balance.gd
##
## НЕ плейтест: плейтест — це живі люди, і його числа (чи весело, чи не
## нудно) бот не дасть. Тут те, що можна порахувати наперед, справжнім
## `Combat` і `Progress` з поточних даних, щоб плейтест не витрачав
## вечір на очевидне:
##
##   гравець рівня L, очки статів порівну в силу й витривалість (воїн
##   ближнього бою — єдиний, кого бот уміє вести), спорядження грейду L
##   за драбиною (перша база кожного слота) — проти КОЖНОГО виду, чий
##   рівень у межах L−2…L+2, один на один, лише удари.
##
## На смугу друкує: скільки видів, медіану часу бою, медіану втраченого
## здоров'я, скільки боїв програно, скільки зіль лікування на бій і
## скільки треба вбити й хвилин полювати на рівень (бій + 10 с на пошук
## наступного). Окремо — найгірші й найлегші види смуги.

const AVATAR := preload("res://scenes/avatar.tscn")
const MOB := preload("res://scenes/mob.tscn")
const LEVELS: Array[int] = [1, 3, 5, 8, 10, 13, 15, 18, 22, 28, 35, 41,
		48, 54, 60, 68, 72, 76, 80]
const STEP := 0.1
const FIGHT_CAP := 180.0
const SEEK_TIME := 10.0
const POTION := "зілля лікування"


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	var data := GameData.new()
	data.load_all()
	var creatures := {}
	var combat := Combat.new(creatures)
	combat.skills = data.skills
	combat.goods = data.items
	combat.smith = data.smith
	var progress := Progress.new(data.levels)
	combat.progress = progress
	var heal := int(data.items.base_of(POTION).get("дія", {}).get("здоров'я", 500))

	print("рівень · грейд · видів · бій, с · втрата hp · програно · зіль/бій"
			+ " · убити на рівень · хв на рівень")
	var report: Array = []
	for level: int in LEVELS:
		var kinds: Array = []
		for key in data.mobs:
			if not str(key).is_valid_int():
				continue
			var mob_level := int(data.for_kind(int(key)).get("рівень", 1))
			if absi(mob_level - level) <= 2:
				kinds.append(int(key))
		if kinds.is_empty():
			print("  %2d · немає видів у смузі" % level)
			continue
		var fights: Array = []
		for kind: int in kinds:
			fights.append(await _fight(data, combat, creatures, progress,
					level, kind))
		var times: Array = fights.map(func(f: Dictionary) -> float: return f["час"])
		var lost: Array = fights.map(func(f: Dictionary) -> float: return f["втрата"])
		var respect: Array = fights.map(func(f: Dictionary) -> float: return f["повага"])
		var losses := fights.filter(func(f: Dictionary) -> bool: return not f["переміг"]).size()
		var need: int = progress.need_for(level)
		var per_kill := _median(respect)
		var kills := ceili(need / maxf(1.0, per_kill))
		var minutes := kills * (_median(times) + SEEK_TIME) / 60.0
		var potions: float = _median(lost) * float(fights[0]["max_hp"]) / float(heal)
		var grade: String = data.items.grade_for_level(level)
		print("  %2d · %-2s · %3d · %5.1f · %4.0f%% · %d · %.2f · %d · %.0f" % [
				level, grade, kinds.size(), _median(times),
				_median(lost) * 100.0, losses, potions, kills, minutes])
		fights.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return float(a["втрата"]) > float(b["втрата"]))
		var hard: Array = fights.slice(0, 3).map(func(f: Dictionary) -> String:
				return "%s (%d рів., %s)" % [f["назва"], f["рівень"],
						"%.0f%% hp" % (f["втрата"] * 100.0) if f["переміг"]
						else "ПРОГРАВ"])
		var easy: Array = fights.slice(-2).map(func(f: Dictionary) -> String:
				return "%s (%.0f с)" % [f["назва"], f["час"]])
		print("       найважчі: %s" % ", ".join(hard))
		print("       найлегші: %s" % ", ".join(easy))
		report.append({"рівень": level, "програно": losses})
	quit()


## Один бій: обоє стоять упритул і б'ють, щойно минув відкат.
func _fight(data: GameData, combat: Combat, creatures: Dictionary,
		progress: Progress, level: int, kind: int) -> Dictionary:
	var hero: Node3D = AVATAR.instantiate()
	var mob: Node3D = MOB.instantiate()
	root.add_child(hero)
	root.add_child(mob)
	await process_frame
	hero.level = level
	var points := (level - 1) * int(data.levels.get("очок статів за рівень", 3))
	for i in points:
		var field: String = "сила" if i % 2 == 0 else "витривалість"
		hero.stat_points += 1
		progress.spend_stat(hero, field)
	_dress(data, hero, data.items.grade_for_level(level))
	hero.refresh_stats()
	hero.hp = hero.stats.max_hp()
	var row: Dictionary = data.for_kind(kind)
	mob.setup(Vector3(1.5, 0, 0), kind, true, row)
	hero.global_position = Vector3.ZERO
	mob.global_position = Vector3(1.5, 0, 0)
	creatures.clear()
	creatures[1] = hero
	creatures[-1] = mob
	hero.target_id = -1
	mob.target_id = 1
	var start_hp: int = hero.hp
	var clock := 0.0
	while clock < FIGHT_CAP and hero.hp > 0 and mob.hp > 0:
		for who: Node in [hero, mob]:
			who.attack_ready_in = maxf(0.0, who.attack_ready_in - STEP)
		combat.attack(1)
		if mob.hp > 0:
			combat.attack(-1)
		clock += STEP
	var won: bool = mob.hp <= 0 and hero.hp > 0
	var mult: float = progress.reward_multiplier(int(row.get("рівень", 1)), level)
	var range_r: Array = row.get("повага", [0, 0])
	var out := {
		"назва": str(row.get("назва", "?")), "рівень": int(row.get("рівень", 1)),
		"час": clock, "переміг": won, "max_hp": start_hp,
		"втрата": float(start_hp - maxi(0, hero.hp)) / maxf(1.0, start_hp),
		"повага": (float(range_r[0]) + float(range_r[-1])) * 0.5 * mult,
	}
	hero.queue_free()
	mob.queue_free()
	creatures.clear()
	return out


## Перша база кожного слота цього грейду; зброя — однорука.
func _dress(data: GameData, hero: Node, grade: String) -> void:
	var taken := {}
	for name: String in data.items.bases:
		var base: Dictionary = data.items.bases[name]
		var slot := str(base.get("слот", ""))
		if str(base.get("грейд", "")) != grade or slot == "" or taken.has(slot):
			continue
		if slot == "зброя" and str(base.get("тип", "")) != "меч":
			continue
		var item: Item = data.items.make(name, [])
		if item == null:
			continue
		taken[slot] = true
		hero.equip(hero.add_thing(item))


func _median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[sorted.size() / 2])
