class_name Creature
extends CharacterBody3D
## Спільне для всього живого: гравців і монстрів.
##
## Рух і бій рахує ТІЛЬКИ сервер (П-08). Клієнт лише малює те, що
## сервер надіслав.

## Дальність удару від статів не залежить — її задасть зброя.
const ATTACK_RANGE := 2.5
## Щоб на самій межі персонажі не блимали, зникають вони трохи далі,
## ніж з'являються.
const VISION_HYSTERESIS := 1.12
## Черга дій за П-38: 4-6 натискань.
const QUEUE_MAX := 5

## Відновлення здоров'я й мани (числа — пропозиція П-101), частка
## максимуму за секунду:
const REGEN_FIGHT := 0.01    ## у бою
const REGEN_REST := 0.02     ## стоячи, поза боєм
const REGEN_SIT := 0.06      ## сидячи — утричі швидше, ніж стоячи
## Скільки після удару вважається «в бою».
const FIGHT_TIME := 3.0
## Правило повороту (П-85, погоджено 02.09.2026):
##
##   є ціль (аґро)  — розвертається до неї МИТТЮ, обійти не вийде;
##   немає цілі     — напрямок дає рух, і тільки він.
##
## Тому спину відкриває не той, хто повільно крутиться, а той, хто тебе
## ЩЕ НЕ ПОМІТИВ: пасивний монстр блукає, дивлячись куди йде, і поки його
## не вдарили — на гравця поруч не повертається.

## Скільки лежить труп (П-45). Без застосованого вміння — коротко,
## із застосованим — довго. Числа взяті з середини погоджених меж
## 3-5 і 15-30 секунд.
const CORPSE_SHORT := 4.0
const CORPSE_LONG := 20.0
## Труп гравця лежить незрівнянно довше за монстрячий: до 20 хвилин,
## щоб хтось устиг його оживити (П-70).
const CORPSE_PLAYER := 1200.0
## З яким запасом здоров'я гравець підводиться (П-69).
const REVIVE_SHARE := 0.30

## Стати БАЗОВІ: раса, стать, рівень. Їх міняє тільки розвиток.
var base_stats := Stats.new()
## Стати ЧИННІ: базові плюс усе, що зараз висить (крок 2.1). Саме їх
## питає бій — щоб дебаф на чутливість чи баф на відкат діяли самі собою,
## без окремої перевірки в кожній формулі.
var stats := Stats.new()
## Бафи й дебафи. Кожен зі строком (П-108).
var states := States.new()
var hp := 0
## Мана. Витрачати її поки нічим — заглушка до вмінь (крок 2.2), але HUD
## показує справжнє число, а не намальоване.
var mp := 0
## Скільки труп ще лежатиме. 0 у живого.
var corpse_left := 0.0

## Куди істота біжить зараз. Камера бере це, щоб доводитись за рухом.
var move_direction := Vector3.ZERO
## Куди істота ДИВИТЬСЯ: поворот навколо вертикалі, у радіанах.
## Веде сервер — з напрямку руху, а при ударі з напрямку на ціль.
## Без цього поля нема на чому рахувати удар зі спини (П-40, П-81):
## капсули на екрані були повернуті випадково.
var facing := 0.0
## Куди сервер сказав дивитись. Клієнт плавно довертається сюди.
var server_facing := 0.0
## Намір, надісланий клієнтом. Заповнює сервер із мережі.
var wanted := Vector2.ZERO
## Спить (монстр далеко від усіх гравців, `mob_ai.gd`): стоїть на землі,
## фізику для нього не рахуємо.
var asleep := false

