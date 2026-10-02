#!/usr/bin/env python3
"""Вирівняти висоти референсу збоку / ззаду під перед (02.10.2026).

Слово замовника: «Вирівняй вивоту в усіх проекціях щоб вони збігалися за
вимотою 3D моделі, висота поясу, грудей, плечей, голови». Модель підбирається
під кадр спереду, тож решта кадрів стає на його висоти.

Опори — рядки, знайдені в самому кадрі: верх голови (з пучком — зачіска в
усіх ракурсах одна), верх і низ бюстгальтера, верх і низ шортів (дві темні
смуги в силуеті), ступні. Кадр збоку чи ззаду переноситься в рамку переду:
по горизонталі — один масштаб (за висотою фігури) з центром за тулубом, по
вертикалі — кусково-лінійно між опорами, тож кожна лінія стає точно на
висоту переду. Маска — так само.

    ~/Програми/cv-venv/bin/python tools/avatar_ref_vysoty.py <перед.png>
        <маска_переду.png> <кадр.png> <маска.png> <вихід.png> <маска_виходу.png>
"""
import sys

import cv2
import numpy as np


def opory(img, mk):
    """[верх, верх бюстгальтера, низ бюстгальтера, верх шортів, низ шортів,
    ступні] — рядки зверху."""
    ys, xs = np.where(mk)
    y0, y1 = ys.min(), ys.max()
    vys = y1 - y0
    temne = (img.max(-1) < 56) & mk
    chastka = temne.sum(1) / np.maximum(mk.sum(1), 1)
    ryad = np.arange(len(chastka))
    # Смуги купальника — між 15% і 75% висоти від маківки (вище — пучок і
    # обличчя, нижче — ноги).
    v_zoni = (ryad > y0 + 0.15 * vys) & (ryad < y0 + 0.75 * vys)
    smuha = (chastka > 0.35) & v_zoni
    seg, poch = [], None
    for y in range(len(smuha)):
        if smuha[y] and poch is None:
            poch = y
        if not smuha[y] and poch is not None:
            if y - poch > 0.02 * vys:
                seg.append((poch, y - 1))
            poch = None
    if len(seg) < 2:
        raise SystemExit("‼ смуг купальника не дві, а %d: %s" % (len(seg), seg))
    (b0, b1), (s0, s1) = seg[0], seg[-1]
    return np.array([y0, b0, b1, s0, s1, y1], float)


def tsentr(mk):
    ys, xs = np.where(mk)
    y0, y1 = ys.min(), ys.max()
    vys = y1 - y0
    tul = (ys > y0 + 0.30 * vys) & (ys < y0 + 0.45 * vys)
    return float(np.median(xs[tul]))


def main():
    per_p, mper_p, kadr_p, mk_p, vyh_p, mvyh_p = sys.argv[1:7]
    per = cv2.imread(per_p)
    mper = cv2.imread(mper_p, 0) > 127
    kadr = cv2.imread(kadr_p)
    mk = cv2.imread(mk_p, 0) > 127
    a_f = opory(cv2.cvtColor(per, cv2.COLOR_BGR2RGB), mper)
    a_v = opory(cv2.cvtColor(kadr, cv2.COLOR_BGR2RGB), mk)
    print("опори переду:", a_f.astype(int).tolist())
    print("опори кадру: ", a_v.astype(int).tolist())
    s_x = (a_v[-1] - a_v[0]) / (a_f[-1] - a_f[0])
    cx_f, cx_v = tsentr(mper), tsentr(mk)
    h, w = per.shape[:2]
    yy, xx = np.mgrid[:h, :w].astype(np.float32)
    # Поза опорами — продовження крайнім масштабом.
    a_f2 = np.concatenate([[a_f[0] - 1000], a_f, [a_f[-1] + 1000]])
    a_v2 = np.concatenate([[a_v[0] - 1000 * s_x], a_v,
                           [a_v[-1] + 1000 * s_x]])
    sy = np.interp(yy[:, 0], a_f2, a_v2).astype(np.float32)
    map_y = np.repeat(sy[:, None], w, 1)
    map_x = (cx_v + (xx - cx_f) * s_x).astype(np.float32)
    tlo = tuple(int(c) for c in np.median(kadr[:20, :20].reshape(-1, 3), 0))
    out = cv2.remap(kadr, map_x, map_y, cv2.INTER_LINEAR,
                    borderMode=cv2.BORDER_CONSTANT, borderValue=tlo)
    mout = cv2.remap(mk.astype(np.uint8) * 255, map_x, map_y,
                     cv2.INTER_NEAREST, borderValue=0)
    cv2.imwrite(vyh_p, out)
    cv2.imwrite(mvyh_p, mout)
    a_o = opory(cv2.cvtColor(out, cv2.COLOR_BGR2RGB), mout > 127)
    print("опори після:  ", a_o.astype(int).tolist(),
          "(розбіжність з передом, px: %s)"
          % np.abs(a_o - a_f).astype(int).tolist())


if __name__ == "__main__":
    main()
