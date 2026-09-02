extends SceneTree
## Проба вікна смерті: підйом у місто числами.
##
## Ганяти так:
##     godot --headless --path game --script res://probes/revive.gd
##
## Досі труп гравця лежав двадцять хвилин і підводився сам (П-69) —
## гра після смерті просто спинялась. Кнопка «Повернутися в місто» робить
## те саме, тільки одразу, і перевіряти тут треба дві речі: що вона
## піднімає мертвого і що вона НЕ піднімає живого. Друге важливіше:
## інакше це безплатний телепорт додому посеред бою.

const AVATAR := preload("res://scenes/avatar.tscn")


class Recorder extends Messenger:
	var sent: Array = []

	func _init(vision: Vision = null) -> void:
		super(null, vision)

	func to_one(peer: int, method: StringName, args: Array = []) -> void:
		sent.append({"peer": peer, "method": String(method), "args": args})

	func methods() -> Array:
		var out: Array = []
		for m in sent:
			out.append(m["method"])
		return out


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	await _revive()
	await _window()
	await _menu()
	quit()


func _revive() -> void:
	print("\n— підйом у місто —")
	var hero: Node3D = AVATAR.instantiate()
	root.add_child(hero)
	await process_frame
	hero.place_at(Vector3(40, 1.5, 40), 0.0)
	var creatures := {1: hero}
	var vision := Vision.new(creatures)
	vision.watch(1)
	vision.update(1)
	var link := Recorder.new(vision)
	var combat := Combat.new(creatures, link)

	print("  живого не піднімає: %s (має бути false)" % combat.revive(1))

	hero.hp = 0
	hero.die()
	print("  загинув за %.1f, %.1f — труп лежатиме %.0f с"
			% [hero.global_position.x, hero.global_position.z,
			   hero.corpse_left])
	link.sent.clear()
	var raised: bool = combat.revive(1)
	print("  кнопка: %s, здоров'я %d із %d (%.0f%% за REVIVE_SHARE %.2f)"
			% [raised, hero.hp, hero.stats.max_hp(),
			   100.0 * hero.hp / maxf(1.0, hero.stats.max_hp()),
			   hero.REVIVE_SHARE])
	print("  де опинився: %.1f, %.1f (місто — 0,0)"
			% [hero.global_position.x, hero.global_position.z])
	print("  надіслано: %s" % [link.methods()])
	print("  строк трупа знято: %s" % [hero.corpse_left <= 0.0])
	print("  удруге, уже живому: %s (має бути false)" % combat.revive(1))
	hero.queue_free()


## Саме вікно: чи є кнопка і чи доходить її натиск.
func _window() -> void:
	print("\n— вікно смерті —")
	var hud := HUD.new()
	root.add_child(hud)
	hud.setup(root)
	await process_frame
	var heard := [false]
	hud.wants_revive.connect(func() -> void: heard[0] = true)

	var box: Control = hud.find_child("ВікноСмерті", true, false)
	var press: Button = hud.find_child("ВМісто", true, false)
	print("  вікно знайдено: %s, кнопка: «%s»"
			% [box != null, press.text if press != null else "—"])
	if box == null or press == null:
		return
	print("  до смерті сховане: %s" % [not box.visible])
	hud.died()
	print("  після смерті видно: %s" % [box.visible])
	press.pressed.emit()
	print("  натиск дійшов: %s" % heard[0])
	hud.revived()
	print("  після підйому сховане: %s" % [not box.visible])
	hud.queue_free()


## Меню внизу праворуч: дві кнопки й сторінка статів.
func _menu() -> void:
	print("\n— меню й стати —")
	var hud := HUD.new()
	root.add_child(hud)
	hud.setup(root)
	await process_frame
	var menu: Control = hud.find_child("Меню", true, false)
	var page: Control = hud.find_child("СторінкаСтатів", true, false)
	var numbers: Label = hud.find_child("Числа", true, false)
	if menu == null or page == null or numbers == null:
		print("  ‼ меню не зібралось")
		return
	var names := PackedStringArray()
	for child in menu.get_children():
		if child is Button:
			names.append(child.text)
	print("  кнопки в куті: %s" % [names])
	print("  сторінка статів спершу схована: %s" % [not page.visible])

	hud.set_stats({
		"раса": "орк", "стать": "чоловік", "рівень": 3, "очки": 6,
		"сила": 14, "сила базова": 12,
		"спритність": 9, "спритність базова": 9,
		"витривалість": 12, "витривалість базова": 12,
		"інтелект": 8, "інтелект базова": 8,
		"чуття": 10, "чуття базова": 10,
		"здоров'я": 136, "мана": 56,
		"атака": 9.2, "магічна атака": 6.4,
		"захист": 18.0, "магічний захист": 18.0})
	for child in menu.get_children():
		if child is Button and child.text == "Стати":
			child.pressed.emit()
	print("  після натиску видно: %s" % [page.visible])
	print("  на сторінці:")
	for line in numbers.text.split("\n"):
		if line != "":
			print("      %s" % line)
	hud.queue_free()
