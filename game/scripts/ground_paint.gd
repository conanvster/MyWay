class_name GroundPaint
extends RefCounted
## Фотографічна земля світу версії 2: шари текстур і їхні ваги.
##
## Слово замовника 11.09.2026: «пошукай рішення схожі на Lineage 2 для
## красивого дизайну поверхонь трави, дерев, каміння… на більш
## реалістичному ґрунті».
##
## Lineage 2 стоїть на Unreal Engine 2, і земля там — ШАРИ: кілька
## текстур (трава, ґрунт, камінь, пісок), у кожної своя карта ваг по
## рельєфу. Тут те саме. Дев'ять фото ambientCG (CC0, `models/ground/`)
## лягають масивом у `terrain.gdshader`, а вага кожного шару лежить у
## вершинах землі: вершина кожні 8 м, трикутник між ними змішує, а
## висота самих текстур робить межу рваною, як у природі.
##
## Було (до 11.09.2026): крап шумом кольором із палітри карти, 46
## окремих поверхонь на кожну зону й кожну пару сусідніх зон. Перехід
## між зонами — дві смуги середнього кольору. Тепер поверхня ОДНА, і
## перехід — це просто ваги, що плавно перетікають.
##
## Звідки вага шару в точці — три речі, як і в справжньої землі:
## - **зона карти** дає основу: рівнина — лука, мертвий схід — потріскана
##   земля, північ — сніг;
## - **схил**: де круто, там скеля, а під нею щебінь — у будь-якій зоні;
## - **що поруч**: під гаєм лісова підстилка (той самий шум, яким
##   садяться дерева, — підстилка лежить рівно під лісом), біля моря
##   пісок, біля річки щебінь і пісок, у дворі села втоптаний ґрунт.

const WHERE := "res://models/ground/%s_%s.jpg"
## Шар: файл ambientCG · метрів на один повтор · шорсткість · множник
## кольору. Множники дібрані знімками 11.09.2026, і причин дві:
## - фото знято яскравим, а справжня земля темна (альбедо ґрунту
##   0,2-0,35): мертвий схід із Ground027 як є виходив майже білим,
##   гори — вицвілими;
## - земля під травою в тіні травинок: шар луки темніший за самі
##   травинки, інакше трава читається волосинками на світлому килимі.
## Окремо: підстилка Ground048 під нашим сонцем рожевіла, щебінь
## Ground022 здалеку білів, мох Ground037 робив гори жовтими.
const LAYERS := [
	["Grass004", 3.2, 0.95, Color(0.62, 0.68, 0.58)],   # 0 лука
	["Ground003", 3.0, 0.95, Color(0.80, 0.80, 0.78)],  # 1 трава з ґрунтом
	["Ground037", 3.6, 0.95, Color(0.55, 0.66, 0.60)],  # 2 мох, гірська лука
	["Ground048", 2.6, 0.98, Color(0.64, 0.76, 0.72)],  # 3 підстилка, згарище
	["Ground022", 3.0, 0.90, Color(0.62, 0.62, 0.62)],  # 4 щебінь
	["Rock030", 7.0, 0.85, Color(0.90, 0.90, 0.90)],    # 5 скеля
	["Snow006", 5.0, 0.60, Color(0.85, 0.86, 0.88)],    # 6 сніг
	["Ground054", 4.0, 0.95, Color(0.80, 0.80, 0.80)],  # 7 пісок
	["Ground027", 4.5, 0.95, Color(0.62, 0.62, 0.62)],  # 8 потріскана земля
	["Ground039", 3.0, 0.92, Color(0.78, 0.78, 0.76)],  # 9 стежка
]
const MEADOW := 0
const SOIL := 1
const MOSS := 2
const LITTER := 3
const SCREE := 4
const ROCK := 5
const SNOW := 6
const SAND := 7
const CRACKED := 8
const PATH := 9
## Шарів із вагами у вершинах. Стежка (9) — окремо, з поля відстаней.
const COUNT := 9
## Скільки байтів ваг на вершину: три групи по чотири шари (COLOR,
## CUSTOM0, CUSTOM1), останні три слоти поки порожні.
const PER_VERTEX := 12

## Роди зон — за назвою з даних, не за кодом: код — це порядок у
## переліку генератора, і він може зсунутись, а назва ні.
const KINDS := {
	"море": 0, "крижана північ": 1, "гори заходу": 2,
	"центральна рівнина": 3, "вулканічна смуга": 4, "мертвий схід": 5,
	"південна тераса": 6,
}
## Наскільки суха трава в кожному роді зони (для відтінку травинок):
## рівнина соковита, мертвий схід — солома.
const DRYNESS := [0.3, 0.4, 0.25, 0.08, 0.75, 0.85, 0.6]

