#!/usr/bin/env python3
"""Чисті основи орків: Kontext трьома точковими діями + тон шкіри (09.11.2026).

Рецепт з `lysyi_pidbir.py` (пам'ять: feedback_flux_bald_beardless): Kontext
з «green orc skin» тримає вуха й ікла орка, без «orc» — робить людину;
кислотний зелений — назад перенесенням тону з вхідного кадру
(`tools/kolir_shkiry.py`). Дії: борода й вуса → голова → залишки (хутро,
ремінці, ланцюжки, клапті, сторонні предмети на тлі).

    ~/Програми/cv-venv/bin/python -u tools/comfyui/ork_lysyi_kontext.py <тека> <кадр…>
→ <тека>/<кадр>-k1.png, -k2.png, -k3.png, фінал <кадр>-chysto.png, аркуш чисті-основи.png
"""
import os
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster3d as m  # noqa: E402
import rasy_kontext as rk  # noqa: E402

TEKA = Path(sys.argv[1])
KADRY = [Path(a) for a in sys.argv[2:]]
SID = 5101
LYSHYTY = (" Keep everything else exactly the same: same face, same pointed ears, same "
           "tusks, same body, same pose, same black briefs, same background, same lighting.")
DII = [
    "Remove his beard and mustache completely, so his chin, jaw, cheeks and upper lip "
    "are smooth bare green orc skin." + LYSHYTY,
    "Shave his head completely bald, so the whole scalp, the top and the back of his "
    "head and the temples are smooth bare green orc skin." + LYSHYTY,
    "Remove all fur, straps, cords, chains, braids, cloth scraps, bracelets and "
    "jewelry from his body, so his shoulders, arms, wrists, chest, hips and legs are "
    "smooth bare green orc skin, and remove any objects, statues and weapons from the "
    "background, leaving a plain empty grey studio backdrop. He wears only the plain "
    "black briefs." + LYSHYTY,
]


def zberehty(done, kudy):
    out = [o for v in done["outputs"].values() for o in v.get("images", [])][-1]
    shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"], out["filename"]), kudy)


def main():
    TEKA.mkdir(parents=True, exist_ok=True)
    m.free()
    for k in KADRY:
        fin = TEKA / (k.stem + "-chysto.png")
        if fin.exists():
            print("є", fin, flush=True)
            continue
        poperedn = k
        for i, dia in enumerate(DII, 1):
            kudy = TEKA / ("%s-k%d.png" % (k.stem, i))
            if not kudy.exists():
                rk.PROMT = dia
                zberehty(m.run(rk.graf(m.stage(str(poperedn)), SID, "lysyi_k%d" % i)), kudy)
            poperedn = kudy
        subprocess.run([sys.executable, str(Path(m.ROOT) / "tools" / "kolir_shkiry.py"),
                        str(poperedn), str(k), str(fin)], check=True)
        print("готово", fin, flush=True)
    m.free()
    s = 360
    n = len(KADRY)
    stovp = 4
    ryadiv = (n + stovp - 1) // stovp
    o = Image.new("RGB", (s * stovp * 2, ryadiv * (s + 28)), (24, 24, 24))
    d = ImageDraw.Draw(o)
    sh = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 14)
    for i, k in enumerate(KADRY):
        x0, y0 = (i % stovp) * 2 * s, (i // stovp) * (s + 28)
        for j, f in enumerate((k, TEKA / (k.stem + "-chysto.png"))):
            im = Image.open(f).convert("RGB")
            im.thumbnail((s, s))
            o.paste(im, (x0 + j * s, y0))
        d.text((x0 + 6, y0 + s + 4), k.stem[:48], fill=(230, 220, 200), font=sh)
    o.save(TEKA / "чисті-основи.png")
    print("аркуш", TEKA / "чисті-основи.png", flush=True)


if __name__ == "__main__":
    main()
