#!/usr/bin/env python3
"""Схожість аватара з референсом — рівноцінна до того, що модель має (02.10.2026).

Відмінність від `avatar_ocinka.py`: масштаб — від ступень до рівня очей
(точки обличчя `tools/oblychchia.py` на кадрі й на рендері), бо верх голови
кадру — зачіска, а зачіска моделі — окрема накладка (слово замовника). Тож:

  силует  — IoU без смуги зачіски над бровами (окремо — і з нею);
  колір   — 1 − середня різниця RGB на спільній площі без зачіски;
  тіло    — SSIM яскравості там само;
  обличчя — SSIM прямокутника брови→підборіддя за точками обличчя.

    ~/Програми/cv-venv/bin/python tools/avatar_ocinka2.py <реф.png> \\
        <маска.png> <рендер.png> <аркуш.png>
"""
import json
import os
import subprocess
import sys
import tempfile

import cv2
import numpy as np
from scipy.ndimage import uniform_filter

S = 640
TUT = os.path.dirname(os.path.abspath(__file__))


def tochky(kadr, maska):
    out = tempfile.mktemp(suffix=".npy")
    r = subprocess.run([sys.executable, os.path.join(TUT, "oblychchia.py"),
                        kadr, maska, out], capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("‼ точки обличчя: %s" % (r.stdout + r.stderr)[-300:])
    return np.load(out)


def normuvaty(rgb, maska, L):
    """Ступні — на 0,96 S, очі — на 0,20 S; центр X — медіана тулуба."""
    ys, xs = np.where(maska)
    y_st = ys.max()
    y_oko = (L[33, 1] + L[263, 1]) / 2
    k = (S * 0.76) / (y_st - y_oko)
    vys = y_st - ys.min()
    tul = (ys > y_st - 0.70 * vys) & (ys < y_st - 0.55 * vys)
    cx = np.median(xs[tul])
    M = np.float32([[k, 0, S / 2 - cx * k], [0, k, S * 0.20 - y_oko * k]])
    r = cv2.warpAffine(rgb, M, (S, S), flags=cv2.INTER_AREA,
                       borderValue=(128, 128, 128))
    m = cv2.warpAffine(maska.astype(np.uint8) * 255, M, (S, S),
                       flags=cv2.INTER_NEAREST) > 127
    L2 = L * k + M[:, 2]
    return r.astype(float) / 255, m, L2


def pidihnaty(a, ma, b, mb, Lb):
    """Точне вирівнювання після нормування: масштаб ±3%, зсув ±6 px за
    кореляцією яскравості на спільній площі (2 px зсуву — мінус ~10%)."""
    sira = lambda x: x @ np.array([0.299, 0.587, 0.114])
    ga, gb = sira(a), sira(b)
    best = (-9, None)
    for sk in np.arange(0.97, 1.031, 0.005):
        for dx in range(-6, 7):
            for dy in range(-6, 7):
                M = np.float32([[sk, 0, (1 - sk) * S / 2 + dx],
                                [0, sk, (1 - sk) * S / 2 + dy]])
                g2 = cv2.warpAffine(gb, M, (S, S), flags=cv2.INTER_LINEAR)
                m2 = cv2.warpAffine(mb.astype(np.uint8), M, (S, S),
                                    flags=cv2.INTER_NEAREST) > 0
                sp = ma & m2
                x, y = ga[sp], g2[sp]
                ncc = ((x - x.mean()) * (y - y.mean())).mean() / \
                    (x.std() * y.std() + 1e-6)
                if ncc > best[0]:
                    best = (ncc, M)
    M = best[1]
    b2 = cv2.warpAffine(b, M, (S, S), flags=cv2.INTER_LINEAR,
                        borderValue=(0.5, 0.5, 0.5))
    m2 = cv2.warpAffine(mb.astype(np.uint8), M, (S, S),
                        flags=cv2.INTER_NEAREST) > 0
    Lb2 = Lb * M[0, 0] + M[:, 2]
    return b2, m2, Lb2


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
    ref_p, mref_p, rnd_p, ark_p = sys.argv[1:5]
    ref = cv2.cvtColor(cv2.imread(ref_p), cv2.COLOR_BGR2RGB)
    mref = cv2.imread(mref_p, cv2.IMREAD_GRAYSCALE) > 127
    rgba = cv2.imread(rnd_p, cv2.IMREAD_UNCHANGED)
    mrnd = rgba[..., 3] > 127
    a_ = rgba[..., 3:4] / 255.0
    rnd = (cv2.cvtColor(rgba[..., :3], cv2.COLOR_BGR2RGB) * a_ +
           128 * (1 - a_)).astype(np.uint8)
    t_r = tempfile.mktemp(suffix=".png")
    t_m = tempfile.mktemp(suffix=".png")
    cv2.imwrite(t_r, cv2.cvtColor(rnd, cv2.COLOR_RGB2BGR))
    cv2.imwrite(t_m, mrnd.astype(np.uint8) * 255)
    La, Lb = tochky(ref_p, mref_p), tochky(t_r, t_m)
    a, ma, La2 = normuvaty(ref, mref, La)
    b, mb, Lb2 = normuvaty(rnd, mrnd, Lb)
    b, mb, Lb2 = pidihnaty(a, ma, b, mb, Lb2)
    # Смуга зачіски: вище найвищої точки брів (за кадром) — поза мірою.
    brovy = min(La2[[70, 63, 105, 66, 107, 336, 296, 334, 293, 300], 1])
    bez = np.ones((S, S), bool)
    bez[: int(brovy) - 4, :] = False
    # Одяг кадру (шорти) — теж окрема частина, не тіло: темні ненасичені
    # пікселі фігури, розширені на 3 px. Повна цифра з ним — окремо.
    hsv = cv2.cvtColor((a * 255).astype(np.uint8), cv2.COLOR_RGB2HSV)
    odiah = ma & (hsv[..., 2] < 70)
    odiah = cv2.dilate(odiah.astype(np.uint8), np.ones((7, 7), np.uint8)) > 0
    odiah = cv2.morphologyEx(odiah.astype(np.uint8), cv2.MORPH_CLOSE,
                             np.ones((15, 15), np.uint8)) > 0
    bez_z_odiahom = bez.copy()
    bez = bez & ~odiah
    sp = ma & mb & bez
    iou_bez = (ma & mb & bez).sum() / max(1, ((ma | mb) & bez).sum())
    iou_z = (ma & mb).sum() / max(1, (ma | mb).sum())
    kolir = 1 - np.abs(a - b)[sp].mean()
    sira = lambda x: x @ np.array([0.299, 0.587, 0.114])
    tilo = ssim(sira(a), sira(b), sp)
    x0, x1 = int(La2[:, 0].min()), int(La2[:, 0].max())
    y0, y1 = int(brovy), int(La2[152, 1])
    obl = np.zeros((S, S), bool)
    obl[y0:y1, x0:x1] = True
    oblychchia = ssim(sira(a), sira(b), obl & ma & mb)
    # Діагностика (не в підсумку): обличчя з власним дорівнюванням ±3 px,
    # ±3% — чи падіння обличчя від форми, чи від зсуву всієї постаті.
    ga_, gb_ = sira(a), sira(b)
    obl_lok = oblychchia
    cy, cx = (y0 + y1) / 2, (x0 + x1) / 2
    for sk in (0.97, 0.985, 1.0, 1.015, 1.03):
        for dx in range(-3, 4):
            for dy in range(-3, 4):
                M_ = np.float32([[sk, 0, (1 - sk) * cx + dx],
                                 [0, sk, (1 - sk) * cy + dy]])
                g2 = cv2.warpAffine(gb_, M_, (S, S), flags=cv2.INTER_LINEAR)
                m2_ = cv2.warpAffine(mb.astype(np.uint8), M_, (S, S),
                                     flags=cv2.INTER_NEAREST) > 0
                obl_lok = max(obl_lok, ssim(ga_, g2, obl & ma & m2_))
    pids = 0.25 * (iou_bez + kolir + tilo + oblychchia)
    iou_odiah = (ma & mb & bez_z_odiahom).sum() / \
        max(1, ((ma | mb) & bez_z_odiahom).sum())
    rez = {"силует": round(float(iou_bez), 3),
           "силует із зачіскою": round(float(iou_z), 3),
           "силует з шортами": round(float(iou_odiah), 3),
           "колір": round(float(kolir), 3), "тіло": round(tilo, 3),
           "обличчя": round(oblychchia, 3),
           "обличчя локально": round(obl_lok, 3), "підсумок": round(float(pids), 3),
           "зсув очей, px": round(float(np.linalg.norm(
               La2[[33, 263]] - Lb2[[33, 263]], axis=1).mean()), 2)}
    print(json.dumps(rez, ensure_ascii=False))
    rizn = np.abs(a - b) * (ma & mb)[..., None]
    # Силуети: червоне — лише на кадрі, зелене — лише в моделі (у мірі).
    sil = np.zeros_like(a)
    sil[ma & mb] = 0.35
    sil[ma & ~mb & bez] = (1, 0, 0)
    sil[mb & ~ma & bez] = (0, 1, 0)
    ark = np.concatenate([a, b * mb[..., None] + (1 - mb[..., None]) * 0.5,
                          np.clip(rizn * 3, 0, 1), sil], axis=1)
    cv2.imwrite(ark_p, cv2.cvtColor((ark * 255).astype(np.uint8),
                                    cv2.COLOR_RGB2BGR))


if __name__ == "__main__":
    main()
