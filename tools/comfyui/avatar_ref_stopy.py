#!/usr/bin/env python3
"""Ступні референсу — у вигляді спереду (02.10.2026).

Слово замовника: «бачу що на референсі ступні зроблені як вигляд згори а
на моделі вигляд спереду, виправ референс». Kontext перемальовує ступні
камерою на рівні щиколоток; у кадр потім вклеюється лише смуга ступень
(`tools/avatar_ref_sym.py`), решта референсу лишається як була.

    python3 -u tools/comfyui/avatar_ref_stopy.py [--кроп | --маска]
"""
import os
import shutil
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster3d as m  # noqa: E402
import rasy_kontext as rk  # noqa: E402

KORIN = Path(__file__).resolve().parents[2]
D = KORIN / "wiki/img/test/avatar/mpfb2"
DZHERELO = D / "plavky-s411.png"
SIDY = (511, 512, 513)
# На всьому кадрі Kontext тримав камеру кадру й ступні лишались «згори»
# (s511–s513). Тому — кроп гомілок і ступень (x 240–752, y 512–1024),
# збільшений удвічі: на ньому вид легше змінити.
KROP = (240, 512, 752, 1024)
PROMT_KROP = (
    "Change the camera angle: photograph these bare feet from floor level, "
    "the camera lies on the floor directly in front of them, so the feet "
    "and toes are seen head-on from the front, short and foreshortened, the "
    "soles and the tops of the feet are not visible, the heels are hidden "
    "behind. Keep the same shins, ankles, skin tone, body hair, light grey "
    "background, lighting and photorealistic style.")
PROMT = (
    "Redraw only his bare feet as seen in a straight-on front view with the "
    "camera level with his ankles: the feet look short and foreshortened, "
    "the toes face the camera and point slightly outward, the tops of the "
    "feet and the toenails are seen from the front, the heels are hidden "
    "behind the feet, the soles stand flat on the floor. Keep everything "
    "else exactly the same: the same man, face, beard, hair, dark navy swim "
    "trunks, arms, legs, ankles, background, lighting and photorealistic "
    "style.")


def krop():
    from PIL import Image
    im = Image.open(DZHERELO).convert("RGB").crop(KROP)
    kudy = D / "stopy-krop.png"
    im.resize((1024, 1024), Image.LANCZOS).save(kudy)
    rk.PROMT = PROMT_KROP
    image = m.stage(str(kudy))
    for seed in (521, 522, 523):
        v = D / ("stopy-krop-s%d.png" % seed)
        if v.exists():
            continue
        done = m.run(rk.graf(image, seed, "mpfb_stopy_krop_s%d" % seed))
        out = done["outputs"]["13"]["images"][-1]
        shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"],
                                 out["filename"]), v)
        print("готово", seed, v, flush=True)


# Kontext і на кропі камеру не міняв (s521–s523) — тому перемальовування
# маскою: FLUX dev, латент із маскою шуму лише на ступнях (від щиколоток),
# гомілки й тло лишаються підказкою.
PROMT_MASKA = (
    "Photograph of a man's bare feet standing on a light grey studio floor, "
    "seen straight from the front with the camera at floor level: the toes "
    "face the camera, the feet look short and foreshortened, the ankles "
    "rise above them, the soles are flat on the floor, soft studio lighting, "
    "tanned skin, photorealistic.")
MASKA_Y0 = 820          # у кропі ×2: щиколотки (y≈922 кадру)


def maska_krop():
    from PIL import Image, ImageFilter
    import numpy as np
    mk = Image.open(D / "maska-plavky-s411.png").convert("L").crop(KROP)
    mk = mk.resize((1024, 1024), Image.NEAREST)
    a = np.array(mk.filter(ImageFilter.MaxFilter(41))) > 127
    a[:MASKA_Y0] = False
    kudy = D / "stopy-krop-maska.png"
    Image.fromarray((a * 255).astype(np.uint8)).save(kudy)
    return kudy


def graf_maska(image, maska, seed, prefix, denoise=0.85):
    return {
        "1": {"class_type": "UnetLoaderGGUF",
              "inputs": {"unet_name": "flux1-dev-Q4_K_S.gguf"}},
        "2": {"class_type": "DualCLIPLoader",
              "inputs": {"clip_name1": "clip_l.safetensors",
                         "clip_name2": "t5xxl_fp8_e4m3fn.safetensors",
                         "type": "flux"}},
        "3": {"class_type": "VAELoader",
              "inputs": {"vae_name": "ae.safetensors"}},
        "4": {"class_type": "LoadImage", "inputs": {"image": image}},
        "5": {"class_type": "LoadImageMask",
              "inputs": {"image": maska, "channel": "red"}},
        "6": {"class_type": "VAEEncode",
              "inputs": {"pixels": ["4", 0], "vae": ["3", 0]}},
        "7": {"class_type": "SetLatentNoiseMask",
              "inputs": {"samples": ["6", 0], "mask": ["5", 0]}},
        "8": {"class_type": "CLIPTextEncode",
              "inputs": {"text": PROMT_MASKA, "clip": ["2", 0]}},
        "9": {"class_type": "FluxGuidance",
              "inputs": {"conditioning": ["8", 0], "guidance": 3.5}},
        "10": {"class_type": "ConditioningZeroOut",
               "inputs": {"conditioning": ["8", 0]}},
        "11": {"class_type": "KSampler",
               "inputs": {"model": ["1", 0], "seed": seed, "steps": 28,
                          "cfg": 1.0, "sampler_name": "euler",
                          "scheduler": "simple", "positive": ["9", 0],
                          "negative": ["10", 0], "latent_image": ["7", 0],
                          "denoise": denoise}},
        "12": {"class_type": "VAEDecode",
               "inputs": {"samples": ["11", 0], "vae": ["3", 0]}},
        "13": {"class_type": "SaveImage",
               "inputs": {"images": ["12", 0], "filename_prefix": prefix}},
    }


def maska():
    krop_png = D / "stopy-krop.png"
    image = m.stage(str(krop_png))
    mk = m.stage(str(maska_krop()))
    for seed in (531, 532, 533, 534):
        v = D / ("stopy-maska-s%d.png" % seed)
        if v.exists():
            continue
        done = m.run(graf_maska(image, mk, seed, "mpfb_stopy_maska_s%d" % seed))
        out = done["outputs"]["13"]["images"][-1]
        shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"],
                                 out["filename"]), v)
        print("готово", seed, v, flush=True)


def main():
    m.free()
    if "--кроп" in sys.argv:
        return krop()
    if "--маска" in sys.argv:
        return maska()
    rk.PROMT = PROMT
    image = m.stage(str(DZHERELO))
    for seed in SIDY:
        kudy = D / ("stopy-s%d.png" % seed)
        if kudy.exists():
            continue
        done = m.run(rk.graf(image, seed, "mpfb_stopy_s%d" % seed))
        out = done["outputs"]["13"]["images"][-1]
        shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"],
                                 out["filename"]), kudy)
        print("готово", seed, kudy, flush=True)


if __name__ == "__main__":
    main()
