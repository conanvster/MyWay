#!/bin/bash
# Важкий сет на аватари без броні (27.11.2026, слово замовника: «орк жінка в грі без броні —
# перевір які аватари в грі з бронею які без», «так»): готові скульпти зон суміщуються з тілом
# іншої картки й вивантажуються в гру тим самим ланцюжком, що й картка 1.
#   tools/set_perenesty.sh орк 2 3        — скульпти картки 1 орка (тіло те саме, інші обличчя)
#   tools/set_perenesty.sh людина 3       — скульпти картки 1 людини-чоловіка (те саме тіло)
#   tools/set_perenesty.sh орчиха 3 4 2   — скульпти жіночого сету людини (MPFB, А-поза): тіло орчихи
#                                           спершу в позі донора (poza_yak.py), висоти кадрів — ×
#                                           зріст орчихи / зріст донора, далі спідниця до талії
# Після зон — рядок моделі в tools/rysy_z_nulia.sh переводиться на 4-зони і йдуть риси, бороди
# (чоловіки), брови; копії GLB до сету — art/_архів-аватарів-2026-11-27/<тека>-do-setu/.
set -e
cd "$(dirname "$0")/.."
B=~/Програми/blender-5.2.2-linux-x64/blender
ARCH=art/_архів-аватарів-2026-11-27
TYP=$1; shift
DONOR=""; SPID=""; BORODY=1
case $TYP in
  орк)    Z1=art/сет-важкий-орк-2026-11-12/зони; R=art/орк-з-нуля-2026-11-11; TEKA=ork-z-nulia
          ZONY="чоботи:скульпт:--верх 1.07|наручі:скульпт3:--верх 1.356 --глибина-кадру 0.68|наплічники:скульпт:--низ 0.948|пояс:скульпт:--верх 1.193 --низ 0.459" ;;
  людина) Z1=art/сет-важкий-людина-2026-11-19/зони; R=art/людина-чоловік-з-нуля-2026-11-14; TEKA=lyudyna-cholovik-z-nulia
          ZONY="чоботи:скульпт:--верх 0.875|наручі:скульпт:--верх 1.432 --низ 0.677 --глибина-кадру 0.68|наплічники:скульпт:--низ 0.795|пояс:скульпт2:--верх 1.113 --низ 0.549" ;;
  орчиха) Z1=art/сет-важкий-людина-жінка-2026-11-20/зони; R=art/орчиха-з-нуля-2026-11-12; TEKA=orchykha-z-nulia
          DONOR=art/сет-важкий-людина-жінка-2026-11-20/4-зони/людина-жінка.blend; SPID=1; BORODY=""
          ZONY="чоботи:скульпт4:--верх @0.837|наручі:скульпт:--верх @1.457 --низ @0.891 --глибина-кадру 0.68|наплічники:скульпт2:--низ @1.001|пояс:скульпт2:--верх @1.111 --низ @0.628" ;;
  # нова Т-модель (картка 2): тіло інше й у Т-позі — у позу скульптів картки 1 (донор знятий у позі
  # свого скульпту: 3-сітка/людина.glb), висоти — × зріст / зріст донора в тій позі
  людина-т) Z1=art/сет-важкий-людина-2026-11-19/зони; R=art/людина-чоловік-з-нуля-2026-11-14/2-скульпт/тіло-т-mv-рівне
          TEKA=lyudyna-cholovik-z-nulia; set -- т
          DONOR=art/людина-чоловік-з-нуля-2026-11-14/6-волосся/людина.blend
          DONOR_H=1.75
          DONOR_K="--донор-сітка $PWD/art/людина-чоловік-з-нуля-2026-11-14/3-сітка/людина.glb"
          ZONY="чоботи:скульпт:--верх @0.875|наручі:скульпт:--верх @1.432 --низ @0.677 --глибина-кадру 0.68|наплічники:скульпт:--низ @0.795|пояс:скульпт2:--верх @1.113 --низ @0.549" ;;
  *) echo "тип: орк | людина | людина-т | орчиха"; exit 1 ;;
