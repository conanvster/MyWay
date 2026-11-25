#!/usr/bin/env python3
"""Звести згенерований кадр до вхідного за головою (25.11.2026, П-288, порівняння способів).

Qwen-Edit не тримає кадр: постать на виході більша або зсунута. Голова лиса й не змінюється —
її маківка, ширина й висота до шиї (найвужче місце під головою) на обох кадрах дають масштаб і
зсув; вихід — згенерований кадр, перетягнутий у рамку вхідного (той самий розмір).

    ~/ComfyUI/venv/bin/python tools/zvesty_kadr.py <вхідний.png> <згенерований.png> <вихід.png>
"""
import sys

import numpy as np
from PIL import Image


def holova(a):
    tlo = np.median(np.concatenate([a[:6].reshape(-1, 3), a[:, :6].reshape(-1, 3),
                                    a[:, -6:].reshape(-1, 3)]), 0)
    m = np.abs(a.astype(int) - tlo).sum(2) > 40
    h = a.shape[0]
    shyr, x_c = [], []
    for y in range(h):
        xs = np.nonzero(m[y])[0]
        if len(xs) == 0:
            shyr.append(0); x_c.append(0)
            continue
        c = a.shape[1] // 2
        # суцільний відрізок навколо середини (голова, не руки)
        mid = xs[np.argmin(np.abs(xs - c))]
        l = r = mid
        while l - 1 >= 0 and m[y, l - 1]:
            l -= 1
        while r + 1 < a.shape[1] and m[y, r + 1]:
            r += 1
        shyr.append(r - l + 1); x_c.append((l + r) / 2)
    shyr = np.array(shyr)
    top = int(np.nonzero(shyr > 3)[0][0])
    # від маківки ширина росте; де вперше впала нижче 0,9 найбільшої — шия, голова скінчилась
    sm = np.convolve(shyr, np.ones(5) / 5, mode="same")
    w_max, i_max, y = 0, top, top
    while y < h - 1:
        if sm[y] > w_max:
            w_max, i_max = sm[y], y
        elif sm[y] < 0.9 * w_max and y - top > 10:
            break
        y += 1
    shyia = y
    return top, shyia, w_max, x_c[i_max]


def main():
    a = np.asarray(Image.open(sys.argv[1]).convert("RGB"))
    g_img = Image.open(sys.argv[2]).convert("RGB")
    g = np.asarray(g_img)
    t1, s1, w1, c1 = holova(a)
    t2, s2, w2, c2 = holova(g)
    k = w1 / max(w2, 1)
    # x_вх = c1 + (x_г − c2)·k ; y_вх = t1 + (y_г − t2)·k → зворотне для перетягування
    inv = (1 / k, 0, c2 - c1 / k, 0, 1 / k, t2 - t1 / k)
    out = g_img.transform((a.shape[1], a.shape[0]), Image.AFFINE, inv, Image.BICUBIC,
                          fillcolor=tuple(int(v) for v in np.median(a[:6].reshape(-1, 3), 0)))
    out.save(sys.argv[3])
    print("[звести] масштаб %.3f (голова %d→%d px, ширина %d→%d), маківка %d→%d"
          % (k, s2 - t2, s1 - t1, w2, w1, t2, t1))


if __name__ == "__main__":
    main()
