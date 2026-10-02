#!/usr/bin/env python3
"""Руки кадру ззаду — з іншого кадру, дзеркально на обидва боки (02.10.2026).

Слово замовника: «для виду із заду використай руки з малюнку
avatar_zh-lysa-bik2_s1966_00001_.png також відзеркаль на іншу сторону».
На кадрі ззаду Kontext малював розкриті долоні. Рука з донора (від плеча
до кінчиків пальців) вирізається за маскою, масштабується під довжину й
товщину руки кадру ззаду, правою стає як є, лівою — віддзеркалена. Старі
руки стираються (inpaint тла), шов біля плеча — плавний.

    ~/Програми/cv-venv/bin/python tools/avatar_ref_ruky.py <донор.png>
        <маска_донора> <корінь_x_донора> <кадр.png> <маска_кадру>
        <вихід.png> <маска_виходу>
"""
import sys

import cv2
import numpy as np


def ruka(mk, x_korin, vpravo, y_maks):
    """Маска руки: пікселі за коренем (праворуч чи ліворуч), вище y_maks."""
    r = np.zeros_like(mk)
    if vpravo:
        r[:y_maks, x_korin:] = mk[:y_maks, x_korin:]
    else:
        r[:y_maks, :x_korin + 1] = mk[:y_maks, :x_korin + 1]
    # лише найбільша зв'язна частина
    n, lab, st, _ = cv2.connectedComponentsWithStats(r.astype(np.uint8))
    if n > 1:
        r = lab == (1 + np.argmax(st[1:, cv2.CC_STAT_AREA]))
    return r


def tovshchyna(r, x):
    ys = np.where(r[:, x])[0]
    return (ys.min(), ys.max()) if len(ys) else None


def main():
    don_p, mdon_p, korin_d, kadr_p, mk_p, vyh_p, mvyh_p = sys.argv[1:8]
    korin_d = int(korin_d)
    # Лікоть правої руки кадру (x). Замовник: «ти відрізав руки від ліктів і
    # причипив ліктями до пахв» — тепер плече до ліктя лишається своє, а від
    # ліктя до пальців — донорське (korin_d — лікоть донора).
    lokot_k = int(sys.argv[8]) if len(sys.argv) > 8 else None
    don = cv2.imread(don_p)
    mdon = cv2.imread(mdon_p, 0) > 127
    kadr = cv2.imread(kadr_p)
    mk = cv2.imread(mk_p, 0) > 127
    h, w = mk.shape
    ys, xs = np.where(mk)
    vys = ys.max() - ys.min()
    # рядок під руками: де силует кадру вже лише тулуб
    shyr = mk.sum(1)
    y_tul = int(ys.min() + 0.27 * vys)
    tul = np.where(mk[y_tul])[0]
    korin_p, korin_l = int(tul.max()) - 8, int(tul.min()) + 8
    y_maks = y_tul
    if lokot_k is not None:
        tsentr = (korin_p + korin_l) / 2.0
        korin_p, korin_l = lokot_k, int(round(2 * tsentr - lokot_k))
    # Корінь донора — за краєм тулуба (x≈613 під пахвою), інакше в шов ліз
    # шматок боку тулуба (сіра пляма).
    r_don = ruka(mdon, korin_d, True, int(np.where(mdon.any(1))[0].max()))

    # донорська рука — лише смуга довкола горизонталі руки
    ys_d = np.where(r_don.any(1))[0]
    r_don[:ys_d.min()] = False
    print("донор: рука x %d…%d, y %d…%d" % (korin_d, np.where(r_don.any(0))[0].max(),
                                            ys_d.min(), ys_d.max()))
    out = kadr.copy()
    mout = mk.copy()
    stari = ruka(mk, korin_p, True, y_maks) | ruka(mk, korin_l, False, y_maks)
    sterty = cv2.dilate(stari.astype(np.uint8), np.ones((9, 9), np.uint8))
    sterty[:, korin_l + 6:korin_p - 5] = 0
    out = cv2.inpaint(out, sterty * 255, 7, cv2.INPAINT_TELEA)
    mout &= ~(sterty > 0)
    xs_d = np.where(r_don.any(0))[0]
    kin_d = xs_d.max()
    for bik in ("p", "l"):
        r_k = ruka(mk, korin_p if bik == "p" else korin_l, bik == "p", y_maks)
        xs_k = np.where(r_k.any(0))[0]
        if bik == "p":
            korin_k, kin_k = korin_p, xs_k.max()
        else:
            korin_k, kin_k = korin_l, xs_k.min()
        dov_k = abs(kin_k - korin_k)
        sx = dov_k / float(kin_d - korin_d)
        t_d = tovshchyna(r_don, korin_d + 10)
        t_k = tovshchyna(r_k, korin_k + (10 if bik == "p" else -10))
        # Той самий масштаб, що й по довжині: товщина біля плеча в кадрах
        # різна за формою (дельта ззаду), і окремий масштаб роздував руку.
        sy = sx
        if lokot_k is not None:
            # Стик у лікті: товщина донора в лікті = товщині своєї руки там
            # (за довжиною передпліччя виходило 0,8 — сходинка в лікті).
            t_d0 = tovshchyna(r_don, korin_d + 3)
            t_k0 = tovshchyna(r_k, korin_k - 3 * znak) if False else \
                tovshchyna(mk, korin_k - 3 * (1 if bik == "p" else -1))
            tovst = (t_k0[1] - t_k0[0]) / float(t_d0[1] - t_d0[0])
            # Довжина — як у своєї руки (розмах = розмаху переду, інакше
            # пальці за краєм кадру), товщина — посередині між довжиною й
            # товщиною в лікті (≈10% неоднорідності не видно; сходинку в
            # лікті доробляє шов).
            sy = 0.5 * (sx + tovst)
            t_d, t_k = t_d0, t_k0
        cy_d, cy_k = (t_d[0] + t_d[1]) / 2, (t_k[0] + t_k[1]) / 2
        # перетворення кадр ← донор
        znak = 1 if bik == "p" else -1
        M = np.float32([[znak * sx, 0, korin_k - znak * sx * korin_d],
                        [0, sy, cy_k - sy * cy_d]])
        nova = cv2.warpAffine(don, M, (w, h), flags=cv2.INTER_LINEAR)
        nm = cv2.warpAffine(r_don.astype(np.uint8) * 255, M, (w, h),
                            flags=cv2.INTER_LINEAR) > 127
        alfa = cv2.GaussianBlur(nm.astype(np.float32), (0, 0), 1.2)
        # плавний шов (у лікті — 50 px, щоб не було сходинки товщини)
        xx = np.arange(w)[None, :]
        rampa = np.clip(((xx - korin_k) * znak + 20) / 50.0, 0, 1)
        alfa *= rampa
        out = (out * (1 - alfa[..., None]) + nova * alfa[..., None]) \
            .astype(np.uint8)
        mout |= nm
        print("рука %s: корінь %d, кінець %d, масштаб %.2f×%.2f"
              % (bik, korin_k, kin_k, sx, sy))
    cv2.imwrite(vyh_p, out)
    cv2.imwrite(mvyh_p, mout.astype(np.uint8) * 255)


if __name__ == "__main__":
    main()
