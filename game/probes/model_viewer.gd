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
## Під рухами — зовнішність, якщо модель її вміє (`SkinnedModel.customize`):
## зачіска й колір зачіски, очі (колір, форма, підводка), вуха, ніс, губи
## (форма й колір), колір шкіри. Угорі списку — «Ельфійки — усі версії»
## (`avatary/elfiiky.json`) і «Орчиха — усі версії» (`avatary/orky.json`): ✔ поточна, ✘ забраковані з причиною (підказка
## й рядок унизу).
## Модель збирає той самий `SkinnedModel`, що й гра (зріст і хутро — з
## `data/mobs.json`), тож видно те, що побачить гравець.
##
## Проба без рук (для перевірок): `-- --проба <частина назви> [--глина]
## [--рух <назва>] [--кут <градуси, 0 — спереду, 180 — ззаду>] [--відстань м]
## [--ціль x,y,z] [--без-волосся] [--скін <частина назви>]
## [--вигляд "зачіска=коса;колір_волосся=#9e1f1a;ніс=кирпатий"] [--капсули]
## --знімок <файл.png>` — обрати, показати, зняти, вийти.
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
## Усі зроблені ельфійки, разом із забракованими (слово замовника
## 12.10.2026: «покажи у виборі персонажів … усі моделі ельфійок які було
## зроблено і забраковано»). Старі версії — `avatary/_arkhiv/` (лише диск,
## дістаються з git: `git show <коміт>:<шлях>`).
const ELFIIKY := "res://models/own/avatary/elfiiky.json"
## Те саме для орчихи (12.10.2026, замовник: «не бачу в ./run.sh --моделі» —
## у розділі «Аватари» вона губилась під назвою файлу).
const VERSII := [["Орчиха — усі версії", "res://models/own/avatary/orky.json"],
		["Ельфійки — усі версії", ELFIIKY],
		["Людина-жінка — усі версії", "res://models/own/avatary/liudy.json"]]
## Вибір зовнішності (там само: «зачіски та колір зачіски, Очі, Вуха, Ніс,
## Губи, Колір скіна»). null — як у текстурі моделі.
const KOLORY_VOLOSSIA := [["як є", null], ["сивий", Color(0.92, 0.93, 0.96)],
		["сірий", Color(0.48, 0.48, 0.5)], ["солом'яний", Color(0.9, 0.78, 0.5)],
		["червоний", Color(0.62, 0.12, 0.1)], ["рудий", Color(0.8, 0.38, 0.16)],
		["каштановий", Color(0.36, 0.21, 0.12)], ["чорний", Color(0.1, 0.09, 0.09)],
		["білий", Color(1, 1, 1)]]
const KOLORY_OCHEI := [["як є", null], ["блакитні", Color(0.3, 0.55, 0.9)],
		["зелені", Color(0.3, 0.65, 0.35)], ["сірі", Color(0.55, 0.6, 0.65)],
		["бурштинові", Color(0.85, 0.55, 0.15)], ["фіалкові", Color(0.55, 0.35, 0.85)],
		["червоні", Color(0.8, 0.1, 0.1)], ["карі", Color(0.35, 0.2, 0.1)]]
const KOLORY_GUB := [["як є", null], ["рожеві", Color(0.85, 0.5, 0.55)],
		["ягідні", Color(0.55, 0.15, 0.3)], ["червоні", Color(0.75, 0.1, 0.12)],
		["бліді", Color(0.82, 0.66, 0.62)]]
const KOLORY_SHKIRY := [["як є", null], ["місячно-бліда", Color(0.88, 0.86, 0.85)],
		["світла", Color(0.86, 0.72, 0.64)], ["смаглява", Color(0.7, 0.52, 0.4)],
		["бронзова", Color(0.55, 0.38, 0.26)], ["оливкова", Color(0.68, 0.6, 0.45)],
		["сіро-блакитна", Color(0.55, 0.6, 0.7)], ["попелясто-сіра", Color(0.5, 0.5, 0.52)]]
const PIDVODKA := [["немає", 0.0], ["легка", 0.45], ["темна", 0.85]]
const RYSY_NAZVY := {"ніс": ["Ніс", "прямий"], "губи": ["Губи", "звичайні"],
		"очі": ["Форма очей", "звичайні"], "вуха": ["Вуха", "звичайні"]}

var _modeli: Array = []          ## {nazva, rozdil, path, height, fur, held, anim}
var _list: ItemList
var _poshuk: LineEdit
var _rukhy: VBoxContainer
var _skiny: VBoxContainer
var _vyhliad: VBoxContainer
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
	for vr: Array in VERSII:
		var el: Variant = JSON.parse_string(FileAccess.get_file_as_string(vr[1])) \
				if FileAccess.file_exists(vr[1]) else null
		if not el is Array:
			continue
		for e: Dictionary in el:
			var p := str(e.get("шлях", ""))
			if not ResourceLoader.exists(p):
				continue
			bachyly[p] = true
			_modeli.append({"nazva": "%s %s" % ["✔" if e.get("стан", "") == "поточна" else "✘",
					str(e.get("назва", p.get_file()))], "rozdil": vr[0],
					"path": p, "height": float(e.get("зріст", 1.82)), "fur": {}, "held": {},
					"pro": str(e.get("чому", ""))})
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
		# Зачіска окремим файлом (`_волосся-<стиль>.glb`, П6) — частина
		# моделі, не модель.
		if (f.ends_with(".glb") or f.ends_with(".gltf")) \
				and not f.contains("_волосся-"):
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
		if str(m.get("pro", "")) != "":
			_list.set_item_tooltip(k, str(m["pro"]))


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
	_vyhliad = VBoxContainer.new()
	pv.add_child(_vyhliad)

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
	_spysok_vyhliadu()
	_aim = Vector3(0, _vybrana["height"] * 0.5, 0)
	_dist = maxf(2.0, _vybrana["height"] * 2.2)
	_kamera()
	_info.text = "%s · %s · зріст %.2f м" % [_vybrana["nazva"],
			_vybrana["path"], _vybrana["height"]]
	if str(_vybrana.get("pro", "")) != "":
		_info.text += "\n" + str(_vybrana["pro"])


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


