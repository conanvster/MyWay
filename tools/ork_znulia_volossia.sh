#!/usr/bin/env bash
# Орк з нуля, крок 6: волосся на модель зі скелетом → гра → аркуш стенда.
#   tools/ork_znulia_volossia.sh <аркуш.png> [зачіска]
set -e
cd "$(dirname "$0")/.."
R=art/орк-з-нуля-2026-11-11; B=~/Програми/blender-5.2.2-linux-x64/blender; G=game/models/own/avatary/ork-z-nulia
$B -b $R/5-скелет/орк.blend -P tools/blender/ork_volossia.py -- $PWD/$R/6-волосся/орк.blend 2>&1 | grep -E "волосся\] [ВБ]|Error|Traceback" -A8
$B -b $R/6-волосся/орк.blend -P tools/blender/pilot_eksport.py -- $G/орк.glb 2>&1 | grep -E "Error|Traceback" -A5 || true
(cd game && timeout 300 godot --headless --import >/dev/null 2>&1)
./run.sh --стенд --модель ork-z-nulia/орк.glb --зріст 1.9 --вікі орк-чоловік-v1.png --вигляд "зачіска=${2:-коси}" --аркуш "$1" 2>&1 | grep -iE "error|помил" || true
