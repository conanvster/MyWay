extends SceneTree
## Сет броні на аватарі тим шляхом, яким його вдягає гра (13.11.2026, слово замовника:
## «перенеси в гру»): `avatar.apply_sex` → `avatar.wear(look, goods)` з речами з
## `data/items.json`. Перевіряє, що кожна важка річ показує свої деталі, знята — ховає,
## а тіло під чобітьми й наручами ховається.
##
##     godot --headless --path game --script res://probes/set_look.gd [-- --раса орк --стать чоловік]

const AVATAR := preload("res://scenes/avatar.tscn")
## Що має показати важка річ у комірці (деталі `Одяг-<комірка>-важка-<деталь>`).
const EXPECT := {
	"тіло": ["тіло-важка-наплічники", "тіло-важка-пояс"],
	"рукавиці": ["рукавиці-важка-наручі"],
	"взуття": ["взуття-важка-чоботи"],
}

var _bad := 0


func _init() -> void:
	call_deferred("_go")


func _arg(args: PackedStringArray, key: String, fallback: String) -> String:
	var at := args.find(key)
	return args[at + 1] if at >= 0 and at + 1 < args.size() else fallback


func _go() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var race := _arg(args, "--раса", "орк")
	var sex := _arg(args, "--стать", "чоловік")
	var goods := ItemBook.new()
	goods.load_from(JSON.parse_string(
			FileAccess.get_file_as_string("res://data/items.json")))
	var hero: Node3D = AVATAR.instantiate()
	root.add_child(hero)
	await process_frame
	var started := Time.get_ticks_msec()
	hero.apply_sex(sex, race)
	var skin: SkinnedModel = hero.model()
	print("\n— сет на аватарі: %s, %s · модель %s · збирання %d мс —"
			% [race, sex, skin.path if skin != null else "—",
			Time.get_ticks_msec() - started])
	if skin == null:
		quit(1)
		return
	# Важкі речі кожного грейду: назви з даних, не вписані сюди.
	var heavy := {}
	for name: String in goods.bases:
		var base: Dictionary = goods.base_of(name)
		if str(base.get("тип", "")) == "важка" and EXPECT.has(str(base.get("слот", ""))):
			(heavy.get_or_add(str(base["слот"]), []) as Array).append(name)
	_expect(skin, [], "без речей")
	for slot: String in EXPECT:
		for name: String in heavy.get(slot, []):
			hero.wear({slot: name}, goods)
			_expect(skin, EXPECT[slot], "%s = %s" % [slot, name])
		hero.wear({}, goods)
		_expect(skin, [], "знято: %s" % slot)
	var full := {}
	var want: Array = []
	for slot: String in EXPECT:
		if heavy.has(slot):
			full[slot] = heavy[slot][0]
			want.append_array(EXPECT[slot])
	hero.wear(full, goods)
	_expect(skin, want, "повний сет")
	var hide: Variant = null
	for m: ShaderMaterial in skin._sculpt_mats:
		hide = m.get_shader_parameter("hide_under")
	print("  тіло під річчю (канали сорочка, штани, взуття, рукавиці): %s" % hide)
	if hide == null or (hide as Vector4).z < 0.5 or (hide as Vector4).w < 0.5:
		_bad += 1
		print("  ‼ стопа чи передпліччя під річчю не ховається")
	print("  підсумок: %s" % ("усе гаразд" if _bad == 0 else "‼ вад: %d" % _bad))
	quit(1 if _bad > 0 else 0)


func _expect(skin: SkinnedModel, want: Array, what: String) -> void:
	var seen: Array = []
	for mesh: MeshInstance3D in skin.find_children(
			SkinnedModel.PIECE_PREFIX + "*", "MeshInstance3D", true, false):
		if mesh.visible:
			seen.append(str(mesh.name).trim_prefix(SkinnedModel.PIECE_PREFIX))
	seen.sort()
	var need := want.duplicate()
	need.sort()
	if seen != need:
		_bad += 1
		print("  ‼ %s: видно %s, має бути %s" % [what, seen, need])
	else:
		print("  ✓ %s: %s" % [what, seen])
