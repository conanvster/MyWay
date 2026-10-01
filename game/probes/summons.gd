extends SceneTree
## Проба прикликаних (П-41).
##
## Ганяти так:
##     godot --headless --path game --script res://probes/summons.gd
##
## Справжні `Combat`, `MobAI` і `Summons`; вузли ставить і прибирає сама
## проба, як це робить світ. Наприкінці «помилок: N».

const AVATAR := preload("res://scenes/avatar.tscn")
const MOB := preload("res://scenes/mob.tscn")

var _bad := 0
var _creatures := {}


func _init() -> void:
	call_deferred("_go")


func _expect(what: String, got: Variant, want: Variant) -> void:
	var ok: bool = got == want
	if not ok:
		_bad += 1
	print("  %s %s: %s%s" % ["✓" if ok else "✗", what, str(got),
			"" if ok else " (чекали %s)" % str(want)])


func _spawn(id: int, at: Vector3) -> Node3D:
	var m: Node3D = MOB.instantiate()
	root.add_child(m)
	m.global_position = at
	_creatures[id] = m
	return m


func _remove(id: int) -> void:
	if _creatures.has(id):
		_creatures[id].queue_free()
		_creatures.erase(id)


func _go() -> void:
	await process_frame
	var data := GameData.new()
	data.load_all()
	var combat := Combat.new(_creatures)
	combat.skills = data.skills
	combat.goods = data.items
	combat.smith = data.smith
	combat.progress = Progress.new(data.levels)
	var summons := Summons.new(_creatures, combat, data, _spawn, _remove)
	combat.on_summon = func(me: int, what: Dictionary) -> void:
			summons.request(me, what)
	var brains := MobAI.new(_creatures, combat)

	var hero: Node3D = AVATAR.instantiate()
	root.add_child(hero)
	await process_frame
	_creatures[1] = hero
	hero.level = 52
	hero.refresh_stats()
	hero.hp = hero.stats.max_hp()
	hero.mp = 10000
	hero.learn("плащ-мертвих", 1)

	print("\n— некромант кличе (плащ мертвих) —")
	var cloak: Skill = data.skills.get_skill("плащ-мертвих")
	_expect("у скіла є прикликання", cloak.summon.get("вид"), 79)
	_expect("скіл почався", combat.cast(1, "плащ-мертвих"), true)
	for i in 40:
		combat.tick_casts(0.1)
	summons.tick(0.1)
	var mine: Array = summons.of_owner(1)
	_expect("прикликано", mine.size(), 1)
	var s_id: int = mine[0] if not mine.is_empty() else 0
	var s: Node3D = _creatures.get(s_id)
	_expect("номер із діапазону прикликаних", s_id <= Summons.FIRST_ID, true)
	_expect("вид — кістяний голем-збирач", s.kind if s else 0, 79)
	_expect("рівень господаря", s.level if s else 0, 52)
	_expect("бік — гравців", combat.side(s_id), 1)
	_expect("плащ далі гартує господаря", hero.states.has("плащ мертвих"),
			true)

	print("\n— свої не б'ються —")
	hero.target_id = s_id
	hero.attack_ready_in = 0.0
	_expect("господар б'є свого", combat.attack(1), false)

	print("\n— б'ється за господаря —")
	var wolf := _spawn(-1, Vector3(1.5, 0, 0))
	# Монстр рівня господаря: за вовка 2 рівня некромант 52-го не дістав
	# би нічого (множник за різницю рівнів 0, П-104).
	wolf.setup(Vector3(1.5, 0, 0), 87, false, data.for_kind(87))
	await process_frame
	s.place_at(Vector3(1.5, 0, 1.0), 0.0)
	hero.target_id = -1
	var respect_before: int = hero.respect
	var wolf_hp: int = wolf.hp
	summons.tick(0.1)
	_expect("ціль прикликаного — ціль господаря", s.target_id, -1)
	_expect("вовк поранений", wolf.hp < wolf_hp, true)
	_expect("вовк мітить прикликаного", wolf.threat.has(s_id), true)
	brains.think(-1, 0.1)
	_expect("вовк б'є прикликаного у відповідь", wolf.target_id, s_id)
	for i in 3000:
		if not wolf.is_alive():
			break
		s.attack_ready_in = maxf(0.0, s.attack_ready_in - 0.1)
		summons.tick(0.1)
	print("    вовк %d hp, прикликаний %d/%d hp, ціль %d, відкат %.1f" % [
			wolf.hp, s.hp, s.stats.max_hp(), s.target_id, s.attack_ready_in])
	_expect("вовк загинув", wolf.is_alive(), false)
	_expect("повагу отримав господар", hero.respect > respect_before
			or hero.level > 52, true)

	print("\n— строк і повторне читання —")
	hero.skill_ready_in.clear()
	combat.cast(1, "плащ-мертвих")
	for i in 40:
		combat.tick_casts(0.1)
	summons.tick(0.1)
	_expect("нове читання замінює, а не додає", summons.of_owner(1).size(), 1)
	summons.tick(61.0)
	_expect("за 60 с розсипався", summons.of_owner(1).size(), 0)

	print("\n— володар праху кличе двох (море праху) —")
	hero.level = 64
	hero.learn("море-праху", 1)
	hero.skill_ready_in.clear()
	hero.target_id = 0
	combat.cast(1, "море-праху")
	for i in 60:
		combat.tick_casts(0.1)
	summons.tick(0.1)
	var two: Array = summons.of_owner(1)
	_expect("прикликано двох", two.size(), 2)
	_expect("вид — порожній скелет-воїн",
			_creatures[two[0]].kind if not two.is_empty() else 0, 122)

	print("\n— господар загинув —")
	hero.hp = 0
	summons.tick(0.1)
	_expect("прикликані зникли", summons.of_owner(1).size(), 0)

	print("\nпомилок: %d" % _bad)
	quit()
