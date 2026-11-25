#!/usr/bin/env python3
"""Пілот 2 якості орка (09.11.2026): чиста основа одним проходом і ракурси.

Слово замовника: «якість погана … потрібно змінити моделі та підходи» → «так,
роби розвідку, скачувати можна, можна лімітоване онлайн, лише безплатне» →
«так, починай пілот». Попередня ітерація зіпсувалась ланцюжком правок (Redux →
Kontext ×3 → тон): кожна розмивала шкіру. Тут:

  основа — Qwen-Image-Edit-2511 (Lightning 8 кроків) ОДНИМ проходом від
           референсу r4 (`ref/перед-tpose.png`): топлес, лиса, без бороди,
           лише чорні плавки, босоніж; поза, обличчя й шкіра — референсу;
  ракурси — та сама модель + LoRA «Multiple Angles» (fal, сила 0,9):
           `<sks> <ракурс> eye-level shot wide shot` — перед, боки, спина
           для Hunyuan3D-2mv (форма з кількох видів).

    ~/Програми/cv-venv/bin/python -u tools/comfyui/pilot2_ork.py основа [сід…]
    ~/Програми/cv-venv/bin/python -u tools/comfyui/pilot2_ork.py ракурси <основа.png> [сід]
→ art/орк-пілот2-2026-11-09/osnova-s<сід>.png | vyd-<ракурс>.png, аркуші
"""
import os
import shutil
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster3d as m  # noqa: E402

ROOT = Path(m.ROOT)
TEKA = ROOT / "art" / "орк-пілот2-2026-11-09"
REF = ROOT / "art" / "орк-пілот-2026-11-09" / "ref" / "перед-tpose.png"
OSNOVA = ("Make this orc topless and barefoot, wearing only plain tight black boxer "
          "briefs: remove the belt, the pouches, the leather apron, the trousers, the "
          "knee pads and the necklace, so his chest, belly, hips, thighs, knees and legs "
          "are bare green orc skin. Shave his head completely bald and remove his beard "
          "and all braids, so his scalp, jaw and chin are smooth bare green orc skin. "
          "Keep his face, his lower tusks, his pointed ears, his green orc skin color "
          "and texture, his massive muscular build, his T-pose and the plain grey "
          "background exactly the same. Photorealistic.")
RAKURSY = {"pered": "front view", "pravyi": "right side view", "zad": "back view",
           "livyi": "left side view"}


def graf(img, promt, seed, prefix, kut=False):
    lora_kutiv = {"2": {"class_type": "LoraLoaderModelOnly",
                        "inputs": {"model": ["1", 0], "strength_model": 1.0,
                                   "lora_name": "Qwen-Image-Edit-2511-Lightning-8steps-V1.0-bf16.safetensors"}}}
    g = {
        "1": {"class_type": "UnetLoaderGGUF",
              "inputs": {"unet_name": "qwen-image-edit-2511-Q4_K_M.gguf"}},
        **lora_kutiv,
        "3": {"class_type": "ModelSamplingAuraFlow",
              "inputs": {"model": ["20" if kut else "2", 0], "shift": 3.0}},
        "4": {"class_type": "CLIPLoader",
              "inputs": {"clip_name": "qwen_2.5_vl_7b_fp8_scaled.safetensors", "type": "qwen_image"}},
        "5": {"class_type": "VAELoader", "inputs": {"vae_name": "qwen_image_vae.safetensors"}},
        "6": {"class_type": "LoadImage", "inputs": {"image": img}},
        "7": {"class_type": "ImageScaleToTotalPixels",
              "inputs": {"image": ["6", 0], "upscale_method": "lanczos", "megapixels": 1.0,
                         "resolution_steps": 1}},
        "9": {"class_type": "TextEncodeQwenImageEditPlus",
              "inputs": {"clip": ["4", 0], "prompt": promt, "vae": ["5", 0], "image1": ["7", 0]}},
        "10": {"class_type": "TextEncodeQwenImageEditPlus",
               "inputs": {"clip": ["4", 0], "prompt": "", "vae": ["5", 0], "image1": ["7", 0]}},
        "11": {"class_type": "VAEEncode", "inputs": {"pixels": ["7", 0], "vae": ["5", 0]}},
        "12": {"class_type": "KSampler",
               "inputs": {"model": ["3", 0], "seed": seed, "steps": 8, "cfg": 1.0,
                          "sampler_name": "euler", "scheduler": "simple",
                          "positive": ["9", 0], "negative": ["10", 0],
                          "latent_image": ["11", 0], "denoise": 1.0}},
        "13": {"class_type": "VAEDecode", "inputs": {"samples": ["12", 0], "vae": ["5", 0]}},
        "14": {"class_type": "SaveImage", "inputs": {"images": ["13", 0], "filename_prefix": prefix}},
    }
    if kut:
        g["20"] = {"class_type": "LoraLoaderModelOnly",
                   "inputs": {"model": ["2", 0], "strength_model": 0.9,
                              "lora_name": "qwen-image-edit-2511-multiple-angles-lora.safetensors"}}
    return g


def zberehty(done, kudy):
    out = [o for v in done["outputs"].values() for o in v.get("images", [])][-1]
    shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"], out["filename"]), kudy)
    print("готово", kudy, flush=True)


