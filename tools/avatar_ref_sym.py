#!/usr/bin/env python3
"""Референс аватара: ступні спереду й симетрія (02.10.2026).

Слова замовника: «спробуй вирівняти референс щоб він був симетричний,
наприклад можна взяти якусь половину і відзеркалити» і «на референсі
ступні зроблені як вигляд згори а на моделі вигляд спереду, виправ
референс».

1. Ступні: кроп ×2 із перемальованими ступнями (FLUX dev під маскою,
   `tools/comfyui/avatar_ref_stopy.py --маска`) зменшується назад і
   вклеюється з розмитим краєм маски; тон підганяється під кадр по смузі
   гомілок над маскою.
2. Вісь тіла — пряма через середину обличчя (точки 168, 1, 152 MediaPipe)
   і медіану тулуба (маска між пахвами й поясом); половина відзеркалюється
   через неї, шов розмивається на ±3 px.

    ~/Програми/cv-venv/bin/python tools/avatar_ref_sym.py <кадр.png>
        <маска.png> <точки.npy> <ступні_кроп.png> <маска_кропу.png> <тека>
→ <тека>/plavky-stopy-s411.png, plavky-sym-l-s411.png, plavky-sym-r-s411.png
"""
import sys

import cv2
import numpy as np

KROP = (240, 512, 752, 1024)      # як у avatar_ref_stopy.py


def vklejity_stupni(img, krop_png, maska_png):
    x0, y0, x1, y1 = KROP
    w, h = x1 - x0, y1 - y0
    nove = cv2.resize(cv2.imread(krop_png), (w, h),
                      interpolation=cv2.INTER_AREA).astype(np.float32)
    mk = cv2.resize(cv2.imread(maska_png, 0), (w, h),
                    interpolation=cv2.INTER_AREA).astype(np.float32) / 255
    mk = cv2.GaussianBlur(mk, (0, 0), 6)
    stare = img[y0:y1, x0:x1].astype(np.float32)
    # Тон: смуга над маскою (гомілки й тло) — однакова в обох.
    ys = np.where(mk.max(1) > 0.5)[0]
    smuha = slice(max(0, ys.min() - 40), ys.min() - 8)
    k = stare[smuha].reshape(-1, 3).mean(0) / \
        np.maximum(nove[smuha].reshape(-1, 3).mean(0), 1)
    nove = np.clip(nove * k, 0, 255)
    out = img.copy()
    out[y0:y1, x0:x1] = (stare * (1 - mk[..., None]) +
                         nove * mk[..., None]).astype(np.uint8)
    return out


def vis(maska, L):
    """Вісь як x = a·y + b (у пікселях кадру)."""
    pts = [L[i] for i in (168, 6, 1, 152)]
    ys, xs = np.where(maska)
    top, bot = ys.min(), ys.max()
    hgt = bot - top
    for fr in np.linspace(0.30, 0.45, 8):
        y = int(top + fr * hgt)
        row = np.where(maska[y])[0]
        # лише тулуб: найширший суцільний відрізок навколо центру
        seg = np.split(row, np.where(np.diff(row) > 1)[0] + 1)
        c = min(seg, key=lambda s: abs(s.mean() - L[1, 0]))
        pts.append((c.mean(), y))
    p = np.array(pts, float)
    a, b = np.polyfit(p[:, 1], p[:, 0], 1)
    return a, b


def dzerkalo(img, a, b, zlivoi):
    h, w = img.shape[:2]
    yy, xx = np.mgrid[:h, :w].astype(np.float32)
    os_x = a * yy + b
    mx = (2 * os_x - xx).astype(np.float32)
    vidb = cv2.remap(img, mx, yy, cv2.INTER_LINEAR,
                     borderMode=cv2.BORDER_REPLICATE)
    # zlivoi: ліва половина кадру лишається, права — її дзеркало.
    d = xx - os_x if zlivoi else os_x - xx
    t = np.clip((d + 3) / 6, 0, 1)[..., None]
    return (img * (1 - t) + vidb * t).astype(np.uint8)


def main():
    kadr, maska, tochky, krop, krop_m, teka = sys.argv[1:7]
    img = cv2.imread(kadr)
    img = vklejity_stupni(img, krop, krop_m)
    cv2.imwrite(teka + "/plavky-stopy-s411.png", img)
    m = cv2.imread(maska, 0) > 127
    L = np.load(tochky)
    a, b = vis(m, L)
    print("вісь: x = %.4f·y + %.1f (нахил %.2f°)"
          % (a, b, np.degrees(np.arctan(a))))
    for imia, zl in (("l", True), ("r", False)):
        cv2.imwrite(teka + "/plavky-sym-%s-s411.png" % imia,
                    dzerkalo(img, a, b, zl))


if __name__ == "__main__":
    main()
