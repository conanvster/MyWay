#!/usr/bin/env bash
# Орчиха з нуля (12.11.2026): той самий ланцюжок, що й орк-чоловік (spec/орк-з-нуля.md).
# Скульпти вже лежать у art/орчиха-з-нуля-2026-11-12/2-скульпт/{тіло,голова}/pixal.glb.
#   tools/orchykha_znulia.sh [аркуш.png]
#   ORK_ZB="…" — додаткові ключі ork_zbirka.py (орчиха-3: --стінка-голови 0.005)
#   ORK_VAR=2 tools/orchykha_znulia.sh — інше обличчя на тому самому тілі: скульпт 2-скульпт/голова2, модель орчиха-2.glb
set -e
cd "$(dirname "$0")/.."
export ORK_R=art/орчиха-з-нуля-2026-11-12 ORK_G=game/models/own/avatary/orchykha-z-nulia ORK_N=орчиха${ORK_VAR:+-$ORK_VAR}
export ORK_P=art/пілот-б-2026-11-07/5/pilot.blend   # жіноча основа: плечові суглоби вужчі, ніж в орка-чоловіка
export ORK_M=orchykha-z-nulia/$ORK_N.glb ORK_Z=1.8 ORK_W=${ORK_W:-орк-жінка-v1.png} ORK_V="--стать ж ${ORK_V2:-}"
# площина шиї — за профілем її скульптів: голова рівно, майже горизонтально під підборіддям: горло (−0,05; 1,52), потилиця (0,05; 1,55)
# (крутіша площина зачіпала верх грудей — бліда пляма на шиї й грудях)
~/Програми/blender-5.2.2-linux-x64/blender -b --factory-startup -P tools/blender/ork_zbirka.py -- \
    $ORK_R/2-скульпт/тіло/pixal.glb $ORK_R/2-скульпт/голова${ORK_VAR:-}/pixal.glb $ORK_R/3-сітка/$ORK_N.blend \
    --зріст $ORK_Z --горло-y -0.05 --горло-z 1.52 --потилиця-y 0.05 --потилиця-z 1.55 --вирівняти-тон --тон-плавний --промахи-радіус 0.19 --промах-поріг 0.06 --без-промахів-тіла --латка-гладка ${ORK_ZB:-} \
    2>&1 | grep -E "^\[|Error|Traceback" -A3
tools/ork_znulia_skelet.sh
tools/ork_znulia_volossia.sh "${1:-$PWD/art/стенд-2026-11-11/12-орчиха-з-нуля${ORK_VAR:+-$ORK_VAR}.png}" "${ORK_ZACH:-довге}"
echo ОРЧИХА ГОТОВО
