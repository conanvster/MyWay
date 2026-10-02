#!/usr/bin/env python3
"""Схожість моделі аватара з референсом — числом (02.10.2026).

Слово замовника: «зроби ітераційно з перевірками 3D модель чоловіка
схожою на референс не менш як на 95%». Рендер моделі спереду
(`tools/blender/avatar_render.py`) і референс вирівнюються за габаритом
фігури (маска референсу — birefnet), тоді:

  силует  — IoU масок;
  колір   — 1 − середня різниця RGB на спільній площі (0…1);
  тіло    — SSIM яскравості на спільній площі;
  обличчя — SSIM верхніх 13% фігури (голова), по центру.

Підсумок — середнє з вагами 0,25 · 0,25 · 0,25 · 0,25. Аркуш
«референс | модель | різниця» — поруч із кадром.

    ~/ComfyUI/venv/bin/python tools/avatar_ocinka.py <реф.png> <маска.png> \\
        <рендер.png> <аркуш.png>
"""
import json
import sys

import numpy as np
from PIL import Image
from scipy.ndimage import uniform_filter

W, H = 640, 640   # квадрат: у T-позі руки з кистями ширші за 0,5 висоти


def obrizaty(rgb, maska):
    """Кадр фігури зі ЗБЕРЕЖЕННЯМ пропорцій: масштаб — за висотою, центр
    — за габаритом. Розтягнення ширини окремо стискало все по X (ширину
    задають кінчики пальців, різні в моделі й на кадрі)."""
    ys, xs = np.where(maska)
    y0, y1 = ys.min(), ys.max() + 1
    cx = (xs.min() + xs.max() + 1) / 2
    shyr = (y1 - y0) * W / H
    x0 = int(round(cx - shyr / 2))
    x1 = x0 + int(round(shyr))
    hh, ww = maska.shape
    pad = max(0, -x0, x1 - ww)
    rgb_p = np.pad(rgb, ((0, 0), (pad, pad), (0, 0)), constant_values=0.5)
    m_p = np.pad(maska, ((0, 0), (pad, pad)))
    x0 += pad
    x1 += pad
    r = Image.fromarray((rgb_p[y0:y1, x0:x1] * 255).astype(np.uint8)) \
        .resize((W, H), Image.LANCZOS)
    m = Image.fromarray((m_p[y0:y1, x0:x1] * 255).astype(np.uint8)) \
        .resize((W, H), Image.NEAREST)
    return np.asarray(r).astype(float) / 255, np.asarray(m) > 127


def zsunuty(b, mb, sx, sy, dx, dy):
    """Масштаб навколо центру й зсув — без scipy.ndimage.affine (повільно)."""
    hh, ww = mb.shape
    ys = ((np.arange(hh) - hh / 2 - dy) / sy + hh / 2).round().astype(int)
    xs = ((np.arange(ww) - ww / 2 - dx) / sx + ww / 2).round().astype(int)
    ok_y = (ys >= 0) & (ys < hh)
    ok_x = (xs >= 0) & (xs < ww)
    ys, xs = np.clip(ys, 0, hh - 1), np.clip(xs, 0, ww - 1)
    m2 = mb[ys][:, xs] & ok_y[:, None] & ok_x[None, :]
    b2 = b[ys][:, xs]
    return b2, m2


def pidihnaty(a, ma, b, mb):
    """Масштаб і зсув, за яких ВМІСТ збігається найкраще: кореляція
    яскравості на спільній площі + трохи силуету. За самим силуетом
    обличчя з'їжджало (кисті манекена тягнули масштаб)."""
    sira = lambda x: x @ np.array([0.299, 0.587, 0.114])
    ga, gb = sira(a)[::2, ::2], sira(b)[::2, ::2]
    ma2, mb2 = ma[::2, ::2], mb[::2, ::2]
    krashche = (-9, 1, 1, 0, 0)
    for sx in np.arange(0.94, 1.061, 0.01):
        for sy in np.arange(0.94, 1.061, 0.01):
            for dx in range(-6, 7):
                for dy in range(-10, 11):
                    g2, m2 = zsunuty(gb, mb2, sx, sy, dx, dy)
                    sp = ma2 & m2
                    if sp.sum() < 100:
                        continue
                    x, y = ga[sp], g2[sp]
                    ncc = ((x - x.mean()) * (y - y.mean())).mean() / \
                        (x.std() * y.std() + 1e-6)
                    iou = sp.sum() / max(1, (ma2 | m2).sum())
                    mira = ncc + 0.3 * iou
                    if mira > krashche[0]:
                        krashche = (mira, sx, sy, dx * 2, dy * 2)
    _, sx, sy, dx, dy = krashche
    print("вирівнювання: масштаб %.2f×%.2f, зсув %+d/%+d px"
          % (sx, sy, dx, dy), file=sys.stderr)
    return zsunuty(b, mb, sx, sy, dx, dy)


def ssim(a, b, m):
    k = 7
    mu_a, mu_b = uniform_filter(a, k), uniform_filter(b, k)
    va = uniform_filter(a * a, k) - mu_a ** 2
    vb = uniform_filter(b * b, k) - mu_b ** 2
    cov = uniform_filter(a * b, k) - mu_a * mu_b
    c1, c2 = 0.01 ** 2, 0.03 ** 2
    s = ((2 * mu_a * mu_b + c1) * (2 * cov + c2)) / \
        ((mu_a ** 2 + mu_b ** 2 + c1) * (va + vb + c2))
    return float(s[m].mean()) if m.any() else 0.0


def main():
    ref = np.asarray(Image.open(sys.argv[1]).convert("RGB")).astype(float) / 255
    mref = np.asarray(Image.open(sys.argv[2]).convert("L")) > 127
    rnd = np.asarray(Image.open(sys.argv[3]).convert("RGBA")).astype(float) / 255
    mrnd = rnd[..., 3] > 0.5
    a, ma = obrizaty(ref, mref)
    b, mb = obrizaty(rnd[..., :3], mrnd)
    # Кадрування не має впливати на схожість: габарит моделі ширший за
    # габарит скану (кисті манекена), і вирівнювання за габаритом зсувало
    # масштаб. Шукаємо масштаб ±6% і зсув ±8 px з найбільшим IoU.
    b, mb = pidihnaty(a, ma, b, mb)
    spilne = ma & mb
    iou = (ma & mb).sum() / max(1, (ma | mb).sum())
    kolir = 1 - np.abs(a - b)[spilne].mean()
    sira = lambda x: x @ np.array([0.299, 0.587, 0.114])
    tilo = ssim(sira(a), sira(b), spilne)
    holova = np.zeros_like(spilne)
    holova[: int(H * 0.13), int(W * 0.42): int(W * 0.58)] = True
    oblychchia = ssim(sira(a), sira(b), spilne & holova)
    pidsumok = 0.25 * (iou + kolir + tilo + oblychchia)
    rez = {"силует": round(float(iou), 3), "колір": round(float(kolir), 3),
           "тіло": round(tilo, 3), "обличчя": round(oblychchia, 3),
           "підсумок": round(float(pidsumok), 3)}
    print(json.dumps(rez, ensure_ascii=False))
    riznytsia = np.abs(a - b) * spilne[..., None]
    arkush = np.concatenate([a, b * mb[..., None] + (1 - mb[..., None]) * 0.5,
                             np.clip(riznytsia * 3, 0, 1)], axis=1)
    Image.fromarray((arkush * 255).astype(np.uint8)).save(sys.argv[4])


if __name__ == "__main__":
    main()
