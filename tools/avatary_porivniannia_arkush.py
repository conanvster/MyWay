#!/usr/bin/env python3
"""Аркуші порівняння аватарів зі стендів (tools/avatary_porivniannia.sh, 14.11.2026).

    ~/Програми/cv-venv/bin/python tools/avatary_porivniannia_arkush.py <тека>

З кожного `стенд-NN.png` (3600×1800, панелі 720×900) береться «зріст» (ряд 2, стовпчик 2) і
«портрет» (ряд 1, стовпчик 3). Аркуш на кожну расу й стать — `порівняння-<тип>.jpg`:
стовпчики — покоління, у підписі — покоління і чи стоїть модель у грі зараз (золота рамка).
Окремо — `порівняння-портрети.jpg`: лише портрети, всі типи рядками.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

D = sys.argv[1]
PANEL = (720, 900)
ZRIST = (720, 900)      # ліва верхня точка панелі «зріст»
PORTRET = (1440, 0)     # панелі «портрет»
W, H = 360, 450         # клітинка — пів панелі
LABEL = 64
GOLD = (222, 180, 90)
BG = (24, 24, 28)


def font(size):
    for f in ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
              "/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf"):
        if os.path.exists(f):
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()


F, FS = font(20), font(16)
rows = []
for line in open(os.path.join(D, "перелік.txt"), encoding="utf-8"):
    p = line.rstrip("\n").split("|")
    if len(p) >= 4:
        rows.append({"n": p[0], "тип": p[1], "покоління": p[2], "у грі": p[3] == "так"})


def panel(n, at):
    path = os.path.join(D, "стенд-%s.png" % n)
    if not os.path.exists(path):
        return None
    im = Image.open(path).convert("RGB")
    return im.crop((at[0], at[1], at[0] + PANEL[0], at[1] + PANEL[1])).resize((W, H), Image.LANCZOS)


def cell(r, parts):
    im = Image.new("RGB", (W, H * len(parts) + LABEL), BG)
    for i, at in enumerate(parts):
        p = panel(r["n"], at)
        if p is None:
            ImageDraw.Draw(im).text((20, H * i + H // 2), "немає знімка", fill=(200, 80, 80), font=F)
        else:
            im.paste(p, (0, H * i))
    d = ImageDraw.Draw(im)
    y = H * len(parts)
    d.text((10, y + 6), r["покоління"], fill=GOLD if r["у грі"] else (220, 220, 220), font=F)
    d.text((10, y + 34), "у грі зараз" if r["у грі"] else "#%s" % r["n"],
           fill=GOLD if r["у грі"] else (140, 140, 150), font=FS)
    if r["у грі"]:
        d.rectangle((0, 0, W - 1, im.height - 1), outline=GOLD, width=4)
    return im


types = []
for r in rows:
    if r["тип"] not in types:
        types.append(r["тип"])

for t in types:
    mine = [r for r in rows if r["тип"] == t]
    cells = [cell(r, [ZRIST, PORTRET]) for r in mine]
    sheet = Image.new("RGB", (len(cells) * (W + 8) + 8, cells[0].height + 60), BG)
    ImageDraw.Draw(sheet).text((12, 14), t, fill=(240, 240, 240), font=font(28))
    for i, c in enumerate(cells):
        sheet.paste(c, (8 + i * (W + 8), 52))
    out = os.path.join(D, "порівняння-%s.jpg" % t)
    sheet.save(out, quality=88)
    print("→", out)

most = max(sum(1 for r in rows if r["тип"] == t) for t in types)
cw, ch = W, H + LABEL
sheet = Image.new("RGB", (160 + most * (cw + 6), len(types) * (ch + 6) + 6), BG)
d = ImageDraw.Draw(sheet)
for j, t in enumerate(types):
    y = 6 + j * (ch + 6)
    d.text((10, y + ch // 2 - 12), t.replace("-", "\n"), fill=(240, 240, 240), font=F)
    for i, r in enumerate([r for r in rows if r["тип"] == t]):
        sheet.paste(cell(r, [PORTRET]), (160 + i * (cw + 6), y))
out = os.path.join(D, "порівняння-портрети.jpg")
sheet.save(out, quality=85)
print("→", out)
