extends SceneTree
## Проба стартової сторінки: чи бачить вона живий сервер.
##
## Ганяти так:
##     godot --headless --path game --script res://probes/launcher.gd
##
## Навіщо вона взагалі з'явилась. Сторінка перевіряла сервер
## `StreamPeerTCP`, а ENet ходить по **UDP**: на TCP-порт 24565 не слухає
## ніхто й ніколи. Тому рядок «сервер: не запущений» горів і тоді, коли
## сервер працює й пише в журнал «сервер чекає гравців», кнопка «Зайти в
## гру» лишалась замкненою, а «Зупинити сервер» не мала кого зупиняти.
## Око цього не спіймало б: обидва стани виглядають однаково правдиво.
##
## Проба НЕ підіймає сервер сама. Ганяти двічі:
##   1) без сервера            — має бути «не запущений»
##   2) з піднятим сервером    — має бути «працює», і номер збігтись

const LAUNCHER := preload("res://scripts/launcher.gd")
const MARK := "user://сервер.json"


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	# Сторінку створюємо, але в дерево не додаємо: `_ready` малює кнопки,
	# а нам потрібні самі перевірки.
	var page: Control = LAUNCHER.new()

	print("\n— порт сервера (UDP %d) —" % LAUNCHER.SERVER_PORT)
	var taken: bool = page._port_taken()
	print("  зайнято: %s" % taken)
	# Те саме питання по-старому, через TCP: він мовчить завжди, і саме
	# тому сторінка була сліпа.
	var tcp := StreamPeerTCP.new()
	var err := tcp.connect_to_host("127.0.0.1", LAUNCHER.SERVER_PORT)
	if err == OK:
		tcp.poll()
		if tcp.get_status() == StreamPeerTCP.STATUS_CONNECTING:
			tcp.poll()
	var by_tcp: bool = err == OK \
			and tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED
	tcp.disconnect_from_host()
	print("  той самий порт через TCP: %s ← так було досі" % by_tcp)

	print("\n— мітка «світ збудовано» —")
	var mark: Dictionary = page._ready_mark()
	print("  файл %s: %s" % [MARK, "є" if FileAccess.file_exists(MARK)
			else "немає"])
	print("  прочитано: %s" % mark)

	print("\n— що побачить людина —")
	# Той самий порядок, що й у `_check`.
	page._port_busy = taken
	var alive: bool = taken and not mark.is_empty()
	var state := "не запущений"
	if alive:
		state = "працює"
	elif taken:
		state = "підіймається"
	print("  сервер: %s" % state)
	print("  кнопка «Зайти в гру» відімкнена: %s" % alive)
	print("  кнопка «Підняти сервер» відімкнена: %s" % (not taken))

	print("\n— кого зупинить кнопка —")
	print("  свого не піднімали, номер із мітки: %d" % page._pid_to_stop())
	page._server_pid = 4242
	print("  свій сервер має перевагу: %d" % page._pid_to_stop())
	page._server_pid = -1
	page._port_busy = false
	print("  порт вільний — мітці не віримо: %d" % page._pid_to_stop())

	page.free()
	quit()
