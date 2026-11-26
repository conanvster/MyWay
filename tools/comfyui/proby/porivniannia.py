#!/usr/bin/env python3
"""Порівняння проб 26.11.2026: для кожного виду три блоки (А- і Т-ряд × 4 ракурси) —
основний прогін (2511), v1 (2511 + Multiple-Angles), v2 (Qwen-Image 2.1 Turbo).
→ art/monsters/_аркуш-каркас/проба-моделей/порівняння-<вид>.jpg"""
import os
import sys
from PIL import Image, ImageDraw, ImageFont

K = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
P = os.path.join(K, "art/monsters/_аркуш-каркас/проба-моделей")
F = lambda r, b=False: ImageFont.truetype(
    "/usr/share/fonts/truetype/dejavu/DejaVuSans%s.ttf" % ("-Bold" if b else ""), r)
VARIANTY = [("ЗАРАЗ · Qwen-Edit 2511", lambda v: os.path.join(K, "art/monsters", v + "-3d/аркуш")),
            ("V1 · 2511 + Multiple-Angles (повороти)", lambda v: os.path.join(P, "v1-2511-кути", v)),
            ("V2 · Qwen-Image 2.1 Turbo", lambda v: os.path.join(P, "v2-qwen21", v))]
C, ZAG = 330, 44
for vyd in sys.argv[1:]:
    W = 4 * C + 60
    o = Image.new("RGB", (W, 70 + 3 * (ZAG + 2 * C + 20)), (238, 237, 233))
    d = ImageDraw.Draw(o)
    d.text((20, 16), vyd.upper() + " — порівняння моделей", font=F(32, True), fill=(30, 30, 34))
    y = 70
    for nazva, teka in VARIANTY:
        d.text((20, y + 8), nazva, font=F(24, True), fill=(150, 40, 40))
        y += ZAG
        for r, poza in enumerate("АТ"):
            d.text((8, y + r * C + 8), poza, font=F(26, True), fill=(30, 30, 34))
            for c, kut in enumerate((0, 45, 90, 180)):
                f = os.path.join(teka(vyd), "%s-%d.png" % (poza, kut))
                if os.path.exists(f):
                    im = Image.open(f).convert("RGB").resize((C - 4, C - 4))
                    o.paste(im, (50 + c * C, y + r * C))
                if r == 0:
                    d.text((50 + c * C + 6, y + 4), "%d°" % kut, font=F(18), fill=(60, 60, 66))
        y += 2 * C + 20
    kudy = os.path.join(P, "порівняння-%s.jpg" % vyd)
    o.save(kudy, quality=90)
    print(kudy)
