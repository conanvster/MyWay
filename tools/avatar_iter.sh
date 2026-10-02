#!/usr/bin/env bash
# Одна ітерація аватара: збірка → рендер спереду → оцінка (02.10.2026).
#   ./tools/avatar_iter.sh <N> [ще доводи avatar_build.py]
set -euo pipefail
cd "$(dirname "$0")/.."
n="$1"; shift
d="art/monsters/аватар-людина-чоловік-v1-3d/ocinka"
blender -b --factory-startup -P tools/blender/avatar_build.py -- \
    --референс wiki/img/test/avatar/baza2-s222.png "$d/maska-ref.png" "$@" \
    art/monsters/аватар-людина-чоловік-v1-3d/pixal3d-02-baza2.glb \
    game/models/own/avatary/людина-чоловік-v1.gltf 2>&1 \
    | grep -E '^\[аватар\] [^ ]|‼|Traceback|Error' || true
blender -b --factory-startup -P tools/blender/avatar_render.py -- \
    game/models/own/avatary/людина-чоловік-v1.gltf "$d/render-$n.png" \
    2>&1 | grep -E 'Traceback|Error' || true
~/ComfyUI/venv/bin/python tools/avatar_ocinka.py \
    wiki/img/test/avatar/baza2-s222.png "$d/maska-ref.png" \
    "$d/render-$n.png" "$d/arkush-$n.png" | tee -a "$d/journal.txt"
