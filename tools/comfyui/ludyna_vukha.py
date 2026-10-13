#!/usr/bin/env python3
"""Людина-жінка з кадру лисої ельфійки: людські вуха (13.10.2026).

Слово замовника: «рендер el_lysa_1902_00001_.png — зроби як людина жінка.
el_lysa_1903_00001_.png — вибери ельфом». Кадр `el-lysa-s1902-рівно.png`
(пропорції вирівняно під основу) відрізняється від людини лише гострими
вухами — тож перемальовуються тільки вони: голова вирізається квадратом,
×5 до 1024², маска — два еліпси довкола вух (з запасом: людське вухо
менше, місце гострого кінчика стає тлом), FLUX dev шум 1,0 у масці; нова
голова вклеюється назад з м'яким краєм маски. Решта — пікселі кадру.

    ~/Програми/cv-venv/bin/python -u tools/comfyui/ludyna_vukha.py [--лише-маска] [сід…]

Вихід — `wiki/img/test/avatar/lyud-lysa-s<сід>.png`.
"""
import os
import shutil
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster3d as m  # noqa: E402
import avatar_ref_stopy as st  # noqa: E402

D = Path(__file__).resolve().parents[2] / "wiki/img/test/avatar"
KADR = D / "el-lysa-s1902-рівно.png"
RAMKA = (412, 20, 612, 220)          # голова, 200² у кадрі 1024²
# (центр x, y, піввісі a, b) у кадрі — гострі вуха разом із кінчиками
VUKHA = [(461, 108, 15, 25), (557, 108, 15, 25)]
SIDY = [int(a) for a in sys.argv[1:] if a.isdigit()] or [2001, 2002, 2003]
PROMT = (
    "Extreme close-up studio portrait of a bald young human woman, front "
    "view, completely smooth shaved head, normal small rounded human ears "
    "close to the head with a natural earlobe, no pointed ears, pale skin "
    "with fine natural pores, calm neutral expression, plain light grey "
    "background, soft even lighting, sharp focus, photorealistic.")


def maska_krop():
    x0, y0, x1, y1 = RAMKA
    k = 1024 / (x1 - x0)
    mm = np.zeros((1024, 1024), np.uint8)
    for x, y, a, b in VUKHA:
        cv2.ellipse(mm, (int((x - x0) * k), int((y - y0) * k)),
                    (int(a * k), int(b * k)), 0, 0, 360, 255, -1)
    return mm


def main():
    kadr = Image.open(KADR).convert("RGB")
    krop = kadr.crop(RAMKA).resize((1024, 1024), Image.LANCZOS)
    krop.save(D / "lyud-holova-krop.png")
    mm = maska_krop()
    Image.fromarray(mm).save(D / "lyud-vukha-maska.png")
    nahl = np.array(krop)
    nahl[mm > 0] = (nahl[mm > 0] * 0.5 + np.array([255, 0, 0]) * 0.5).astype(np.uint8)
    Image.fromarray(nahl).save(D / "lyud-vukha-nahliad.png")
    if "--лише-маска" in sys.argv:
        return
    st.PROMT_MASKA = PROMT
    image, mask = m.stage(str(D / "lyud-holova-krop.png")), m.stage(str(D / "lyud-vukha-maska.png"))
    m.free()
    x0, y0, x1, y1 = RAMKA
    s = x1 - x0
    soft = cv2.GaussianBlur(cv2.dilate(mm, np.ones((15, 15), np.uint8)).astype(np.float32) / 255,
                            (0, 0), 6.0)
    soft = cv2.resize(soft, (s, s), interpolation=cv2.INTER_AREA)[..., None]
    for seed in SIDY:
        done = m.run(st.graf_maska(image, mask, seed, "lyud_vukha_%d" % seed, 1.0))
        out = done["outputs"]["13"]["images"][-1]
        nova = Image.open(os.path.join(m.COMFY, "output", out["subfolder"], out["filename"])) \
            .convert("RGB")
        shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"], out["filename"]),
                    D / ("lyud-holova-s%d.png" % seed))
        nova = np.array(nova.resize((s, s), Image.LANCZOS)).astype(np.float32)
        a = np.array(kadr).astype(np.float32)
        a[y0:y1, x0:x1] = a[y0:y1, x0:x1] * (1 - soft) + nova * soft
        Image.fromarray(a.clip(0, 255).astype(np.uint8)).save(D / ("lyud-lysa-s%d.png" % seed))
        print("готово lyud-lysa-s%d.png" % seed, flush=True)
    m.free()


if __name__ == "__main__":
    main()
