#!/usr/bin/env python3
"""Орчиха у трьох проекціях — від самого референсу Firefly (14.10.2026).

Слово замовника про аркуш `proektsii_vybir.py`: «референс краще — спробуй
зробити краще». Перемальовка з нуля (Q4 FLUX, 1024 px) втрачає чіткість
референсу, тож тут від нього йдемо обережно:
  1. постать вирізано (birefnet) і покладено на рівне сіре тло — без сітки й
     підпису «ORC FEMALE…»;
  2. FLUX dev поверх із легким шумом (0,35 / 0,5) і контурами — лише жива
     шкіра, форма й деталі лишаються референсу;
  3. другий прохід у 1,5× (1536 px, шум 0,3) — дрібні деталі.
Збоку й ззаду — розвороти Kontext із того самого референсу
(`орчиха-3-проекції/<вид>-dzherelo.png`), ті самі кроки.

    ~/Програми/cv-venv/bin/python -u tools/comfyui/proektsii_ref.py

Вихід — `art/meshy/2026-10-14/орчиха-від-референсу/` і `аркуш.png`.
"""
import os
import shutil
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster3d as m  # noqa: E402
import rasy_realizm as rr  # noqa: E402

KORIN = rr.KORIN
REF = KORIN / "art/references/ork/ork-zhinka-ref.png"
DZH = KORIN / "art/meshy/2026-10-13/орчиха-3-проекції"
VYHID = KORIN / "art/meshy/2026-10-14/орчиха-від-референсу"
VYDY = {"спереду": (REF, "front view"),
        "збоку": (DZH / "збоку-dzherelo.png", "side view in profile, facing left"),
        "ззаду": (DZH / "ззаду-dzherelo.png", "back view from behind")}
SEED = 9101
SHUMY = (0.35, 0.5)
FON = (128, 128, 128)
OPYS = ("Full body photo of a tall strong muscular adult female orc with "
        "olive-green orc skin, long pointed ears, long straight loose black "
        "hair, a stern face, topless with a bare chest, a double brown leather "
        "belt with a round bronze stud and a leather pouch, a ragged dark cloth "
        "loincloth with a brown leather flap, barefoot, strict T-pose, %s. "
        "Highly detailed realistic skin with pores, veins and fine scars, matte "
        "natural skin, sharp focus, soft even studio light, plain grey backdrop. "
        "Not a cartoon.")


def chyste_tlo(dzherelo, kudy):
    """Постать на рівному сірому тлі (маска birefnet, м'який край)."""
    maska = kudy.with_name(kudy.stem + "-maska.png")
    m.cutout(str(dzherelo), str(maska))
    im = Image.open(dzherelo).convert("RGB")
    mk = Image.open(maska).convert("L").resize(im.size).filter(ImageFilter.GaussianBlur(1.5))
    tlo = Image.new("RGB", im.size, FON)
    Image.composite(im, tlo, mk).save(kudy)
    maska.unlink()


def prohid(kadr_shliakh, promt, shum, kudy, rozmir=None):
    """FLUX поверх кадру (i2i + слабкі контури); `rozmir` — збільшити перед."""
    if rozmir:
        im = Image.open(kadr_shliakh).convert("RGB")
        k = rozmir / max(im.size)
        im.resize((round(im.width * k / 16) * 16, round(im.height * k / 16) * 16),
                  Image.LANCZOS).save(kudy)
        kadr_shliakh = kudy
    kadr = m.stage(str(kadr_shliakh))
    done = m.run(rr.graf_flux(kadr, promt, SEED, True, 2.5, shum, 0.35, 0.35))
    out = done["outputs"]["13"]["images"][-1]
    shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"], out["filename"]), kudy)
    print("готово", kudy.name, flush=True)


def arkush():
    s = 420
    kol = 2 + len(SHUMY)
    o = Image.new("RGB", (s * kol, len(VYDY) * (s + 30)), (24, 24, 24))
    d = ImageDraw.Draw(o)
    try:
        sh = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 16)
    except OSError:
        sh = ImageFont.load_default()
    for r, (vyd, (dzh, _)) in enumerate(VYDY.items()):
        kadry = [("%s — джерело" % vyd, dzh), ("чисте тло", VYHID / ("%s-tlo.png" % vyd))] + [
            ("шум %.2f + 1536" % sh_, VYHID / ("%s-%02d-hd.png" % (vyd, round(sh_ * 100))))
            for sh_ in SHUMY]
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
    m.free()
    for vyd, (dzh, _) in VYDY.items():
        tlo = VYHID / ("%s-tlo.png" % vyd)
        if not tlo.exists():
            chyste_tlo(dzh, tlo)
    m.free()
    for vyd, (_, slova) in VYDY.items():
        promt = OPYS % slova
        for shum in SHUMY:
            p1 = VYHID / ("%s-%02d.png" % (vyd, round(shum * 100)))
            if not p1.exists():
                prohid(VYHID / ("%s-tlo.png" % vyd), promt, shum, p1)
            p2 = VYHID / ("%s-%02d-hd.png" % (vyd, round(shum * 100)))
            if not p2.exists():
                prohid(p1, promt, 0.3, p2, rozmir=1536)
    m.free()
    arkush()


if __name__ == "__main__":
    main()
