#!/usr/bin/env bash
# Клієнт MyWay для гравців: macOS (Universal), Linux x86_64, Windows x86_64.
#
#   tools/zibraty.sh                  усі платформи, для яких є шаблони
#   tools/zibraty.sh macos linux      лише названі
#   OUT_DIR=~/збірки tools/zibraty.sh інша тека для збірок (типово build/, поза git)
#   TEMPLATES_DIR=<тека> tools/zibraty.sh   шаблони не з
#                     ~/.local/share/godot/export_templates/<версія>/, а з цієї теки
#
# Що виходить: build/myway-<дата>-<коміт>/
#   macos/MyWay.app             (рушій у Contents/MacOS, дані — окремий
#                                Contents/Resources/MyWay.pck)
#   linux/MyWay.x86_64 + MyWay.pck
#   windows/MyWay.exe  + MyWay.pck
#   versiia.json                коміт і дата — те саме, що клієнт показує
#   MyWay-<платформа>-<дата>-<коміт>.zip   архів кожної, для гравця
# Рушій і дані окремо (pck не вбудовано) — щоб апдейтер перекачував лише
# те, що змінилось.
#
# Godot тут лише ГОЛОВОЮ (--headless): відеокарта не потрібна й не
# береться — на ній можуть іти довгі прогони (ComfyUI).
# Інтернету скрипт не чіпає: шаблону немає — каже, звідки взяти, і йде далі.
#
# Змінні лише латиницею: кирилична назва тихо ламає масиви й `for`.
set -euo pipefail
cd "$(dirname "$0")/.."
root="$(pwd)"

platforms=("$@")
[ ${#platforms[@]} -eq 0 ] && platforms=(macos linux windows)

full_version="$(godot --headless --version 2>/dev/null | tail -1)"
# «4.7.2.stable.official.ed1daf0bf» → «4.7.2.stable»: так зветься тека шаблонів.
version="$(printf '%s' "$full_version" | sed -E 's/\.(official|custom_build|mono|[a-z_]+build).*$//')"
tag="$(printf '%s' "$version" | sed -E 's/\.([a-z]+[0-9]*)$/-\1/')"
templates_root="$HOME/.local/share/godot/export_templates"
templates="${TEMPLATES_DIR:-$templates_root/$version}"

commit="$(git rev-parse --short HEAD 2>/dev/null || echo bez-git)"
dirty=""
git diff --quiet HEAD -- game 2>/dev/null || dirty="+зміни"
stamp="$(date +%Y-%m-%d)"
out_root="${OUT_DIR:-$root/build}"
out="$out_root/myway-$stamp-$commit$dirty"
work="$(mktemp -d)"
version_file="$root/game/versiia.json"
cleanup() {
    rm -rf "$work"
    rm -f "$version_file"
}
trap cleanup EXIT

echo "→ godot $full_version, шаблони: $templates"

# Шаблони з іншої теки: Godot шукає їх лише в
# $XDG_DATA_HOME/godot/export_templates/<версія>, тож даємо йому тимчасовий
# XDG_DATA_HOME з посиланням. Справжній ~/.local/share не чіпаємо.
godot_env=()
if [ -n "${TEMPLATES_DIR:-}" ]; then
    mkdir -p "$work/xdg/godot/export_templates"
    ln -s "$(realpath "$TEMPLATES_DIR")" "$work/xdg/godot/export_templates/$version"
    godot_env=(env "XDG_DATA_HOME=$work/xdg")
fi

# Версію — у файл, який гра читає (`Net.build_version`); у git його немає.
printf '{"коміт": "%s%s", "дата": "%s"}\n' "$commit" "$dirty" "$stamp" > "$version_file"

template_of() {
    case "$1" in
        macos)   echo "$templates/macos.zip" ;;
        linux)   echo "$templates/linux_release.x86_64" ;;
        windows) echo "$templates/windows_release_x86_64.exe" ;;
    esac
}
preset_of() {
    case "$1" in
        macos) echo "macOS" ;; linux) echo "Linux" ;; windows) echo "Windows" ;;
    esac
}

built=()
missing=()
failed=()

# Архітектури Mach-O — з fat-заголовка: lipo на Linux зазвичай немає.
mach_archs() {
    if command -v lipo > /dev/null; then
        lipo -archs "$1"
        return
    fi
    python3 -I - "$1" <<'PY'
import struct, sys
names = {0x01000007: "x86_64", 0x0100000C: "arm64"}
with open(sys.argv[1], "rb") as f:
    head = f.read(8)
    magic, count = struct.unpack(">II", head)
    if magic != 0xCAFEBABE:
        print("тонкий файл, не universal (magic %#x)" % struct.unpack("<I", head[:4])[0])
        sys.exit(0)
    found = []
    for _ in range(count):
        cpu = struct.unpack(">iiIII", f.read(20))[0] & 0xFFFFFFFF
        found.append(names.get(cpu, hex(cpu)))
    print(" ".join(found))
PY
}

