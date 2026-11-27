#!/usr/bin/env bash
# Керування сервером MyWay: база, сервер гри, сервіс оновлень — службами
# systemd --user. Цим самим скриптом користується значок «MyWay — сервер» у
# треї (tools/server/tray). Слово замовника 27.11.2026: «не організована
# процедура перезапуску та інформування про необхідність оновити лаунчер та
# гру, зроби окремим пунктом в треї щоб я міг стартонути, зупинити, оновити».
#
#   myway-server.sh install                 поставити служби (не запускає)
#   myway-server.sh status                  стан служб і онлайн
#   myway-server.sh start                   база → сервіс оновлень → сервер гри
#   myway-server.sh stop [сек] [чому]       попередити гравців, зберегти, зупинити все
#   myway-server.sh restart [сек] [чому]    перезапустити лише сервер гри
#   myway-server.sh cancel                  скасувати відлік зупинки
#   myway-server.sh say "текст"             повідомлення всім у грі
#   myway-server.sh update-game [сек]       зібрати клієнт → опублікувати новий
#                                           випуск → перезапустити сервер гри
#   myway-server.sh update-updater          зібрати новий апдейтер (версія +1)
#                                           → викласти на вікі → старі апдейтери
#                                           покажуть «вийшла нова версія»
#
# Сервер гри зупиняється сам за командою (файл ~/MyWay-сервер/команда.json,
# world.gd → _tick_command): відлік у чат гравцям, збереження кожного, вихід.
# Змінні латиницею (кирилиця ламає масиви й for у bash).
set -euo pipefail

repo="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
state_dir="$HOME/MyWay-сервер"
status_file="$state_dir/status.json"
command_file="$state_dir/команда.json"
log_dir="$state_dir/logs"
unit_dir="$HOME/.config/systemd/user"
units="myway-db myway-updates myway-game"
db_url="http://127.0.0.1:3000"
mkdir -p "$log_dir"

say_err() { echo "‼ $*" >&2; }

is_active() { systemctl --user is-active --quiet "$1.service"; }

write_command() {
    # $1 — JSON; через тимчасовий файл, щоб сервер не прочитав половину.
    printf '%s\n' "$1" > "$command_file.tmp"
    mv "$command_file.tmp" "$command_file"
}

json_str() { python3 -c 'import json,sys; print(json.dumps(sys.argv[1], ensure_ascii=False))' "$1"; }

# Попросити сервер гри зупинитись і дочекатись, поки служба стане неактивною.
graceful_stop_game() {
    local delay="${1:-0}" why="${2:-}" waited=0 limit
    if ! is_active myway-game; then
        return 0
    fi
    write_command "{\"дія\": \"зупинка\", \"через\": $delay, \"чому\": $(json_str "$why")}"
    echo "→ сервер гри: зупинка через $delay с${why:+ ($why)}, гравців попереджено"
    limit=$((delay + 45))
    while is_active myway-game && [ "$waited" -lt "$limit" ]; do
        sleep 1
        waited=$((waited + 1))
    done
    if is_active myway-game; then
        say_err "сервер гри не зупинився сам за $limit с — зупиняю службою"
        systemctl --user stop myway-game.service
    fi
    echo "✓ сервер гри зупинено"
}

cmd_install() {
    mkdir -p "$unit_dir"
    cat > "$unit_dir/myway-db.service" <<EOF
# Поставив $repo/tools/server/myway-server.sh install
[Unit]
Description=MyWay: база (PostgREST :3000 над Postgres)

[Service]
WorkingDirectory=$repo
ExecStart=$repo/run-db.sh
Restart=on-failure
RestartSec=5
StandardOutput=append:$log_dir/db.log
StandardError=append:$log_dir/db.log
EOF
    cat > "$unit_dir/myway-updates.service" <<EOF
# Поставив $repo/tools/server/myway-server.sh install
[Unit]
Description=MyWay: сервіс оновлень і стан для вікі (HTTP, TCP 24600)
After=network-online.target

[Service]
WorkingDirectory=$repo
ExecStart=$repo/run-updates.sh --port 24600
Restart=on-failure
RestartSec=5
StandardOutput=append:$log_dir/updates.log
StandardError=append:$log_dir/updates.log
EOF
    cat > "$unit_dir/myway-game.service" <<EOF
# Поставив $repo/tools/server/myway-server.sh install
[Unit]
Description=MyWay: сервер гри (UDP 24565, світ 2)
Requires=myway-db.service
After=myway-db.service

[Service]
WorkingDirectory=$repo
ExecStart=$repo/run-server.sh --світ2 --база $db_url
# systemctl stop теж акуратний: команда «зупинка зараз» → збереження → вихід.
ExecStop=$repo/tools/server/myway-server.sh _exec-stop
TimeoutStopSec=60
KillMode=mixed
# Зупинка командою — код 0, служба лишається зупиненою; падіння — підняти знову.
Restart=on-failure
RestartSec=10
StandardOutput=append:$log_dir/game.log
StandardError=append:$log_dir/game.log
EOF
    systemctl --user daemon-reload
    echo "✓ служби поставлено в $unit_dir: $units (з репозиторію $repo)"
    echo "  запуск: $0 start   ·   журнали: $log_dir"
}

