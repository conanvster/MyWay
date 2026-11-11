#!/usr/bin/env python3
"""Перемалювати кадр обличчя моделі генератора різкіше (П-285, 11.11.2026).

Кадр — `tools/blender/oblychchia_kadr.py кадр`. FLUX.1 dev поверх кадру (i2i) + ControlNet
Union за контурами: риси лишаються на місці, тож перемальоване ляже назад на сітку.

    ~/Програми/cv-venv/bin/python -u tools/comfyui/oblychchia_flux.py <кадр.png> <вихід.png> \
        [--шум 0.45] [--сід 7101] [--опис "…"]
"""
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster3d as m  # noqa: E402

CN = "FLUX.1-dev-ControlNet-Union-Pro-2.0.safetensors"
OPYS = (
    "Extreme close-up front portrait photograph of a fierce male orc, face fills the frame. "
    "Olive green skin with visible pores, fine wrinkles and a few old scars, heavy deeply "
    "wrinkled brow, small sharp amber eyes with dark pupils and wet highlights, broad flat "
    "nose, two large ivory lower tusks rising over the upper lip, closed mouth, long pointed "
    "ears. Thick black beard of individual coarse hairs, black hair combed straight back with "
    "visible strands, dark brown dreadlocks hanging at the sides. Photorealistic, sharp focus, "
    "flat even frontal soft light without shadows, plain dark grey background.")


def arg(k, typ, d):
    return typ(sys.argv[sys.argv.index(k) + 1]) if k in sys.argv else d


def graf(kadr, promt, seed, shum, cn_syla=0.6, cn_kinets=0.7):
    return {
        "1": {"class_type": "UnetLoaderGGUF", "inputs": {"unet_name": "flux1-dev-Q4_K_S.gguf"}},
        "2": {"class_type": "DualCLIPLoader",
              "inputs": {"clip_name1": "clip_l.safetensors",
                         "clip_name2": "t5xxl_fp8_e4m3fn.safetensors", "type": "flux"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": "ae.safetensors"}},
        "4": {"class_type": "LoadImage", "inputs": {"image": kadr}},
        "5": {"class_type": "Canny", "inputs": {"image": ["4", 0],
                                                "low_threshold": 0.1, "high_threshold": 0.3}},
        "6": {"class_type": "VAEEncode", "inputs": {"pixels": ["4", 0], "vae": ["3", 0]}},
        "8": {"class_type": "CLIPTextEncode", "inputs": {"text": promt, "clip": ["2", 0]}},
        "9": {"class_type": "FluxGuidance", "inputs": {"conditioning": ["8", 0], "guidance": 3.0}},
        "10": {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["8", 0]}},
        "14": {"class_type": "ControlNetLoader", "inputs": {"control_net_name": CN}},
        "16": {"class_type": "ControlNetApplyAdvanced",
               "inputs": {"positive": ["9", 0], "negative": ["10", 0], "control_net": ["14", 0],
                          "image": ["5", 0], "strength": cn_syla, "start_percent": 0.0,
                          "end_percent": cn_kinets, "vae": ["3", 0]}},
        "11": {"class_type": "KSampler",
               "inputs": {"model": ["1", 0], "seed": seed, "steps": 28, "cfg": 1.0,
                          "sampler_name": "euler", "scheduler": "simple",
                          "positive": ["16", 0], "negative": ["16", 1],
                          "latent_image": ["6", 0], "denoise": shum}},
        "12": {"class_type": "VAEDecode", "inputs": {"samples": ["11", 0], "vae": ["3", 0]}},
        "13": {"class_type": "SaveImage", "inputs": {"images": ["12", 0],
                                                     "filename_prefix": "oblychchia"}},
    }


def main():
    kadr = m.stage(sys.argv[1])
    done = m.run(graf(kadr, arg("--опис", str, OPYS), arg("--сід", int, 7101),
                      arg("--шум", float, 0.45)))
    out = done["outputs"]["13"]["images"][-1]
    shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"], out["filename"]), sys.argv[2])
    print("готово", sys.argv[2], flush=True)


if __name__ == "__main__":
    main()
