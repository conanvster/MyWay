#!/usr/bin/env python3
"""Пілот 2 орка (09.11.2026): детальна 3D-сітка з референсу локально —
TRELLIS.2 і Pixal3D тим самим графом (`pixal3d.api.json`, вузол 316 —
перемикач). Далі сітка запікається на основу MPFB (`tools/blender/zapikannia.py`).

    ~/Програми/cv-venv/bin/python -u tools/comfyui/ork_pilot_3d.py <референс.png> <тека> [trellis|pixal ...]
"""
import json
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster3d as m  # noqa: E402

ref, teka = sys.argv[1], sys.argv[2]
os.makedirs(teka, exist_ok=True)
# --текстура N: розмір текстури скульпту (типово 4096). Густий скульпт (торс із наплічниками)
# на 16 ГіБ падає на запіканні 4096 з нестачею пам'яті — тоді 3072 чи 2048.
TEKSTURA = int(sys.argv[sys.argv.index("--текстура") + 1]) if "--текстура" in sys.argv else 0
modeli = [a for a in sys.argv[3:] if a in ("trellis", "pixal")]
for model in modeli or ["trellis", "pixal"]:
    g = json.load(open(os.path.join(m.HERE, "pixal3d.api.json")))
    g["122"]["inputs"]["image"] = m.stage(ref)
    g["316"]["inputs"]["value"] = model == "trellis"
    g["186"]["inputs"]["target_face_count"] = 400000
    if TEKSTURA:
        g["288"]["inputs"]["value"] = TEKSTURA
    # --ремеш N (типово 768), --форма N (типово 1536): густий скульпт (торс із наплічниками й
    # хутром) на 16 ГіБ падає на запіканні текстури — дерево трикутників опорної сітки не влазить
    if "--ремеш" in sys.argv:
        g["241"]["inputs"]["resolution"] = int(sys.argv[sys.argv.index("--ремеш") + 1])
    if "--форма" in sys.argv:
        g["94"]["inputs"]["target_resolution"] = sys.argv[sys.argv.index("--форма") + 1]
    g["900"]["inputs"]["filename_prefix"] = "3d/ork_pilot_%s" % model
    g["901"]["inputs"]["filename_prefix"] = "3d/ork_pilot_%s_vc" % model
    m.free()
    done = m.run(g)
    out = done["outputs"]["900"]["3d"][-1]
    shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"], out["filename"]),
                os.path.join(teka, model + ".glb"))
    print("готово", model, flush=True)
m.free()
