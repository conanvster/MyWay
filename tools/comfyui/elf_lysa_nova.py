#!/usr/bin/env python3
"""Ельфійка заново: лиса, пропорції — скелетом основи (13.10.2026).

Слово замовника: «зроби ельфійку заново, вади тільки накоплюються. зроби
рендер по новій, з правильній пропорції, без волосся». Кадри s808/k1811
несли сліди правок (кисті пересаджено, волосся перемальовано, обличчя
вклеєно) — тут кадр з нуля: FLUX dev, шум 1,0 на весь кадр, ControlNet
Union-Pro 2.0 за скелетом `el-cn-poza.png` (з `el-dovha-chernetka.png` —
погоджена висока тендітна статура: ноги +18%, вузький таз). Голова лиса —
волосся не буде ні в скані, ні під перуками.

    ~/Програми/cv-venv/bin/python -u tools/comfyui/elf_lysa_nova.py [сід…]

Вихід — `wiki/img/test/avatar/el-lysa-s<сід>.png`; лінії пропорцій проти
основи — `tools/elf_markery.py аркуш`.
"""
import os
import shutil
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import monster3d as m  # noqa: E402
import elf_nabory_cn as cn  # noqa: E402

D = cn.D
OSNOVA = D / "el-dovha-chernetka.png"
POZA = "el-cn-poza.png"
SIDY = [int(a) for a in sys.argv[1:] if a.isdigit()] or [1904, 1905, 1906]
# Сила й тривалість скелета: 0,85 до 65% кроків (як у наборах) опускали
# промежину на 10–30 px проти основи (проба s1901–1903) — тут сильніше.
cn.SYLA, cn.KINETS = 1.0, 0.9
PROMT = (
    "Full body neutral studio reference photo of a tall, slender adult elf "
    "woman standing in a strict T-pose, arms straight out to the sides at "
    "shoulder height, front view. Completely bald head: a clean smooth "
    "shaved pale scalp with no hair at all, the round shape of her skull "
    "visible, thin natural eyebrows, long pointed elf ears. "
    "Open hands with palms facing down, all five fingers straight and "
    "slightly spread apart, thumbs visible. Topless with a bare chest, "
    "wearing only plain black briefs, barefoot, feet slightly apart. Pale "
    "smooth skin, delicate face, calm neutral expression, very long slim "
    "legs with a high crotch, narrow hips, tiny waist, narrow shoulders, thin arms. Plain "
    "light grey studio background, soft even lighting, photorealistic "
    "anatomy reference, the whole body from head to feet in frame.")


def main():
    vsia = Image.new("L", Image.open(OSNOVA).size, 255)
    vsia.save(D / "el-lysa-vsia-maska.png")
    osn, msk, poz = (m.stage(str(D / f)) for f in
                     (OSNOVA.name, "el-lysa-vsia-maska.png", POZA))
    m.free()
    for seed in SIDY:
        kudy = D / ("el-lysa-s%d.png" % seed)
        done = m.run(cn.graf(osn, msk, poz, PROMT, seed, "el_lysa_%d" % seed))
        out = done["outputs"]["13"]["images"][-1]
        shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"],
                                 out["filename"]), kudy)
        print("готово", kudy.name, flush=True)
    m.free()


if __name__ == "__main__":
    main()
