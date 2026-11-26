#!/usr/bin/env python3
"""Малюнок кістяка OpenPose (COCO-18, стандартні кольори, чорне тло) з точок
tools/blender/kistiak_openpose.py → _аркуш-каркас/кістяк/<поза>-<кут>.png (26.11.2026).
    ~/Програми/cv-venv/bin/python tools/comfyui/kistiak_malyunok.py <точки.json> <тека>"""
import json
import os
import sys

from PIL import Image, ImageDraw

PARY = [(1, 2), (1, 5), (2, 3), (3, 4), (5, 6), (6, 7), (1, 8), (8, 9), (9, 10), (1, 11),
        (11, 12), (12, 13), (1, 0), (0, 14), (14, 16), (0, 15), (15, 17)]
KOLIR = [(255, 0, 0), (255, 85, 0), (255, 170, 0), (255, 255, 0), (170, 255, 0), (85, 255, 0),
         (0, 255, 0), (0, 255, 85), (0, 255, 170), (0, 255, 255), (0, 170, 255), (0, 85, 255),
         (0, 0, 255), (85, 0, 255), (170, 0, 255), (255, 0, 255), (255, 0, 170), (255, 0, 85)]

dani = json.load(open(sys.argv[1]))
os.makedirs(sys.argv[2], exist_ok=True)
for nazva, t in dani.items():
    t = {int(k): v for k, v in t.items()}
    im = Image.new("RGB", (1024, 1024), (0, 0, 0))
    d = ImageDraw.Draw(im)
    for i, (a, b) in enumerate(PARY):
        if a in t and b in t:
            k = tuple(int(c * 0.6) for c in KOLIR[i])
            d.line([tuple(t[a]), tuple(t[b])], fill=k, width=12)
    for i, (x, y) in t.items():
        d.ellipse((x - 7, y - 7, x + 7, y + 7), fill=KOLIR[i])
    im.save(os.path.join(sys.argv[2], nazva + ".png"))
print("кістяк →", sys.argv[2], len(dani))
