#!/usr/bin/env bash
# Річ сету броні зі скульпту зони (spec/сети-броні-дослідження.md, spec/аватари-з-нуля.md):
# скульпт зони → річ на скелеті в моделі гри → експорт → імпорт Godot.
#   tools/set_zona.sh <зона> [ключі odiah_zona.py: --верх м --низ м …]
# Зони: чоботи, наручі, наплічники, пояс (ZONY у tools/blender/odiah_zona.py).
# Модель і сет — змінними (типово орк і його важкий сет); інша раса — ті самі кроки:
#   SET_D  тека сету (зони/<зона>/скульпт/pixal.glb, 4-зони/<модель>.blend)
#   MOD_R  тека моделі в art (3-сітка/<модель>.glb, 6-волосся/<модель>.blend)
#   SKULPT тека скульпту в зони/<зона>/ (типово скульпт; друга спроба — скульпт2)
#   MOD_V  перший файл сету (типово MOD_R/6-волосся/<модель>.blend); MOD_T — назва тіла (Тіло);
#   MOD_S  сітка в позі скульпту (типово MOD_R/3-сітка/<модель>.glb; «-» — немає, модель з MPFB:
#          поза скульпту = поза спокою, кадр — tools/blender/kadr_tila.py); MOD_K — ключі експорту
#          (людина-жінка пілот Б: «--з-формами», бо ланцюжка рис у неї немає)
#   MOD_N  назва моделі, MOD_G — її GLB у грі, SET_TYP — тип речей (важка)
set -e
cd "$(dirname "$0")/.."
D=${SET_D:-art/сет-важкий-орк-2026-11-12}; R=${MOD_R:-art/орк-з-нуля-2026-11-11}; N=${MOD_N:-орк}
G=${MOD_G:-game/models/own/avatary/ork-z-nulia/орк.glb}; T=${SET_TYP:-важка}; B=~/Програми/blender-5.2.2-linux-x64/blender
ZONA=$1; shift
S=${SKULPT:-скульпт}
mkdir -p $D/4-зони
# перша зона сету стартує з моделі з волоссям, наступні — з уже зібраного
VHID=$D/4-зони/$N.blend
[ -f $VHID ] || VHID=${MOD_V:-$R/6-волосся/$N.blend}
SITKA=${MOD_S:-$R/3-сітка/$N.glb}
if [ "$SITKA" = "-" ]; then SITKA_K=(); else SITKA_K=(--сітка "$SITKA"); fi
$B -b $VHID -P tools/blender/odiah_zona.py -- $D/зони/$ZONA/$S/pixal.glb $PWD/$D/4-зони/$N.blend \
    "${SITKA_K[@]}" --тіло ${MOD_T:-Тіло} --зона $ZONA --тип $T --огляд $PWD/$D/зони/$ZONA/огляд.png "$@" 2>&1 \
    | grep -E "^\[зона\]|Error|Traceback|SystemExit" -A8 | grep -vE "render|Deprecation|use_nodes|INFO|Info|cycles|Blender|^--| \| $"
$B -b $D/4-зони/$N.blend -P tools/blender/pilot_eksport.py -- $G --колір-вершин під_одяг ${MOD_K:-} 2>&1 | grep -E "Error|Traceback" -A5 || true
(cd game && timeout 300 godot --headless --import >/dev/null 2>&1) || true
echo "ЗОНА $ZONA ГОТОВА"
