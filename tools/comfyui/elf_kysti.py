#!/usr/bin/env python3
"""Кисті ельфійки з коротким волоссям — перемалювати лише кисті (13.10.2026).

Слово замовника: «перероби ельфійку з коротким волоссям … el_korotke_903_00002_.png,
але тут вади кисті рук, але все інше гарно». У кадрі (як і в основі s808)
пальці злиплись у «лопатку» з великим пальцем окремо — Mixamo й скан
потребують п'ять окремих розведених пальців.

Кожна кисть: квадрат довкола кисті (від кінчиків пальців до зап'ястя) ×8
до 1024² → FLUX dev перемальовує під маскою (кисть + трохи тла, щоб пальці
мали куди розійтися), шум `DENOISE`; ліва кисть віддзеркалюється, щоб обидві
малювались як права (один промпт). Назад — зменшення й м'яка маска; решта
кадру — пікселі `el_korotke_903_00002_`.

    ~/Програми/cv-venv/bin/python -u tools/comfyui/elf_kysti.py [сід…]

Вихід — `wiki/img/test/avatar/el-korotke-s903b-kysti-s<сід>.png`;
основа — `el-korotke-s903b.png` (копія кадру ComfyUI).

`--пересадити` (13.10.2026, слово замовника: «кісті візьми з
el_cn_202_00001_.png або el_cn_101_00001_.png»): кисті — пікселі кадру
`el-cn-101.png` (розкриті долоні, п'ять розведених пальців, рука
горизонтальна; у 202 кисті підняті й обмотані): від зап'ястя (край наруча)
до кінчиків, афінно на зап'ястя ельфійки — уздовж руки за пропорцією
(кисть ≈ 10,5% зросту), поперек — за товщиною зап'ястя (ельфійка
тонша); стара кисть — геть (`cv2.inpaint` тла), колір шкіри — Lab під
передпліччя, перехід на зап'ясті 10 px. Вихід — `el-korotke-s903b-k101.png`.
"""
import os
import shutil
import sys

import cv2
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster3d as m  # noqa: E402
import avatar_ref_stopy as st  # noqa: E402
import elf_oblychchia as eo  # noqa: E402

D = eo.D
DZHERELO = os.path.join(m.COMFY, "output", "el_korotke_903_00002_.png")
KADR = D / "el-korotke-s903b.png"
SIDY = [int(a) for a in sys.argv[1:] if a.isdigit()] or [1801, 1802, 1803]
K = 8
DENOISE = 0.8
st.PROMT_MASKA = (
    "Close-up studio photo of the right hand of a slender pale-skinned elf "
    "woman in a T-pose: the arm straight out to the side, the hand flat and "
    "relaxed in line with the arm, palm facing down, five long slim separate "
    "fingers slightly spread apart with visible gaps between them, the thumb "
    "clearly separated and pointing forward, natural knuckles and short "
    "fingernails, plain light grey background, soft even lighting, "
    "photorealistic, sharp focus.")


def kvadrat(sylu, pravа):
    """Квадрат кисті: від кінчиків пальців 112 px углиб руки."""
    ys, xs = np.where(sylu)
    x_t = xs.max() if pravа else xs.min()
    smuga = sylu[:, x_t - 3:x_t + 1] if pravа else sylu[:, x_t:x_t + 4]
    y_t = int(np.where(smuga.any(1))[0].mean())
    s = 128
    x0 = x_t - 112 if pravа else x_t - 16
    return x0, y_t - s // 2, x0 + s, y_t + s // 2


DONOR = D / "el-cn-101.png"
# зап'ястя донора — край наруча (профіль товщини й яскравості, 13.10)
DONOR_ZAP = {"ліва": 142, "права": 870}


def profil(sylu, x, y0=100, y1=400):
    col = np.where(sylu[y0:y1, x])[0]
    return (col.min() + y0, col.max() + y0) if len(col) else None


