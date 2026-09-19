"""Текстури хутра для своїх моделей: колір і карта нормалей.

Замовник 19.09.2026 про зайця: «шерсть виглядає як шліфована поверхня».
Однотонна гладка поверхня й дає це відчуття; вузли-шуми Blender у гру не
переносяться (glTF бере лише картинки), тож хутро малюється тут
картинкою: тисячі коротких ворсинок уздовж V (у сфер Blender це
«меридіани» — ворс лягає від голови до хвоста) з легкою різницею тону,
і з них же — карта нормалей, яка дає ворсу тінь під світлом гри.

Системний Python (потрібен Pillow), не Blender:
    python3 tools/blender/fur_texture.py art/monsters/textures
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

SIZE = 512
STRANDS = 26000

# Назва -> (основний тон, розкид світлоти ворсинок, частка темних кінчиків).
FURS = {
    "хутро-буре": ((120, 84, 52), 38, 0.25),
    "хутро-світле": ((214, 204, 188), 22, 0.08),
    "хутро-сіре": ((118, 116, 112), 34, 0.2),
    "хутро-темне": ((74, 50, 32), 30, 0.3),
    # Бестіарій (spec/monsters.md, 19.09.2026): лисиця, рись, олень,
    # сіромаха, кабан.
    "хутро-руде": ((186, 92, 36), 34, 0.22),
    "хутро-рисяче": ((168, 134, 92), 30, 0.3),
    "хутро-оленяче": ((132, 94, 60), 26, 0.2),
    "хутро-сиве": ((150, 148, 142), 30, 0.35),
    "щетина": ((72, 56, 44), 36, 0.45),
    # Волосся гравця (19.09.2026): людина, ельф, орк.
    "волосся-русяве": ((88, 62, 38), 26, 0.25),
    "волосся-світле": ((214, 196, 150), 22, 0.1),
    "волосся-чорне": ((30, 26, 24), 18, 0.3),
}


def strands(seed):
    """Однакові для кольору й нормалей: ворсинка — відрізок уздовж V."""
    rng = random.Random(seed)
    out = []
    for _ in range(STRANDS):
        x = rng.uniform(0, SIZE)
        y = rng.uniform(0, SIZE)
        length = rng.uniform(5, 14)
        lean = rng.uniform(-0.35, 0.35)
        shade = rng.gauss(0, 1)
        dark = rng.random()
        out.append((x, y, length, lean, shade, dark))
    return out


def colour(name, base, spread, tips, lines):
    img = Image.new("RGB", (SIZE, SIZE), base)
    draw = ImageDraw.Draw(img)
    for x, y, length, lean, shade, dark in lines:
        k = 1.0 + shade * spread / 255.0
        if dark < tips:
            k *= 0.72
        tone = tuple(max(0, min(255, int(c * k))) for c in base)
        x2 = x + math.sin(lean) * length
        y2 = y + math.cos(lean) * length
        # Шов текстури не видно: ворсинка, що вилазить за край,
        # малюється й з протилежного боку.
        for dx in (-SIZE, 0, SIZE):
            for dy in (-SIZE, 0, SIZE):
                draw.line((x + dx, y + dy, x2 + dx, y2 + dy), fill=tone,
                          width=1)
    return img.filter(ImageFilter.GaussianBlur(0.6))


def normals(lines):
    """Висота — ворсинки, з неї — нормалі (формат OpenGL, як у glTF)."""
    height = Image.new("L", (SIZE, SIZE), 110)
    draw = ImageDraw.Draw(height)
    for x, y, length, lean, shade, _ in lines:
        x2 = x + math.sin(lean) * length
        y2 = y + math.cos(lean) * length
        level = int(150 + shade * 30)
        for dx in (-SIZE, 0, SIZE):
            for dy in (-SIZE, 0, SIZE):
                draw.line((x + dx, y + dy, x2 + dx, y2 + dy),
                          fill=max(0, min(255, level)), width=1)
    height = height.filter(ImageFilter.GaussianBlur(0.8))
    h = height.load()
    out = Image.new("RGB", (SIZE, SIZE))
    o = out.load()
    strength = 2.2
    for j in range(SIZE):
        for i in range(SIZE):
            dx = (h[(i + 1) % SIZE, j] - h[(i - 1) % SIZE, j]) / 255.0
            dy = (h[i, (j + 1) % SIZE] - h[i, (j - 1) % SIZE]) / 255.0
            nx, ny, nz = -dx * strength, dy * strength, 1.0
            n = math.sqrt(nx * nx + ny * ny + nz * nz)
            o[i, j] = (int((nx / n * 0.5 + 0.5) * 255),
                       int((ny / n * 0.5 + 0.5) * 255),
                       int((nz / n * 0.5 + 0.5) * 255))
    return out


def main():
    folder = sys.argv[1] if len(sys.argv) > 1 else "art/monsters/textures"
    os.makedirs(folder, exist_ok=True)
    lines = strands(19092026)
    for name, (base, spread, tips) in FURS.items():
        colour(name, base, spread, tips, lines).save(
            os.path.join(folder, name + ".png"))
    normals(lines).save(os.path.join(folder, "хутро-нормаль.png"))
    print("[хутро] %s: %s + нормаль" % (folder, ", ".join(FURS)))


if __name__ == "__main__":
    main()
