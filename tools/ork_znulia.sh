#!/usr/bin/env bash
# Орк-чоловік з нуля (11–14.11.2026): збірка тим самим ланцюжком, що й орчиха та ельфійка
# (spec/орк-з-нуля.md, spec/аватари-з-нуля.md). Перший орк (орк.glb) збирали ключами
# ork_zbirka.py за замовчуванням — вони під нього й заміряні (площина шиї тощо).
#   tools/ork_znulia.sh [аркуш.png]
#   ORK_VAR=2 tools/ork_znulia.sh — інше обличчя на тому самому тілі: скульпт 2-скульпт/голова2,
#                                   модель орк-2.glb, кадр вікі орк-чоловік-v2.png
#   ORK_ZB="…" — додаткові ключі ork_zbirka.py; ORK_ZACH — зачіска на аркуші (типово «коси»)
set -e
cd "$(dirname "$0")/.."
export ORK_R=art/орк-з-нуля-2026-11-11 ORK_G=game/models/own/avatary/ork-z-nulia ORK_N=орк${ORK_VAR:+-$ORK_VAR}
export ORK_M=ork-z-nulia/$ORK_N.glb ORK_Z=1.9 ORK_W=${ORK_W:-орк-чоловік-v${ORK_VAR:-1}.png}
# ORK_TON — ключі вирівнювання тону. Перший орк збирався без них, і в нього тон рівний; з ними
# (як «завжди» в рецепті для жінок) обличчя орків v2/v3 виходили темнішими за тіло (14.11.2026).
ORK_TON=${ORK_TON-}
~/Програми/blender-5.2.2-linux-x64/blender -b --factory-startup -P tools/blender/ork_zbirka.py -- \
    $ORK_R/2-скульпт/тіло/pixal.glb $ORK_R/2-скульпт/голова${ORK_VAR:-}/pixal.glb $ORK_R/3-сітка/$ORK_N.blend \
    --зріст $ORK_Z $ORK_TON --стінка-голови 0.005 ${ORK_ZB:-} \
    2>&1 | grep -E "^\[|Error|Traceback" -A3
tools/ork_znulia_skelet.sh
tools/ork_znulia_volossia.sh "${1:-$PWD/art/стенд-2026-11-11/11-орк-з-нуля${ORK_VAR:+-$ORK_VAR}.png}" "${ORK_ZACH:-коси}"
echo ОРК ГОТОВО
