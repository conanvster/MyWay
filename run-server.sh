#!/usr/bin/env bash
# Ігровий сервер: той самий Godot без вікна.
#
#   ./run-server.sh                         без бази
#   ./run-server.sh --база http://…:3000    із базою
#
# Другий сервер не піднімається: він однаково не зможе взяти порт 24565,
# зате з'їсть пам'ять. Один сервер будує рельєф, 70 дерев і три десятки
# монстрів — це під гігабайт; кілька забутих таких з'їли всю пам'ять
# 02.09.2026, аж до свопу.
set -euo pipefail
cd "$(dirname "$0")"

if pgrep -f "godot --headless --path .*game -- --server" > /dev/null; then
    echo "‼ сервер уже працює. Зупинити: ./play.sh --stop" >&2
    exit 1
fi

exec godot --headless --path "$(pwd)/game" -- --server "$@"
