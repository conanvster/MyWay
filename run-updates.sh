#!/usr/bin/env bash
# Сервіс оновлень для апдейтера: HTTP (TCP), лише читання.
#
#   ./run-updates.sh                   порт 24600, каталог updates/
#   ./run-updates.sh --port 24610      інший порт
#   UPDATES_DIR=~/myway-updates ./run-updates.sh
#
# Наповнює каталог tools/opublikuvaty.sh. Слухає на всіх адресах машини
# (--bind 0.0.0.0) — та сама IP, що й у сервера гри, окремий TCP-порт.
# Назовні треба відкрити TCP 24600 (і UDP 24565 для самої гри).
#
# Змінні лише латиницею.
set -euo pipefail
cd "$(dirname "$0")"
updates_dir="${UPDATES_DIR:-$(pwd)/updates}"
exec python3 -I tools/onovlennia/serve.py --root "$updates_dir" "$@"
