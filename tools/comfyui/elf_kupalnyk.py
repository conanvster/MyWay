#!/usr/bin/env python3
"""Ельфійка в купальнику (11.10.2026) — референс під 3D.

Слово замовника: «зроби за допомогою інших інструментів вигляд у купальнику
для Ельф, жінка — варіант 1» (П-256). Шлях той самий, що для людини-жінки
(`avatar_ref.py --жінка`, `--купальник`): Kontext двома кроками — спершу
T-поза на сірому тлі в тому ж одязі, тоді одяг → чорний роздільний
купальник. Промпти людини, до яких дописано гострі вуха й довге
сріблясто-біле волосся — без них Kontext «олюднює» ельфа.

    ~/Програми/cv-venv/bin/python -u tools/comfyui/elf_kupalnyk.py [--купальник]

Без ключа — T-пози; `--купальник [--з <файл>]` — купальник від T-пози
(типово el-tpoza-s11.png). Вихід — `wiki/img/test/avatar/el-*.png`
(лише диск, як усі кадри аватарів). Готовий кадр не перегенеровується.
"""
import os
import shutil
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster3d as m  # noqa: E402
import rasy_kontext as rk  # noqa: E402

KORIN = Path(__file__).resolve().parents[2]
DZHERELO = KORIN / "wiki/img/rasy/ельф-жінка-v1.png"
VYKHID = KORIN / "wiki/img/test/avatar"

ELF = ("Keep exactly the same elf woman: same face, same long pointed elf "
       "ears, same long straight silver-white hair, same pale skin")

TPOZA_SIDY = (11, 22, 33, 44)
TPOZA = (
    "Change only the pose, the view and the background. The same elf woman "
    "now stands in a strict T-pose facing the camera directly: both arms "
    "stretched straight out to the sides horizontally at shoulder height, "
    "palms facing down, fingers together, legs straight and slightly "
    "apart, feet flat on the ground, head level looking straight forward, "
    "front orthographic view, the whole body from head to feet in frame "
    "with margin around it. Remove anything held in her hands or hanging "
    "from her belt. Replace the forest with a plain uniform light grey "
    "studio background, soft even shadowless lighting. " + ELF + ", same "
    "clothing (linen shirt, brown leather vest, belts, dark trousers, "
    "leather boots), same colours, same photorealistic style.")

KUPALNYK_SIDY = (611, 622, 633)
KUPALNYK = (
    "Replace all of her clothing (shirt, vest, belts, trousers and boots) "
    "with a simple black two-piece swimsuit: a black underwire bikini top "
    "with thin shoulder straps and smooth moulded cups, and black high-cut "
    "bikini briefs with the leg openings cut high up to her hip bones; she "
    "is barefoot. Show her bare shoulders, bare arms, bare midriff, bare "
    "thighs, bare legs and bare feet with natural realistic skin. " + ELF +
    ", same natural slender feminine figure and body proportions, same "
    "strict T-pose with both arms straight out horizontally, same front "
    "view, same plain light grey studio background, same soft even "
    "lighting, same photorealistic style.")


def kroky(prompt, dzherelo, sidy, nazva):
    rk.PROMT = prompt
    image = m.stage(str(dzherelo))
    for seed in sidy:
        kudy = VYKHID / (nazva % seed)
        if kudy.exists():
            print("є", kudy.name, flush=True)
            continue
        done = m.run(rk.graf(image, seed, "elf_" + (nazva % seed)[:-4]))
        out = done["outputs"]["13"]["images"][-1]
        shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"],
                                 out["filename"]), kudy)
        print("готово", kudy.name, flush=True)


def main():
    m.free()
    if "--купальник" in sys.argv:
        z = VYKHID / (sys.argv[sys.argv.index("--з") + 1]
                      if "--з" in sys.argv else "el-tpoza-s11.png")
        kroky(KUPALNYK, z, KUPALNYK_SIDY,
              "el-kupalnyk-" + z.stem.split("-")[-1] + "-s%d.png")
        return
    kroky(TPOZA, DZHERELO, TPOZA_SIDY, "el-tpoza-s%d.png")


if __name__ == "__main__":
    main()
