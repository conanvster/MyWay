extends SceneTree
## Проба екрана створення персонажа з вибором зовнішності (07.11.2026).
##
##     godot --path game --script res://probes/look_pick.gd [-- <тека>]
##
## Кожна раса й стать: модель у вікні, перелік виборів; для сканів —
## ще й вибрана зачіска й кольори. Знімок на кожен тип, а в журнал —
## що саме запропоновано і що піде на сервер (`Appearance.clean`).

var _dir := "user://вибір-зовнішності"
var _bad := 0


func _init() -> void:
	call_deferred("_go")


func _expect(what: String, ok: bool) -> void:
	if not ok:
		_bad += 1
	print("  %s %s" % ["✓" if ok else "✗", what])


func _go() -> void:
	create_timer(120.0).timeout.connect(func() -> void:
		print("‼ проба не скінчилась за 2 хв")
		quit(1))
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_dir = args[0]
	DirAccess.make_dir_recursive_absolute(_dir)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var screen := SignScreen.new()
	root.add_child(screen)
	screen.setup()
	var sent: Array = []
	screen.wants_new_character.connect(func(n: String, r: String, s: String,
			look: Dictionary) -> void:
		sent.append([n, r, s, look]))
	screen.show_characters([])
	var cases := [
		["ельф", "жінка", {"зачіска": "коса", "волосся": "рудий",
				"очі": "зелені"}],
		["ельф", "жінка", {}, 2],
		["людина", "жінка", {}, 3],
		["людина", "жінка", {"зачіска": "каре", "волосся": "чорний",
				"очі": "блакитні", "шкіра": "смаглява"}],
		["орк", "жінка", {"зачіска": "коси", "волосся": "сивий",
				"очі": "бурштинові"}],
		["орк", "жінка", {}, 3],
		["людина", "чоловік", {}],
	]
	for c: Array in cases:
		screen._race.select(["людина", "орк", "ельф"].find(c[0]))
		screen._sex.select(["чоловік", "жінка"].find(c[1]))
		screen._pick_variant(int(c[3]) if c.size() > 3 else 1)
		screen._chosen.merge(c[2], true)
		screen._refresh_preview()
		_expect("картки: 3 кадри вікі, натиснута %d" % screen._chosen["варіант"],
				screen._card_buttons.all(func(b: Button) -> bool:
					return b.icon != null)
				and screen._card_buttons[int(screen._chosen["варіант"]) - 1]
					.button_pressed)
		for i in 20:
			await process_frame
		var rows := screen._look_grid.get_child_count() / 2
		var opts: Dictionary = screen._preview.look_options()
		print("\n— %s, %s —" % [c[0], c[1]])
		print("    зачіски моделі: %s; рядків вибору: %d; примітка: «%s»"
				% [opts["зачіски"], rows, screen._look_note.text])
		if c.size() > 3:
			var want: Dictionary = Appearance.preset(c[0], c[1], c[3])
			_expect("варіант %d = кадр вікі: %s" % [c[3], want],
					screen._chosen == want)
			c[2] = want
		if c[2].is_empty():
			_expect("без скану — вибору немає, примітка є",
					rows == 0 and screen._look_note.text != "")
		else:
			_expect("скан: є зачіски й кольори (рядків ≥ 5)",
					rows >= 5 and not opts["зачіски"].is_empty())
			var shown := ""
			for m: MeshInstance3D in screen._preview.find_children(
					"Волосся-*", "MeshInstance3D", true, false):
				if m.visible:
					shown = str(m.name)
			_expect("видно саме «Волосся-%s» (видно: %s)"
					% [c[2]["зачіска"], shown],
					shown == "Волосся-" + str(c[2]["зачіска"]))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%s-%s-%d.png"
				% [_dir, c[0], c[1], screen._chosen["варіант"]])
		screen._new_name.text = "Проба-" + c[0]
		screen._create_now()
		screen._create.disabled = false
	print("\n— що піде на сервер —")
	for row: Array in sent:
		var clean := Appearance.clean(row[3])
		print("    %s %s %s → %s" % [row[0], row[1], row[2], clean])
	_expect("усі %d створень пішли з зовнішністю" % cases.size(),
			sent.size() == cases.size())
	_expect("сервер не пускає вигаданий колір",
			not Appearance.clean({"волосся": "золотий", "варіант": 9})
				.has("волосся")
			and Appearance.clean({"варіант": 9})["варіант"] == 3)
	print("\nзнімки: %s\nпомилок: %d" % [ProjectSettings.globalize_path(_dir),
			_bad])
	quit(1 if _bad > 0 else 0)
