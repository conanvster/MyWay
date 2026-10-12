#!/usr/bin/env python3
"""Обличчя орчихи з рендера-скульптури замовника (12.10.2026).

Слово замовника: «s1303 — краще цей, [два рендери] — візьми обличчя
звідси». Рендери — сіра скульптура орчихи 3/4 (знімки екрана 18-03-48 і
18-04-35); обличчя: важкі надбрівні дуги, насуплений погляд, широкий ніс,
сильна щелепа.

FLUX Kontext з ДВОМА кадрами (ланцюжок ReferenceLatent): голова s1303
(вирізана квадратом, ×N до 1024²) і обличчя з рендера. Колір шкіри,
ракурс і світло — з s1303, будова обличчя — з рендера. Нова голова
вставляється назад у кадр м'яким еліпсом — тіло лишається пікселями s1303.

    ~/Програми/cv-venv/bin/python -u tools/comfyui/ork_oblychchia_ref.py [сід…]

Вихід — `wiki/img/test/avatar/ork2-lysa-s1303-obl-s<сід>.png`.
"""
import os
import shutil
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster3d as m  # noqa: E402
import rasy_kontext as rk  # noqa: E402
import elf_oblychchia as eo  # noqa: E402

D = eo.D
KADR = D / "ork2-lysa-s1303.png"
REF = "/home/alex/Зображення/Знімки екрана/Знімок екрана з 2026-10-12 18-03-48.png"
REF_RAMKA = (150, 20, 300, 170)          # голова на рендері 486×978
SIDY = [int(a) for a in sys.argv[1:] if a.isdigit()] or [1401, 1402, 1403]
PROMT = (
    "Give the green-skinned orc woman in the first image the face from the "
    "second image (a grey sculpture): the same facial structure — heavy "
    "protruding brow ridge, deep-set narrowed eyes, fierce scowling "
    "expression, broad flat nose, strong square jaw, high cheekbones, "
    "full lips pressed together. Keep everything else of the first image: "
    "same olive-green skin colour and texture, same short white hair, same "
    "long pointed ears, same front view and head position, same lighting, "
    "same grey background, photorealistic.")


def graf(holova, oblychchia, seed, prefix):
    g = rk.graf(holova, seed, prefix)
    g["20"] = {"class_type": "LoadImage", "inputs": {"image": oblychchia}}
    g["21"] = {"class_type": "FluxKontextImageScale", "inputs": {"image": ["20", 0]}}
    g["22"] = {"class_type": "VAEEncode", "inputs": {"pixels": ["21", 0], "vae": ["3", 0]}}
    g["23"] = {"class_type": "ReferenceLatent",
               "inputs": {"conditioning": ["8", 0], "latent": ["22", 0]}}
    g["9"]["inputs"]["conditioning"] = ["23", 0]
    return g


# Перший прохід переносив і сірий матеріал скульптури — другий оживлює
# голову (`--оживити <сід першого проходу>`), будова та сама.
PROMT_ZHYVA = (
    "Turn this grey sculpture head into a living photorealistic adult "
    "female orc woman: olive-green skin with natural pores and texture, "
    "exactly the same face structure, the same fierce scowling expression, "
    "heavy brow, deep-set dark eyes with detailed irises, slightly feminine "
    "features, natural darker green lips, completely bald smooth green "
    "scalp, the same long pointed ears in green skin with reddish tips. Same "
    "framing, same head position, same front view, same grey grid "
    "background, soft even lighting.")


def ozhyvyty(pershyi, sidy):
    """Другий прохід: Kontext на голові першого проходу → вставка в кадр."""
    rk.PROMT = PROMT_ZHYVA
    maska = np.asarray(Image.open(D / (KADR.stem + "-maska.png")).convert("L")) > 127
    x0, y0, x1, y1 = eo.holova_ramka(maska)
    s = x1 - x0
    kadr = Image.open(KADR).convert("RGB")
    holova = m.stage(str(D / ("%s-holova-obl-s%d.png" % (KADR.stem, pershyi))))
    m.free()
    for seed in sidy:
        kudy = D / ("%s-obl-s%d-zh-s%d.png" % (KADR.stem, pershyi, seed))
        done = m.run(rk.graf(holova, seed, "ork_zh_%d" % seed))
        out = done["outputs"]["13"]["images"][-1]
        src = os.path.join(m.COMFY, "output", out["subfolder"], out["filename"])
        shutil.copy(src, D / ("%s-holova-obl-s%d-zh-s%d.png" % (KADR.stem, pershyi, seed)))
        nova = Image.open(src).convert("RGB").resize((s, s), Image.LANCZOS)
        kraj = Image.new("L", (s, s), 0)
        ImageDraw.Draw(kraj).ellipse((s * 0.12, s * 0.04, s * 0.88, s * 0.96), fill=255)
        kraj = kraj.filter(ImageFilter.GaussianBlur(s * 0.06))
        zbir = kadr.copy()
        zbir.paste(nova, (x0, y0), kraj)
        zbir.save(kudy)
        print("готово", kudy.name, flush=True)
    m.free()