# ── зовнішність ─────────────────────────────────────────────────────────

func _spysok_vyhliadu() -> void:
	for c in _vyhliad.get_children():
		c.queue_free()
	var o := _skin_node.look_options()
	var styles: Array = o["зачіски"]
	var rysy: Dictionary = o["риси"]
	if styles.is_empty() and rysy.is_empty() and not o["маски"]:
		return
	_vyhliad.add_child(HSeparator.new())
	if not styles.is_empty():
		var it: Array = []
		for st: String in styles:
			it.append([st, st])
		it.append(["без волосся", "без"])
		_vybir("Зачіска", it, "зачіска")
		_vybir("Колір зачіски", KOLORY_VOLOSSIA, "колір_волосся")
	if o["маски"]:
		_vybir("Очі — колір", KOLORY_OCHEI, "колір_очей")
		_vybir("Очі — підводка", PIDVODKA, "підводка")
	for k: String in ["очі", "вуха", "ніс", "губи"]:
		if not rysy.has(k):
			continue
		var it: Array = [[RYSY_NAZVY[k][1], ""]]
		for v: String in rysy[k]:
			it.append([v.replace("-", " "), v])
		_vybir(RYSY_NAZVY[k][0], it, k)
		if k == "губи" and o["маски"]:
			_vybir("Губи — колір", KOLORY_GUB, "колір_губ")
	if o["маски"]:
		_vybir("Колір шкіри", KOLORY_SHKIRY, "колір_шкіри")


## Підпис і список; кольори — зі зразком. Вибір → `SkinnedModel.customize`.
func _vybir(nazva: String, items: Array, kliuch: String) -> void:
	var l := Label.new()
	l.text = nazva
	_vyhliad.add_child(l)
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(190, 0)
	ob.clip_text = true
	for i in items.size():
		var v: Variant = items[i][1]
		if v is Color:
			var img := Image.create(14, 14, false, Image.FORMAT_RGB8)
			img.fill(v)
			ob.add_icon_item(ImageTexture.create_from_image(img), items[i][0], i)
		else:
			ob.add_item(items[i][0], i)
	ob.item_selected.connect(func(i: int) -> void:
		_skin_node.customize({kliuch: items[i][1]}))
	_vyhliad.add_child(ob)


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
					and (f.begins_with(stem + "_") or dir.ends_with(stem + "/")) \
					and not ("маски" in f or "волосинки" in f):
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
			m.material_override = _skin_node.skin_material() \
					if m == _skin_node.body_mesh() else null
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
	var znaid := -1
	for k in _list.item_count:
		if _list.get_item_metadata(k) == null:
			continue
		var t := _list.get_item_text(k).strip_edges()
		if t == shukaty:          # точна назва — перед частковою
			znaid = k
			break
		if znaid < 0 and t.find(shukaty) >= 0:
			znaid = k
	if znaid >= 0:
		_list.select(znaid)
		_obrano(znaid)
	if _vybrana.is_empty():
		print("[переглядач] ‼ немає моделі «%s»" % shukaty)
		get_tree().quit(1)
		return
	if "--вигляд" in args:      # ключ=значення;… — як у меню (кольори — #rrggbb)
		var look := {}
		for pair: String in args[args.find("--вигляд") + 1].split(";"):
			var kv := pair.split("=")
			if kv.size() == 2:
				look[kv[0]] = Color(kv[1]) if kv[1].begins_with("#") else \
						(float(kv[1]) if kv[1].is_valid_float() else kv[1])
		_skin_node.customize(look)
	if "--глина" in args:
		_zastosuvaty(null, true)
	if "--скін" in args:         # частина назви картинки-скіна
		for p: String in _kartynky():
			if p.get_file().find(args[args.find("--скін") + 1]) >= 0:
				_zastosuvaty(load(p) as Texture2D, false)
				break
	if "--без-волосся" in args:
		for m: MeshInstance3D in _skin_node.find_children("Волосся*", "MeshInstance3D", true, false):
			m.visible = false
	if "--без-пружин" in args:
		for n in _skin_node.find_children("Волосся-пружини", "", true, false):
			n.free()
	if "--кут" in args:
		_yaw = deg_to_rad(float(args[args.find("--кут") + 1]))
		_kamera()
	if "--капсули" in args:     # заміри капсул волосся з тіла
		for k: String in _skin_node._hair_capsules:
			var m: Array = _skin_node._hair_capsules[k]
			print("[капсула] %s r %.3f h %.3f зсув %.3f" % [k, m[0], m[1], m[2]])
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
	if "--ціль" in args:            # x,y,z — куди дивиться камера
		var c := args[args.find("--ціль") + 1].split(",")
		_aim = Vector3(float(c[0]), float(c[1]), float(c[2]))
		_kamera()
	for i in kadriv:
		await get_tree().process_frame
	if "--знімок" in args:
		get_viewport().get_texture().get_image().save_png(args[args.find("--знімок") + 1])
		print("[знімок] ", args[args.find("--знімок") + 1])
	get_tree().quit()
