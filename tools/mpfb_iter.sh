#!/usr/bin/env bash
# Ітерація аватара MPFB: збірка з підбором і проєкцією → рендер → оцінка.
#   ./tools/mpfb_iter.sh <N> [ще доводи mpfb_avatar.py]
# Змінні (типово — людина-чоловік): D — тека кадрів, REF — кадр спереду
# (маска — maska-$REF.png), BIK / ZAD — кадри збоку й ззаду (порожні — без
# них), OUT — тека ітерацій.
# Оцінка з трьох боків (замовник 02.10.2026: «ненадали вигляду з боку та з
# заду і не порівняли»): спереду — avatar_ocinka2.py, збоку й ззаду —
# avatar_ocinka_vyd.py; «разом» — середнє трьох підсумків.
set -euo pipefail
cd "$(dirname "$0")/.."
n="$1"; shift
D="${D:-wiki/img/test/avatar/mpfb2}"
R="${REF:-plavky-sym-s411}"
BIK="${BIK-bik-sym-s922}"
ZAD="${ZAD-zad-sym-s911}"
o="${OUT:-art/monsters/аватар-людина-чоловік-v1-3d/mpfb}"
mkdir -p "$o/$n"   # своя тека: текстури всіх ітерацій звуться однаково
pidbir=(--підбір "$D/maska-$R.png")
vydy=()
if [ -n "$BIK" ] && [ -n "$ZAD" ]; then
    pidbir+=("$D/maska-$BIK.png")
    vydy=(--види "$D/$BIK.png" "$D/maska-$BIK.png" "$D/$ZAD.png" "$D/maska-$ZAD.png")
fi
blender -b -P tools/blender/mpfb_avatar.py -- \
    "${pidbir[@]}" "${vydy[@]}" \
    --референс "$D/$R.png" "$D/maska-$R.png" "$@" \
    "$o/$n/avatar.gltf" "$o/$n/kadry" 2>&1 \
    | grep -E '^\[(mpfb|підбір|обличчя|контури)\]|‼|Traceback|Error' | grep -vE 'крок 0\.(25|12|06)|кісток|сітки|модифікатори' || true
for vyd in перед бік зад; do
    [ "$vyd" != перед ] && [ -z "$BIK" ] && continue
    sfx=$([ "$vyd" = перед ] && echo "" || echo "-$vyd")
    blender -b --factory-startup -P tools/blender/avatar_render.py -- \
        "$o/$n/avatar.gltf" "$o/render-$n$sfx.png" "$vyd" --т-поза 2>&1 \
        | grep -E 'Traceback|Error' || true
    [ -f "$o/render-$n$sfx.png" ] || { echo "‼ рендер $n ($vyd) не вийшов — оцінки нема"; exit 1; }
done
pered=$(~/Програми/cv-venv/bin/python tools/avatar_ocinka2.py "$D/$R.png" \
    "$D/maska-$R.png" "$o/render-$n.png" "$o/arkush-$n.png")
echo "спереду: $pered" | tee -a "$o/journal.txt"
[ -z "$BIK" ] && exit 0
bik=$(~/Програми/cv-venv/bin/python tools/avatar_ocinka_vyd.py "$D/$BIK.png" \
    "$D/maska-$BIK.png" "$o/render-$n-бік.png" "$o/arkush-$n-бік.png" \
    "$D/maska-$R.png" "$D/tochky-ref.npy" --бік)
zad=$(~/Програми/cv-venv/bin/python tools/avatar_ocinka_vyd.py "$D/$ZAD.png" \
    "$D/maska-$ZAD.png" "$o/render-$n-зад.png" "$o/arkush-$n-зад.png" \
    "$D/maska-$R.png" "$D/tochky-ref.npy")
echo "збоку: $bik" | tee -a "$o/journal.txt"
echo "ззаду: $zad" | tee -a "$o/journal.txt"
python3 - "$pered" "$bik" "$zad" <<'E' | tee -a "$o/journal.txt"
import json, sys
p = [json.loads(a)["підсумок"] for a in sys.argv[1:4]]
print("разом (%s): %.3f" % (", ".join("%.3f" % x for x in p), sum(p) / 3))
E
