#!/usr/bin/env bash
# Великі чисті кадри варіантів орка-пілота в переглядачі (П-281, 09.11.2026).
#   tools/ork_pilot_kadry.sh <тека виходу> <мітка> <аргументи проби…>
# Напр.: tools/ork_pilot_kadry.sh art/…/velyki A --проба орк-trellis
set -e
cd "$(dirname "$0")/.."
out=$(realpath "$1"); mitka=$2; shift 2
G=(godot --path game --disable-vsync --resolution 1400x1400 res://scenes/model_viewer.tscn --)
kadr() { "${G[@]}" "$@" --без-панелей --кадрів 60 >/dev/null 2>&1; }
kadr "$@" --кут 0   --відстань 0.5 --ціль 0,1.5,0 --знімок "$out/$mitka-1-обличчя.png"
kadr "$@" --кут 35  --відстань 0.5 --ціль 0,1.5,0 --знімок "$out/$mitka-2-обличчя-бік.png"
kadr "$@" --кут 20  --відстань 1.2  --ціль 0,1.2,0  --знімок "$out/$mitka-3-торс.png"
kadr "$@" --кут 0   --відстань 3.2  --ціль 0,0.95,0 --знімок "$out/$mitka-4-зріст.png"
kadr "$@" --кут 180 --відстань 3.2  --ціль 0,0.95,0 --знімок "$out/$mitka-5-зад.png"
kadr "$@" --рух Walk --кут 40 --відстань 3.2 --ціль 0,0.95,0 --знімок "$out/$mitka-6-хода.png"
echo "кадри $mitka → $out"
