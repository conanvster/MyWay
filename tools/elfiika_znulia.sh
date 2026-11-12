#!/usr/bin/env bash
# Ельфійка з нуля (12.11.2026): той самий ланцюжок, що й орк і орчиха (spec/орк-з-нуля.md, §10).
# Скульпти лежать у art/ельфійка-з-нуля-2026-11-12/2-скульпт/{тіло,голова,голова2,голова3}/pixal.glb.
#   tools/elfiika_znulia.sh [аркуш.png]
#   ORK_VAR=2 tools/elfiika_znulia.sh — інше обличчя на тому самому тілі (скульпт голова2, модель ельфійка-2.glb)
#   ORK_ZB="…" — додаткові ключі ork_zbirka.py
set -e
cd "$(dirname "$0")/.."
export ORK_R=art/ельфійка-з-нуля-2026-11-12 ORK_G=game/models/own/avatary/elfiika-z-nulia ORK_N=ельфійка${ORK_VAR:+-$ORK_VAR}
export ORK_P=art/пілот-б-2026-11-07/5/pilot.blend   # жіноча основа
export ORK_M=elfiika-z-nulia/$ORK_N.glb ORK_Z=1.82 ORK_W=${ORK_W:-ельф-жінка-v${ORK_VAR:-1}.png} ORK_V="--стать ж ${ORK_V2:-}"
export ORK_KOLIR=${ORK_KOLIR:-#e6e6ea}              # біле волосся (constitution: ельф — біле волосся)
# площина шиї — під щелепою (підборіддя 1,59, верх плечей 1,53): нижча площина клала шматок плечей
# зі скульпту голови поверх плечей тіла — виходив «комір» на ключицях
ELF_SHYIA=${ELF_SHYIA:---горло-y -0.03 --горло-z 1.575 --потилиця-y 0.06 --потилиця-z 1.615 --зріз-голови 0.02}
~/Програми/blender-5.2.2-linux-x64/blender -b --factory-startup -P tools/blender/ork_zbirka.py -- \
    $ORK_R/2-скульпт/тіло/pixal.glb $ORK_R/2-скульпт/голова${ORK_VAR:-}/pixal.glb $ORK_R/3-сітка/$ORK_N.blend \
    --зріст $ORK_Z $ELF_SHYIA --вирівняти-тон --тон-плавний --тон-плями 0.007 --стінка-голови 0.005 --чистити-шкіру --вуха-гостріші 0.3 --вуха-стирчать 0.02 \
    --промахи-радіус 0.19 --промах-поріг 0.06 --без-промахів-тіла --латка-гладка ${ORK_ZB:-} \
    2>&1 | grep -E "^\[|Error|Traceback" -A3
tools/ork_znulia_skelet.sh
tools/ork_znulia_volossia.sh "${1:-$PWD/art/стенд-2026-11-11/13-ельфійка-з-нуля${ORK_VAR:+-$ORK_VAR}.png}" "${ORK_ZACH:-довге}"
echo ЕЛЬФІЙКА ГОТОВО
