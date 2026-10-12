#!/usr/bin/env bash
# Ельфійка від скану до гри одним запуском (12.10.2026): тіло → основа →
# риси обличчя → 5 зачісок → збирання на скелеті Mixamo з 10 рухами.
#
#   tools/elfiika_zbirka.sh <тека-скану> <кадр-основа без .png> [вихід.glb]
#
# <тека-скану> — art/monsters/<назва>-3d з pixal3d.glb; кадр-основа —
# wiki/img/test/avatar/<…> (поруч мають бути <…>-4k.png і <…>-4k-maska.png).
# Рухи — art/mixamo/elf808v5 (скелет Mixamo підганяється за габаритом,
# тож годиться той самий, поки статура та сама).
# Змінні — латиницею (кирилиця в масивах bash ламається).
set -euo pipefail
cd "$(dirname "$0")/.."
BL=~/Програми/blender-5.2.2-linux-x64/blender
SKAN=$1
REF=$2
OUT=${3:-game/models/own/avatary/elf-s808-mixamo/elf-s808-mixamo.glb}
RUKHY=art/mixamo/elf808v5
STYLES="розпущене напівхвіст коса зачесане каре"
BODY=$SKAN/avatar-v3
OSN=$SKAN/osnova-v3

$BL -b --factory-startup -P tools/blender/avatar_build.py -- "$SKAN/pixal3d.glb" \
    "$BODY/ельф-жінка.gltf" --референс "$REF-4k.png" "$REF-4k-maska.png" \
    --текстура 4096 --кисті-скану --одна-оболонка --коліна 8 --обличчя --очі \
    | grep "\[аватар\]\|\[маски\]\|‼"
$BL -b --factory-startup -P tools/blender/elf_osnova.py -- "$BODY/ельф-жінка.gltf" "$OSN" \
    | grep "\[заміри\]\|\[основа\]"
$BL -b --factory-startup -P tools/blender/elf_rysy.py -- "$OSN/основа.blend" \
    "$BODY/oblychchia-G.npy" "$OSN/основа-риси.blend" | grep "\[риси\]"
ZACH=()
for st in $STYLES; do
    $BL -b --factory-startup -P tools/blender/volossia_pasma.py -- "$OSN/основа.blend" \
        "$OSN/волосся-$st.blend" --стиль "$st" | grep "\[пасма\] карток"
    ZACH+=(--зачіска "$OSN/волосся-$st.blend")
done
SHKIRA=$(ls $RUKHY/*01_spokii*.fbx)
$BL -b --factory-startup -P tools/blender/mixamo_zbirka.py -- "$OSN/основа-риси.blend" \
    "$OUT" "$SHKIRA" $(ls $RUKHY/*.fbx | grep -v 01_spokii) --волосся "${ZACH[@]}" \
    --маски "$BODY/аватар-маски.png" | grep "\[mixamo\]\|\[волосся\]"
(cd game && godot --headless --import >/dev/null 2>&1) || true
echo "готово: $OUT"
