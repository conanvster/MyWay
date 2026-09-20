extends Node
## Проба до мапи: місто, мешканці, ліс, гори.
##
## Ганяти так:
##     godot --headless --path game --script res://probes/місто.gd

const MAIN := preload("res://scenes/main.tscn")


func _ready() -> void:
	call_deferred("_go")


func _go() -> void:
	await get_tree().process_frame
	var data := GameData.new()
	data.load_all()
	# Світ-клієнт сам стукає на 127.0.0.1, а там може саме йти
	# гра замовника (19.09.2026: проба під'єдналась до живого
	# сервера світу 2 й перезапускалась по колу). «Уже в мережі» —
	# і `Net.join()` нічого не робить.
	var net: Node = get_tree().root.get_node_or_null("Net")
	if net != null:
		net.joined = true
	var world: Node3D = MAIN.instantiate()
	get_tree().root.add_child(world)
	await get_tree().process_frame
	var land: Node = world.get_node("Landscape")
	land.build(data.map)
	await get_tree().process_frame

	print("\n— що збудовано —")
	var counted := {}
	for child in land.get_children():
		# Godot дає однаковим вузлам різні імена («Дерево», «Дерево2»…),
		# тож рахуємо за початком, а не за повним збігом.
		var kind := "інше"
		for word: String in ["Будинок", "Дерево", "Гора", "Мешканець",
				"Дах", "Крона"]:
			if str(child.name).begins_with(word):
				kind = word
				break
		counted[kind] = int(counted.get(kind, 0)) + 1
	print("  %s" % [counted])
	var sample: Array = []
	for child in land.get_children():
		if sample.size() < 6:
			sample.append(str(child.name))
	print("  як звуться перші вузли: %s" % [sample])

	print("\n— мешканці (замовник пробував клікнути по них) —")
	var dwellers := land.find_children("Мешканець-*", "NPC", true, false)
	for who: Node3D in dwellers:
		print("  %-24s на %s, шар %d, колір %s"
				% [who.title(), who.global_position, who.collision_layer,
				   who.tint.to_html(false)])
	print("  промінь миші шукає шари: %d (2 істоти + 4 мешканці)" % (2 | 4))

	# Двоє в одній точці (спіймано 20.09.2026: у столиці коваль і майстер
	# магії стояли один в одному). Міряємо по ДАНИХ, а не по сцені: у
	# сцені видно лише те місто, де стоїть проба.
	print("\n— чи не стоять мешканці один в одному —")
	var closest := INF
	var pair := ""
	for town: Dictionary in (data.map.get("міста", [])
			+ data.map.get("села", [])):
		var folk: Array = town.get("мешканці", [])
		for i in folk.size():
			for j in range(i + 1, folk.size()):
				var a: Array = folk[i]["де"]
				var b: Array = folk[j]["де"]
				var d: float = Vector2(float(a[0]) - float(b[0]),
						float(a[2]) - float(b[2])).length()
				if d < closest:
					closest = d
					pair = "%s: %s і %s" % [town.get("назва", "?"),
							folk[i]["хто"], folk[j]["хто"]]
	print("  найтісніша пара в усьому світі: %.1f м (%s)"
			% [closest, pair])
	print("  %s" % ("‼ ближче за 3 м — вони накладаються"
			if closest < 3.0 else "просвіт усюди більший за 3 м"))
	print("  усі на шарі 4: %s" % dwellers.all(
			func(x): return x.collision_layer == 4))

	print("\n— монстри: видно, хто є хто (П-105) —")
	for kind: int in [1, 2]:
		var look: Dictionary = data.for_kind(kind).get("вигляд", {})
		print("  вид %d (%s): колір %s, зріст %s"
				% [kind, data.for_kind(kind).get("назва", "?"),
				   look.get("колір", "—"), look.get("зріст", "—")])

	print("\n— чи не стоїть благодатне місце в будинку —")
	var holy: Node3D = world.get_node("GracePlace")
	print("  благодатне місце в %s" % holy.global_position)
	var inside := false
	for child in land.get_children():
		if child.name.begins_with("Будино"):
			var far: float = child.global_position.distance_to(
					holy.global_position)
			if far < 6.0:
				inside = true
			print("    будинок у %s — за %.1f" % [child.global_position, far])
	print("  жоден не ближче за 6,0: %s" % not inside)
	world.queue_free()
	get_tree().quit()
