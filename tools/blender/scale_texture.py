"""Луска для драконідів (spec/monsters.md, 19.09.2026): ряди лусок, що
перекривають одна одну, кожна з темним краєм і світлішою серединою.

    python3 tools/blender/scale_texture.py
"""
import os
import random

from PIL import Image, ImageDraw, ImageFilter

SIZE = 512
OUT = "art/monsters/textures"
KINDS = {
    "луска-зелена": (70, 104, 58),
    "луска-червона": (132, 52, 38),
    "луска-темна": (46, 44, 52),
    "луска-піщана": (176, 150, 100),
}


def scales(base, seed):
    rng = random.Random(seed)
    img = Image.new("RGB", (SIZE, SIZE), tuple(int(c * 0.5) for c in base))
    d = ImageDraw.Draw(img)
    step = 32
    for row in range(-1, SIZE // (step // 2) + 2):
        y = row * step // 2
        shift = (row % 2) * step // 2
        for col in range(-1, SIZE // step + 2):
            x = col * step + shift
            k = rng.uniform(0.82, 1.12)
            fill = tuple(min(255, int(c * k)) for c in base)
            edge = tuple(int(c * 0.45) for c in base)
            for dx in (-SIZE, 0, SIZE):
                for dy in (-SIZE, 0, SIZE):
                    box = (x + dx - step * 0.55, y + dy - step * 0.2,
                           x + dx + step * 0.55, y + dy + step * 0.9)
                    d.ellipse(box, fill=fill, outline=edge, width=3)
    return img.filter(ImageFilter.GaussianBlur(0.8))


def main():
    os.makedirs(OUT, exist_ok=True)
    for i, (name, base) in enumerate(KINDS.items()):
        scales(base, 100 + i).save(os.path.join(OUT, name + ".png"))
        print("[луска]", name)


if __name__ == "__main__":
    main()
