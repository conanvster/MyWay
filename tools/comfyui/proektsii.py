#!/usr/bin/env python3
"""Референс раси у трьох проекціях, реалістично (13.10.2026).

Слово замовника, обравши на аркуші орка-чоловіка (`rasy_realizm.py`):
«flux-i2i — найкращий, flux-cn — другий за якістю. Зроби в тому ж ключі
[орчиха Firefly] з 3 проекцій». Бокового й заднього виду в референсі немає:
спершу Kontext розвертає ту саму постать (вид збоку, вид ззаду), далі кожна
проекція — однаково flux-i2i і flux-cn (`rasy_realizm.graf_flux`), ті самі
сіди й опис.

    ~/Програми/cv-venv/bin/python -u tools/comfyui/proektsii.py [профіль]

Вихід — `art/meshy/2026-10-13/орчиха-3-проекції/<проекція>-<модель>-s<сід>.png`
і `аркуш.png` (рядок на проекцію: джерело, i2i ×2, cn ×2).
"""
import os
import shutil
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster3d as m  # noqa: E402
import rasy_realizm as rr  # noqa: E402

KORIN = rr.KORIN
# Профілі: референс, тека, опис; `nul` — нульовий крок Kontext (референс
# не в Т-позі: спершу постать спереду в Т-позі на рівному тлі).
PROFILI = {
    "орчиха": dict(ref="art/references/ork/ork-zhinka-ref.png",
                   vyhid="art/meshy/2026-10-13/орчиха-3-проекції", nul=None),
    # орк-жінка-v3 з вікі рас («зроби так само з [v3] топлес», 14.10.2026)
    "орчиха-v3": dict(
        ref="art/references/ork/ork-zhinka-v3-ref.png",
        vyhid="art/meshy/2026-10-14/орчиха-v3-3-проекції",
        nul=("Show the exact same orc woman (same face, same black braided hair, "
             "same skin colour, same strong build) standing alone in a strict "
             "T-pose with both arms straight out horizontally to the sides, full "
             "body front view on a plain light grey studio background. Remove the "
             "cape, the shoulder pauldrons, the chest armour bra, the bracers and "
             "the boots: she is topless and barefoot. Keep only her leather belt "
             "with the round buckle and the long leather tasset over plain dark "
             "briefs. Whole body from head to feet."),
        opys=("A tall strong muscular adult female orc with olive-green skin, "
              "long pointed ears, black braided hair tied back, a stern face, "
              "topless, a dark leather belt with a round embossed buckle and a "
              "long pointed leather tasset over dark briefs, barefoot, standing "
              "in a strict T-pose with arms straight out to the sides. ")),
}
PROFIL = next((a for a in sys.argv[1:] if a in PROFILI), "орчиха")
REF = KORIN / PROFILI[PROFIL]["ref"]
VYHID = KORIN / PROFILI[PROFIL]["vyhid"]
SIDY = (6101, 6102)
OPYS = ("A tall strong muscular adult female orc with olive-green skin, long "
        "pointed ears, long straight black hair, a stern face with small lower "
        "tusks, topless, a double brown leather belt with a round bronze stud "
        "and a leather pouch, a ragged dark cloth loincloth skirt, barefoot, "
        "standing in a strict T-pose with arms straight out to the sides. ")
OPYS = PROFILI[PROFIL].get("opys", OPYS)
REAL = ("Photorealistic photo, a real actor in highly realistic orc prosthetic "
        "makeup, natural skin with pores, veins and fine scars, muted olive "
        "skin tone, realistic anatomy, real worn leather and cloth, soft even "
        "studio light, plain grey studio backdrop, full body from head to feet. "
        "Not a cartoon, not a 3D render, not a game model.")
VYDY = {
    "спереду": ("front view", None),
    "збоку": ("side view in profile, facing left",
              "Show the exact same orc woman from the side: a full body side "
              "profile view facing left, same strict T-pose: her arms stay "
              "straight out to her sides, so from the side one arm points "
              "straight toward the camera and the other straight away and both "
              "look very short, NOT reaching forward. Same body, hair, belt and "
              "everything at the hips, same proportions. Plain grey studio "
              "background, whole body from head to feet."),
    "ззаду": ("back view from behind",
              "Show the exact same orc woman from behind: a full body back "
              "view, same strict T-pose with arms straight out to the sides, "
              "her same hair seen from behind, same belt and everything at the "
              "hips seen from behind, same proportions. Plain grey studio background, "
              "whole body from head to feet."),
}


def zberehty(done, kudy):
    out = done["outputs"]["13"]["images"][-1]
    shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"], out["filename"]), kudy)
    print("готово", kudy.name, flush=True)


def arkush():
    s = 400
    kol = 1 + 2 * len(SIDY)
    o = Image.new("RGB", (s * kol, len(VYDY) * (s + 34)), (24, 24, 24))
    d = ImageDraw.Draw(o)
    try:
        sh = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 18)
    except OSError:
        sh = ImageFont.load_default()
    for r, vyd in enumerate(VYDY):
        kadry = [("%s — джерело" % vyd, VYHID / ("%s-dzherelo.png" % vyd))] + [
            ("%s s%d" % (mo, sd), VYHID / ("%s-%s-s%d.png" % (vyd, mo, sd)))
            for mo in ("flux-i2i", "flux-cn") for sd in SIDY]
        y = r * (s + 34)
        for i, (pidpys, f) in enumerate(kadry):
            if f.exists():
                im = Image.open(f).convert("RGB")
                im.thumbnail((s, s))
                o.paste(im, (i * s + (s - im.width) // 2, y))
            d.text((i * s + 8, y + s + 6), pidpys, fill=(230, 220, 200), font=sh)
    o.save(VYHID / "аркуш.png")
    print("аркуш", VYHID / "аркуш.png", flush=True)


def main():
    VYHID.mkdir(parents=True, exist_ok=True)
    m.free()
    nul = PROFILI[PROFIL]["nul"]
    pered = VYHID / "спереду-dzherelo.png"
    if nul is None:
        shutil.copy(REF, pered)
    elif not pered.exists():
        g = rr.graf_kontext(m.stage(str(REF)), SIDY[0])
        g["7"]["inputs"]["text"] = nul
        zberehty(m.run(g), pered)
    # розвороти — від постаті спереду в Т-позі
    ref = m.stage(str(pered))
    # 1. Kontext — бокова й задня проекції
    for vyd, (_, kontext) in VYDY.items():
        kudy = VYHID / ("%s-dzherelo.png" % vyd)
        if kontext and not kudy.exists():
            g = rr.graf_kontext(ref, SIDY[0])
            g["7"]["inputs"]["text"] = kontext
            zberehty(m.run(g), kudy)
    m.free()
    # 2. FLUX i2i і cn — кожна проекція однаково
    for vyd, (slova, _) in VYDY.items():
        dzh = m.stage(str(VYHID / ("%s-dzherelo.png" % vyd)))
        promt = OPYS + slova + ". " + REAL
        for sd in SIDY:
            for mo, i2i in (("flux-i2i", True), ("flux-cn", False)):
                kudy = VYHID / ("%s-%s-s%d.png" % (vyd, mo, sd))
                if not kudy.exists():
                    zberehty(m.run(rr.graf_flux(dzh, promt, sd, i2i)), kudy)
    m.free()
    arkush()


if __name__ == "__main__":
    main()
