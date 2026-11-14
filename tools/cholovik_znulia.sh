#!/usr/bin/env bash
# Людина-чоловік і ельф-чоловік з нуля (14.11.2026, слово замовника: «старі 3 моделі чоловіка мають
# дивний вигляд — потрібно генерувати нові», «не маємо нормальної моделі ельфа — треба зробити»).
# Той самий ланцюжок, що й орк, орчиха, ельфійка (spec/орк-з-нуля.md). Скульпти —
# art/<раса>-чоловік-з-нуля-2026-11-14/2-скульпт/{тіло,голова,голова2,голова3}/pixal.glb.
#   RASA=людина tools/cholovik_znulia.sh [аркуш.png]
#   RASA=ельф ORK_VAR=2 tools/cholovik_znulia.sh — друге обличчя на тому самому тілі
#   ORK_ZB="…" — додаткові ключі ork_zbirka.py; ORK_ZACH — зачіска на аркуші
set -e
cd "$(dirname "$0")/.."
RASA=${RASA:?людина або ельф}
if [ "$RASA" = ельф ]; then
    LAT=elf-cholovik-z-nulia; NAZVA=ельф; ZRIST=1.85
    # площина шиї — під щелепою, як в ельфійки, лише в зрості 1,85
    SHYIA=${SHYIA:---горло-y -0.03 --горло-z 1.60 --потилиця-y 0.06 --потилиця-z 1.64 --зріз-голови 0.02}
    VUHA="--вуха-гостріші 0.3 --вуха-стирчать 0.02 --вуха-в-тон"
    export ORK_KOLIR=${ORK_KOLIR:-#e6e6ea}       # ельф — біле волосся
else
    LAT=lyudyna-cholovik-z-nulia; NAZVA=людина; ZRIST=1.75
    SHYIA=${SHYIA:---горло-y -0.03 --горло-z 1.515 --потилиця-y 0.06 --потилиця-z 1.555 --зріз-голови 0.02}
    VUHA="--шия-в-тон"                         # v3: червона пляма на горлі (14.11.2026)
fi
export ORK_R=art/$RASA-чоловік-з-нуля-2026-11-14 ORK_G=game/models/own/avatary/$LAT ORK_N=$NAZVA${ORK_VAR:+-$ORK_VAR}
export ORK_P=art/аватари-2026-11-09/$RASA-чоловік/основа/pilot.blend   # чоловіча основа раси
export ORK_M=$LAT/$ORK_N.glb ORK_Z=$ZRIST ORK_W=${ORK_W:-$RASA-чоловік-v${ORK_VAR:-1}.png}
# ORK_TON — вирівнювання тону; для v2/v3 можна --тон-як <текстура голови v1>, як в орків
ORK_TON=${ORK_TON---вирівняти-тон --тон-плавний --тон-плями 0.007}
mkdir -p $ORK_R/3-сітка; rm -f $ORK_R/3-сітка/$ORK_N.glb   # щоб не підхопити старий проміжний файл
~/Програми/blender-5.2.2-linux-x64/blender -b --factory-startup -P tools/blender/ork_zbirka.py -- \
    $ORK_R/2-скульпт/тіло/pixal.glb $ORK_R/2-скульпт/голова${ORK_VAR:-}/pixal.glb $ORK_R/3-сітка/$ORK_N.blend \
    --зріст $ORK_Z $SHYIA $ORK_TON --стінка-голови 0.005 --стінка-лише-зовні --чистити-шкіру --тон-тіла-рівний 0.03 $VUHA \
    --промахи-радіус 0.19 --промах-поріг 0.06 --без-промахів-тіла --латка-гладка ${ORK_ZB:-} \
    > $ORK_R/3-сітка/$ORK_N-збірка.log 2>&1 || true
grep -E "^\[" $ORK_R/3-сітка/$ORK_N-збірка.log | tail -12
# журнал повністю, а тоді перевірка (grep -q у конвеєрі обриває Blender посеред роботи)
grep -qE "Traceback|^Error:" $ORK_R/3-сітка/$ORK_N-збірка.log && { grep -E "Traceback|^Error:" -A4 $ORK_R/3-сітка/$ORK_N-збірка.log; echo "ЗБІРКА ВПАЛА"; exit 1; }
[ -s $ORK_R/3-сітка/$ORK_N.glb ] || { echo "немає $ORK_R/3-сітка/$ORK_N.glb"; exit 1; }
tools/ork_znulia_skelet.sh
tools/ork_znulia_volossia.sh "${1:-$PWD/art/стенд-2026-11-11/14-$RASA-чоловік-з-нуля${ORK_VAR:+-$ORK_VAR}.png}" "${ORK_ZACH:-зачесане}"
echo "$RASA-ЧОЛОВІК ГОТОВО"
