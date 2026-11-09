#!/usr/bin/env bash
# Чисті основи орків → 3D у грі (09.11.2026): Pixal3D, риг (refit + пальці
# сітки), суглоби замовника (skelet-vruchnu4), центрування, ваги, експорт.
#   tools/ork_osnovy_3d.sh <назва>=<кадр.png> …
set -e
cd "$(dirname "$0")/.."
P=art/орк-пілот-2026-11-09; B=~/Програми/blender-5.2.2-linux-x64/blender; G=game/models/own/avatary/pilot-b-ork-pilot
PY=~/Програми/cv-venv/bin/python
R=A_TPose,Crouch_Fwd_Loop,Idle_Loop,Jump_Start,Sitting_Idle_Loop,Sprint_Loop,Sword_Attack,Walk_Loop
O=art/орк-чоловік-основи-2026-11-09/3d
for para in "$@"; do
  n=${para%%=*}; k=${para#*=}
  echo "== $n ← $k"
  mkdir -p $O/$n
  [ -f $O/$n/pixal.glb ] || $PY -u tools/comfyui/ork_pilot_3d.py "$k" $O/$n pixal | grep -E "готово|Error"
  $B -b $P/v3/pilot.blend -P tools/blender/rig_sitky.py -- $O/$n/pixal.glb $PWD/$O/$n/a.blend --граней 150000 --пальці-сітки 2>&1 | grep -E "риг сітки\] (сітка|пальці [lr]: великий)|Error|Traceback"
  $B -b $O/$n/a.blend -P tools/blender/perenesty_kistky.py -- $PWD/$P/skelet-vruchnu4.blend $PWD/$O/$n/b.blend 2>&1 | grep -E "перенесення|Error|Traceback"
  $B -b $O/$n/b.blend -P tools/blender/skelet_tiunynh.py -- $PWD/$O/$n/c.blend 2>&1 | grep -E "тюнінг\] →|Error|Traceback"
  $B -b $O/$n/c.blend -P tools/blender/vagy_z_ruchnoho.py -- $PWD/$O/$n/орк.blend 2>&1 | grep -E "шви|Error|Traceback"
  $B -b $O/$n/орк.blend -P tools/blender/pilot_eksport.py -- $G/орк-$n.glb --рухи $R 2>&1 | grep -E "пілот\]|Error"
  $B -b $O/$n/орк.blend -P tools/blender/skelet_render.py -- $O/$n/skelet >/dev/null 2>&1 || true
done
(cd game && timeout 300 godot --headless --import >/dev/null 2>&1)
echo ГОТОВО