## Крихітний «інтелект» на випадок застрягання об кут будинку/паркану/
## дерева (замовник побачив: наказ «іди до крамаря» буксує на розі
## будинку — намір щокадру рахується прямою лінією на ціль, без жодної
## обізнаності про перешкоди; `move_and_slide()` ковзає вздовж стіни,
## але на випуклому куті пряма на ціль знову «тисне» крізь неї). Ліки —
## не шлях-пошук, а рефлекс: не посунулись за STUCK_CHECK — крок назад,
## тоді трохи по діагоналі (слова замовника), і знову пряма на ціль.
const STUCK_CHECK := 0.4
const STUCK_MIN := 0.25
const ESCAPE_BACK := 0.35
const ESCAPE_TURN := 0.55
var _stuck_since := Vector3.ZERO
var _stuck_clock := 0.0
var _escape_left := 0.0
var _escape_dir := Vector3.ZERO
var _escape_diag := Vector3.ZERO
## Заклинило: хоче йти, а не зрушив ані на міліметр, — і відступ назад
## теж не рятує. Так буває на гострому ребрі стіни підземелля: рушій
## рахує нормаль зіткнення навпаки, і капсулу тягне в стіну, в будь-який
## бік і навіть униз (застрягання замовника 19.09.2026, «Хід під
## костелом»: точка прохідна, але жоден з 8 боків не рухає). Після
## WEDGED_AFTER такого стояння — переставити на найближче вільне місце
## тієї самої підлоги (`_unwedge`).
const WEDGED_AFTER := 1.0
const WEDGED_MOVE := 0.002
var _wedged := 0.0
## Куди сервер сказав стати. Клієнт плавно підтягується сюди.
var server_position := Vector3.ZERO

var target_id := 0
## Рівень персонажа: його дає ПОВАГА (крок 3). Поки не росте, але скіли
## вже питають, бо вчаться з певного рівня.
var level := 1
## Досвід — валюта на навчання скілів (не повага, яка дає рівні).
var experience := 0
## Повага — те, що дає рівні. За смерть втрачається 10% обсягу рівня.
var respect := 0
## Нерозподілені очки статів: по стільки за кожен рівень.
var stat_points := 0
## Акаунт, якому належить персонаж (крок 5). Порожній — гра без бази.
var account := ""
## Раса й стать: від них залежить і сітка поваги, і базові стати (П-89).
var race := "людина"
var sex := "чоловік"
## СКЛАДАНІ речі: ім'я -> скільки. Гроші, ресурси, руни, витратне.
var items: Dictionary = {}
## ПООДИНОКІ речі: зброя, обладунки, амулети. У кожної свої афікси, тож
## кількістю їх не порахувати (крок 4).
var things: Array[Item] = []
## Склад (крок 5, П-145): друга пара торби й речей, до якої немає
## доступу в бою — лише через завідувача складу. Окремий на персонажа.
var warehouse_items: Dictionary = {}
var warehouse_things: Array[Item] = []
## Що вдягнене: слот -> номер у `things`.
var gear: Dictionary = {}

## Вивчені скіли: ключ -> рівень усередині грейду (П-106).
var learned: Dictionary = {}

## Професія (П-224). Порожня — етап 1, «без професії»: гравець бачить
## лише спільні вкладки вмінь.
var profession := ""
## Назви відкритих прихованих гілок. Доки гілки тут немає, її вмінь
## гільдмайстер не показує й вивчити їх не можна.
var opened: Array[String] = []
## Кого і скільки вбив: назва виду → скільки. Це рахунок для квестів
## переходу й для гілок, що відкриваються полюванням, тому він
## зберігається разом із персонажем, а не живе до виходу з гри.
var kills: Dictionary = {}
## Взяте в майстра гільдії завдання переходу (П-227): {"професія",
## "від"} — «від» = скільки цього виду було вбито на мить, коли взяв.
## Лічильник «убито|треба» рахується від неї, не від усього життя.
var quest: Dictionary = {}
## Позначка вбивці (П-87/П-261): {"вбивств", "згасає за" (с гри)}.
## Порожньо — не позначений. Веде `Outlaws`; зберігається з персонажем.
var outlaw: Dictionary = {}
## Відкати скілів: ключ -> скільки секунд лишилось.
var skill_ready_in: Dictionary = {}
var attack_ready_in := 0.0
var busy_in := 0.0
## Що зараз читається: ключ скіла, скільки лишилось і скільки тривало.
## Порожній ключ означає, що каст не йде (крок 2.3).
var casting_key := ""
var casting_left := 0.0
var casting_full := 0.0
## Кого мітив, коли починав. Ціль могли змінити посеред читання, а скіл
## має влучити в того, на кого його починали (П-42).
var casting_target := 0
## Скільки ще лічиться «в бою»: оновлюється кожним ударом по тобі й твоїм.
var in_fight := 0.0
## Скільки ще можна не дихати. Під водою спадає, на повітрі вертається
## (П-61). Нижче нуля — тоне.
var breath := 0.0
## Наскільки швидко відновлює благодатне місце, у якому стоїш (П-113).
## 0 — не в ньому.
var in_grace := 0.0
## Сидить: відновлює швидше, але встає від першого ж удару (П-101).
var sitting := false
## Залишки, що не дотягли до цілої одиниці. Без них при 1% на секунду й
## тіку 1/60 не відновлювалось би нічого взагалі: roundi(0,016) = 0.
var _hp_left := 0.0
var _mp_left := 0.0
var _drown_left := 0.0
var queue: Array[String] = []


