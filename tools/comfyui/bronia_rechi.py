#!/usr/bin/env python3
"""Набір броні на e1903 — річ за річчю, кожна у своїй ділянці (13.10.2026).

Слово замовника: «зображення не схоже на іконки в грі — перероби щоб було
схоже»; «додай до зображень для кожного сету сет з іконок, щоб можна було
порівняти». Один довгий промпт на весь набір (`bronia_e1903.py`, s2011–2013)
FLUX зливав у хламиду. Тут кожна річ — окремий прохід inpaint по своїй
ділянці тіла (маска з точок скелета e1903) з коротким описом за її значком;
наступний прохід бере вихід попереднього. Маска кожної речі лишається —
у 3D з неї легше відділити річ від тіла.

    ~/Програми/cv-venv/bin/python -u tools/comfyui/bronia_rechi.py [ключ] [сід…]

Вихід — `wiki/img/test/avatar/e1903-rechi-<ключ>-s<сід>.png`, маски речей
`…-maska-<річ>.png`, аркуш порівняння зі значками —
`art/meshy/2026-10-13/e1903-<ключ>-значки.png`.
"""
import os
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import monster3d as m  # noqa: E402
import elf_nabory_cn as cn  # noqa: E402

D = cn.D
KADR = D / "el-lysa-e1903.png"
IKONKY = Path(__file__).resolve().parents[2] / "game/assets/icons/items"
ARKUSHI = Path(__file__).resolve().parents[2] / "art/meshy/2026-10-13"
cn.SYLA, cn.KINETS = 1.0, 0.9
FON = ("pale elf woman in a T-pose, front view, plain light grey studio "
       "background, photorealistic, realistic worn materials")

# Набір: (річ = значок, ділянка, опис). Порядок — знизу вгору шарами: куртка
# раніше за каптур (накидка каптура лягає на плечі куртки).
NABORY = {
    "E-легкий": [
        ("куртка з кори дуба", "тулуб",
         "a short-sleeved fitted jerkin of ochre leather with carved oak bark "
         "texture and swirling wood grain, small stand-up collar, layered "
         "rectangular bark shoulder pauldrons, grey-green cloth half sleeves "
         "to mid upper arm, a dark red leather band around the waist, short "
         "split flaps ending at the top of the thighs"),
        ("пояс з кори дуба", "пояс",
         "a worn dark brown leather belt with a large square grey iron buckle "
         "worn on the hips"),
        ("каптур зі шкури", "голова",
         "a smooth tan-brown leather hood pulled up over her head, her face "
         "and pointed elf ears visible, the hood falls onto her shoulders as a "
         "short leather capelet with a thin strap"),
        ("рукавички зі шкури", "кисті",
         "smooth tan leather five-finger gloves with flared cuffs to mid "
         "forearm, fingers spread, palms down"),
        ("черевики зі шкури", "ступні",
         "tan leather pull-on boots to mid-calf with slightly slouched shafts, "
         "rounded toe caps and low heels"),
    ],
}


def dilianky(T, rozmir, lm, ramka):
    """Маски ділянок з точок скелета (COCO-18, див. `elf_nabory_cn.PARY`)."""
    w, h = rozmir
    ruka_y = T[2][1]
    sh = lambda a, b, t: (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)  # noqa
    taz_y = T[8][1]
    M = {}

    def nova():
        im = Image.new("L", rozmir, 0)
        return im, ImageDraw.Draw(im)

    # тулуб: від шиї до верху стегон, рукава — до середини плеча
    im, d = nova()
    l_ruk, p_ruk = sh(T[2], T[3], 0.55), sh(T[5], T[6], 0.55)
    d.rectangle((l_ruk[0], ruka_y - 40, p_ruk[0], ruka_y + 32), fill=255)
    d.rectangle((T[2][0] - 10, T[1][1] - 12, T[5][0] + 10, taz_y + 45), fill=255)
    M["тулуб"] = im
    im, d = nova()
    d.rectangle((T[8][0] - 30, taz_y - 30, T[11][0] + 30, taz_y + 10), fill=255)
    M["пояс"] = im
    # голова без обличчя + плечі (накидка)
    im, d = nova()
    x0, x1, y0, y1 = ramka
    d.rectangle((T[16][0] - 45, 0, T[17][0] + 45, T[1][1] + 10), fill=255)
    d.rectangle((T[2][0] - 15, T[1][1] - 10, T[5][0] + 15, ruka_y + 45), fill=255)
    pts = np.array([(x0 + lm[i].x * (x1 - x0), y0 + lm[i].y * (y1 - y0))
                    for i in (10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361,
                              288, 397, 365, 379, 378, 400, 377, 152, 148, 176, 149,
                              150, 136, 172, 58, 132, 93, 234, 127, 162, 21, 54, 103,
                              67, 109)])
    c = pts.mean(0)
    d.polygon([tuple(p) for p in c + (pts - c) * 0.85], fill=0)
    M["голова"] = im
    # кисті: від середини передпліччя до кінчиків пальців
    im, d = nova()
    for kraj, likot in ((T[4], T[3]), (T[7], T[6])):
        zap = sh(kraj, likot, 0.55)
        d.rectangle((min(kraj[0], zap[0]) - 25, ruka_y - 32,
                     max(kraj[0], zap[0]) + 25, ruka_y + 32), fill=255)
    M["кисті"] = im
    # ступні: від середини литки до підлоги
    im, d = nova()
    for kol, kis in ((T[9], T[10]), (T[12], T[13])):
        lytka = sh(kol, kis, 0.35)
        d.rectangle((kis[0] - 38, lytka[1], kis[0] + 38, min(h - 1, kis[1] + 70)), fill=255)
    M["ступні"] = im
    return {k: v.filter(ImageFilter.GaussianBlur(4)) for k, v in M.items()}


