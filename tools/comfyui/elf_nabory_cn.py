#!/usr/bin/env python3
"""Набори ельфійки з ControlNet (12.10.2026) — пропорції тримає поза.

Слово замовника: «пропорції не витримались … промежини не дотягнуті»;
«Важкі шоломи D грейду не повинні закривати»; спосіб — «ControlNet
Union-Pro 2.0» (Shakker Labs, flux-1-dev-non-commercial-license, як і
FLUX dev/Kontext, що вже в роботі). Kontext тримає статуру лише словами —
і не тримає (`tools/elf_markery.py`: промежина нижче на 25–128 px).

Тут FLUX dev від основи `el-dovha-chernetka.png` (img2img) + ControlNet
Union-Pro за скелетом OpenPose, побудованим із силуету й обличчя основи:
довжини кінцівок, промежина, коліна, ступні — з кадру, а не з промпту;
об'єм одягу скелет не обмежує. Обличчя — під маскою, лишається основи.

    ~/Програми/cv-venv/bin/python -u tools/comfyui/elf_nabory_cn.py [ключ…]

Ключі ті самі, що в `elf_nabory.py`. Вихід —
`wiki/img/test/avatar/el-cn-nabir-<ключ>-s<сід>.png`; скелет і маска —
`el-cn-poza.png`, `el-cn-maska.png`.
"""
import os
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import monster3d as m  # noqa: E402
import elf_nabory as en  # noqa: E402
import elf_markery as mk  # noqa: E402

D = en.D
OSNOVA = D / "el-dovha-chernetka.png"
CN = "FLUX.1-dev-ControlNet-Union-Pro-2.0.safetensors"
SIDY = (707, 808)   # 101/202 — шум 0,92; 303/404, 505/606 — до правок шолома
SYLA, KINETS = 0.85, 0.65      # сила ControlNet і до якої частки кроків
# 0,92 лишав купальник (проба 12.10: топ замість броні, без шолома) — з
# нуля; обличчя однаково під маскою.
DENOISE = 1.0
# Шоломи — відкриті (слово замовника 12.10.2026).
NABORY = dict(en.NABORY)
NABORY["E-важкий"] = NABORY["E-важкий"].replace(
    "a closed bark helmet with narrow eye slits covering her head",
    "an open-faced carved bark helmet that leaves her whole face visible")
NABORY["D-важкий"] = NABORY["D-важкий"].replace(
    "a closed iron knight helmet with a visor covering her head",
    "an open-faced iron helmet with cheek guards that leaves her whole "
    "face visible")

# Важкі — шолом першим і матеріал прямо (проба 12.10, s303/404: шкіра
# замість кори, шолом пропущено).
NABORY["E-важкий"] = (
    "an open-faced helmet of carved dark oak bark on her head (her whole "
    "face visible), and heavy armour made entirely of thick carved dark "
    "oak bark plates: a bark breastplate with rounded bark shoulder "
    "guards, bark vambraces and gauntlets, a bark plate skirt over dark "
    "leggings, bark greaves and tall bark boots, a worn brown leather belt")
NABORY["D-важкий"] = (
    "an open-faced iron helmet with cheek guards on her head (her whole "
    "face visible), and a full set of slim fitted iron plate armour: a "
    "polished iron cuirass with layered pauldrons, a dark red cloth tabard, "
    "articulated iron gauntlets, iron tassets over the hips, iron greaves "
    "and sabatons, a dark iron-studded belt")

# OpenPose COCO-18: 0 ніс, 1 шия, 2-4 права рука, 5-7 ліва, 8-10 права
# нога, 11-13 ліва, 14/15 очі, 16/17 вуха. «Права» — права тіла, на кадрі
# спереду — ліворуч.
PARY = [(1, 2), (1, 5), (2, 3), (3, 4), (5, 6), (6, 7), (1, 8), (8, 9),
        (9, 10), (1, 11), (11, 12), (12, 13), (1, 0), (0, 14), (14, 16),
        (0, 15), (15, 17)]
KOLORY = [(255, 0, 0), (255, 85, 0), (255, 170, 0), (255, 255, 0),
          (170, 255, 0), (85, 255, 0), (0, 255, 0), (0, 255, 85),
          (0, 255, 170), (0, 255, 255), (0, 170, 255), (0, 85, 255),
          (0, 0, 255), (85, 0, 255), (170, 0, 255), (255, 0, 255),
          (255, 0, 170), (255, 0, 85)]