func _ready() -> void:
	var body := get_node_or_null("Mesh")
	if body is CreatureModel:
		body.build()
	seat_model()
	refresh_stats()
	if hp == 0:
		hp = stats.max_hp()
	if mp == 0:
		mp = stats.max_mp()


## Перерахувати чинні стати. Кликати після кожної зміни станів або
## базових статів; сам бій цього не робить — він просто читає `stats`.
## Чинні стати = базові ПЛЮС спорядження, а вже потім помножені на
## стани. Порядок саме такий (крок 2.1): спорядження додає, стани
## множать — інакше баф +20% давав би різне залежно від того, у якому
## порядку його повісили.
func refresh_stats() -> void:
	var dressed := Stats.new()
	dressed.strength = base_stats.strength + _gear_bonus("сила")
	dressed.agility = base_stats.agility + _gear_bonus("спритність")
	dressed.stamina = base_stats.stamina + _gear_bonus("витривалість")
	dressed.intellect = base_stats.intellect + _gear_bonus("інтелект")
	dressed.sense = base_stats.sense + _gear_bonus("чуття")
	# Рунні посилення коваля бувають не статами, а відсотками швидкості
	# (21.09.2026). Каст і відкат — додатком, як і бафи на них: відкат
	# скорочує лише спорядження й стани, не стати (П-35), і це саме той
	# шлях. Швидкість атаки — множником, як баф священика.
	dressed.cooldown_cut = base_stats.cooldown_cut \
			+ _gear_bonus(Smith.COOLDOWN) / 100.0
	dressed.cast_speed_bonus = base_stats.cast_speed_bonus \
			+ _gear_bonus(Smith.CAST) / 100.0
	dressed.concentration_bonus = base_stats.concentration_bonus
	stats = states.applied_to(dressed)
	stats.battle_factor *= 1.0 + _gear_bonus(Smith.ATTACK_SPEED) / 100.0
	# Стан, що піднімав здоров'я (штраф світу, П-213), спав — здоров'я
	# не може лишитись вищим за новий максимум.
	hp = mini(hp, stats.max_hp())


## Скільки цього стата дає вдягнене. Стати речей названі українською —
## так їх пишуть у `data/items.json`, і так їх читає людина.
func _gear_bonus(stat: String) -> int:
	var total := 0
	for slot in gear:
		var at: int = gear[slot]
		if at >= 0 and at < things.size() and not things[at].is_blunt():
			total += int(things[at].stats.get(stat, 0))
	return total


## Удар влучив — зброя тупиться (21.09.2026). Повертає true, коли саме
## цим ударом міцність дійшла до нуля: тоді бій ламає зброю
## (`Smith.break_weapon`, П-234) і каже про це гравцеві.
func wear_weapon(amount: int) -> bool:
	var weapon: Item = worn_in("зброя")
	if weapon == null or weapon.durability_max <= 0 or weapon.durability <= 0:
		return false
	weapon.durability = maxi(0, weapon.durability - amount)
	if weapon.durability > 0:
		return false
	refresh_stats()
	return true


## Узяти поодиноку річ. Повертає її номер в інвентарі.
func add_thing(item: Item) -> int:
	things.append(item)
	return things.size() - 1


