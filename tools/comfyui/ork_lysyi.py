#!/usr/bin/env python3
"""Орк-пілот: лиса основа без бороди й з чистими грудьми (09.11.2026).

Слово замовника: «Основа лиса й без бороди — намалюй заново всю модель з
чистою груддю» (зачіски й бороди — окремі сітки з кольором, як в аватарів
MPFB). Від топлес-кадрів (`ork_topless.py`): маска — усе темне й
ненасичене в силуеті (волосся, борода, коси, шнурок і кулон; HSV: S < 0,35,
V < 0,30), крім дрібних плям (очі, ніздрі, нігті), розширене на 10 px;
FLUX dev під маскою, шум 1,0; решта — пікселі кадру.

    ~/Програми/cv-venv/bin/python -u tools/comfyui/ork_lysyi.py <тека> <кадр…> [--сіди 3201,3202]
→ <тека>/<кадр>-lysyi-s<сід>.png, маска <кадр>-lysyi-maska.png, аркуш lysyi.png
"""
import colorsys  # noqa: F401
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

A = sys.argv[1:]
TEKA = Path(A[0])
SIDY = [int(x) for x in A[A.index("--сіди") + 1].split(",")] if "--сіди" in A else [3201, 3202]
KADRY = [Path(x) for x in A[1:] if x.endswith(".png")]
PROMT = ("Full body photo of the same huge muscular adult male orc with "
         "olive-green orc skin, long pointed ears and two lower tusks, a "
         "completely bald smooth shaved head with no hair at all, clean-shaven "
         "face and jaw with no beard and no stubble, topless with a clean bare "
         "muscular chest and bare shoulders, no braids, no necklace, no "
         "jewelry, wearing only plain tight black boxer briefs, barefoot, "
         "strict T-pose, front view. Highly detailed realistic skin with "
         "pores, veins and fine scars, sharp focus, soft even studio light, "
         "plain grey backdrop. Not a cartoon.")


def maska(kadr):
    syl_f = TEKA / (kadr.stem + "-sylyet.png")
    m.cutout(str(kadr), str(syl_f))
    im = Image.open(kadr).convert("RGB")
    a = np.asarray(im).astype(float) / 255
    h, w = a.shape[:2]
    syl = np.asarray(Image.open(syl_f).convert("L").resize((w, h))) > 128
    syl_f.unlink()
    mx, mn = a.max(2), a.min(2)
    s = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    temne = syl & (s < 0.35) & (mx < 0.30)
    # лише вище плавок: нижче — чорні плавки, їх не чіпати
    ys = np.where(syl.any(1))[0]
    zrist = ys.max() - ys.min()
    temne[ys.min() + int(0.47 * zrist):] = False
    temne = ndimage.binary_opening(temne, iterations=1)
    mitky, n = ndimage.label(temne)
    if n:
        rozm = ndimage.sum(temne, mitky, range(1, n + 1))
        temne = np.isin(mitky, 1 + np.where(rozm > temne.size * 0.0012)[0])
    temne = ndimage.binary_dilation(temne, iterations=10)
    if "--геометрія" in A:
        # другий прохід: за положенням у силуеті — маківка, смуга грудей між
        # плечима (ланцюжок, кулон, сліди кіс), між ногами нижче плавок
        # (лямка); пасма й ланцюжок не настільки темні для маски кольору
        temne[:] = False
        xs = np.where(syl.any(0))[0]
        y0 = ys.min()
        cx = int(np.median(np.where(syl[y0 + int(0.05 * zrist)])[0]))
        yy, xx = np.mgrid[0:h, 0:w]
        makivka = (yy < y0 + 0.075 * zrist)
        hrudy = (yy > y0 + 0.15 * zrist) & (yy < y0 + 0.33 * zrist) & (np.abs(xx - cx) < 0.11 * zrist)
        nohy = (yy > y0 + 0.55 * zrist) & (yy < y0 + 0.80 * zrist) & (np.abs(xx - cx) < 0.035 * zrist)
        temne = (makivka | hrudy | nohy) & ndimage.binary_dilation(syl, iterations=6)
    kudy = TEKA / (kadr.stem + "-lysyi-maska.png")
    Image.fromarray((temne * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(3)).save(kudy)
    return kudy


def graf(kadr, msk, seed):
    g = rr.graf_flux(kadr, PROMT, seed, True, 2.5, 1.0, 0.3, 0.3)
    g["20"] = {"class_type": "LoadImageMask", "inputs": {"image": msk, "channel": "red"}}
    g["21"] = {"class_type": "SetLatentNoiseMask",
               "inputs": {"samples": ["6", 0], "mask": ["20", 0]}}
    g["11"]["inputs"]["latent_image"] = ["21", 0]
    return g


def main():
    TEKA.mkdir(parents=True, exist_ok=True)
    m.free()
    masky = {k: maska(k) for k in KADRY}
    m.free()
    for k in KADRY:
        kd, mk = m.stage(str(k)), m.stage(str(masky[k]))
        for sd in SIDY:
            done = m.run(graf(kd, mk, sd))
            out = done["outputs"]["13"]["images"][-1]
            kudy = TEKA / ("%s-lysyi-s%d.png" % (k.stem, sd))
            shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"], out["filename"]), kudy)
            print("готово", kudy, flush=True)
    m.free()
    s = 480
    o = Image.new("RGB", (s * (2 + len(SIDY)), len(KADRY) * (s + 30)), (24, 24, 24))
    d = ImageDraw.Draw(o)
    sh = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 18)
    for r, k in enumerate(KADRY):
        ryad = [(k.stem, k), ("маска", masky[k])] + [
            ("s%d" % sd, TEKA / ("%s-lysyi-s%d.png" % (k.stem, sd))) for sd in SIDY]
        for i, (p, f) in enumerate(ryad):
            im = Image.open(f).convert("RGB")
            im.thumbnail((s, s))
            o.paste(im, (i * s + (s - im.width) // 2, r * (s + 30)))
            d.text((i * s + 8, r * (s + 30) + s + 6), p, fill=(230, 220, 200), font=sh)
    o.save(TEKA / "lysyi.png")
    print("аркуш", TEKA / "lysyi.png", flush=True)


if __name__ == "__main__":
    main()
