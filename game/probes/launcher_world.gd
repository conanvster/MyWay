extends SceneTree
## Проба: стартова сторінка піднімає сервер у ТОМУ Ж світі, що й сама.
##
## Слово замовника 11.09.2026: «персонаж з'являється під землею… немає
## змоги навіть зробити телепорт в місто». Причина: сторінка, відкрита з
## `--світ2`, піднімала сервер без нього — сервер будував світ версії 1,
## клієнт малював версії 2.
##
## Проба сама тисне «Підняти сервер», чекає на мітку «світ збудовано» і
## читає з неї, у якому світі сервер. Потім сама його зупиняє.
##
## Ганяти так (порт 24565 має бути вільний):
##     godot --headless --path game --script res://probes/launcher_world.gd
##     godot --headless --path game --script res://probes/launcher_world.gd -- --світ2

const LAUNCHER := preload("res://scripts/launcher.gd")


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	var mine := GameData.map_path().get_file()
	var page: Control = LAUNCHER.new()
	root.add_child(page)
	await process_frame
	if page._port_taken():
		print("‼ порт %d уже зайнято — зупини сервер і повтори"
				% LAUNCHER.SERVER_PORT)
		quit(1)
		return
	page._db_alive = false
	page._start_server()
	var started := Time.get_ticks_msec()
	var mark: Dictionary = {}
	while Time.get_ticks_msec() - started < 120000:
		await process_frame
		var got: Dictionary = page._ready_mark()
		if int(got.get("номер", -1)) == page._server_pid:
			mark = got
			break
	var theirs := str(mark.get("світ", "—"))
	print("\n— стартова сторінка в світі %s —" % mine)
	print("  сервер піднявся за %.1f с, мітка: %s"
			% [(Time.get_ticks_msec() - started) / 1000.0, mark])
	print("  світ сервера: %s" % theirs)
	page._check()
	print("  сторінка бачить розбіжність: «%s», «Зайти в гру» замкнена: %s"
			% [page._clash, page._play.disabled])
	page._stop_server()
	await process_frame
	var bad := mark.is_empty() or theirs != mine
	print("  %s" % ("‼ сервер НЕ в тому світі" if bad
			else "✓ сервер у тому самому світі, що й сторінка"))
	quit(1 if bad else 0)