export_one() {
    local name="$1"
    local preset
    preset="$(preset_of "$name")"
    local template
    template="$(template_of "$name")"
    if [ -z "$preset" ]; then
        echo "‼ невідома платформа «$name» (є: macos linux windows)" >&2
        failed+=("$name")
        return
    fi
    echo
    echo "── $preset"
    if [ ! -f "$template" ]; then
        echo "  ∅ немає шаблону: $template"
        missing+=("$name")
        return
    fi
    if [ "$name" = "macos" ] && ! unzip -tq "$template" > /dev/null 2>&1; then
        echo "  ‼ шаблон пошкоджений (unzip -t не проходить): $template"
        missing+=("$name")
        return
    fi
    local dest="$out/$name"
    rm -rf "$dest"
    mkdir -p "$dest"
    local log="$out/$name.log"
    local target
    case "$name" in
        macos)   target="$work/MyWay-macos.zip" ;;
        linux)   target="$dest/MyWay.x86_64" ;;
        windows) target="$dest/MyWay.exe" ;;
    esac
    if ! "${godot_env[@]}" godot --headless --path "$root/game" \
            --export-release "$preset" "$target" > "$log" 2>&1 \
            || [ ! -s "$target" ]; then
        echo "  ‼ експорт не вдався — $log:"
        sed 's/\x1b\[[0-9;]*m//g' "$log" | grep -E 'ERROR|‼' | head -10 | sed 's/^/    /'
        failed+=("$name")
        return
    fi

    # ── перевірка: рушій і окремий .pck ──
    local binary pck
    if [ "$name" = "macos" ]; then
        unzip -q "$target" -d "$dest"
        local app
        app="$(find "$dest" -maxdepth 1 -name '*.app' -type d | head -1)"
        if [ -z "$app" ]; then
            echo "  ‼ у zip немає .app"; failed+=("$name"); return
        fi
        local plist="$app/Contents/Info.plist"
        local exe_name bundle_id
        exe_name="$(grep -A1 '<key>CFBundleExecutable</key>' "$plist" | tail -1 \
            | sed -E 's/.*<string>(.*)<\/string>.*/\1/')"
        bundle_id="$(grep -A1 '<key>CFBundleIdentifier</key>' "$plist" | tail -1 \
            | sed -E 's/.*<string>(.*)<\/string>.*/\1/')"
        binary="$app/Contents/MacOS/$exe_name"
        pck="$(find "$app/Contents/Resources" -maxdepth 1 -name '*.pck' | head -1)"
        local archs
        archs="$(mach_archs "$binary")"
        case "$archs" in
            *x86_64*arm64*|*arm64*x86_64*) ;;
            *) echo "  ‼ не обидві архітектури: $archs"; failed+=("$name"); return ;;
        esac
        echo "  $(basename "$app"): $bundle_id, архітектури: $archs"
    else
        binary="$target"
        pck="$dest/MyWay.pck"
        echo "  $(file -b "$binary" | cut -c1-70)"
    fi
    if [ ! -f "$binary" ] || [ -z "$pck" ] || [ ! -f "$pck" ]; then
        echo "  ‼ немає рушія ($binary) або окремого .pck"; failed+=("$name"); return
    fi
    echo "  рушій $(du -h "$binary" | cut -f1), дані .pck $(du -h "$pck" | cut -f1)"
    local errors
    errors="$(sed 's/\x1b\[[0-9;]*m//g' "$log" | grep -c '^ERROR' || true)"
    [ "$errors" -gt 0 ] && echo "  (у журналі ERROR: $errors — перевір $log)"

    # Архів для гравця. `-y` береже символьні посилання в бандлі Mac.
    local archive="$out/MyWay-$name-$stamp-$commit$dirty.zip"
    (cd "$dest" && zip -qry "$archive" .)
    echo "  ✓ $archive ($(du -h "$archive" | cut -f1))"
    built+=("$name")
}

mkdir -p "$out"
cp "$version_file" "$out/versiia.json"
for one in "${platforms[@]}"; do
    export_one "$one"
done

echo
echo "────────────────────────────────────────────"
echo "зібрано: ${built[*]:-нічого} · без шаблону: ${missing[*]:-—} · провалено: ${failed[*]:-—}"
echo "тека: $out"
if [ ${#missing[@]} -gt 0 ]; then
    echo
    echo "Шаблонів бракує. Завантаж (скрипт сам в інтернет не ходить):"
    echo "  https://github.com/godotengine/godot/releases/download/$tag/Godot_v${tag}_export_templates.tpz"
    echo ".tpz — це zip із текою templates/. Розпакувати й перейменувати теку на версію:"
    echo "  cd $templates_root && unzip Godot_v${tag}_export_templates.tpz && mv templates $version"
fi
[ ${#failed[@]} -eq 0 ] && [ ${#built[@]} -gt 0 ]
