#!/usr/bin/env python3
"""Кисті на кадрі ззаду — тильним боком до камери (02.10.2026).

Слово замовника: «вигляд із спини не повний - без ніг, і розвернутими
долонями назад - це не правильно». Kontext ззаду малює розкриті долоні
(4 сіди, s1411…s1444) — тож кожна кисть перемальовується окремо: кроп
довкола кінця руки ×6, FLUX dev під маскою (як ступні чоловіка,
`avatar_ref_stopy.py`), назад із розмитим краєм.

    ~/Програми/cv-venv/bin/python tools/comfyui/avatar_ref_kysti.py <кадр> <маска> <вихід>
"""
import os
import shutil
import sys

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster3d as m  # noqa: E402
import avatar_ref_stopy as st  # noqa: E402

# З шумом 0,9 FLUX лишав ту саму розкриту долоню — тепер 1,0 і ширша маска.
PROMT = ("Close-up photograph of a woman's outstretched arm ending in a hand "
         "seen from its back side: the dorsal side of the hand faces the "
         "viewer, the knuckles and the backs of the fingers are visible, the "
         "palm is hidden and faces away from the viewer, fingers straight "
         "and together pointing sideways, natural realistic skin, light grey "
         "studio background, soft even lighting, photorealistic.")
DENOISE = 1.0
R = 85          # півсторона кропу, px


def main():
    kadr, maska, vyh = sys.argv[1:4]
    im = Image.open(kadr).convert("RGB")
    mk = np.asarray(Image.open(maska).convert("L")) > 127
    ys, xs = np.where(mk)
    out = im.copy()
    m.free()
    st.PROMT_MASKA = PROMT
    for bik, x_kr in (("l", xs.min()), ("r", xs.max())):
        y_kr = int(np.median(ys[np.abs(xs - x_kr) < 3]))
        cx = x_kr + (R - 15 if bik == "l" else -(R - 15))
        box = (cx - R, y_kr - R, cx + R, y_kr + R)
        kr = im.crop(box).resize((1020, 1020), Image.LANCZOS)
        kp = os.path.join(os.path.dirname(vyh), "kyst-%s.png" % bik)
        kr.save(kp)
        mm = Image.fromarray((mk[box[1]:box[3], box[0]:box[2]] * 255)
                             .astype(np.uint8)).resize((1020, 1020))
        # лише кисть: від зап'ястя (≈ 60 px від кінця руки) назовні
        a = np.array(mm) > 127
        xx = np.arange(1020)[None, :]
        zap = (R - 15 - 60 + R) * 6 if bik == "l" else (R + 15 + 60 - R) * 6
        a &= (xx < (R - (R - 15) + 60) * 6) if bik == "l" else \
            (xx > (R + (R - 15) - 60) * 6)
        mm = Image.fromarray((a * 255).astype(np.uint8)).filter(
            ImageFilter.MaxFilter(81))
        mp = kp.replace(".png", "-maska.png")
        mm.save(mp)
        done = m.run(st.graf_maska(m.stage(kp), m.stage(mp), 1500 + ord(bik),
                                   "avatar_kyst_%s" % bik, DENOISE))
        o = done["outputs"]["13"]["images"][-1]
        nove = Image.open(os.path.join(m.COMFY, "output", o["subfolder"],
                                       o["filename"])).convert("RGB")
        nove = nove.resize((2 * R, 2 * R), Image.LANCZOS)
        mz = mm.resize((2 * R, 2 * R)).filter(ImageFilter.GaussianBlur(4))
        out.paste(Image.composite(nove, out.crop(box), mz), box[:2])
        print("кисть", bik, "готово", box, flush=True)
    out.save(vyh)


if __name__ == "__main__":
    main()
