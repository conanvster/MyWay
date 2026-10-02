#!/usr/bin/env bash
# Ітерація аватара MPFB: збірка з підбором і проєкцією → рендер → оцінка.
#   ./tools/mpfb_iter.sh <N> [ще доводи mpfb_avatar.py]
set -euo pipefail
cd "$(dirname "$0")/.."
n="$1"; shift
D=wiki/img/test/avatar/mpfb2
o=art/monsters/аватар-людина-чоловік-v1-3d/mpfb
mkdir -p "$o/$n"   # своя тека: текстури всіх ітерацій звуться однаково
blender -b -P tools/blender/mpfb_avatar.py -- \
    --підбір "$D/maska-plavky-s411.png" \
    --референс "$D/plavky-s411.png" "$D/maska-plavky-s411.png" "$@" \
    "$o/$n/avatar.gltf" "$o/$n/kadry" 2>&1 \
    | grep -E '^\[(mpfb|підбір|обличчя)\]|‼|Traceback|Error' | grep -vE 'крок 0\.(25|12|06)|кісток|сітки|модифікатори' || true
blender -b --factory-startup -P tools/blender/avatar_render.py -- \
    "$o/$n/avatar.gltf" "$o/render-$n.png" --т-поза 2>&1 | grep -E 'Traceback|Error' || true
~/Програми/cv-venv/bin/python tools/avatar_ocinka2.py "$D/plavky-s411.png" \
    "$D/maska-plavky-s411.png" "$o/render-$n.png" "$o/arkush-$n.png" \
    | tee -a "$o/journal.txt"
