extends Node
## Проба клієнта для Mac (26.11.2026): шлях гравця від стартової сторінки
## до світу — так, як його пройде людина, тільки руками проби.
##
##   1. на сторінці (`--лише-мережа`, як у зібраному клієнті) — розбір
##      адреси: порожня, кривий порт, IPv6 — кожна з поясненням;
##   2. «Підключитися» до порту, де нікого немає, — сторінка має
##      повернутись із причиною за `CONNECT_WAIT`, а не мовчати;
##   3. «Підключитися» до справжнього сервера → «Завести акаунт» →
##      «Створити» персонажа → натиснути на нього → персонаж у світі;
##   4. «Вийти» (як у HUD) і знову: «Увійти» тим самим акаунтом → обрати
##      НАЯВНОГО персонажа → у світі.
##
## Сервер проба не піднімає. Потрібен сервер із базою на НЕТИПОВОМУ порту
## (24565 може бути гри замовника):
##     ./run-db.sh &
##     godot --headless --path game -- --server --світ2 --порт 24601 \
##         --база http://127.0.0.1:3000
## Ганяти:
##     godot --headless --path game res://scenes/remote_join.tscn -- \
##         --лише-мережа --світ2 --адреса 127.0.0.1:24601 --мертвий 24609
## `--адреса` — куди стукати (і LAN-IP цього ПК теж); `--мертвий` — порт,
## де точно нікого немає. Акаунт і персонаж — тестові, з міткою часу.

const LAUNCHER := preload("res://scenes/launcher.tscn")
const NET := preload("res://scripts/net.gd")

var _failed := 0
## Адреса, що лежала в `ADDRESS_FILE` до проби: проба її повертає, щоб
## сторінка людини не підставила тестовий порт.
var _kept := ""


func _ready() -> void:
	_go.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("  %s %s" % ["✓" if ok else "✗", what])
	if not ok:
		_failed += 1


func _arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	var at := args.find(name)
	return args[at + 1] if at != -1 and at + 1 < args.size() else fallback


## Чекати, доки `test` не скаже «так», але не довше `seconds`.
func _until(test: Callable, seconds: float) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < seconds * 1000.0:
		if test.call():
			return true
		await get_tree().process_frame
	return false


func _page() -> Node:
	for child in get_tree().root.get_children():
		if child.get_script() == preload("res://scripts/launcher.gd") \
				and not child.is_queued_for_deletion():
			return child
	return null


func _world() -> Node:
	for child in get_tree().root.get_children():
		if child.has_method("client_sign_needed") \
				and not child.is_queued_for_deletion():
			return child
	return null


func _open_page() -> Node:
	if _page() == null:
		get_tree().root.add_child(LAUNCHER.instantiate())
	await _until(func() -> bool: return _page() != null, 5.0)
	await get_tree().process_frame
	return _page()