def tochky_tila():
    """Скелет основи: точки з силуету (birefnet) і обличчя (MediaPipe)."""
    import mediapipe as mpp
    from mediapipe.tasks.python import BaseOptions, vision
    mir = mk.mirky(OSNOVA)
    msk = mk.sylyet(OSNOVA)
    h, w = msk.shape
    ys, xs = np.where(msk)
    cx = float(xs[(ys > mir["промежина"] - 40) & (ys < mir["промежина"])].mean())
    # руки: рядок найбільшої ширини у верхній половині
    shyr = msk[: int(mir["пояс"])].sum(1)
    ruka_y = float(np.argmax(shyr))
    rx = np.where(msk[int(ruka_y)])[0]
    lavyi, pravyi = float(rx.min()), float(rx.max())
    # плечі: ширина тулуба трохи нижче пахви
    nyzh = int(ruka_y + 45)
    s, e = mk.smugy(msk[nyzh])
    tulub = [(a, b) for a, b in zip(s, e) if a <= cx < b][0]
    pl_l, pl_p = float(tulub[0]) + 8, float(tulub[1]) - 8
    kys = (pravyi - lavyi) * 0.045
    # обличчя
    det = vision.FaceLandmarker.create_from_options(vision.FaceLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=mk.MODEL), num_faces=1))
    a = np.asarray(Image.open(OSNOVA).convert("RGB"))
    x0, x1, y0, y1, k = 362, 662, 0, 300, 3
    big = np.asarray(Image.fromarray(a[y0:y1, x0:x1]).resize(
        ((x1 - x0) * k, (y1 - y0) * k), Image.LANCZOS))
    lm = det.detect(mpp.Image(image_format=mpp.ImageFormat.SRGB,
                              data=np.ascontiguousarray(big))).face_landmarks[0]
    P = lambda i: (x0 + lm[i].x * (x1 - x0), y0 + lm[i].y * (y1 - y0))  # noqa
    nis, oko_p, oko_l = P(1), P(33), P(263)       # 33 — праве око тіла
    vukho_p, vukho_l = P(234), P(454)
    shyia = (cx, (mir["підборіддя"] + ruka_y) / 2 + 6)
    kr, st = mir["промежина"], mir["ступні"]
    nogy_y = {"стегно": kr - 28, "коліно": kr + (st - kr) * 0.47,
              "кісточка": st - 38}
    def noga(y):
        s, e = mk.smugy(msk[int(y)])
        c = [(a + b) / 2 for a, b in zip(s, e)]
        c.sort()
        return (c[0], c[-1]) if len(c) >= 2 else (cx - 40, cx + 40)
    kl, kp = noga(nogy_y["коліно"])
    al, ap = noga(nogy_y["кісточка"])
    # тазові суглоби — ±0,3 ширини стегон на їхньому рівні (з відстані
    # колін виходили біля самої середини)
    s_, e_ = mk.smugy(msk[int(nogy_y["стегно"])])
    tz = [(a, b) for a, b in zip(s_, e_) if a <= cx < b]
    shyr_taz = (tz[0][1] - tz[0][0]) * 0.6 if tz else (kp - kl) * 1.4
    T = {0: nis, 1: shyia, 2: (pl_l, ruka_y), 5: (pl_p, ruka_y),
         3: ((pl_l + lavyi + kys) / 2, ruka_y), 4: (lavyi + kys, ruka_y),
         6: ((pl_p + pravyi - kys) / 2, ruka_y), 7: (pravyi - kys, ruka_y),
         8: (cx - shyr_taz / 2, nogy_y["стегно"]), 9: (kl, nogy_y["коліно"]),
         10: (al, nogy_y["кісточка"]),
         11: (cx + shyr_taz / 2, nogy_y["стегно"]), 12: (kp, nogy_y["коліно"]),
         13: (ap, nogy_y["кісточка"]),
         14: oko_p, 15: oko_l, 16: vukho_p, 17: vukho_l}
    return T, (w, h), lm, (x0, x1, y0, y1)


def malyuvaty_pozu(T, rozmir):
    im = Image.new("RGB", rozmir, (0, 0, 0))
    d = ImageDraw.Draw(im)
    for i, (a, b) in enumerate(PARY):
        d.line((T[a], T[b]), fill=tuple(int(c * 0.6) for c in KOLORY[i]),
               width=8)
    for i, p in T.items():
        d.ellipse((p[0] - 5, p[1] - 5, p[0] + 5, p[1] + 5), fill=KOLORY[i])
    im.save(D / "el-cn-poza.png")


def malyuvaty_masku(lm, ramka, rozmir):
    """Біле — перемальовувати, чорне — лишити основи (овал обличчя, звужений
    на 10% до центру, щоб шолом і каптур могли лягти на чоло й щоки)."""
    x0, x1, y0, y1 = ramka
    oval = [10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397,
            365, 379, 378, 400, 377, 152, 148, 176, 149, 150, 136, 172, 58,
            132, 93, 234, 127, 162, 21, 54, 103, 67, 109]
    pts = np.array([(x0 + lm[i].x * (x1 - x0), y0 + lm[i].y * (y1 - y0))
                    for i in oval])
    c = pts.mean(0)
    # 0,8 — шолом має лягти на чоло й вилиці (0,9 лишав голову волоссю)
    pts = c + (pts - c) * 0.8
    im = Image.new("L", rozmir, 255)
    ImageDraw.Draw(im).polygon([tuple(p) for p in pts], fill=0)
    im.save(D / "el-cn-maska.png")


