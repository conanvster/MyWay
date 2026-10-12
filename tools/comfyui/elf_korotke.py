#!/usr/bin/env python3
"""Основа ельфійки з коротким волоссям (12.10.2026) — під 3D і зачіски.

Слово замовника: «Волосся здається не покриває всю голову, та є залишки
від контуру волосся — тож можливо краще генерувати голову лисою чи з
коротким волоссям». Довге волосся кадру s808 Pixal3D ліпив пластиною
на спину, а шкіри під нею не бачив (темна латка на спині після
відрізання); пасма вздовж шиї лишались намальованими на шиї.

Тут FLUX dev перемальовує лише волосся (маска — колірність Lab < 9 над
плечима в межах голови й шиї, без обличчя й вух) + ControlNet за тим самим
скелетом, що й набори; тіло й обличчя — пікселі основи (зшивка м'якою
маскою після декодування).

    ~/Програми/cv-venv/bin/python -u tools/comfyui/elf_korotke.py [сід…]

Вихід — `wiki/img/test/avatar/el-korotke-s<сід>.png` (+ `-maska-inp.png`).
"""
import os
import shutil
import sys

import cv2
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import monster3d as m  # noqa: E402
import elf_nabory_cn as cn  # noqa: E402

D = cn.D
OSNOVA = D / "el-cn-nabir-топлес-s808.png"
TOCHKY_4K = D / "el-cn-nabir-топлес-s808-4k-tochky.npy"
SIDY = [int(a) for a in sys.argv[1:] if a.isdigit()] or [901, 902, 903]
OVAL = [10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379,
        378, 400, 377, 152, 148, 176, 149, 150, 136, 172, 58, 132, 93, 234, 127,
        162, 21, 54, 103, 67, 109]
PROMT = (
    "Full body neutral studio reference photo of a tall, slender adult elf "
    "woman standing in a strict T-pose, arms straight out to the sides, "
    "front view, topless, wearing only plain black briefs. Very short "
    "close-cropped silver-white hair, a neat buzz cut tight to the scalp, "
    "the round shape of her skull clearly visible, bare neck and bare "
    "shoulders with no hair on them, long pointed elf ears fully visible, "
    "pale skin, delicate face, calm neutral expression. Plain light grey "
    "studio background, soft even lighting, photorealistic anatomy "
    "reference.")


def maska_volossia():
    im = np.array(Image.open(OSNOVA).convert("RGB"))
    h, w = im.shape[:2]
    F = np.load(TOCHKY_4K) * (w / 4096.0)
    lab = cv2.cvtColor(im, cv2.COLOR_RGB2LAB).astype(np.float32)
    nenas = np.hypot(lab[..., 1] - 128, lab[..., 2] - 128) < 9.0
    vys_ob = F[152, 1] - F[10, 1]
    cx = F[1, 0]
    yy, xx = np.mgrid[0:h, 0:w]
    # голова й шия до плечей: від маківки (з запасом) до 1,15 обличчя нижче
    # підборіддя; ширина — 0,85 висоти обличчя від осі
    korobka = (yy > F[10, 1] - vys_ob * 0.45) & (yy < F[152, 1] + vys_ob * 1.15) \
        & (np.abs(xx - cx) < vys_ob * 0.85)
    oval = np.zeros((h, w), np.uint8)
    cv2.fillPoly(oval, [np.round(F[OVAL]).astype(np.int32)], 1)
    # обличчя трохи звужене: лінія росту волосся теж перемальовується
    c = F[OVAL].mean(0)
    vuz = np.zeros((h, w), np.uint8)
    cv2.fillPoly(vuz, [np.round(c + (F[OVAL] - c) * 0.93).astype(np.int32)], 1)
    # шия (між щелепою й плечима) — лишається: шкіра, колірність висока
    vol = (nenas & korobka & (vuz == 0)).astype(np.uint8)
    # тло всередині коробки поруч із волоссям — теж (коротке волосся
    # відкриє тло там, де були пасма)
    vol = cv2.morphologyEx(vol, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    vol = cv2.dilate(vol, np.ones((3, 3), np.uint8), iterations=3)
    vol[vuz > 0] = 0
    # лише одна область — голова з шиєю (бліді груди під шиєю за
    # колірністю теж «сиві»: пляма на грудях у першій пробі)
    n, mit, st, _ = cv2.connectedComponentsWithStats(vol)
    if n > 2:
        vol = (mit == 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))).astype(np.uint8)
    Image.fromarray(vol * 255).save(D / "el-korotke-maska-inp.png")
    return vol


def main():
    vol = maska_volossia()
    print("маска: %d px" % vol.sum(), flush=True)
    osn, msk, poz = (m.stage(str(D / f)) for f in
                     (OSNOVA.name, "el-korotke-maska-inp.png", "el-cn-poza.png"))
    m.free()
    m_soft = cv2.GaussianBlur(vol.astype(np.float32), (0, 0), 2.0)[..., None]
    orig = np.array(Image.open(OSNOVA).convert("RGB")).astype(np.float32)
    for seed in SIDY:
        kudy = D / ("el-korotke-s%d.png" % seed)
        if kudy.exists():
            print("є", kudy.name, flush=True)
            continue
        done = m.run(cn.graf(osn, msk, poz, PROMT, seed, "el_korotke_%d" % seed))
        out = done["outputs"]["13"]["images"][-1]
        src = os.path.join(m.COMFY, "output", out["subfolder"], out["filename"])
        nove = np.array(Image.open(src).convert("RGB")).astype(np.float32)
        zsh = orig * (1 - m_soft) + nove * m_soft
        Image.fromarray(zsh.clip(0, 255).astype(np.uint8)).save(kudy)
        print("готово", kudy.name, flush=True)
    m.free()


if __name__ == "__main__":
    main()
