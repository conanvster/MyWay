class_name Warehouse
extends RefCounted
## Завідувач складу: класти речі на схов і забирати назад (крок 5, П-145).
##
## Живе на СЕРВЕРІ й нікому не вірить (П-08), той самий принцип, що й
## `Shop`: клієнт каже лише «хочу покласти/забрати оце», решта —
## перевірка тут. Склад окремий на персонажа (слово замовника
## 03.09.2026) і бере і складані речі, і поодинокі з афіксами.

const TALK_RANGE := 4.0


func within(who: Node3D, resident: Node3D) -> bool:
	return who.global_position.distance_to(resident.global_position) \
			<= TALK_RANGE


# ── складані ─────────────────────────────────────────────────────────

## Покласти весь стос складаної речі на склад.
func store_stack(who: Node, name: String) -> String:
	var have := int(who.items.get(name, 0))
	if have <= 0:
		return "такої речі немає"
	who.take_item(name, have)
	who.warehouse_items[name] = int(who.warehouse_items.get(name, 0)) + have
	return ""


## Забрати весь стос складаної речі зі складу.
func withdraw_stack(who: Node, name: String) -> String:
	var have := int(who.warehouse_items.get(name, 0))
	if have <= 0:
		return "на складі цього немає"
	who.warehouse_items.erase(name)
	who.give_item(name, have)
	return ""


# ── поодинокі ────────────────────────────────────────────────────────

## Покласти поодиноку річ за її номером у торбі.
func store_thing(who: Node, at: int) -> String:
	if at < 0 or at >= who.things.size():
		return "такої речі немає"
	if who.is_worn(at):
		return "спершу зніми"
	var item: Item = who.drop_thing(at)
	who.warehouse_things.append(item)
	return ""


## Забрати поодиноку річ за її номером на складі.
func withdraw_thing(who: Node, at: int) -> String:
	if at < 0 or at >= who.warehouse_things.size():
		return "на складі цього немає"
	var item: Item = who.warehouse_things[at]
	who.warehouse_things.remove_at(at)
	who.add_thing(item)
	return ""
