extends SceneTree
## Проба П-22 (перша половина): ресурс можна продати крамареві.
##
##     godot --headless --path game --script res://probes/resources_sell.gd
##
## Кожен «ресурс» із `items.json`: крамар не відмовляє й дає більше нуля.
## Ресурс без ціни — показати, а не ставити число мовчки (P3).

var _bad := 0


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	var data := GameData.new()
	data.load_all()
	var shop := Shop.new(data)
	var total := 0
	var no_price: Array = []
	for name: String in data.items.bases:
		if str(data.items.bases[name].get("вид", "")) != "ресурс":
			continue
		total += 1
		var paid := shop.buy_price(name)
		if shop.refuses(name) or paid <= 0:
			no_price.append("%s (ціна %s)" % [name,
					str(data.items.bases[name].get("ціна", "немає"))])
		else:
			print("  ✓ %s — крамар дає %d" % [name, paid])
	print("\nресурсів %d, без викупу %d" % [total, no_price.size()])
	for one: String in no_price:
		print("  ✗ %s" % one)
	print("помилок: %d" % no_price.size())
	quit()
