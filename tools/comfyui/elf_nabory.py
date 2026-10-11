#!/usr/bin/env python3
"""Ельфійка s811 у наборах E і D — картинки перед 3D (12.10.2026).

Слово замовника: «знайди всі речі E D рангу, які може вдягнути ельфійка …
наступним кроком потрібно вдягнути на ельфійку по черзі різні сети»; спосіб
— «спершу картинки». Kontext бере одну картинку, тож набір описано
словами за значками `game/assets/icons/items/` (аркуші
`art/meshy/2026-10-11/речі-{E,D}-ельфійка.png`). Без зброї в руках — інакше
ламається T-поза; прикраси надто дрібні для кадру всього тіла.

    ~/Програми/cv-venv/bin/python -u tools/comfyui/elf_nabory.py [ключ…]

Ключі: E-важкий E-легкий E-магічний D-важкий D-легкий D-магічний (типово
всі). Вихід — `wiki/img/test/avatar/el-dovha-nabir-<ключ>-s<сід>.png`.
"""
import os
import shutil
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster3d as m  # noqa: E402
import rasy_kontext as rk  # noqa: E402

KORIN = Path(__file__).resolve().parents[2]
D = KORIN / "wiki/img/test/avatar"
# Основа — висока тендітна (elf_dovha.py, слово замовника 12.10.2026:
# «ноги +18%, тонші»); перші проходи — від el-odyn-s811 (el-nabir-*).
DZHERELO = D / "el-dovha-chernetka.png"
SIDY = (77, 88)

NABORY = {
    "E-важкий": "a full set of slim fitted armour made of carved dark oak bark: a "
                "closed bark helmet with narrow eye slits covering her head, "
                "a carved bark breastplate cuirass with rounded shoulder "
                "guards, bark gauntlets with clawed fingertips, tall bark "
                "boots up to the knees, and a worn brown leather belt with a "
                "square buckle; plain dark undertunic and leggings beneath",
    "E-легкий": "a light set of simple brown leather: a brown leather hood "
                "over her head with her ears showing, a fitted brown leather "
                "jerkin with short sleeves and small shoulder pads, tan "
                "leather gloves, tan leather ankle boots, a worn brown "
                "leather belt with a square buckle, and brown leather "
                "leggings",
    "E-магічний": "a simple novice mage outfit of undyed cream linen: a thin "
                  "brown leather headband circlet on her forehead, a long "
                  "plain cream linen robe down to the ankles, cream linen "
                  "arm wraps from wrist to elbow, open cream linen sandals, "
                  "and a worn brown leather belt",
    "D-важкий": "a full set of slim fitted elven iron plate armour: a closed iron knight "
                "helmet with a visor covering her head, a polished iron "
                "plate cuirass with layered pauldrons and a dark red cloth "
                "tabard beneath, articulated iron gauntlets, iron greaves "
                "and sabatons, and a dark iron-studded belt",
    "D-легкий": "a light hunter set of wolf leather and grey wolf fur: a "
                "grey wolf-fur hood with small wolf ears over her head, a "
                "dark leather jacket with a thick wolf-fur collar, crossed "
                "leather straps and brown belts, dark leather gloves with "
                "fur cuffs, dark leather boots with fur tops and buckled "
                "straps, and dark leather trousers",
    "D-магічний": "an elegant mage outfit of fine linen: a dark silver "
                  "circlet with a glowing blue gem on her forehead, a long "
                  "flowing blue-grey linen mage robe with wide sleeves and "
                  "a dark red sash, cream bracers with small glowing blue "
                  "gems, and open cream linen sandals",
}


# Статура (слово замовника 12.10.2026: «ти знов генеруєш пропорції тіла як
# у низькорослої коренастої людини — я очікую статуру високої тендітної
# дівчини»): перший прохід (s11/s22) вдягав броню з об'ємом — плечі й стегна
# ширшали, ноги в обладунках товщали. Тепер силует названо незмінним, а
# броню — тонкою, по фігурі.
STATURA = (
    "The clothing is slim and form-fitting, tailored closely to her slender "
    "body, with no bulk and no padding. Her silhouette must stay exactly "
    "the same as in the photo: same height, same very long thin legs, same "
    "narrow shoulders, same tiny waist, same narrow hips, same thin arms. "
    "She is a tall, delicate, graceful young elf woman, about eight heads "
    "tall, not stocky, not muscular. Do not move any body landmark: the "
    "crotch, the hip line, the knees and the feet stay at exactly the same "
    "height in the frame as in the photo, the legs keep exactly the same "
    "length and thickness, only the surface is covered by clothing. ")


def promt(nabir):
    return (
        "Dress the same elf woman in " + nabir + ". The swimsuit is fully "
        "covered by the new clothing. " + STATURA + "Keep exactly the same "
        "elf woman: same "
        "face, same long pointed elf ears, same long straight silver-white "
        "hair, same pale skin, same tall slim long-legged figure, same "
        "strict T-pose with both arms straight out horizontally, empty "
        "hands, same front view, the whole body from head to feet in frame, "
        "same plain light grey studio background, same soft even lighting, "
        "same photorealistic style. Fantasy game character armour, "
        "realistic materials.")


def main():
    kluchi = [a for a in sys.argv[1:] if a in NABORY] or list(NABORY)
    image = m.stage(str(DZHERELO))
    m.free()
    for kl in kluchi:
        rk.PROMT = promt(NABORY[kl])
        for seed in SIDY:
            kudy = D / ("el-dovha-nabir-%s-s%d.png" % (kl, seed))
            if kudy.exists():
                print("є", kudy.name, flush=True)
                continue
            done = m.run(rk.graf(image, seed, "el_nabir_%d" % seed))
            out = done["outputs"]["13"]["images"][-1]
            shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"],
                                     out["filename"]), kudy)
            print("готово", kudy.name, flush=True)
    m.free()


if __name__ == "__main__":
    main()
