#!/usr/bin/env bash
# Бороди чоловіків «з нуля» (19.11.2026, план 15.11 крок 6): до повної — «коротка» і «вуса»
# (вуса — за точками обличчя maski_z_nulia.py). Додаються до 7-риси/*.blend (зачіски й риси
# вже там), далі вивантаження в гру: RYSY_LYSHE_EKSPORT=1 tools/rysy_z_nulia.sh.
#   tools/borody_z_nulia.sh [фільтр назви моделі]
set -e
cd "$(dirname "$0")/.."
B=~/Програми/blender-5.2.2-linux-x64/blender
# моделі — з таблиці tools/rysy_z_nulia.sh (лише чоловіки); [фільтр назви моделі]
# (20.11.2026: людина v1 тепер із сетом — 7-риси в теці сету, як орк v1)
sed -n '/^SPYSOK="/,/"$/p' tools/rysy_z_nulia.sh | sed 's/^SPYSOK="//; s/"$//' | while IFS='|' read -r teka model dzherelo kliuchi; do
    case $teka in lyudyna-cholovik*|elf-cholovik*|ork-z-nulia) ;; *) continue;; esac
    [ -n "${1:-}" ] && [[ "$model" != *"$1"* ]] && continue
    [ -n "${TOCHNO:-}" ] && [ "$model" != "$1" ] && continue   # TOCHNO=1 — лише ця модель
    art_d=$(dirname "$(dirname "$dzherelo")")
    blend=$art_d/7-риси/$model.blend
    echo "== $model"
    $B -b "$blend" -P tools/blender/ork_volossia.py -- "$PWD/$blend" --лише-бороди \
        --точки art/маски-з-нуля-2026-11-19/$teka-$model/точки.npy 2>&1 \
        | grep -E "волосся\] Борода|Traceback|^Error" -A3 || true
done
echo БОРОДИ ГОТОВО
