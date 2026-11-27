extends Node
## Підняття мережі. Автозавантаження, ім'я `Net`.
##
## Роль обирається аргументом після `--`:
##     godot --headless -- --server        сервер
##     godot -- --host 192.168.0.10        клієнт до вказаного вузла
##     godot -- --host 192.168.0.10:24600  те саме з портом
##     godot -- --порт 24600               інший порт (і серверу, і клієнту)
##     godot -- --version                  надрукувати версію збірки й вийти
##
## Усе — ПІСЛЯ `--`: без нього `--version` перехоплює сам рушій і друкує
## СВОЮ версію («4.7.2.stable…»), а `--host` гра не побачить узагалі.
## Без аргументів — клієнт до 127.0.0.1.
##
## Адресу можна ввести й на стартовій сторінці (клієнт для Mac, 26.11.2026):
## там вона розбирається `parse_address` і запам'ятовується в
## `ADDRESS_FILE`, щоб наступного разу не вводити.

const PORT := 24565
## П-04: цілимось у 10 одночасних гравців.
const MAX_PLAYERS := 10
## Остання адреса сервера, введена на стартовій сторінці.
const ADDRESS_FILE := "user://адреса-сервера.cfg"
## Версія збірки: кладе `tools/zibraty_macos.sh` перед експортом (у git
## файла немає). Без нього — гра з репозиторію, версію питаємо в git.
const VERSION_FILE := "res://versiia.json"

var is_server := false
var host := "127.0.0.1"
## Порт сервера. Типово `PORT`; `--порт` — щоб пробний сервер не займав
## порт, на якому, можливо, саме грають.
var port := PORT
## Чому востаннє не вдалось з'єднатись або обірвалось з'єднання. Світ
## кладе сюди причину й вертає на стартову сторінку, а та її показує:
## без цього людина бачила б порожній світ і нічого більше (P3).
var why_left := ""
## Адреса прийшла з рядка запуску (`--host`). Так клієнт запускатиме
## апдейтер: сторінка тоді підключається сама, без натискання.
var host_given := ""
## Ім'я персонажа: `-- --персонаж Вовкодав`. Під ним він зберігається в
## базі (крок 3). Акаунти — крок 5; поки ім'я береться з рядка запуску.
var character := "Мандрівник"
## Адреса PostgREST: `-- --база http://127.0.0.1:3000`. Порожня — гра йде
## без збереження й каже про це вголос.
var db := ""
## Акаунт і пароль із рядка запуску: `-- --акаунт конан --пароль таємниця`.
## Порожні — клієнт покаже екран входу й чекатиме на людину.
var account := ""
var password := ""


## Чи вже з'єднані. Клієнт з'єднується не одразу, а коли заходить у світ.
var joined := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--version") or args.has("--версія"):
		print(build_version())
		get_tree().quit()
		return
	# Діагностика зібраного клієнта: чи читаються картинки, які гра бере
	# байтами (карта, земля, фото дерев, кора) — див. RawImage.
	if args.has("--перевірити-картинки"):
		var bad := 0
		var paths: Array[String] = ["res://data/svit2/karta/r1c1.jpg",
				"res://models/ground/Grass004_Color.jpg",
				"res://models/nature/bark/Bark014_Color.jpg"]
		for name in DirAccess.get_files_at("res://models/nature/photo"):
			var plain := name.trim_suffix(".import").trim_suffix(".remap")
			if plain.get_extension() in ["png", "webp"]:
				paths.append("res://models/nature/photo/" + plain)
				break
		for path in paths:
			var picture := RawImage.read(path)
			print("[картинки] %s %s" % ["✓" if picture != null else "✗", path
					+ (" %dx%d" % [picture.get_width(), picture.get_height()]
					if picture != null else "")])
			bad += 0 if picture != null else 1
		print("[картинки] %s" % ("усе читається" if bad == 0
				else "не читається: %d" % bad))
		get_tree().quit(1 if bad else 0)
		return
	if args.has("--server"):
		is_server = true
	address_from_args()
	var at := args.find("--персонаж")
	if at != -1 and at + 1 < args.size():
		character = args[at + 1]
	at = args.find("--база")
	if at != -1 and at + 1 < args.size():
		db = args[at + 1]
	at = args.find("--акаунт")
	if at != -1 and at + 1 < args.size():
		account = args[at + 1]
	at = args.find("--пароль")
	if at != -1 and at + 1 < args.size():
		password = args[at + 1]

	# Сервер слухає одразу. КЛІЄНТ — ні: доки людина на стартовій
	# сторінці, світу в нього ще немає, і надіслані туди пакети шукають
	# вузол «Main», якого не існує. У журналі це виглядало так:
	# «Node not found: Main» десятками рядків. Тому клієнт з'єднується
	# аж тоді, коли зайшов у світ, — через `join()`.
	if is_server:
		join()


