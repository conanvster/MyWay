#!/usr/bin/env python3
"""Кластери листя для генератора дерев (П-253) — зі справжніх листків.

Слово замовника 01.10.2026: генератор дерев «на базі реальних гілок та
листя»; П-253 — «безкоштовні скани й фото, скрипт Blender». Окремий
листок на дереві — десятки тисяч площинок, для гри забагато, тож листки
спершу складаються в «гілочки з листям» тут, а дерево (`tools/blender/
derevo.py`) обсаджує ними кінці гілок.

Вхід — атлас листків ambientCG (CC0, `LeafSetNNN`: колір + прозорість,
листки викладено сіткою). Листки вирізаються за зв'язними плямами
прозорості, тоді на прозорому полотні малюється тонкий пагін і вздовж
нього — листки з випадковим поворотом, розміром і відтінком.

    python3 tools/derevo_lystia.py <тека LeafSet> <вихід.png> [seed]

Вихід — атлас 2×2 кластерів, 2048×2048, RGBA.
"""
import math
import random
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

KLITYNKA = 1024          # бік одного кластера в атласі
NAJMENSHA_PLAMA = 400    # пікселів: менше — крихта, не листок


def lystky(teka):
    """Окремі листки з атласу: [RGBA] обрізані по своїй плямі."""
    teka = Path(teka)
    imia = teka.name
    kolir = Image.open(teka / ("%s_1K-PNG_Color.png" % imia)).convert("RGB")
    prozorist = Image.open(teka / ("%s_1K-PNG_Opacity.png" % imia)) \
        .convert("L")
    w, h = prozorist.size
    px = prozorist.load()
    bachyly = bytearray(w * h)
    out = []
    for y0 in range(0, h, 2):
        for x0 in range(0, w, 2):
            if px[x0, y0] < 128 or bachyly[y0 * w + x0]:
                continue
            # Заливка плями: межі листка.
            stos = [(x0, y0)]
            bachyly[y0 * w + x0] = 1
            x1 = x2 = x0
            y1 = y2 = y0
            n = 0
            while stos:
                x, y = stos.pop()
                n += 1
                x1, x2, y1, y2 = min(x1, x), max(x2, x), min(y1, y), \
                    max(y2, y)
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1),
                               (x, y - 1)):
                    if 0 <= nx < w and 0 <= ny < h \
                            and not bachyly[ny * w + nx] \
                            and px[nx, ny] >= 128:
                        bachyly[ny * w + nx] = 1
                        stos.append((nx, ny))
            if n < NAJMENSHA_PLAMA:
                continue
            ramka = (x1, y1, x2 + 1, y2 + 1)
            lyst = kolir.crop(ramka)
            lyst.putalpha(prozorist.crop(ramka))
            out.append(lyst)
    return out


def klaster(lyst_y, rng, kolir_pahona):
    """Одна гілочка з листям на прозорому полотні KLITYNKA²."""
    k = KLITYNKA
    polotno = Image.new("RGBA", (k, k), (0, 0, 0, 0))
    malo = ImageDraw.Draw(polotno)
    # Пагін — від низу до середини вгору, злегка вигнутий, з бічними
    # пагонцями: на ньому листки «ростуть», а не висять у повітрі.
    tochky = []
    x, y = k * 0.5, k * 0.98
    kut = -math.pi / 2 + rng.uniform(-0.25, 0.25)
    for _ in range(14):
        tochky.append((x, y))
        kut += rng.uniform(-0.12, 0.12)
        x += math.cos(kut) * k * 0.055
        y += math.sin(kut) * k * 0.055
    malo.line(tochky, fill=kolir_pahona, width=int(k * 0.012))
    vuzly = []
    for i in range(2, len(tochky), 2):
        bx, by = tochky[i]
        bik = rng.choice((-1, 1))
        dov = k * rng.uniform(0.12, 0.25)
        kut2 = -math.pi / 2 + bik * rng.uniform(0.5, 1.1)
        ex, ey = bx + math.cos(kut2) * dov, by + math.sin(kut2) * dov
        malo.line([(bx, by), (ex, ey)], fill=kolir_pahona,
                  width=int(k * 0.007))
        vuzly.append((ex, ey, kut2))
        vuzly.append((bx, by, kut2 - bik * 1.2))
    vuzly.append((tochky[-1][0], tochky[-1][1], kut))
    # Листки: черешком до вузла, кінчиком у бік росту.
    for vx, vy, napr in vuzly:
        for _ in range(rng.randint(1, 3)):
            lyst = rng.choice(lyst_y)
            mira = k * rng.uniform(0.16, 0.26) / max(lyst.size)
            lyst = lyst.resize((max(1, int(lyst.width * mira)),
                                max(1, int(lyst.height * mira))))
            # У атласі листок стоїть черешком униз — повертаємо так, щоб
            # кінчик дивився вздовж `napr`.
            povorot = -math.degrees(napr + math.pi / 2) \
                + rng.uniform(-35, 35)
            lyst = ImageEnhance.Brightness(lyst).enhance(
                rng.uniform(0.75, 1.1))
            lyst = lyst.rotate(povorot, expand=True,
                               resample=Image.BICUBIC)
            dx = math.cos(napr) * lyst.width * 0.35
            dy = math.sin(napr) * lyst.height * 0.35
            polotno.alpha_composite(
                lyst, (int(vx + dx - lyst.width / 2),
                       int(vy + dy - lyst.height / 2)))
    # Краї м'якші — інакше на відстані блимає драбинка.
    alfa = polotno.getchannel("A").filter(ImageFilter.GaussianBlur(0.8))
    polotno.putalpha(alfa)
    return polotno


def main():
    teka, vykhid = sys.argv[1], Path(sys.argv[2])
    rng = random.Random(int(sys.argv[3]) if len(sys.argv) > 3 else 1)
    lyst_y = lystky(teka)
    if not lyst_y:
        sys.exit("‼ у %s не знайшлось жодного листка" % teka)
    atlas = Image.new("RGBA", (KLITYNKA * 2, KLITYNKA * 2), (0, 0, 0, 0))
    pahin = (78, 62, 44, 255)
    for i in range(4):
        atlas.alpha_composite(klaster(lyst_y, rng, pahin),
                              ((i % 2) * KLITYNKA, (i // 2) * KLITYNKA))
    vykhid.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(vykhid)
    print("[листя] %s: листків %d → %s" % (Path(teka).name, len(lyst_y),
                                          vykhid))


if __name__ == "__main__":
    main()
