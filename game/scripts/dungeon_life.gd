class_name DungeonLife
extends Node
## Строк підземель і штраф світу (П-153, Ф7) — і те, що обидва
## переживають перезапуск сервера.
##
## Задум замовника 05.09.2026: «не вбитий за 30 днів бос закриває
## підземелля й накладає на весь світ 7-денний штраф — забафаних мобів;
## штрафи за кілька незачищених підземель складаються».
##
## Відлік іде від АКТИВАЦІЇ святині, а не від першого входу: ключ
## витрачено саме тоді, і саме тоді святиня світиться відкритою. Тому й
## запис у базі з'являється на активації (шаблону ще немає), а шаблон і
## зерно дописуються першим входом. Без цього перезапуск сервера
## відбирав би в гравця витрачений ключ.
##
## Час — секунди Unix, цілим числом: і в пам'яті, і в базі. Рядки часу
## з поясами PostgREST і Godot розбирають по-різному, а число — ні.
##
## Живе лише на сервері. Клієнт про строк нічого не знає: закриття
## приходить йому як `client_dungeon_closed`, штраф — як стан на
## монстрі, який HUD уже вміє показати.

const DUNGEONS := "dungeons"
const PENALTIES := "world_penalties"
## Як часто дивитись, чи не минув строк. Строк у днях — секунди тут
## нічого не важать.
const LOOK_EVERY := 10.0
const DAY := 86400.0

## Номер святині -> {"grade", "template", "seed", "opened", "closes"}.
var records: Dictionary = {}
## Чинні штрафи: [{"shrine", "until"}].
var penalties: Array = []
## Звідки брати «зараз». Проба підміняє, щоб не чекати 30 днів.
var clock: Callable = func() -> float: return Time.get_unix_time_from_system()

var _store: Store
var _life: Dictionary = {}
var _world_key := ""
var _look_in := 0.0


func setup(store: Store, life: Dictionary, world_key: String) -> void:
	_store = store
	_life = life
	_world_key = world_key


func now() -> int:
	return int(clock.call())


func days_open() -> float:
	return float(_life.get("строк_днів", 30.0))


func days_penalty() -> float:
	return float(_life.get("штраф_днів", 7.0))


## Прочитати з бази, що було відкрито до перезапуску. `restored`
## кличеться на кожне ще живе підземелля, `expired` — на те, чий строк
## минув, поки сервер стояв.
func restore(restored: Callable, expired: Callable) -> void:
	if _store == null or not _store.works():
		print("[підземелля] бази немає — строк і штраф не збережуться")
		return
	var world := "world=eq.%s" % _world_key.uri_encode()
	_store.fetch(PENALTIES, "%s&until=gt.%d" % [world, now()],
			func(ok: bool, rows: Array) -> void:
				if not ok:
					return
				for row: Dictionary in rows:
					penalties.append({"shrine": int(row["shrine"]),
							"until": int(row["until"])})
				if not penalties.is_empty():
					print("[підземелля] штрафів світу чинних: %d"
							% penalties.size()))
	_store.fetch(DUNGEONS, world, func(ok: bool, rows: Array) -> void:
			if not ok:
				return
			for row: Dictionary in rows:
				var at := int(row["shrine"])
				records[at] = {"grade": str(row["grade"]),
						"template": str(row["template"]),
						"seed": int(row["seed"]),
						"opened": int(row["opened_at"]),
						"closes": int(row["closes_at"])}
				if now() >= int(records[at]["closes"]):
					expired.call(at)
				else:
					restored.call(at, records[at])
			print("[підземелля] з бази: %d відкритих" % records.size()))


## Святиню активовано — пішов відлік.
func activated(at: int, grade: String) -> void:
	var from := now()
	records[at] = {"grade": grade, "template": "", "seed": 0,
			"opened": from, "closes": from + int(days_open() * DAY)}
	_save(at)


## Перший вхід збудував підземелля — запам'ятати, яке саме.
func built(at: int, template: String, with_seed: int) -> void:
	if not records.has(at):
		return
	records[at]["template"] = template
	records[at]["seed"] = with_seed
	_save(at)


## Скільки днів лишилось, для напису. -1 — не активована.
func days_left(at: int) -> float:
	if not records.has(at):
		return -1.0
	return maxf(0.0, (int(records[at]["closes"]) - now()) / DAY)


## Раз на `LOOK_EVERY` — чи не минув строк. Повертає номери святинь, чиї
## підземелля треба закрити; запис і штраф веде сам.
func tick(delta: float) -> Array[int]:
	var due: Array[int] = []
	_look_in -= delta
	if _look_in > 0.0:
		return due
	_look_in = LOOK_EVERY
	var moment := now()
	for at: int in records.keys():
		if moment >= int(records[at]["closes"]):
			due.append(at)
	penalties = penalties.filter(func(p: Dictionary) -> bool:
			return int(p["until"]) > moment)
	return due


## Строк минув: запис геть, штраф на світ.
func expire(at: int) -> void:
	records.erase(at)
	var until := now() + int(days_penalty() * DAY)
	penalties.append({"shrine": at, "until": until})
	if _store != null and _store.works():
		# Запис, ще в дорозі, воскресив би видалене, якби дійшов після
		# видалення. Тоді видаляємо, щойно він дійде.
		_again.erase(at)
		if _busy.has(at):
			_drop_after[at] = true
		else:
			_drop_row(at)
		_store.put(PENALTIES, {"world": _world_key, "shrine": at,
				"until": until})


## Стани, які штраф вішає на монстра. Строк стану — скільки лишилось
## самому штрафові: закінчиться він — стан спаде сам, тим самим шляхом,
## що й будь-який баф. Кожен штраф — окремі стани з окремими іменами,
## тому вони складаються (П-108), а не поновлюють один одного.
func penalty_states() -> Array[State]:
	var out: Array[State] = []
	var moment := now()
	for p: Dictionary in penalties:
		var left := float(int(p["until"]) - moment)
		if left <= 0.0:
			continue
		for one: Dictionary in _life.get("штраф", []):
			out.append(State.new("штраф світу · святиня %d" % int(p["shrine"])
					+ " · " + str(one.get("стат", "")),
					str(one.get("стат", "")), float(one.get("множник", 1.0)),
					left))
	return out


## Записи однієї святині — строго по черзі. Активація й перший вхід
## шлють два запити майже разом, і відповідь на старіший могла прийти
## останньою й затерти шаблон порожнім (спіймано пробою через справжню
## базу 19.09.2026). Поки запис у дорозі, наступний чекає й піде вже з
## найсвіжішим станом.
var _busy: Dictionary = {}
var _again: Dictionary = {}
var _drop_after: Dictionary = {}


func _drop_row(at: int) -> void:
	_store.drop(DUNGEONS, "world=eq.%s&shrine=eq.%d"
			% [_world_key.uri_encode(), at])


func _save(at: int) -> void:
	if _store == null or not _store.works():
		return
	if _busy.has(at):
		_again[at] = true
		return
	if not records.has(at):
		return
	_busy[at] = true
	var r: Dictionary = records[at]
	_store.put(DUNGEONS, {"world": _world_key, "shrine": at,
			"grade": r["grade"], "template": r["template"],
			"seed": r["seed"], "opened_at": r["opened"],
			"closes_at": r["closes"]},
			func(_ok: bool, _rows: Array) -> void:
				_busy.erase(at)
				if _drop_after.has(at):
					_drop_after.erase(at)
					_drop_row(at)
				elif _again.has(at):
					_again.erase(at)
					_save(at))