def graf(osnova, maska, poza, promt, seed, prefix):
    return {
        "1": {"class_type": "UnetLoaderGGUF",
              "inputs": {"unet_name": "flux1-dev-Q4_K_S.gguf"}},
        "2": {"class_type": "DualCLIPLoader",
              "inputs": {"clip_name1": "clip_l.safetensors",
                         "clip_name2": "t5xxl_fp8_e4m3fn.safetensors",
                         "type": "flux"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": "ae.safetensors"}},
        "4": {"class_type": "LoadImage", "inputs": {"image": osnova}},
        "5": {"class_type": "LoadImageMask",
              "inputs": {"image": maska, "channel": "red"}},
        "6": {"class_type": "VAEEncode", "inputs": {"pixels": ["4", 0], "vae": ["3", 0]}},
        "7": {"class_type": "SetLatentNoiseMask",
              "inputs": {"samples": ["6", 0], "mask": ["5", 0]}},
        "8": {"class_type": "CLIPTextEncode", "inputs": {"text": promt, "clip": ["2", 0]}},
        "9": {"class_type": "FluxGuidance",
              "inputs": {"conditioning": ["8", 0], "guidance": 3.5}},
        "10": {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["8", 0]}},
        "14": {"class_type": "ControlNetLoader", "inputs": {"control_net_name": CN}},
        "15": {"class_type": "LoadImage", "inputs": {"image": poza}},
        "16": {"class_type": "ControlNetApplyAdvanced",
               "inputs": {"positive": ["9", 0], "negative": ["10", 0],
                          "control_net": ["14", 0], "image": ["15", 0],
                          "strength": SYLA, "start_percent": 0.0,
                          "end_percent": KINETS, "vae": ["3", 0]}},
        "11": {"class_type": "KSampler",
               "inputs": {"model": ["1", 0], "seed": seed, "steps": 28, "cfg": 1.0,
                          "sampler_name": "euler", "scheduler": "simple",
                          "positive": ["16", 0], "negative": ["16", 1],
                          "latent_image": ["7", 0], "denoise": DENOISE}},
        "12": {"class_type": "VAEDecode", "inputs": {"samples": ["11", 0], "vae": ["3", 0]}},
        "13": {"class_type": "SaveImage", "inputs": {"images": ["12", 0],
                                                      "filename_prefix": prefix}},
    }


# Без броні, топлес (слово замовника 12.10.2026: «зроби ельфійку без
# броні, топлес в T позі») — тіло-основа під одяг; нейтральний студійний
# референс дорослої жінки, як для анатомії.
TOPLES = (
    "Full body neutral studio reference photo of a tall, slender adult elf "
    "woman standing in a strict T-pose, arms straight out to the sides, "
    "palms down, front view, topless with a bare chest, wearing only plain "
    "black briefs, barefoot. Long pointed elf ears, long straight "
    "silver-white hair behind her shoulders, pale skin, delicate face, "
    "calm neutral expression, very long slim legs, narrow hips, tiny "
    "waist, narrow shoulders, thin arms. Plain light grey studio "
    "background, soft even lighting, photorealistic anatomy reference, "
    "the whole body from head to feet in frame.")


def promt(nabir, sholom=False):
    volossia = ("long straight silver-white hair flowing down from under "
                "the helmet, the helmet covers the top of her head and her "
                "forehead" if sholom else "long straight silver-white hair")
    return ("Full body photo of a tall, slender young elf woman standing in a "
            "strict T-pose, arms straight out to the sides, front view, fully "
            "dressed from neck to toes, no bare skin on the body, wearing the "
            "complete outfit: " + nabir + ". Long pointed elf ears, " + volossia + ", "
            "pale skin, delicate face, very long slim legs, narrow hips, tiny "
            "waist. Plain light grey studio background, soft even lighting, "
            "photorealistic, fantasy game character armour, realistic "
            "materials, the whole body from head to feet in frame.")


def main():
    T, rozmir, lm, ramka = tochky_tila()
    malyuvaty_pozu(T, rozmir)
    malyuvaty_masku(lm, ramka, rozmir)
    print("скелет і маска готові", flush=True)
    if "--лише-поза" in sys.argv:
        return
    kluchi = [a for a in sys.argv[1:] if a in NABORY or a == "топлес"] \
        or list(NABORY)
    osn, msk, poz = (m.stage(str(D / f)) for f in
                     ("el-dovha-chernetka.png", "el-cn-maska.png", "el-cn-poza.png"))
    m.free()
    for kl in kluchi:
        for seed in SIDY:
            kudy = D / ("el-cn-nabir-%s-s%d.png" % (kl, seed))
            if kudy.exists():
                print("є", kudy.name, flush=True)
                continue
            done = m.run(graf(osn, msk, poz, (TOPLES if kl == "топлес" else promt(NABORY[kl], "важкий" in kl)),
                       seed, "el_cn_%d" % seed))
            out = done["outputs"]["13"]["images"][-1]
            shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"],
                                     out["filename"]), kudy)
            print("готово", kudy.name, flush=True)
    m.free()


if __name__ == "__main__":
    main()
