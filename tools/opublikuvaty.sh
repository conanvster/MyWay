#!/usr/bin/env bash
# Публікація зібраного клієнта для апдейтера (після tools/zibraty.sh).
#
#   tools/opublikuvaty.sh                       найновіша збірка з build/, усі її платформи
#   tools/opublikuvaty.sh linux                 лише названі платформи
#   tools/opublikuvaty.sh --build build/myway-2026-11-26-cc57450 --name "MyWay · дім"
#   tools/opublikuvaty.sh --game-port 24601     ігровий порт, який апдейтер дасть клієнтові
#   tools/opublikuvaty.sh --min-release 3       пускати грати клієнти з випуску 3 і новіші
#   tools/opublikuvaty.sh --root ~/інша/тека    інший корінь (типово ~/MyWay-сервер/updates)
#   tools/opublikuvaty.sh --manifest-only linux перерахувати маніфест після ручної заміни файла
#
# Корінь — тека, з якої сервер роздає збірки (./run-updates.sh). Поза
# репозиторієм, бо worktree зникає після злиття. Гравці ставлять гру не
# сюди, а в теку, яку обирають в апдейтері.
#
# Кладе: <корінь>/files/<платформа>/…, manifest/<платформа>.json, config.json.
# Подробиці — tools/onovlennia/publish.py і spec/апдейтер.md.
#
# Змінні лише латиницею.
set -euo pipefail
cd "$(dirname "$0")/.."
root_dir="${UPDATES_DIR:-$HOME/MyWay-сервер/updates}"
rest=()
while [ $# -gt 0 ]; do
    case "$1" in
        --root|--updates) root_dir="$2"; shift 2 ;;
        *) rest+=("$1"); shift ;;
    esac
done
echo "→ тека, з якої сервер роздає збірки: $root_dir"
mkdir -p "$root_dir"
exec python3 -I tools/onovlennia/publish.py --updates "$root_dir" "${rest[@]}"
