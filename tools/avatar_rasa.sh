#!/bin/bash
# Аватар раси пошарово (П-281, 09.11.2026; слово замовника: «тепер зробити для
# усих рас так само, модель топлес з усіма налаштуваннями як ми зробили та
# приклад із бронею»). Той самий ланцюжок, що в людини-жінки
# (spec/аватари-підходи.md), параметри типу — tools/avatary_rasy.json.
#
#   tools/avatar_rasa.sh <тип> [крок…]
#   кроки: osnova volossia rysy eksport shkiry odiah (без кроків — усі)
#   змінні (П-285): ART — тека проміжного, TEKA — тека моделі в грі,
#   VOL="--якість" — картки волосся нового зразка, PASOM — кількість пасом
#
# Проміжне — art/аватари-2026-11-09/<тип>/ (лише диск), моделі —
# game/models/own/avatary/<тека>/<тип>.glb і <тип>-одяг-важка.glb.
set -e
VOL=${VOL:-}
cd "$(dirname "$0")/.."
t=$1
shift
steps=${*:-"osnova volossia rysy eksport shkiry odiah"}
B=${BLENDER:-$HOME/Програми/blender-5.2.2-linux-x64/blender}
PY=${CVPY:-$HOME/Програми/cv-venv/bin/python}
D=$HOME/.config/blender/5.2/extensions/.user/blender_org/mpfb/data
cfg() { python3 -c "import json,sys;v=json.load(open('tools/avatary_rasy.json'))[sys.argv[1]].get(sys.argv[2],'');print(('1' if v else '') if isinstance(v,bool) else v)" "$t" "$1"; }
A=${ART:-art/аватари-2026-11-09}/$t
O=$A/основа
V=$A/волосся
RY=$A/риси
G=game/models/own/avatary/${TEKA:-$(cfg тека)}
mkdir -p "$O" "$V" "$RY" "$G"
RUHY=A_TPose,Idle_Loop,Walk_Loop,Sprint_Loop,Sword_Attack,Crouch_Fwd,Sitting_Idle,Jump_Start
log() { echo "[$t] $*"; }

for s in $steps; do
case $s in
osnova)
  if [ ! -f "$O/pilot.blend" ]; then
    rs=$(cfg риси)
    args=(-- "$O" --зачіска - --без-рендеру --макро "$(cfg макро)" --шкіра "$(cfg шкіра)")
    [ -n "$rs" ] && args+=(--риси "$rs")
    $B -b -P tools/blender/pilot_b.py "${args[@]}" 2>&1 | grep -E "Error|Traceback" || true
  fi
  extra=()
  [ -n "$(cfg чоловік)" ] && extra+=(--чоловік)
  [ -n "$(cfg ікла)" ] && extra+=(--ікла)
  $B -b "$O/pilot.blend" -P tools/blender/pilot_osnova.py -- "$O" "${extra[@]}" 2>&1 | grep -E "\[основа\]|Error|Traceback"
  ;;
volossia)
  $B -b "$O/основа.blend" -P tools/blender/pilot_volossia.py -- тіло "$V/тіло.blend" 2>&1 | grep -E "\[волосся\]|Error|Traceback"
  zbir=()
  for par in $(cfg зачіски); do
    st=${par%%=*}
    $B -b --factory-startup -P tools/blender/volossia_pasma.py -- "$V/тіло.blend" "$V/волосся-$st.blend" \
      --стиль "$st" --природне --пасом ${PASOM:-2200} $VOL 2>&1 | grep -E "\[пасма\] (стиль|пучків)|Error|Traceback"
    zbir+=("$V/волосся-$st.blend=${par#*=}")
  done
  bk=$(cfg борода)
  if [ -n "$bk" ]; then
    $B -b --factory-startup -P tools/blender/volossia_pasma.py -- "$V/тіло.blend" "$V/борода.blend" \
      --стиль борода --природне --пасом 5000 $VOL 2>&1 | grep -E "\[пасма\] стиль|Error|Traceback"
    zbir+=("$V/борода.blend=$bk")
  fi
  $B -b "$O/основа.blend" -P tools/blender/pilot_volossia.py -- зібрати "$V/зачіски.blend" "${zbir[@]}" \
    2>&1 | grep -E "\[волосся\]|Error|Traceback"
  ;;
rysy)
  $B -b "$V/зачіски.blend" -P tools/blender/pilot_rysy.py -- "$RY/риси.blend" --спосіб цілі \
    --брови "$(cfg брови)" --вії "$(cfg вії)" 2>&1 | grep -E "Error|Traceback|\[риси\].*→" || true
  ;;
eksport)
  $B -b "$RY/риси.blend" -P tools/blender/pilot_eksport.py -- "$G/$t.glb" --з-формами \
    2>&1 | grep -E "Error|Traceback|\[пілот\] →" || true
  ;;
shkiry)
  $PY tools/pilot_maski.py "$RY/риси.npz" "$D/eyes/materials/brown_eye.png" "$RY/маски.png" "$RY/маски-очі.png"
  for m in "$t" "$t-одяг-важка"; do
    cp "$RY/маски.png" "$G/${m}_маски.png"
    cp "$RY/маски-очі.png" "$G/${m}_маски-очі.png"
  done
  (cd game && timeout 600 godot --headless --import >/dev/null 2>&1 || true)
  sk=$(cfg шкіри)
  for m in "$t" "$t-одяг-важка"; do      # і модель із бронею: шкіра крізь проріз шолома
    $PY tools/pilot_shkiry.py "$D" "$RY/маски.png" "$RY/маски-очі.png" "$G/$m" ${sk:+--шкіри "$sk"} | tail -1
  done
  ;;
odiah)
  $B -b "$RY/риси.blend" -P tools/blender/pilot_odiah.py -- "$A/одяг-важка.blend" --спосіб важка \
    2>&1 | grep -E "під річчю|Error|Traceback"
  $B -b "$A/одяг-важка.blend" -P tools/blender/pilot_eksport.py -- "$G/$t-одяг-важка.glb" --рухи $RUHY \
    --з-формами --колір-вершин під_одяг 2>&1 | grep -E "Error|Traceback|\[пілот\] →" || true
  ;;
esac
log "крок $s — готово"
done
