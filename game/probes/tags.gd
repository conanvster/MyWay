extends SceneTree
## Проба підписів: кольори за різницею рівнів (погоджено 02.09.2026).
##
## Ганяти так:
##     godot --headless --path game --script res://probes/tags.gd
##
## Кольори — не прикраса, а правило, за яким гравець вирішує, чи лізти в
## бій. Тому вони перевіряються числами, а не оком: око не відрізнить
## «-2» від «-3», а межа саме там.

func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	print("\n— колір імені за різницею рівнів —")
	var names := {
		"1.00 0.12 0.10": "яскраво-червоний",
		"0.88 0.26 0.20": "червоний",
		"1.00 0.64 0.20": "помаранчовий",
		"1.00 1.00 1.00": "білий",
		"0.45 0.76 1.00": "голубий",
		"0.24 0.38 0.82": "темно-синій"}
	for diff in [-9, -6, -5, -3, -2, 0, 2, 3, 4, 5, 6, 7, 12]:
		var color: Color = HUD.level_color(diff)
		var key := "%.2f %.2f %.2f" % [color.r, color.g, color.b]
		print("  моб %+3d рівня від мене -> %s" % [diff, names.get(key, key)])
	print("\n  межі, на яких це ламається найлегше:")
	print("    -3 і -2: %s проти %s"
			% [_short(HUD.level_color(-3)), _short(HUD.level_color(-2))])
	print("     2 і  3: %s проти %s"
			% [_short(HUD.level_color(2)), _short(HUD.level_color(3))])
	print("     6 і  7: %s проти %s"
			% [_short(HUD.level_color(6)), _short(HUD.level_color(7))])
	print("    -6 і -5: %s проти %s"
			% [_short(HUD.level_color(-6)), _short(HUD.level_color(-5))])
	quit()


func _short(color: Color) -> String:
	return "#" + color.to_html(false)