def arkush(kliuch, vyhody):
    """Основа, кадри наборів і ряд значків під ними — для порівняння."""
    rechi = [r for r, _, _ in NABORY[kliuch]]
    kadry = [KADR] + vyhody
    s = 512
    ik = 2 * s * len(kadry) // len(rechi) // 2
    W = s * len(kadry)
    H = s + ik + 40
    o = Image.new("RGB", (W, H), (24, 24, 24))
    try:
        sh = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 22)
    except OSError:
        sh = ImageFont.load_default()
    for i, k in enumerate(kadry):
        o.paste(Image.open(k).convert("RGB").resize((s, s)), (i * s, 0))
    krok = W // len(rechi)
    d = ImageDraw.Draw(o)
    for i, r in enumerate(rechi):
        im = Image.open(IKONKY / (r + ".png")).convert("RGB").resize((ik, ik))
        x = i * krok + (krok - ik) // 2
        o.paste(im, (x, s))
        d.text((i * krok + 10, s + ik + 8), r, fill=(230, 220, 200), font=sh)
    ARKUSHI.mkdir(parents=True, exist_ok=True)
    kudy = ARKUSHI / ("e1903-%s-значки.png" % kliuch)
    o.save(kudy)
    print("аркуш", kudy, flush=True)


def main():
    kliuch = next((a for a in sys.argv[1:] if a in NABORY), "E-легкий")
    sidy = [int(a) for a in sys.argv[1:] if a.isdigit()] or [2021, 2022, 2023]
    if "--аркуш" in sys.argv:
        arkush(kliuch, sorted(D.glob("e1903-rechi-%s-s*.png" % kliuch)))
        return
    cn.OSNOVA = KADR
    T, rozmir, lm, ramka = cn.tochky_tila()
    maski = dilianky(T, rozmir, lm, ramka)
    poz = m.stage(str(D / "e1903-cn-poza.png"))
    imena = {}
    for rich, dil, _ in NABORY[kliuch]:
        f = D / ("e1903-rechi-%s-maska-%s.png" % (kliuch, rich.split()[0]))
        maski[dil].save(f)
        imena[rich] = m.stage(str(f))
    m.free()
    vyhody = []
    for seed in sidy:
        kadr = m.stage(str(KADR))
        for n, (rich, dil, opys) in enumerate(NABORY[kliuch]):
            done = m.run(cn.graf(kadr, imena[rich], poz, opys + ". " + FON,
                                 seed + n, "e1903_rich_%d_%d" % (seed, n)))
            out = done["outputs"]["13"]["images"][-1]
            prom = D / ("_e1903-rechi-prom.png")
            shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"], out["filename"]), prom)
            kadr = m.stage(str(prom))
            print("  %s — готово" % rich, flush=True)
        kudy = D / ("e1903-rechi-%s-s%d.png" % (kliuch, seed))
        shutil.copy(prom, kudy)
        prom.unlink()
        vyhody.append(kudy)
        print("готово", kudy.name, flush=True)
    m.free()
    arkush(kliuch, vyhody)


if __name__ == "__main__":
    main()
