#!/usr/bin/env bash
# Перевірка перед комітом: чи компілюється код, чи підіймається сервер,
# чи відповідає він клієнтові, чи не бреше стартова сторінка.
#
#   ./check.sh              усе, разом із вікном, боєм і крамарем (~3 хв)
#   ./check.sh --швидко     без вікна й бою (близько 40 секунд) — так
#                           ганяє гачок перед комітом
#   ./check.sh --лінт       лише лінтер
#
# Навіщо. Один випадок — стартова сторінка стукала TCP у сервер, який
# слухає UDP, — з'їв чотири години. Жодна проба його не ловила, бо проби
# перевіряють числа всередині, а тут ламалось на стику процесів. Тому
# перевірки нижче навмисно запускають СПРАВЖНІ процеси й дивляться, що
# один сказав другому.
#
# Змінні тут лише латиницею: кирилична назва тихо ламає масиви й `for`.

set -uo pipefail
cd "$(dirname "$0")"

logs=".logs/check"
mkdir -p "$logs"
port=24565
mark="$HOME/.local/share/godot/app_userdata/гра-lineage/сервер.json"
# Перевірки ганяються у СВІТІ 2 — тому, у який грають (П-205). До
# 06.11.2026 тут був світ 600 м («малий і швидкий»), і перевірки мовчки
# не бачили ні міст, ні мостів, ні річок світу 2. Слово замовника
# 06.11.2026: «перенеси всі типи тестів на нову карту, щоб не тестували
# автоматично на застарілому функціоналі». Прапорець дається і серверові,
# і клієнтові: інакше вони опиняться в різних світах.
test_world="--світ2"

failed=0
passed=0
skipped=0
## Номер сервера, який підняли МИ. Чужих не чіпаємо: перевірка не має
## права вбити сервер, за яким хтось саме грає.
own_server=""

say_ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; passed=$((passed + 1)); }
say_bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; failed=$((failed + 1)); }
say_skip() { printf '  \033[33m∅\033[0m %s\n' "$1"; skipped=$((skipped + 1)); }
head_of()  { printf '\n\033[1m%s\033[0m\n' "$1"; }

# Хто зайняв порт сервера. Порожньо — не зайнятий.
server_pid() {
    ss -lunp 2>/dev/null | grep ":$port " | grep -o 'pid=[0-9]*' \
        | cut -d= -f2 | head -1
}

stop_server() {
    # Тільки свій. Чужий сервер міг підняти той, хто зараз грає.
    [ -z "$own_server" ] && return 0
    kill "$own_server" 2>/dev/null
    own_server=""
    rm -f "$mark"
    # Порт звільняється не миттєво, а наступна перевірка одразу його бере.
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        [ -z "$(server_pid)" ] && return 0
        sleep 0.3
    done
    return 1
}

# Сервер відв'язуємо від цієї оболонки: інакше він гине разом із нею,
# щойно скрипт доходить до кінця кроку, і наступний крок стукає в порожнечу.
start_server() {
    local log="$1"
    shift
    # Стару мітку прибираємо ДО запуску. Інакше чекання бреше: воно
    # бачить чужу мітку від убитого сервера (той її прибрати не встигає)
    # і вважає, що новий уже збудував світ, хоч він щойно взяв порт.
    rm -f "$mark"
    setsid nohup godot --headless --path game -- --server "$test_world" "$@" \
        > "$log" 2>&1 < /dev/null &
    disown
    for _ in $(seq 1 40); do
        if [ -n "$(server_pid)" ] && [ -f "$mark" ]; then
            own_server="$(server_pid)"
            return 0
        fi
        sleep 0.5
    done
    return 1
}


## Прибирання за собою — і при звичайному кінці, і при Ctrl+C.
##
## Сервер запускається `setsid`, тобто відв'язаним від цієї оболонки: без
## цього рядка перерваний скрипт лишав би його жити назавжди. Саме так
## забуті сервери й з'їли колись усю пам'ять.
cleanup() {
    [ -n "$own_server" ] && kill "$own_server" 2>/dev/null
    [ -n "${own_client:-}" ] && kill "$own_client" 2>/dev/null
    [ -n "${own_client2:-}" ] && kill "$own_client2" 2>/dev/null
    return 0
}
trap cleanup EXIT INT TERM