esac
for k in "$@"; do
  NN=${TYP%-т}-$k
  DD=art/сет-важкий-${TYP%-т}-картка-$NN-2026-11-27
  mkdir -p $DD/зони $ARCH/$TEKA-do-setu
  for zz in чоботи наручі наплічники пояс; do
    mkdir -p $DD/зони/$zz
    for ss in скульпт скульпт2 скульпт3 скульпт4; do
      [ -e $DD/зони/$zz/$ss ] || [ ! -d $Z1/$zz/$ss ] || ln -s $PWD/$Z1/$zz/$ss $DD/зони/$zz/$ss
    done
  done
  [ -f $ARCH/$TEKA-do-setu/$NN.glb ] || cp game/models/own/avatary/$TEKA/$NN.glb $ARCH/$TEKA-do-setu/
  rm -f $DD/4-зони/$NN.blend
  export SET_D=$DD MOD_R=$R MOD_N=$NN SET_TYP=важка MOD_G=/tmp/claude-1000/set-$NN.glb
  unset MOD_S
  KK=1.0
  if [ -n "$DONOR" ]; then
    $B -b $R/6-волосся/$NN.blend -P tools/blender/poza_yak.py -- $PWD/$DONOR $PWD/$DD/поза-донора.npy ${DONOR_K:-} 2>&1 | grep -E "\[поза\] →|‼"
    export MOD_S=$PWD/$DD/поза-донора.npy
    KK=$(~/Програми/cv-venv/bin/python -c "import numpy as n;p=n.load('$DD/поза-донора.npy');print(round((p[:,2].max()-p[:,2].min())/${DONOR_H:-1.739},3))")
  fi
  echo "=== $NN (висоти ×$KK)"
  IFS='|' read -ra ZZ <<< "$ZONY"
  for z in "${ZZ[@]}"; do
    zona=${z%%:*}; rest=${z#*:}; sk=${rest%%:*}; kl=${rest#*:}
    kl=$(python3 -c "import re,sys;print(re.sub(r'@([0-9.]+)',lambda m:str(round(float(m.group(1))*$KK,3)),sys.argv[1]))" "$kl")
    # shellcheck disable=SC2086
    SKULPT=$sk tools/set_zona.sh $zona $kl 2>&1 | tail -2
  done
  if [ -n "$SPID" ]; then
    H() { python3 -c "print(round($1*$KK,3))"; }
    $B -b $DD/4-зони/$NN.blend -P tools/blender/spidnytsia_talia.py -- --тіло Тіло --талія $(H 1.03) \
        --від $(H 0.88) --до $(H 0.95) 2>&1 | grep -E "\[спідниця\] верх|Error|Traceback" -A3
  fi
  python3 - "$TEKA" "$NN" "$DD/4-зони/$NN.blend" <<'EOF'
import re, sys
teka, nn, bl = sys.argv[1:]
p = "tools/rysy_z_nulia.sh"; s = open(p).read()
# кінець рядка — без лапки, що закриває SPYSOK (останній рядок таблиці)
s2 = re.sub(r"^%s\|%s\|[^|\n]*\|[^\n\"]*" % (re.escape(teka), re.escape(nn)),
            "%s|%s|%s|--колір-вершин під_одяг" % (teka, nn, bl), s, count=1, flags=re.M)
assert "%s|%s|%s|" % (teka, nn, bl) in s2, "рядка %s немає в таблиці" % nn
open(p, "w").write(s2)
EOF
  TOCHNO=1 tools/rysy_z_nulia.sh $NN 2>&1 | grep -E "РИСИ|‼"
  [ -z "$BORODY" ] || TOCHNO=1 tools/borody_z_nulia.sh $NN 2>&1 | grep -E "БОРОДИ|‼"
  TOCHNO=1 tools/brovy_z_nulia.sh $NN 2>&1 | grep -E "БРОВИ|‼"
done
echo "СЕТ $TYP ГОТОВО"
