#!/usr/bin/env python3
"""Основа для 3D з кадру в одязі: лиса й без одягу, лише чорні плавки (14.10.2026).

Слово замовника про `proektsii_ref.py`: «супер — зроби ту ж модель без
волосся та одягу». За правилами основ (ельфійка, людина, орчиха s1303):
голова лиса (волосся — окремою сіткою), замість одягу прості чорні плавки.
Решта кадру не чіпається: перемальовується лише маска — усе всередині
силуету (birefnet), що не кольору шкіри (шкіру видно за відтінком: у орчихи
зелений канал вищий за червоний і синій), розширене на 14 px; дрібні плями
(очі, рот, нігті) відкинуто за розміром.

    ~/Програми/cv-venv/bin/python -u tools/comfyui/osnova_bez.py <кадр…>

Вихід — поруч із кадром: `<кадр>-bez-s<сід>.png`, маска `<кадр>-bez-maska.png`;
аркуш — `<тека>/без-волосся-й-одягу.png`.
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

SIDY = (9201, 9202)
PROMT = ("Full body photo of the same tall strong muscular adult female orc "
         "with olive-green orc skin, long pointed ears, a completely bald "
         "smooth shaved head with no hair at all, topless with a bare chest, "
         "wearing only plain black briefs, barefoot, strict T-pose, %s. Highly "
         "detailed realistic matte skin with pores, veins and fine scars, sharp "
         "focus, soft even studio light, plain grey backdrop. Not a cartoon.")


def maska(kadr):
    sylyet_f = kadr.with_name(kadr.stem + "-sylyet.png")
    m.cutout(str(kadr), str(sylyet_f))
    a = np.asarray(Image.open(kadr).convert("RGB")).astype(float)
    syl = np.asarray(Image.open(sylyet_f).convert("L").resize(
        (a.shape[1], a.shape[0]))) > 128
    sylyet_f.unlink()
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    shkira = (g > r * 0.98) & (g > b * 1.15) & (g > 60)
    ne = syl & ~shkira
    ne = ndimage.binary_opening(ne, iterations=2)
    mitky, n = ndimage.label(ne)
    if n:
        rozm = ndimage.sum(ne, mitky, range(1, n + 1))
        ne = np.isin(mitky, 1 + np.where(rozm > ne.size * 0.0015)[0])
    ne = ndimage.binary_dilation(ne, iterations=14)
    im = Image.fromarray((ne * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(4))
    kudy = kadr.with_name(kadr.stem + "-bez-maska.png")
    im.save(kudy)
    return kudy


def graf(kadr, msk, promt, seed):
    g = rr.graf_flux(kadr, promt, seed, True, 2.5, 1.0, 0.3, 0.3)
    g["20"] = {"class_type": "LoadImageMask", "inputs": {"image": msk, "channel": "red"}}
    g["21"] = {"class_type": "SetLatentNoiseMask",
               "inputs": {"samples": ["6", 0], "mask": ["20", 0]}}
    g["11"]["inputs"]["latent_image"] = ["21", 0]
    return g


def vyd(kadr):
    n = kadr.name
    return ("side view in profile, facing left" if "збоку" in n else
            "back view from behind" if "ззаду" in n else "front view")


def main():
    kadry = [Path(a) for a in sys.argv[1:]]
    m.free()
    masky = {k: maska(k) for k in kadry}
    m.free()
    for k in kadry:
        kd, mk = m.stage(str(k)), m.stage(str(masky[k]))
        for sd in SIDY:
            kudy = k.with_name("%s-bez-s%d.png" % (k.stem, sd))
            done = m.run(graf(kd, mk, PROMT % vyd(k), sd))
            out = done["outputs"]["13"]["images"][-1]
            shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"], out["filename"]), kudy)
            print("готово", kudy.name, flush=True)
    m.free()
    s = 420
    o = Image.new("RGB", (s * (2 + len(SIDY)), len(kadry) * (s + 30)), (24, 24, 24))
    d = ImageDraw.Draw(o)
    sh = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 16)
    for r, k in enumerate(kadry):
        ryad = [(k.stem, k), ("маска", masky[k])] + [
            ("s%d" % sd, k.with_name("%s-bez-s%d.png" % (k.stem, sd))) for sd in SIDY]
        for i, (p, f) in enumerate(ryad):
            im = Image.open(f).convert("RGB")
            im.thumbnail((s, s))
            o.paste(im, (i * s + (s - im.width) // 2, r * (s + 30)))
            d.text((i * s + 6, r * (s + 30) + s + 6), p, fill=(230, 220, 200), font=sh)
    o.save(kadry[0].parent / "без-волосся-й-одягу.png")
    print("аркуш", kadry[0].parent / "без-волосся-й-одягу.png", flush=True)


if __name__ == "__main__":
    main()
