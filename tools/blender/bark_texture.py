"""Текстура набору речей «з кори дуба» (19.09.2026): кора — поздовжні
волокна й тріщини. Нею фарбуються частини одягу, коли вдягнуто речі
цього набору (`вигляд` у game/data/items.json). Інший набір — інша
картинка й рядок у даних, модель не міняється.

Системний Python (Pillow):
    python3 tools/blender/bark_texture.py
"""
import os
import random

from PIL import Image, ImageDraw, ImageFilter

SIZE = 512
OUT = "game/models/own/clothes/кора-дуба.png"


def main():
    rng = random.Random(1909)
    img = Image.new("RGB", (SIZE, SIZE), (92, 64, 40))
    draw = ImageDraw.Draw(img)
    # Волокна: довгі, трохи хвилясті, різного тону.
    for _ in range(900):
        x = rng.uniform(0, SIZE)
        y = rng.uniform(0, SIZE)
        length = rng.uniform(40, 160)
        tone = rng.randint(-26, 22)
        colour = (92 + tone, 64 + int(tone * 0.8), 40 + int(tone * 0.6))
        width = rng.choice((1, 2, 2, 3))
        drift = rng.uniform(-6, 6)
        for dx in (-SIZE, 0, SIZE):
            for dy in (-SIZE, 0, SIZE):
                draw.line((x + dx, y + dy, x + dx + drift, y + dy + length),
                          fill=colour, width=width)
    # Тріщини: темні, вужчі, уздовж волокон.
    for _ in range(140):
        x = rng.uniform(0, SIZE)
        y = rng.uniform(0, SIZE)
        length = rng.uniform(20, 90)
        for dx in (-SIZE, 0, SIZE):
            for dy in (-SIZE, 0, SIZE):
                draw.line((x + dx, y + dy, x + dx + rng.uniform(-3, 3),
                           y + dy + length), fill=(34, 22, 14), width=1)
    img = img.filter(ImageFilter.GaussianBlur(0.7))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT)
    print("[кора]", OUT)


if __name__ == "__main__":
    main()
