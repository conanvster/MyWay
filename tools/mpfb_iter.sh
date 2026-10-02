#!/usr/bin/env bash
# Ітерація аватара MPFB: збірка з підбором і проєкцією → рендер → оцінка.
#   ./tools/mpfb_iter.sh <N> [ще доводи mpfb_avatar.py]
set -euo pipefail
cd "$(dirname "$0")/.."
n="$1"; shift
D=wiki/img/test/avatar/mpfb2
R="${REF:-plavky-sym-s411}"   # кадр-референс у $D (маска — maska-$R.png)
o=art/monsters/аватар-людина-чоловік-v1-3d/mpfb
mkdir -p "$o/$n"   # своя тека: текстури всіх ітерацій звуться однаково
blender -b -P tools/blender/mpfb_avatar.py -- \
    --підбір "$D/maska-$R.png" \
    --референс "$D/$R.png" "$D/maska-$R.png" "$@" \
    "$o/$n/avatar.gltf" "$o/$n/kadry" 2>&1 \
    | grep -E '^\[(mpfb|підбір|обличчя)\]|‼|Traceback|Error' | grep -vE 'крок 0\.(25|12|06)|кісток|сітки|модифікатори' || true
blender -b --factory-startup -P tools/blender/avatar_render.py -- \
    "$o/$n/avatar.gltf" "$o/render-$n.png" --т-поза 2>&1 | grep -E 'Traceback|Error' || true
[ -f "$o/render-$n.png" ] || { echo "‼ рендер $n не вийшов — оцінки нема"; exit 1; }
~/Програми/cv-venv/bin/python tools/avatar_ocinka2.py "$D/$R.png" \
    "$D/maska-$R.png" "$o/render-$n.png" "$o/arkush-$n.png" \
    | tee -a "$o/journal.txt"
