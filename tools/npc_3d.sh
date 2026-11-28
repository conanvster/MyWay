#!/bin/bash
# 3D-моделі NPC з аркушів-референсів (28.11.2026, слово замовника: «зроби 3D моделі для гри, по
# закінченню заміни ними NPC в грі»). Аркуш — art/npc/<ремесло>-<стать>/аркуш/ (npc_arkush.py).
#   1. форма — Hunyuan3D-2mv з Т-ряду: Т-0 спереду, Т-90 зліва (профіль показує ліву сторону:
#      обличчя вліво кадру = камера з +X, як «зліва» в kadry_4.py), Т-180 ззаду;
#   2. колір — proektsiia_4.py з тих самих кадрів (рівне світло аркуша; --ерозія 2 — без білого
#      краю силуету на боках); спрощення до ~40 тис. (npc_sproshchennia.py, голові — більше текстури);
#   2б. обличчя — виріз голови з Т-0, Qwen-Edit відновлює різкість (npc_oblychchia.py) → запікання
#      спереду з м'яким краєм (tools/blender/npc_oblychchia.py);
#   3. скелет — avatar_build.py: скан на скелеті манекена гравця, ваги з його тіла — рухи UAL1
#      (Idle, Idle_Talking) працюють, як на нинішніх NPC.
# Вихід: game/models/own/avatary/npc/<лат-назва>/<лат-назва>.gltf (+ кадри перевірки в art/npc/<…>/3d/кадри).
#   tools/npc_3d.sh "коваль-чоловік" ["майстер магії-жінка" …]   (без аргументів — усі 14)
set -e
cd "$(dirname "$0")/.."
B=~/Програми/blender-5.2.2-linux-x64/blender
PY=~/Програми/cv-venv/bin/python
GPU=~/gpu-broker/bin/gpu
if [ $# -eq 0 ]; then
  set -- art/npc/*/аркуш
  set -- "${@#art/npc/}"; set -- "${@%/аркуш}"
fi
for kl in "$@"; do
  A="art/npc/$kl/аркуш"; D="art/npc/$kl/3d"
  [ -f "$A/Т-0.png" ] || { echo "‼ $kl: немає аркуша"; continue; }
  mkdir -p "$D"
  lat=$($PY -c "
import sys
t={'а':'a','б':'b','в':'v','г':'h','ґ':'g','д':'d','е':'e','є':'ie','ж':'zh','з':'z','и':'y','і':'i','ї':'i','й':'i','к':'k','л':'l','м':'m','н':'n','о':'o','п':'p','р':'r','с':'s','т':'t','у':'u','ф':'f','х':'kh','ц':'ts','ч':'ch','ш':'sh','щ':'shch','ь':'','ю':'iu','я':'ia',' ':'_','-':'-'}
print(''.join(t.get(c,c) for c in sys.argv[1].lower()))" "$kl")
  echo "=== $kl → game/models/own/avatary/npc/$lat.gltf"
  if [ ! -f "$D/forma.glb" ]; then
    # NPC_SID — інший сід, NPC_BEZ_BOKU=1 — без профілю (Hunyuan вигадував вуха й хвіст крамарям)
    BIK=(--зліва "$A/Т-90.png"); [ -n "$NPC_BEZ_BOKU" ] && BIK=()
    $PY -u tools/comfyui/hunyuan_mv.py "$PWD/$D/forma.glb" \
      --спереду "$A/Т-0.png" "${BIK[@]}" --ззаду "$A/Т-180.png" --сід ${NPC_SID:-1} | tail -1
  fi
  if [ ! -f "$D/kolir.glb" ]; then
    $B -b -P tools/blender/proektsiia_4.py -- "$PWD/$D/forma.glb" "$PWD/$D/kolir.glb" \
      --спереду "$PWD/$A/Т-0.png" --зліва "$PWD/$A/Т-90.png" --ззаду "$PWD/$A/Т-180.png" \
      --бокові-запас --ерозія 2 2>&1 | grep -E "‼|Error|готово|→" | tail -3
  fi
  if [ ! -f "$D/hra.glb" ]; then
    $B -b -P tools/blender/npc_sproshchennia.py -- "$PWD/$D/kolir.glb" "$PWD/$D/hra.glb" 40000 2>&1 | grep "спрощення"
  fi
  # чисте обличчя: виріз голови з Т-0 → Qwen-Edit (різкість без зсуву рис) → на голову спереду
  if [ ! -f "$D/обличчя.png" ]; then
    $PY -u tools/comfyui/npc_oblychchia.py "$kl" | tail -1
  fi
  if [ ! -f "$D/hra-o.glb" ]; then
    $B -b -P tools/blender/npc_oblychchia.py -- "$PWD/$D/hra.glb" "$PWD/$D/hra-o.glb" \
      "$PWD/$A/Т-0.png" "$PWD/$D/обличчя.png" $(cat "$D/обличчя.txt") 2>&1 | grep -E "\[обличчя\] рамка|Error|Traceback"
  fi
  # --кисті-скану: чоботи й рукавиці з аркуша, а не босі ступні й кисті манекена;
  # --перед-скану 1: перед сітки Hunyuan завжди той самий, а пошук за ступнями плутають каблуки
  mkdir -p "game/models/own/avatary/npc/$lat" "$D/кадри"
  $B -b --factory-startup -P tools/blender/avatar_build.py -- --кисті-скану --перед-скану 1 \
    "$PWD/$D/hra-o.glb" "$PWD/game/models/own/avatary/npc/$lat/$lat.gltf" "$PWD/$D/кадри" 2>&1 | grep -E "‼|Error|Traceback|готово|→" | tail -4
done
echo "NPC 3D ГОТОВО"
