class_name States
extends RefCounted
## Усі стани однієї істоти й те, що вони роблять зі статами.
##
## Правила складання — П-108, погоджено 02.09.2026:
##
##   однакові не додаються, а ПОНОВЛЮЮТЬ строк;
##   різні складаються МНОЖЕННЯМ (+20% і +20% дають +44%, не +40%);
##   кількість не обмежена числом, обмежена строком;
##   баф і дебаф на той самий стат гасять одне одного (1,2 × 0,8 = 0,96).
##
## Клас нічого не знає ні про мережу, ні про вузли: його можна ганяти
## пробою на голих числах.

## Ім'я стану -> State.
var _by_name: Dictionary = {}


## Повісити стан. Той самий (за іменем) не подвоює ефект, а починає строк
## наново — і бере нову величину, якщо джерело стало сильнішим.
func apply(state: State) -> void:
	_by_name[state.name] = state


func remove(name: String) -> bool:
	return _by_name.erase(name)


func has(name: String) -> bool:
	return _by_name.has(name)


func count() -> int:
	return _by_name.size()


func all() -> Array:
	return _by_name.values()


## Строк спливає. Повертає імена тих, що скінчились, — щоб сервер міг
## сказати про це клієнтові.
func tick(delta: float) -> Array:
	var gone: Array = []
	for name in _by_name.keys():
		var state: State = _by_name[name]
		state.left -= delta
		if state.left <= 0.0:
			_by_name.erase(name)
			gone.append(name)
	return gone


## Спільний множник до одного стата. Немає станів — рівно 1,0.
func factor_for(stat: String) -> float:
	var total := 1.0
	for state: State in _by_name.values():
		if state.stat == stat:
			total *= state.factor
	return total


## Чинні стати: базові, помножені на все, що зараз висить.
##
## Повертає НОВИЙ `Stats`, а не міняє базові: інакше баф, що скінчився,
## лишав би слід назавжди — саме так псуються стати в таких системах.
func applied_to(base: Stats) -> Stats:
	var out := Stats.new()
	out.strength = _shift(base.strength, "strength")
	out.agility = _shift(base.agility, "agility")
	out.stamina = _shift(base.stamina, "stamina")
	out.intellect = _shift(base.intellect, "intellect")
	out.sense = _shift(base.sense, "sense")
	# Бафи на каст і відкат — не стати, а окремі поля: відкат статами не
	# ріжеться взагалі (П-35, підтверджено 02.09), тож він і тут іде
	# власним шляхом.
	out.cooldown_cut = base.cooldown_cut + _bonus("cooldown_cut")
	out.cast_speed_bonus = base.cast_speed_bonus + _bonus("cast_speed_bonus")
	out.concentration_bonus = base.concentration_bonus \
			+ _bonus("concentration_bonus")
	# Похідні величини — множенням, як і стати (П-108): +20% і дебаф −20%
	# на швидкість гасять одне одного.
	out.move_factor = factor_for("move_speed")
	out.attack_factor = factor_for("physical_attack")
	out.defence_factor = factor_for("physical_defence")
	out.hp_factor = factor_for("max_hp")
	# Швидкість бою й швидкість відкату вмінь — теж множенням, тож
	# баф ×6 і дебаф ÷6 гасять одне одного, як і решта похідних.
	out.battle_factor = factor_for("attack_speed")
	out.cooldown_factor = factor_for("cooldown_speed")
	return out


## Стат — ціле число, тож множення округлюється, але не нижче 1: інакше
## сильний дебаф зробив би стат нулем, і формули дали б ділення на нуль.
func _shift(value: int, stat: String) -> int:
	return maxi(1, roundi(value * factor_for(stat)))


## Для бафів касту й відкату множник — це не множення, а додаток:
## «баф на чверть відкату» і має додати 0,25 до `cooldown_cut`.
func _bonus(field: String) -> float:
	var total := 0.0
	for state: State in _by_name.values():
		if state.stat == field:
			total += state.factor
	return total
