extends Node
## Драбина спорядження (задачі З-1…З-6 зі `spec/спорядження.md`).
##
## Слово замовника 20.09.2026: «визнач яка кількість предметів є
## обовязковою на яких рівнях і наскільки доступні».
##
## Перевіряємо числами: у кожного слота кожного грейду є що вдягти,
## кожна річ звідкись падає, стати й ціни ростуть із грейдом, крамар не
## торгує верхами, а верхні грейди беруться в підземеллях.
##
##     godot --headless --path game res://scenes/gear.tscn

var _ok := 0
var _bad := 0
var _data: GameData


func _ready() -> void:
	_go()


func _yes(text: String, is_ok: bool) -> void:
	_ok += 1 if is_ok else 0
	_bad += 0 if is_ok else 1
	print("  %s %s" % ["✓" if is_ok else "✗", text])


func _go() -> void:
	await get_tree().process_frame
	_data = GameData.new()
	_data.load_all()
	_набір()
	_зростання()
	_джерела()
	_крамар()
	_афікси()
	print("  підсумок: %s" % ("усе гаразд" if _bad == 0
			else "‼ вад: %d" % _bad))
	get_tree().quit(1 if _bad > 0 else 0)


func _grades() -> Array:
	return _data.items.bases.get("грейди", {}).keys() if false \
			else ItemBook.GRADES


## Носиме: тільки те, що має слот.
func _worn() -> Dictionary:
	var out: Dictionary = {}
	for name: String in _data.items.bases:
		var base: Dictionary = _data.items.bases[name]
		if base.has("слот"):
			out[name] = base
	return out


func _набір() -> void:
	print("\n— у кожного слота кожного грейду є що вдягти —")
	var worn := _worn()
	var by: Dictionary = {}
	for name: String in worn:
		var base: Dictionary = worn[name]
		var key := "%s/%s" % [str(base.get("грейд", "?")),
				str(base.get("слот", "?"))]
		by[key] = int(by.get(key, 0)) + 1
	var slots: Array = ["голова", "тіло", "ремінь", "рукавиці", "взуття",
			"щит", "зброя", "підвіска", "перстень"]
	var порожні: Array = []
	for grade: String in ItemBook.GRADES:
		for slot: String in slots:
			if int(by.get("%s/%s" % [grade, slot], 0)) == 0:
				порожні.append("%s/%s" % [grade, slot])
	print("    носимих баз %d на %d грейдів" % [worn.size(),
			ItemBook.GRADES.size()])
	if not порожні.is_empty():
		print("    ‼ порожньо: %s" % [порожні])
	_yes("жодного порожнього слота в жодному грейді", порожні.is_empty())

	# Дві зброї на грейд: одноручна зі щитом і дворучна.
	var руки: Array = []
	for grade: String in ItemBook.GRADES:
		var one := 0
		var two := 0
		for name: String in worn:
			var base: Dictionary = worn[name]
			if str(base.get("грейд", "")) != grade \
					or str(base.get("слот", "")) != "зброя":
				continue
			if bool(base.get("дві руки", false)):
				two += 1
			else:
				one += 1
		if one == 0 or two == 0:
			руки.append(grade)
	_yes("у кожному грейді є і одноручна зброя, і дворучна",
			руки.is_empty())


func _зростання() -> void:
	print("\n— чим вищий грейд, тим сильніша річ —")
	var worn := _worn()
	var падіння: Array = []
	for slot: String in ["голова", "тіло", "зброя", "перстень"]:
		var попередній := -1
		var ряд: Array = []
		for grade: String in ItemBook.GRADES:
			var краще := -1
			for name: String in worn:
				var base: Dictionary = worn[name]
				if str(base.get("грейд", "")) != grade \
						or str(base.get("слот", "")) != slot \
						or bool(base.get("дві руки", false)):
					continue
				var сума := 0
				for stat: String in base.get("стати", {}):
					сума += int(base["стати"][stat])
				краще = maxi(краще, сума)
			ряд.append("%s:%d" % [grade, краще])
			if краще < попередній:
				падіння.append("%s %s" % [slot, grade])
			попередній = краще
		print("    %-10s %s" % [slot, " ".join(PackedStringArray(ряд))])
	_yes("стати не падають із грейдом", падіння.is_empty())

	var ціни: Array = []
	var попередня := -1
	for grade: String in ItemBook.GRADES:
		var найдорожча := 0
		for name: String in worn:
			var base: Dictionary = worn[name]
			if str(base.get("грейд", "")) == grade:
				найдорожча = maxi(найдорожча, int(base.get("ціна", 0)))
		ціни.append("%s:%d" % [grade, найдорожча])
		if найдорожча < попередня:
			_bad += 1
		попередня = найдорожча
	print("    найдорожча річ грейду: %s" % " ".join(
			PackedStringArray(ціни)))
	_yes("ціни ростуть із грейдом", попередня > 0)


