#!/bin/bash
# Зона важкого сету способом Б (25.11.2026, П-288; порівняння — art/порівняння-способів-2026-11-24):
# кадри всього тіла з 4 боків → лати з еталона на кожному (Qwen-Edit) → зведення за головою →
# виріз зони → Hunyuan3D-2mv → колір з кадрів → set_zona.sh --рамка --річ-за-відстанню.
#   SET_D=… MOD_R=… MOD_N=… [MOD_S=сітка-скульпту.glb|-] [MOD_V=…] [MOD_T=…] [MOD_K=…] MOD_G=… \
#       tools/zona_mv.sh <зона> <еталон.png> [сід]
set -e
cd "$(dirname "$0")/.."
ZN=$1; ET=$2; SD=${3:-9901}
B=~/Програми/blender-5.2.2-linux-x64/blender
PQ=~/Програми/cv-venv/bin/python
PP=~/ComfyUI/venv/bin/python
SITKA=${MOD_S:-$MOD_R/3-сітка/$MOD_N.glb}
[ "$SITKA" = "-" ] && SITKA=${MOD_V:-$MOD_R/6-волосся/$MOD_N.blend}
T=$SET_D/тіло-4
[ -f $T/справа.png ] || $B -b -P tools/blender/kadry_4.py -- $SITKA $T 2>&1 | grep -E "^\[кадри\]|Error"
MV=$SET_D/зони/$ZN/mv
mkdir -p $MV/зв
for BK in спереду ззаду зліва справа; do
  [ "$ZN" = "наручі" ] && [ "$BK" = "зліва" ] && continue
  case $BK in спереду) SF="" ;; ззаду) SF="-ззаду" ;; *) SF="-збоку" ;; esac
  [ -f $MV/ген-$BK-s$SD.png ] || $PQ -u tools/comfyui/ork_znulia_ref.py повне-$ZN$SF $T/$BK.png $MV/ген-$BK $SD --друга $ET | tail -1
  $PP tools/zvesty_kadr.py $T/$BK.png $MV/ген-$BK-s$SD.png $MV/зв/$BK.png
done
VR=$($PP tools/vyriz_zony.py $ZN $MV/зв $MV)
echo "$VR"
VYRIZ=$(echo "$VR" | grep ВИРІЗ | cut -d' ' -f2-)
read LO HI <<< "$(echo "$VR" | grep ЧАСТКИ | cut -d' ' -f2-)"
VIDY=(--спереду $MV/виріз-спереду.png --ззаду $MV/виріз-ззаду.png --справа $MV/виріз-справа.png)
[ "$ZN" = "наручі" ] || VIDY+=(--зліва $MV/виріз-зліва.png)
[ -f $MV/hmv.glb ] || $PQ -u tools/comfyui/hunyuan_mv.py $MV/hmv.glb "${VIDY[@]}" | tail -1
RM=$($B -b -P tools/blender/ramka_4.py -- $SITKA --тіло ${MOD_T:-Тіло} --виріз $VYRIZ --спереду $MV/виріз-спереду.png --скульпт $MV/hmv.glb 2>&1 | grep -E "РАМКА|дотягнуто" | tee /dev/stderr | grep РАМКА | cut -d' ' -f2-)
VYRIZY=$(echo "$VR" | grep БІК | awk '{printf "%s%s:%s:%s:%s:%s", (NR>1?",":""), $2,$3,$4,$5,$6}')
mkdir -p $SET_D/зони/$ZN/скульпт-mv
$B -b -P tools/blender/proektsiia_4.py -- $MV/hmv.glb $SET_D/зони/$ZN/скульпт-mv/pixal.glb "${VIDY[@]}" \
    --текстура 2048 --бокові-запас --рамка $RM --кадр $T/зріст.txt --вирізи "$VYRIZY" 2>&1 | grep -E "без кольору|Error"
read ZR Z0 _ _ < $T/зріст.txt
VERH=$(python3 -c "print(round($Z0+$HI*$ZR,3))"); NYZ=$(python3 -c "print(round($Z0+$LO*$ZR,3))")
DOD=(--низ $NYZ)
[ "$ZN" = "наплічники" ] || DOD+=(--верх $VERH)
SKULPT=скульпт-mv tools/set_zona.sh $ZN "${DOD[@]}" --рамка $RM --річ-за-відстанню 0.006
