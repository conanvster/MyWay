extends Node
## Переглядач моделей (12.10.2026). Слово замовника: «напиши меню, щоб
## можна було запустити меню 1 командою, а в меню вибрати одну з наявних
## моделей для тесту і перевірки, що виглядає нормально … додай в меню
## можливість вибору скіна або без скіна моделі, схоже буде потреба в
## окремому механізмі тестування скінів».
##
##     ./run.sh --моделі
##
## Ліворуч — усі моделі гри розділами (аватари, власні монстри, процедурні
## гуманоїди) і пошук. Праворуч — рухи моделі (кнопкою) і скін:
##   * «Зі скіном» — як у грі;
##   * «Без скіна» — сіра глина, видно саму форму й шви сітки;
##   * будь-яка картинка-скін: файли поруч із моделлю з тим самим
##     початком імені (`<модель>_*.png|jpg`) і тека
##     `res://models/own/skins/<модель>/` — сюди класти скіни на пробу.
## Модель збирає той самий `SkinnedModel`, що й гра (зріст і хутро — з
## `data/mobs.json`), тож видно те, що побачить гравець.
##
## Проба без рук (для перевірок): `-- --проба <частина назви> [--глина]
## [--рух <назва>] [--кут <градуси, 0 — спереду, 180 — ззаду>] --знімок <файл.png>` — обрати, показати, зняти, вийти.
##
## Камера: ліва кнопка + тягнути — обертати; права/середня — зсув; колесо —
## ближче/далі; F — показати всю модель; пробіл — знімок у user://.

const AVATAR_ANIM := "res://models/player/animations/UAL1_Standard.glb"
const ROZDILY := [
	["Аватари", ["res://models/own/avatary/", "res://models/player/"], true],
	["Монстри (власні)", ["res://models/own/"], false],
	["Гуманоїди (процедурні)", ["res://models/own/humanoids/"], false],
]
const SKINS_DIR := "res://models/own/skins/"

var _modeli: Array = []          ## {nazva, rozdil, path, height, fur, held, anim}
var _list: ItemList
var _poshuk: LineEdit
var _rukhy: VBoxContainer
var _skiny: VBoxContainer
var _info: Label
var _world: Node3D
var _skin_node: SkinnedModel
var _cam: Camera3D
var _aim := Vector3(0, 0.9, 0)
var _yaw := 0.6
var _pitch := -0.15
var _dist := 4.0
var _vybrana: Dictionary = {}
var _gl: StandardMaterial3D


func _ready() -> void:
	get_window().size = Vector2i(1600, 900)
	_gl = StandardMaterial3D.new()
	_gl.albedo_color = Color(0.72, 0.72, 0.72)
	_gl.roughness = 0.85
	_zibraty_spysok()
	_scena()
	_ui()
	_pokazaty_spysok("")
	var args := OS.get_cmdline_user_args()
	if "--проба" in args:
		_proba(args)


# ── список моделей ──────────────────────────────────────────────────────

func _zibraty_spysok() -> void:
	var mobs: Dictionary = {}
	var data: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/mobs.json"))
	if data is Dictionary:
		for v: Variant in data.values():
			if v is Dictionary and v.has("вигляд"):
				var look: Dictionary = v["вигляд"]
				var p := str(look.get("модель", ""))
				if p != "" and not mobs.has(p):
					mobs[p] = {"nazva": str(v.get("назва", "")), "look": look}
	var bachyly := {}
	for r: Array in ROZDILY:
		for dir: String in r[1]:
			for p: String in _faily(dir, r[2]):
				if bachyly.has(p):
					continue
				bachyly[p] = true
				var m: Dictionary = mobs.get(p, {})
				var look: Dictionary = m.get("look", {})
				var nazva := p.get_file().get_basename()
				var h := float(look.get("зріст", 1.82 if r[0] == "Аватари" else 1.0))
				if r[0] == "Аватари" and nazva.begins_with("орк"):
					h = 1.9
				_modeli.append({"nazva": nazva, "rozdil": r[0], "path": p,
						"height": h, "fur": look.get("хутро", {}),
						"held": look.get("в_руці", {})})


## Моделі в теці; `vglyb` — і в підтеках. `.import`, текстури й речі — ні.
func _faily(dir: String, vglyb: bool) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".glb") or f.ends_with(".gltf"):
			out.append(dir + f)
	if vglyb:
		for sub in d.get_directories():
			if sub == "animations":     # бібліотеки рухів — не моделі
				continue
			out.append_array(_faily(dir + sub + "/", true))
	out.sort()
	return out


func _pokazaty_spysok(filtr: String) -> void:
	_list.clear()
	var rozdil := ""
	for i in _modeli.size():
		var m: Dictionary = _modeli[i]
		if filtr != "" and m["nazva"].to_lower().find(filtr.to_lower()) < 0:
			continue
		if m["rozdil"] != rozdil:
			rozdil = m["rozdil"]
			var z := _list.add_item("── " + rozdil + " ──")
			_list.set_item_selectable(z, false)
			_list.set_item_custom_fg_color(z, Color(0.95, 0.8, 0.45))
		var k := _list.add_item("   " + m["nazva"])
		_list.set_item_metadata(k, i)