## Вдягти. Що вже стояло в цій комірці — знімається саме собою.
##
## `want` — у яку саме комірку тіла (для перснів, бо пальців два).
## Порожнє — гра бере першу вільну, а як вільних немає, то першу.
##
## Два правила про руки, і обидва тут, а не в показі: показ нічого не
## вирішує (П-08), а обійти його — це підказати клієнтові, що можна.
func equip(at: int, want: String = "") -> String:
	if at < 0 or at >= things.size():
		return "такої речі немає"
	var item: Item = things[at]
	var places: Array = ItemBook.slots_for(item.slot)
	if places.is_empty():
		return "%s не вдягається" % item.title()

	# Сокира на дві руки звільняє щит; щит не вдягнеться, поки в руках
	# дворучна.
	if item.slot == "зброя" and item.two_handed:
		gear.erase("щит")
	if item.slot == "щит":
		var weapon: Item = worn_in("зброя")
		if weapon != null and weapon.two_handed:
			return "«%s» — на дві руки, щит нікуди подіти" % weapon.title()

	var place: String = want if places.has(want) else ""
	if place == "":
		place = places[0]
		for free in places:
			if not gear.has(free):
				place = free
				break
	gear[place] = at
	refresh_stats()
	return ""


## Що стоїть у цій комірці тіла. Порожньо — нічого.
func worn_in(slot: String) -> Item:
	if not gear.has(slot):
		return null
	var at: int = int(gear[slot])
	return things[at] if at >= 0 and at < things.size() else null


func unequip(slot: String) -> void:
	if gear.erase(slot):
		refresh_stats()


func is_worn(at: int) -> bool:
	return gear.values().has(at)


## Викинути поодиноку річ. Номери зсуваються, тож вдягнене переписуємо.
func drop_thing(at: int) -> Item:
	if at < 0 or at >= things.size():
		return null
	var item: Item = things[at]
	things.remove_at(at)
	var fixed := {}
	for slot in gear:
		var was: int = gear[slot]
		if was == at:
			continue
		fixed[slot] = was - 1 if was > at else was
	gear = fixed
	refresh_stats()
	return item


## Повісити баф або дебаф і одразу перерахувати стати.
func add_state(state: State) -> void:
	states.apply(state)
	refresh_stats()


func die() -> void:
	hp = 0
	sitting = false
	stop_cast()
	corpse_left = CORPSE_SHORT
	queue.clear()
	wanted = Vector2.ZERO
	target_id = 0
	# Бафи й дебафи зі смертю спадають — усі, і «поки живий» теж: це
	# його ж строк. Клієнт побачить порожній ряд станів за відбитком
	# (`world._push`), окремого повідомлення не треба.
	if states.count() > 0:
		states.clear()
		refresh_stats()


## Вміння, застосоване до трупа, продовжує йому строк (П-45).
func extend_corpse() -> void:
	corpse_left = maxf(corpse_left, CORPSE_LONG)


func is_corpse() -> bool:
	return hp <= 0 and corpse_left > 0.0


## Тіло, яке видно: або фігурка з примітивів, або готова модель із
## набору. Обидві вміють `dress`, `animate` і `swing`, тож решті коду
## однаково, що саме там стоїть. Може бути порожнім у пробах.
func model() -> Node3D:
	var body := get_node_or_null("Mesh")
	return body if body is CreatureModel or body is SkinnedModel else null


## Підпис над головою: хто це і якого рівня.
##
## Досі ціль у показі звалась «монстр 22» — номером з'єднання, який не
## означає нічого. Тепер над кожним видно ім'я, а колір каже головне:
## по кому ти влучиш, а від кого краще піти.
##
## `Label3D` навмисно замість напису в показі: він сам обертається до
## камери, сам ховається за стіною й не потребує щокадрового
## перерахунку екранних координат.
const TAG_HEIGHT := 0.55


func show_tag(text: String, tint: Color) -> void:
	var tag: Label3D = get_node_or_null("Підпис")
	if tag == null:
		tag = Label3D.new()
		tag.name = "Підпис"
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = false
		tag.font_size = 48
		tag.outline_size = 14
		tag.outline_modulate = Color(0, 0, 0, 0.85)
		# Сталий розмір на екрані, а не у світі. Інакше та сама назва
		# здалеку зникає, а зблизька займає пів екрана — обидва випадки
		# знято. Так само роблять усі MMO з іменами над головами.
		tag.fixed_size = true
		tag.pixel_size = 0.0009
		add_child(tag)
	# Над головою: зріст моделі плюс трохи. У фігурок і моделей висота
	# однакова за домовленістю (П-105), тож одного числа досить.
	tag.position = Vector3(0.0, head_y() + TAG_HEIGHT, 0.0)
	tag.text = text
	tag.modulate = tint


