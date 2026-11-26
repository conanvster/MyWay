#!/usr/bin/env python3
"""Проба Т-0, 26.11.2026 (слово замовника «так, запускай пробу»): лишаємо Qwen-Edit 2511, але
Т-0 у частини видів лишався з опущеними руками (базальтовий некро-охоронець, драконід-воїн,
кабанолюд-громила, ведмедолюд-вождь). Три способи × 3 сіди з того самого А-0:
  фото   — як в основному прогоні: друга картинка — фото манекена `_аркуш-каркас/Т-0.png`;
  кістяк — друга картинка — кістяк OpenPose `_аркуш-каркас/кістяк/Т-0.png` (тіла немає —
           нічого не просвічує) + чіткий опис Т-пози;
  текст  — без другої картинки, лише чіткий опис Т-пози.
Автоперевірка: розмах рук Т-0 ≥ 1,3 розмаху А-0 (як у qc-перевірці аркушів).
    ~/Програми/cv-venv/bin/python -u tools/comfyui/proby/t0_sposoby.py
→ art/monsters/_аркуш-каркас/проба-т0/<вид>/<спосіб>-s<сід>.png, підсумок.jpg
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

TUT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(TUT))
import monstr_arkush as ma  # noqa: E402
import monster3d as m  # noqa: E402
import bronia_2var as b2  # noqa: E402

VYDY = ["базальтовий некро-охоронець", "драконід-воїн", "кабанолюд-громила", "ведмедолюд-вождь"]
SIDY = [ma.SID, ma.SID + 1, ma.SID + 2]
SPOSOBY = ["фото", "кістяк", "текст"]
VYKHID = os.path.join(ma.KARKAS, "проба-т0")
T_SYLNO = ("POSE CHANGE IS REQUIRED: raise both arms straight out sideways, fully horizontal at "
           "shoulder height, elbows straight, palms down, hands open — a strict T-pose; the arms "
           "must NOT hang down. ")


def promt(sposib, b):
    p = ma.instr("Т", 0, False, b)
    if sposib == "фото":
        return p
    if sposib == "кістяк":
        p = p.replace("the grey mannequin in the second image",
                      "the coloured OpenPose stick-figure skeleton in the second image")
        p = p.replace("The mannequin is only a pose guide: do not copy its body, face or shorts.",
                      "The skeleton is only a pose guide: do not draw any lines or dots of it.")
        return T_SYLNO + p
    p = p.replace("in the same pose as the grey mannequin in the second image — ", "in ")
    p = p.replace("seen from the same camera angle as the second image: ", "seen from ")
    p = p.replace("The mannequin is only a pose guide: do not copy its body, face or shorts. ", "")
    return T_SYLNO + p


def rozmakh(f):
    a = np.asarray(Image.open(f).convert("RGB").resize((256, 256))).astype(int)
    mk = np.abs(a - np.array(ma.FON)).sum(2) > 25
    xs = np.where(mk[40:110].any(0))[0]
    return (xs[-1] - xs[0]) if len(xs) else 0


def zapustyty(persha, druha, tekst, seed, kudy):
    g = b2.graf_qwen(m.stage(persha), m.stage(druha or persha), tekst, seed, "proba_t0")
    g["1"]["inputs"]["unet_name"] = "qwen-image-edit-2511-Q4_K_M.gguf"
    g["2"]["inputs"]["lora_name"] = "Qwen-Image-Edit-2511-Lightning-8steps-V1.0-bf16.safetensors"
    if druha is None:
        for n in ("9", "10"):
            g[n]["inputs"].pop("image2", None)
    g["7"]["inputs"]["resolution_steps"] = 1
    done = m.run(g)
    out = [o for v in done["outputs"].values() for o in v.get("images", [])][-1]
    syryi = os.path.join(os.path.dirname(kudy), "сирі", os.path.basename(kudy))
    os.makedirs(os.path.dirname(syryi), exist_ok=True)
    import shutil
    shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"], out["filename"]), syryi)
    ma.chyste_tlo(m, syryi, kudy)


DRUHA = {"фото": os.path.join(ma.KARKAS, "Т-0.png"),
         "кістяк": os.path.join(ma.KARKAS, "кістяк", "Т-0.png"), "текст": None}
best = ma.bestiarii()
for seed in SIDY:            # спершу всі види й способи з першим сідом — рання картина
    for vyd in VYDY:
        a0 = os.path.join(ma.teka(vyd), "А-0.png")
        for s in SPOSOBY:
            kudy = os.path.join(VYKHID, vyd, "%s-s%d.png" % (s, seed))
            if os.path.exists(kudy):
                continue
            os.makedirs(os.path.dirname(kudy), exist_ok=True)
            zapustyty(a0, DRUHA[s], promt(s, best[vyd]), seed, kudy)
            k = rozmakh(kudy) / max(1, rozmakh(a0))
            print("готово", vyd, s, seed, "розмах ×%.2f %s" % (k, "✓" if k >= 1.3 else "✗"),
                  flush=True)
m.free()

# підсумок: ряд — вид (А-0 + 9 спроб), підпис ✓/✗
C = 240
o = Image.new("RGB", (C * 10, 40 + len(VYDY) * (C + 30)), (238, 237, 233))
d = ImageDraw.Draw(o)
f = ma.shryft(16)
for j, nazva in enumerate(["А-0"] + ["%s s%d" % (s, sd) for s in SPOSOBY for sd in SIDY]):
    d.text((j * C + 6, 10), nazva, font=ma.shryft(16, True), fill=(30, 30, 34))
pidsumok = {s: 0 for s in SPOSOBY}
for i, vyd in enumerate(VYDY):
    y = 40 + i * (C + 30)
    a0 = os.path.join(ma.teka(vyd), "А-0.png")
    o.paste(Image.open(a0).convert("RGB").resize((C - 4, C - 4)), (0, y))
    d.text((6, y + C - 2), vyd, font=f, fill=(30, 30, 34))
    for j, (s, sd) in enumerate((s, sd) for s in SPOSOBY for sd in SIDY):
        kf = os.path.join(VYKHID, vyd, "%s-s%d.png" % (s, sd))
        if not os.path.exists(kf):
            continue
        o.paste(Image.open(kf).convert("RGB").resize((C - 4, C - 4)), ((j + 1) * C, y))
        k = rozmakh(kf) / max(1, rozmakh(a0))
        pidsumok[s] += k >= 1.3
        d.text(((j + 1) * C + 6, y + C - 2), "×%.2f %s" % (k, "✓" if k >= 1.3 else "✗"),
               font=f, fill=(40, 120, 40) if k >= 1.3 else (170, 40, 40))
o.save(os.path.join(VYKHID, "підсумок.jpg"), quality=90)
print("підсумок", {s: "%d/%d" % (n, len(VYDY) * len(SIDY)) for s, n in pidsumok.items()},
      os.path.join(VYKHID, "підсумок.jpg"), flush=True)
