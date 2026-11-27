#!/usr/bin/env bash
# Апдейтер MyWay (updater/) для гравців: Linux x86_64, macOS Universal, Windows x86_64.
#
#   tools/zibraty_updater.sh                 усі платформи, для яких є шаблони
#   tools/zibraty_updater.sh linux windows   лише названі
#   OUT_DIR=~/збірки tools/zibraty_updater.sh   інша тека (типово build/, поза git)
#   TEMPLATES_DIR=<тека> tools/zibraty_updater.sh  шаблони не з ~/.local/share/godot/…
#
# Виходить build/updater-<дата>-<коміт>/:
#   linux/MyWay-Updater.x86_64       один файл (дані вбудовано)
#   macos/MyWay Updater.app          ad-hoc підпис від Godot
#   windows/MyWay-Updater.exe        один файл
#   MyWay-Updater-<платформа>-….zip  архів для гравця
# Апдейтер малий (≈70–160 МБ — це сам рушій), тож дані вбудовано: гравцеві
# простіше з одним файлом. Самооновлення немає: новішу версію (config/version
# у updater/project.godot) апдейтер лише показує попередженням.
#
# Godot — лише --headless. Інтернету скрипт не чіпає.
# Змінні лише латиницею.
set -euo pipefail
cd "$(dirname "$0")/.."
root="$(pwd)"

platforms=("$@")
[ ${#platforms[@]} -eq 0 ] && platforms=(linux macos windows)

full_version="$(godot --headless --version 2>/dev/null | tail -1)"
version="$(printf '%s' "$full_version" | sed -E 's/\.(official|custom_build|mono|[a-z_]+build).*$//')"
templates="${TEMPLATES_DIR:-$HOME/.local/share/godot/export_templates/$version}"
commit="$(git rev-parse --short HEAD 2>/dev/null || echo bez-git)"
dirty=""
git diff --quiet HEAD -- updater 2>/dev/null || dirty="+зміни"
stamp="$(date +%Y-%m-%d)"
out="${OUT_DIR:-$root/build}/updater-$stamp-$commit$dirty"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

godot_env=()
if [ -n "${TEMPLATES_DIR:-}" ]; then
    mkdir -p "$work/xdg/godot/export_templates"
    ln -s "$(realpath "$TEMPLATES_DIR")" "$work/xdg/godot/export_templates/$version"
    godot_env=(env "XDG_DATA_HOME=$work/xdg")
fi

echo "→ godot $full_version, шаблони: $templates, апдейтер v$(grep -oP '^config/version="\K\d+' updater/project.godot)"
# Кеш імпорту: без нього експорт не знайде ресурсів.
[ -d updater/.godot ] || godot --headless --path "$root/updater" --import > /dev/null 2>&1 || true

built=()
missing=()
failed=()
mkdir -p "$out"
for name in "${platforms[@]}"; do
    case "$name" in
        linux)   preset="Linux";   template="$templates/linux_release.x86_64";        target="$out/linux/MyWay-Updater.x86_64" ;;
        macos)   preset="macOS";   template="$templates/macos.zip";                   target="$work/MyWay-Updater.zip" ;;
        windows) preset="Windows"; template="$templates/windows_release_x86_64.exe";  target="$out/windows/MyWay-Updater.exe" ;;
        *) echo "‼ невідома платформа «$name»" >&2; failed+=("$name"); continue ;;
    esac
    echo
    echo "── $preset"
    if [ ! -f "$template" ]; then
        echo "  ∅ немає шаблону: $template"; missing+=("$name"); continue
    fi
    rm -rf "$out/$name"
    mkdir -p "$out/$name"
    log="$out/$name.log"
    if ! "${godot_env[@]}" godot --headless --path "$root/updater" \
            --export-release "$preset" "$target" > "$log" 2>&1 || [ ! -s "$target" ]; then
        echo "  ‼ експорт не вдався — $log"; failed+=("$name"); continue
    fi
    if [ "$name" = macos ]; then
        unzip -q "$target" -d "$out/$name"
        if sed 's/\x1b\[[0-9;]*m//g' "$log" | grep -q 'CodeSign.*не вдався\|CodeSign: Failed'; then
            echo "  ‼ вбудований підпис не вдався — див. $log"
        elif compgen -G "$out/$name/*.app/Contents/_CodeSignature" > /dev/null; then
            echo "  ✓ ad-hoc підпис є (_CodeSignature)"
        else
            echo "  ‼ у бандлі немає _CodeSignature"
        fi
    fi
    errors="$(sed 's/\x1b\[[0-9;]*m//g' "$log" | grep -c '^ERROR' || true)"
    [ "$errors" -gt 0 ] && echo "  (у журналі ERROR: $errors — $log)"
    archive="$out/MyWay-Updater-$name-$stamp-$commit$dirty.zip"
    (cd "$out/$name" && zip -qry "$archive" .)
    echo "  ✓ $archive ($(du -h "$archive" | cut -f1))"
    built+=("$name")
done
echo
echo "зібрано: ${built[*]:-нічого} · без шаблону: ${missing[*]:-—} · провалено: ${failed[*]:-—}"
echo "тека: $out"
[ ${#failed[@]} -eq 0 ] && [ ${#built[@]} -gt 0 ]
