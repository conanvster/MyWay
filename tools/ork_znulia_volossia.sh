#!/usr/bin/env bash
# Орк з нуля, крок 6: волосся на модель зі скелетом → гра → аркуш стенда.
#   tools/ork_znulia_volossia.sh <аркуш.png> [зачіска]
set -e
cd "$(dirname "$0")/.."
# інша модель: ORK_R, ORK_G, ORK_N (як у ork_znulia_skelet.sh), ORK_M (тека/файл для стенда),
# ORK_Z (зріст), ORK_W (кадр вікі), ORK_V (ключі ork_volossia.py, напр. "--стать ж")
R=${ORK_R:-art/орк-з-нуля-2026-11-11}; B=~/Програми/blender-5.2.2-linux-x64/blender; G=${ORK_G:-game/models/own/avatary/ork-z-nulia}
N=${ORK_N:-орк}; M=${ORK_M:-ork-z-nulia/орк.glb}; Z=${ORK_Z:-1.9}; W=${ORK_W:-орк-чоловік-v1.png}
mkdir -p $R/6-волосся
$B -b $R/5-скелет/$N.blend -P tools/blender/ork_volossia.py -- $PWD/$R/6-волосся/$N.blend $ORK_V 2>&1 | grep -E "волосся\] [ВБ]|Error|Traceback" -A8
$B -b $R/6-волосся/$N.blend -P tools/blender/pilot_eksport.py -- $G/$N.glb 2>&1 | grep -E "Error|Traceback" -A5 || true
(cd game && timeout 300 godot --headless --import >/dev/null 2>&1)
./run.sh --стенд --модель $M --зріст $Z --вікі $W --вигляд "зачіска=${2:-коси}" --аркуш "$1" 2>&1 | grep -iE "error|помил" || true