## Стрілка над вибраним (П-156): жовта, вертикально вниз, над підписом.
## Рамка цілі в HUD каже ЩО вибрано, але не каже, ЯКА фігура у світі це,
## якщо поруч кілька однакових на вигляд істот.
## З 13.09.2026 — ще й коло під ногами (`select_mark.gd`): замовник не
## розумів, кого вибрав, стрілка була задрібна.
func mark_as_target(on: bool) -> void:
	if on:
		SelectMark.put(self, 0.8, head_y() + TAG_HEIGHT)
	else:
		SelectMark.clear(self)


## На скільки ноги нижче за сам вузол. Вузол тіла — це середина капсули
## зіткнення (так її ставить `CharacterBody3D`), а ноги моделі — у її
## власному початку; без зсуву кожна істота висіла над землею на пів
## капсули: людина на 1,00 м (проба `probes/feet.gd`, слово замовника
## 19.09.2026: «аватар висить над поверхнею»). Капсула в монстрів
## масштабується зростом (`mob.gd:_apply_look`), тож і зсув з нею.
func foot_drop() -> float:
	var holder := get_node_or_null("Collision") as CollisionShape3D
	if holder == null or not (holder.shape is CapsuleShape3D):
		return 0.0
	var capsule := holder.shape as CapsuleShape3D
	return capsule.height * 0.5 * holder.scale.y - holder.position.y


## Верх голови відносно вузла — для підпису й позначки цілі.
func head_y() -> float:
	return body_height() - foot_drop()


## Поставити модель ногами на низ капсули. Суто вигляд: фізика, сервер і
## все, що міряє від вузла (перевірка місця П-202, камера), не міняються.
## Кликати щоразу, як модель замінено або змінено зріст.
func seat_model() -> void:
	var body := model()
	if body != null:
		body.position.y = -foot_drop()


## Наскільки істота висока. Потрібно, щоб підпис не вліз у голову.
func body_height() -> float:
	var body := model()
	if body == null:
		return 1.75
	# У фігурки з примітивів це `body_height`, у моделі з набору —
	# `height`. Обидві означають ОДНЕ Й ТЕ САМЕ (зріст у метрах, П-105),
	# просто назвались по-різному.
	if "body_height" in body:
		return float(body.body_height)
	if "height" in body:
		return float(body.height)
	return 1.75


## Труп лягає. Викликає клієнт — це суто вигляд.
##
## Модель людини має власний рух падіння (П-162, `Death01`) — тоді
## кладемо анімацією, а не грубим поворотом на 90°: обидва разом
## виглядали б так, ніби тіло падає ЩЕ РАЗ уже лежачи.
func lay_down() -> void:
	var mesh := get_node_or_null("Mesh")
	if mesh == null:
		return
	var fall := death_move()
	if fall != "":
		mesh.show_move(fall)
		return
	mesh.rotation = Vector3(PI / 2.0, 0.0, 0.0)
	# Лежить на боці: вісь фігурки — на висоті її товщини над землею.
	mesh.position = Vector3(0.0, 0.15 - foot_drop(), 0.0)


## Власний рух падіння моделі, або порожньо. У людини він зветься
## `Death01` (набір Quaternius), у своїх моделей з Blender — `Death`
## (19.09.2026: без цього заєць не падав своїм рухом на бік, а гра
## перекидала всю модель на спину поворотом на 90°).
func death_move() -> String:
	var mesh := get_node_or_null("Mesh")
	if not (mesh is SkinnedModel):
		return ""
	for name: String in ["Death01", "Death"]:
		if mesh.has_move(name):
			return name
	return ""


## Зворотне до `lay_down`. Теж суто вигляд, теж викликає клієнт.
## Без цього оживлений лишався лежати на екрані в усіх, хто його бачить
## — з повним здоров'ям і на ходу.
func stand_up() -> void:
	var mesh := get_node_or_null("Mesh")
	if mesh == null:
		return
	if death_move() != "":
		mesh.show_move("Idle")
		return
	mesh.rotation = Vector3.ZERO
	mesh.position = Vector3(0.0, -foot_drop(), 0.0)