def zshyty(holova_png, kudy):
    """Вставка голови в кадр (друга проба зшивки): колір шкіри — під тіло
    (середнє й розкид у Lab по пікселях шкіри старої голови), лише в межах
    силуету голови (тло — сіре ненасичене; без ореолу від іншої сітки
    тла), нижче підборіддя — ні (на шиї з'являвся комір сорочки)."""
    import cv2
    maska = np.asarray(Image.open(D / (KADR.stem + "-maska.png")).convert("L")) > 127
    x0, y0, x1, y1 = eo.holova_ramka(maska)
    s = x1 - x0
    kadr = np.asarray(Image.open(KADR).convert("RGB"))
    stara = kadr[y0:y1, x0:x1]
    nova = np.asarray(Image.open(holova_png).convert("RGB").resize((s, s), Image.LANCZOS))
    def shkira(a):
        hsv = cv2.cvtColor(a, cv2.COLOR_RGB2HSV)
        return (hsv[..., 1] > 45) & (hsv[..., 0] >= 18) & (hsv[..., 0] <= 45)
    ls = cv2.cvtColor(stara, cv2.COLOR_RGB2LAB).astype(np.float32)
    ln = cv2.cvtColor(nova, cv2.COLOR_RGB2LAB).astype(np.float32)
    ms, mn = shkira(stara), shkira(nova)
    for k in range(3):
        a_, b_ = ln[..., k][mn], ls[..., k][ms]
        ln[..., k] = (ln[..., k] - a_.mean()) / max(a_.std(), 1e-3) * b_.std() + b_.mean()
    nova = cv2.cvtColor(ln.clip(0, 255).astype(np.uint8), cv2.COLOR_LAB2RGB)
    # силует нової голови — шкіра й вуха (відтінок 0…50 або червоні кінчики,
    # S > 40), дірки (очі, губи) заповнено; тло нової голови теж трохи
    # насичене — «S > 30» давало ореол
    hsv_n = cv2.cvtColor(nova, cv2.COLOR_RGB2HSV)
    sh_n = ((hsv_n[..., 0] <= 50) | (hsv_n[..., 0] >= 165)) & (hsv_n[..., 1] > 40)
    sh_n = cv2.morphologyEx(sh_n.astype(np.uint8), cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))
    n_, mit, st, _ = cv2.connectedComponentsWithStats(sh_n)
    sh_n = (mit == 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))).astype(np.uint8)
    zal = sh_n.copy()
    ff = np.zeros((s + 2, s + 2), np.uint8)
    cv2.floodFill(zal, ff, (0, 0), 1)
    sh_n = sh_n | (1 - zal)
    sylu = sh_n.astype(np.float32)
    el = np.zeros((s, s), np.float32)
    cv2.ellipse(el, (s // 2, int(s * 0.45)), (int(s * 0.40), int(s * 0.40)), 0, 0, 360, 1.0, -1)
    m_ = cv2.GaussianBlur(el * sylu, (0, 0), s * 0.02)[..., None]
    zbir = kadr.copy()
    zbir[y0:y1, x0:x1] = (stara * (1 - m_) + nova * m_).astype(np.uint8)
    Image.fromarray(zbir).save(kudy)
    print("зшито", kudy.name, flush=True)


def main():
    if "--зшити" in sys.argv:
        for f in sorted(D.glob(KADR.stem + "-holova-obl-s*-zh-s*.png")):
            zshyty(f, D / f.name.replace("-holova-", "-"))
        return
    if "--оживити" in sys.argv:
        i = sys.argv.index("--оживити")
        pershyi = int(sys.argv[i + 1])
        ozhyvyty(pershyi, [int(a) for a in sys.argv[i + 2:] if a.isdigit()] or [1501, 1502, 1503])
        return
    rk.PROMT = PROMT
    maska_p = D / (KADR.stem + "-maska.png")
    if not maska_p.exists():
        m.cutout(str(KADR), str(maska_p))
    maska = np.asarray(Image.open(maska_p).convert("L")) > 127
    ramka = eo.holova_ramka(maska)
    kadr = Image.open(KADR).convert("RGB")
    krop_p = D / (KADR.stem + "-holova-krop.png")
    kadr.crop(ramka).resize((1024, 1024), Image.LANCZOS).save(krop_p)
    ref_p = D / "ork-oblychchia-ref.png"
    Image.open(REF).convert("RGB").crop(REF_RAMKA).resize((1024, 1024), Image.LANCZOS).save(ref_p)
    holova, obl = m.stage(str(krop_p)), m.stage(str(ref_p))
    m.free()
    x0, y0, x1, y1 = ramka
    s = x1 - x0
    for seed in SIDY:
        kudy = D / ("%s-obl-s%d.png" % (KADR.stem, seed))
        if kudy.exists():
            print("є", kudy.name, flush=True)
            continue
        done = m.run(graf(holova, obl, seed, "ork_obl_%d" % seed))
        out = done["outputs"]["13"]["images"][-1]
        nova = Image.open(os.path.join(m.COMFY, "output", out["subfolder"],
                                       out["filename"])).convert("RGB")
        shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"], out["filename"]),
                    D / ("%s-holova-obl-s%d.png" % (KADR.stem, seed)))
        nova = nova.resize((s, s), Image.LANCZOS)
        kraj = Image.new("L", (s, s), 0)
        ImageDraw.Draw(kraj).ellipse((s * 0.12, s * 0.04, s * 0.88, s * 0.96), fill=255)
        kraj = kraj.filter(ImageFilter.GaussianBlur(s * 0.06))
        zbir = kadr.copy()
        zbir.paste(nova, (x0, y0), kraj)
        zbir.save(kudy)
        print("готово", kudy.name, flush=True)
    m.free()


if __name__ == "__main__":
    main()
