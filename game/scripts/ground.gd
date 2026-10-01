class_name Ground
extends RefCounted
## Речі на землі (П-160): викинуте з торби й загублене при смерті.
##
## Слово замовника 01.10.2026: «зроби додаткову дію — підняти річ, можна
## підняти застакані речі, можна викинути річ, або видалити в інвенторі.
## Можна викинути довільну кількість речей, вказавши кількість». Вигляд
## на землі — «спрощене зображення» (`tools/zemlia_znachky.py`).
##
## Живе на СЕРВЕРІ й нічого не знає про мережу: що лягло чи зникло, світ
## роздає клієнтам сам (`changed`). Поодинока річ лежить як `Item` — з
## афіксами, міцністю й руною, — тож піднята вертається тією самою.
## Складана — ім'я й кількість.

## Скільки лежить, доки не зникне, і хто може підняти — слова замовника
## не було: строк і «будь-хто» — пропозиція виконавця (P5).
const LIFETIME := 300.0
## Ближче за це — дістає рукою: дія «підняти» бере найближчу.
const REACH := 3.0
## Кілька речей, викинутих поспіль, лягають не в одну точку, а розсипом.
const SPREAD := 0.6

## номер -> {"де": Vector3, "річ": Item або null, "назва", "скільки",
## "лишилось": секунди}
var lying: Dictionary = {}
## Щось лягло, піднялось чи зникло — світу пора роздати перелік.
var changed := false
var _next := 0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


## Покласти поодиноку річ біля `at`. Повертає її номер на землі.
func put_thing(item: Item, at: Vector3) -> int:
	return _put(at, {"річ": item, "назва": item.title(), "скільки": 1,
			"база": item.base, "грейд": item.grade})


## Покласти стос.
func put_stack(name: String, count: int, at: Vector3,
		book: ItemBook = null) -> int:
	if count <= 0 or name == "":
		return 0
	var grade := ""
	if book != null:
		grade = str(book.base_of(name).get("грейд", ""))
	return _put(at, {"річ": null, "назва": name, "скільки": count,
			"база": name, "грейд": grade})


func _put(at: Vector3, row: Dictionary) -> int:
	_next += 1
	var angle := _rng.randf() * TAU
	row["де"] = at + Vector3(cos(angle), 0.0, sin(angle)) \
			* _rng.randf_range(0.0, SPREAD)
	row["лишилось"] = LIFETIME
	lying[_next] = row
	changed = true
	return _next


# ── дії гравця ────────────────────────────────────────────────────────
#
# Повертають порожній рядок, коли вдалось, і причину, коли ні — той самий
# стиль, що в `smith.gd`.


## Викинути поодиноку річ `at` з торби під ноги. Вдягнене спершу знімають:
## викинути річ просто з тіла — найлегший спосіб загубити її випадково.
func drop_thing(who: Node, at: int) -> String:
	if at < 0 or at >= who.things.size():
		return "такої речі немає"
	if who.is_worn(at):
		return "спершу зніми"
	var item: Item = who.drop_thing(at)
	put_thing(item, who.global_position)
	return ""


## Викинути `count` штук стосу. Більше, ніж є, не викидається.
func drop_stack(who: Node, name: String, count: int,
		book: ItemBook = null) -> String:
	var have := int(who.items.get(name, 0))
	if have <= 0:
		return "немає: %s" % name
	if count <= 0:
		return "скільки викинути?"
	count = mini(count, have)
	who.take_item(name, count)
	put_stack(name, count, who.global_position, book)
	return ""


## Видалити поодиноку річ із торби — назавжди, на землю вона не лягає.
func destroy_thing(who: Node, at: int) -> String:
	if at < 0 or at >= who.things.size():
		return "такої речі немає"
	if who.is_worn(at):
		return "спершу зніми"
	who.drop_thing(at)
	return ""


func destroy_stack(who: Node, name: String, count: int) -> String:
	var have := int(who.items.get(name, 0))
	if have <= 0:
		return "немає: %s" % name
	if count <= 0:
		return "скільки видалити?"
	who.take_item(name, mini(count, have))
	return ""


## Найближча річ у межах руки. 0 — нічого поруч.
func nearest(at: Vector3, reach: float = REACH) -> int:
	var best := 0
	var best_d := reach
	for key: int in lying:
		var d: float = (lying[key]["де"] as Vector3).distance_to(at)
		if d <= best_d:
			best = key
			best_d = d
	return best


## Підняти найближчу річ: поодинока лягає в торбу як була, стос —
## увесь, до того, що вже є (складається). Повертає {"назва",
## "скільки"} або порожньо, якщо поруч нічого.
func pick_up(who: Node) -> Dictionary:
	var key := nearest(who.global_position)
	if key == 0:
		return {}
	var row: Dictionary = lying[key]
	lying.erase(key)
	changed = true
	if row["річ"] != null:
		who.add_thing(row["річ"])
	else:
		who.give_item(str(row["назва"]), int(row["скільки"]))
	return {"назва": row["назва"], "скільки": row["скільки"]}


## Кожен кадр сервера: що пролежало строк, зникає.
func tick(delta: float) -> void:
	for key: int in lying.keys():
		lying[key]["лишилось"] -= delta
		if lying[key]["лишилось"] <= 0.0:
			lying.erase(key)
			changed = true


## Для клієнта: що де лежить. Номер, місце, ім'я для значка й підказки.
func rows() -> Array:
	var out: Array = []
	for key: int in lying:
		var row: Dictionary = lying[key]
		out.append({"номер": key, "де": row["де"],
				"назва": row["назва"], "база": row["база"],
				"грейд": row["грейд"], "скільки": row["скільки"]})
	return out
