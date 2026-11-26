#!/usr/bin/env python3
"""Проба 26.11.2026, варіант 2: увесь аркуш тим самим ланцюжком, що й monstr_arkush.py
(реф → А-0 → Т-0 → ракурси; монстр першою картинкою, каркас другою), але модель —
Qwen-Image 2.1 Turbo (int8_convrot, 7 млрд), кодувальник qwen3vl_8b int8, 8 кроків за
розкладом шаблону ComfyUI `image_qwen_image_2_1_turbo_image_edit.json`, cfg 1. Картинки в
інструкції — `<image1>`, `<image2>` (так велить шаблон). Ліцензія — Qwen Research (лише
некомерційне; замовник 26.11: гра некомерційна).
    ~/Програми/cv-venv/bin/python -u tools/comfyui/proby/qwen21_arkush.py драконід-воїн наг вампір
→ art/monsters/_аркуш-каркас/проба-моделей/v2-qwen21/<вид>/ (кадри, сирі/, аркуш.jpg)
"""
import os
import shutil
import sys

TUT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(TUT))
import monstr_arkush as ma  # noqa: E402

VYKHID = os.path.join(ma.KARKAS, "проба-моделей", "v2-qwen21")
SIGMY = "1.0, 0.978453, 0.95418, 0.926626, 0.89508, 0.845148, 0.704534, 0.414568, 0"


def graf(persha, druha, promt, seed):
    obrazy = {"images.image_1": ["6", 0]}
    g = {
        "1": {"class_type": "UNETLoader",
              "inputs": {"unet_name": "qwen_image_2.1_turbo_int8_convrot.safetensors",
                         "weight_dtype": "default"}},
        "2": {"class_type": "CLIPLoader",
              "inputs": {"clip_name": "qwen3vl_8b_int8_convrot.safetensors",
                         "type": "qwen_image", "device": "default"}},
        "3": {"class_type": "VAELoader",
              "inputs": {"vae_name": "qwen_image_2.1_vae_bf16.safetensors"}},
        "4": {"class_type": "QwenImage21Cache",
              "inputs": {"model": ["1", 0], "device": "auto", "dtype": "default"}},
        "6": {"class_type": "LoadImage", "inputs": {"image": persha}},
        "9": {"class_type": "CFGGuider",
              "inputs": {"model": ["4", 0], "positive": ["8", 0], "negative": ["8", 1],
                         "cfg": 1.0}},
        "10": {"class_type": "RandomNoise", "inputs": {"noise_seed": seed}},
        "11": {"class_type": "KSamplerSelect", "inputs": {"sampler_name": "euler"}},
        "12": {"class_type": "ManualSigmas", "inputs": {"sigmas": SIGMY}},
        "13": {"class_type": "SamplerCustomAdvanced",
               "inputs": {"noise": ["10", 0], "guider": ["9", 0], "sampler": ["11", 0],
                          "sigmas": ["12", 0], "latent_image": ["8", 2]}},
        "14": {"class_type": "VAEDecode", "inputs": {"samples": ["13", 0], "vae": ["3", 0]}},
        "15": {"class_type": "SaveImage",
               "inputs": {"images": ["14", 0], "filename_prefix": "proba_q21"}},
    }
    if druha:
        g["7"] = {"class_type": "LoadImage", "inputs": {"image": druha}}
        obrazy["images.image_2"] = ["7", 0]
    g["8"] = {"class_type": "TextEncodeQwenImage21",
              "inputs": dict({"clip": ["2", 0], "vae": ["3", 0], "prompt": promt,
                              "negative_prompt": "", "resolution": 1024}, **obrazy)}
    return g


def zapustyty(m, b2, persha, druha, promt, kudy):
    promt = (promt.replace("the first image", "<image1>")
             .replace("the second image", "<image2>").replace("From the image", "From <image1>"))
    done = m.run(graf(m.stage(persha), m.stage(druha) if druha else None, promt, ma.SID))
    out = [o for v in done["outputs"].values() for o in v.get("images", [])][-1]
    syryi = os.path.join(os.path.dirname(kudy), "сирі", os.path.basename(kudy))
    os.makedirs(os.path.dirname(syryi), exist_ok=True)
    shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"], out["filename"]), syryi)
    ma.chyste_tlo(m, syryi, kudy)


ma.zapustyty = zapustyty
ma.teka = lambda vyd: os.path.join(VYKHID, vyd)
ma.zheneruvaty(sys.argv[1:])
