#!/usr/bin/env python3
"""Орк-чоловік v1–v3 з вікі рас — основи для 3D трьома інструментами (09.11.2026).

Слово замовника: «зроби рендер топлес без бороди та зачіски з
wiki/rasy.html Орк, чоловік. їх там 3 моделі, на кожну з них 3 варіації
різними інструментами». Правила основи (як пілот орка): топлес, лиса
голова, без бороди й кіс, лише чорні плавки, босоніж, сувора Т-поза
спереду, рівне сіре тло; обличчя, ікла, вуха, шкіра й статура — моделі.

  К · FLUX Kontext — редагування кадру інструкцією;
  Q · Qwen-Image-Edit 2509 (Lightning 8 кроків) — те саме іншою моделлю;
  R · FLUX dev img2img від лисої Т-пози пілота (поза й чисте тіло) +
      Redux концепту (обличчя, шкіра, статура).

    ~/Програми/cv-venv/bin/python -u tools/comfyui/ork_rasy_osnovy.py [сід]
→ art/орк-чоловік-основи-2026-11-09/v<n>-<К|Q|R>.png, аркуш основи.png
"""
import os
import shutil
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster3d as m  # noqa: E402
import bronia_2var as b2  # noqa: E402
import rasy_kontext as rk  # noqa: E402

ROOT = Path(m.ROOT)
VYKHID = ROOT / "art" / "орк-чоловік-основи-2026-11-09"
KADRY = [ROOT / "wiki" / "img" / "rasy" / ("орк-чоловік-v%d.png" % i) for i in (1, 2, 3)]
POZA = ROOT / "art" / "орк-пілот-2026-11-09" / "topless" / "topless-s3103-lysyi-s3202-lysyi-s3301.png"
SID = next((int(a) for a in sys.argv[1:] if a.isdigit()), 4101)

INSTR = ("Turn this orc into a clean base body for 3D modeling: change his pose "
         "to a strict symmetric T-pose, front view, arms straight out to the "
         "sides at shoulder height, palms down, fingers slightly apart, legs "
         "straight and slightly apart, feet apart. Remove all armor, cloak, "
         "pauldrons, bracers, belt, pouches, straps, trousers and boots: he is "
         "topless with a bare muscular chest and barefoot, wearing only plain "
         "tight black boxer briefs. Shave his head completely bald and remove "
         "the beard and all braids, clean-shaven jaw. Keep his face, lower "
         "tusks, pointed ears, skin color and skin texture, scars and massive "
         "muscular build exactly the same. Plain grey studio background, soft "
         "even light, the whole body from head to feet in frame, photorealistic.")
PROMT_R = ("Full body photo of a huge muscular adult male orc standing in a strict "
           "T-pose, front view, arms straight out to the sides, palms down. "
           "Completely bald smooth head, clean-shaven face with no beard, lower "
           "tusks, pointed ears, rough weathered olive green-brown orc skin with "
           "pores and old scars, heavy brow, broad jaw. Topless with a bare "
           "muscular chest, wearing only plain tight black boxer briefs, "
           "barefoot, no armor, no jewelry. Plain grey studio background, soft "
           "even light, photorealistic.")


def graf_kontext(kadr, seed, prefix):
    rk.PROMT = INSTR
    return rk.graf(kadr, seed, prefix)


def graf_qwen(kadr, seed, prefix):
    g = b2.graf_qwen(kadr, kadr, INSTR, seed, prefix)
    for n in ("9", "10"):                   # одна картинка — без зразка
        g[n]["inputs"].pop("image2", None)
    g["7"]["inputs"]["resolution_steps"] = 1    # новий ComfyUI вимагає
    return g


def graf_redux(poza, kadr, seed, prefix):
    g = b2.graf_redux(poza, poza, kadr, PROMT_R, seed, prefix, syla=0.55, shum=0.72)
    # без маски: перемальовується весь кадр (тіло тримає img2img)
    g["16"]["inputs"]["latent_image"] = ["5", 0]
    del g["6"], g["7"]
    return g


def zrobyty(graf, kudy):
    if kudy.exists():
        print("є", kudy, flush=True)
        return
    zberehty(m.run(graf), kudy)


