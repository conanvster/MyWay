#!/usr/bin/env python3
"""Виріз зони з кадрів усього тіла (25.11.2026, П-288, спосіб Б). Кадр 1024 від `kadry_4.py`:
маківка на 0,035, підошви на 0,965. Межі зони — частки зросту; наручі — лише права рука
(ліва — дзеркалом у `odiah_zona`), тож спереду це ліва половина кадру, ззаду — права.

    ~/ComfyUI/venv/bin/python tools/vyriz_zony.py <зона> <тека-зведених> <тека-вирізів>
→ виріз-<бік>.png і рядок «ВИРІЗ x0 y0 ширина висота ВЕРХ м НИЗ м» (для спереду; зріст — з кадру)
"""
import os
import sys

from PIL import Image

ZONY = {"чоботи": (0.0, 0.36), "наручі": (0.44, 0.68), "наплічники": (0.57, 1.0), "пояс": (0.30, 0.64)}
z, vhid, vyhid = sys.argv[1:4]
os.makedirs(vyhid, exist_ok=True)
lo, hi = ZONY[z]
R = 1024
def riadok(f):                       # частка зросту → рядок кадру
    return int(round(R * (0.965 - 0.93 * f)))
y0, y1 = max(0, riadok(hi) - 24), min(R, riadok(lo) + 24)
for bik in ("спереду", "ззаду", "зліва", "справа"):
    x0, x1 = 0, R
    if z == "наручі":
        if bik == "спереду":
            x0, x1 = 0, R // 2
        elif bik == "ззаду":
            x0, x1 = R // 2, R
        elif bik == "зліва":
            continue
    Image.open(os.path.join(vhid, bik + ".png")).convert("RGB").crop((x0, y0, x1, y1)).save(
        os.path.join(vyhid, "виріз-%s.png" % bik))
    if bik == "спереду":
        print("ВИРІЗ %d %d %d %d" % (x0, y0, x1 - x0, y1 - y0))
    print("БІК %s %d %d %d %d" % (bik, x0, y0, x1 - x0, y1 - y0))
print("ЧАСТКИ %.3f %.3f" % (lo, hi))
