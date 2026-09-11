#!/usr/bin/env bash
# Запустити гру: оновитись, переімпортувати, відкрити стартову сторінку.
#
#   ./play.sh                оновитись і відкрити гру
#   ./play.sh --no-update    без оновлення з git
#   ./play.sh --світ2       те саме у світі версії 2 (і сервер у ньому)
#   ./play.sh --stop         зупинити сервер і базу
#
# Сервер і базу ПІДІЙМАЄ САМА СТОРІНКА, і кнопка «Зайти в гру» не
# працює, доки сервер не відповів. Це навмисно: коли все підіймалося
# одним скриптом, клієнт стукав до сервера, поки той ще читав дані,
# сервер стукав до бази, поки та ще не відповідала, — і в журналі
# лишалося тільки «код 0», з якого не видно, хто саме не встиг.

set -uo pipefail
cd "$(dirname "$0")"
mkdir -p .logs

# Скільки вікон гри вже відкрито. Кожне тримає всі моделі, тож на трьох
# забутих вікнах машина починає свопитись — перевірено 02.09.2026.
open_now=$(pgrep -cf "godot --path .*game" || true)
if [ "${open_now:-0}" -ge 2 ] && [ "${1:-}" != "--stop" ]; then
    echo "‼ уже відкрито $open_now вікон гри." >&2
    echo "  Закрий зайві або зупини все: ./play.sh --stop" >&2
    exit 1
fi

if [ "${1:-}" = "--stop" ]; then
    # Своїх предків не вбиваємо. `pkill -f "godot --headless"` збігається
    # й з оболонкою, у чиєму РЯДКУ КОМАНДИ є цей текст, — тобто з тією,
    # що зараз викликала цей скрипт. Так двічі обривався власний прогін
    # (02.09.2026, і ще двічі 03.09.2026, поки це не полагодили).
    ancestors=" $$ "
    walk=$$
    while [ "$walk" -gt 1 ] && [ -r "/proc/$walk/stat" ]; do
        walk=$(awk '{print $4}' "/proc/$walk/stat" 2>/dev/null || echo 1)
        ancestors="$ancestors$walk "
    done
    # Шукаємо за "--headless --path", а не за "godot --headless":
    # перевірка запускає сервер повним шляхом до двійника
    # (Godot_v4.7.2-stable_linux.x86_64), і слова "godot" у її рядку
    # команди немає взагалі. Такий сервер лишався жити після --stop і їв
    # пам'ять далі — знайдено 03.09.2026.
    for name in "\-\-headless \-\-path" "postgrest"; do
        label="сервер гри"
        [ "$name" = "postgrest" ] && label="база"
        killed=0
        for victim in $(pgrep -f "$name" 2>/dev/null || true); do
            case "$ancestors" in
                *" $victim "*) continue ;;
            esac
            kill "$victim" 2>/dev/null && killed=$((killed + 1))
        done
        [ "$killed" -gt 0 ] && echo "зупинено: $label ($killed)"
    done
    # Мітка «світ збудовано», яку кладе сервер: убитий на місці, він її
    # прибрати не встигає. Стартова сторінка вірить мітці лише при
    # зайнятому порті, тож це прибирання не для неї, а для чистоти диска.
    rm -f "$HOME/.local/share/godot/app_userdata/гра-lineage/сервер.json"
    exit 0
fi

if [ "${1:-}" != "--no-update" ] && [ -d .git ] && git remote | grep -q .; then
    echo "→ оновлююсь із git"
    git pull --ff-only 2>&1 | tail -2 || echo "  (не вийшло — граю на тому, що є)"
fi

newest=$(find game -name "*.gd" -newer game/.godot/uid_cache.bin 2>/dev/null | head -1)
if [ ! -d game/.godot ] || [ -n "$newest" ]; then
    echo "→ переімпортовую проєкт"
    godot --headless --path game --import > .logs/import.log 2>&1
fi

# Світ версії 2: стартова сторінка підніме й сервер у ньому ж.
if [ "${1:-}" = "--світ2" ]; then
    exec ./run.sh --світ2
fi
exec ./run.sh --run
