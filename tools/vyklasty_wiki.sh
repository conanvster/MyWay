#!/usr/bin/env bash
# Викласти вікі MyWay разом з архівами апдейтера на сервер home-hub
# (http://192.168.1.34/myway/, П-291; слово замовника 27.11.2026: «додати
# сторінку для завантаження гри в http://192.168.1.34/ разом з wiki … на
# головній буде додано розділ скачати апдейтер/лоадер»).
#
#   tools/vyklasty_wiki.sh                    вікі + найсвіжіший апдейтер
#   tools/vyklasty_wiki.sh --updater DIR      конкретна збірка build/updater-…
#   tools/vyklasty_wiki.sh --server-ip IP     IP сервера гри для гравців
#                                             (типово — LAN-IP цього ПК)
#   tools/vyklasty_wiki.sh --dry-run          показати, що буде скопійовано
#
# Куди: alex@192.168.1.34:~/myway-site/wiki — цю теку nginx home-hub
# роздає як /myway/ (home-hub: local/nginx.conf, local/docker-compose.yml).
# Вікі не перезбирається: спершу `python3 tools/wiki.py`, якщо дані змінились.
# Змінні латиницею (кирилиця ламає масиви й for у bash).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
host="alex@192.168.1.34"
dest="myway-site/wiki"
updater_dir=""
server_ip=""
dry=""

while [ $# -gt 0 ]; do
    case "$1" in
        --updater)   updater_dir="$2"; shift 2 ;;
        --server-ip) server_ip="$2"; shift 2 ;;
        --host)      host="$2"; shift 2 ;;
        --dry-run)   dry="--dry-run"; shift ;;
        -h|--help)   sed -n '2,17p' "$0"; exit 0 ;;
        *) echo "‼ невідомий аргумент: $1" >&2; exit 2 ;;
    esac
done

# Найсвіжіша збірка апдейтера: у build/ репо або в будь-якому worktree.
if [ -z "$updater_dir" ]; then
    updater_dir="$(ls -1dt "$root"/build/updater-*/ "$root"/.claude/worktrees/*/build/updater-*/ 2>/dev/null | head -1 || true)"
    updater_dir="${updater_dir%/}"
fi
if [ -z "$updater_dir" ] || [ ! -d "$updater_dir" ]; then
    echo "‼ не знайдено збірки апдейтера (build/updater-*). Збери: tools/zibraty_updater.sh" >&2
    exit 1
fi
if [ -z "$server_ip" ]; then
    server_ip="$(ip -4 route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' || true)"
fi
if [ -z "$server_ip" ]; then
    echo "‼ не вдалося визначити LAN-IP; передай --server-ip" >&2
    exit 1
fi

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/zavantazhennia"

version="$(basename "$updater_dir" | sed 's/^updater-//')"
found=0
for os_name in linux macos windows; do
    src="$(ls -1 "$updater_dir"/MyWay-Updater-"$os_name"-*.zip 2>/dev/null | head -1 || true)"
    if [ -z "$src" ]; then
        echo "‼ немає архіву для $os_name у $updater_dir" >&2
        exit 1
    fi
    cp "$src" "$stage/zavantazhennia/MyWay-Updater-$os_name.zip"
    found=$((found + 1))
done

python3 - "$stage/zavantazhennia" "$version" "$server_ip" <<'EOF'
import hashlib, json, os, sys, datetime
d, version, ip = sys.argv[1:4]
# Номер апдейтера (v3…) — той, що опубліковано для самооновлення; без нього
# на сторінці видно лише позначку збірки, і нова версія не впізнається.
number = None
try:
    with open(os.path.expanduser("~/MyWay-сервер/updates/config.json"), encoding="utf-8") as f:
        number = json.load(f).get("updater_version")
except (OSError, ValueError):
    pass
files = []
for name in ("windows", "macos", "linux"):
    p = os.path.join(d, "MyWay-Updater-%s.zip" % name)
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    files.append({"os": name, "file": os.path.basename(p),
                  "size": os.path.getsize(p), "sha256": h.hexdigest()})
info = {"version": version, "number": number, "server": ip,
        "date": datetime.datetime.now().strftime("%d.%m.%Y %H:%M"),
        "files": files}
with open(os.path.join(d, "info.json"), "w", encoding="utf-8") as f:
    json.dump(info, f, ensure_ascii=False, indent=1)
EOF

echo "→ вікі:      $root/wiki"
echo "→ апдейтер:  $updater_dir ($found архіви, версія $version)"
echo "→ сервер гри для гравців: $server_ip"
echo "→ куди:      $host:~/$dest  (http://${host#*@}/myway/)"

ssh -o BatchMode=yes "$host" "mkdir -p ~/$dest"
# Вікі: --delete прибирає застарілі сторінки, але не чіпає zavantazhennia/.
rsync -a --delete $dry --exclude 'zavantazhennia/' "$root/wiki/" "$host:$dest/"
rsync -a --delete $dry "$stage/zavantazhennia/" "$host:$dest/zavantazhennia/"
ssh -o BatchMode=yes "$host" "chmod -R a+rX ~/$dest"

if [ -z "$dry" ]; then
    url="http://${host#*@}/myway/zavantazhennia/info.json"
    # Код 200 нічого не доводить: SPA home-hub на невідомий шлях теж віддає
    # 200 зі своєю index.html. Тому звіряємо вміст — це має бути наш info.json.
    got="$(curl -s -m 10 "$url" || true)"
    if printf '%s' "$got" | grep -q "\"version\": \"$version\""; then
        echo "✓ викладено: http://${host#*@}/myway/"
    else
        echo "‼ файли на сервері, але $url віддає не info.json — nginx home-hub ще не роздає /myway/ (задеплой home-hub)" >&2
        exit 1
    fi
fi
