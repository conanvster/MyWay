#!/bin/bash
# Важкий сет ельфійки, картки 1–3 (27.11.2026, слово замовника: «зроби важкий сет для ельфів
# також»): скульпти зон жіночого сету людини (art/сет-важкий-людина-жінка-2026-11-20 — панцир
# жінки: наплічники з кірасою, пояс-спідниця), кожна зона суміщується з тілом ельфійки за шкірою —
# у позі донора (poza_yak.py: ельфійка в Т-позі, скульпти — в А-позі; без цього не сідало).
# Висоти кадрів зон — ті самі, що для людини-жінки (зріст 1,739), перераховані на зріст ельфійки
# — ігрова модель ельфійки теж ~1,74 м (1,819 — сирий скульпт): ×1,0. Далі спідниця до талії, риси, брови й вивантаження в гру (рядки ельфійки в
# tools/rysy_z_nulia.sh беруть 4-зони).
#   tools/set_elfiika.sh [1] [2] [3]
set -e
cd "$(dirname "$0")/.."
B=~/Програми/blender-5.2.2-linux-x64/blender
Z1=art/сет-важкий-людина-жінка-2026-11-20/зони
ARCH=art/_архів-аватарів-2026-11-27
GD=game/models/own/avatary/elfiika-z-nulia
K=1.0
h() { python3 -c "print(round($1*$K,3))"; }
for k in ${*:-1 2 3}; do
  if [ "$k" = 1 ]; then NN=ельфійка; else NN=ельфійка-$k; fi
  DD=art/сет-важкий-ельфійка-картка$k-2026-11-27
  mkdir -p $DD/зони $ARCH/elfiika-z-nulia-do-setu
  for zz in чоботи наручі наплічники пояс; do
    mkdir -p $DD/зони/$zz
    for ss in скульпт скульпт2 скульпт4; do
      [ -e $DD/зони/$zz/$ss ] || [ ! -d $Z1/$zz/$ss ] || ln -s $PWD/$Z1/$zz/$ss $DD/зони/$zz/$ss
    done
  done
  [ -f $ARCH/elfiika-z-nulia-do-setu/$NN.glb ] || cp $GD/$NN.glb $ARCH/elfiika-z-nulia-do-setu/
  rm -f $DD/4-зони/$NN.blend
  # тіло ельфійки (Т-поза скульпту) — у позу донора скульптів (А-поза MPFB людини-жінки)
  $B -b art/ельфійка-з-нуля-2026-11-12/6-волосся/$NN.blend -P tools/blender/poza_yak.py -- \
      $PWD/art/сет-важкий-людина-жінка-2026-11-20/4-зони/людина-жінка.blend $PWD/$DD/поза-донора.npy 2>&1 | grep -E "\[поза\] →|‼"
  export SET_D=$DD MOD_R=art/ельфійка-з-нуля-2026-11-12 MOD_N=$NN SET_TYP=важка MOD_S=$PWD/$DD/поза-донора.npy
  export MOD_G=/tmp/claude-1000/set-elfiika-kartka$k.glb   # проміжний; у гру — після рис
  echo "=== картка $k ($NN)"
  SKULPT=скульпт4 tools/set_zona.sh чоботи --верх $(h 0.837) 2>&1 | tail -3
  SKULPT=скульпт tools/set_zona.sh наручі --верх $(h 1.457) --низ $(h 0.891) --глибина-кадру 0.68 2>&1 | tail -3
  SKULPT=скульпт2 tools/set_zona.sh наплічники --низ $(h 1.001) 2>&1 | tail -3
  SKULPT=скульпт2 tools/set_zona.sh пояс --верх $(h 1.111) --низ $(h 0.628) 2>&1 | tail -3
  $B -b $DD/4-зони/$NN.blend -P tools/blender/spidnytsia_talia.py -- --тіло Тіло --талія $(h 1.03) \
      --від $(h 0.88) --до $(h 0.95) 2>&1 | grep -E "спідниця|Error|Traceback" -A3
  TOCHNO=1 tools/rysy_z_nulia.sh $NN 2>&1 | grep -E "РИСИ|‼"
  TOCHNO=1 tools/brovy_z_nulia.sh $NN 2>&1 | grep -E "БРОВИ|‼"
done
echo "СЕТИ ЕЛЬФІЙКИ ГОТОВІ"