func _джерела() -> void:
	print("\n— чи здобувається —")
	var worn := _worn()
	var падає: Dictionary = {}
	var глибоке: Dictionary = {}
	for kind: String in _data.mobs:
		var mob: Dictionary = _data.mobs[kind]
		for row: Dictionary in mob.get("дроп", []):
			var name := str(row.get("що", ""))
			var chance := float(row.get("шанс", 0.0))
			падає[name] = maxf(float(падає.get(name, 0.0)), chance)
			if not bool(mob.get("підземелля", false)):
				глибоке[name] = false
			elif not глибоке.has(name):
				глибоке[name] = true
	var нізвідки: Array = []
	var рідко: Array = []
	for name: String in worn:
		if not падає.has(name):
			нізвідки.append(name)
		elif 1.0 / float(падає[name]) > 30.0:
			рідко.append("%s (~%d)" % [name, roundi(1.0 / float(падає[name]))])
	if not нізвідки.is_empty():
		print("    ‼ нізвідки: %s" % [нізвідки])
	_yes("кожна носима річ звідкись падає", нізвідки.is_empty())
	if not рідко.is_empty():
		print("    ‼ рідше ніж раз на 30 вбивств: %s" % [рідко.slice(0, 6)])
	_yes("жодна не рідша за ~30 вбивств", рідко.is_empty())

	var не_в_підземеллі: Array = []
	for name: String in worn:
		var grade := str(worn[name].get("грейд", "E"))
		if grade in ["A", "S", "SS"] and глибоке.get(name, false) == false \
				and падає.has(name):
			не_в_підземеллі.append(name)
	print("    речей A/S/SS, що падають і поза підземеллям: %d"
			% не_в_підземеллі.size())
	_yes("A, S і SS беруться тільки в підземеллях",
			не_в_підземеллі.is_empty())


func _крамар() -> void:
	print("\n— що тримає крамар —")
	var worn := _worn()
	var stock: Array = _data.items.trade.get("асортимент крамаря", [])
	var високе: Array = []
	var скільки := 0
	for name: String in stock:
		if not worn.has(name):
			continue
		скільки += 1
		var grade := str(worn[name].get("грейд", "E"))
		if ItemBook.GRADES.find(grade) > ItemBook.GRADES.find("D"):
			високе.append("%s (%s)" % [name, grade])
	print("    носимого в асортименті %d, з них вище D: %d"
			% [скільки, високе.size()])
	_yes("крамар торгує лише грейдами E і D", високе.is_empty())
	_yes("а нижні грейди в нього таки є", скільки >= 20)


func _афікси() -> void:
	print("\n— афікс росте з грейдом (З-6) —")
	var step := float(_data.items.affixes.get("крок за грейд", 0.0))
	_yes("крок за грейд заданий у даних", step > 0.0)
	# Міряємо, а не віримо: кидаємо ту саму річ сто разів і беремо
	# найбільший афікс.
	var найбільший := {}
	for name: String in ["куртка з кори дуба", "зоряний панцир"]:
		if not _data.items.has(name):
			continue
		var top := 0
		for _i in 200:
			var item: Item = _data.items.make(name)
			for affix: Dictionary in item.affixes:
				top = maxi(top, int(affix["скільки"]))
		найбільший[name] = top
	print("    найбільший афікс за 200 кидків: %s" % [найбільший])
	_yes("на SS афікс більший, ніж на E",
			int(найбільший.get("зоряний панцир", 0))
			> int(найбільший.get("куртка з кори дуба", 99)))
