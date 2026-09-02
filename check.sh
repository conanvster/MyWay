#!/usr/bin/env bash
# Перевірка перед комітом: чи компілюється код, чи підіймається сервер,
# чи відповідає він клієнтові, чи не бреше стартова сторінка.
#
#   ./check.sh              усе, разом із вікном і боєм (близько 2 хвилин)
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
    setsid nohup godot --headless --path game -- --server "$@" \
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

    timeout 25 godot --headless --path game -- --демо \
        > "$logs/client.log" 2>&1
    if grep -q 'приєднався' "$logs/server.log"; then
        say_ok "сервер завів персонажа: $(grep -o 'приєднався.*' \
            "$logs/server.log" | head -1)"
    else
        say_bad "сервер не побачив клієнта — $logs/server.log"
    fi
    # Рядок, який клієнт може надрукувати ЛИШЕ з відповіді сервера:
    # про святиню йому каже сервер, коли персонаж уже у світі.
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
    timeout 30 ./run.sh --демо > "$logs/screen-client.log" 2>&1
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
    godot --headless --path game -- --демо > "$logs/fight.log" 2>&1 &
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
    godot --headless --path game -- --демо > "$logs/memory.log" 2>&1 &
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
case "$mode" in
    --лінт)
        run_lint
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
        run_memory
        ;;
esac

stop_server
printf '\n────────────────────────────────────────────\n'
printf 'пройдено %d · провалено %d · пропущено %d\n' \
    "$passed" "$failed" "$skipped"
[ "$failed" -eq 0 ] || printf 'журнали: %s/\n' "$logs"
exit $([ "$failed" -eq 0 ] && echo 0 || echo 1)