## Ваги шарів у кожній вершині сітки, `PER_VERTEX` байтів поспіль.
var weights := PackedByteArray()
## Що росте в кожній вершині, чотири байти: скільки трави · наскільки
## вона суха · скільки квітів · (порожньо). Читає `meadow.gd`.
var cover := PackedByteArray()
var points := 0
var start := Vector2.ZERO
var step := 8.0

var _heights := PackedFloat32Array()
var _normals := PackedVector3Array()


## Лише форма, без ваг — для сервера: йому земля потрібна як число.
func shape_only(heights: PackedFloat32Array, grid: int, from: Vector2,
		spacing: float) -> void:
	_heights = heights
	points = grid
	start = from
	step = spacing
	_normals = _normals_of(heights, grid, spacing)


## Порахувати ваги для всієї землі.
##
## `land` — краєвид: з нього беремо зону в точці (з тією самою рваною
## межею, що й у рослин), рівень моря, правила гаїв, міста й річки.
func paint(land: Landscape, heights: PackedFloat32Array, grid: int,
		from: Vector2, spacing: float) -> void:
	shape_only(heights, grid, from, spacing)
	var sea: float = land.sea_level()

	# Роди зон за кодом і шум гаю кожної зони — той самий, яким
	# `_greenery()` садить дерева: підстилка має лягти рівно під ліс.
	var kind_of := PackedInt32Array()
	var groves: Dictionary = {}
	var grove_edge: Dictionary = {}
	for zone: Dictionary in land.data.get("зони", []):
		var code := int(zone.get("код", 0))
		while kind_of.size() <= code:
			kind_of.append(3)
		kind_of[code] = int(KINDS.get(str(zone.get("назва", "")), 3))
	for rule: Dictionary in land.data.get("рослинність", []):
		var code := int(rule.get("зона", -1))
		var noise := FastNoiseLite.new()
		noise.seed = Landscape.SEED + code * 31
		noise.frequency = float(rule.get("клуб", 0.012))
		groves[code] = noise
		grove_edge[code] = float(rule.get("поріг", 0.0))

	# Великі плями (~55 м) і дрібні (~14 м): де на луці проступає ґрунт,
	# де на горі щебінь, де на вершині латка снігу.
	var patch := FastNoiseLite.new()
	patch.seed = Landscape.SEED + 501
	patch.frequency = 0.018
	var fine := FastNoiseLite.new()
	fine.seed = Landscape.SEED + 502
	fine.frequency = 0.07

	var yard := _yard_mask(land)
	var bank := _bank_mask(land)

	# Зона кожної вершини — один раз, далі сусіди читаються звідси.
	var total := grid * grid
	var codes := PackedByteArray()
	codes.resize(total)
	for iz in grid:
		for ix in grid:
			codes[iz * grid + ix] = land._zone_at(from.x + ix * spacing,
					from.y + iz * spacing)

	weights.resize(total * PER_VERTEX)
	weights.fill(0)
	cover.resize(total * 4)
	cover.fill(0)
	var w := PackedFloat32Array()
	w.resize(COUNT)
	var one := PackedFloat32Array()
	one.resize(COUNT)
	for iz in grid:
		for ix in grid:
			var i := iz * grid + ix
			var x := from.x + ix * spacing
			var z := from.y + iz * spacing
			var h: float = heights[i]
			var slope: float = 1.0 - _normals[i].y
			var p := patch.get_noise_2d(x, z) * 0.5 + 0.5
			var q := fine.get_noise_2d(x, z) * 0.5 + 0.5
			w.fill(0.0)
			var dry := 0.0
			# Межа зон: частка кожної зони серед сусідів 3×3 (24 м). У
			# глибині зони всі дев'ять однакові — рахуємо одну.
			var here: int = codes[i]
			var mixed := false
			for dz in range(-1, 2):
				var jz := clampi(iz + dz, 0, grid - 1)
				for dx in range(-1, 2):
					var jx := clampi(ix + dx, 0, grid - 1)
					if codes[jz * grid + jx] != here:
						mixed = true
			if not mixed:
				dry = _zone_rule(kind_of, here, groves, grove_edge, x, z, h,
						p, q, one)
				for k in COUNT:
					w[k] = one[k]
			else:
				var seen := {}
				for dz in range(-1, 2):
					var jz := clampi(iz + dz, 0, grid - 1)
					for dx in range(-1, 2):
						var jx := clampi(ix + dx, 0, grid - 1)
						var c: int = codes[jz * grid + jx]
						var share := 0.25 if dx == 0 and dz == 0 else \
								(0.125 if dx == 0 or dz == 0 else 0.0625)
						seen[c] = float(seen.get(c, 0.0)) + share
				for c: int in seen:
					var share: float = seen[c]
					dry += share * _zone_rule(kind_of, c, groves, grove_edge,
							x, z, h, p, q, one)
					for k in COUNT:
						w[k] += one[k] * share
			_slope_and_shore(w, slope, h - sea, kind_of[here] == 1)
			var t: float = yard[i]
			if t > 0.0:
				for k in COUNT:
					w[k] *= 1.0 - t
				w[SOIL] += t * 1.2
			t = bank[i]
			if t > 0.0:
				for k in COUNT:
					w[k] *= 1.0 - t
				w[SCREE] += t * 0.6
				w[SAND] += t * 0.5
			_store(i, w, dry)


