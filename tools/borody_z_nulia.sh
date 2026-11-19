#!/usr/bin/env bash
# Бороди чоловіків «з нуля» (19.11.2026, план 15.11 крок 6): до повної — «коротка» і «вуса»
# (вуса — за точками обличчя maski_z_nulia.py). Додаються до 7-риси/*.blend (зачіски й риси
# вже там), далі вивантаження в гру: RYSY_LYSHE_EKSPORT=1 tools/rysy_z_nulia.sh.
#   tools/borody_z_nulia.sh
set -e
cd "$(dirname "$0")/.."
B=~/Програми/blender-5.2.2-linux-x64/blender
for row in "lyudyna-cholovik-z-nulia|людина|art/людина-чоловік-з-нуля-2026-11-14" \
           "lyudyna-cholovik-z-nulia|людина-2|art/людина-чоловік-з-нуля-2026-11-14" \
           "lyudyna-cholovik-z-nulia|людина-3|art/людина-чоловік-з-нуля-2026-11-14" \
           "elf-cholovik-z-nulia|ельф|art/ельф-чоловік-з-нуля-2026-11-14" \
           "elf-cholovik-z-nulia|ельф-2|art/ельф-чоловік-з-нуля-2026-11-14" \
           "elf-cholovik-z-nulia|ельф-3|art/ельф-чоловік-з-нуля-2026-11-14" \
           "ork-z-nulia|орк|art/сет-важкий-орк-2026-11-12" \
           "ork-z-nulia|орк-2|art/орк-з-нуля-2026-11-11" \
           "ork-z-nulia|орк-3|art/орк-з-нуля-2026-11-11"; do
    IFS='|' read -r teka model art_d <<< "$row"
    blend=$art_d/7-риси/$model.blend
    echo "== $model"
    $B -b "$blend" -P tools/blender/ork_volossia.py -- "$PWD/$blend" --лише-бороди \
        --точки art/маски-з-нуля-2026-11-19/$teka-$model/точки.npy 2>&1 \
        | grep -E "волосся\] Борода|Traceback|^Error" -A3 || true
done
echo БОРОДИ ГОТОВО
