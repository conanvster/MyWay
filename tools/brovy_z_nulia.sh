#!/usr/bin/env bash
# Брови ×4 і вії ×3 сітками-картками для моделей «з нуля» (19.11.2026, план 15.11 крок 4;
# замовник вибрав спосіб (а) — «роби а»). Після рис і борід: 7-риси/<модель>.blend →
# 8-брови/<модель>.blend (брови затерто в текстурі, сітки Брови-*/Вії-*) → GLB у гру.
#   tools/brovy_z_nulia.sh [фільтр назви моделі]
# Таблиця моделей — та сама, що в tools/rysy_z_nulia.sh.
set -e
cd "$(dirname "$0")/.."
B=~/Програми/blender-5.2.2-linux-x64/blender
A=game/models/own/avatary
sed -n '/^SPYSOK="/,/"$/p' tools/rysy_z_nulia.sh | sed 's/^SPYSOK="//; s/"$//' | while IFS='|' read -r teka model dzherelo kliuchi; do
    [ -n "${1:-}" ] && [[ "$model" != *"$1"* ]] && continue
    [ -n "${TOCHNO:-}" ] && [ "$model" != "$1" ] && continue   # TOCHNO=1 — лише ця модель
    tochky=art/маски-з-нуля-2026-11-19/$teka-$model/точки.npy
    rysy=$(dirname "$dzherelo")/../7-риси/$model.blend
    vyhid=$(dirname "$dzherelo")/../8-брови/$model.blend
    [ -f "$tochky" ] && [ -f "$rysy" ] || { echo "‼ $model: немає $tochky або $rysy"; continue; }
    mkdir -p "$(dirname "$vyhid")"
    echo "== $model"
    $B -b --factory-startup -P tools/blender/brovy_kartky.py -- "$rysy" "$tochky" "$PWD/$vyhid" \
        > "${vyhid%.blend}.log" 2>&1 || true
    grep -E "^\[брови\] (брови затерто|‼)" "${vyhid%.blend}.log" || true
    if grep -qE "Traceback|^Error:" "${vyhid%.blend}.log"; then
        grep -E "Traceback|^Error:" -A4 "${vyhid%.blend}.log"; echo "‼ $model: ВПАЛО"; continue
    fi
    # shellcheck disable=SC2086
    $B -b "$vyhid" -P tools/blender/pilot_eksport.py -- $A/$teka/$model.glb --з-формами $kliuchi 2>&1 \
        | grep -E "пілот\]|Traceback|^Error" -A3 || true
done
(cd game && timeout 300 godot --headless --import >/dev/null 2>&1)
echo БРОВИ ГОТОВО
