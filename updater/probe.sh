#!/usr/bin/env bash
# Наскрізна перевірка апдейтера на цьому ПК (Linux), без GPU.
#
#   updater/probe.sh                       найновіша збірка з build/
#   updater/probe.sh --build build/myway-…  названа збірка
#   LAN_IP=192.168.1.48 updater/probe.sh   ще й через LAN-адресу
#
# Що піднімає (усе — на НЕТИПОВИХ портах, 24565 не чіпає) і гасить у кінці:
#   - пробну публікацію в тимчасовій теці (не updates/!) з ігровим портом 24601;
#   - сервіс оновлень на TCP 24600 (HTTP_PORT=…);
#   - PostgREST, якщо 3000 ще ніхто не слухає (свій гасить, чужий лишає);
#   - сервер гри --світ2 на UDP 24601 (GAME_PORT=…) з базою;
#   - тестовий акаунт test-upd-<час> через /rpc/register.
# Далі — godot --headless з updater/probes/e2e.gd: апдейтер качає клієнт у
# тимчасову теку, докачує обірване, міняє один файл, запускає клієнт
# (--headless) з --host, і той заходить на сервер.
#
# Окремо — path traversal і Range у сервісу (curl).
#
# Змінні лише латиницею.
set -euo pipefail
cd "$(dirname "$0")/.."
root="$(pwd)"

build=""
if [ "${1:-}" = "--build" ]; then
    build="$(realpath "$2")"
fi
http_port="${HTTP_PORT:-24600}"
game_port="${GAME_PORT:-24601}"
lan_ip="${LAN_IP:-}"
# На диск, не в /tmp (tmpfs): публікація й клієнт — по 1,6 ГБ.
mkdir -p "$root/build"
work="$(mktemp -d "$root/build/.updater-probe.XXXXXX")"
logs="$root/.logs/updater-probe"
mkdir -p "$logs"
pids=()

cleanup() {
    for one in "${pids[@]}"; do
        kill "$one" 2>/dev/null || true
    done
    sleep 1
    for one in "${pids[@]}"; do
        kill -9 "$one" 2>/dev/null || true
    done
    rm -rf "$work"
}
trap cleanup EXIT INT TERM

busy_tcp() { ss -ltnH "sport = :$1" | grep -q .; }
busy_udp() { ss -lunH "sport = :$1" | grep -q .; }

if busy_tcp "$http_port"; then
    echo "‼ TCP $http_port уже зайнятий — HTTP_PORT=… інший" >&2; exit 1
fi
if busy_udp "$game_port"; then
    echo "‼ UDP $game_port уже зайнятий — GAME_PORT=… інший" >&2; exit 1
fi

echo "── публікація (пробна, $work/updates)"
publish_args=(--updates "$work/updates" --name "MyWay · проба апдейтера"
    --game-port "$game_port")
[ -n "$build" ] && publish_args+=(--build "$build")
python3 -I tools/onovlennia/publish.py "${publish_args[@]}" linux

echo "── сервіс оновлень на TCP $http_port"
python3 -I tools/onovlennia/serve.py --root "$work/updates" --port "$http_port" \
    --status "$work/status.json" > "$logs/serve.log" 2>&1 &
pids+=($!)
base="http://127.0.0.1:$http_port"
for _ in $(seq 50); do
    curl -s -o /dev/null "$base/config.json" && break
    sleep 0.2
done

echo "── path traversal і Range"
failed=0
expect() {
    local want="$1" path="$2" got
    got="$(curl -s --path-as-is -o /dev/null -w '%{http_code}' "$base$path")"
    if [ "$got" = "$want" ]; then echo "  ✓ $path → $got"
    else echo "  ✗ $path → $got (чекав $want)"; failed=$((failed + 1)); fi
}
expect 200 /config.json
expect 200 /manifest/linux.json
expect 404 /files/linux/../../config.json
expect 404 /files/linux/%2e%2e/%2e%2e/config.json
expect 404 /files/linux/..%2f..%2fconfig.json
expect 404 /files/../manifest/linux.json
expect 404 /files/linux/..%5cconfig.json
expect 404 /files/linux//etc/passwd
expect 404 /etc/passwd
expect 404 /manifest/../config.json
got="$(curl -s -X PUT -o /dev/null -w '%{http_code}' "$base/config.json")"
[ "$got" = 405 ] && echo "  ✓ PUT → 405" || { echo "  ✗ PUT → $got"; failed=$((failed + 1)); }
pck="$work/updates/files/linux/MyWay.pck"
curl -s -r 1000-1999 -o "$work/range" "$base/files/linux/MyWay.pck"
if cmp -s "$work/range" <(tail -c +1001 "$pck" | head -c 1000); then
    echo "  ✓ Range 1000-1999 — ті самі байти"
else echo "  ✗ Range"; failed=$((failed + 1)); fi

if ! curl -s --max-time 2 -o /dev/null http://127.0.0.1:3000/; then
    echo "── PostgREST (свій)"
    "$HOME/.local/bin/postgrest" db/postgrest.conf > "$logs/postgrest.log" 2>&1 &
    pids+=($!)
    for _ in $(seq 50); do
        curl -s -o /dev/null http://127.0.0.1:3000/ && break
        sleep 0.2
    done
