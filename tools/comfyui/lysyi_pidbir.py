#!/usr/bin/env python3
"""Лиса голова й без бороди: який спосіб працює з FLUX (09.11.2026).

Слово замовника: «реально лисих та без волосся створити не вдалося,
можливо треба вивчити як правильно задавати умови для цієї моделі».
Чому не вдавалось (`ork_lysyi.py`): (1) FLUX dev без негативу (cfg 1)
читає «no beard, no hair» як «beard, hair»; (2) граф `rasy_realizm.graf_flux`
тримає ControlNet Canny від вихідного кадру — контур бороди й зачіски
малюється знову; (3) маска лише темних пікселів — борода довкола лишається
і продовжується в масці. Три способи на кадрах замовника:

  A · Kontext — одна дія за раз («прибери бороду…», тоді «поголи голову…»);
  B · FLUX dev під маскою (маківка, скроні, щелепа, підборіддя), без
      ControlNet, промпт лише ствердний (без слів beard/hair);
  C · те саме з негативом (cfg 3: beard, mustache, stubble, hair …).

    ~/Програми/cv-venv/bin/python -u tools/comfyui/lysyi_pidbir.py <тека> <кадр…>
→ <тека>/<кадр>-A.png, -B.png, -C.png, маска -holova.png, аркуш лиса-підбір.png
"""
import os
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster3d as m  # noqa: E402
import rasy_kontext as rk  # noqa: E402

TEKA = Path(sys.argv[1])
KADRY = [Path(a) for a in sys.argv[2:]]
SID = 5101
MITKA = os.environ.get("MITKA", "")      # другий раунд — «2»: промпти без кольору й ікол (09.11)
BEZ_C = bool(MITKA)
LYSHE_A = MITKA == "3"                   # третій раунд — лише Kontext
BORODA = ("Remove his beard and mustache completely, so his chin, jaw, cheeks and "
          "upper lip are smooth bare skin. He stays an orc: keep his long pointed "
          "orc ears, his two lower tusks jutting from the lower lip, his heavy orc "
          "brow and his stern orc face exactly the same. Keep his skin the same pale "
          "olive-grey color as now. Keep everything else exactly the same: same body, "
          "same pose, same black briefs, same background, same lighting.")
HOLOVA = ("Shave his head completely bald, so the whole scalp, the top and the back "
          "of his head and the temples are smooth bare skin. He stays an orc: keep "
          "his long pointed orc ears, his two lower tusks, his heavy orc brow and his "
          "stern orc face exactly the same. Keep his skin the same pale olive-grey "
          "color as now. Keep everything else exactly the same: same body, same pose, "
          "same black briefs, same background, same lighting.")
STVERDNO = ("Photo of a huge muscular male orc with a shiny smooth bald scalp, a "
            "clean-shaven smooth bare jaw, chin, cheeks and upper lip, rough "
            "weathered skin with pores and fine scars, heavy brow, "
            "pointed ears, stern face, bare muscular shoulders and chest, plain grey "
            "studio background, soft even light, photorealistic.")
NEHATYV = "beard, mustache, stubble, goatee, sideburns, facial hair, hair, hairstyle, braids, ponytail, mohawk"


def holova_maska(kadr, kudy):
    """Маківка, скроні, щелепа й підборіддя — за силуетом голови."""
    syl_f = kudy.with_name(kudy.stem + "-syl.png")
    m.cutout(str(kadr), str(syl_f))
    syl = np.asarray(Image.open(syl_f).convert("L")) > 128
    syl_f.unlink()
    h, w = syl.shape
    ys = np.where(syl.any(1))[0]
    top, zr = ys.min(), ys.max() - ys.min()
    cx = float(np.where(syl[top + int(0.05 * zr)])[0].mean())
    im = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(im)
    # голова до основи шиї — без очей і носа (лишається обличчя)
    d.ellipse((cx - 0.075 * zr, top - 0.01 * zr, cx + 0.075 * zr, top + 0.075 * zr), fill=255)
    d.rectangle((cx - 0.085 * zr, top + 0.02 * zr, cx - 0.04 * zr, top + 0.16 * zr), fill=255)
    d.rectangle((cx + 0.04 * zr, top + 0.02 * zr, cx + 0.085 * zr, top + 0.16 * zr), fill=255)
    d.ellipse((cx - 0.07 * zr, top + 0.085 * zr, cx + 0.07 * zr, top + 0.19 * zr), fill=255)
    im = im.filter(ImageFilter.GaussianBlur(4))
    im.save(kudy)
    return kudy


