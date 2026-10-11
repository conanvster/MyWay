#!/usr/bin/env python3
"""Висока тендітна основа ельфійки (12.10.2026).

Слово замовника: «ти знов генеруєш пропорції тіла як у низькорослої
коренастої людини — хоча я очікую статуру високої тендітної дівчини»;
з чотирьох чернеток обрано «ноги +18%, тонші». У el-odyn-s811 ноги
(промежина → підлога) — 48% зросту, звичайна статура; Kontext переносить
її в кожен набір. Тож основу правлено геометрично, без нейромережі, а
Kontext лише прибирає шви:

  1. нижче промежини кадр розтягнуто по висоті ×`NOGY`, ноги стиснуто
     до осі фігури ×`TONSHI`, тло — однотонне з кута кадру;
  2. усе вписано назад у 1024² → `el-dovha-chernetka.png`;
  3. Kontext «прибери шви, пропорції ті самі» → `el-dovha-s<сід>.png`
     (ширшає таз — тому основа для наборів — сама чернетка, а Kontext
     лише з `--kontext`).

    ~/Програми/cv-venv/bin/python -u tools/comfyui/elf_dovha.py
"""
import os
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster3d as m  # noqa: E402
import rasy_kontext as rk  # noqa: E402

KORIN = Path(__file__).resolve().parents[2]
D = KORIN / "wiki/img/test/avatar"
NOGY = 1.18
TONSHI = 0.94
PEREKHID = 120   # пікселів над промежиною, де звуження наростає
SIDY = (911, 922, 933)
PROMT = (
    "Clean up this photo: remove any seams, stretching artifacts and "
    "uneven background, make the plain light grey studio background "
    "uniform, make the skin, knees and feet look natural and smooth. Keep "
    "exactly the same elf woman with exactly the same body proportions: "
    "same height, same very long slender legs, same narrow hips, same "
    "thin thighs, same tiny waist, same narrow shoulders, same face, same "
    "long pointed elf ears, same long straight silver-white hair, same "
    "black bikini, same strict T-pose with both arms straight out, bare "
    "feet, same front view, the whole body in frame, same soft even "
    "lighting, same photorealistic style.")


def runs(r):
    d = np.diff(np.concatenate([[0], r.astype(int), [0]]))
    return int((d == 1).sum())


def chernetka():
    im = Image.open(D / "el-odyn-s811.png").convert("RGB")
    a = np.asarray(im).astype(float)
    mask = np.asarray(Image.open(D / "el-odyn-s811-maska.png")
                      .convert("L")) > 127
    w, h = im.size
    ys = np.where(mask.any(1))[0]
    top, bot = ys.min(), ys.max()
    # промежина — найнижчий рядок, де ноги ще одна смуга
    krok = next(y for y in range(bot - 5, top + 300, -1)
                if runs(mask[y]) == 1)
    cx = float(np.where(mask[krok:bot].any(0))[0].mean())
    z0 = krok - PEREKHID          # звідки починає вужчати (талія)

    # 1. Тло без фігури нижче талії: рядок під розширеною маскою — лінійно
    # між тлом ліворуч і праворуч (інакше крізь тонші ноги видно старі).
    shyr = np.asarray(Image.fromarray(mask.astype(np.uint8) * 255)
                      .filter(ImageFilter.MaxFilter(15))) > 0
    tlo = a.copy()
    xs = np.arange(w)
    for y in range(z0, h):
        ok = ~shyr[y]
        if ok.sum() > 2 and (~ok).any():
            for c in range(3):
                tlo[y, ~ok, c] = np.interp(xs[~ok], xs[ok], tlo[y, ok, c])

    # 2. Вертикаль: рядок нового кадру → рядок старого (нижче промежини
    # розтягнуто ×NOGY).
    vys = krok + int((h - krok) * NOGY)
    src_y = np.where(np.arange(vys) < krok, np.arange(vys),
                     krok + (np.arange(vys) - krok) / NOGY)
    src_y = np.clip(src_y, 0, h - 1)

    # 3. Горизонталь: від талії до верху стегна ширина плавно ×1 → ×TONSHI.
    nove = np.empty((vys, w, 3))
    for y in range(vys):
        sy = src_y[y]
        k = 1.0 if y < z0 else 1.0 - (1.0 - TONSHI) * min(
            1.0, (y - z0) / float(PEREKHID + 40))
        sx = np.clip(cx + (xs - cx) / k, 0, w - 1)
        y0 = int(sy)
        y1 = min(h - 1, y0 + 1)
        t = sy - y0
        def ryadok(arr):
            r = arr[y0] * (1 - t) + arr[y1] * t
            return np.stack([np.interp(sx, xs, r[:, c]) for c in range(3)], 1)
        fig = ryadok(a)
        mk = ryadok(np.repeat(mask[..., None].astype(float), 3, 2))[:, :1]
        tl = ryadok(tlo) if y >= z0 else fig
        nove[y] = fig * mk + tl * (1 - mk) if y >= z0 else fig
    # 4. Назад у w×h; краї — крайніми стовпцями (суцільне тло давало смуги).
    mal = Image.fromarray(nove.clip(0, 255).astype(np.uint8))
    k = h / vys
    mal = mal.resize((int(w * k), h), Image.LANCZOS)
    pad = w - mal.width
    out = Image.fromarray(np.pad(np.asarray(mal),
                                 ((0, 0), (pad // 2, pad - pad // 2), (0, 0)),
                                 mode="edge"))
    out.save(D / "el-dovha-chernetka.png")
    print("промежина", krok, "чернетка готова", flush=True)


def main():
    chernetka()
    if "--kontext" not in sys.argv:
        return
    rk.PROMT = PROMT
    image = m.stage(str(D / "el-dovha-chernetka.png"))
    m.free()
    for seed in SIDY:
        kudy = D / ("el-dovha-s%d.png" % seed)
        if kudy.exists():
            continue
        done = m.run(rk.graf(image, seed, "el_dovha_s%d" % seed))
        out = done["outputs"]["13"]["images"][-1]
        shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"],
                                 out["filename"]), kudy)
        print("готово", kudy.name, flush=True)


if __name__ == "__main__":
    main()