# ── сцена й інтерфейс ───────────────────────────────────────────────────

func _scena() -> void:
	_world = Node3D.new()
	add_child(_world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	_world.add_child(sun)
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 12)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("#4a5c3a")
	ground.material_override = gm
	_world.add_child(ground)
	_cam = Camera3D.new()
	_world.add_child(_cam)
	_kamera()


func _ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	# Якорі, не пікселі: інтерфейс гри збільшено ×1,5 (stretch/scale), і
	# панель, поставлена за пікселями вікна, виїжджала за край.
	var liva := PanelContainer.new()
	liva.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	liva.offset_left = 6
	liva.offset_top = 6
	liva.offset_bottom = -6
	liva.offset_right = 250
	layer.add_child(liva)
	var lv := VBoxContainer.new()
	liva.add_child(lv)
	var t := Label.new()
	t.text = "Моделі"
	lv.add_child(t)
	_poshuk = LineEdit.new()
	_poshuk.placeholder_text = "пошук…"
	_poshuk.text_changed.connect(_pokazaty_spysok)
	lv.add_child(_poshuk)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_obrano)
	lv.add_child(_list)

	var prava := PanelContainer.new()
	prava.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	prava.offset_left = -210
	prava.offset_top = 6
	prava.offset_bottom = -6
	prava.offset_right = -6
	layer.add_child(prava)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	prava.add_child(scroll)
	var pv := VBoxContainer.new()
	scroll.add_child(pv)
	var s := Label.new()
	s.text = "Скін"
	pv.add_child(s)
	_skiny = VBoxContainer.new()
	pv.add_child(_skiny)
	pv.add_child(HSeparator.new())
	var r := Label.new()
	r.text = "Рухи"
	pv.add_child(r)
	_rukhy = VBoxContainer.new()
	pv.add_child(_rukhy)

	_info = Label.new()
	_info.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_info.offset_left = 258
	_info.offset_right = -216
	_info.offset_top = -48
	_info.offset_bottom = -6
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.text = "Оберіть модель ліворуч · ЛКМ — обертати · ПКМ — зсув · колесо — ближче · F — уся модель · пробіл — знімок"
	layer.add_child(_info)


# ── модель ──────────────────────────────────────────────────────────────

func _obrano(at: int) -> void:
	var i: Variant = _list.get_item_metadata(at)
	if i == null:
		return
	_vybrana = _modeli[int(i)]
	if _skin_node != null:
		_skin_node.queue_free()
	_skin_node = SkinnedModel.new()
	_skin_node.path = _vybrana["path"]
	_skin_node.height = _vybrana["height"]
	_skin_node.fur = _vybrana["fur"]
	_skin_node.held = _vybrana["held"]
	if not _maie_ruhy(_vybrana["path"]):
		_skin_node.anim_path = AVATAR_ANIM
	_world.add_child(_skin_node)
	_skin_node.build()
	_skin_node.rotation_degrees.y = 180.0
	_spysok_ruhiv()
	_spysok_skiniv()
	_aim = Vector3(0, _vybrana["height"] * 0.5, 0)
	_dist = maxf(2.0, _vybrana["height"] * 2.2)
	_kamera()
	_info.text = "%s · %s · зріст %.2f м" % [_vybrana["nazva"],
			_vybrana["path"], _vybrana["height"]]


func _maie_ruhy(p: String) -> bool:
	var s: Node = (load(p) as PackedScene).instantiate()
	var ap: AnimationPlayer = s.find_child("AnimationPlayer", true, false)
	var ok := ap != null and ap.get_animation_list().size() > 0
	s.free()
	return ok


func _player() -> AnimationPlayer:
	return _skin_node.find_child("AnimationPlayer", true, false) \
			if _skin_node != null else null


func _spysok_ruhiv() -> void:
	for c in _rukhy.get_children():
		c.queue_free()
	var ap := _player()
	if ap == null:
		var l := Label.new()
		l.text = "рухів немає"
		_rukhy.add_child(l)
		return
	var names := Array(ap.get_animation_list())
	names.sort()
	for n: String in names:
		if n == "RESET":
			continue
		var b := Button.new()
		b.text = n
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func() -> void:
			var a := ap.get_animation(n)
			a.loop_mode = Animation.LOOP_LINEAR
			ap.play(n))
		_rukhy.add_child(b)


# ── скіни ───────────────────────────────────────────────────────────────

