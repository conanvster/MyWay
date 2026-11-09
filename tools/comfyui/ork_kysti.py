#!/usr/bin/env python3
"""Кисть орка-пілота — розгорнута й у великому масштабі (09.11.2026).

Слово замовника: «розібратися чому не вдалося якісно зробити руки
покращити референс наприклад правильно розгорнути, та або збільшити
масштаб щоб отримати більшу якість, а потім зменшити модель».

Чому грудка: Pixal3D будує форму на сітці 32³ на всю фігуру (~6 см на
клітинку при зрості 1,9 м) — палець орка 2–3 см; і на референсі кисть видно
лише згори, пальці звисають і зібрані в ряд — з одного кадру не розділити.

Тут: кисть із референсу (квадрат від передпліччя до кінчиків, ×4 до 1024²,
віддзеркалено — пальці праворуч) → FLUX dev перемальовує під маскою лише
кисть: рівна, долонею донизу, п'ять окремих трохи розведених пальців (як
`elf_kysti.py`). Далі — 3D самої кисті (`ork_pilot_3d.py … pixal`).

    ~/Програми/cv-venv/bin/python -u tools/comfyui/ork_kysti.py <референс.png> <тека> [сід…]
→ <тека>/kyst-ref.png (кроп), kyst-maska.png, kyst-s<сід>.png
"""
import os
import sys

import cv2
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster3d as m  # noqa: E402
import avatar_ref_stopy as st  # noqa: E402

REF, TEKA = sys.argv[1], sys.argv[2]
SIDY = [int(a) for a in sys.argv[3:] if a.isdigit()] or [2101, 2102, 2103]
PREF = "kyst-v" if "--вся-ділянка" in sys.argv else "kyst"
KROP = (20, 215, 260, 455)          # права кисть орка (ліворуч у кадрі) + передпліччя
ZAPIASTIA = 0.53                    # частка кропу від лівого краю: далі — передпліччя
DENOISE = 1.0 if "--вся-ділянка" in sys.argv else 0.85
st.PROMT_MASKA = (
    "Close-up studio photo of the right hand of a huge muscular green-skinned "
    "orc in a T-pose: the thick arm straight out to the side, the large hand "
    "flat and relaxed in line with the arm, palm facing down, five thick "
    "separate fingers straight and slightly spread apart with visible gaps "
    "between them, the thumb clearly separated and pointing forward, knobbly "
    "knuckles, thick dark fingernails, olive green skin with fine wrinkles, "
    "plain grey background, soft even lighting, photorealistic, sharp focus.")

os.makedirs(TEKA, exist_ok=True)
maska_p = os.path.join(TEKA, "sylu-ref.png")
if not os.path.exists(maska_p):
    m.cutout(REF, maska_p)
sylu = np.asarray(Image.open(maska_p).convert("L")) > 127
kadr = np.asarray(Image.open(REF).convert("RGB"))
x0, y0, x1, y1 = KROP
krop = kadr[y0:y1, x0:x1][:, ::-1]                       # пальці праворуч
msk = sylu[y0:y1, x0:x1][:, ::-1].astype(np.uint8)
if "--вся-ділянка" in sys.argv:
    # з маскою-силуетом FLUX лишав кисть звислою там, де була стара: уся
    # ділянка за зап'ястям — щоб кисть могла лягти в лінію руки (09.11)
    msk[:] = 1
msk[:, :int((1 - ZAPIASTIA) * (x1 - x0))] = 0            # передпліччя лишається
msk = cv2.dilate(msk, np.ones((3, 3), np.uint8), iterations=8)
big = Image.fromarray(np.ascontiguousarray(krop)).resize((1024, 1024), Image.LANCZOS)
mbig = Image.fromarray(np.ascontiguousarray(msk) * 255).resize((1024, 1024), Image.NEAREST)
bp, mp = os.path.join(TEKA, "kyst-ref.png"), os.path.join(TEKA, PREF + "-maska.png")
big.save(bp)
mbig.save(mp)
m.free()
img, mk = m.stage(bp), m.stage(mp)
for seed in SIDY:
    done = m.run(st.graf_maska(img, mk, seed, "ork_kyst_%d" % seed, DENOISE))
    out = done["outputs"]["13"]["images"][-1]
    nova = Image.open(os.path.join(m.COMFY, "output", out["subfolder"], out["filename"])).convert("RGB")
    kudy = os.path.join(TEKA, "%s-s%d.png" % (PREF, seed))
    nova.save(kudy)
    print("готово", kudy, flush=True)
m.free()
