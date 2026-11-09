#!/usr/bin/env python3
"""Пілот деталізації аватара — орк-чоловік, вигляди на 360° (09.11.2026).

Слово замовника: «так, роби пілот орка … Kontext — якось можна його або іншу
модель налаштувати робити рендери топлес, налаштувати щоб зробити 360
градусів вигляд». Шлях — від нашої геометрії, не від картинки: рендер
основи MPFB з кута (`vydy.py`, Blender) → FLUX.1 dev поверх рендера (i2i) +
ControlNet Union за контурами рендера (силует і пропорції — наші, тож
проєкція ляже на сітку) + Redux з кадру орка (шкіра, обличчя, стиль). Тіло
на рендері вже оголене — FLUX лише перемальовує, тож топлес не впирається в
обмеження Kontext.

    ~/Програми/cv-venv/bin/python -u tools/comfyui/ork_pilot_vydy.py <тека рендерів> <вихід> \
        [--кути 0,45,…] [--шум 0.6] [--redux 0.35] [--сід 7001]

Вхід — `<тека>/вид-<кут>.png`, вихід — `<вихід>/вид-<кут>.png`.
"""
import os
import shutil
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster3d as m  # noqa: E402

KORIN = Path(__file__).resolve().parents[2]
CN = "FLUX.1-dev-ControlNet-Union-Pro-2.0.safetensors"
REF = KORIN / "art/орк-пілот-2026-11-09/ref/перед-tpose.png"

OPYS = (
    "Photorealistic full body studio photo of a huge male orc, {kut}. "
    "Massive muscular body, olive grey-green skin with natural pores, "
    "visible veins on arms and forearms, a few pale old scars, defined abs "
    "and chest, thick neck and trapezius, pointed ears, heavy brow, broad "
    "flat nose, stern face, shaved bald head, no beard, mouth closed. "
    "Bare skin everywhere, wearing only short plain dark underwear shorts. "
    "Arms held down and away from the body, standing straight, neutral "
    "pose. Even soft studio lighting, plain dark grey background, no "
    "props, no clothing, no jewelry, no straps, no belt.")
KUTY_SLOVA = {0: "front view", 45: "three-quarter front-left view",
              90: "left side profile view", 135: "three-quarter back-left view",
              180: "back view, seen from behind", 225: "three-quarter back-right view",
              270: "right side profile view", 315: "three-quarter front-right view"}


def arg(k, typ, d):
    return typ(sys.argv[sys.argv.index(k) + 1]) if k in sys.argv else d


def graf(kadr, ref, promt, seed, shum, redux, cn_syla=0.55, cn_kinets=0.6):
    return {
        "1": {"class_type": "UnetLoaderGGUF", "inputs": {"unet_name": "flux1-dev-Q4_K_S.gguf"}},
        "2": {"class_type": "DualCLIPLoader",
              "inputs": {"clip_name1": "clip_l.safetensors",
                         "clip_name2": "t5xxl_fp8_e4m3fn.safetensors", "type": "flux"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": "ae.safetensors"}},
        "4": {"class_type": "LoadImage", "inputs": {"image": kadr}},
        "5": {"class_type": "Canny", "inputs": {"image": ["4", 0],
                                                "low_threshold": 0.15, "high_threshold": 0.35}},
        "6": {"class_type": "VAEEncode", "inputs": {"pixels": ["4", 0], "vae": ["3", 0]}},
        "8": {"class_type": "CLIPTextEncode", "inputs": {"text": promt, "clip": ["2", 0]}},
        "20": {"class_type": "StyleModelLoader",
               "inputs": {"style_model_name": "flux1-redux-dev.safetensors"}},
        "21": {"class_type": "CLIPVisionLoader",
               "inputs": {"clip_name": "sigclip_vision_patch14_384.safetensors"}},
        "22": {"class_type": "LoadImage", "inputs": {"image": ref}},
        "23": {"class_type": "CLIPVisionEncode",
               "inputs": {"clip_vision": ["21", 0], "image": ["22", 0], "crop": "center"}},
        "24": {"class_type": "StyleModelApply",
               "inputs": {"conditioning": ["8", 0], "style_model": ["20", 0],
                          "clip_vision_output": ["23", 0], "strength": redux,
                          "strength_type": "multiply"}},
        "9": {"class_type": "FluxGuidance", "inputs": {"conditioning": ["24", 0], "guidance": 3.0}},
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
        "13": {"class_type": "SaveImage", "inputs": {"images": ["12", 0], "filename_prefix": "ork_pilot"}},
    }


def main():
    vhid, vyhid = Path(sys.argv[1]), Path(sys.argv[2])
    vyhid.mkdir(parents=True, exist_ok=True)
    kuty = [int(k) for k in arg("--кути", str, "0,45,90,135,180,225,270,315").split(",")]
    shum = arg("--шум", float, 0.6)
    redux = arg("--redux", float, 0.35)
    sid = arg("--сід", int, 7001)
    ref = m.stage(str(REF))
    for k in kuty:
        kadr = m.stage(str(vhid / ("вид-%03d.png" % k)))
        promt = OPYS.format(kut=KUTY_SLOVA.get(k, "view"))
        done = m.run(graf(kadr, ref, promt, sid, shum, redux))
        out = done["outputs"]["13"]["images"][-1]
        shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"], out["filename"]),
                    vyhid / ("вид-%03d.png" % k))
        print("готово кут", k, flush=True)


if __name__ == "__main__":
    main()
