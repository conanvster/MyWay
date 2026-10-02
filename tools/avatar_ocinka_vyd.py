#!/usr/bin/env python3
"""Оцінка схожості збоку й ззаду (02.10.2026) — до `avatar_ocinka2.py`.

Слово замовника: «я оціюю модель чоловіка на 65-70% , можливо через те що
ненадали вигляду з боку та з заду і не порівняли». Обличчя тут не видно,
тож міра — силует, колір і SSIM тіла (без зачіски й одягу, тло однакове).
Масштаб — від ступень до очей, як спереду: на кадрі рівень очей — та сама
частка висоти фігури з зачіскою, що на кадрі спереду (та сама людина);
у рендері — центр очних яблук (`avatar_render.py` пише його в .json).

    ~/Програми/cv-venv/bin/python tools/avatar_ocinka_vyd.py <кадр> <маска>
        <рендер.png> <аркуш.png> <маска_спереду> <точки_спереду.npy>
"""
import json
import os
import sys

import cv2
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import avatar_ocinka2 as O  # noqa: E402

S = O.S


def norm(rgb, maska, oko_y):
    ys, xs = np.where(maska)
    y_st = ys.max()
    k = (S * 0.76) / (y_st - oko_y)
    vys = y_st - ys.min()
    tul = (ys > y_st - 0.70 * vys) & (ys < y_st - 0.55 * vys)
    cx = np.median(xs[tul])
    M = np.float32([[k, 0, S / 2 - cx * k], [0, k, S * 0.20 - oko_y * k]])
    r = cv2.warpAffine(rgb, M, (S, S), flags=cv2.INTER_AREA,
                       borderValue=(128, 128, 128))
    m = cv2.warpAffine(maska.astype(np.uint8) * 255, M, (S, S),
                       flags=cv2.INTER_NEAREST) > 127
    return r.astype(float) / 255, m


def main():
    ref_p, mref_p, rnd_p, ark_p, mpered_p, tochky_p = sys.argv[1:7]
    ref = cv2.cvtColor(cv2.imread(ref_p), cv2.COLOR_BGR2RGB)
    mref = cv2.imread(mref_p, cv2.IMREAD_GRAYSCALE) > 127
    # Розпущене волосся — не тіло (те саме правило, що в підборі,
    # `mpfb_pidbir.bez_volossia`; рядок 0 тут — верх).
    temne = ref.max(-1) < 56
    ys_, xs_ = np.where(mref)
    y0_, y1_ = ys_.min(), ys_.max() + 1
    vys_ = y1_ - y0_
    yy_ = np.arange(mref.shape[0])[:, None]
    if "--бік" in sys.argv:
        tul_ = (ys_ < y0_ + 0.45 * vys_) & (ys_ > y0_ + 0.30 * vys_)
        cx_ = float(np.median(xs_[tul_]))
        volos = temne & (yy_ < y1_ - 0.70 * vys_) & \
            (np.arange(mref.shape[1])[None, :] > cx_)
    else:
        volos = temne & (yy_ < y1_ - 0.78 * vys_)
    mref = mref & ~volos
    mper = cv2.imread(mpered_p, cv2.IMREAD_GRAYSCALE) > 127
    L = np.load(tochky_p)
    yp = np.where(mper.any(1))[0]
    oko_f = (L[33, 1] + L[263, 1]) / 2
    chastka = (yp.max() - oko_f) / (yp.max() - yp.min())
    yv = np.where(mref.any(1))[0]
    oko_ref = yv.max() - chastka * (yv.max() - yv.min())
    rgba = cv2.imread(rnd_p, cv2.IMREAD_UNCHANGED)
    mrnd = rgba[..., 3] > 127
    a_ = rgba[..., 3:4] / 255.0
    rnd = (cv2.cvtColor(rgba[..., :3], cv2.COLOR_BGR2RGB) * a_ +
           128 * (1 - a_)).astype(np.uint8)
    oko_rnd = json.load(open(rnd_p + ".json"))["око"][1]
    a, ma = norm(ref, mref, oko_ref)
    b, mb = norm(rnd, mrnd, oko_rnd)
    a[~ma] = 0.5
    # Грубий зсув по горизонталі ±30 px (у профіль центр за тулубом збиває
    # рука), тоді звичне точне дорівнювання.
    dx = max(range(-30, 31, 2), key=lambda d: (ma & np.roll(mb, d, 1)).sum()
             / max(1, (ma | np.roll(mb, d, 1)).sum()))
    b, mb = np.roll(b, dx, 1), np.roll(mb, dx, 1)
    b, mb, _ = O.pidihnaty(a, ma, b, mb, np.zeros((478, 2)))
    bez = np.ones((S, S), bool)
    bez[: int(S * 0.20 - 0.05 * S), :] = False        # зачіска
    hsv = cv2.cvtColor((a * 255).astype(np.uint8), cv2.COLOR_RGB2HSV)
    odiah = ma & (hsv[..., 2] < 70)
    odiah = cv2.dilate(odiah.astype(np.uint8), np.ones((7, 7), np.uint8)) > 0
    odiah = cv2.morphologyEx(odiah.astype(np.uint8), cv2.MORPH_CLOSE,
                             np.ones((15, 15), np.uint8)) > 0
    bez_o = bez & ~odiah
    sp = ma & mb & bez_o
    iou = (ma & mb & bez_o).sum() / max(1, ((ma | mb) & bez_o).sum())
    kolir = 1 - np.abs(a - b)[sp].mean()
    sira = lambda x: x @ np.array([0.299, 0.587, 0.114])
    tilo = O.ssim(sira(a), sira(b), sp)
    rez = {"силует": round(float(iou), 3), "колір": round(float(kolir), 3),
           "тіло": round(tilo, 3),
           "підсумок": round(float((iou + kolir + tilo) / 3), 3)}
    print(json.dumps(rez, ensure_ascii=False))
    sil = np.zeros_like(a)
    sil[ma & mb] = 0.35
    sil[ma & ~mb & bez] = (1, 0, 0)
    sil[mb & ~ma & bez] = (0, 1, 0)
    ark = np.concatenate([a, b * mb[..., None] + (1 - mb[..., None]) * 0.5,
                          sil], axis=1)
    cv2.imwrite(ark_p, cv2.cvtColor((ark * 255).astype(np.uint8),
                                    cv2.COLOR_RGB2BGR))


if __name__ == "__main__":
    main()