def peresadyty():
    sylu_t = np.asarray(Image.open(D / (KADR.stem + "-maska.png")).convert("L")) > 127
    if not (D / "el-cn-101-maska.png").exists():
        m.cutout(str(DONOR), str(D / "el-cn-101-maska.png"))
    sylu_s = np.asarray(Image.open(D / "el-cn-101-maska.png").convert("L")) > 127
    kadr = np.asarray(Image.open(KADR).convert("RGB")).copy()
    dzh = np.asarray(Image.open(DONOR).convert("RGB"))
    ys = np.where(sylu_t.any(1))[0]
    H = ys.max() - ys.min()
    L_t = 0.105 * H
    for bik, sgn in (("ліва", -1), ("права", 1)):
        # ціль: кінчик і зап'ястя (найтонше місце за 60…150 px від кінчика)
        xs = np.where(sylu_t[100:400].any(0))[0]
        x_tip = xs.min() if sgn < 0 else xs.max()
        tov = {}
        for d in range(60, 150):
            pr = profil(sylu_t, x_tip - sgn * d)
            if pr:
                tov[d] = pr[1] - pr[0]
        d_w = min(tov, key=lambda d: (tov[d], d))
        x_wt = x_tip - sgn * d_w
        p0, p1 = profil(sylu_t, x_wt), profil(sylu_t, x_wt - sgn * 30)
        W_t = np.array([x_wt, (p0[0] + p0[1]) / 2])
        lik = np.array([x_wt - sgn * 30, (p1[0] + p1[1]) / 2])
        os_t = (W_t - lik) / np.linalg.norm(W_t - lik)          # до кінчиків
        th_t = p0[1] - p0[0] + 1
        # донор
        x_ws = DONOR_ZAP[bik]
        q0, q1 = profil(sylu_s, x_ws), profil(sylu_s, x_ws - sgn * 25)
        W_s = np.array([x_ws, (q0[0] + q0[1]) / 2])
        lik_s = np.array([x_ws - sgn * 25, (q1[0] + q1[1]) / 2])
        os_s = (W_s - lik_s) / np.linalg.norm(W_s - lik_s)
        th_s = q0[1] - q0[0] + 1
        xs_s = np.where(sylu_s[100:400].any(0))[0]
        x_tip_s = xs_s.min() if sgn < 0 else xs_s.max()
        L_s = abs(x_tip_s - x_ws)
        sa, sc = L_t / L_s, float(np.clip(th_t / th_s, 0.55, 1.0))
        # афінна: донорська система (уздовж, поперек) → цільова
        n_s, n_t = np.array([-os_s[1], os_s[0]]), np.array([-os_t[1], os_t[0]])
        A_s = np.c_[os_s, n_s]                                     # 2×2
        A_t = np.c_[os_t * sa, n_t * sc]
        Mx = A_t @ np.linalg.inv(A_s)
        M = np.c_[Mx, W_t - Mx @ W_s]
        print("[кисті] %s: ціль зап'ястя %s товщ %d, кінчик %d; донор зап'ястя %s товщ %d, довж %d; ×%.2f уздовж, ×%.2f поперек"
              % (bik, W_t.round(), th_t, x_tip, W_s.round(), th_s, L_s, sa, sc), flush=True)
        # кисть донора — лише за зап'ястям
        yy, xx = np.mgrid[0:1024, 0:1024]
        za = ((np.c_[xx.ravel(), yy.ravel()] - W_s) @ os_s).reshape(1024, 1024)
        # (звуження на 1 px проти облямівки рвало мізинець — облямівку
        # прибирає `--шліфувати`)
        km = (sylu_s & (za > -2)).astype(np.float32)
        kyst = cv2.warpAffine(dzh, M, (1024, 1024), flags=cv2.INTER_LANCZOS4)
        km_t = cv2.warpAffine(km, M, (1024, 1024), flags=cv2.INTER_LINEAR)
        # колір шкіри — під передпліччя ельфійки (20…60 px до зап'ястя)
        zt = ((np.c_[xx.ravel(), yy.ravel()] - W_t) @ os_t).reshape(1024, 1024)
        pered = sylu_t & (zt < -20) & (zt > -60)
        nova_s = (km_t > 0.5)
        lab_k = cv2.cvtColor(kyst, cv2.COLOR_RGB2LAB).astype(np.float32)
        lab_t = cv2.cvtColor(kadr, cv2.COLOR_RGB2LAB).astype(np.float32)
        for c in range(3):
            a_, b_ = lab_k[..., c][nova_s], lab_t[..., c][pered]
            lab_k[..., c] = (lab_k[..., c] - a_.mean()) / max(a_.std(), 1e-3) * b_.std() + b_.mean()
        kyst = cv2.cvtColor(lab_k.clip(0, 255).astype(np.uint8), cv2.COLOR_LAB2RGB)
        # стара кисть геть: усе за зап'ястям у силуеті — тло
        stara = (sylu_t & (zt > 2)).astype(np.uint8)
        stara = cv2.dilate(stara, np.ones((3, 3), np.uint8), iterations=3)
        kadr = cv2.inpaint(kadr, stara, 5, cv2.INPAINT_TELEA)
        # вставка: м'який край і перехід на зап'ясті (10 px)
        perekhid = np.clip((zt + 2) / 10.0, 0, 1)
        alfa = (cv2.GaussianBlur(km_t, (0, 0), 0.8) * perekhid)[..., None]
        kadr = (kadr * (1 - alfa) + kyst * alfa).astype(np.uint8)
    kudy = D / (KADR.stem + "-k101.png")
    Image.fromarray(kadr).save(kudy)
    print("готово", kudy.name, flush=True)


