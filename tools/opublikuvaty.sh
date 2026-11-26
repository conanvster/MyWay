#!/usr/bin/env bash
# Публікація зібраного клієнта для апдейтера (після tools/zibraty.sh).
#
#   tools/opublikuvaty.sh                       найновіша збірка з build/, усі її платформи
#   tools/opublikuvaty.sh linux                 лише названі платформи
#   tools/opublikuvaty.sh --build build/myway-2026-11-26-cc57450 --name "MyWay · дім"
#   tools/opublikuvaty.sh --game-port 24601     ігровий порт, який апдейтер дасть клієнтові
#   tools/opublikuvaty.sh --min-release 3       пускати грати клієнти з випуску 3 і новіші
#   UPDATES_DIR=~/myway-updates tools/opublikuvaty.sh   інший каталог (типово updates/, поза git)
#   tools/opublikuvaty.sh --manifest-only linux перерахувати маніфест після ручної заміни файла
#
# Кладе: <каталог>/files/<платформа>/…, manifest/<платформа>.json, config.json.
# Роздає їх ./run-updates.sh. Подробиці — tools/onovlennia/publish.py і
# spec/апдейтер.md.
#
# Змінні лише латиницею.
set -euo pipefail
cd "$(dirname "$0")/.."
updates_dir="${UPDATES_DIR:-$(pwd)/updates}"
exec python3 -I tools/onovlennia/publish.py --updates "$updates_dir" "$@"