## Розвернутись у бік напрямку. Кут той самий, що й у камери: -Z вузла
## дивиться туди, куди показує `dir`.
func face_to(dir: Vector3) -> void:
	if dir.x * dir.x + dir.z * dir.z < 0.0001:
		return
	facing = atan2(-dir.x, -dir.z)


## Розвернутись до точки. Миттю — так вирішено в П-85.
func face_point(point: Vector3) -> void:
	face_to(point - global_position)


## Переставити БЕЗ плавності: поява, оживлення, майбутні телепорти.
## Інакше клієнт тягне капсулу до нової позиції з SMOOTHING = 14, і
## оживлений проїжджає через усю мапу за пів секунди, крізь будинки.
func place_at(pos: Vector3, look: float) -> void:
	global_position = pos
	server_position = pos
	facing = look
	server_facing = look
	rotation.y = look


## Перенос — телепорт, підземелля, арена, місто. Те саме, що
## `place_at`, і ще забуває, куди біг і кого бив: черга дій, напрямок
## і ціль лишились там, звідки перенесло (слово замовника 11.10.2026:
## «після телепортації повинна зніматися цілевказівка останніх дій —
## бігти, бити»). Виштовхування зі стіни (`_unstick`) — не перенос,
## воно йде через голий `place_at`.
func teleport_to(pos: Vector3, look: float) -> void:
	place_at(pos, look)
	queue.clear()
	wanted = Vector2.ZERO
	target_id = 0


## Ознака саме вади рушія: нормаль зіткнення дивиться ВІД істоти (тягне
## в стіну). Коли просто тиснеш у рівну стіну, нормаль дивиться на тебе —
## тоді це не застрягання, і переставляти не треба.
func _pulled_in() -> bool:
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var away := global_position - hit.get_position()
		away.y = 0.0
		if hit.get_normal().dot(away) < 0.0:
			return true
	return false


## Найближче місце, де капсула ні з чим не перетинається, під нею підлога,
## а дорога від теперішнього місця до нього не перетинає стіну (щоб не
## вискочити в товщу скелі чи за стіну). Кільця від 0,3 до 2,4 м.
func _unwedge() -> void:
	var space := get_world_3d().direct_space_state
	var shapes: Array[CollisionShape3D] = []
	for child in get_children():
		if child is CollisionShape3D and not child.disabled:
			shapes.append(child)
	# Початок істоти — центр капсули, не п'яти: ставимо так, щоб низ
	# капсули був на 5 см над знайденою підлогою.
	var feet := 1.0
	for holder in shapes:
		if holder.shape is CapsuleShape3D:
			feet = holder.shape.height * 0.5 - holder.position.y
	var from := global_position
	var eye := Vector3(0, 1.0, 0)
	for step in range(1, 9):
		var r := 0.3 * step
		for turn in 12:
			var spot := from + Vector3(r, 0.3, 0).rotated(Vector3.UP,
					TAU * turn / 12.0)
			var road := PhysicsRayQueryParameters3D.create(from + eye,
					spot + eye, 1)
			if not space.intersect_ray(road).is_empty():
				continue
			var down := PhysicsRayQueryParameters3D.create(spot + eye,
					spot - Vector3(0, 3.0, 0), 1)
			var ground := space.intersect_ray(down)
			if ground.is_empty() or ground["normal"].y < 0.7:
				continue
			var stand: Vector3 = ground["position"] + Vector3(0, feet + 0.05,
					0)
			var free := true
			for holder in shapes:
				var q := PhysicsShapeQueryParameters3D.new()
				q.shape = holder.shape
				q.collision_mask = 1
				q.transform = Transform3D(global_basis, stand) \
						* holder.transform
				if not space.intersect_shape(q, 1).is_empty():
					free = false
					break
			if free:
				place_at(stand, facing)
				velocity = Vector3.ZERO
				print(("[рух] %s заклинило в (%.1f, %.1f, %.1f) — переставлено"
						+ " на %.1f м") % [name, from.x, from.y, from.z,
						from.distance_to(stand)])
				return
	print(("[рух] ‼ %s заклинило в (%.1f, %.1f, %.1f), вільного місця"
			+ " за 2,4 м немає") % [name, from.x, from.y, from.z])


