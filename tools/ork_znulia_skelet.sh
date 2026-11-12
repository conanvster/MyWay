#!/usr/bin/env bash
# Орк з нуля, крок 5: ігрова сітка (ork_zbirka.py) → скелет гри, ваги, експорт у гру.
#   tools/ork_znulia_skelet.sh [рухи через кому]
set -e
cd "$(dirname "$0")/.."
# інша модель тим самим ланцюжком: ORK_R (тека art), ORK_G (тека в грі), ORK_N (назва файла),
# ORK_P (основа MPFB зі скелетом гри — джерело ваг і пропорцій скелета)
R=${ORK_R:-art/орк-з-нуля-2026-11-11}; P=${ORK_P:-art/орк-пілот-2026-11-09/v3/pilot.blend}; B=~/Програми/blender-5.2.2-linux-x64/blender
G=${ORK_G:-game/models/own/avatary/ork-z-nulia}; N=${ORK_N:-орк}
mkdir -p $R/5-скелет $G
$B -b $P -P tools/blender/rig_sitky.py -- $R/3-сітка/$N.glb $PWD/$R/5-скелет/a.blend --граней 200000 --без-швів --зварити --руки-окремо 2>&1 | grep -E "риг сітки\] →|Error|Traceback" -A5
$B -b $R/5-скелет/a.blend -P tools/blender/skelet_tiunynh.py -- $PWD/$R/5-скелет/c.blend 2>&1 | grep -E "тюнінг\] →|Error|Traceback" -A5
$B -b $R/5-скелет/c.blend -P tools/blender/vagy_z_ruchnoho.py -- $PWD/$R/5-скелет/d.blend 2>&1 | grep -E "шви|Error|Traceback" -A5
$B -b $R/5-скелет/d.blend -P tools/blender/kulaky.py -- $PWD/$R/5-скелет/$N.blend 2>&1 | grep -E "кулак\]|Error|Traceback" -A5
$B -b $R/5-скелет/$N.blend -P tools/blender/pilot_eksport.py -- $G/$N.glb ${1:+--рухи $1} 2>&1 | grep -E "пілот\]|Error|Traceback" -A5
$B -b --factory-startup -P tools/blender/shkira_karty.py -- $G/$N.glb 2>&1 | grep -E "карти\] →|Error|Traceback" -A5
(cd game && timeout 300 godot --headless --import >/dev/null 2>&1)
echo ГОТОВО
