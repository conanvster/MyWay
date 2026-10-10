extends SceneTree
## Проба вмінь від речей (П-221): «складаються» з вивченими.
##
##     godot --headless --path game --script res://probes/item_skills.gd
##
## Речей із вмінням у даних ще немає — вміння ставимо на річ руками, як
## його поставить база з полем «вміння».

const AVATAR := preload("res://scenes/avatar.tscn")
const BEAM := "енергетичний-промінь"
const CRY := "клич-хоробрості"

var _bad := 0


func _init() -> void:
	call_deferred("_go")


func _expect(what: String, got: Variant, want: Variant) -> void:
	var ok: bool = got == want
	if not ok:
		_bad += 1
	print("  %s %s: %s%s" % ["✓" if ok else "✗", what, str(got),
			"" if ok else " (чекали %s)" % str(want)])


func _go() -> void:
	await process_frame
	var data := GameData.new()
	data.load_all()
	var hero: Node3D = AVATAR.instantiate()
	root.add_child(hero)
	await process_frame
	hero.level = 30
	hero.learned.clear()
	hero.learn(BEAM, 1)

	var sword: Item = data.items.make("меч з кори дуба")
	sword.skills = {BEAM: 2, CRY: 1}
	var at: int = hero.add_thing(sword)

	print("\n— у торбі, не вдягнуто —")
	_expect("промінь — лише вивчений рівень", hero.skill_level(BEAM), 1)
	_expect("клича не знає", hero.knows(CRY), false)

	print("\n— вдягнуто —")
	hero.equip(at)
	_expect("промінь 1 + 2 = 3", hero.skill_level(BEAM), 3)
	_expect("клич від речі — знає", hero.knows(CRY), true)
	_expect("перелік діючих: обидва", hero.skill_keys().has(CRY), true)

	var runes := Runes.new(data.skills, data.professions)
	var why: String = runes.learn(hero, CRY)
	print("    вивчити клич, коли він є від речі: «%s»" % why)
	_expect("річ не заважає вчити руною", why.contains("уже вивчено"), false)

	print("\n— затуплена зброя —")
	sword.durability_max = 100
	sword.durability = 0
	_expect("затуплена — вміння не дає", hero.skill_level(BEAM), 1)
	sword.durability = 100

	print("\n— зняв —")
	hero.unequip("зброя")
	_expect("промінь знову 1", hero.skill_level(BEAM), 1)
	_expect("клич зник", hero.knows(CRY), false)

	print("\n— бій бере рівень зі складеного —")
	hero.equip(at)
	var combat := Combat.new({1: hero})
	combat.skills = data.skills
	hero.mp = 10000
	hero.target_id = 0
	var before: int = hero.mp
	combat.cast(1, CRY)
	_expect("клич читається лише від речі", hero.mp < before
			or hero.is_casting(), true)
	print("\nпомилок: %d" % _bad)
	quit()
