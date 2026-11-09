#!/usr/bin/env bash
# ланцюжок: риг → суглоби замовника → центрування → ваги → експорт
set -e
cd /home/alex/гра-lineage
P=art/орк-пілот-2026-11-09; B=~/Програми/blender-5.2.2-linux-x64/blender; G=game/models/own/avatary/pilot-b-ork-pilot
R=A_TPose,Crouch_Fwd_Loop,Idle_Loop,Jump_Start,Sitting_Idle_Loop,Sprint_Loop,Sword_Attack,Walk_Loop
for v in topless lysyi; do
  echo "== $v"
  $B -b $P/v3/pilot.blend -P tools/blender/rig_sitky.py -- $P/3d-$v/pixal.glb $PWD/$P/rig-pixal/орк-$v-a.blend --граней 150000 --пальці-сітки 2>&1 | grep -E "риг сітки\] (сітка|пальці [lr]: великий)|Error|Traceback"
  $B -b $P/rig-pixal/орк-$v-a.blend -P tools/blender/perenesty_kistky.py -- $PWD/$P/skelet-vruchnu4.blend $PWD/$P/rig-pixal/орк-$v-b.blend 2>&1 | grep -E "перенесення|Error|Traceback"
  $B -b $P/rig-pixal/орк-$v-b.blend -P tools/blender/skelet_tiunynh.py -- $PWD/$P/rig-pixal/орк-$v-c.blend 2>&1 | grep -E "тюнінг\] →|Error|Traceback"
  $B -b $P/rig-pixal/орк-$v-c.blend -P tools/blender/vagy_z_ruchnoho.py -- $PWD/$P/rig-pixal/орк-$v.blend 2>&1 | grep -E "шви|Error|Traceback"
  $B -b $P/rig-pixal/орк-$v.blend -P tools/blender/pilot_eksport.py -- $G/орк-$v.glb --рухи $R 2>&1 | grep -E "пілот\]|Error"
done
cd game && timeout 300 godot --headless --import >/dev/null 2>&1
echo ГОТОВО
