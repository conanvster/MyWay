#!/usr/bin/env python3
"""Три проекції орчихи v3 — менш мультяшно, усі наші моделі (14.10.2026).

Слово замовника про аркуш `proektsii.py орчиха-v3`: «єдине зображення більш
менш — збоку-flux-cn-s6102.png, інші дуже мультяшні — спробуй зробити те саме
усіма доступними моделями». У s6102 шкіра приглушена, без «пластику». Тут ті
самі джерела (`<проекція>-dzherelo.png`), кожна проекція — чотири способи по
два сіди:
  * cn-g2    — FLUX dev з нуля + ControlNet (Canny), guidance 2,0 (нижча сила
               промпту у FLUX дає менш «відполіровану» шкіру; s6102 був 3,5);
  * cn-g35   — те саме, guidance 3,5, нові сіди;
  * i2i-08   — FLUX dev поверх джерела, шум 0,8, guidance 2,0;
  * kontext  — Kontext: перемалювати джерело приглушеним плівковим фото.

    ~/Програми/cv-venv/bin/python -u tools/comfyui/proektsii_realizm.py

Вихід — `art/meshy/2026-10-14/орчиха-v3-реалізм/` і `аркуш.png`.
"""
import os
import shutil
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster3d as m  # noqa: E402
import rasy_realizm as rr  # noqa: E402

KORIN = rr.KORIN
DZH = KORIN / "art/meshy/2026-10-14/орчиха-v3-3-проекції"
VYHID = KORIN / "art/meshy/2026-10-14/орчиха-v3-реалізм"
ETALON = DZH / "збоку-flux-cn-s6102.png"
SIDY = (7101, 7102)
VYDY = {"спереду": "front view", "збоку": "side view in profile, facing left",
        "ззаду": "back view from behind"}
OPYS = ("A tall strong muscular adult female orc with grey-olive skin, long "
        "pointed ears, black braided hair tied back, a stern weathered face, "
        "a dark top, a dark leather belt with a round embossed buckle, dark "
        "shorts, leather bracers, barefoot, standing in a strict T-pose with "
        "arms straight out to the sides, %s. ")
REAL = ("Raw unedited documentary photograph shot on 35mm film, a real actress "
        "in subtle realistic orc prosthetic makeup, desaturated muted grey-olive "
        "skin with visible pores, freckles, veins, uneven tone and fine scars, "
        "no shine, no airbrushing, natural matte skin, realistic body fat and "
        "muscle, dim soft grey studio light, plain dark grey backdrop, full body "
        "from head to feet. Not a cartoon, not CGI, not a 3D render, not a game "
        "character, not plastic.")
KONTEXT = ("Turn this into a raw unedited documentary 35mm film photograph of "
           "a real actress in subtle realistic orc prosthetic makeup: same "
           "person, same pose, same clothes, same framing, but desaturated muted "
           "grey-olive matte skin with visible pores, veins, uneven tone and "
           "fine scars, no shine, dim soft studio light on a plain dark grey "
           "backdrop. Not a cartoon, not CGI.")
SPOSOBY = ("cn-g2", "cn-g35", "i2i-08", "kontext")


def zberehty(done, kudy):
    out = done["outputs"]["13"]["images"][-1]
    shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"], out["filename"]), kudy)
    print("готово", kudy.name, flush=True)


def arkush():
    s = 340
    kol = 2 + len(SPOSOBY) * len(SIDY)
    o = Image.new("RGB", (s * kol, len(VYDY) * (s + 30)), (24, 24, 24))
    d = ImageDraw.Draw(o)
    try:
        sh = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 15)
    except OSError:
        sh = ImageFont.load_default()
    for r, vyd in enumerate(VYDY):
        kadry = [("%s — джерело" % vyd, DZH / ("%s-dzherelo.png" % vyd)),
                 ("еталон: збоку cn s6102", ETALON)] + [
            ("%s s%d" % (sp, sd), VYHID / ("%s-%s-s%d.png" % (vyd, sp, sd)))
            for sp in SPOSOBY for sd in SIDY]
        y = r * (s + 30)
        for i, (pidpys, f) in enumerate(kadry):
            if f.exists():
                im = Image.open(f).convert("RGB")
                im.thumbnail((s, s))
                o.paste(im, (i * s + (s - im.width) // 2, y))
            d.text((i * s + 6, y + s + 6), pidpys, fill=(230, 220, 200), font=sh)
    o.save(VYHID / "аркуш.png")
    print("аркуш", VYHID / "аркуш.png", flush=True)


def main():
    VYHID.mkdir(parents=True, exist_ok=True)
    dzh = {v: m.stage(str(DZH / ("%s-dzherelo.png" % v))) for v in VYDY}
    m.free()
    for vyd, slova in VYDY.items():
        promt = (OPYS % slova) + REAL
        for sd in SIDY:
            for sp, i2i, g, shum in (("cn-g2", False, 2.0, 1.0), ("cn-g35", False, 3.5, 1.0),
                                     ("i2i-08", True, 2.0, 0.8)):
                kudy = VYHID / ("%s-%s-s%d.png" % (vyd, sp, sd))
                if not kudy.exists():
                    zberehty(m.run(rr.graf_flux(dzh[vyd], promt, sd, i2i, g, shum)), kudy)
    m.free()
    for vyd in VYDY:
        for sd in SIDY:
            kudy = VYHID / ("%s-kontext-s%d.png" % (vyd, sd))
            if not kudy.exists():
                g = rr.graf_kontext(dzh[vyd], sd)
                g["7"]["inputs"]["text"] = KONTEXT
                zberehty(m.run(g), kudy)
    m.free()
    arkush()


if __name__ == "__main__":
    main()
