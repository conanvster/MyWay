#!/usr/bin/env bash
# PostgREST перед Postgres (П-92). Сам Postgres підіймає systemd.
#
#   ./запуск-бази.sh          підняти
#   ./запуск-бази.sh --стан   перевірити, чи відповідає
#
# Схема й ролі ставляться раз: див. база/ЯК-ПІДНЯТИ.md
set -euo pipefail
cd "$(dirname "$0")"

if [ "${1:-}" = "--стан" ]; then
    if curl -s --max-time 2 http://127.0.0.1:3000/characters > /dev/null; then
        echo "→ PostgREST відповідає на 3000"
        psql "postgres://game_api:змінити-мене@127.0.0.1:5432/myway" \
            -c "select name, level, respect, experience from game.characters"
    else
        echo "‼ PostgREST не відповідає — підніми ./запуск-бази.sh" >&2
        exit 1
    fi
    exit 0
fi

if ! systemctl is-active --quiet postgresql; then
    echo "‼ Postgres не запущений: sudo systemctl start postgresql" >&2
    exit 1
fi
exec "$HOME/.local/bin/postgrest" база/postgrest.conf
