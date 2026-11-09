#!/usr/bin/env python3
"""Орк-пілот топлес — референс без одягу для нового Pixal3D (09.11.2026).

Слово замовника: «чи зможемо зробити модель топлес? поточна модель має
випираючі частини одягу що буде заважати вдягати броню» → «Новий кадр +
Pixal3D». Як `osnova_bez.py`, але голова з зачіскою й бородою лишається
(замовнику подобається): перемальовується лише маска — усе в силуеті, що
не кольору шкіри, нижче підборіддя й між зап'ястями (пояс, підсумки,
пов'язка, наколінники, штани, кулон, пасма кіс на грудях), розширене на
14 px. Решта — пікселі кадру.

    ~/Програми/cv-venv/bin/python -u tools/comfyui/ork_topless.py <кадр> <тека> [сід…]
→ <тека>/topless-maska.png, topless-s<сід>.png, аркуш topless.png
"""
import os
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster3d as m  # noqa: E402
import rasy_realizm as rr  # noqa: E402

KADR, TEKA = Path(sys.argv[1]), Path(sys.argv[2])
SIDY = [int(a) for a in sys.argv[3:] if a.isdigit()] or [3101, 3102, 3103]
PIDBORIDDIA = 0.27      # частка висоти кадру: вище — голова й борода (не чіпати)
ZAPIASTIA = (0.21, 0.79)  # частки ширини: за ними — кисті (не чіпати)
PROMT = ("Full body photo of the same huge muscular adult male orc with "
         "olive-green orc skin, the same long black hair and black beard, "
         "topless with a bare muscular chest and bare belly, wearing only "
         "plain tight black boxer briefs, bare muscular thighs and bare knees "
         "and bare legs, no belt, no pouches, no straps, no necklace, no "
         "jewelry, barefoot, strict T-pose, front view. Highly detailed "
         "realistic skin with pores, veins and fine scars, sharp focus, soft "
         "even studio light, plain grey backdrop. Not a cartoon.")


def maska():
    TEKA.mkdir(parents=True, exist_ok=True)
    syl_f = TEKA / "topless-sylyet.png"
    m.cutout(str(KADR), str(syl_f))
    a = np.asarray(Image.open(KADR).convert("RGB")).astype(float)
    h, w = a.shape[:2]
    syl = np.asarray(Image.open(syl_f).convert("L").resize((w, h))) > 128
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    shkira = (g > r * 0.98) & (g > b * 1.15) & (g > 60)
    ne = syl & ~shkira
    ne[:int(PIDBORIDDIA * h)] = False
    ne[:, :int(ZAPIASTIA[0] * w)] = False
    ne[:, int(ZAPIASTIA[1] * w):] = False
    ne = ndimage.binary_opening(ne, iterations=2)
    mitky, n = ndimage.label(ne)
    if n:
        rozm = ndimage.sum(ne, mitky, range(1, n + 1))
        ne = np.isin(mitky, 1 + np.where(rozm > ne.size * 0.0015)[0])
    ne = ndimage.binary_dilation(ne, iterations=14)
    ne[:int(PIDBORIDDIA * h)] = False
    im = Image.fromarray((ne * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(4))
    kudy = TEKA / "topless-maska.png"
    im.save(kudy)
    return kudy


def graf(kadr, msk, seed):
    g = rr.graf_flux(kadr, PROMT, seed, True, 2.5, 1.0, 0.3, 0.3)
    g["20"] = {"class_type": "LoadImageMask", "inputs": {"image": msk, "channel": "red"}}
    g["21"] = {"class_type": "SetLatentNoiseMask",
               "inputs": {"samples": ["6", 0], "mask": ["20", 0]}}
    g["11"]["inputs"]["latent_image"] = ["21", 0]
    return g


def main():
    m.free()
    mk_f = maska()
    m.free()
    kd, mk = m.stage(str(KADR)), m.stage(str(mk_f))
    for sd in SIDY:
        done = m.run(graf(kd, mk, sd))
        out = done["outputs"]["13"]["images"][-1]
        shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"], out["filename"]),
                    TEKA / ("topless-s%d.png" % sd))
        print("готово", TEKA / ("topless-s%d.png" % sd), flush=True)
    m.free()
    s = 500
    ryad = [("референс", KADR), ("маска", mk_f)] + [("s%d" % sd, TEKA / ("topless-s%d.png" % sd)) for sd in SIDY]
    o = Image.new("RGB", (s * len(ryad), s + 30), (24, 24, 24))
    d = ImageDraw.Draw(o)
    sh = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 18)
    for i, (p, f) in enumerate(ryad):
        im = Image.open(f).convert("RGB")
        im.thumbnail((s, s))
        o.paste(im, (i * s + (s - im.width) // 2, 0))
        d.text((i * s + 8, s + 6), p, fill=(230, 220, 200), font=sh)
    o.save(TEKA / "topless.png")
    print("аркуш", TEKA / "topless.png", flush=True)


if __name__ == "__main__":
    main()
