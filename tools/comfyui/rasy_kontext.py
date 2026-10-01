#!/usr/bin/env python3
"""Орчиці: точкове редагування Kontext від v1 (seed 8111), 01.10.2026.

Слово замовника: «тільки у v1 seed 8111 правильне обличчя орка жінки, а
груди та стегна все ще замалі». Новий FLUX-прогін дав би нове обличчя,
тож — розділ 1а `spec/генерація-референсів-монстрів.md`: той самий кадр,
одна дія, «Keep everything else exactly the same». Kontext не розуміє
заперечень — лише дії.

    python3 -u tools/comfyui/rasy_kontext.py [--дзеркало ~/гра-lineage]

Вхід — `wiki/img/test/rasy/vidkynuti/орк-жінка-v1-s8111.png`, вихід —
`орк-жінка-v1..v3.png` поруч зі сторінкою; сторінку перебудовує
`rasy_ref.zibraty()`.
"""
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster3d as m  # noqa: E402
import rasy_ref as r  # noqa: E402

DZHERELO = r.VYKHID / "vidkynuti" / "орк-жінка-v1-s8111.png"
# Перша спроба (сіди 61–63, «more voluptuous and heavier built») вийшла
# огрядною — замовник: «некрасивою, повернись до першого варіанта та
# спробуй зробити моделі трохи сексуальнішими». Тепер — жіночність і
# форма, а не вага.
SIDY = {1: 71, 2: 72, 3: 73}
PROMT = (
    "Make the same green-skinned orc woman slightly more attractive and "
    "sensual: an hourglass athletic figure with a fuller, shapely bust, a "
    "narrower waist and rounded, wider hips, strong toned muscular arms "
    "and legs, a confident proud posture. Make her clothing a little more "
    "fitted so it follows her curves: the linen shirt laced and slightly "
    "open at the neck, the leather vest tightly cinched at the waist by "
    "the belt. Keep everything else exactly the same: same face, same "
    "coarse stern expression, same green skin, same tusks, same hair, "
    "same ears, same trousers and boots, same standing pose, same misty "
    "pine forest background, same lighting, same photorealistic style.")


def graf(image, seed, prefix):
    return {
        "1": {"class_type": "UnetLoaderGGUF",
              "inputs": {"unet_name": "flux1-kontext-dev-Q5_K_S.gguf"}},
        "2": {"class_type": "DualCLIPLoader",
              "inputs": {"clip_name1": "clip_l.safetensors",
                         "clip_name2": "t5xxl_fp8_e4m3fn.safetensors",
                         "type": "flux"}},
        "3": {"class_type": "VAELoader",
              "inputs": {"vae_name": "ae.safetensors"}},
        "4": {"class_type": "LoadImage", "inputs": {"image": image}},
        "5": {"class_type": "FluxKontextImageScale",
              "inputs": {"image": ["4", 0]}},
        "6": {"class_type": "VAEEncode",
              "inputs": {"pixels": ["5", 0], "vae": ["3", 0]}},
        "7": {"class_type": "CLIPTextEncode",
              "inputs": {"text": PROMT, "clip": ["2", 0]}},
        "8": {"class_type": "ReferenceLatent",
              "inputs": {"conditioning": ["7", 0], "latent": ["6", 0]}},
        "9": {"class_type": "FluxGuidance",
              "inputs": {"conditioning": ["8", 0], "guidance": 2.5}},
        "10": {"class_type": "ConditioningZeroOut",
               "inputs": {"conditioning": ["7", 0]}},
        "11": {"class_type": "KSampler",
               "inputs": {"model": ["1", 0], "seed": seed, "steps": 24,
                          "cfg": 1.0, "sampler_name": "euler",
                          "scheduler": "simple", "positive": ["9", 0],
                          "negative": ["10", 0], "latent_image": ["6", 0],
                          "denoise": 1.0}},
        "12": {"class_type": "VAEDecode",
               "inputs": {"samples": ["11", 0], "vae": ["3", 0]}},
        "13": {"class_type": "SaveImage",
               "inputs": {"images": ["12", 0], "filename_prefix": prefix}},
    }


def main():
    image = m.stage(str(DZHERELO))
    m.free()
    for v, seed in SIDY.items():
        imia = "орк-жінка-v%d" % v
        done = m.run(graf(image, seed, "rasy2_" + imia))
        out = done["outputs"]["13"]["images"][-1]
        shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"],
                                 out["filename"]), r.VYKHID / (imia + ".png"))
        print("готово", imia, flush=True)
        r.zibraty()
        r.dzerkalo(imia)


if __name__ == "__main__":
    main()