else
    echo "── PostgREST уже працює — беру його"
fi

stamp="$(date +%s)"
login="test-upd-$stamp"
password="test-upd-parol"
hero="TestUpd${stamp: -5}"
reply="$(curl -s -X POST -H 'Content-Type: application/json' \
    -d "{\"login\":\"$login\",\"password\":\"$password\"}" \
    http://127.0.0.1:3000/rpc/register)"
echo "── акаунт $login: $reply"

echo "── сервер гри на UDP $game_port (світ 2, з базою)"
server_log="$logs/server.log"
# До старту сервера /status.json має чесно казати «не працює».
if curl -s "$base/status.json" | grep -q '"працює": false'; then
    echo "  ✓ /status.json без сервера гри — «не працює»"
else echo "  ✗ /status.json без сервера"; failed=$((failed + 1)); fi
godot --headless --path "$root/game" -- --server --світ2 --порт "$game_port" \
    --база http://127.0.0.1:3000 --статус "$work/status.json" > "$server_log" 2>&1 &
pids+=($!)
for _ in $(seq 300); do
    grep -q 'сервер чекає гравців' "$server_log" && break
    sleep 1
done
grep -q 'сервер чекає гравців' "$server_log" || {
    echo "‼ сервер не піднявся — $server_log" >&2; exit 1; }

# Зміна одного файла в публікації: versiia.json, і перерахунок маніфесту.
change="$work/change.sh"
cat > "$change" <<EOF
set -e
printf '{"коміт": "змінено-пробою", "дата": "$stamp"}\n' > "$work/updates/files/linux/versiia.json"
python3 -I "$root/tools/onovlennia/publish.py" --updates "$work/updates" --manifest-only linux >&2
echo versiia.json
EOF

# Псування: файл у публікації інший (того самого розміру), а маніфест
# старий — хеш не зійдеться.
spoil="$work/spoil.sh"
target="$work/updates/files/linux/versiia.json"
printf 'head -c "$(stat -c %%s "%s")" /dev/zero | tr "\\000" x > "%s.tmp"\nmv "%s.tmp" "%s"\n' \
    "$target" "$target" "$target" "$target" > "$spoil"

sleep 1
if curl -s "$base/status.json" | grep -q '"працює": true'; then
    echo "  ✓ /status.json — сервер гри працює"
else echo "  ✗ /status.json після старту сервера"; failed=$((failed + 1)); fi
# Поки апдейтер грає, у фоні стежимо за онлайном: найбільше «гравців».
# Сам файл, а не HTTP: клієнт проби заходить і виходить за частки секунди,
# а сервер переписує стан саме при вході/виході (HTTP-шлях перевірено вище).
( while :; do cat "$work/status.json" 2>/dev/null; echo; sleep 0.05; done ) \
    > "$logs/status-poll.log" 2>/dev/null &
pids+=($!)

echo "── апдейтер (godot --headless, проба e2e)"
probe_args=(--робоча "$work" --стара-тека "$work/немає" --адреса "127.0.0.1:$http_port"
    --мертвий "127.0.0.1:24609" --порт-гри "$game_port" --обрив-мб 300
    --зміна "$change" --псування "$spoil" --журнал-сервера "$server_log"
    --клієнту-рушій "--headless"
    --клієнту "--акаунт $login --пароль $password --персонаж $hero")
[ -n "$lan_ip" ] && probe_args+=(--lan "$lan_ip:$http_port")
code=0
godot --headless --path "$root/updater" res://scenes/e2e.tscn -- \
    "${probe_args[@]}" 2>&1 | tee "$logs/e2e.log" | grep -avE '^\s*$' \
    | grep -aE '^\s*[✓✗—]|проба|апдейтер|‼' || true
grep -aq 'проба апдейтера: ПРОЙДЕНО' "$logs/e2e.log" || code=1
echo
echo "── що бачив сервіс оновлень (206 — докачування):"
grep -E 'MyWay.pck|versiia' "$logs/serve.log" | sed 's/^/  /' | tail -8
most="$(grep -o '"гравців": [0-9]*' "$logs/status-poll.log" | grep -o '[0-9]*$' | sort -n | tail -1)"
if [ "${most:-0}" -ge 1 ]; then
    echo "  ✓ онлайн у /status.json під час гри: $most ($(grep -o "\"ім'я\": \"[^\"]*\"" "$logs/status-poll.log" | sort -u | head -3 | tr '\n' ' '))"
else echo "  ✗ онлайн у /status.json так і не з'явився"; failed=$((failed + 1)); fi
echo "── сервер гри:"
grep -E '\[акаунт\]|\[світ\] приєднався' "$server_log" | sed 's/^/  /'
[ $failed -gt 0 ] && code=1
echo
echo "журнали: $logs"
[ $code -eq 0 ] && echo "ПРОЙДЕНО" || echo "НЕ ПРОЙДЕНО"
exit $code
