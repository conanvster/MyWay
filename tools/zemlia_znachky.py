#!/usr/bin/env python3
"""Спрощені зображення речей на землі (П-160) — зі значків речей.

Слово замовника 01.10.2026: «згенерувати спрощене зображення». Значок
речі (`game/assets/icons/items/<назва>.png`, 64×64) намальовано на
темному тлі; на землі тло мусить зникнути, інакше річ лежить чорним
квадратом. Тож тло вирізається заливкою ВІД КРАЇВ: прозорим стає лише
те, що схоже на колір тла й торкається краю, — темні місця всередині
речі (руків'я, тінь на клинку) лишаються.

    python3 tools/zemlia_znachky.py            усі значки
    python3 tools/zemlia_znachky.py --аркуш    ще й аркуш огляду в
                                               .logs/zemlia-ogliad.png

Вихід — `game/assets/icons/ground/<та сама назва>.png`. Після нових
файлів — `godot --path game --headless --import`, інакше гра їх не
побачить.
"""
import sys
from collections import deque
from pathlib import Path

from PIL import Image, ImageFilter

KORIN = Path(__file__).resolve().parent.parent
DZHERELO = KORIN / "game/assets/icons/items"
VYKHID = KORIN / "game/assets/icons/ground"
# Наскільки піксель може відрізнятись від тла (сума модулів RGB), щоб
# іще вважатись тлом. До ПОРИГ — прозоре зовсім, від ПОРИГ до ОРЕОЛ —
# напівпрозоре: так згасає сяйво рун, а не лишається плямою. Далі ОРЕОЛ
# заливка не йде — це вже сама річ.
PORIH = 46
OREOL = 80
# Темніше за це (найяскравіший канал) — тло за будь-якого кольору: у
# частини значків кути чорні, а решта краю синювата.
TEMRIAVA = 12
# Скільки пікселів пом'якшити край, щоб на землі не було драбинки.
MYAKO = 1


def tlo(im):
    """Колір тла — медіана пікселів по краю."""
    w, h = im.size
    px = im.load()
    kraj = [px[x, y][:3] for x in range(w) for y in (0, h - 1)]
    kraj += [px[x, y][:3] for y in range(h) for x in (0, w - 1)]
    return tuple(sorted(c[i] for c in kraj)[len(kraj) // 2] for i in range(3))


def maska(im):
    """255 — річ, 0 — тло, з'єднане з краєм; між ними — ореол."""
    w, h = im.size
    px = im.load()
    t = tlo(im)

    def vidstan(x, y):
        r, g, b = px[x, y][:3]
        if max(r, g, b) <= TEMRIAVA:
            return 0
        return abs(r - t[0]) + abs(g - t[1]) + abs(b - t[2])

    m = Image.new("L", (w, h), 255)
    mp = m.load()
    bachyly = set()
    cherga = deque()
    for x in range(w):
        cherga.extend([(x, 0), (x, h - 1)])
    for y in range(h):
        cherga.extend([(0, y), (w - 1, y)])
    while cherga:
        x, y = cherga.popleft()
        if (x, y) in bachyly:
            continue
        bachyly.add((x, y))
        d = vidstan(x, y)
        if d > OREOL:
            continue
        mp[x, y] = 0 if d <= PORIH else \
            round(255 * (d - PORIH) / (OREOL - PORIH))
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in bachyly:
                cherga.append((nx, ny))
    return m.filter(ImageFilter.GaussianBlur(MYAKO)) if MYAKO else m


def sproshchene(shliakh):
    im = Image.open(shliakh).convert("RGBA")
    im.putalpha(maska(im))
    return im


def arkush(shliakhy, kudy):
    """Аркуш огляду: кожна річ на сірому й на трав'яному тлі."""
    kl = 72
    stovp = 16
    riadky = (len(shliakhy) + stovp - 1) // stovp
    a = Image.new("RGBA", (stovp * kl, riadky * kl * 2), (0, 0, 0, 255))
    for i, p in enumerate(shliakhy):
        im = Image.open(p)
        x, y = (i % stovp) * kl, (i // stovp) * kl * 2
        for j, kolir in enumerate([(128, 128, 128, 255), (74, 92, 52, 255)]):
            pid = Image.new("RGBA", (kl, kl), kolir)
            pid.alpha_composite(im, (4, 4))
            a.paste(pid, (x, y + j * kl))
    kudy.parent.mkdir(parents=True, exist_ok=True)
    a.save(kudy)


def main():
    VYKHID.mkdir(parents=True, exist_ok=True)
    zrobleno = []
    for p in sorted(DZHERELO.glob("*.png")):
        kudy = VYKHID / p.name
        sproshchene(p).save(kudy)
        zrobleno.append(kudy)
    print("[земля] спрощених зображень: %d → %s" % (len(zrobleno), VYKHID))
    if "--аркуш" in sys.argv:
        kudy = KORIN / ".logs/zemlia-ogliad.png"
        arkush(zrobleno, kudy)
        print("[земля] аркуш огляду: %s" % kudy)


if __name__ == "__main__":
    main()
