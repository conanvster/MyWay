#!/usr/bin/env python3
"""Звести референси збоку й ззаду до переду за висотами й розмірами
(02.10.2026).

Слово замовника: «спробуй створити ідеальний рендер з усіх 3 сторін щоб він
співпадав по висоті та основним розмірам (ступні, коліна, пояс, груди,
плечі, лікті, запястя, шия, вуха, верхівка голови). Спочатку добийся того
щоб референси співпадали, модливо спробуй їх виправити стиснувши чи
розтягнувши».

1. Висоти (бік і зад): кусково-лінійно по вертикалі між опорами — маківка,
   шия (найвужче над плечима), пахви (де кінчаються руки, лише спереду й
   ззаду), верх і низ бюстгальтера, верх і низ шортів, коліна (звуження ноги
   між шортами й ступнями), щиколотки, ступні.
2. Ширини (лише зад — та сама постать, тож силует ззаду дзеркальний до
   переду): у кожному рядку відрізки силуету (руки, тулуб, ноги) ззаду
   ставляться на відрізки віддзеркаленого переду; зсув по горизонталі
   розмивається між рядками. Так сходяться зап'ястя, лікті, плечі, стегна,
   коліна, розмах рук.

    ~/Програми/cv-venv/bin/python tools/avatar_ref_vyrivniaty.py <перед.png>
        <маска_переду> <кадр.png> <маска> <вихід.png> <маска_виходу> бік|зад
"""
import sys

import cv2
import numpy as np


def vidrizky(ryadok):
    """[(x0, x1)] суцільних відрізків маски в рядку."""
    x = np.where(ryadok)[0]
    if len(x) == 0:
        return []
    rozryv = np.where(np.diff(x) > 1)[0]
    poch = np.concatenate([[x[0]], x[rozryv + 1]])
    kin = np.concatenate([x[rozryv], [x[-1]]])
    return [(a, b) for a, b in zip(poch, kin) if b - a >= 2]


def opory(img, mk, z_rukamy):
    ys, xs = np.where(mk)
    y0, y1 = ys.min(), ys.max()
    vys = y1 - y0
    ryad = np.arange(mk.shape[0])
    shyr = mk.sum(1)
    temne = (img.max(-1) < 56) & mk
    chastka = temne.sum(1) / np.maximum(shyr, 1)
    smuha = (chastka > 0.35) & (ryad > y0 + 0.15 * vys) & (ryad < y0 + 0.75 * vys)
    seg, poch = [], None
    for y in range(len(smuha)):
        if smuha[y] and poch is None:
            poch = y
        if not smuha[y] and poch is not None:
            if y - poch > 0.02 * vys:
                seg.append((poch, y - 1))
            poch = None
    if len(seg) < 2:
        raise SystemExit("‼ смуг купальника %d: %s" % (len(seg), seg))
    (b0, b1), (s0, s1) = seg[0], seg[-1]
    # шия — найвужчий «тулубний» відрізок між маківкою й бюстгальтером
    def tulub_shyr(y):
        v = vidrizky(mk[y])
        if not v:
            return 1e9
        c = np.median(xs)
        a, b = min(v, key=lambda r: abs((r[0] + r[1]) / 2 - c))
        return b - a
    zona = range(int(y0 + 0.06 * vys), int(b0 - 0.02 * vys))
    shyia = min(zona, key=tulub_shyr)
    op = {"маківка": y0, "шия": shyia}
    if z_rukamy:
        # пахви — останній рядок, де силует ширший за 3 ширини тулуба
        t = tulub_shyr(int((b0 + b1) / 2))
        ruky = [y for y in range(shyia, b1) if shyr[y] > 3 * t]
        if ruky:
            op["пахви"] = max(ruky) + 1
    op.update({"бюстгальтер верх": b0, "бюстгальтер низ": b1,
               "шорти верх": s0, "шорти низ": s1})
    # коліна й щиколотки — звуження однієї ноги
    def noha(y):
        v = vidrizky(mk[y])
        return min((b - a for a, b in v), default=1e9) if len(v) >= 2 \
            else (v[0][1] - v[0][0] if v else 1e9)
    lo = s1 + int(0.35 * (y1 - s1))
    hi = s1 + int(0.62 * (y1 - s1))
    op["коліна"] = min(range(lo, hi), key=noha)
    op["щиколотки"] = min(range(s1 + int(0.80 * (y1 - s1)),
                                y1 - int(0.02 * vys)), key=noha)
    op["ступні"] = y1
    return op


def vysoty(per, mper, kadr, mk, z_rukamy):
    o_f = opory(per, mper, True)
    o_v = opory(kadr, mk, z_rukamy)
    # Коліна й щиколотки — лише для звіту: «звуження ноги» на кадрі спереду
    # знаходило не коліно (846 px замість ~740), і гомілки збоку
    # спотворювались. Між низом шортів і ступнями — рівномірно.
    kl = [k for k in o_f if k in o_v and k not in ("коліна", "щиколотки")]
    a_f = np.array([o_f[k] for k in kl], float)
    a_v = np.array([o_v[k] for k in kl], float)
    pory = np.argsort(a_f)
    a_f, a_v = a_f[pory], a_v[pory]
    s = (a_v[-1] - a_v[0]) / (a_f[-1] - a_f[0])
    a_f2 = np.concatenate([[a_f[0] - 1000], a_f, [a_f[-1] + 1000]])
    a_v2 = np.concatenate([[a_v[0] - 1000 * s], a_v, [a_v[-1] + 1000 * s]])
    return kl, o_f, o_v, a_f2, a_v2, s


