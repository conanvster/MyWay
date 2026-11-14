extends Node
## Знімок вікна «Речі» з розширеною торбою (14.11.2026: «зачищене
## підземелля +2 ячейки — з'являється полоса прокрутки»).
##
##     godot --path game res://scenes/bag_window.tscn -- [тека]
##
## Два кадри: 30 місць (смуги немає) і 34 місця з 31 річчю (смуга є,
## лічильник «торба: 31 / 34»). Не мережа — лише показ HUD.

var _dir := "user://торба"


func _ready() -> void:
	call_deferred("_go")


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_dir = args[0]
	DirAccess.make_dir_recursive_absolute(_dir)
	await get_tree().process_frame
	var data := GameData.new()
	data.load_all()
	var back := ColorRect.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.color = Color(0.24, 0.31, 0.22)
	add_child(back)
	var hud := HUD.new()
	add_child(hud)
	hud.setup(get_tree().root)
	await get_tree().process_frame
	hud.show_windows()
	# Карту показ відкриває теж — тут вона лише заступає торбу.
	if hud._map_box != null:
		hud._map_box.visible = false
	for shot: Array in [[28, 30, "1-30-місць"], [31, 34, "2-34-місця"]]:
		hud.set_things(_things(data, int(shot[0])), [], int(shot[1]))
		for i in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := "%s/%s.png" % [_dir, shot[2]]
		get_viewport().get_texture().get_image().save_png(path)
		print("знімок: %s" % path)
	get_tree().quit()


func _things(data: GameData, many: int) -> Array:
	var bases := ["пояс з кори дуба", "шолом з кори дуба", "перстень учня",
			"амулет учня", "рукавиці з кори дуба"]
	var out: Array = []
	for i in many:
		var base: String = bases[i % bases.size()]
		out.append({"номер": i, "назва": base, "база": base,
				"вид": data.items.kind_of(base),
				"слот": str(data.items.base_of(base).get("слот", "")),
				"грейд": "E", "вдягнене": false, "стати": ""})
	return out
