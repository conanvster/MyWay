#!/usr/bin/env bash
# Риси обличчя (12 форм-ключів, як у людини-жінки) для моделей «з нуля» (19.11.2026, план 15.11
# крок 3; слово замовника 14.11: «таку ж кількість налаштувань для усих як у жінки людини»).
# Спершу маски й точки обличчя: tools/blender/maski_z_nulia.py (art/маски-з-нуля-2026-11-19/…/точки.npy).
#   tools/rysy_z_nulia.sh [фільтр назви моделі]
# Рядок: тека-в-грі|модель|джерело .blend|ключі pilot_eksport.py
set -e
cd "$(dirname "$0")/.."
B=~/Програми/blender-5.2.2-linux-x64/blender
A=game/models/own/avatary
SPYSOK="lyudyna-cholovik-z-nulia|людина|art/сет-важкий-людина-2026-11-19/4-зони/людина.blend|--колір-вершин під_одяг
lyudyna-cholovik-z-nulia|людина-2|art/людина-чоловік-з-нуля-2026-11-14/6-волосся/людина-2.blend|
lyudyna-cholovik-z-nulia|людина-3|art/людина-чоловік-з-нуля-2026-11-14/6-волосся/людина-3.blend|
elf-cholovik-z-nulia|ельф|art/ельф-чоловік-з-нуля-2026-11-14/6-волосся/ельф.blend|
elf-cholovik-z-nulia|ельф-2|art/ельф-чоловік-з-нуля-2026-11-14/6-волосся/ельф-2.blend|
elf-cholovik-z-nulia|ельф-3|art/ельф-чоловік-з-нуля-2026-11-14/6-волосся/ельф-3.blend|
elfiika-z-nulia|ельфійка|art/ельфійка-з-нуля-2026-11-12/6-волосся/ельфійка.blend|
elfiika-z-nulia|ельфійка-2|art/ельфійка-з-нуля-2026-11-12/6-волосся/ельфійка-2.blend|
elfiika-z-nulia|ельфійка-3|art/ельфійка-з-нуля-2026-11-12/6-волосся/ельфійка-3.blend|
ork-z-nulia|орк|art/сет-важкий-орк-2026-11-12/4-зони/орк.blend|--колір-вершин під_одяг
ork-z-nulia|орк-2|art/орк-з-нуля-2026-11-11/6-волосся/орк-2.blend|
ork-z-nulia|орк-3|art/орк-з-нуля-2026-11-11/6-волосся/орк-3.blend|
orchykha-z-nulia|орчиха-3|art/орчиха-з-нуля-2026-11-12/6-волосся/орчиха-3.blend|
orchykha-z-nulia|орчиха-4|art/орчиха-з-нуля-2026-11-12/6-волосся/орчиха-4.blend|
orchykha-z-nulia|орчиха-2|art/орчиха-з-нуля-2026-11-12/6-волосся/орчиха-2.blend|"
echo "$SPYSOK" | while IFS='|' read -r teka model dzherelo kliuchi; do
    [ -n "${1:-}" ] && [[ "$model" != *"$1"* ]] && continue
    [ -n "${TOCHNO:-}" ] && [ "$model" != "$1" ] && continue   # TOCHNO=1 — лише ця модель
    tochky=art/маски-з-нуля-2026-11-19/$teka-$model/точки.npy
    [ -f "$tochky" ] || { echo "‼ $model: немає $tochky — спершу maski_z_nulia.py"; continue; }
    vyhid=$(dirname "$dzherelo")/../7-риси/$model.blend
    mkdir -p "$(dirname "$vyhid")"
    echo "== $model"
    # RYSY_LYSHE_EKSPORT=1 — ключі вже в 7-риси/*.blend, лише вивантажити в гру
    [ -n "${RYSY_LYSHE_EKSPORT:-}" ] && [ -f "$vyhid" ] || $B -b --factory-startup -P tools/blender/elf_rysy.py -- "$dzherelo" "$tochky" "$PWD/$vyhid" --з-нуля 2>&1 \
        | grep -E "^\[риси\]|Traceback|^Error" -A3
    # shellcheck disable=SC2086
    $B -b "$vyhid" -P tools/blender/pilot_eksport.py -- $A/$teka/$model.glb --з-формами $kliuchi 2>&1 \
        | grep -E "пілот\]|Traceback|^Error" -A3 || true
done
(cd game && timeout 300 godot --headless --import >/dev/null 2>&1)
echo РИСИ ГОТОВО