def main():
    global KADR, DENOISE
    if "--пересадити" in sys.argv:
        peresadyty()
        return
    # `--шліфувати`: те саме перемалювання, але кадр — пересаджені кисті й
    # слабкий шум (тон і краї пальців, форма лишається)
    if "--шліфувати" in sys.argv:
        KADR = D / (KADR.stem + "-k101.png")
        DENOISE = 0.45
    if not KADR.exists():
        shutil.copy(DZHERELO, KADR)
    if "--шліфувати" in sys.argv:            # силует нових кистей, не старих
        m.cutout(str(KADR), str(D / (KADR.stem + "-maska.png")))
    maska_p = D / (KADR.stem + "-maska.png")
    if not maska_p.exists():
        m.cutout(str(KADR), str(maska_p))
    sylu = np.asarray(Image.open(maska_p).convert("L")) > 127
    kadr = np.asarray(Image.open(KADR).convert("RGB")).copy()
    ramky = {"права": kvadrat(sylu, True), "ліва": kvadrat(sylu, False)}
    print("кисті:", ramky, flush=True)
    m.free()
    vkhid = {}
    for bik, (x0, y0, x1, y1) in ramky.items():
        krop = kadr[y0:y1, x0:x1]
        msk = sylu[y0:y1, x0:x1].astype(np.uint8)
        # лише кисть: від зап'ястя (36 px від краю з боку руки) до кінчиків
        if bik == "права":
            msk[:, :36] = 0
        else:
            msk[:, -36:] = 0
        msk = cv2.dilate(msk, np.ones((3, 3), np.uint8), iterations=6)
        if bik == "ліва":                   # дзеркально — як права
            krop, msk = krop[:, ::-1], msk[:, ::-1]
        big = Image.fromarray(np.ascontiguousarray(krop)).resize((1024, 1024), Image.LANCZOS)
        mbig = Image.fromarray(np.ascontiguousarray(msk) * 255).resize((1024, 1024), Image.NEAREST)
        bp, mp = D / ("%s-kyst-%s.png" % (KADR.stem, bik)), D / ("%s-kyst-%s-maska.png" % (KADR.stem, bik))
        big.save(bp)
        mbig.save(mp)
        vkhid[bik] = (m.stage(str(bp)), m.stage(str(mp)), msk)
    for seed in SIDY:
        zbir = kadr.copy()
        for bik, (x0, y0, x1, y1) in ramky.items():
            img, mk, msk = vkhid[bik]
            done = m.run(st.graf_maska(img, mk, seed, "el_kyst_%s_%d" % ("r" if bik == "права" else "l", seed),
                                       DENOISE))
            out = done["outputs"]["13"]["images"][-1]
            nova = np.asarray(Image.open(os.path.join(m.COMFY, "output", out["subfolder"], out["filename"]))
                              .convert("RGB").resize((x1 - x0, y1 - y0), Image.LANCZOS)).astype(np.float32)
            soft = cv2.GaussianBlur(msk.astype(np.float32), (0, 0), 2.0)[..., None]
            if bik == "ліва":
                nova, soft = nova[:, ::-1], soft[:, ::-1]
            zbir[y0:y1, x0:x1] = (zbir[y0:y1, x0:x1] * (1 - soft) + nova * soft).astype(np.uint8)
        kudy = D / ("%s-kysti-s%d.png" % (KADR.stem, seed))
        Image.fromarray(zbir).save(kudy)
        print("готово", kudy.name, flush=True)
    m.free()


if __name__ == "__main__":
    main()
