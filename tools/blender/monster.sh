#!/usr/bin/env bash
# Монстр із Blender у гру одною командою (19.09.2026).
#
#   ./tools/blender/monster.sh art/monsters/вовкулака.blend
#
# Що робить: експортує .blend у game/models/own/<та сама назва>.glb з
# потрібними налаштуваннями, дає Godot імпортувати й проганяє пробу
# `own_models.gd` — чи є рухи, чи стоїть на землі, чи дивиться вперед.
#
# Змінні лише латиницею: кирилична назва тихо ламає масиви й `for`.
set -euo pipefail
cd "$(dirname "$0")/../.."

if [ $# -lt 1 ] || [ ! -f "$1" ]; then
    echo "‼ дай шлях до .blend: ./tools/blender/monster.sh art/monsters/x.blend" >&2
    exit 1
fi
src="$1"
base="$(basename "$src" .blend)"
out="$PWD/game/models/own/$base.glb"
mkdir -p game/models/own

blender --background "$src" --python tools/blender/export_glb.py -- "$out" \
    2>&1 | grep -E '^\[експорт\]|Error|Traceback' || true
[ -f "$out" ] || { echo "‼ експорт не вдався — $out не з'явився" >&2; exit 1; }

godot --headless --path game --import > /dev/null 2>&1 || true
godot --headless --path game --script res://probes/own_models.gd 2>&1 \
    | grep -E '—|✓|✗|підсумок|моделей'
echo
echo "Щоб монстр з'явився в грі — у game/data/mobs.json, у потрібному виді:"
echo "  \"вигляд\": {\"модель\": \"res://models/own/$base.glb\", \"зріст\": 1.4}"