func server_step(delta: float) -> void:
	if not is_alive():
		corpse_left = maxf(0.0, corpse_left - delta)
		return
	if asleep and is_on_floor():
		return
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
	else:
		velocity.y = 0.0

	# Обрізаємо довжину: інакше підроблений намір дав би надшвидкість.
	var raw_dir := Vector3(wanted.x, 0.0, wanted.y).limit_length(1.0)
	# Читає скіл, який велить стояти (П-200): наміру йти немає зовсім — і
	# обхід застрягання нижче не прийме нерухомість за «уперся в кут».
	if is_casting() and casting_move <= 0.0:
		raw_dir = Vector3.ZERO
		_escape_left = 0.0
	var dir := raw_dir

	if _escape_left > 0.0:
		# У фазі втечі: спершу назад, тоді по діагоналі — своя пряма на
		# ціль тут ні до чого, вона й завела в кут.
		dir = _escape_dir if _escape_left > ESCAPE_TURN else _escape_diag
		_escape_left -= delta
	elif raw_dir.length() > 0.1:
		_stuck_clock += delta
		if _stuck_clock >= STUCK_CHECK:
			var moved := global_position.distance_to(_stuck_since)
			_stuck_clock = 0.0
			_stuck_since = global_position
			if moved < STUCK_MIN:
				var side := 1.0 if randf() < 0.5 else -1.0
				_escape_dir = -raw_dir
				_escape_diag = raw_dir.rotated(Vector3.UP,
						deg_to_rad(70.0) * side)
				_escape_left = ESCAPE_BACK + ESCAPE_TURN
				dir = _escape_dir
	else:
		_stuck_clock = 0.0
		_stuck_since = global_position

	move_direction = dir
	# Біжить — дивиться туди, куди біжить: бігти боком не можна. Стоїть —
	# тримає бік; розвертає його тільки ціль (`face_point` у бою та в
	# mob_ai.gd), і саме тому непомічений гравець заходить у спину.
	face_to(dir)
	var speed := stats.move_speed()
	# Читання сповільнює або зупиняє — як велить сам скіл (П-200).
	if is_casting():
		speed *= casting_move
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	var before := global_position
	move_and_slide()
	if dir.length() > 0.1 and speed > 0.0 \
			and global_position.distance_to(before) < WEDGED_MOVE \
			and _pulled_in():
		_wedged += delta
		if _wedged >= WEDGED_AFTER:
			_wedged = 0.0
			_unwedge()
	else:
		_wedged = 0.0

	attack_ready_in = maxf(0.0, attack_ready_in - delta)
	busy_in = maxf(0.0, busy_in - delta)
	in_fight = maxf(0.0, in_fight - delta)
	_regen(delta)

	for key in skill_ready_in.keys():
		var left: float = skill_ready_in[key] - delta
		if left <= 0.0:
			skill_ready_in.erase(key)
		else:
			skill_ready_in[key] = left

	# Строк станів спливає на сервері; що скінчилось — перераховуємо.
	if not states.tick(delta).is_empty():
		refresh_stats()


## Чи знає істота цей скіл і чи минув його відкат.
func knows(key: String) -> bool:
	return skill_level(key) > 0


## Рівень уміння, з яким воно діє: вивчене ПЛЮС рівні з вдягнених речей
## (П-221, слово замовника 10.10.2026: «складаються»). Зняв річ — лишається
## вивчене; не вивчав — діє, лише поки річ на тобі. Затуплена зброя, як і
## її стати, вміння не дає. Понад останній рівень скіла не росте — це
## обрізає `Skill.at`.
func skill_level(key: String) -> int:
	return int(learned.get(key, 0)) + gear_skill(key)


func gear_skill(key: String) -> int:
	var total := 0
	for slot in gear:
		var at: int = gear[slot]
		if at >= 0 and at < things.size() and not things[at].is_blunt():
			total += int(things[at].skills.get(key, 0))
	return total


