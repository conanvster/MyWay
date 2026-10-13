#!/usr/bin/env python3
"""Основи ельфійки й орчихи для 3D — перемальовка Kontext (13.10.2026).

Слово замовника, побачивши прогін броні (`bronia_porivniannia.py`): «мені
сподобалося як генерує kontext — згенеруй за нашими правилами ельфійку і
орчиху для 3D — хочу перегенерувати» → «основи без броні». Kontext тримав
тіло, позу й лису голову e1903 найкраще з наших моделей, тож від погодженої
основи він лише доводить якість кадру.

Правила основи для 3D (усе, що спливало на скані й у Mixamo): лиса голова;
сувора Т-поза, руки горизонтально; кисті долонями вниз, **пальці розведені
й не торкаються** (у e1903/l2002 Mixamo бачив лише великий і вказівний);
**стопи й кісточки окремо з видимою щілиною** (у l2002 скан зліпив стопи);
топлес, лише чорні плавки, босоніж; вид спереду, рівне світле тло.
Пропорції — тієї самої основи: після кадру `elf_markery.py вирівняти`.

    ~/Програми/cv-venv/bin/python -u tools/comfyui/osnova_kontext.py [ельф|орк] [сід…]

Вихід — `wiki/img/test/avatar/kontext-<хто>-s<сід>.png` і `…-рівно.png`,
аркуш з лініями — `art/meshy/2026-10-13/kontext-<хто>-лінії.png`.
"""
import os
import shutil
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import monster3d as m  # noqa: E402
import bronia_porivniannia as bp  # noqa: E402
import elf_markery as mk  # noqa: E402

D = bp.D
KORIN = bp.KORIN
PRAVYLA = (
    "Keep the exact strict T-pose with both arms straight out horizontally at "
    "shoulder height, the exact body proportions, height, limb lengths, crotch "
    "height, face and completely bald head. Open hands palms down with all "
    "five fingers straight and clearly spread apart, gaps between every "
    "finger. Feet slightly apart with a clear gap between the feet and between "
    "the ankles, barefoot. Topless, wearing only plain black briefs. Front "
    "view, the whole body from head to feet in frame, plain light grey studio "
    "background, soft even lighting. High quality photorealistic anatomy "
    "reference photo with realistic skin detail.")
KHTO = {
    "ельф": ("el-lysa-e1903.png",
             "Re-photograph this tall slender bald elf woman with long pointed "
             "elf ears and pale skin as a high quality studio reference. "),
    "орк": ("ork2-lysa-s1303.png",
            "Re-photograph this bald orc woman with her green skin, tusks and "
            "strong build as a high quality studio reference. "),
    # орк-чоловік з референсу замовника 13.10.2026 («зроби орка», Firefly):
    # статура й обличчя — звідти; коси, борода, пояс із сумками — геть
    # (рішення 02.10: волосся й борода окремо), руки з А-пози — у Т-позу.
    "орк-чоловік": (str(KORIN / "art/references/ork/ork-cholovik-ref.png"),
                    "Turn this huge muscular male orc with green skin, tusks and "
                    "pointed ears into a 3D model reference: completely bald head "
                    "with no hair and no braids, clean-shaven with no beard and no "
                    "moustache, no belt, no pouches, no loincloth. Raise his arms "
                    "into a strict T-pose. "),
}
SIDY = [int(a) for a in sys.argv[1:] if a.isdigit()] or [4101, 4102, 4103]


def main():
    vybir = [a for a in sys.argv[1:] if a in KHTO] or list(KHTO)
    arkushi = Path(KORIN / "art/meshy/2026-10-13")
    m.free()
    for khto in vybir:
        osnova, opys = KHTO[khto]
        kadr = m.stage(str(osnova if os.path.isabs(osnova) else D / osnova))
        bp.KONTEXT_ = opys + PRAVYLA
        vyhody = []
        for seed in SIDY:
            g = bp.graf_kontext(kadr, kadr, seed, "osnova_kontext")
            # одна опорна картинка: другий ReferenceLatent геть
            g["9"]["inputs"]["conditioning"] = ["8", 0]
            for k in ("14", "15", "16", "18"):
                g.pop(k)
            g["7"]["inputs"]["text"] = opys + PRAVYLA
            done = m.run(g)
            out = done["outputs"]["13"]["images"][-1]
            kudy = D / ("kontext-%s-s%d.png" % (khto, seed))
            shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"], out["filename"]), kudy)
            print("готово", kudy.name, flush=True)
            vyhody.append(kudy)
        if os.path.isabs(osnova):
            continue   # референс не основа: ліній пропорцій немає з чим рівняти
        osn = mk.mirky(D / osnova)
        rivni = [mk.vyrivniaty(v, osn) for v in vyhody]
        mk.OSNOVA = D / osnova
        mk.arkush(str(arkushi / ("kontext-%s-лінії.png" % khto)), [str(r) for r in rivni])
    m.free()


if __name__ == "__main__":
    main()
