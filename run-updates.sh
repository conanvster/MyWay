#!/usr/bin/env bash
# Сервіс оновлень для апдейтера: HTTP (TCP), лише читання.
#
#   ./run-updates.sh                         порт 24600, корінь ~/MyWay-сервер/updates
#   ./run-updates.sh --port 24610            інший порт
#   ./run-updates.sh --root ~/інша/тека      інший корінь публікації
#   UPDATES_DIR=~/інша/тека ./run-updates.sh те саме змінною
#
# Корінь — тека, з якої СЕРВЕР РОЗДАЄ збірки (її наповнює tools/opublikuvaty.sh).
# Гравці гру туди не ставлять: апдейтер ставить її в теку, яку гравець
# обирає на своєму комп'ютері («Куди встановити гру»).
# Корінь навмисно поза репозиторієм: worktree зникає після злиття.
#
# Слухає на всіх адресах машини — та сама IP, що й у сервера гри, окремий
# TCP-порт. Назовні треба відкрити TCP 24600 (і UDP 24565 для самої гри).
#
# Змінні лише латиницею.
set -euo pipefail
cd "$(dirname "$0")"
root_dir="${UPDATES_DIR:-$HOME/MyWay-сервер/updates}"
port="24600"
rest=()
while [ $# -gt 0 ]; do
    case "$1" in
        --root) root_dir="$2"; shift 2 ;;
        --port) port="$2"; shift 2 ;;
        *) rest+=("$1"); shift ;;
    esac
done

echo "════════════════════════════════════════════════════════════════"
echo " Сервіс оновлень MyWay"
echo "  Тека, з якої сервер РОЗДАЄ збірки гравцям: $root_dir"
echo "  (гравці встановлюють гру у свою теку, обрану в апдейтері)"
echo "  Порт: TCP $port"
# Адреси справжніх мережевих карт: мости Docker (docker0, br-…) і veth гравцям ні до чого.
lan="$(ip -4 -o addr show scope global 2>/dev/null \
    | awk '$2 !~ /^(docker|br-|veth|virbr|lo)/ {split($4, a, "/"); print a[1]}' || true)"
if [ -n "$lan" ]; then
    echo "  Гравцям у полі «IP сервера» вводити:"
    for one in $lan; do
        if [ "$port" = "24600" ]; then echo "      $one"; else echo "      $one:$port"; fi
    done
else
    echo "  ‼ LAN-адреси не знайдено — подивись: ip -4 addr"
fi
echo "════════════════════════════════════════════════════════════════"
if [ ! -f "$root_dir/config.json" ]; then
    echo "‼ у $root_dir ще немає публікації: спершу tools/zibraty.sh і tools/opublikuvaty.sh" >&2
    exit 1
fi
exec python3 -I tools/onovlennia/serve.py --root "$root_dir" --port "$port" "${rest[@]}"
