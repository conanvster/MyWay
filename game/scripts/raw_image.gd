class_name RawImage
## Картинка з `res://` як `Image` — і в редакторі, і в ЗІБРАНІЙ грі.
##
## Плитки карти, шари землі, фото дерев і кору гра читає байтами (щоб самій
## різати, міряти силует, складати Texture2DArray). Але ці файли мають
## `.import`, а експорт кладе в .pck лише ІМПОРТОВАНУ текстуру, без сирого
## .jpg/.png. У зібраному клієнті читання байтів давало порожнечу: на Mac
## карта була синьою плямою (знімок замовника 27.11.2026: «на MacOS в грі не
## видно карту»), земля — сірою, без фото-карток дерев. Тому: є сирий файл —
## з нього; немає — з імпортованої текстури (розтиснутої, без mip-рівнів, бо
## далі кожен генерує свої).


static func read(path: String) -> Image:
	var raw := FileAccess.get_file_as_bytes(path)
	if not raw.is_empty():
		var picture := Image.new()
		var err: int
		match path.get_extension().to_lower():
			"png":
				err = picture.load_png_from_buffer(raw)
			"webp":
				err = picture.load_webp_from_buffer(raw)
			_:
				err = picture.load_jpg_from_buffer(raw)
		if err == OK:
			return picture
		print("[картинка] ‼ %s не прочитався: %s" % [path, error_string(err)])
		return null
	if not ResourceLoader.exists(path):
		return null
	var texture := load(path) as Texture2D
	if texture == null:
		print("[картинка] ‼ %s є, але не завантажився як текстура" % path)
		return null
	var picture := texture.get_image()
	if picture == null:
		print("[картинка] ‼ з текстури %s не дістати зображення" % path)
		return null
	if picture.is_compressed():
		picture.decompress()
	if picture.has_mipmaps():
		picture.clear_mipmaps()
	return picture
