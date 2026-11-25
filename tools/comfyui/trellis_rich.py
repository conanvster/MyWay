#!/usr/bin/env python3
"""Річ окремо → сітка з PBR-текстурою (25.11.2026, П-289). Той самий граф, що й Pixal3D
(`pixal3d.api.json`), з перемикачем на TRELLIS.2 (вузол 316) — річ без тіла, кадр прямо.

    ~/Програми/cv-venv/bin/python -u tools/comfyui/trellis_rich.py <кадр.png> <вихід.glb> \
        [--граней 150000] [--pixal] [--сід 42]
"""
import json
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster3d as m  # noqa: E402


def arg(k, typ, d):
    return typ(sys.argv[sys.argv.index(k) + 1]) if k in sys.argv else d


def main():
    kadr, vyhid = sys.argv[1], os.path.abspath(sys.argv[2])
    g = json.load(open(os.path.join(m.HERE, "pixal3d.api.json")))
    g["122"]["inputs"]["image"] = m.stage(kadr)
    g["186"]["inputs"]["target_face_count"] = arg("--граней", int, 150000)
    g["316"]["inputs"]["value"] = "--pixal" not in sys.argv
    sd = arg("--сід", int, 42)
    for n in ("18", "23"):
        g[n]["inputs"]["seed"] = sd
    nazva = os.path.splitext(os.path.basename(vyhid))[0]
    g["900"]["inputs"]["filename_prefix"] = "3d/rich_%s_textured" % nazva
    g["901"]["inputs"]["filename_prefix"] = "3d/rich_%s_vertexcolor" % nazva
    m.free()
    done = m.run(g)
    out = done["outputs"]["900"]["3d"][0]
    shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"], out["filename"]), vyhid)
    print("готово", vyhid, flush=True)
    m.free()


if __name__ == "__main__":
    main()