# ── лінтер ────────────────────────────────────────────────────────────
run_lint() {
    head_of "Лінтер"
    if godot --headless --path game res://scenes/lint.tscn \
            > "$logs/lint.log" 2>&1; then
        say_ok "$(grep -c 'перевірено скриптів' "$logs/lint.log" > /dev/null \
            && grep 'перевірено скриптів' "$logs/lint.log" | tr -s ' ')"
        local notes
        notes="$(grep -c '^    · ' "$logs/lint.log")"
        [ "$notes" -gt 0 ] && printf '    (зауважень: %s — %s)\n' \
            "$notes" "$logs/lint.log"
    else
        say_bad "код не компілюється або порушено домовленості:"
        grep -E '^    ‼ ' "$logs/lint.log" | sed 's/^/  /'
    fi
}

# ── сервер відповідає ─────────────────────────────────────────────────
#
# Не «процес живий» і не «порт зайнято», а саме ВІДПОВІДЬ: клієнт стукає,
# сервер заводить йому персонажа й шле назад стан. Обидва боки мусять це
# сказати у своїх журналах.
run_server() {
    head_of "Сервер відповідає клієнтові"
    stop_server
    if ! start_server "$logs/server.log" --полігон; then
        say_bad "сервер не піднявся за 20 с — $logs/server.log"
        return
    fi
    say_ok "піднявся: $(grep -o '\[полігон\].*' "$logs/server.log" | head -1)"

    timeout 25 godot --headless --path game -- --демо "$test_world" \
        > "$logs/client.log" 2>&1
    if grep -q 'приєднався' "$logs/server.log"; then
        say_ok "сервер завів персонажа: $(grep -o 'приєднався.*' \
            "$logs/server.log" | head -1)"
    else
        say_bad "сервер не побачив клієнта — $logs/server.log"
    fi
    # Рядок, який клієнт може надрукувати ЛИШЕ з відповіді сервера:
    # про благодатне місце йому каже сервер, коли персонаж уже у світі.
    if grep -q '^\[гра\]' "$logs/client.log"; then
        say_ok "клієнт отримав відповідь: $(grep -m1 -o '\[гра\].*' \
            "$logs/client.log")"
    else
        say_bad "клієнт не дочекався відповіді — $logs/client.log"
    fi
    if grep -q 'ERROR' "$logs/client.log"; then
        say_bad "у журналі клієнта є помилки:"
        grep -m3 'ERROR' "$logs/client.log" | sed 's/^/      /'
    else
        say_ok "клієнт відпрацював без помилок"
    fi
}

# ── стартова сторінка ─────────────────────────────────────────────────
run_page() {
    head_of "Стартова сторінка"
    # Свій сервер, а не чийсь із попереднього кроку: кроки мають бути
    # незалежні, інакше падіння одного тягне за собою решту.
    stop_server
    start_server "$logs/server-page.log" --полігон \
        || { say_bad "сервер не піднявся"; return; }
    godot --headless --path game --script res://probes/launcher.gd \
        -- "$test_world" \
        > "$logs/page-up.log" 2>&1
    if grep -q 'сервер: працює' "$logs/page-up.log"; then
        say_ok "бачить живий сервер"
    else
        say_bad "не бачить живого сервера — $logs/page-up.log"
    fi
    if grep -q 'номер із мітки: [0-9]' "$logs/page-up.log"; then
        say_ok "знає, кого зупиняти: $(grep -o 'номер із мітки: [0-9]*' \
            "$logs/page-up.log")"
    else
        say_bad "не знає номера сервера — кнопка «Зупинити» безсила"
    fi

    stop_server
    godot --headless --path game --script res://probes/launcher.gd \
        -- "$test_world" \
        > "$logs/page-down.log" 2>&1
    if grep -q 'сервер: не запущений' "$logs/page-down.log"; then
        say_ok "бачить, що сервера немає"
    else
        say_bad "показує сервер, якого немає — $logs/page-down.log"
    fi
}

