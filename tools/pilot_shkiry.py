#!/usr/bin/env python3
"""Шкіри й текстури очей на вибір для людини MPFB (П-281, крок 3, Б+В).

Пише поруч із моделлю `<модель>_шкіра-<назва>.png` і `<модель>_очі-<назва>.png`
(гра бере їх як варіанти: `skinned_model.gd`, `_variant_files`). Розгортка
в усіх шкірах і очах MPFB одна.

Середніх тонів серед молодих жіночих шкір MakeHuman немає: «азійська» й
«європейська» майже однакові (≈208,162,135), «африканська» темна
(≈105,61,44). Смаглява й засмагла — зі світлої переведенням тону в Lab
(яскравість множником, барви зсувом), щоб пори й малюнок лишились; губи
й соски темнішають разом зі шкірою.

Карі очі MPFB бордові (райдужка ≈62,18,10 — у грі червоні): барви
райдужки зсуваються в Lab до каро-горіхових (за маскою очей), малюнок
лишається. Тим самим файлом заміщується й витягнута з GLB текстура очей
`<модель>_brown_eye.png` (типові очі моделі) — тому запускати після
імпорту GLB у Godot.

    ~/Програми/cv-venv/bin/python tools/pilot_shkiry.py <дані MPFB> \\
        <маски.png> <маски-очі.png> <вихідний префікс: …/людина-жінка>
"""
import os
import shutil
import sys

import cv2
import numpy as np

DANI, MASKY, MASKY_OCHI, PREF = sys.argv[1:5]
SK = os.path.join(DANI, "skins")
SVITLA = os.path.join(SK, "young_caucasian_female", "young_lightskinned_female_diffuse.png")
SHKIRY = [
    ("1-світла", SVITLA, None),
    ("2-світла-рожева", os.path.join(SK, "young_caucasian_female2",
                                     "young_lightskinned_female_diffuse2.png"), None),
    ("3-смаглява", SVITLA, (176, 124, 90)),
    ("4-засмагла", SVITLA, (150, 104, 72)),
    ("5-темна", os.path.join(SK, "young_african_female",
                             "young_darkskinned_female_diffuse.png"), None),
]
OCHI = [("blue", "блакитні"), ("bluegreen", "синьо-зелені"), ("brown", "карі"),
        ("brownlight", "світло-карі"), ("deepblue", "темно-сині"), ("green", "зелені"),
        ("grey", "сірі"), ("ice", "крижані"), ("lightblue", "світло-блакитні")]

m = cv2.imread(MASKY, cv2.IMREAD_UNCHANGED)
for nazva, dzherelo, ton in SHKIRY:
    kudy = "%s_шкіра-%s.png" % (PREF, nazva)
    if ton is None:
        shutil.copyfile(dzherelo, kudy)
    else:
        im = cv2.imread(dzherelo)
        mm = cv2.resize(m, im.shape[1::-1])
        shkira = (im.mean(2) > 40) & (mm.max(2) < 25)     # поза губами, підводкою, скальпом
        lab = cv2.cvtColor(im, cv2.COLOR_BGR2LAB).astype(np.float32)
        t = cv2.cvtColor(np.uint8([[ton[::-1]]]), cv2.COLOR_BGR2LAB).astype(np.float32)[0, 0]
        s = lab[shkira].mean(0)
        lab[..., 0] *= t[0] / s[0]
        lab[..., 1:] += t[1:] - s[1:]
        im = cv2.cvtColor(np.clip(lab, 0, 255).astype(np.uint8), cv2.COLOR_LAB2BGR)
        cv2.imwrite(kudy, im)
    print("[шкіри]", kudy)
KARI = (78, 48, 24)          # sRGB райдужки після зсуву
mo = cv2.imread(MASKY_OCHI, cv2.IMREAD_UNCHANGED)[..., 2].astype(np.float32) / 255
for en, uk in OCHI:
    dz = os.path.join(DANI, "eyes", "materials", en + "_eye.png")
    if en != "brown":
        shutil.copyfile(dz, "%s_очі-%s.png" % (PREF, uk))
        continue
    im = cv2.imread(dz, cv2.IMREAD_UNCHANGED)
    lab = cv2.cvtColor(im[..., :3], cv2.COLOR_BGR2LAB).astype(np.float32)
    t = cv2.cvtColor(np.uint8([[KARI[::-1]]]), cv2.COLOR_BGR2LAB).astype(np.float32)[0, 0]
    s = lab[mo > 0.5].mean(0)
    zsuv = np.zeros(3, np.float32)
    zsuv[1:] = t[1:] - s[1:]
    lab[..., 0] *= 1 + (t[0] / s[0] - 1) * mo
    lab += zsuv * mo[..., None]
    im[..., :3] = cv2.cvtColor(np.clip(lab, 0, 255).astype(np.uint8), cv2.COLOR_LAB2BGR)
    for kudy in ("%s_очі-%s.png" % (PREF, uk), PREF + "_brown_eye.png"):
        cv2.imwrite(kudy, im)
    print("[шкіри] карі: райдужка", [int(x) for x in im[..., :3][mo > 0.5].mean(0)[::-1]])
print("[шкіри] очей: %d" % len(OCHI))
