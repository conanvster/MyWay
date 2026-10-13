#!/usr/bin/env python3
"""Набір броні на кадрі ельфійки e1903 — для скану «у наборі мінус тіло» (13.10.2026).

Слово замовника: «Броня частинами» (план §3б, крок 4), спосіб — «я не знаю
як краще»; обрано скан у наборі, від якого віднімається тіло e1903. Щоб
тіло під бронею лягло на тіло скану e1903, набір малюється від кадру
`el-lysa-e1903.png` і за скелетом, знятим з нього ж (а не з
`el-dovha-chernetka.png`, як у `elf_nabory_cn.py`). Обличчя — під маскою,
лишається кадру. Скелет і маска пишуться окремими файлами — погоджені
`el-cn-poza.png`/`el-cn-maska.png` не чіпаються.

    ~/Програми/cv-venv/bin/python -u tools/comfyui/bronia_e1903.py [ключ] [сід…]

Вихід — `wiki/img/test/avatar/e1903-nabir-<ключ>-s<сід>.png`.
"""
import os
import shutil
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import monster3d as m  # noqa: E402
import elf_nabory_cn as cn  # noqa: E402

D = cn.D
KADR = D / "el-lysa-e1903.png"
KLIUCH = next((a for a in sys.argv[1:] if a in cn.NABORY), "E-легкий")
SIDY = [int(a) for a in sys.argv[1:] if a.isdigit()] or [2001, 2002, 2003]
# як у `elf_lysa_nova.py`: 0,85 до 65% опускало промежину
cn.SYLA, cn.KINETS = 1.0, 0.9


def main():
    cn.OSNOVA = KADR
    T, rozmir, lm, ramka = cn.tochky_tila()
    poza = Image.new("RGB", rozmir, (0, 0, 0))
    d = ImageDraw.Draw(poza)
    for i, (a, b) in enumerate(cn.PARY):
        d.line((T[a], T[b]), fill=tuple(int(c * 0.6) for c in cn.KOLORY[i]), width=8)
    for i, p in T.items():
        d.ellipse((p[0] - 5, p[1] - 5, p[0] + 5, p[1] + 5), fill=cn.KOLORY[i])
    poza.save(D / "e1903-cn-poza.png")
    x0, x1, y0, y1 = ramka
    pts = np.array([(x0 + lm[i].x * (x1 - x0), y0 + lm[i].y * (y1 - y0))
                    for i in (10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361,
                              288, 397, 365, 379, 378, 400, 377, 152, 148, 176, 149,
                              150, 136, 172, 58, 132, 93, 234, 127, 162, 21, 54, 103,
                              67, 109)])
    c = pts.mean(0)
    pts = c + (pts - c) * 0.8
    maska = Image.new("L", rozmir, 255)
    ImageDraw.Draw(maska).polygon([tuple(p) for p in pts], fill=0)
    maska.save(D / "e1903-cn-maska.png")
    print("скелет і маска e1903 готові", flush=True)
    osn, msk, poz = (m.stage(str(D / f)) for f in
                     (KADR.name, "e1903-cn-maska.png", "e1903-cn-poza.png"))
    m.free()
    for seed in SIDY:
        kudy = D / ("e1903-nabir-%s-s%d.png" % (KLIUCH, seed))
        done = m.run(cn.graf(osn, msk, poz, cn.promt(cn.NABORY[KLIUCH], "важкий" in KLIUCH),
                             seed, "e1903_nabir_%d" % seed))
        out = done["outputs"]["13"]["images"][-1]
        shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"], out["filename"]), kudy)
        print("готово", kudy.name, flush=True)
    m.free()


if __name__ == "__main__":
    main()