def zberehty(done, kudy):
    out = [o for v in done["outputs"].values() for o in v.get("images", [])][-1]
    shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"], out["filename"]), kudy)
    print("готово", kudy, flush=True)


def main():
    VYKHID.mkdir(parents=True, exist_ok=True)
    m.free()
    staged = {k: m.stage(str(k)) for k in KADRY}
    poza = m.stage(str(POZA))
    for i, k in enumerate(KADRY, 1):                 # Kontext — підряд, модель одна
        zrobyty(graf_kontext(staged[k], SID, "ork_rasy_K_%d" % i), VYKHID / ("v%d-К.png" % i))
    m.free()
    for i, k in enumerate(KADRY, 1):
        zrobyty(graf_qwen(staged[k], SID, "ork_rasy_Q_%d" % i), VYKHID / ("v%d-Q.png" % i))
    m.free()
    for i, k in enumerate(KADRY, 1):
        zrobyty(graf_redux(poza, staged[k], SID, "ork_rasy_R_%d" % i), VYKHID / ("v%d-R.png" % i))
    m.free()
    s = 420
    o = Image.new("RGB", (s * 4, 3 * (s + 30)), (24, 24, 24))
    d = ImageDraw.Draw(o)
    sh = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 18)
    for r, k in enumerate(KADRY):
        for c, (pidp, f) in enumerate([("v%d концепт" % (r + 1), k), ("К · Kontext", VYKHID / ("v%d-К.png" % (r + 1))),
                                       ("Q · Qwen-Edit", VYKHID / ("v%d-Q.png" % (r + 1))),
                                       ("R · FLUX+Redux", VYKHID / ("v%d-R.png" % (r + 1)))]):
            im = Image.open(f).convert("RGB")
            im.thumbnail((s, s))
            o.paste(im, (c * s + (s - im.width) // 2, r * (s + 30)))
            d.text((c * s + 8, r * (s + 30) + s + 6), pidp, fill=(230, 220, 200), font=sh)
    o.save(VYKHID / "основи.png")
    print("аркуш", VYKHID / "основи.png", flush=True)


def kadr_oblychchia(k, kudy):
    """Кроп голови концепту для Redux: з цілого кадру Redux переносив і
    броню (навіть на силі 0,2), з обличчя — лише обличчя, ікла й шкіру."""
    import numpy as np
    syl_f = kudy.with_name(kudy.stem + "-syl.png")
    m.cutout(str(k), str(syl_f))
    syl = np.asarray(Image.open(syl_f).convert("L")) > 128
    syl_f.unlink()
    ys, xs = np.where(syl)
    top, h = ys.min(), ys.max() - ys.min()
    cx = int(np.where(syl[top + int(0.06 * h)])[0].mean())
    side = int(0.2 * h)
    y0 = top - int(0.02 * h)
    Image.open(k).convert("RGB").crop((cx - side // 2, y0, cx + side // 2, y0 + side)).resize((768, 768)).save(kudy)


def oblychchia_main(sidy):
    """`--обличчя`: Redux від кропу голови (сила 0,3, шум 0,78), по сіду —
    варіація; далі очищення `ork_lysyi.py` (темне, тоді за положенням)."""
    V = VYKHID / "redux-обличчя"
    V.mkdir(parents=True, exist_ok=True)
    m.free()
    for i, k in enumerate(KADRY, 1):
        kadr_oblychchia(k, V / ("v%d-oblychchia.png" % i))
    m.free()
    poza = m.stage(str(POZA))
    for i in range(1, 4):
        ob = m.stage(str(V / ("v%d-oblychchia.png" % i)))
        for sd in sidy:
            g = b2.graf_redux(poza, poza, ob, PROMT_R, sd, "ork_ob_%d" % i, syla=0.3, shum=0.78)
            g["16"]["inputs"]["latent_image"] = ["5", 0]
            del g["6"], g["7"]
            zrobyty(g, V / ("v%d-s%d.png" % (i, sd)))
    m.free()


if __name__ == "__main__":
    if "--обличчя" in sys.argv:
        oblychchia_main([int(x) for x in sys.argv[1:] if x.isdigit()] or [4201, 4202, 4203])
    else:
        main()
