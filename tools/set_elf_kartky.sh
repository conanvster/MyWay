#!/bin/bash
# Важкий сет ельфа-чоловіка на картки 2 і 3 (27.11.2026, слово замовника: «зроби важкий сет для
# ельфів також»): ті самі скульпти зон, що й на картці 1 (art/сет-важкий-ельф-2026-11-20), тіло
# те саме (інші лише обличчя) — кожна зона заново суміщується з моделлю своєї картки; далі риси,
# бороди, брови й вивантаження в гру (рядок картки в tools/rysy_z_nulia.sh бере 4-зони).
#   tools/set_elf_kartky.sh [2] [3]
set -e
cd "$(dirname "$0")/.."
Z1=art/сет-важкий-ельф-2026-11-20/зони
ARCH=art/_архів-аватарів-2026-11-27
GD=game/models/own/avatary/elf-cholovik-z-nulia
for k in ${*:-2 3}; do
  NN=ельф-$k
  DD=art/сет-важкий-ельф-картка$k-2026-11-27
  mkdir -p $DD/зони $ARCH/elf-cholovik-z-nulia-do-setu
  for zz in чоботи наручі наплічники пояс; do
    mkdir -p $DD/зони/$zz
    [ -e $DD/зони/$zz/скульпт ] || ln -s $PWD/$Z1/$zz/скульпт $DD/зони/$zz/скульпт
  done
  [ -f $ARCH/elf-cholovik-z-nulia-do-setu/$NN.glb ] || cp $GD/$NN.glb $ARCH/elf-cholovik-z-nulia-do-setu/
  rm -f $DD/4-зони/$NN.blend
  export SET_D=$DD MOD_R=art/ельф-чоловік-з-нуля-2026-11-14 MOD_N=$NN SET_TYP=важка
  export MOD_G=/tmp/claude-1000/set-elf-kartka$k.glb       # проміжний; у гру — після рис
  echo "=== картка $k"
  tools/set_zona.sh чоботи --верх 0.925 2>&1 | tail -3
  tools/set_zona.sh наручі --верх 1.515 --низ 0.782 --глибина-кадру 0.68 2>&1 | tail -3
  tools/set_zona.sh наплічники --низ 1.266 2>&1 | tail -3
  tools/set_zona.sh пояс --верх 1.246 --низ 0.691 2>&1 | tail -3
  TOCHNO=1 tools/rysy_z_nulia.sh $NN 2>&1 | grep -E "РИСИ|‼"
  TOCHNO=1 tools/borody_z_nulia.sh $NN 2>&1 | grep -E "БОРОДИ|‼"
  TOCHNO=1 tools/brovy_z_nulia.sh $NN 2>&1 | grep -E "БРОВИ|‼"
done
echo "СЕТИ ЕЛЬФА ГОТОВІ"
