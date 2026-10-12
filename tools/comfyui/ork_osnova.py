#!/usr/bin/env python3
"""Основа орчихи під 3D (12.10.2026) — за правилами ельфійки.

Слово замовника: «згенеруй за тими ж правилами Орк, жінка — варіант 1,
але без зачіски — лиса голова»; «я бачу ти орчиху генеруєш не тією
моделлю» (перша проба — Kontext від `wiki/img/rasy/орк-жінка-v1.png`, а
це не той кадр: потрібен T-поза-рендер замовника,
`wiki/img/test/avatar/ork-tpoza-v1.png`).

Правила ельфійки (`spec/аватар-ельфійка-mixamo.md` §1, `elf_nabory_cn.py`):
FLUX dev + ControlNet Union-Pro 2.0 за скелетом OpenPose з силуету й
обличчя основи, обличчя — під маскою (лишається основи), решта з нуля:
топлес у чорних трусиках, босоніж, рівне сіре тло. Тут ще й лиса голова
(досвід ельфійки: довге волосся Pixal3D ліпить пластиною на спину).

Спідниця ховає промежину — мірки її не знаходять; висота промежини —
52,5% зросту від маківки (людська пропорція), коліна й ступні — з кадру.

    ~/Програми/cv-venv/bin/python -u tools/comfyui/ork_osnova.py [сід…]

Вихід — `wiki/img/test/avatar/ork-cn-topless-s<сід>.png` (лише диск);
скелет і маска — `ork-cn-poza.png`, `ork-cn-maska.png`.
"""
import os
import shutil
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import monster3d as m  # noqa: E402
import elf_nabory_cn as cn  # noqa: E402
import elf_markery as mk  # noqa: E402

D = cn.D
# `--кадр <файл у D>`: v2 — рендер замовника «ORC FEMALE - BARE T-POSE»
# (Firefly, босоніж, без наручів; слово: «референс орка — використай
# його»); імена виходу — від основи кадру.
OSNOVA = D / "ork-tpoza-v1.png"
if "--кадр" in sys.argv:
    _i = sys.argv.index("--кадр")
    OSNOVA = D / sys.argv[_i + 1]
    del sys.argv[_i:_i + 2]
PREF = "ork" if OSNOVA.stem == "ork-tpoza-v1" else "ork" + OSNOVA.stem.rsplit("v", 1)[-1]
SIDY = [int(a) for a in sys.argv[1:] if a.isdigit()] or [1203, 1204, 1205]
# Перша проба (s1201/1202) — «powerful … broad shoulders» дало гладку
# чоловічу фігуру: статура жіноча, як на кадрі замовника, — словами.
PROMT = (
    "Full body neutral studio reference photo of an adult orc woman, "
    "clearly female, standing in a strict T-pose, arms straight out to the "
    "sides, palms down, front view. She has a feminine athletic muscular "
    "physique like a female fitness athlete: natural female breasts, a "
    "narrow waist, wider feminine hips, toned muscular arms and thighs, "
    "defined abs, lean with low body fat. Topless with a bare chest, "
    "wearing only plain black briefs, barefoot with bare green feet. "
    "Olive-green skin, completely bald head with a clean smooth shaved "
    "green scalp and no hair at all, long pointed ears, stern female face. "
    "Plain light grey studio background, soft even lighting, photorealistic "
    "anatomy reference, the whole body from head to feet in frame.")

_mirky = mk.mirky


def mirky_z_promezhynoiu(shliakh):
    o = _mirky(shliakh)
    if o["промежина"] is None:
        msk = mk.sylyet(shliakh)
        ys = np.where(msk.sum(1) > 6)[0]
        o["промежина"] = float(ys.min() + 0.525 * (ys.max() - ys.min()))
        print("промежина за пропорцією: %.0f px" % o["промежина"], flush=True)
    return o


def main():
    mk.mirky = mirky_z_promezhynoiu
    cn.OSNOVA = OSNOVA
    T, rozmir, lm, ramka = cn.tochky_tila()
    im = Image.new("RGB", rozmir, (0, 0, 0))
    d = ImageDraw.Draw(im)
    for i, (a, b) in enumerate(cn.PARY):
        d.line((T[a], T[b]), fill=tuple(int(c * 0.6) for c in cn.KOLORY[i]), width=8)
    for i, p in T.items():
        d.ellipse((p[0] - 5, p[1] - 5, p[0] + 5, p[1] + 5), fill=cn.KOLORY[i])
    im.save(D / (PREF + "-cn-poza.png"))
    x0, x1, y0, y1 = ramka
    pts = np.array([(x0 + lm[i].x * (x1 - x0), y0 + lm[i].y * (y1 - y0))
                    for i in (10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288,
                              397, 365, 379, 378, 400, 377, 152, 148, 176, 149, 150, 136,
                              172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109)])
    c = pts.mean(0)
    # обличчя лишається, лоб і скроні — ні (волосся геть, лиса голова)
    pts = c + (pts - c) * 0.8
    mm = Image.new("L", rozmir, 255)
    ImageDraw.Draw(mm).polygon([tuple(p) for p in pts], fill=0)
    mm.save(D / (PREF + "-cn-maska.png"))
    print("скелет і маска готові", flush=True)
    if "--лише-поза" in sys.argv:
        return
    osn, msk, poz = (m.stage(str(D / f)) for f in
                     (OSNOVA.name, PREF + "-cn-maska.png", PREF + "-cn-poza.png"))
    m.free()
    for seed in SIDY:
        kudy = D / (PREF + "-cn-topless-s%d.png" % seed)
        if kudy.exists():
            print("є", kudy.name, flush=True)
            continue
        done = m.run(cn.graf(osn, msk, poz, PROMT, seed, "ork_cn_%d" % seed))
        out = done["outputs"]["13"]["images"][-1]
        shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"],
                                 out["filename"]), kudy)
        print("готово", kudy.name, flush=True)
    m.free()


if __name__ == "__main__":
    main()
