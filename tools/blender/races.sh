#!/usr/bin/env bash
# Шість моделей гравця (людина, ельф, орк × чоловік, жінка) з одягом —
# з моделі людини Quaternius (19.09.2026). Картинки для перевірки оком —
# другим доводом.
#
#   ./tools/blender/races.sh [тека_для_картинок]
#
# Змінні лише латиницею: кирилична назва тихо ламає масиви й `for`.
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p game/models/own/races
shots="${1:-}"
python3 tools/blender/skin_texture.py
for race in людина ельф орк; do
    for sex in чоловік жінка; do
        blender --background --python tools/blender/make_races.py -- \
            "$race" "$sex" "game/models/own/races/$race-$sex.gltf" $shots \
            2>&1 | grep -E '^\[раси\]|Traceback|Error' || true
    done
done
godot --headless --path game --import > /dev/null 2>&1 || true
