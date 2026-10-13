#!/usr/bin/env python3
"""Вуха кольором шкіри (13.10.2026): у кадрі ельфійки el-lysa-e1903 FLUX
намалював вуха помаранчево-рожевими, світлішими за обличчя — у скані й
текстурі це вийшло б «накладними» вухами. Зсуваються лише відтінок і
насиченість (a, b у Lab) — середнє вуха до середнього щоки; яскравість
(світлотінь, хрящ) лишається. Тло (сіре, без насиченості) не чіпається.

    ~/Програми/cv-venv/bin/python tools/vukha_kolir.py <кадр.png>   # на місці

Еліпси вух і щоки — у координатах 1024²; кадр будь-якого розміру
(4K — ×4).
"""
import sys

import cv2
import numpy as np

VUKHA = [(460, 108, 16, 23), (560, 108, 16, 23)]
SHCHOKY = [(488, 130, 8, 6), (532, 130, 8, 6)]


def maska(shape, ell, k):
    mm = np.zeros(shape[:2], np.uint8)
    for x, y, a, b in ell:
        cv2.ellipse(mm, (int(x * k), int(y * k)), (int(a * k), int(b * k)), 0, 0, 360, 255, -1)
    return mm


for f in sys.argv[1:]:
    im = cv2.imread(f)
    k = im.shape[1] / 1024
    lab = cv2.cvtColor(im, cv2.COLOR_BGR2LAB).astype(np.float32)
    chroma = np.hypot(lab[..., 1] - 128, lab[..., 2] - 128)
    mv = (maska(im.shape, VUKHA, k) > 0) & (chroma > 12)
    ms = maska(im.shape, SHCHOKY, k) > 0
    zsuv = lab[mv][:, 1:].mean(0) - lab[ms][:, 1:].mean(0)
    w = cv2.GaussianBlur(maska(im.shape, VUKHA, k).astype(np.float32) / 255, (0, 0), 3 * k)
    w *= np.clip((chroma - 6) / 8, 0, 1)
    lab[..., 1:] -= w[..., None] * zsuv
    cv2.imwrite(f, cv2.cvtColor(lab.clip(0, 255).astype(np.uint8), cv2.COLOR_LAB2BGR))
    print(f.split("/")[-1], "зсув a,b", zsuv.round(1))
