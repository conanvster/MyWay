#!/usr/bin/env python3
"""Варіанти раси — реалістично, порівняння наявних моделей (13.10.2026).

Слово замовника: «wiki/rasy.html — підтягни Орк, чоловік — варіант 1, 2, 3 —
дуже мультяшно. Покажи теж варіанти з різних моделей». Генераторів картинок
у нас три (Pixal3D і TRELLIS — лише 3D), кожен — від того самого кадру
варіанта, ті самі сіди:
  * kontext  — FLUX.1 Kontext dev: перемалювати сам кадр живим фото;
  * flux-cn  — FLUX.1 dev з нуля + ControlNet Union-Pro 2.0 за контурами
               (Canny) кадру: компоновка звідти, вигляд — з опису;
  * flux-i2i — FLUX.1 dev поверх кадру (шум 0,65) + ті самі контури слабше.

    ~/Програми/cv-venv/bin/python -u tools/comfyui/rasy_realizm.py [ключ…]

Вихід — `art/meshy/2026-10-13/раси-реалізм/<ключ>-<модель>-s<сід>.png` і
аркуш `<ключ>-аркуш.png` (рядок на варіант: оригінал і кадри моделей).
"""
import os
import shutil
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster3d as m  # noqa: E402

KORIN = Path(__file__).resolve().parents[2]
RASY = KORIN / "wiki/img/rasy"
VYHID = KORIN / "art/meshy/2026-10-13/раси-реалізм"
SIDY = (5101, 5102)
CN = "FLUX.1-dev-ControlNet-Union-Pro-2.0.safetensors"
MODELI = ("kontext", "flux-cn", "flux-i2i")

REAL = ("Photorealistic live-action film still, a real actor in highly "
        "realistic orc prosthetic makeup, natural skin with pores, scars and "
        "veins, muted grey-green skin tone, realistic heavy muscular anatomy, "
        "real leather, steel and fur with wear and dirt, cinematic soft light, "
        "35mm photo, dark grey studio backdrop, full body from head to feet. "
        "Not a cartoon, not a 3D render, not a game model.")
OPYSY = {
    "орк-чоловік-v1": (
        "A huge male orc warrior with large lower tusks, pointed ears, black "
        "braided hair and a long black beard, one dark steel spiked pauldron "
        "and a fur mantle on the other shoulder, bare muscular chest with a "
        "leather harness, fur-trimmed leather bracers, a wide leather belt "
        "with pouches and a riveted leather tasset, dark trousers, fur leg "
        "wraps, leather boots, a long tattered dark cape. "),
    "орк-чоловік-v2": (
        "A huge male orc warrior with large lower tusks, pointed ears, black "
        "hair, a long braided black beard, a steel pauldron with fur on one "
        "shoulder, bare muscular chest, fur-trimmed leather bracers, a rope "
        "and leather belt with a round buckle, a leather skirt, fur leg "
        "wraps, barefoot sandals, a long dark cape. "),
    "орк-чоловік-v3": (
        "A huge male orc warrior with large lower tusks, pointed ears, black "
        "braids and a black beard, two layered steel pauldrons with a fur "
        "collar, bare muscular chest with crossed leather straps, leather "
        "bracers, a wide belt with leather tassets, fur leg wraps, leather "
        "sandals, a tattered dark cape. "),
}
KONTEXT = ("Turn this image into a photorealistic live-action film photo: the "
           "same orc warrior, same pose, same outfit and equipment, same "
           "framing, but as a real actor in highly realistic orc prosthetic "
           "makeup with natural skin texture, pores, scars and veins, muted "
           "grey-green skin, real worn leather, steel and fur. Not a cartoon, "
           "not a 3D render.")