func _spysok_skiniv() -> void:
	for c in _skiny.get_children():
		c.queue_free()
	_knopka_skin("Зі скіном (як у грі)", func() -> void: _zastosuvaty(null, false))
	_knopka_skin("Без скіна (глина)", func() -> void: _zastosuvaty(null, true))
	var stem: String = _vybrana["path"].get_file().get_basename()
	for p: String in _kartynky():
		var nazva := p.get_file().trim_prefix(stem + "_")
		if p.begins_with(SKINS_DIR):
			nazva = "скін: " + nazva
		_knopka_skin(nazva, func() -> void:
			_zastosuvaty(load(p) as Texture2D, false))


func _knopka_skin(text: String, dia: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.custom_minimum_size = Vector2(190, 0)
	b.pressed.connect(dia)
	_skiny.add_child(b)


## Картинки-скіни: поруч із моделлю з тим самим початком імені і тека
## `skins/<модель>/`.
func _kartynky() -> Array:
	var out: Array = []
	var p: String = _vybrana["path"]
	var dir := p.get_base_dir() + "/"
	var stem := p.get_file().get_basename()
	var d := DirAccess.open(dir)
	if d != null:
		for f in d.get_files():
			if (f.ends_with(".png") or f.ends_with(".jpg")) \
					and (f.begins_with(stem + "_") or dir.ends_with(stem + "/")):
				out.append(dir + f)
	var sd := DirAccess.open(SKINS_DIR + stem + "/")
	if sd != null:
		for f in sd.get_files():
			if f.ends_with(".png") or f.ends_with(".jpg"):
				out.append(SKINS_DIR + stem + "/" + f)
	out.sort()
	return out


## `tex` — нова картинка кольору на всі поверхні; `glyna` — сірий матеріал;
## обидва порожні — повернути матеріали моделі.
func _zastosuvaty(tex: Texture2D, glyna: bool) -> void:
	if _skin_node == null:
		return
	for m: MeshInstance3D in _skin_node.find_children("*", "MeshInstance3D", true, false):
		if m.name.begins_with("Одяг-") and not m.visible:
			continue
		if glyna:
			m.material_override = _gl
		elif tex == null:
			m.material_override = null
		else:
			var src: Material = m.get_active_material(0)
			var mat: StandardMaterial3D = (src.duplicate() if src is StandardMaterial3D
					else StandardMaterial3D.new())
			mat.albedo_texture = tex
			mat.albedo_color = Color.WHITE
			m.material_override = mat


# ── камера ──────────────────────────────────────────────────────────────

func _kamera() -> void:
	var off := Vector3(sin(_yaw) * cos(_pitch), -sin(_pitch), cos(_yaw) * cos(_pitch)) * _dist
	_cam.position = _aim + off
	_cam.look_at(_aim, Vector3.UP)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = maxf(0.3, _dist * 0.9)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = minf(30.0, _dist * 1.1)
		_kamera()
	elif e is InputEventMouseMotion:
		if e.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_yaw -= e.relative.x * 0.01
			_pitch = clampf(_pitch - e.relative.y * 0.01, -1.4, 1.4)
			_kamera()
		elif e.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE):
			var right := _cam.global_transform.basis.x
			var up := _cam.global_transform.basis.y
			_aim += (-right * e.relative.x + up * e.relative.y) * _dist * 0.002
			_kamera()
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_F and not _vybrana.is_empty():
			_aim = Vector3(0, _vybrana["height"] * 0.5, 0)
			_dist = maxf(2.0, _vybrana["height"] * 2.2)
			_kamera()
		elif e.keycode == KEY_SPACE:
			Shot.take(_world)


func _proba(args: PackedStringArray) -> void:
	var shukaty := args[args.find("--проба") + 1]
	for k in _list.item_count:
		if _list.get_item_metadata(k) != null \
				and _list.get_item_text(k).find(shukaty) >= 0:
			_list.select(k)
			_obrano(k)
			break
	if _vybrana.is_empty():
		print("[переглядач] ‼ немає моделі «%s»" % shukaty)
		get_tree().quit(1)
		return
	if "--глина" in args:
		_zastosuvaty(null, true)
	if "--кут" in args:
		_yaw = deg_to_rad(float(args[args.find("--кут") + 1]))
		_kamera()
	var ap := _player()
	if "--рух" in args and ap != null:
		ap.play(args[args.find("--рух") + 1])
	print("[переглядач] модель %s, рухів %d, скінів %d" % [_vybrana["nazva"],
			0 if ap == null else ap.get_animation_list().size(), _kartynky().size()])
	var kadriv := 40
	if "--кадрів" in args:
		kadriv = int(args[args.find("--кадрів") + 1])
	if "--відстань" in args:
		_dist = float(args[args.find("--відстань") + 1])
		_kamera()
	for i in kadriv:
		await get_tree().process_frame
	if "--знімок" in args:
		get_viewport().get_texture().get_image().save_png(args[args.find("--знімок") + 1])
		print("[знімок] ", args[args.find("--знімок") + 1])
	get_tree().quit()
