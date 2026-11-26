#!/usr/bin/env python3
"""Проба 26.11.2026, варіант 1: повороти аркуша (45/90/180) поточною Qwen-Edit 2511 + Lightning
+ LoRA «Multiple Angles» (fal, сила 0,9), одна картинка — готовий 0° цього ж виду, промт лише
`<sks> <ракурс> eye-level shot wide shot` (так у pilot2_ork.py; довгий текст знижує влучання).
Порівняння з основним прогоном (2511 без LoRA, манекен другою картинкою), де 45°/90° часто
лишались анфас.
    ~/Програми/cv-venv/bin/python -u tools/comfyui/proby/kuty_lora.py драконід-воїн наг вампір
→ art/monsters/_аркуш-каркас/проба-моделей/v1-2511-кути/<вид>/<поза>-<кут>.png
"""
import os
import sys

TUT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(TUT))
import monstr_arkush as ma  # noqa: E402
import monster3d as m  # noqa: E402
import bronia_2var as b2  # noqa: E402

KUTY = {45: "front-right quarter view", 90: "right side view", 180: "back view"}
VYKHID = os.path.join(ma.KARKAS, "проба-моделей", "v1-2511-кути")

for vyd in sys.argv[1:]:
    for poza in "АТ":
        osnova = os.path.join(ma.teka(vyd), "%s-0.png" % poza)
        for kut, slova in KUTY.items():
            kudy = os.path.join(VYKHID, vyd, "%s-%d.png" % (poza, kut))
            if os.path.exists(kudy):
                continue
            os.makedirs(os.path.dirname(kudy), exist_ok=True)
            g = b2.graf_qwen(m.stage(osnova), m.stage(osnova),
                             "<sks> %s eye-level shot wide shot" % slova, ma.SID, "proba_kuty")
            g["1"]["inputs"]["unet_name"] = "qwen-image-edit-2511-Q4_K_M.gguf"
            g["2"]["inputs"]["lora_name"] = "Qwen-Image-Edit-2511-Lightning-8steps-V1.0-bf16.safetensors"
            for n in ("9", "10"):
                g[n]["inputs"].pop("image2", None)
            g["7"]["inputs"]["resolution_steps"] = 1
            g["20"] = {"class_type": "LoraLoaderModelOnly",
                       "inputs": {"model": ["2", 0], "strength_model": 0.9,
                                  "lora_name": "qwen-image-edit-2511-multiple-angles-lora.safetensors"}}
            g["3"]["inputs"]["model"] = ["20", 0]
            done = m.run(g)
            out = [o for v in done["outputs"].values() for o in v.get("images", [])][-1]
            syryi = os.path.join(os.path.dirname(kudy), "сирі", os.path.basename(kudy))
            os.makedirs(os.path.dirname(syryi), exist_ok=True)
            import shutil
            shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"], out["filename"]), syryi)
            ma.chyste_tlo(m, syryi, kudy)
            print("готово", vyd, poza, kut, flush=True)
m.free()
