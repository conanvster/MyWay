#!/usr/bin/env python3
"""Текстури кори й нутра для дерев-велетів нових порід (13.11.2026).

Баобаб має кору з фото замовника (`game/assets/baobab/`). Для ялівця й секвої фото
замалі (стовбур — сотня пікселів), тож кора й деревина нутра — FLUX.1 dev текстом,
кадр 1152², краї зшиті перехресним переходом у безшовну плитку 1024².

    ~/Програми/cv-venv/bin/python -u tools/comfyui/dereva_tekstury.py [назва ...]

Плитки → game/assets/dereva/<назва>.jpg. Готові не перемальовуються.
"""
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster3d as m  # noqa: E402
import dereva_ref as d  # noqa: E402

KUDY = os.path.join(m.ROOT, "game", "assets", "dereva")
HVIST = (" Flat front-on macro photograph, the surface fills the whole frame edge to edge, "
         "even diffuse overcast light, no shadows, no sky, no background, no text.")
PLYTKY = {
    "sekvoia-kora": (
        "Close-up of giant sequoia bark: thick soft fibrous cinnamon red-brown bark with "
        "deep vertical furrows and long stringy ridges.", 3101),
    "sekvoia-nutro": (
        "Uniform surface of dark red-brown sequoia heartwood split along the grain: long "
        "straight parallel vertical fibres from top to bottom, a few black charred "
        "streaks, the same all over, no rings, no knots, no centre.", 3112),
    "yalivets-kora": (
        "Close-up of an ancient juniper trunk: weathered bare deadwood with flowing twisted "
        "vertical grain, silver-grey with honey-gold and rust streaks, fine cracks, strips "
        "of shredded grey bark.", 3103),
    "yalivets-nutro": (
        "Uniform surface of old dry silver-grey weathered wood split along the grain: "
        "long gently wavy parallel vertical fibres from top to bottom with fine cracks "
        "and pale honey streaks, the same all over, no rings, no knots, no centre.", 3114),
}
SMUHA = 128


def plytka(path_in, path_out):
    a = np.asarray(Image.open(path_in).convert("RGB"), dtype=np.float32)
    n = a.shape[0] - SMUHA
    t = (np.arange(SMUHA, dtype=np.float32) / SMUHA)
    b = a[:, :n].copy()
    b[:, :SMUHA] = a[:, :SMUHA] * t[None, :, None] + a[:, n:] * (1 - t)[None, :, None]
    c = b[:n].copy()
    c[:SMUHA] = b[:SMUHA] * t[:, None, None] + b[n:] * (1 - t)[:, None, None]
    Image.fromarray(c.clip(0, 255).astype(np.uint8)).save(path_out, quality=92)


def main():
    os.makedirs(KUDY, exist_ok=True)
    pidkladka = m.stage(os.path.join(d.FOTO, d.NUTRO))
    for nazva, (opys, sid) in PLYTKY.items():
        if len(sys.argv) > 1 and nazva not in sys.argv[1:]:
            continue
        kudy = os.path.join(KUDY, nazva + ".jpg")
        if os.path.exists(kudy):
            print("є", kudy, flush=True)
            continue
        syre = os.path.join(m.COMFY, "output", "dereva_tekstura_%s.png" % nazva)
        d.kadr(pidkladka, opys + HVIST, sid, 1.0, (1024 + SMUHA, 1024 + SMUHA), syre)
        plytka(syre, kudy)
        print("плитка", kudy, flush=True)


if __name__ == "__main__":
    main()
