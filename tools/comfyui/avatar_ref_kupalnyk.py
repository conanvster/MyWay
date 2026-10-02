#!/usr/bin/env python3
"""Купальник жінки: низ — трусики з високим вирізом (02.10.2026).

Слово замовника: «створи референс для 3d людини жінки Людина, жінка —
варіант 1 у купальнику як в прикладі» (приклад — чорний роздільний,
трусики з високим вирізом). Kontext двічі лишив шорти (s611…s663, другий
прохід просив змінити лише низ) — тому, як зі ступнями чоловіка,
перемальовування маскою: FLUX dev, кроп стегон ×2, шум лише на шортах
(темні пікселі, розширені) і краю шкіри навколо.

    ~/Програми/cv-venv/bin/python tools/comfyui/avatar_ref_kupalnyk.py
→ wiki/img/test/avatar/zh-kupalnyk2-s<seed>.png (повний кадр)
"""
import os
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster3d as m  # noqa: E402
import avatar_ref_stopy as st  # noqa: E402

KORIN = Path(__file__).resolve().parents[2]
D = KORIN / "wiki/img/test/avatar"
# Основа — s622: слово замовника «найбільш підходящі пропорції купальник
# (під 3D, як у прикладі замовника) Kontext, seed 622».
DZHERELO = D / "zh-kupalnyk-s622.png"
KROP = (300, 330, 724, 754)
SIDY = (811, 822, 833, 844)
# З шумом 0,85 FLUX повертав ту саму форму шортів (s711…s744) — тепер
# 1,0 і маска на всю верхню частину стегон.
DENOISE = 1.0
PROMT = (
    "Photograph of a woman's hips and upper thighs in black high-cut bikini "
    "briefs: a smooth black triangle at the front, the leg openings cut "
    "high up to her hip bones, bare outer hips, bare thighs, natural "
    "realistic skin, front view, plain light grey studio background, soft "
    "even lighting, photorealistic.")


def main():
    im = Image.open(DZHERELO).convert("RGB")
    x0, y0, x1, y1 = KROP
    kr = im.crop(KROP).resize((1024, 1024), Image.LANCZOS)
    kr_p = D / "zh-kupalnyk-krop.png"
    kr.save(kr_p)
    a = np.asarray(kr).astype(int)
    temne = (a.max(-1) < 60)
    # лише великий шмат (шорти), не волосся чи тіні
    # Лише шорти з полем (прямокутник на всі стегна давав шви й чужий
    # тон шкіри, s751…s784): трусики менші за шорти, решту поля FLUX
    # домальовує шкірою.
    mk = Image.fromarray((temne * 255).astype(np.uint8)).filter(
        ImageFilter.MaxFilter(61))
    mk_p = D / "zh-kupalnyk-krop-maska.png"
    mk.save(mk_p)
    st.PROMT_MASKA = PROMT
    image, maska = m.stage(str(kr_p)), m.stage(str(mk_p))
    m.free()
    for seed in SIDY:
        kudy = D / ("zh-kupalnyk2-s%d.png" % seed)
        if kudy.exists():
            continue
        done = m.run(st.graf_maska(image, maska, seed,
                                   "avatar1_zh_kupalnyk2_s%d" % seed,
                                   DENOISE))
        out = done["outputs"]["13"]["images"][-1]
        nove = Image.open(os.path.join(m.COMFY, "output", out["subfolder"],
                                       out["filename"])).convert("RGB")
        nove = nove.resize((x1 - x0, y1 - y0), Image.LANCZOS)
        mm = mk.resize((x1 - x0, y1 - y0)).filter(ImageFilter.MinFilter(9)) \
            .filter(ImageFilter.GaussianBlur(10))
        povne = im.copy()
        povne.paste(Image.composite(nove, im.crop(KROP), mm), (x0, y0))
        povne.save(kudy)
        print("готово", seed, kudy, flush=True)


if __name__ == "__main__":
    main()