def zahalne(kadr):
    return {
        "1": {"class_type": "UnetLoaderGGUF", "inputs": {"unet_name": "flux1-dev-Q4_K_S.gguf"}},
        "2": {"class_type": "DualCLIPLoader",
              "inputs": {"clip_name1": "clip_l.safetensors",
                         "clip_name2": "t5xxl_fp8_e4m3fn.safetensors", "type": "flux"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": "ae.safetensors"}},
        "4": {"class_type": "LoadImage", "inputs": {"image": kadr}},
    }


def graf_flux(kadr, promt, seed, i2i, guidance=3.5, shum=0.65, syla=None, kinets=None):
    g = zahalne(kadr)
    g.update({
        "5": {"class_type": "Canny", "inputs": {"image": ["4", 0],
                                                "low_threshold": 0.15, "high_threshold": 0.35}},
        "8": {"class_type": "CLIPTextEncode", "inputs": {"text": promt, "clip": ["2", 0]}},
        "9": {"class_type": "FluxGuidance", "inputs": {"conditioning": ["8", 0], "guidance": guidance}},
        "10": {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["8", 0]}},
        "14": {"class_type": "ControlNetLoader", "inputs": {"control_net_name": CN}},
        "16": {"class_type": "ControlNetApplyAdvanced",
               "inputs": {"positive": ["9", 0], "negative": ["10", 0], "control_net": ["14", 0],
                          "image": ["5", 0],
                          "strength": syla if syla is not None else (0.45 if i2i else 0.7),
                          "start_percent": 0.0,
                          "end_percent": kinets if kinets is not None else (0.5 if i2i else 0.65),
                          "vae": ["3", 0]}},
        "6": ({"class_type": "VAEEncode", "inputs": {"pixels": ["4", 0], "vae": ["3", 0]}}
              if i2i else
              {"class_type": "EmptySD3LatentImage",
               "inputs": {"width": 1024, "height": 1024, "batch_size": 1}}),
        "11": {"class_type": "KSampler",
               "inputs": {"model": ["1", 0], "seed": seed, "steps": 28, "cfg": 1.0,
                          "sampler_name": "euler", "scheduler": "simple",
                          "positive": ["16", 0], "negative": ["16", 1],
                          "latent_image": ["6", 0], "denoise": shum if i2i else 1.0}},
        "12": {"class_type": "VAEDecode", "inputs": {"samples": ["11", 0], "vae": ["3", 0]}},
        "13": {"class_type": "SaveImage", "inputs": {"images": ["12", 0], "filename_prefix": "rasy_flux"}},
    })
    return g


def graf_kontext(kadr, seed):
    g = zahalne(kadr)
    g["1"]["inputs"]["unet_name"] = "flux1-kontext-dev-Q5_K_S.gguf"
    g.update({
        "5": {"class_type": "FluxKontextImageScale", "inputs": {"image": ["4", 0]}},
        "6": {"class_type": "VAEEncode", "inputs": {"pixels": ["5", 0], "vae": ["3", 0]}},
        "7": {"class_type": "CLIPTextEncode", "inputs": {"text": KONTEXT, "clip": ["2", 0]}},
        "8": {"class_type": "ReferenceLatent", "inputs": {"conditioning": ["7", 0], "latent": ["6", 0]}},
        "9": {"class_type": "FluxGuidance", "inputs": {"conditioning": ["8", 0], "guidance": 2.5}},
        "10": {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["7", 0]}},
        "11": {"class_type": "KSampler",
               "inputs": {"model": ["1", 0], "seed": seed, "steps": 24, "cfg": 1.0,
                          "sampler_name": "euler", "scheduler": "simple",
                          "positive": ["9", 0], "negative": ["10", 0],
                          "latent_image": ["6", 0], "denoise": 1.0}},
        "12": {"class_type": "VAEDecode", "inputs": {"samples": ["11", 0], "vae": ["3", 0]}},
        "13": {"class_type": "SaveImage", "inputs": {"images": ["12", 0], "filename_prefix": "rasy_kontext"}},
    })
    return g


def zberehty(done, kudy):
    out = done["outputs"]["13"]["images"][-1]
    shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"], out["filename"]), kudy)
    print("готово", kudy.name, flush=True)


def arkush(kliuchi):
    s = 400
    kol = 1 + len(MODELI) * len(SIDY)
    o = Image.new("RGB", (s * kol, len(kliuchi) * (s + 34)), (24, 24, 24))
    d = ImageDraw.Draw(o)
    try:
        sh = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 18)
    except OSError:
        sh = ImageFont.load_default()
    for r, k in enumerate(kliuchi):
        kadry = [("%s (вікі)" % k, RASY / (k + ".png"))] + [
            ("%s s%d" % (mo, sd), VYHID / ("%s-%s-s%d.png" % (k, mo, sd)))
            for mo in MODELI for sd in SIDY]
        y = r * (s + 34)
        for i, (pidpys, f) in enumerate(kadry):
            if f.exists():
                o.paste(Image.open(f).convert("RGB").resize((s, s)), (i * s, y))
            d.text((i * s + 8, y + s + 6), pidpys, fill=(230, 220, 200), font=sh)
    kudy = VYHID / "орк-чоловік-аркуш.png"
    o.save(kudy)
    print("аркуш", kudy, flush=True)


def main():
    VYHID.mkdir(parents=True, exist_ok=True)
    kliuchi = [a for a in sys.argv[1:] if a in OPYSY] or list(OPYSY)
    kadry = {k: m.stage(str(RASY / (k + ".png"))) for k in kliuchi}
    m.free()
    for k in kliuchi:
        for sd in SIDY:
            for mo, i2i in (("flux-cn", False), ("flux-i2i", True)):
                kudy = VYHID / ("%s-%s-s%d.png" % (k, mo, sd))
                if not kudy.exists():
                    zberehty(m.run(graf_flux(kadry[k], OPYSY[k] + REAL, sd, i2i)), kudy)
    m.free()
    for k in kliuchi:
        for sd in SIDY:
            kudy = VYHID / ("%s-kontext-s%d.png" % (k, sd))
            if not kudy.exists():
                zberehty(m.run(graf_kontext(kadry[k], sd)), kudy)
    m.free()
    arkush(kliuchi)


if __name__ == "__main__":
    main()
