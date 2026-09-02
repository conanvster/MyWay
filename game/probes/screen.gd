extends SceneTree
## Проба картинки: чи клієнт справді щось намалював.
##
## Ганяти так (після того, як клієнт у режимі показу лишив знімки):
##     godot --headless --path game --script res://probes/screen.gd
##
## Навіщо. «Клієнт запустився» без картинки нічого не означає: камера вже
## одного разу дивилась угору, і жодної помилки при цьому не було
## (пастка з CONTEXT.md). Тому дивимось на пікселі — це найдешевше
## «візуальне підтвердження», яке можна поставити в перевірку.
##
## Що вважається підтвердженням:
##   1. знімок узагалі є і не порожній;
##   2. кольорів більше за жменю — тобто це сцена, а не залитий екран;
##   3. у лівому верхньому куті є червона смуга здоров'я — її малює показ,
##      і з'являється вона лише тоді, коли персонаж уже у світі.

## Скільки кольорів вважаємо ознакою намальованої сцени.
const COLORS_MIN := 200
## Скільки червоних точок має бути у смузі здоров'я.
const HEALTH_MIN := 300


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	var newest := _newest()
	if newest.is_empty():
		print("  ‼ знімків немає — клієнт не дійшов до показу")
		quit(1)
		return
	var image := Image.load_from_file(newest)
	if image == null or image.get_width() == 0:
		print("  ‼ знімок не читається: %s" % newest)
		quit(1)
		return

	var wide := image.get_width()
	var high := image.get_height()
	print("  знімок: %s" % newest.get_file())
	print("  розмір: %d×%d" % [wide, high])

	# Кольори рахуємо по сітці, а не по кожній точці: мільйон звернень до
	# `get_pixel` у GDScript — це секунди, а відповідь та сама.
	var seen := {}
	for x in range(0, wide, 4):
		for y in range(0, high, 4):
			seen[image.get_pixel(x, y).to_rgba32()] = true
	print("  різних кольорів: %d (треба понад %d)" % [seen.size(), COLORS_MIN])

	# Смуга здоров'я: показ малює її від лівого краю, згори.
	var red := 0
	for x in range(4, mini(300, wide)):
		for y in range(14, mini(40, high)):
			var color := image.get_pixel(x, y)
			if color.r > 0.5 and color.g < 0.35 and color.b < 0.35:
				red += 1
	print("  червоних точок у смузі здоров'я: %d (треба понад %d)"
			% [red, HEALTH_MIN])

	var ok: bool = seen.size() > COLORS_MIN and red > HEALTH_MIN
	if ok:
		print("  ✓ світ намальовано, показ на місці")
	else:
		if seen.size() <= COLORS_MIN:
			print("  ‼ на екрані заливка, а не сцена")
		if red <= HEALTH_MIN:
			print("  ‼ смуги здоров'я немає — персонаж не зайшов у світ")
	quit(0 if ok else 1)


## Найсвіжіший знімок із user://.
func _newest() -> String:
	var at := "user://"
	var dir := DirAccess.open(at)
	if dir == null:
		return ""
	var best := ""
	var best_at := -1
	for name in dir.get_files():
		if not name.begins_with("знімок-") or not name.ends_with(".png"):
			continue
		var path: String = at.path_join(name)
		var when: int = FileAccess.get_modified_time(path)
		if when > best_at:
			best_at = when
			best = path
	return best
