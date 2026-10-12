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


def main():
    if not KADR.exists():
        shutil.copy(DZHERELO, KADR)
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