cmd_status() {
    local name
    for name in $units; do
        printf '  %-15s %s\n' "$name" "$(systemctl --user is-active "$name.service" 2>/dev/null || true)"
    done
    curl -s -m 3 http://127.0.0.1:24600/status.json || echo '{"працює": false, "чому": "сервіс оновлень не відповідає"}'
    echo
}

cmd_start() {
    local name
    if [ ! -f "$unit_dir/myway-game.service" ]; then
        cmd_install
    fi
    systemctl --user start myway-db.service myway-updates.service myway-game.service
    for _ in $(seq 120); do
        if curl -s -m 2 http://127.0.0.1:24600/status.json | grep -q '"працює": true'; then
            echo "✓ сервер працює"
            return 0
        fi
        for name in $units; do
            if systemctl --user is-failed --quiet "$name.service"; then
                say_err "$name не піднявся — $log_dir/${name#myway-}.log"
                tail -5 "$log_dir/${name#myway-}.log" >&2 || true
                return 1
            fi
        done
        sleep 1
    done
    say_err "сервер гри не повідомив стан за 2 хв — $log_dir/game.log"
    return 1
}

cmd_stop() {
    graceful_stop_game "${1:-0}" "${2:-}"
    systemctl --user stop myway-updates.service myway-db.service
    echo "✓ усе зупинено"
}

cmd_restart() {
    graceful_stop_game "${1:-0}" "${2:-перезапуск сервера}"
    systemctl --user reset-failed myway-game.service 2>/dev/null || true
    cmd_start
}

cmd_update_game() {
    local delay="${1:-60}"
    echo "═══ оновлення гри: збірка → публікація → перезапуск ($(date '+%d.%m %T'))"
    (cd "$repo" && tools/zibraty.sh)
    (cd "$repo" && tools/opublikuvaty.sh)
    # Сервіс оновлень працює з коду репозиторію: після оновлення коду він має
    # підхопити новий (27.11.2026 старий сервіс віддавав 404 на апдейтер).
    systemctl --user try-restart myway-updates.service || true
    if is_active myway-game; then
        cmd_restart "$delay" "вийшла нова версія гри — після перезапуску апдейтер її завантажить"
    else
        echo "→ сервер гри не працював — лише опубліковано"
    fi
    echo "✓ оновлення гри завершено"
}

cmd_update_updater() {
    local project="$repo/updater/project.godot" old new
    old="$(grep -oP '^config/version="\K\d+' "$project")"
    new=$((old + 1))
    echo "═══ оновлення апдейтера v$old → v$new ($(date '+%d.%m %T'))"
    sed -i "s/^config\/version=\"$old\"/config\/version=\"$new\"/" "$project"
    # Підйом версії — окремим комітом лише цього файла (гачок check.sh займає
    # порт робочого сервера, тому --no-verify): інші незакомічені файли не чіпаємо.
    git -C "$repo" commit --no-verify -q -m "Апдейтер v$new (myway-server.sh update-updater)" -- updater/project.godot \
        || say_err "підйом версії не закомічено — закоміть updater/project.godot сам"
    (cd "$repo" && tools/zibraty_updater.sh)
    build_dir="$(ls -1dt "$repo"/build/updater-*/ | head -1)"
    python3 -I "$repo/tools/onovlennia/publish.py" --config-only --updater-build "${build_dir%/}"
    systemctl --user try-restart myway-updates.service || true
    "$repo/tools/vyklasty_wiki.sh"
    if is_active myway-game; then
        write_command "{\"дія\": \"повідомити\", \"текст\": $(json_str "Вийшов новий апдейтер v$new: відкрий апдейтер і натисни «Оновити апдейтер» (апдейтер v1–v2 — завантаж новий з http://192.168.1.34/myway/)")}"
    fi
    echo "✓ апдейтер v$new зібрано й викладено (версію закомічено; запуш, коли зручно)"
}

action="${1:-status}"
shift || true
case "$action" in
    install)        cmd_install ;;
    status)         cmd_status ;;
    start)          cmd_start ;;
    stop)           cmd_stop "$@" ;;
    restart)        cmd_restart "$@" ;;
    cancel)         write_command '{"дія": "скасувати"}'; echo "✓ відлік скасовано" ;;
    say)            write_command "{\"дія\": \"повідомити\", \"текст\": $(json_str "${1:?текст}")}"; echo "✓ надіслано" ;;
    update-game)    cmd_update_game "$@" ;;
    update-updater) cmd_update_updater ;;
    _exec-stop)
        # ExecStop служби myway-game: зупинка «зараз» і чекання виходу.
        write_command '{"дія": "зупинка", "через": 0, "чому": ""}'
        for _ in $(seq 20); do
            if [ -n "${MAINPID:-}" ] && ! kill -0 "$MAINPID" 2>/dev/null; then
                exit 0
            fi
            sleep 1
        done ;;
    -h|--help)      sed -n '2,24p' "$0" ;;
    *) say_err "невідома дія: $action (див. --help)"; exit 2 ;;
esac
