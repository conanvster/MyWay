#!/bin/bash
# Гуманоїд бестіарію → ігрова модель з рухами (П-297, 28.11.2026; спосіб з пілоту — Hunyuan3D-2mv
# з Т-ряду аркуша + проєкція аркуша, TRELLIS.2 лише для зброї).
#   tools/monstr_3d.sh <вид> [<вид> …]
# Швидше за пілот: лише Т-ряд; кроки на відеокарті (сітка, зброя — через gpu-broker) ідуть по черзі,
# а процесорна частина виду (спрощення, проєкція, запікання, скелет і рухи) — паралельно з
# відеокартою наступного. Наприкінці кожного: кадри рухів (огляд) і модель у грі
# (tools/monstr_v_hru.py — стиск, models/own/<вид>.glb, mobs.json). Готове не переробляє.
# Тека виду: art/monsters/<вид>-3d/3d/ (поза git).
set -o pipefail
cd "$(dirname "$0")/.."
PY=~/Програми/cv-venv/bin/python
KOR="$PWD"

# крок: <файл, що має з'явитися> <команда…>; вивід — у журнал виду
krok() { local f="$1"; shift; [ -f "$f" ] && return 0; "$@" >> "$J" 2>&1; [ -f "$f" ] || { echo "‼ збій: $f" >> "$J"; return 1; }; }

cpu_chastyna() {
  local v="$1" O="art/monsters/$1-3d/3d" A="art/monsters/$1-3d/аркуш"
  J="$O/журнал.txt"; : > "$J"
  krok "$O/гра.glb" blender -b -P tools/blender/sproshchennia.py -- "$O/hmv-Т.glb" "$O/гра.glb" --граней 40000 &&
  krok "$O/колір.glb" blender -b -P tools/blender/proektsiia_4.py -- "$O/hmv-Т.glb" "$O/колір.glb" \
    --спереду "$A/Т-0.png" --зліва "$A/Т-90.png" --ззаду "$A/Т-180.png" --текстура 2048 \
    --бокові-запас --ерозія 6 --мін-кут 0.35 &&
  krok "$O/запечено.glb" blender -b -P tools/blender/zapikannia_monstr.py -- "$O/колір.glb" "$O/гра.glb" "$O/запечено.glb" &&
  krok "$O/манера.json" $PY tools/monstr_manera.py "$v" "$O/манера.json" &&
  krok "$O/модель.glb" blender -b -P tools/blender/monstr_rig.py -- "$O/запечено.glb" "$O/модель.glb" \
    --манера "$O/манера.json" --граней 999999 $( [ -s "$O/зброя/зброя.json" ] && echo --зброя "$O/зброя/зброя.json" ) &&
  krok "$O/рухи.png" ~/gpu-broker/bin/gpu run --мб 1500 --мета "кадри рухів $v" -- \
    blender -b "$O/модель.blend" -P tools/blender/monstr_kadry.py -- "$KOR/$O/рухи.png" &&
  python3 tools/monstr_v_hru.py "$v" "$O/модель.glb" >> "$J" 2>&1 || { echo "‼ $v: збій — $J"; return 1; }
  echo "ГОТОВО $v"
  grep -E 'спрощення\]|без кольору|IoU|запікання\]|"манера"|монстр-риг\] (зріст|хвіст|поли|ваги|зброя|‼)|Traceback|у гру\]' "$J" | sed "s/^/  $v: /"
}

pids=()
for v in "$@"; do
  O="art/monsters/$v-3d/3d"; A="art/monsters/$v-3d/аркуш"; mkdir -p "$O"
  echo "── $v: сітка й зброя (відеокарта)"
  # диспетчер буває віддає 502 (ComfyUI ще піднімається) — до 3 спроб
  for t in 1 2 3; do
    [ -f "$O/hmv-Т.glb" ] && break
    [ "$t" -gt 1 ] && { echo "  повтор $t"; ~/gpu-broker/bin/gpu status 2>&1 | grep -E 'comfyui|Черга'; sleep 30; }
    $PY -u tools/comfyui/hunyuan_mv.py "$O/hmv-Т.glb" --спереду "$A/Т-0.png" \
      --зліва "$A/Т-90.png" --ззаду "$A/Т-180.png" --сід 1 --роздільність 384 2>&1 | tail -2
  done
  [ -f "$O/hmv-Т.glb" ] || { echo "‼ $v: немає сітки"; continue; }
  [ -f "$O/зброя/зброя.json" ] || $PY -u tools/comfyui/zbroia_monstra.py "$v" "$O/зброя" 2>&1 | grep -E 'зброя «|готово'
  cpu_chastyna "$v" &
  pids+=($!)
done
for p in "${pids[@]}"; do wait "$p"; done
echo ВСЕ
