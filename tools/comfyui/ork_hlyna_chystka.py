#!/usr/bin/env python3
"""Орчиха-глина перед сканом: прибрати те, що Pixal3D зліпить у сітку (12.10.2026).

Слово замовника: «орчиха-s1303-глина.png — мені подобається. Роби». На
кадрі `ork2-lysa-s1303-hlyna.png` лишились пряжка на животі, сумка на
правому стегні, темні плями від краю спідниці на стегнах, пасма волосся
на грудях і плечі — усе це стало б горбами й пластинами скану. Маска —
вручну еліпсами (кадр один), перемальовує FLUX dev + ControlNet за
скелетом (`ork2-cn-poza.png`), як `ork_lysa.py`; решта — пікселі кадру.

    ~/Програми/cv-venv/bin/python -u tools/comfyui/ork_hlyna_chystka.py [--лише-маска] [сід…]

Вихід — `wiki/img/test/avatar/ork2-lysa-s1303-hlyna-c<сід>.png`.
"""
import os
import sys

import cv2
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import monster3d as m  # noqa: E402
import elf_nabory_cn as cn  # noqa: E402

D = cn.D
KADR = D / "ork2-lysa-s1303-hlyna.png"
POZA = "ork2-cn-poza.png"
SIDY = [int(a) for a in sys.argv[1:] if a.isdigit()] or [1701, 1702, 1703]
# (центр x, y, піввісі a, b) у кадрі 1024²
MISTSIA = [
    (488, 442, 40, 20),      # пряжка на животі
    (616, 518, 44, 56),      # сумка на стегні
    (432, 612, 50, 45),      # плями на лівому стегні
    (597, 582, 45, 35),      # плями на правому стегні
    (552, 255, 18, 45),      # пасмо на грудях
    (455, 265, 18, 40),      # пасмо біля лівого плеча
]
PROMT = (
    "Full body front view of a uniform matte grey clay sculpture of an adult "
    "female orc in a strict T-pose, untextured digital sculpt, smooth bare "
    "clay skin on the belly and thighs with muscle forms, no belt, no "
    "buckle, no pouch, no hair strands on the body, plain black briefs, "
    "grey grid studio backdrop, soft even lighting.")


def maska():
    mm = np.zeros((1024, 1024), np.uint8)
    for x, y, a, b in MISTSIA:
        cv2.ellipse(mm, (x, y), (a, b), 0, 0, 360, 255, -1)
    Image.fromarray(mm).save(D / "ork2-hlyna-chystka-maska.png")
    return mm


def main():
    a = np.array(Image.open(KADR).convert("RGB"))
    mm = maska()
    nahl = a.copy()
    nahl[mm > 0] = (nahl[mm > 0] * 0.5 + np.array([255, 0, 0]) * 0.5).astype(np.uint8)
    Image.fromarray(nahl).save(D / "ork2-hlyna-chystka-nahliad.png")
    if "--лише-маска" in sys.argv:
        return
    osn, msk, poz = (m.stage(str(D / f)) for f in
                     (KADR.name, "ork2-hlyna-chystka-maska.png", POZA))
    m.free()
    soft = cv2.GaussianBlur(mm.astype(np.float32) / 255, (0, 0), 3.0)[..., None]
    for seed in SIDY:
        kudy = D / ("%s-c%d.png" % (KADR.stem, seed))
        done = m.run(cn.graf(osn, msk, poz, PROMT, seed, "ork_chystka_%d" % seed))
        out = done["outputs"]["13"]["images"][-1]
        nove = np.array(Image.open(os.path.join(m.COMFY, "output", out["subfolder"],
                                                out["filename"])).convert("RGB"))
        # сіре — як і кадр (FLUX міг додати відтінку)
        l_ = cv2.cvtColor(nove, cv2.COLOR_RGB2LAB)[..., 0]
        nove = np.repeat(l_[..., None], 3, 2).astype(np.float32)
        zsh = a.astype(np.float32) * (1 - soft) + nove * soft
        Image.fromarray(zsh.clip(0, 255).astype(np.uint8)).save(kudy)
        print("готово", kudy.name, flush=True)
    m.free()


if __name__ == "__main__":
    main()
