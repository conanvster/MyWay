#!/bin/bash
# Пояс орчихи — зі скульпту пояса орка-чоловіка (27.11.2026): жіночий пояс людини (MPFB) на широких
# стегнах орчихи сідав лише спереду, ззаду лишалась білизна. Тіло орчихи — у позу скульпту орка
# (poza_yak.py --донор-сітка), висоти кадру пояса орка (--верх 1.193 --низ 0.459) — × зріст орчихи
# в тій позі / 1,897 (орк у позі скульпту). Річ замінює наявний пояс у 4-зони; далі риси й брови.
#   tools/orchykha_poyas_orka.sh 3 4 2
set -e
cd "$(dirname "$0")/.."
B=~/Програми/blender-5.2.2-linux-x64/blender
PY=~/Програми/cv-venv/bin/python
for k in "$@"; do
  NN=орчиха-$k
  DD=art/сет-важкий-орчиха-картка-$NN-2026-11-27
  [ -f $DD/4-зони/$NN.blend ] || { echo "‼ $NN: спершу tools/set_perenesty.sh орчиха $k"; exit 1; }
  [ -e $DD/зони/пояс/скульпт-орк ] || ln -s $PWD/art/сет-важкий-орк-2026-11-12/зони/пояс/скульпт $DD/зони/пояс/скульпт-орк
  $B -b art/орчиха-з-нуля-2026-11-12/6-волосся/$NN.blend -P tools/blender/poza_yak.py -- \
      $PWD/art/орк-з-нуля-2026-11-11/6-волосся/орк.blend $PWD/$DD/поза-орка.npy \
      --донор-сітка $PWD/art/орк-з-нуля-2026-11-11/3-сітка/орк.glb 2>&1 | grep -E "\[поза\] →|‼"
  KK=$($PY -c "import numpy as n;p=n.load('$DD/поза-орка.npy');print(round((p[:,2].max()-p[:,2].min())/1.897,3))")
  V=$($PY -c "print(round(1.193*$KK,3))"); N=$($PY -c "print(round(0.459*$KK,3))")
  echo "=== $NN: пояс орка, висоти ×$KK (верх $V, низ $N)"
  SET_D=$DD MOD_R=art/орчиха-з-нуля-2026-11-12 MOD_N=$NN SET_TYP=важка MOD_S=$PWD/$DD/поза-орка.npy \
      MOD_G=/tmp/claude-1000/set-$NN.glb SKULPT=скульпт-орк tools/set_zona.sh пояс --верх $V --низ $N 2>&1 | tail -2
  TOCHNO=1 tools/rysy_z_nulia.sh $NN 2>&1 | grep -E "РИСИ|‼" || true
  TOCHNO=1 tools/brovy_z_nulia.sh $NN 2>&1 | grep -E "БРОВИ|‼" || true
done
echo "ПОЯС ОРКА НА ОРЧИХУ ГОТОВО"