## Правила однієї зони: пише ваги шарів у `out` і вертає сухість трави.
func _zone_rule(kind_of: PackedInt32Array, code: int, groves: Dictionary,
		grove_edge: Dictionary, x: float, z: float, h: float, p: float,
		q: float, out: PackedFloat32Array) -> float:
	out.fill(0.0)
	var kind: int = kind_of[code] if code < kind_of.size() else 3
	var grove := 0.0
	if groves.has(code):
		var edge: float = grove_edge[code]
		var noise: FastNoiseLite = groves[code]
		# Край ширший за край самого гаю: підстилка виходить з-під крайніх
		# дерев на кілька метрів і сходить нанівець, а не лягає смугою.
		grove = smoothstep(edge - 0.07, edge + 0.16, noise.get_noise_2d(x, z))
	match kind:
		0:  # море: дно
			out[SAND] = 1.0
			out[SCREE] = smoothstep(0.5, 0.8, p) * 0.7
		1:  # крижана північ
			out[SNOW] = 1.0
			out[SCREE] = smoothstep(0.6, 0.85, p) * 0.7
			out[LITTER] = grove * 0.35
		2:  # гори заходу: долина — лука, схил — мох і ґрунт, маківка —
			# щебінь із латками снігу. Пороги ті самі, що були в поясів
			# (42 і 82 м), тільки тепер це плавний перехід, а не сходинка.
			var valley := 1.0 - smoothstep(34.0, 50.0, h)
			var peak := smoothstep(74.0, 88.0, h)
			out[MEADOW] = valley * 0.7
			out[MOSS] = (0.4 + valley * 0.3) * (1.0 - peak)
			out[SOIL] = (1.0 - valley) * 0.5 * (1.0 - peak)
			out[SCREE] = smoothstep(0.55, 0.85, p) * 0.5 + peak * 1.2
			out[SNOW] = peak * smoothstep(0.45, 0.7, q) * 1.3
			out[LITTER] = grove * 1.0
			out[MOSS] += grove * 0.6
		4:  # вулканічна смуга: згарище впереміш із темним попелом-щебенем
			out[LITTER] = 0.75
			out[SCREE] = 0.35 + smoothstep(0.4, 0.75, p) * 0.6
			out[SOIL] = smoothstep(0.65, 0.9, q) * 0.3
		5:  # мертвий схід
			out[CRACKED] = 1.0
			out[SCREE] = smoothstep(0.5, 0.8, p) * 0.9
			out[SAND] = smoothstep(0.6, 0.9, q) * 0.4
		6:  # південна тераса
			out[SAND] = 0.7
			out[SOIL] = smoothstep(0.45, 0.8, p) * 0.9
			out[MEADOW] = smoothstep(0.6, 0.9, q) * 0.5 + grove * 0.3
			out[LITTER] = grove * 1.2
		_:  # центральна рівнина
			out[MEADOW] = 1.0
			out[SOIL] = smoothstep(0.55, 0.85, p) * 0.9 \
					+ smoothstep(0.6, 0.9, q) * 0.3
			# Під ялинами — хвоя впереміш із мохом: сама хвоя (Ground048)
			# на першому знімку лягла рудою смугою, у лісі такого нема.
			out[LITTER] = grove * 1.1
			out[MOSS] = grove * 0.8
	return DRYNESS[clampi(kind, 0, DRYNESS.size() - 1)]


