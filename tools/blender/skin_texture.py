"""Шкіра ельфа й орка з текстури людини (Quaternius, CC0).

Замовник 19.09.2026: «на базі моделі людини зробити ельфа й орка».
Тіло лишається тим самим (скелет і рухи людини), міняється тон шкіри:
орк — зелений, ельф — блідий. Зсуваються лише насичені теплі тони
(шкіра); темна білизна, запечена в ту саму текстуру, лишається як є.

Системний Python (Pillow):
    python3 tools/blender/skin_texture.py
"""
import colorsys
import os

from PIL import Image

SRC = "game/models/player"
OUT = "art/races/textures"

# раса -> (новий відтінок або None, множник насиченості, множник світла)
RACES = {
    "орк": (0.25, 0.85, 0.78),
    "ельф": (None, 0.55, 1.12),
    # Нежить бестіарію (spec/monsters.md, 19.09.2026): зомбі — сіро-
    # зелений, гуль — сірий, упир — попелястий, вампір — блідий.
    "зомбі": (0.2, 0.35, 0.62),
    "гуль": (0.12, 0.15, 0.55),
    "упир": (0.6, 0.08, 0.7),
    "вампір": (None, 0.18, 1.18),
    # Наги — зеленкуваті (spec/monsters.md, лінія 3).
    "наг": (0.3, 0.45, 0.85),
    # Імп: багряна шкіра — підігнано під готовий колір мобу
    # (mobs.json, вид 7, "колір": "#a05040").
    "імп": (0.03, 1.3, 0.72),
}


def recolour(src, dst, hue, sat_k, val_k):
    img = Image.open(src).convert("RGB")
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b = (c / 255.0 for c in px[x, y])
            hh, s, v = colorsys.rgb_to_hsv(r, g, b)
            # Шкіра — теплий відтінок (червоний…жовтий) і хоч трохи
            # насичена; білизна темна й сіра — її не чіпаємо.
            warm = hh < 0.14 or hh > 0.95
            weight = min(1.0, max(0.0, (s - 0.12) / 0.15)) if warm else 0.0
            if weight <= 0.0:
                continue
            nh = hue if hue is not None else hh
            ns = min(1.0, s * sat_k)
            nv = min(1.0, v * val_k)
            nr, ng, nb = colorsys.hsv_to_rgb(nh, ns, nv)
            px[x, y] = tuple(int(255 * (a * (1 - weight) + c * weight))
                             for a, c in zip((r, g, b), (nr, ng, nb)))
    img.save(dst)


def main():
    os.makedirs(OUT, exist_ok=True)
    # Назви в наборі різні: у жінки з «_BaseColor» на кінці.
    files = {"Male": "T_Superhero_Male_Dark.png",
             "Female": "T_Superhero_Female_Dark_BaseColor.png"}
    for sex, name in files.items():
        src = os.path.join(SRC, name)
        for race, (hue, sat_k, val_k) in RACES.items():
            dst = os.path.join(OUT, "шкіра-%s-%s.png"
                               % (race, "чоловік" if sex == "Male" else "жінка"))
            recolour(src, dst, hue, sat_k, val_k)
            print("[шкіра]", dst)


if __name__ == "__main__":
    main()
