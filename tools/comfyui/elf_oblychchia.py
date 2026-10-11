#!/usr/bin/env python3
"""Чітке обличчя ельфійки для проєкції на аватар (11.10.2026).

Слово замовника: «спробуй зробити максимально якісно ельфійку на 100%
схожу з рендера meshy, з кістками людини … щоб з наближенням обличчя не
викривлялось і було схоже, збільши деталізацію». Pixal3D з кадру
el-odyn-s811 (1024²) дає розмите обличчя: голова там ~70 px, запікати
нічого. Тут — кадр для `avatar_build.py --референс`:

  1. силует s811 (birefnet) → `el-odyn-s811-maska.png`;
  2. голова, вирізана квадратом, ×N до 1024² → FLUX dev перемальовує
     слабким шумом (`DENOISE`), риси лишаються, з'являються пори, вії,
     райдужка;
  3. кадр ×4 (4096²) LANCZOS + нова голова з м'яким еліптичним краєм →
     `el-odyn-s811-4k.png`, маска теж ×4 → `el-odyn-s811-4k-maska.png`.

    ~/Програми/cv-venv/bin/python -u tools/comfyui/elf_oblychchia.py [сід]

Сіди 1-3 — варіанти голови `el-holova-s<сід>.png`; збирається кадр з
першого переданого (типово 1).
"""
import os
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster3d as m  # noqa: E402
import avatar_ref_stopy as st  # noqa: E402

KORIN = Path(__file__).resolve().parents[2]
D = KORIN / "wiki/img/test/avatar"
KADR = D / "el-odyn-s811.png"
K = 4
DENOISE = 0.38
PROMT = (
    "Extreme close-up studio portrait of a beautiful young elf woman, front "
    "view, long straight silver-white hair parted in the middle, long "
    "pointed elf ears, pale smooth skin with fine natural pores, soft "
    "brown eyes with detailed irises and long eyelashes, thin defined "
    "eyebrows, small straight nose, soft natural pink lips, calm neutral "
    "expression, plain light grey background, soft even lighting, sharp "
    "focus, photorealistic, 8k detail.")


def holova_ramka(maska):
    """Квадрат голови: верх силуету, висота голови ≈ 1/8 зросту."""
    ys, xs = np.where(maska)
    top, bot = ys.min(), ys.max()
    hh = (bot - top) / 8.0
    smuga = maska[top:int(top + hh)]
    cx = np.where(smuga.any(0))[0].mean()
    cy = top + hh * 0.5
    s = int(hh * 1.7)
    x0, y0 = int(cx - s / 2), int(cy - s / 2)
    return x0, y0, x0 + s, y0 + s


def main():
    sidy = [int(a) for a in sys.argv[1:]] or [1, 2, 3]
    m.free()
    maska_p = D / "el-odyn-s811-maska.png"
    if not maska_p.exists():
        m.cutout(str(KADR), str(maska_p))
    maska = np.asarray(Image.open(maska_p).convert("L")) > 127
    ramka = holova_ramka(maska)
    print("голова", ramka, flush=True)
    kadr = Image.open(KADR).convert("RGB")
    krop = kadr.crop(ramka).resize((1024, 1024), Image.LANCZOS)
    krop_p = D / "el-holova-krop.png"
    krop.save(krop_p)
    vsia = Image.new("L", (1024, 1024), 255)
    vsia_p = D / "el-holova-vsia-maska.png"
    vsia.save(vsia_p)
    st.PROMT_MASKA = PROMT
    image, mask = m.stage(str(krop_p)), m.stage(str(vsia_p))
    for seed in sidy:
        kudy = D / ("el-holova-s%d.png" % seed)
        if not kudy.exists():
            done = m.run(st.graf_maska(image, mask, seed,
                                       "el_holova_s%d" % seed, DENOISE))
            out = done["outputs"]["13"]["images"][-1]
            shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"],
                                     out["filename"]), kudy)
        print("готово", kudy.name, flush=True)
    m.free()

    # Збірка 4K-кадру з першого сіда.
    velyk = kadr.resize((kadr.width * K, kadr.height * K), Image.LANCZOS)
    x0, y0, x1, y1 = (v * K for v in ramka)
    s = x1 - x0
    nova = Image.open(D / ("el-holova-s%d.png" % sidy[0])).convert("RGB") \
        .resize((s, s), Image.LANCZOS)
    kraj = Image.new("L", (s, s), 0)
    ImageDraw.Draw(kraj).ellipse((s * 0.12, s * 0.06, s * 0.88, s * 0.94),
                                 fill=255)
    kraj = kraj.filter(ImageFilter.GaussianBlur(s * 0.06))
    velyk.paste(nova, (x0, y0), kraj)
    velyk.save(D / "el-odyn-s811-4k.png")
    Image.open(maska_p).convert("L").resize(velyk.size, Image.NEAREST) \
        .save(D / "el-odyn-s811-4k-maska.png")
    print("кадр 4K з сіда", sidy[0], flush=True)


if __name__ == "__main__":
    main()