def tsentr(mk):
    ys, xs = np.where(mk)
    y0, y1 = ys.min(), ys.max()
    vys = y1 - y0
    tul = (ys > y0 + 0.30 * vys) & (ys < y0 + 0.45 * vys)
    return float(np.median(xs[tul]))


def main():
    per_p, mper_p, kadr_p, mk_p, vyh_p, mvyh_p, vyd = sys.argv[1:8]
    per = cv2.cvtColor(cv2.imread(per_p), cv2.COLOR_BGR2RGB)
    mper = cv2.imread(mper_p, 0) > 127
    kadr_bgr = cv2.imread(kadr_p)
    kadr = cv2.cvtColor(kadr_bgr, cv2.COLOR_BGR2RGB)
    mk = cv2.imread(mk_p, 0) > 127
    h, w = mper.shape
    kl, o_f, o_v, a_f2, a_v2, s = vysoty(per, mper, kadr, mk, vyd == "зад")
    print("опори:", {k: (int(o_f[k]), int(o_v[k])) for k in kl})
    cx_f, cx_v = tsentr(mper), tsentr(mk)
    yy, xx = np.mgrid[:h, :w].astype(np.float32)
    sy = np.interp(np.arange(h), a_f2, a_v2).astype(np.float32)
    map_y = np.repeat(sy[:, None], w, 1)
    map_x = (cx_v + (xx - cx_f) * s).astype(np.float32)
    tlo = tuple(int(c) for c in np.median(kadr_bgr[:20, :20].reshape(-1, 3), 0))
    krok1 = cv2.remap(kadr_bgr, map_x, map_y, cv2.INTER_LINEAR,
                      borderMode=cv2.BORDER_CONSTANT, borderValue=tlo)
    m1 = cv2.remap(mk.astype(np.uint8) * 255, map_x, map_y,
                   cv2.INTER_NEAREST) > 127
    out, mout = krok1, m1
    if vyd == "зад":
        # Ширини: дзеркальний перед — ціль; у кожному рядку відрізки
        # ставляться відрізок на відрізок, якщо їх стільки ж.
        tsil = mper[:, ::-1]
        sx = np.tile(np.arange(w, dtype=np.float32), (h, 1))
        dx = np.zeros((h, w), np.float32)
        vaga = np.zeros(h, np.float32)
        for y in range(h):
            vt, vk = vidrizky(tsil[y]), vidrizky(m1[y])
            if not vt or len(vt) != len(vk):
                continue
            xs_t = np.array([p for r in vt for p in r], float)
            xs_k = np.array([p for r in vk for p in r], float)
            # позиція в кадрі для кожного x цілі (кусково-лінійно)
            dx[y] = np.interp(np.arange(w), xs_t, xs_k,
                              left=xs_k[0] - xs_t[0] + 0,
                              right=xs_k[-1] - xs_t[-1] + 0) - np.arange(w)
            dx[y, :int(xs_t[0])] = xs_k[0] - xs_t[0]
            dx[y, int(xs_t[-1]):] = xs_k[-1] - xs_t[-1]
            vaga[y] = 1
        # Рядки без пари — з сусідів; згладити між рядками.
        ok = vaga > 0
        if ok.sum() > 10:
            idx = np.where(ok)[0]
            for y in np.where(~ok)[0]:
                dx[y] = dx[idx[np.argmin(np.abs(idx - y))]]
        dx = cv2.GaussianBlur(dx, (0, 0), sigmaX=1.5, sigmaY=6)
        map_x2 = (sx + dx).astype(np.float32)
        map_y2 = np.tile(np.arange(h, dtype=np.float32)[:, None], (1, w))
        out = cv2.remap(krok1, map_x2, map_y2, cv2.INTER_LINEAR,
                        borderMode=cv2.BORDER_CONSTANT, borderValue=tlo)
        mout = cv2.remap(m1.astype(np.uint8) * 255, map_x2, map_y2,
                         cv2.INTER_NEAREST) > 127
        iou = (mout & tsil).sum() / max(1, (mout | tsil).sum())
        iou0 = (m1 & tsil).sum() / max(1, (m1 | tsil).sum())
        print("силует ззаду проти дзеркального переду: %.3f → %.3f"
              % (iou0, iou))
    cv2.imwrite(vyh_p, out)
    cv2.imwrite(mvyh_p, (mout * 255).astype(np.uint8))
    o_o = opory(cv2.cvtColor(out, cv2.COLOR_BGR2RGB), mout, vyd == "зад")
    print("розбіжність опор після, px:",
          {k: int(abs(o_o[k] - o_f[k])) for k in kl if k in o_o})


if __name__ == "__main__":
    main()
