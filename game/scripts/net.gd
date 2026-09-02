extends Node
## Підняття мережі. Автозавантаження, ім'я `Net`.
##
## Роль обирається аргументом після `--`:
##     godot --headless -- --server        сервер
##     godot -- --host 192.168.0.10        клієнт до вказаного вузла
## Без аргументів — клієнт до 127.0.0.1.

const PORT := 24565
## П-04: цілимось у 10 одночасних гравців.
const MAX_PLAYERS := 10

var is_server := false
var host := "127.0.0.1"
## Ім'я персонажа: `-- --персонаж Вовкодав`. Під ним він зберігається в
## базі (крок 3). Акаунти — крок 5; поки ім'я береться з рядка запуску.
var character := "Мандрівник"
## Адреса PostgREST: `-- --база http://127.0.0.1:3000`. Порожня — гра йде
## без збереження й каже про це вголос.
var db := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--server"):
		is_server = true
	var at := args.find("--host")
	if at != -1 and at + 1 < args.size():
		host = args[at + 1]
	at = args.find("--персонаж")
	if at != -1 and at + 1 < args.size():
		character = args[at + 1]
	at = args.find("--база")
	if at != -1 and at + 1 < args.size():
		db = args[at + 1]

	var peer := ENetMultiplayerPeer.new()
	var err := (peer.create_server(PORT, MAX_PLAYERS) if is_server
			else peer.create_client(host, PORT))
	if err != OK:
		push_error("мережу підняти не вдалось: %s" % error_string(err))
		return
	multiplayer.multiplayer_peer = peer
	print("[мережа] ", "сервер на порту %d" % PORT if is_server
			else "клієнт до %s:%d" % [host, PORT])
