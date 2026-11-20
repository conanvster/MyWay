#!/bin/bash
# Важкий сет людини-жінки на картки 2 і 3 (20.11.2026, слово замовника: «у людини жінки коли
# вдягаєш бронь нічого не вдягається»): ті самі скульпти, що й на картці 1 (пілот Б), —
# кожна зона заново суміщується з тілом своєї картки; далі спідниця до талії й вивантаження.
#   tools/set_zhinka_kartky.sh [2] [3]
set -e
cd "$(dirname "$0")/.."
B=~/Програми/blender-5.2.2-linux-x64/blender
Z1=art/сет-важкий-людина-жінка-2026-11-20/зони
ARCH=art/_архів-аватарів-2026-11-20
for k in "${@:-2 3}"; do
  case $k in
    2) RR=art/аватари-2026-11-11/людина-жінка; NN=людина-жінка; GG=game/models/own/avatary/pilot-c-zhinka/людина-жінка.glb ;;
    3) RR=art/аватари-2026-11-11/людина-жінка-2; NN=людина-жінка-2; GG=game/models/own/avatary/pilot-c-zhinka-2/людина-жінка-2.glb ;;
    *) echo "картка $k?"; exit 1 ;;
  esac
  DD=art/сет-важкий-людина-жінка-картка$k-2026-11-20
  mkdir -p $DD/зони
  for zz in чоботи наручі наплічники пояс; do
    mkdir -p $DD/зони/$zz
    for ss in скульпт скульпт2 скульпт4; do
      [ -e $DD/зони/$zz/$ss ] || [ ! -d $Z1/$zz/$ss ] || ln -s $PWD/$Z1/$zz/$ss $DD/зони/$zz/$ss
    done
  done
  rm -f $DD/4-зони/$NN.blend
  mkdir -p $ARCH/$(basename $(dirname $GG))-do-setu
  [ -f $ARCH/$(basename $(dirname $GG))-do-setu/$(basename $GG) ] || cp $GG $ARCH/$(basename $(dirname $GG))-do-setu/
  export SET_D=$DD MOD_R=$RR MOD_N=$NN MOD_V=$RR/риси/риси.blend MOD_S=- MOD_T=Human MOD_K=--з-формами SET_TYP=важка
  export MOD_G=/tmp/claude-1000/set-kartka$k.glb
  echo "=== картка $k"
  SKULPT=скульпт4 tools/set_zona.sh чоботи --верх 0.837
  SKULPT=скульпт tools/set_zona.sh наручі --верх 1.457 --низ 0.891 --глибина-кадру 0.68
  SKULPT=скульпт2 tools/set_zona.sh наплічники --низ 1.001
  SKULPT=скульпт2 tools/set_zona.sh пояс --верх 1.111 --низ 0.628
  $B -b $DD/4-зони/$NN.blend -P tools/blender/spidnytsia_talia.py 2>&1 | grep "спідниця"
  $B -b $DD/4-зони/$NN.blend -P tools/blender/pilot_eksport.py -- $GG --з-формами --колір-вершин під_одяг 2>&1 | grep -E "пілот|Error"
done
(cd game && timeout 300 godot --headless --import >/dev/null 2>&1) || true
echo "СЕТИ КАРТОК ГОТОВІ"