# ── клієнт малює ──────────────────────────────────────────────────────
run_screen() {
    head_of "Клієнт малює"
    if [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
        say_skip "немає екрана — перевірка картинки пропущена"
        return
    fi
    stop_server
    start_server "$logs/server-screen.log" --полігон \
        || { say_bad "сервер не піднявся"; return; }
    rm -f "$HOME/.local/share/godot/app_userdata/гра-lineage/"знімок-*.png
    # NOVSYNC: без нього перевірка міряє не гру, а робочий стіл.
    # Композитор не показує кадри вікну, якого не видно (інше вікно
    # зверху, інший стіл, замкнений екран), Godot чекає на показ кадру, і
    # клієнт іде 1 кадр за секунду — GPU 0%, ЦП 19%, тобто не
    # завантажений, а заблокований. Перший знімок тоді припадає на 33-35 с
    # замість ~5, і крок валиться на межі 30 с, кажучи «картинка не
    # підтвердилась», хоча малює клієнт правильно. Заміряно 05.09.2026:
    # той самий клієнт без синхронізації дає 300-450 кадрів за секунду.
    # Саме це, а не «втома системи», і стояло за плаваючими провалами
    # цього кроку з 03.09.2026.
    NOVSYNC=1 timeout 30 ./run.sh --демо "$test_world" \
        > "$logs/screen-client.log" 2>&1
    godot --headless --path game --script res://probes/screen.gd \
        > "$logs/screen.log" 2>&1
    if grep -q '✓' "$logs/screen.log"; then
        grep -E '^  [а-яА-Яa-z]' "$logs/screen.log" | sed 's/^/    /'
        say_ok "на знімку є світ і показ"
    else
        say_bad "картинка не підтвердилась — $logs/screen.log"
        grep -E '‼' "$logs/screen.log" | sed 's/^/      /'
    fi
}

# ── бій від початку до здобичі ────────────────────────────────────────
run_fight() {
    head_of "Бій: ціль за 5 метрів, підійти, вбити, взяти здобич"
    stop_server
    start_server "$logs/server-fight.log" --полігон \
        || { say_bad "сервер не піднявся"; return; }
    : > "$logs/fight.log"
    godot --headless --path game -- --демо "$test_world" \
        > "$logs/fight.log" 2>&1 &
    local player=$!
    own_client=$player
    # Чекаємо не «доки вийде час», а доки все, що перевіряємо, з'явиться в
    # журналах: заміряно, що здобич падає секунд за двадцять п'ять, і
    # тримати клієнта далі — це просто марно згаяні хвилини.
    local waited=0
    while [ "$waited" -lt 90 ]; do
        # Чекаємо не лише на першу здобич, а й на другу ціль: вона стоїть
        # за 9 метрів, і саме на ній перевіряється підхід. Раніше цикл
        # виходив на 16-й секунді — до того, як показ до неї взявся.
        if grep -q 'здобуто:' "$logs/fight.log" \
                && grep -q 'повага +' "$logs/fight.log" \
                && grep -q 'підходжу до цілі' "$logs/fight.log"; then
            break
        fi
        sleep 1
        waited=$((waited + 1))
    done
    kill "$player" 2>/dev/null
    wait "$player" 2>/dev/null
    own_client=""
    printf '    (бій зайняв %d с)\n' "$waited"

    grep -q 'приєднався' "$logs/server-fight.log" \
        && say_ok "тестовий гравець зайшов" \
        || say_bad "гравець не зайшов"
    grep -q '\[бій\].*вдарив -' "$logs/server-fight.log" \
        && say_ok "дійшов і вдарив: $(grep -m1 -o '\[бій\].*' \
            "$logs/server-fight.log")" \
        || say_bad "жодного удару по монстрові"
    grep -q '^\[бій\] -[0-9]* загинув' "$logs/server-fight.log" \
        && say_ok "монстр загинув" \
        || say_bad "монстр не загинув за 90 с"
    grep -q 'повага +' "$logs/fight.log" \
        && say_ok "нагорода: $(grep -m1 -o 'повага +.*' "$logs/fight.log")" \
        || say_bad "повага не нарахована"
    grep -q 'здобуто:' "$logs/fight.log" \
        && say_ok "здобич: $(grep -m1 -o 'здобуто:.*' "$logs/fight.log")" \
        || say_bad "здобич не впала (з трьох зайців це раз на 4000)"
    # Друга ціль стоїть за 9 метрів — тобто далі за будь-яку дальність,
    # крім променя. Якщо підхід зламається, тут буде «задалеко».
    grep -q 'підходжу до цілі' "$logs/fight.log" \
        && say_ok "до дальньої цілі підійшов сам" \
        || say_bad "не підійшов до цілі — дія просто зникла"
    # Панель мусить бути та, що просив замовник: 1 удар, 2 ціль, 3 промінь.
    if grep -q '"attack", "next_mob", "скіл:енергетичний-промінь"' \
            "$logs/server-fight.log"; then
        say_ok "панель за замовчуванням: 1 удар · 2 ціль · 3 промінь"
    else
        say_bad "розкладка панелі не та, що домовлялись"
    fi
    grep -q 'задалеко' "$logs/fight.log" \
        && say_bad "дія загубилась через відстань: $(grep -c 'задалеко' \
            "$logs/fight.log") разів" \
        || say_ok "жодної дії не загублено через відстань"
}

# ── крамар: підійти, поговорити, купити, продати ─────────────────────
#
# Обгортка навколо ./run.sh --демо-крамар: показ сам полює, доки не
# набере грошей, потім іде до Ліди, торгується задорогою річчю (сервер
# МУСИТЬ відмовити), купує кристал душі й продає його назад.
run_shop() {
    head_of "Крамар: підійти, поговорити, купити, продати"
    stop_server
    start_server "$logs/server-shop.log" --полігон \
        || { say_bad "сервер не піднявся"; return; }
    : > "$logs/shop.log"
    godot --headless --path game -- --демо --крамар "$test_world" \
        > "$logs/shop.log" 2>&1 &
    local player=$!
    own_client=$player
    local waited=0
    while [ "$waited" -lt 90 ]; do
        if grep -q '\[крамар\] показ закінчив торгувати' "$logs/shop.log"; then
            break
        fi
        sleep 1
        waited=$((waited + 1))
    done
    kill "$player" 2>/dev/null
    wait "$player" 2>/dev/null
    own_client=""
    printf '    (крамар зайняв %d с)\n' "$waited"

    grep -q 'приєднався' "$logs/server-shop.log" \
        && say_ok "тестовий гравець зайшов" \
        || say_bad "гравець не зайшов"
    grep -q '\[крамар\] у мапі немає жодного крамаря' "$logs/shop.log" \
        && say_bad "у мапі немає крамаря — Ліда зникла"
    grep -q '\[гра\] не вистачає грошей' "$logs/shop.log" \
        && say_ok "сервер відмовив у задорогій речі: $(grep -m1 -o \
            '\[гра\] не вистачає грошей.*' "$logs/shop.log")" \
        || say_bad "задорога річ не відхилена — сервер вірить клієнту"
    grep -q '\[гра\] куплено:' "$logs/shop.log" \
        && say_ok "куплено: $(grep -m1 -o '\[гра\] куплено:.*' \
            "$logs/shop.log")" \
        || say_bad "нічого не куплено"
    grep -q '\[гра\] продано:' "$logs/shop.log" \
        && say_ok "продано: $(grep -m1 -o '\[гра\] продано:.*' \
            "$logs/shop.log")" \
        || say_bad "нічого не продано"
    grep -q '\[крамар\] показ закінчив торгувати' "$logs/shop.log" \
        && say_ok "торгівля пройшла до кінця" \
        || say_bad "торгівля не дійшла до кінця за 90 с"

    # Звіряємо гроші: крамар купує за DEFAULT_BUYBACK = 40% від ціни
    # продажу (shop.gd). Якщо ці числа розійдуться — щось порахувало
    # інакше, ніж домовлено.
    local buy_amount sell_amount expect
    buy_amount=$(grep -m1 -o '\[гра\] куплено:.*за [0-9]*' "$logs/shop.log" \
        | grep -o '[0-9]*$')
    sell_amount=$(grep -m1 -o '\[гра\] продано:.*за [0-9]*' "$logs/shop.log" \
        | grep -o '[0-9]*$')
    if [ -n "$buy_amount" ] && [ -n "$sell_amount" ]; then
        expect=$((buy_amount * 40 / 100))
        [ "$expect" -lt 1 ] && expect=1
        if [ "$sell_amount" -eq "$expect" ]; then
            say_ok "гроші зійшлись: купив за $buy_amount, продав за \
$sell_amount (40%)"
        else
            say_bad "гроші не зійшлись: купив за $buy_amount, продав за \
$sell_amount, очікував $expect"
        fi
    else
        say_bad "не вдалось звірити гроші — купівлю чи продаж не знайдено \
в журналі"
    fi

    if grep -q 'ERROR' "$logs/shop.log"; then
        say_bad "у журналі клієнта є помилки:"
        grep -m3 'ERROR' "$logs/shop.log" | sed 's/^/      /'
    fi
}

# ── обмін між гравцями (П-218) ────────────────────────────────────────
#
# Два справжні клієнти через справжній сервер: ведучий (`--веде`) полює
# до перших грошей, другий ходить слідом. Тоді ведучий кличе на обмін,
# кладе всі гроші на стіл, обидва згоджуються. Звіряємо: скільки віддав
# один — стільки ж отримав другий, а сервер записав обмін у журнал.
run_trade() {
    head_of "Обмін між гравцями: запросити, покласти, обидва згодні"
    stop_server
    start_server "$logs/server-trade.log" --полігон \
        || { say_bad "сервер не піднявся"; return; }
    : > "$logs/trade-lead.log"
    : > "$logs/trade-follow.log"
    godot --headless --path game -- --демо --обмін --веде "$test_world" \
        > "$logs/trade-lead.log" 2>&1 &
    own_client=$!
    sleep 2
    godot --headless --path game -- --демо --обмін "$test_world" \
        > "$logs/trade-follow.log" 2>&1 &
    own_client2=$!
    local waited=0
    while [ "$waited" -lt 120 ]; do
        if grep -q '\[обмін\] показ закінчив' "$logs/trade-lead.log" \
            && grep -q '\[обмін\] показ закінчив' "$logs/trade-follow.log"
        then
            break
        fi
        sleep 1
        waited=$((waited + 1))
    done
    kill "$own_client" "$own_client2" 2>/dev/null
    wait "$own_client" "$own_client2" 2>/dev/null
    own_client=""
    own_client2=""
    printf '    (обмін зайняв %d с)\n' "$waited"

    local gave before_follow after_follow
    gave=$(grep -m1 -o 'показ закінчив: віддав [0-9]*' "$logs/trade-lead.log" \
        | grep -o '[0-9]*$')
    after_follow=$(grep -m1 -o 'показ закінчив: отримав, грошей тепер [0-9]*' \
        "$logs/trade-follow.log" | grep -o '[0-9]*$')
    if [ -z "$gave" ] || [ -z "$after_follow" ]; then
        say_bad "обмін не дійшов до кінця за 120 с"
        grep -h '\[обмін\]\|\[гра\]' "$logs/trade-lead.log" \
            "$logs/trade-follow.log" | tail -6 | sed 's/^/      /'
        return
    fi
    say_ok "ведучий віддав $gave грошей, у другого стало $after_follow"
    grep -q 'показ закінчив: віддав [0-9]*, грошей тепер 0' \
        "$logs/trade-lead.log" \
        && say_ok "у ведучого лишилось 0" \
        || say_bad "у ведучого гроші не зникли: $(grep -m1 -o \
            'показ закінчив.*' "$logs/trade-lead.log")"
    before_follow=0
    [ "$after_follow" -eq "$((before_follow + gave))" ] \
        && say_ok "гроші зійшлись: $gave → $after_follow" \
        || say_bad "гроші не зійшлись: віддав $gave, отримав $after_follow"
    grep -q '\[обмін\].*гроші ×'"$gave" "$logs/server-trade.log" \
        && say_ok "сервер записав обмін у журнал" \
        || say_bad "у журналі сервера немає рядка [обмін]"
    if grep -q 'ERROR' "$logs/trade-lead.log" "$logs/trade-follow.log"; then
        say_bad "у журналах клієнтів є помилки:"
        grep -h -m3 'ERROR' "$logs/trade-lead.log" "$logs/trade-follow.log" \
            | sed 's/^/      /'
    fi
}

# ── погоджений PvP: виклик і арена (П-260) ─────────────────────────────
#
# Два справжні клієнти через справжній сервер: ведучий (`--веде`) кличе
# другого на арену, той погоджується, обох переносить, б'є лише ведучий.
# Звіряємо: обидва побували на арені, переможений не загубив речей, і
# обох повернуло туди, звідки покликали. Ведучий стоїть на місці — йому
# не далі 1 м; другий у мить згоди ще йде до ведучого (кличуть за 4 м, а
# підходить він до 2,5), і його останнє місце на клієнті розходиться з
# серверним на крок-два — йому не далі 3 м.
run_duel() {
    head_of "Арена: виклик, бій за згодою, повернення"
    stop_server
    start_server "$logs/server-duel.log" --полігон \
        || { say_bad "сервер не піднявся"; return; }
    : > "$logs/duel-lead.log"
    : > "$logs/duel-follow.log"
    godot --headless --path game -- --демо --арена --веде "$test_world" \
        > "$logs/duel-lead.log" 2>&1 &
    own_client=$!
    sleep 2
    godot --headless --path game -- --демо --арена "$test_world" \
        > "$logs/duel-follow.log" 2>&1 &
    own_client2=$!
    local waited=0
    while [ "$waited" -lt 150 ]; do
        if grep -q '\[арена\] показ закінчив' "$logs/duel-lead.log" \
            && grep -q '\[арена\] показ закінчив' "$logs/duel-follow.log"
        then
            break
        fi
        sleep 1
        waited=$((waited + 1))
    done
    kill "$own_client" "$own_client2" 2>/dev/null
    wait "$own_client" "$own_client2" 2>/dev/null
    own_client=""
    own_client2=""
    printf '    (бій зайняв %d с)\n' "$waited"

    local side log line far most
    for side in lead follow; do
        most=$([ "$side" = lead ] && echo 1.0 || echo 3.0)
        log="$logs/duel-$side.log"
        grep -q '\[арена\] показ: на арені' "$log" \
            && say_ok "$side: $(grep -m1 -o 'на арені, стою в .*' "$log")" \
            || { say_bad "$side: на арену не перенесло"; continue; }
        line=$(grep -m1 -o 'показ закінчив: .*' "$log")
        far=$(printf '%s' "$line" | grep -o 'за [0-9.]* м' | grep -o '[0-9.]*')
        if [ -z "$far" ]; then
            say_bad "$side: назад не повернуло за 150 с"
        elif awk -v f="$far" -v m="$most" 'BEGIN { exit !(f <= m) }'; then
            say_ok "$side: ${line#показ закінчив: }"
        else
            say_bad "$side: повернуло задалеко — $line"
        fi
    done
    grep -q 'поразка. речі не загублено' "$logs/duel-follow.log" \
        && say_ok "переможений: «поразка. речі не загублено»" \
        || say_bad "переможений не дістав «поразки»"
    grep -q 'загублено, лежить на землі' "$logs/duel-follow.log" \
        && say_bad "на арені впали речі"
    grep -q '\[арена\] .* переміг ' "$logs/server-duel.log" \
        && say_ok "сервер записав: $(grep -m1 -o '\[арена\] .* переміг .*' \
            "$logs/server-duel.log")" \
        || say_bad "у журналі сервера немає переможця"
    grep -q '\[pvp\]' "$logs/server-duel.log" \
        && say_bad "на арені хтось флагнутий: $(grep -m1 '\[pvp\]' \
            "$logs/server-duel.log")"
    if grep -q 'ERROR' "$logs/duel-lead.log" "$logs/duel-follow.log"; then
        say_bad "у журналах клієнтів є помилки:"
        grep -h -m3 'ERROR' "$logs/duel-lead.log" "$logs/duel-follow.log" \
            | sed 's/^/      /'
    fi
}

# ── пам'ять не росте ──────────────────────────────────────────────────
#
# Найдорожча вада проєкту була саме така: вічний цикл у показі набирав по
# 700 МіБ за секунду, і OOM-килер клав увесь робочий стіл. Ні лінтер, ні
# проби, ні «сервер відповідає» цього не бачили — тому окремий крок.
run_memory() {
    head_of "Пам'ять не росте"
    stop_server
    start_server "$logs/server-memory.log" --полігон \
        || { say_bad "сервер не піднявся"; return; }
    godot --headless --path game -- --демо "$test_world" \
        > "$logs/memory.log" 2>&1 &
    local player=$!
    own_client=$player
    local grew=0
    local first=0
    local last=0
    for step in $(seq 1 12); do
        sleep 5
        last=$(awk '/VmRSS/{print int($2/1024)}' "/proc/$player/status" \
            2>/dev/null || echo 0)
        [ "$step" -eq 2 ] && first="$last"
        # 2 ГіБ — стеля, за якою вже нема чого міряти: зупиняємо одразу,
        # щоб перевірка не поклала машину, як це вже сталось.
        if [ "${last:-0}" -gt 2000 ]; then
            grew=1
            break
        fi
    done
    kill "$player" 2>/dev/null
    wait "$player" 2>/dev/null
    own_client=""
    local srv_rss
    srv_rss=$(awk '/VmRSS/{print int($2/1024)}' "/proc/$(server_pid)/status" \
        2>/dev/null || echo 0)
    printf '    клієнт: %s → %s МіБ за хвилину · сервер: %s МіБ\n' \
        "$first" "$last" "$srv_rss"
    if [ "$grew" -eq 1 ]; then
        say_bad "клієнт перевалив 2 ГіБ — щось накопичується"
    elif [ "${first:-0}" -gt 0 ] && [ "$last" -gt $((first * 2)) ]; then
        say_bad "клієнт подвоївся за хвилину ($first → $last МіБ)"
    else
        say_ok "клієнт тримається ($first → $last МіБ)"
    fi
}

# Не лізти в чужу гру.
#
# Перевірка піднімає власний сервер на тому самому порту й ганяє клієнтів.
# Якби вона зупиняла чужий сервер, то вбивала б сеанс того, хто саме грає,
# — а вона ганяється й тоді, коли поруч грають.
if [ -n "$(server_pid)" ]; then
    echo "‼ на порту $port уже працює сервер (номер $(server_pid))." >&2
    echo "  Перевірка піднімає свій і чужого не чіпає." >&2
    echo "  Зупини гру: ./play.sh --stop — і повтори." >&2
    exit 2
fi

mode="${1:-}"

# Вікно гри — лише в оренді gpu-broker (26.11.2026).
#
# Клієнт із вікном рендерить через Vulkan на NVIDIA, і змінні Mesa
# (LIBGL_ALWAYS_SOFTWARE тощо) його не переводять на процесор — вони діють
# лише на OpenGL. Повний прогін 26.11.2026 о 18:10 узяв відеопам'ять повз
# диспетчер, і прогін аркушів у ComfyUI впав з «out of memory». Тому режими
# з вікном (усе, --обмін, --арена) перезапускають себе через `gpu run`:
# диспетчер пустить, коли на карті справді є місце, а доти тримає в черзі.
# Без вікна (--швидко, --лінт; так ганяє гачок коміту) — одразу, карта не
# потрібна. Межа 4000 МіБ — на два клієнти світу 2, з запасом; не заміряно.
case "$mode" in
    --лінт|--швидко) ;;
    *)
        if [ -z "${CHECK_IN_GPU_LEASE:-}" ]; then
            if ! command -v gpu > /dev/null; then
                echo "‼ режим з вікном бере відеокарту, а gpu-broker (команда gpu) не знайдено." >&2
                echo "  Без вікна: ./check.sh --швидко" >&2
                exit 2
            fi
            echo "вікно гри бере відеокарту — стаю в чергу gpu-broker (gpu status — хто тримає)."
            echo "Не чекати: Ctrl+C і ./check.sh --швидко (без вікна)."
            exec gpu run --мб 4000 --мета "гра-lineage check.sh ${mode:-повний} (вікно)" \
                -- env CHECK_IN_GPU_LEASE=1 "$0" "$@"
        fi
        ;;
esac

case "$mode" in
    --лінт)
        run_lint
        ;;
    --обмін)
        run_trade
        ;;
    --арена)
        run_duel
        ;;
    --швидко)
        run_lint
        run_server
        run_page
        ;;
    *)
        run_lint
        run_server
        run_page
        run_screen
        run_fight
        run_shop
        run_trade
        run_duel
        run_memory
        ;;
esac

stop_server
printf '\n────────────────────────────────────────────\n'
printf 'пройдено %d · провалено %d · пропущено %d\n' \
    "$passed" "$failed" "$skipped"
[ "$failed" -eq 0 ] || printf 'журнали: %s/\n' "$logs"
exit $([ "$failed" -eq 0 ] && echo 0 || echo 1)
