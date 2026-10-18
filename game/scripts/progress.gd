class_name Progress
extends RefCounted
## Повага, рівні й винагорода за вбивство (крок 3).
##
## Дві валюти, і вони різні (погоджено 02.09.2026):
##
##   ПОВАГА  дає рівні. Накопичується й не списується ніколи, крім
##           смерті: за смерть іде рівно 10% ОБСЯГУ поточного рівня, а
##           не частка накопиченого. Смерть на нулі поваги забирає рівень
##           (18.10.2026).
##   ДОСВІД  платиться за навчання скілів і за смерть не втрачається.
##
## Числа сітки — тимчасові (П-99, П-103): замовник лишив їх на пробу
## грою, і вони живуть у `data/levels.json`, тобто правляться без
## перезапуску.

var grid: Dictionary = {}


func _init(from_data: Dictionary = {}) -> void:
	grid = from_data


## Скільки поваги треба набрати, СТОЯЧИ на цьому рівні, щоб піти далі.
##
## Раса й стать зсувають вимогу: стать на ±2,5%, раса на ±5% — те саме
## «раса = 2 × стать», що й у статах (П-48).
func need_for(level: int, race: String = "людина",
		sex: String = "чоловік") -> int:
	var base: float = float(grid.get("основа", 1000))
	var power: float = float(grid.get("показник", 1.585))
	var shift: float = float(grid.get("раса", {}).get(race, 0.0)) \
			+ float(grid.get("стать", {}).get(sex, 0.0))
	return maxi(1, roundi(base * pow(maxi(1, level), power) * (1.0 + shift)))


## Множник винагороди за різницю рівнів (П-104).
##
## Точки задані в даних, між ними — лінійно. Різниця в 1–2 рівні нічого
## не міняє: інакше гравець рахував би рівні перед кожним ударом.
func reward_multiplier(mob_level: int, player_level: int) -> float:
	var diff: int = mob_level - player_level
	var points: Array = grid.get("різниця рівнів", [])
	if points.is_empty():
		return 1.0
	if diff <= int(points[0]["різниця"]):
		return float(points[0]["множник"])
	for i in range(points.size() - 1):
		var low: Dictionary = points[i]
		var high: Dictionary = points[i + 1]
		if diff >= int(low["різниця"]) and diff <= int(high["різниця"]):
			var span: float = float(int(high["різниця"]) - int(low["різниця"]))
			var part: float = (diff - int(low["різниця"])) / maxf(1.0, span)
			return lerpf(float(low["множник"]), float(high["множник"]), part)
	return float(points[-1]["множник"])


## Додати поваги. Повертає, скільки рівнів узято.
##
## Новий рівень — здоров'я й мана до повна (18.10.2026, слово замовника:
## «після підняття рівня очікую бонус — відновлення HP MP до
## максимуму»). Мертвого не чіпаємо: рівень, узятий прикликаним уже
## після смерті господаря, не має його оживляти.
func add_respect(who: Node, amount: int) -> int:
	who.respect += amount
	var gained := 0
	while who.respect >= need_for(who.level, who.race, who.sex):
		who.respect -= need_for(who.level, who.race, who.sex)
		who.level += 1
		who.stat_points += _points_per_level()
		gained += 1
	if gained > 0 and who.hp > 0:
		who.hp = who.stats.max_hp()
		who.mp = who.stats.max_mp()
	return gained


func _points_per_level() -> int:
	return int(grid.get("очок статів за рівень", 3))


## Втрата за смерть: рівно 10% обсягу поточного рівня, не нижче нуля.
##
## Смерть, коли поваги вже нуль, забирає рівень (18.10.2026, слово
## замовника: «якщо на мінімумі прогрес, то втрачається рівень»). Повага
## тоді стає повним обсягом нижчого рівня мінус ті самі 10% його обсягу —
## наче смерть сталась на ньому. Перший рівень не втрачається.
##
## Очки статів за втрачений рівень забираються з вільних, а коли їх
## менше — у борг (від'ємне число): розподілене не скидаємо, а наступний
## рівень спершу гасить борг. Інакше «загинути й набрати рівень знову»
## щоразу дарувало б ще три очки.
func death_loss(who: Node) -> int:
	var share: float = float(grid.get("втрата за смерть", 0.10))
	if who.respect <= 0 and who.level > 1:
		who.level -= 1
		who.stat_points -= _points_per_level()
		var full: int = need_for(who.level, who.race, who.sex)
		var dropped: int = roundi(full * share)
		who.respect = full - dropped
		return dropped
	var loss: int = roundi(need_for(who.level, who.race, who.sex) * share)
	loss = mini(loss, who.respect)
	who.respect -= loss
	return loss