def graf_flux_maska(kadr, maska, promt, seed, prefix, nehatyv=None):
    g = {
        "1": {"class_type": "UnetLoaderGGUF", "inputs": {"unet_name": "flux1-dev-Q4_K_S.gguf"}},
        "2": {"class_type": "DualCLIPLoader",
              "inputs": {"clip_name1": "clip_l.safetensors",
                         "clip_name2": "t5xxl_fp8_e4m3fn.safetensors", "type": "flux"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": "ae.safetensors"}},
        "4": {"class_type": "LoadImage", "inputs": {"image": kadr}},
        "5": {"class_type": "LoadImageMask", "inputs": {"image": maska, "channel": "red"}},
        "6": {"class_type": "VAEEncode", "inputs": {"pixels": ["4", 0], "vae": ["3", 0]}},
        "7": {"class_type": "SetLatentNoiseMask", "inputs": {"samples": ["6", 0], "mask": ["5", 0]}},
        "8": {"class_type": "CLIPTextEncode", "inputs": {"text": promt, "clip": ["2", 0]}},
        "9": {"class_type": "FluxGuidance", "inputs": {"conditioning": ["8", 0], "guidance": 3.5}},
        "10": ({"class_type": "CLIPTextEncode", "inputs": {"text": nehatyv, "clip": ["2", 0]}}
               if nehatyv else {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["8", 0]}}),
        "11": {"class_type": "KSampler",
               "inputs": {"model": ["1", 0], "seed": seed, "steps": 28,
                          "cfg": 3.0 if nehatyv else 1.0, "sampler_name": "euler",
                          "scheduler": "simple", "positive": ["9", 0], "negative": ["10", 0],
                          "latent_image": ["7", 0], "denoise": 1.0}},
        "12": {"class_type": "VAEDecode", "inputs": {"samples": ["11", 0], "vae": ["3", 0]}},
        "13": {"class_type": "SaveImage", "inputs": {"images": ["12", 0], "filename_prefix": prefix}},
    }
    return g


def zberehty(done, kudy):
    out = [o for v in done["outputs"].values() for o in v.get("images", [])][-1]
    shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"], out["filename"]), kudy)
    print("готово", kudy, flush=True)


def main():
    TEKA.mkdir(parents=True, exist_ok=True)
    m.free()
    masky = {k: holova_maska(k, TEKA / (k.stem + "-holova.png")) for k in KADRY}
    m.free()
    for k in KADRY:                                   # A · Kontext: борода, тоді голова
        rk.PROMT = BORODA
        a1 = TEKA / (k.stem + "-A1" + MITKA + ".png")
        zberehty(m.run(rk.graf(m.stage(str(k)), SID, "lysyi_A1")), a1)
        rk.PROMT = HOLOVA
        zberehty(m.run(rk.graf(m.stage(str(a1)), SID, "lysyi_A2")), TEKA / (k.stem + "-A" + MITKA + ".png"))
    m.free()
    for k in ([] if LYSHE_A else KADRY):
        kd, mk = m.stage(str(k)), m.stage(str(masky[k]))
        zberehty(m.run(graf_flux_maska(kd, mk, STVERDNO, SID, "lysyi_B")), TEKA / (k.stem + "-B" + MITKA + ".png"))
        if not BEZ_C:
            zberehty(m.run(graf_flux_maska(kd, mk, STVERDNO, SID, "lysyi_C", NEHATYV)), TEKA / (k.stem + "-C" + MITKA + ".png"))
    m.free()
    s = 380
    o = Image.new("RGB", (s * 5, len(KADRY) * (s + 30)), (24, 24, 24))
    d = ImageDraw.Draw(o)
    sh = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 16)
    for r, k in enumerate(KADRY):
        ryad = [("вхід", k), ("маска B/C", masky[k]), ("A · Kontext", TEKA / (k.stem + "-A" + MITKA + ".png")),
                ] + ([] if LYSHE_A else [("B · ствердно", TEKA / (k.stem + "-B" + MITKA + ".png"))]) + (
                [] if BEZ_C else [("C · негатив", TEKA / (k.stem + "-C" + MITKA + ".png"))])
        for c, (p, f) in enumerate(ryad):
            im = Image.open(f).convert("RGB")
            w, h = im.size
            im = im.crop((int(w * 0.25), 0, int(w * 0.75), int(h * 0.5))).resize((s, s))
            o.paste(im, (c * s, r * (s + 30)))
            d.text((c * s + 6, r * (s + 30) + s + 6), p, fill=(230, 220, 200), font=sh)
    o.save(TEKA / ("лиса-підбір%s.png" % MITKA))
    print("аркуш", TEKA / ("лиса-підбір%s.png" % MITKA), flush=True)


if __name__ == "__main__":
    main()