## Усі вміння, що діють зараз: вивчені й від речей.
func skill_keys() -> Array:
	var out: Array = learned.keys()
	for slot in gear:
		var at: int = gear[slot]
		if at >= 0 and at < things.size() and not things[at].is_blunt():
			for key: String in things[at].skills:
				if not out.has(key):
					out.append(key)
	return out


func skill_ready(key: String) -> bool:
	return not skill_ready_in.has(key)


func has_item(name: String) -> bool:
	return name == "" or int(items.get(name, 0)) > 0


## Забрати штуку або кілька. Руна витрачається при використанні (П-50),
## а гроші йдуть сотнями за раз у крамаря — звідси `count`.
func take_item(name: String, count: int = 1) -> void:
	if name == "" or count <= 0:
		return
	var left: int = int(items.get(name, 0)) - count
	if left > 0:
		items[name] = left
	else:
		items.erase(name)


func give_item(name: String, count: int = 1) -> void:
	items[name] = int(items.get(name, 0)) + count


## Вивчити скіл одразу потрібного рівня. Руни й досвід — крок 2.5; поки
## це шлях, яким скіл потрапляє в істоту (і в монстра теж).
func learn(key: String, level: int = 1) -> void:
	learned[key] = level


## Під водою. Дихання спадає, а коли скінчилось — здоров'я тане (П-61).
##
## Числа приходять іззовні: скільки триматися й скільки втрачати за
## секунду — це баланс, а не властивість істоти.
##
## Повертає true, якщо цієї миті гравець захлинувся, — щоб світ міг
## сказати про це словами.
func breathe(delta: float, under_water: bool, holds: float,
		harm: float) -> bool:
	if not is_alive():
		return false
	if not under_water:
		# На повітрі дихання вертається вчетверо швидше, ніж витрачалось:
		# виринув — і майже одразу можеш пірнати знову.
		breath = minf(holds, breath + delta * 4.0)
		return false
	breath -= delta
	if breath > 0.0:
		return false
	# Шкода накопичується дробом, а не округлюється щоразу вгору.
	# Інакше нижня межа «одна одиниця за виклик» при 60 кадрах на секунду
	# дає 60 за секунду замість чотирьох — спіймано пробою.
	_drown_left += stats.max_hp() * harm * delta
	if _drown_left < 1.0:
		return false
	var was: int = hp
	hp = maxi(0, hp - int(_drown_left))
	_drown_left -= int(_drown_left)
	return was > 0 and hp < was


## Відновлення здоров'я й мани. Швидкість залежить від того, чи ти в бою
## і чи сидиш (П-93, П-101). Монстри користуються тим самим кодом —
## у них це «здоров'я потроху відновлюється» з П-109.
func _regen(delta: float) -> void:
	if not is_alive():
		return
	var rate := REGEN_FIGHT
	if in_fight <= 0.0:
		rate = REGEN_SIT if sitting else REGEN_REST
	# У благодатному місці відновлення швидше за будь-яке сидіння (П-113).
	if in_grace > 0.0:
		rate = maxf(rate, in_grace)
	_hp_left += stats.max_hp() * rate * delta
	_mp_left += stats.max_mp() * rate * delta
	if _hp_left >= 1.0:
		hp = mini(stats.max_hp(), hp + int(_hp_left))
		_hp_left -= int(_hp_left)
	if _mp_left >= 1.0:
		mp = mini(stats.max_mp(), mp + int(_mp_left))
		_mp_left -= int(_mp_left)


## Сісти або встати. Сидячи відновлюєшся втричі швидше, але від першого
## удару підводишся.
func sit(down: bool) -> void:
	sitting = down and is_alive()


func is_casting() -> bool:
	return casting_key != ""


## Частка швидкості, поки читає (П-200): ставить скіл при `start_cast`.
var casting_move := 0.0


## Почати читання.
func start_cast(key: String, seconds: float, target: int,
		move_share: float = 0.0) -> void:
	casting_key = key
	casting_left = seconds
	casting_full = seconds
	casting_target = target
	casting_move = move_share


## Кинути читання — і коли дочитав, і коли збили.
func stop_cast() -> void:
	casting_key = ""
	casting_left = 0.0
	casting_full = 0.0
	casting_target = 0
	casting_move = 0.0


func is_alive() -> bool:
	return hp > 0


func vision_radius() -> float:
	return stats.vision_radius()