## Що впало з гравця, коли він загинув (друга половина П-27).
##
## Ранжовано: ресурси йдуть найлегше, здобуте важче, вдягнене майже
## ніколи. Кидається на КОЖНУ річ окремо, тож утрата завжди часткова —
## саме це й називається «частина речей».
##
## Числа — пропозиція П-112. Множник штрафу за позначку вбивці (П-64)
## сюди ще не входить: його числа чекають у П-88.
##
## Повертає перелік того, що зникло, — щоб сказати гравцеві словами.
## `ground` є — втрачене лягає на землю біля загиблого (П-160), немає —
## зникає, як до 01.10.2026 (так ганяють пробу без світу).
func lose_items(who: Node, goods: Object, ground: Ground = null,
		more: float = 1.0) -> Array:
	var chances: Dictionary = grid.get("втрата речей", {})
	if chances.is_empty():
		return []
	var lost: Array = []

	for name in who.items.keys():
		var kind: String = goods.kind_of(name) if goods != null else "ресурс"
		if kind == "гроші":
			continue                      # гроші поки не губляться
		# Позначеному вбивці — більше (П-261): `more` = 1,1 за вбивство.
		var chance: float = minf(1.0, more * float(chances.get(
				"ресурси" if kind == "ресурс" else "лут", 0.0)))
		var count: int = int(who.items[name])
		var gone := 0
		for i in count:
			if randf() < chance:
				gone += 1
		if gone > 0:
			lost.append("%s ×%d" % [name, gone])
			if ground != null:
				ground.put_stack(name, gone, who.global_position, goods)
			if gone >= count:
				who.items.erase(name)
			else:
				who.items[name] = count - gone

	# Поодинокі перебираємо з кінця: `drop_thing` зсуває номери.
	for at in range(who.things.size() - 1, -1, -1):
		var worn: bool = who.is_worn(at)
		var chance: float = minf(1.0, more * float(chances.get(
				"вдягнене" if worn else "лут", 0.0)))
		if randf() >= chance:
			continue
		var item: Item = who.drop_thing(at)
		if item != null:
			lost.append(item.title() + (" (був удягнений)" if worn else ""))
			if ground != null:
				ground.put_thing(item, who.global_position)
	return lost


## Розподілити одне вільне очко в стат (П-147). Разом із максимумом росте
## й ПОТОЧНЕ здоров'я/мана — на ту саму різницю, інакше очко у
## Витривалість нічого не давало б, поки гравець не долікується.
##
## Повертає порожній рядок, якщо вийшло, або причину — той самий стиль,
## що й у `runes.gd`.
func spend_stat(who: Node, field: String) -> String:
	if not Stats.STAT_FIELDS.has(field):
		return "такого стата немає"
	if who.stat_points <= 0:
		return "немає вільних очок"
	var before_hp: int = who.stats.max_hp()
	var before_mp: int = who.stats.max_mp()
	var prop: String = Stats.STAT_FIELDS[field]
	who.base_stats.set(prop, int(who.base_stats.get(prop)) + 1)
	who.stat_points -= 1
	who.refresh_stats()
	who.hp = mini(who.stats.max_hp(),
			who.hp + (who.stats.max_hp() - before_hp))
	who.mp = mini(who.stats.max_mp(),
			who.mp + (who.stats.max_mp() - before_mp))
	return ""


## Частка поточного рівня, від 0 до 1 — для смуги в HUD.
func share_of_level(who: Node) -> float:
	return clampf(float(who.respect)
			/ maxf(1.0, need_for(who.level, who.race, who.sex)), 0.0, 1.0)
