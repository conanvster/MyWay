extends SceneTree
## Проба: куди самооновлення й «Перенести апдейтер…» ставлять апдейтер
## (`updater.gd` → `self_place`, `translocated`, `self_stage`). Чисті
## функції, тож Mac і Windows імітуємо шляхами:
##     godot --headless --path updater -s res://probes/self_place.gd

const UPDATER := preload("res://scripts/updater.gd")

var _failed := 0


func _init() -> void:
	var mac_env := {"HOME": "/Users/ola"}
	var moved := "/Users/ola/Applications/MyWay Updater.app"
	var trans := "/private/var/folders/x1/abc/T/AppTranslocation/" \
			+ "1F2E-33/d/MyWay Updater.app"
	_same(UPDATER.translocated(trans), true, "транслокація впізнана")
	_same(UPDATER.translocated("/Users/ola/Downloads/MyWay Updater.app"),
			false, "«Завантаження» без транслокації — не вона")
	# Mac, транслокований: навіть якщо «можна писати» — у ~/Applications.
	_same(UPDATER.self_place(trans, "macOS", true, mac_env), moved,
			"Mac: транслокований → ~/Applications")
	_same(UPDATER.self_place(trans, "macOS", false, mac_env), moved,
			"Mac: транслокований, тека лише для читання → ~/Applications")
	_same(UPDATER.self_place("/Users/ola/Downloads/MyWay Updater.app",
			"macOS", true, mac_env), "/Users/ola/Downloads/MyWay Updater.app",
			"Mac: звичайна тека з правом запису → на місці")
	_same(UPDATER.self_place("/Applications/MyWay Updater.app", "macOS",
			false, mac_env), moved,
			"Mac: /Applications без прав адміна → ~/Applications")
	_same(UPDATER.self_place(moved, "macOS", true, mac_env), moved,
			"Mac: уже в ~/Applications → на місці")
	_same(UPDATER.self_place(trans, "macOS", false, {}), "",
			"Mac: без HOME — нема куди")
	_same(UPDATER.self_place(trans, "macOS", false,
			{"HOME": "/Users/ola/"}), moved, "Mac: HOME зі скісною в кінці")
	_same(UPDATER.self_stage(moved), "/Users/ola/Applications/"
			+ UPDATER.SELF_STAGE, "Mac: тимчасова тека поруч із місцем")
	# Linux.
	var exe := "/home/ola/Завантаження/MyWay-Updater.x86_64"
	_same(UPDATER.self_place(exe, "Linux", true, {"HOME": "/home/ola"}), exe,
			"Linux: можна писати → на місці")
	_same(UPDATER.self_place(exe, "Linux", false, {"HOME": "/home/ola"}),
			"/home/ola/.local/share/MyWay-Updater/bin/MyWay-Updater.x86_64",
			"Linux: не можна писати → ~/.local/share/MyWay-Updater/bin")
	_same(UPDATER.self_place(exe, "Linux", false, {"HOME": "/home/ola",
			"XDG_DATA_HOME": "/srv/xdg/"}),
			"/srv/xdg/MyWay-Updater/bin/MyWay-Updater.x86_64",
			"Linux: XDG_DATA_HOME має перевагу")
	# Windows.
	var win := "C:/Users/ola/Downloads/MyWay-Updater.exe"
	_same(UPDATER.self_place(win, "Windows", true,
			{"LOCALAPPDATA": "C:\\Users\\ola\\AppData\\Local"}), win,
			"Windows: можна писати → на місці")
	_same(UPDATER.self_place(win, "Windows", false,
			{"LOCALAPPDATA": "C:\\Users\\ola\\AppData\\Local"}),
			"C:/Users/ola/AppData/Local/Programs/MyWay Updater/"
			+ "MyWay-Updater.exe",
			"Windows: не можна писати → %LOCALAPPDATA%\\Programs")
	_same(UPDATER.self_place(win, "Windows", false, {}), "",
			"Windows: без LOCALAPPDATA — нема куди")
	print("✓ усе збіглось" if _failed == 0 else "✗ не збіглось: %d" % _failed)
	quit(0 if _failed == 0 else 1)


func _same(got: Variant, want: Variant, what: String) -> void:
	if got == want:
		print("  ✓ %s" % what)
	else:
		_failed += 1
		print("  ‼ %s: «%s», а треба «%s»" % [what, got, want])