## Скеля на крутому, щебінь під нею, пісок біля моря — у будь-якій зоні.
##
## 0,10 і 0,24 — це приблизно 26° і 40°: положистий пагорб лишається
## трав'яним, а стіна гори стає каменем, як і в природі.
static func _slope_and_shore(w: PackedFloat32Array, slope: float,
		above_sea: float, frozen: bool) -> void:
	var cliff := smoothstep(0.10, 0.24, slope)
	var loose := smoothstep(0.05, 0.12, slope) * (1.0 - cliff)
	if cliff > 0.0:
		for k in COUNT:
			w[k] *= 1.0 - cliff
		w[ROCK] += cliff * 1.5
	w[SCREE] += loose * 0.45
	var shore := 1.0 - smoothstep(0.8, 2.6, above_sea)
	if shore > 0.0:
		for k in COUNT:
			w[k] *= 1.0 - shore
		w[SCREE if frozen else SAND] += shore * 1.3


## Нормалізувати й покласти в байти вершини; заразом — що тут росте.
func _store(i: int, w: PackedFloat32Array, dry: float) -> void:
	var sum := 0.0
	for k in COUNT:
		sum += w[k]
	if sum <= 0.0001:
		w[MEADOW] = 1.0
		sum = 1.0
	var inv := 1.0 / sum
	var at := i * PER_VERTEX
	for k in COUNT:
		weights[at + k] = clampi(roundi(w[k] * inv * 255.0), 0, 255)
	# Скільки трави тримає кожен шар. Скеля й сніг — нуль, лісова
	# підстилка майже нуль (під смереками трави не буває, там папороть).
	var grassy: float = (w[MEADOW] + w[SOIL] * 0.55 + w[MOSS] * 0.65
			+ w[LITTER] * 0.08 + w[SCREE] * 0.10 + w[SAND] * 0.06
			+ w[CRACKED] * 0.06) * inv
	var bloom: float = w[MEADOW] * inv * (1.0 - dry)
	var parched: float = dry + w[SOIL] * inv * 0.15
	cover[i * 4] = clampi(roundi(clampf(grassy, 0.0, 1.0) * 255.0), 0, 255)
	cover[i * 4 + 1] = clampi(roundi(clampf(parched, 0.0, 1.0) * 255.0),
			0, 255)
	cover[i * 4 + 2] = clampi(roundi(clampf(bloom, 0.0, 1.0) * 255.0), 0, 255)


## Двори поселень: утоптаний ґрунт. Радіус — двір («радіус»), а не вся
## пляма з полями («рівне»): поле довкола села лишається трав'яним.
func _yard_mask(land: Landscape) -> PackedFloat32Array:
	var mask := PackedFloat32Array()
	mask.resize(points * points)
	for town: Dictionary in land.towns():
		var at: Array = town.get("центр", [0, 0, 0])
		var cx := float(at[0])
		var cz := float(at[2])
		var inner := float(town.get("радіус", 26.0)) * 0.8
		var outer := inner + 14.0
		var box := _box(cx, cz, outer)
		for iz in range(box[1], box[3] + 1):
			for ix in range(box[0], box[2] + 1):
				var far := Vector2(start.x + ix * step - cx,
						start.y + iz * step - cz).length()
				var i := iz * points + ix
				mask[i] = maxf(mask[i], 1.0 - smoothstep(inner, outer, far))
	return mask


## Береги річок: щебінь і пісок на кілька метрів від води.
func _bank_mask(land: Landscape) -> PackedFloat32Array:
	var mask := PackedFloat32Array()
	mask.resize(points * points)
	for stream: Dictionary in land.data.get("русла", []):
		var line: Array = stream.get("точки", [])
		for k in range(line.size() - 1):
			var a := Vector2(float(line[k][0]), float(line[k][1]))
			var b := Vector2(float(line[k + 1][0]), float(line[k + 1][1]))
			var half := float(line[k][3]) * 0.5
			var reach := half + 5.0
			var mid := (a + b) * 0.5
			var box := _box(mid.x, mid.y, a.distance_to(b) * 0.5 + reach)
			for iz in range(box[1], box[3] + 1):
				for ix in range(box[0], box[2] + 1):
					var p := Vector2(start.x + ix * step, start.y + iz * step)
					var far := Geometry2D.get_closest_point_to_segment(
							p, a, b).distance_to(p)
					var i := iz * points + ix
					mask[i] = maxf(mask[i],
							1.0 - smoothstep(half, reach, far))
	return mask


