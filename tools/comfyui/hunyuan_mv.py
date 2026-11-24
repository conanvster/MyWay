#!/usr/bin/env python3
"""Форма з кількох видів — Hunyuan3D-2mv (24.11.2026, П-288, спосіб Б порівняння).

Кадри одного масштабу й середини (`tools/blender/kadry_4.py` + Qwen-Edit) → сітка без
текстури (колір накладає `tools/blender/proektsiia_4.py`). Тло кадрів — рівне сіре: тут воно
стає білим, як у навчальних кадрах моделі; квадрат — доповненням білим.

    ~/Програми/cv-venv/bin/python -u tools/comfyui/hunyuan_mv.py <вихід.glb> \
        --спереду a.png --ззаду b.png [--зліва c.png] [--справа d.png] [--сід 1] [--роздільність 384]
"""
import os
import shutil
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster3d as m  # noqa: E402


def arg(k, typ, d):
    return typ(sys.argv[sys.argv.index(k) + 1]) if k in sys.argv else d


def bile(shliakh, kudy):
    a = np.asarray(Image.open(shliakh).convert("RGB")).astype(np.int16)
    tlo = np.median(np.concatenate([a[:8].reshape(-1, 3), a[:, :8].reshape(-1, 3),
                                    a[:, -8:].reshape(-1, 3)]), 0)
    blyzko = np.abs(a - tlo).sum(2) < 24
    a[blyzko] = 255
    h, w = a.shape[:2]
    s = max(h, w)
    kv = np.full((s, s, 3), 255, np.uint8)
    kv[(s - h) // 2:(s - h) // 2 + h, (s - w) // 2:(s - w) // 2 + w] = a
    Image.fromarray(kv).resize((518, 518), Image.LANCZOS).save(kudy)
    return kudy


def main():
    vyhid = os.path.abspath(sys.argv[1])
    tmp = os.path.join(os.path.dirname(vyhid), "_hmv")
    os.makedirs(tmp, exist_ok=True)
    g = {
        "1": {"class_type": "ImageOnlyCheckpointLoader",
              "inputs": {"ckpt_name": "hunyuan3d-dit-v2-mv.safetensors"}},
        "2": {"class_type": "ModelSamplingAuraFlow", "inputs": {"model": ["1", 0], "shift": 1.0}},
        "20": {"class_type": "Hunyuan3Dv2ConditioningMultiView", "inputs": {}},
        "21": {"class_type": "EmptyLatentHunyuan3Dv2", "inputs": {"resolution": 4096, "batch_size": 1}},
        "22": {"class_type": "KSampler",
               "inputs": {"model": ["2", 0], "seed": arg("--сід", int, 1), "steps": 30, "cfg": 5.0,
                          "sampler_name": "euler", "scheduler": "normal",
                          "positive": ["20", 0], "negative": ["20", 1],
                          "latent_image": ["21", 0], "denoise": 1.0}},
        "23": {"class_type": "VAEDecodeHunyuan3D",
               "inputs": {"samples": ["22", 0], "vae": ["1", 2], "num_chunks": 8000,
                          "octree_resolution": arg("--роздільність", int, 384)}},
        "24": {"class_type": "VoxelToMesh",
               "inputs": {"voxel": ["23", 0], "algorithm": "surface net", "threshold": 0.6}},
        "25": {"class_type": "SaveGLB", "inputs": {"mesh": ["24", 0], "filename_prefix": "3d/hmv"}},
    }
    n = 30
    for bik, kl in (("--спереду", "front"), ("--зліва", "left"), ("--ззаду", "back"), ("--справа", "right")):
        if bik not in sys.argv:
            continue
        p = bile(arg(bik, str, ""), os.path.join(tmp, kl + ".png"))
        g[str(n)] = {"class_type": "LoadImage", "inputs": {"image": m.stage(p)}}
        g[str(n + 1)] = {"class_type": "CLIPVisionEncode",
                         "inputs": {"clip_vision": ["1", 1], "image": [str(n), 0], "crop": "none"}}
        g["20"]["inputs"][kl] = [str(n + 1), 0]
        n += 2
    m.free()
    done = m.run(g)
    out = done["outputs"]["25"]["3d"][0] if "3d" in done["outputs"]["25"] else \
        [v for v in done["outputs"]["25"].values()][0][0]
    shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"], out["filename"]), vyhid)
    m.free()
    print("готово", vyhid, flush=True)


if __name__ == "__main__":
    main()
