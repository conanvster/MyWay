#!/usr/bin/env python3
"""GIF з кадрів monstr_gif.py (П-297): підпис руху на кожному кадрі; кілька тек — поруч в одному кадрі.
    ~/Програми/cv-venv/bin/python tools/monstr_gif_zbyraty.py <вихід.gif> <тека> [<тека> …] [--назви a,b,c]"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

a = sys.argv[1:]
nazvy = a[a.index("--назви") + 1].split(",") if "--назви" in a else []
if "--назви" in a:
    i = a.index("--назви")
    a = a[:i] + a[i + 2:]
vyhid, teky = a[0], a[1:]
F = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 18)
spysky = []
for t in teky:
    spysky.append([l.split(" ", 1) for l in open(os.path.join(t, "рухи.txt")).read().splitlines()])
N = max(len(s) for s in spysky)
kadry = []
for j in range(N):
    ims = []
    for t, s in zip(teky, spysky):
        nm, ruh = s[j % len(s)]
        im = Image.open(os.path.join(t, nm + ".png")).convert("RGB")
        d = ImageDraw.Draw(im)
        d.text((8, 6), ruh, font=F, fill=(255, 255, 255), stroke_width=2, stroke_fill=(30, 30, 30))
        ims.append(im)
    w, h = ims[0].size
    o = Image.new("RGB", (w * len(ims), h + (28 if nazvy else 0)), (40, 40, 44))
    for i, im in enumerate(ims):
        o.paste(im, (i * w, 28 if nazvy else 0))
        if nazvy:
            ImageDraw.Draw(o).text((i * w + 8, 4), nazvy[i], font=F, fill=(240, 240, 240))
    kadry.append(o.quantize(colors=128))
kadry[0].save(vyhid, save_all=True, append_images=kadry[1:], duration=66, loop=0, optimize=True)
print("gif →", vyhid, N, "кадрів")
