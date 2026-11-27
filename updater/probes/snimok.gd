extends Node
## Знімок вікна апдейтера (для власника): адреса введена, config прийшов.
## Ганяти на процесорі (Mesa llvmpipe), щоб не брати GPU:
##     export __GLX_VENDOR_LIBRARY_NAME=mesa LIBGL_ALWAYS_SOFTWARE=1 \
##         GALLIUM_DRIVER=llvmpipe __EGL_VENDOR_LIBRARY_FILENAMES=\
##         /usr/share/glvnd/egl_vendor.d/50_mesa.json
##     godot --path updater --rendering-driver opengl3 \
##         res://scenes/snimok.tscn -- --адреса 127.0.0.1:24610 \
##         --тека ~/Games/MyWay --png build/updater-vikno.png
## `--тісно` — найгірший випадок для розкладки: ще й кнопки самооновлення
## й перенесення видно (у незібраному їх ховає) і довга помилка з шляхом.
## Налаштувань апдейтера не міняє (тека — з `--тека`, адресу вертає).

const UPDATER := preload("res://scenes/updater.tscn")
const PAGE := preload("res://scripts/updater.gd")


func _arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	var at := args.find(name)
	return args[at + 1] if at != -1 and at + 1 < args.size() else fallback


func _ready() -> void:
	_go.call_deferred()


func _go() -> void:
	var settings := ProjectSettings.globalize_path(PAGE.SETTINGS_FILE)
	var had := FileAccess.file_exists(settings)
	var kept := FileAccess.get_file_as_string(settings) if had else ""
	var page := UPDATER.instantiate()
	get_tree().root.add_child(page)
	page._address.text = _arg("--адреса", "127.0.0.1:24600")
	page.start_check()
	var started := Time.get_ticks_msec()
	while page.busy() and Time.get_ticks_msec() - started < 120000:
		await get_tree().process_frame
	if OS.get_cmdline_user_args().has("--тісно"):
		page._self_button.visible = true
		page._move_button.visible = true
		page._fail("новий апдейтер не завантажено: не вдалось поставити " \
				+ "апдейтер на місце /Users/ola/Applications/MyWay Updater" \
				+ ".app/Contents/MacOS/дуже-довгий-шлях-без-пробілів-" \
				+ "щоб-перевірити-перенесення-рядка: Permission denied — " \
				+ "лишився старий, він працює. Спробуй ще раз або завантаж " \
				+ "новий апдейтер з http://192.168.1.34/myway/ вручну.")
	for i in 10:
		await get_tree().process_frame
	var png := _arg("--png", "user://updater.png")
	var err := get_viewport().get_texture().get_image().save_png(png)
	print("знімок: %s (%s)" % [png, error_string(err)])
	if had:
		FileAccess.open(settings, FileAccess.WRITE).store_string(kept)
	else:
		DirAccess.remove_absolute(settings)
	get_tree().quit(0 if err == OK else 1)