def arkush(ryad, kudy, s=460):
    f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 18)
    o = Image.new("RGB", (s * len(ryad), s + 30), (24, 24, 24))
    d = ImageDraw.Draw(o)
    for i, (p, fn) in enumerate(ryad):
        im = Image.open(fn).convert("RGB")
        im.thumbnail((s, s))
        o.paste(im, (i * s + (s - im.width) // 2, 0))
        d.text((i * s + 8, s + 6), p, fill=(230, 220, 200), font=f)
    o.save(kudy)
    print("аркуш", kudy, flush=True)


def pidhotuvaty(vyd, kudy):
    """Ракурс для Hunyuan3D: фігура без тла (birefnet), по центру квадрата на білому."""
    import numpy as np
    msk_f = kudy.with_name(kudy.stem + "-m.png")
    m.cutout(str(vyd), str(msk_f))
    im = Image.open(vyd).convert("RGB")
    mk = Image.open(msk_f).convert("L").resize(im.size)
    a = np.asarray(mk) > 128
    ys, xs = np.where(a)
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    side = int(max(x1 - x0, y1 - y0) * 1.12)
    bile = Image.new("RGB", im.size, (255, 255, 255))
    bile.paste(im, (0, 0), mk)
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    kv = Image.new("RGB", (side, side), (255, 255, 255))
    kv.paste(bile.crop((cx - side // 2, cy - side // 2, cx + side // 2, cy + side // 2)), (0, 0))
    kv.resize((518, 518), Image.LANCZOS).save(kudy)
    msk_f.unlink()


def graf_2mv(vydy, seed, prefix, kroky=30, cfg=5.0, octree=384):
    """Hunyuan3D-2mv (вбудовані вузли ComfyUI): форма з кількох ракурсів, без текстури."""
    g = {"1": {"class_type": "ImageOnlyCheckpointLoader",
               "inputs": {"ckpt_name": "hunyuan3d-dit-v2-mv.safetensors"}}}
    vkhody = {}
    for i, (rol, img) in enumerate(vydy.items()):
        g["l%d" % i] = {"class_type": "LoadImage", "inputs": {"image": img}}
        g["e%d" % i] = {"class_type": "CLIPVisionEncode",
                        "inputs": {"clip_vision": ["1", 1], "image": ["l%d" % i, 0], "crop": "none"}}
        vkhody[rol] = ["e%d" % i, 0]
    g.update({
        "2": {"class_type": "Hunyuan3Dv2ConditioningMultiView", "inputs": vkhody},
        "3": {"class_type": "EmptyLatentHunyuan3Dv2", "inputs": {"resolution": 4096, "batch_size": 1}},
        "4": {"class_type": "KSampler",
              "inputs": {"model": ["1", 0], "seed": seed, "steps": kroky, "cfg": cfg,
                         "sampler_name": "euler", "scheduler": "normal",
                         "positive": ["2", 0], "negative": ["2", 1],
                         "latent_image": ["3", 0], "denoise": 1.0}},
        "5": {"class_type": "VAEDecodeHunyuan3D",
              "inputs": {"samples": ["4", 0], "vae": ["1", 2], "num_chunks": 8000,
                         "octree_resolution": octree}},
        "6": {"class_type": "VoxelToMesh", "inputs": {"voxel": ["5", 0], "algorithm": "surface net",
                                                      "threshold": 0.6}},
        "7": {"class_type": "SaveGLB", "inputs": {"mesh": ["6", 0], "filename_prefix": prefix}},
    })
    return g


def main():
    TEKA.mkdir(parents=True, exist_ok=True)
    rezhym = sys.argv[1]
    m.free()
    if rezhym == "основа":
        sidy = [int(a) for a in sys.argv[2:] if a.isdigit()] or [6101, 6102, 6103]
        ref = m.stage(str(REF))
        for sd in sidy:
            zberehty(m.run(graf(ref, OSNOVA, sd, "p2_osnova")), TEKA / ("osnova-s%d.png" % sd))
        arkush([("референс r4", REF)] + [("s%d" % sd, TEKA / ("osnova-s%d.png" % sd)) for sd in sidy],
               TEKA / "основа.png")
    elif rezhym == "ракурси":
        osn = Path(sys.argv[2])
        sd = int(sys.argv[3]) if len(sys.argv) > 3 else 6201
        st = m.stage(str(osn))
        for k, opys in RAKURSY.items():
            kudy = TEKA / ("vyd-%s.png" % k)
            zberehty(m.run(graf(st, "<sks> %s eye-level shot wide shot" % opys, sd, "p2_vyd_" + k, kut=True)), kudy)
        arkush([("основа", osn)] + [(k, TEKA / ("vyd-%s.png" % k)) for k in RAKURSY], TEKA / "ракурси.png")
    elif rezhym == "3d":
        # ракурс LoRA «right side view» — камера праворуч від персонажа, тобто
        # видно його ЛІВИЙ бік; `--дзеркало-боків` міняє, якщо форма вийде навпаки
        mina = "--дзеркало-боків" in sys.argv
        roli = {"front": "pered", "left": "livyi" if mina else "pravyi", "back": "zad",
                "right": "pravyi" if mina else "livyi"}
        if "--перед-зад" in sys.argv:
            # боки LoRA ракурсів малювала з опущеними руками (не Т-поза) —
            # суперечать переду й спині (10.11)
            roli = {"front": "pered", "back": "zad"}
        vydy = {}
        for rol, k in roli.items():
            kudy = TEKA / ("h3d-%s.png" % rol)
            pidhotuvaty(TEKA / ("vyd-%s.png" % k), kudy)
            vydy[rol] = m.stage(str(kudy))
        sd = next((int(a) for a in sys.argv[2:] if a.isdigit()), 6301)
        done = m.run(graf_2mv(vydy, sd, "p2_h3d"))
        out = [o for v in done["outputs"].values() for o in (v.get("3d") or v.get("meshes") or [])][-1]
        kudy = TEKA / ("h3d-2mv%s%s.glb" % ("-d" if mina else "", "-pz" if "--перед-зад" in sys.argv else ""))
        shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"], out["filename"]), kudy)
        print("готово", kudy, flush=True)
    m.free()


if __name__ == "__main__":
    main()
