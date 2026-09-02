#!/usr/bin/env bash
# Запустити гру: оновитись, переімпортувати, відкрити стартову сторінку.
#
#   ./play.sh                оновитись і відкрити гру
#   ./play.sh --no-update    без оновлення з git
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

if [ "${1:-}" = "--stop" ]; then
    for name in "godot --headless" "postgrest"; do
        pkill -f "$name" 2>/dev/null && echo "зупинено: $name"
    done
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

exec ./run.sh --run