func _go() -> void:
	var address := _arg("--адреса", "127.0.0.1:24601")
	var dead := _arg("--мертвий", "24609")
	var stamp := str(int(Time.get_unix_time_from_system()))
	var login := "test-mac-%s" % stamp
	var password := "test-mac-parol"
	var hero := "ТестMac%s" % stamp.right(5)
	_kept = NET.last_address()

	print("\n— 1. розбір адреси —")
	_check(NET.parse_address("").has("why"), "порожня — пояснення")
	_check(NET.parse_address("192.168.1.48:99999").has("why"),
			"порт 99999 — пояснення")
	_check(NET.parse_address("::1").has("why"), "IPv6 — пояснення")
	var plain := NET.parse_address(" 192.168.1.48 ")
	_check(plain.get("host") == "192.168.1.48" \
			and plain.get("port") == NET.PORT,
			"без порту — типовий %d" % NET.PORT)
	var full := NET.parse_address("10.0.0.5:24601")
	_check(full.get("host") == "10.0.0.5" and full.get("port") == 24601,
			"з портом — 10.0.0.5:24601")
	var page := await _open_page()
	_check(page._play == null, "у режимі «лише мережа» кнопок бази й " \
			+ "сервера немає")
	page._address.text = "192.168.1.48:0"
	page._connect.pressed.emit()
	_check(page._log.text.contains("порт") and _world() == null,
			"кривий порт — світ не відкрито, сказано: «%s»" % page._log.text)

	print("\n— 2. сервера немає (порт %s) —" % dead)
	page._address.text = "127.0.0.1:%s" % dead
	var started := Time.get_ticks_msec()
	page._connect.pressed.emit()
	_check(NET.last_address() == "127.0.0.1:%s" % dead,
			"адресу запам'ятовано в %s" % NET.ADDRESS_FILE)
	await _until(func() -> bool: return _world() != null, 5.0)
	var back := await _until(func() -> bool:
			return _world() == null and _page() != null, 30.0)
	var took := (Time.get_ticks_msec() - started) / 1000.0
	page = _page()
	_check(back and page != null and page._log.text.contains("не відповів"),
			"повернуло на сторінку за %.1f с: «%s»" % [took,
			page._log.text if page != null else "—"])
	# Світ 2 будується в клієнта ~5 с ДО того, як той почне стукати, і
	# лише тоді йде відлік `CONNECT_WAIT` (10 с).
	_check(took < 25.0, "не довше за 25 с (побудова світу + 10 с чекання)")

	print("\n— 3. новий акаунт, новий персонаж (%s) —" % address)
	var sign := await _join(address)
	if sign == null:
		_finish()
		return
	sign._login.text = login
	sign._password.text = password
	sign._sign_up.pressed.emit()
	_check(await _until(func() -> bool: return sign._pick_box.visible, 20.0),
			"акаунт %s заведено, видно перелік персонажів" % login)
	sign._new_name.text = hero
	sign._create.pressed.emit()
	_check(await _until(func() -> bool:
			return sign._list.get_child_count() > 0, 20.0),
			"персонажа %s створено, він у переліку" % hero)
	await _enter_first(sign, hero)

	print("\n— 4. вийти й зайти НАЯВНИМ персонажем —")
	var world := _world()
	if world != null and world.hud != null:
		world.hud._quit()
	page = await _open_page()
	_check(page != null and page._address.text == address,
			"сторінка пам'ятає адресу: %s" % (page._address.text
			if page != null else "—"))
	sign = await _join(address)
	if sign == null:
		_finish()
		return
	sign._login.text = login
	sign._password.text = password
	sign._sign_in.pressed.emit()
	_check(await _until(func() -> bool:
			return sign._pick_box.visible and sign._list.get_child_count() > 0,
			20.0), "увійшов, у переліку є %s" % hero)
	await _enter_first(sign, hero)
	world = _world()
	if world != null and world.hud != null:
		world.hud._quit()
	_finish()


## «Підключитися» на сторінці й дочекатись екрана входу.
func _join(address: String) -> SignScreen:
	var page := await _open_page()
	page._address.text = address
	page._connect.pressed.emit()
	var got := await _until(func() -> bool:
			var w := _world()
			return w != null and w.view != null and w.view._sign != null, 60.0)
	_check(got, "з'єднався, видно екран входу")
	if not got:
		var p := _page()
		print("    сторінка каже: %s" % (p._log.text if p != null else "—"))
		return null
	return _world().view._sign


## Натиснути на персонажа в переліку й дочекатись, що він у світі.
func _enter_first(sign: SignScreen, hero: String) -> void:
	var press: Button = null
	for b: Button in sign._list.get_children():
		if b.text.begins_with(hero):
			press = b
	_check(press != null, "кнопка «%s» є" % hero)
	if press == null:
		return
	press.pressed.emit()
	var world := _world()
	var inside := await _until(func() -> bool:
			return world.creatures.has(world.multiplayer.get_unique_id()) \
					and world.view._sign == null, 60.0)
	_check(inside, "персонаж у світі, екран входу прибрано")


func _finish() -> void:
	if _kept != "":
		NET.remember_address(_kept)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(
				NET.ADDRESS_FILE))
	print("\nпроба: %s, провалено %d" % ["ПРОЙДЕНО" if _failed == 0
			else "НЕ ПРОЙДЕНО", _failed])
	get_tree().quit(1 if _failed > 0 else 0)
