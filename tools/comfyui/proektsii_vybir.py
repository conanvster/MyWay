#!/usr/bin/env python3
"""Орчиха у трьох проекціях — від кадрів, обраних замовником (14.10.2026).

Слово замовника: «я виберу декілька які найбільше співпадають з моїми
вимогами: збоку-flux-cn-s6102, спереду-cn-g2-s7101, ззаду-cn-g2-s7102 —
спробуй зробити краще користуючись [Firefly, `ork-zhinka-ref.png`]».
Обраний кадр дає позу й тіло (контури Canny, сила нижча, ніж у
`proektsii_realizm.py`, — щоб знялись бюстгальтер і шорти), референс Firefly —
вигляд словами (Kontext двох картинок не поєднує, перевірено 13.10):
оливкова орчача шкіра, топлес, розпущене волосся, подвійний пояс з бляхою й
сумкою, рвана пов'язка. Не «actress» — у `proektsii_realizm.py` з ним шкіра
ставала людською.

    ~/Програми/cv-venv/bin/python -u tools/comfyui/proektsii_vybir.py

Вихід — `art/meshy/2026-10-14/орчиха-вибір/` і `аркуш.png`.
"""
import os
import shutil
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster3d as m  # noqa: E402
import rasy_realizm as rr  # noqa: E402

KORIN = rr.KORIN
A = KORIN / "art/meshy/2026-10-14"
REF = KORIN / "art/references/ork/ork-zhinka-ref.png"
VYHID = A / "орчиха-вибір"
VYBIR = {
    "спереду": (A / "орчиха-v3-реалізм/спереду-cn-g2-s7101.png", "front view"),
    "збоку": (A / "орчиха-v3-3-проекції/збоку-flux-cn-s6102.png",
              "side view in profile, facing left"),
    "ззаду": (A / "орчиха-v3-реалізм/ззаду-cn-g2-s7102.png", "back view from behind"),
}
SIDY = (8101, 8102)
OPYS = ("Full body photo of a tall strong muscular adult female orc with "
        "muted olive-green orc skin (green, not human skin tone), long pointed "
        "ears, long straight loose black hair over her shoulders and back, a "
        "stern face with small lower tusks, topless with a bare chest, a double "
        "brown leather belt with a round bronze stud and a leather pouch on the "
        "hip, a ragged dark cloth loincloth with a brown leather front flap, "
        "barefoot, standing in a strict T-pose with arms straight out to the "
        "sides, %s. ")
REAL = ("Raw unedited 35mm film photograph, highly realistic orc, matte skin "
        "with visible pores, veins, uneven tone and fine scars, no shine, no "
        "airbrushing, realistic muscle and body fat, soft even studio light, "
        "plain medium grey backdrop, full body from head to feet. Not a cartoon, "
        "not CGI, not a 3D render, not a game character.")
# (назва, i2i, guidance, шум, сила контурів, до якої частки кроків)
SPOSOBY = (("cn-s05", False, 2.5, 1.0, 0.5, 0.45),
           ("cn-s07", False, 2.5, 1.0, 0.7, 0.5),
           ("i2i-08", True, 2.5, 0.8, 0.4, 0.4))


def zberehty(done, kudy):
    out = done["outputs"]["13"]["images"][-1]
    shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"], out["filename"]), kudy)
    print("готово", kudy.name, flush=True)


def arkush():
    s = 360
    kol = 2 + len(SPOSOBY) * len(SIDY)
    o = Image.new("RGB", (s * kol, len(VYBIR) * (s + 30)), (24, 24, 24))
    d = ImageDraw.Draw(o)
    try:
        sh = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 15)
    except OSError:
        sh = ImageFont.load_default()
    for r, (vyd, (dzh, _)) in enumerate(VYBIR.items()):
        kadry = [("обрано: " + dzh.stem, dzh), ("референс Firefly", REF)] + [
            ("%s %s s%d" % (vyd, sp[0], sd), VYHID / ("%s-%s-s%d.png" % (vyd, sp[0], sd)))
            for sp in SPOSOBY for sd in SIDY]
        y = r * (s + 30)
        for i, (pidpys, f) in enumerate(kadry):
            if f.exists():
                im = Image.open(f).convert("RGB")
                im.thumbnail((s, s))
                o.paste(im, (i * s + (s - im.width) // 2, y))
            d.text((i * s + 6, y + s + 6), pidpys[:40], fill=(230, 220, 200), font=sh)
    o.save(VYHID / "аркуш.png")
    print("аркуш", VYHID / "аркуш.png", flush=True)


def main():
    VYHID.mkdir(parents=True, exist_ok=True)
    m.free()
    for vyd, (dzh, slova) in VYBIR.items():
        kadr = m.stage(str(dzh))
        promt = (OPYS % slova) + REAL
        for sd in SIDY:
            for nazva, i2i, g, shum, syla, kinets in SPOSOBY:
                kudy = VYHID / ("%s-%s-s%d.png" % (vyd, nazva, sd))
                if not kudy.exists():
                    zberehty(m.run(rr.graf_flux(kadr, promt, sd, i2i, g, shum, syla, kinets)), kudy)
    m.free()
    arkush()


if __name__ == "__main__":
    main()
