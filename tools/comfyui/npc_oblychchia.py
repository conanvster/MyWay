#!/usr/bin/env python3
"""Чисте обличчя NPC (28.11.2026, слово замовника: «спробуй накласти зображення облича чистіше для
усих»). На кадрі Т-0 аркуша голова — ~80 px, тож обличчя на моделі розмите. Тут: голова з Т-0
вирізається квадратом, збільшується до 1024 і Qwen-Edit 2511 відновлює її різкою — без зсуву рис
(перевірка: зсув відносно вирізу шукається перебором і виправляється). Вихід поруч з аркушем:
  art/npc/<ремесло>-<стать>/3d/обличчя.png   — 1024², відновлене
  art/npc/<ремесло>-<стать>/3d/обличчя.txt   — рамка вирізу в пікселях Т-0: x0 y0 x1 y1
Накладає його на модель `tools/blender/npc_oblychchia.py`.

    ~/Програми/cv-venv/bin/python -u tools/comfyui/npc_oblychchia.py коваль-чоловік [...] [--сід N]
"""
import os
import shutil
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
KORIN = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PROMT = ("Restore this blurry, low-resolution close-up into a sharp, high-detail photograph of exactly "
         "the same person with exactly the same framing. Keep the identity, face shape, eyes, nose, "
         "mouth, eyebrows, beard, skin tone, hair, headwear and collar exactly as they are, at exactly "
         "the same positions and size in the image; do not move, rotate, zoom, crop or re-pose "
         "anything. Strict front view, the same even soft studio lighting, the same plain grey "
         "background. Only add natural fine detail: crisp eyes and irises, eyelashes, natural skin "
         "texture, individual hair strands, fabric weave.")


def ramka_holovy(shliakh):
    a = np.asarray(Image.open(shliakh).convert("RGB")).astype(np.int16)
    tlo = np.median(np.concatenate([a[:6].reshape(-1, 3), a[:, :6].reshape(-1, 3),
                                    a[:, -6:].reshape(-1, 3)]), 0)
    maska = np.abs(a - tlo).sum(2) > 23
    ys, xs = np.nonzero(maska)
    y0, y1 = ys.min(), ys.max()
    H = y1 - y0
    smuha = maska[y0:y0 + int(0.08 * H)]
    cx = np.nonzero(smuha)[1].mean()
    S = 0.17 * H
    top = y0 - 0.015 * H
    return int(round(cx - S / 2)), int(round(top)), int(round(cx + S / 2)), int(round(top + S))


def zsuv(a, b, r=8):
    """Зсув b відносно a (сірі 128²) перебором ±r — найменша середня різниця."""
    naikr = (1e9, 0, 0)
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            aa = a[max(0, dy):128 + min(0, dy), max(0, dx):128 + min(0, dx)]
            bb = b[max(0, -dy):128 + min(0, -dy), max(0, -dx):128 + min(0, -dx)]
            d = np.abs(aa - bb).mean()
            if d < naikr[0]:
                naikr = (d, dx, dy)
    return naikr


def main():
    import monster3d as m  # noqa: E402
    import bronia_2var as b2  # noqa: E402
    A = sys.argv[1:]
    sid = 4242
    if "--сід" in A:
        i = A.index("--сід")
        sid = int(A[i + 1])
        del A[i:i + 2]
    for kl in A:
        t0 = os.path.join(KORIN, "art/npc", kl, "аркуш", "Т-0.png")
        d = os.path.join(KORIN, "art/npc", kl, "3d")
        os.makedirs(d, exist_ok=True)
        x0, y0, x1, y1 = ramka_holovy(t0)
        im = Image.open(t0).convert("RGB")
        vyriz = im.crop((x0, y0, x1, y1)).resize((1024, 1024), Image.LANCZOS)
        vhid = os.path.join(d, "обличчя-вхід.png")
        vyriz.save(vhid)
        g = b2.graf_qwen(m.stage(vhid), m.stage(vhid), PROMT, sid, "oblychchia")
        g["1"]["inputs"]["unet_name"] = "qwen-image-edit-2511-Q4_K_M.gguf"
        g["2"]["inputs"]["lora_name"] = "Qwen-Image-Edit-2511-Lightning-8steps-V1.0-bf16.safetensors"
        for n in ("9", "10"):
            g[n]["inputs"].pop("image2", None)
        g["7"]["inputs"]["resolution_steps"] = 1
        done = m.run(g)
        out = [o for v in done["outputs"].values() for o in v.get("images", [])][-1]
        syryi = os.path.join(d, "обличчя-сире.png")
        shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"], out["filename"]), syryi)
        nove = Image.open(syryi).convert("RGB").resize((1024, 1024), Image.LANCZOS)
        a = np.asarray(vyriz.convert("L").resize((128, 128))).astype(float)
        b = np.asarray(nove.convert("L").resize((128, 128))).astype(float)
        riz, dx, dy = zsuv(a, b)
        # виправити зсув (у 1024 — ×8): рисам бути там, де на Т-0
        if dx or dy:
            nove = Image.fromarray(np.roll(np.roll(np.asarray(nove), -dy * 8, 0), -dx * 8, 1))
        nove.save(os.path.join(d, "обличчя.png"))
        open(os.path.join(d, "обличчя.txt"), "w").write("%d %d %d %d\n" % (x0, y0, x1, y1))
        znak = "‼" if riz > 18 or max(abs(dx), abs(dy)) > 5 else "✓"
        print("%s %s: виріз %d,%d–%d,%d, зсув Qwen %+d %+d (×8 px), різниця %.1f" %
              (znak, kl, x0, y0, x1, y1, dx, dy, riz), flush=True)
    m.free()


if __name__ == "__main__":
    main()