## Межі вершин навколо точки: [x0, z0, x1, z1].
func _box(cx: float, cz: float, radius: float) -> Array[int]:
	return [
		clampi(floori((cx - radius - start.x) / step), 0, points - 1),
		clampi(floori((cz - radius - start.y) / step), 0, points - 1),
		clampi(ceili((cx + radius - start.x) / step), 0, points - 1),
		clampi(ceili((cz + radius - start.y) / step), 0, points - 1),
	]


## Нормаль у кожній вершині — з самого поля висот, а не з трикутників
## клаптя. Так вона однакова по обидва боки межі клаптів, і на стику не
## видно шва світла.
static func _normals_of(heights: PackedFloat32Array, grid: int,
		spacing: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(grid * grid)
	for iz in grid:
		var up_z := maxi(iz - 1, 0)
		var down_z := mini(iz + 1, grid - 1)
		for ix in grid:
			var left := maxi(ix - 1, 0)
			var right := mini(ix + 1, grid - 1)
			var dx: float = (heights[iz * grid + right]
					- heights[iz * grid + left]) / ((right - left) * spacing)
			var dz: float = (heights[down_z * grid + ix]
					- heights[up_z * grid + ix]) / ((down_z - up_z) * spacing)
			out[iz * grid + ix] = Vector3(-dx, 1.0, -dz).normalized()
	return out


## Висота видимої землі — по трикутнику, яким її малює меш клаптя
## (діагональ від b до c, як у `chunk_mesh()`).
func surface_y(x: float, z: float) -> float:
	var fx := (x - start.x) / step
	var fz := (z - start.y) / step
	var ix := clampi(floori(fx), 0, points - 2)
	var iz := clampi(floori(fz), 0, points - 2)
	var tx := clampf(fx - ix, 0.0, 1.0)
	var tz := clampf(fz - iz, 0.0, 1.0)
	var i := iz * points + ix
	var a: float = _heights[i]
	var b: float = _heights[i + 1]
	var c: float = _heights[i + points]
	var d: float = _heights[i + points + 1]
	if tx + tz <= 1.0:
		return a + (b - a) * tx + (c - a) * tz
	return d + (c - d) * (1.0 - tx) + (b - d) * (1.0 - tz)


## Вага шару в найближчій вершині, 0-1.
func layer_at(x: float, z: float, layer: int) -> float:
	if weights.is_empty():
		return 0.0
	var ix := clampi(roundi((x - start.x) / step), 0, points - 1)
	var iz := clampi(roundi((z - start.y) / step), 0, points - 1)
	return weights[(iz * points + ix) * PER_VERTEX + layer] / 255.0


## Що росте в точці, змішано з чотирьох сусідніх вершин.
func cover_at(x: float, z: float) -> Color:
	if cover.is_empty():
		return Color(0, 0, 0, 0)
	var fx := (x - start.x) / step
	var fz := (z - start.y) / step
	var ix := clampi(floori(fx), 0, points - 2)
	var iz := clampi(floori(fz), 0, points - 2)
	var tx := clampf(fx - ix, 0.0, 1.0)
	var tz := clampf(fz - iz, 0.0, 1.0)
	var a := (iz * points + ix) * 4
	var b := a + 4
	var c := a + points * 4
	var d := c + 4
	var got := [0.0, 0.0, 0.0]
	for k in 3:
		got[k] = lerpf(lerpf(cover[a + k], cover[b + k], tx),
				lerpf(cover[c + k], cover[d + k], tx), tz) / 255.0
	return Color(got[0], got[1], got[2], 0.0)


## Меш одного клаптя: `size` клітинок від (cx, cz). Без ваг (сервер) —
## лише вершини й нормалі: серверові земля потрібна тільки як число.
func chunk_mesh(cx: int, cz: int, size: int) -> ArrayMesh:
	var x1 := mini(cx + size, points - 1)
	var z1 := mini(cz + size, points - 1)
	var row := x1 - cx + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var colors := PackedColorArray()
	var more_a := PackedByteArray()
	var more_b := PackedByteArray()
	var painted := not weights.is_empty()
	for iz in range(cz, z1 + 1):
		for ix in range(cx, x1 + 1):
			var i := iz * points + ix
			verts.append(Vector3(start.x + ix * step, _heights[i],
					start.y + iz * step))
			norms.append(_normals[i])
			if painted:
				var at := i * PER_VERTEX
				colors.append(Color(weights[at] / 255.0,
						weights[at + 1] / 255.0, weights[at + 2] / 255.0,
						weights[at + 3] / 255.0))
				for k in range(4, 8):
					more_a.append(weights[at + k])
				for k in range(8, 12):
					more_b.append(weights[at + k])
	var index := PackedInt32Array()
	for iz in range(z1 - cz):
		for ix in range(x1 - cx):
			var a := iz * row + ix
			var b := a + 1
			var c := a + row
			var d := c + 1
			# Той самий порядок, що й раніше (a, b, c, b, d, c): інакше
			# нормаль дивиться вниз і земля відсікається як тильна грань.
			index.append(a)
			index.append(b)
			index.append(c)
			index.append(b)
			index.append(d)
			index.append(c)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = index
	var flags := 0
	if painted:
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_CUSTOM0] = more_a
		arrays[Mesh.ARRAY_CUSTOM1] = more_b
		flags = (Mesh.ARRAY_CUSTOM_RGBA8_UNORM
				<< Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
				| (Mesh.ARRAY_CUSTOM_RGBA8_UNORM
				<< Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
			flags)
	return mesh


## Матеріал землі: три масиви текстур і шейдер.
##
## Файли читаються байтами, а не через `load()`: так само, як решта
## даних світу 2, — гра не залежить від того, чи редактор уже
## імпортував картинки. Немає файлу — кажемо про це (P3) і кладемо
## сіру заглушку того ж розміру, щоб масив зібрався.
static func material(path: ImageTexture = null,
		path_origin := Vector2.ZERO, path_extent := 1.0,
		path_range := 16.0, path_half := 1.4) -> ShaderMaterial:
	var paint := ShaderMaterial.new()
	paint.shader = preload("res://scripts/terrain.gdshader")
	paint.set_shader_parameter("layer_color", _array("Color", false))
	paint.set_shader_parameter("layer_normal", _array("Normal", true))
	paint.set_shader_parameter("layer_height", _array("Height", false))
	var sizes := PackedFloat32Array()
	var rough := PackedFloat32Array()
	var tints := PackedVector3Array()
	for layer: Array in LAYERS:
		sizes.append(float(layer[1]))
		rough.append(float(layer[2]))
		var tint: Color = layer[3]
		tints.append(Vector3(tint.r, tint.g, tint.b))
	while sizes.size() < 12:
		sizes.append(4.0)
		rough.append(0.9)
		tints.append(Vector3.ONE)
	paint.set_shader_parameter("layer_size", sizes)
	paint.set_shader_parameter("layer_rough", rough)
	paint.set_shader_parameter("layer_tint", tints)
	paint.set_shader_parameter("layer_count", LAYERS.size())
	var noise := FastNoiseLite.new()
	noise.seed = Landscape.SEED + 77
	noise.frequency = 0.016
	var macro := ImageTexture.create_from_image(
			noise.get_seamless_image(256, 256))
	paint.set_shader_parameter("macro_noise", macro)
	if path != null:
		paint.set_shader_parameter("path_field", path)
		paint.set_shader_parameter("path_origin", path_origin)
		paint.set_shader_parameter("path_extent", path_extent)
		paint.set_shader_parameter("path_range", path_range)
		paint.set_shader_parameter("path_half", path_half)
		paint.set_shader_parameter("path_layer", PATH)
	else:
		paint.set_shader_parameter("path_layer", 99)
	return paint


const SIDE := 1024


static func _array(kind: String, is_normal: bool) -> Texture2DArray:
	var images: Array[Image] = []
	for layer: Array in LAYERS:
		var path := WHERE % [layer[0], kind]
		var raw := FileAccess.get_file_as_bytes(path)
		var picture := Image.new()
		if raw.is_empty() or picture.load_jpg_from_buffer(raw) != OK:
			print("[земля] ‼ немає %s — шар буде сірим" % path)
			picture = Image.create_empty(SIDE, SIDE, false, Image.FORMAT_RGB8)
			picture.fill(Color(0.5, 0.5, 1.0) if is_normal
					else Color(0.45, 0.45, 0.42))
		if kind == "Height":
			picture.convert(Image.FORMAT_L8)
		else:
			picture.convert(Image.FORMAT_RGB8)
		if picture.get_width() != SIDE or picture.get_height() != SIDE:
			picture.resize(SIDE, SIDE)
		picture.generate_mipmaps()
		images.append(picture)
	var made := Texture2DArray.new()
	made.create_from_images(images)
	return made