## Адреса з рядка запуску (`--host`, `--порт`) або типова. Окремо — щоб
## стартова сторінка могла повернути її для «Зайти в гру» після того, як
## людина пробувала інший сервер.
func address_from_args() -> void:
	var args := OS.get_cmdline_user_args()
	host = "127.0.0.1"
	port = PORT
	host_given = ""
	var at := args.find("--host")
	if at != -1 and at + 1 < args.size():
		var asked := parse_address(args[at + 1])
		if asked.has("why"):
			print("[мережа] ‼ --host %s: %s" % [args[at + 1], asked["why"]])
		else:
			host = str(asked["host"])
			port = int(asked["port"])
			host_given = args[at + 1]
	at = args.find("--порт")
	if at != -1 and at + 1 < args.size():
		var asked := args[at + 1]
		if asked.is_valid_int() and int(asked) >= 1 and int(asked) <= 65535:
			port = int(asked)
		else:
			print("[мережа] ‼ порт «%s» не число 1…65535 — беру %d"
					% [asked, PORT])


## «коміт · дата» збірки. Із файла, що його кладе скрипт збірки; у грі з
## репозиторію — з git; немає й git — так і кажемо, а не мовчимо.
static func build_version() -> String:
	if FileAccess.file_exists(VERSION_FILE):
		var parsed: Variant = JSON.parse_string(
				FileAccess.get_file_as_string(VERSION_FILE))
		if parsed is Dictionary:
			return "%s · %s" % [parsed.get("коміт", "?"),
					parsed.get("дата", "?")]
		return "версія: %s пошкоджено" % VERSION_FILE
	if OS.has_feature("editor"):
		var out: Array = []
		var code := OS.execute("git", ["-C", ProjectSettings.globalize_path(
				"res://"), "log", "-1", "--format=%h · %cs"], out)
		if code == 0 and not out.is_empty():
			return "%s (з репозиторію)" % str(out[0]).strip_edges()
	return "версія невідома"


## Розібрати введене людиною: «192.168.1.48», «192.168.1.48:24600»,
## «myserver.local». Вертає {"host", "port"} або {"why"} — що не так.
## Порожній порт означає типовий.
static func parse_address(text: String) -> Dictionary:
	var line := text.strip_edges()
	if line == "":
		return {"why": "введи IP сервера, наприклад 192.168.1.48"}
	if " " in line:
		return {"why": "в адресі не має бути пробілів: «%s»" % line}
	var where := line
	var number := PORT
	if line.count(":") == 1:
		where = line.get_slice(":", 0)
		var tail := line.get_slice(":", 1)
		if not tail.is_valid_int() or int(tail) < 1 or int(tail) > 65535:
			return {"why": "порт «%s» — має бути число від 1 до 65535" % tail}
		number = int(tail)
	elif line.count(":") > 1:
		return {"why": "IPv6 не підтримується — введи IPv4, як 192.168.1.48"}
	if where == "":
		return {"why": "перед двокрапкою має бути IP сервера"}
	return {"host": where, "port": number}


## Остання введена адреса — порожньо, якщо ще не вводили або файл не
## прочитався (тоді й кажемо чому, а не мовчимо).
static func last_address() -> String:
	if not FileAccess.file_exists(ADDRESS_FILE):
		return ""
	var file := ConfigFile.new()
	var err := file.load(ADDRESS_FILE)
	if err != OK:
		print("[мережа] ‼ не прочитав %s: %s" % [ADDRESS_FILE,
				error_string(err)])
		return ""
	return str(file.get_value("сервер", "адреса", ""))


static func remember_address(text: String) -> void:
	var file := ConfigFile.new()
	file.set_value("сервер", "адреса", text.strip_edges())
	var err := file.save(ADDRESS_FILE)
	if err != OK:
		print("[мережа] ‼ не запам'ятав адресу в %s: %s" % [ADDRESS_FILE,
				error_string(err)])


## Чи є живе з'єднання. Питати номер без нього — помилка щокадру.
##
## `OfflineMultiplayerPeer` доводиться відсіювати окремо (заміряно
## 05.09.2026): Godot ставить його сам у кожному процесі, де мережі не
## піднімали, і він чесно відповідає `CONNECTION_CONNECTED` — тобто без
## цієї перевірки функція казала «з'єднані» там, де жодного пакета не
## було й бути не могло. Охорона з неї виходила уявна: `hud.gd` за нею
## щокадру ліз у `_world.creatures` і в пробі вітрини валився помилкою
## на кожному кадрі.
func connected() -> bool:
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return false
	return peer.get_connection_status() \
			== MultiplayerPeer.CONNECTION_CONNECTED


## Підняти з'єднання. Для сервера це слухати порт, для клієнта — стукати.
func join() -> bool:
	if joined:
		return true
	var peer := ENetMultiplayerPeer.new()
	# Сервер слухає UDP на всіх адресах машини (ENet типово бере «*»),
	# тож до нього стукають і з локальної мережі, якщо пускає брандмауер.
	var err := (peer.create_server(port, MAX_PLAYERS) if is_server
			else peer.create_client(host, port))
	if err != OK:
		why_left = ("порт %d не взяти: %s" % [port, error_string(err)]
				if is_server else "до %s:%d не з'єднатись: %s" % [host, port,
				"адресу не знайдено" if err == ERR_CANT_RESOLVE
				else error_string(err)])
		push_error("мережу підняти не вдалось: %s" % why_left)
		print("[мережа] ‼ не вдалось: %s" % why_left)
		return false
	multiplayer.multiplayer_peer = peer
	joined = true
	print("[мережа] ", "сервер на порту %d (UDP)" % port if is_server
			else "клієнт до %s:%d" % [host, port])
	return true
