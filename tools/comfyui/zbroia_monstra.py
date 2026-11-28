#!/usr/bin/env python3
"""Зброя монстра-гуманоїда → 3D (П-297, крок «1 — зброя», 28.11.2026).

Кадр `зброя.png` аркуша не годиться для 3D: у частини видів на ньому сама істота, а предметів
буває два («Меч і щит»). Тут кожен предмет окремо:
  1. опис зброї з бестіарію → предмети (через « і », «,», «та»); рука й розмір — за ключовим
     словом (`PREDMETY`);
  2. Qwen-Edit 2511 з референсу вікі: лише цей предмет, прямо, спереду, на сірому — `<пр>.png`;
  3. TRELLIS.2 (`trellis_rich.py`) → `<пр>.glb`;
  4. опис для `monstr_rig.py --зброя`: `зброя.json` [{файл, кістка, довжина, хват, вісь}].

    ~/Програми/cv-venv/bin/python -u tools/comfyui/zbroia_monstra.py <вид> <тека>
"""
import json
import os
import re
import shutil
import subprocess
import sys

TUT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TUT)
import monstr_arkush as ma  # noqa: E402

# ключ → (англійська назва для Qwen, кістка, довжина як частка зросту, хват від низу (частка),
#          вісь: «вістря» — довге (держак у кулаці), «лице» — пласке (щит, бубон))
PREDMETY = [
    ("щит", ("round shield", "hand_l", 0.36, 0.5, "лице")),
    # бубон — плаский (рама + шкіра), тримають за обід: хват біля нижнього краю (28.11: «бубон»
    # Qwen малював бочкою на боці — у руці гнола читалась скринька); тримають за ВЕРХНІЙ край
    # обода — бубон висить під кистю: за нижній він у касті закривав морду
    ("бубон", ("flat round shaman frame drum (a thin wooden hoop with a stretched hide head, like a "
               "large tambourine, small rattles hanging on the rim), seen face-on as a flat circle",
               "hand_l", 0.3, 0.92, "лице")),
    ("барабан", ("flat round frame drum seen face-on as a flat circle", "hand_l", 0.3, 0.92, "лице")),
    ("посох", ("wooden staff", "hand_r", 0.95, 0.45, "вістря")),
    ("жезл", ("short scepter", "hand_r", 0.32, 0.25, "вістря")),
    ("спис", ("spear", "hand_r", 1.0, 0.4, "вістря")),
    ("молот", ("war hammer", "hand_r", 0.45, 0.14, "вістря")),
    ("сокир", ("battle axe", "hand_r", 0.45, 0.14, "вістря")),
    ("булав", ("mace", "hand_r", 0.4, 0.14, "вістря")),
    ("кийок", ("wooden club", "hand_r", 0.4, 0.14, "вістря")),
    ("дубин", ("wooden club", "hand_r", 0.45, 0.14, "вістря")),
    ("рапір", ("rapier", "hand_r", 0.5, 0.12, "вістря")),
    ("меч", ("sword", "hand_r", 0.48, 0.12, "вістря")),
    ("клин", ("curved blade", "hand_r", 0.42, 0.12, "вістря")),
    ("ніж", ("long knife", "hand_r", 0.2, 0.2, "вістря")),
    ("кинджал", ("dagger", "hand_r", 0.2, 0.2, "вістря")),
    # лук тримають сторч за середину (вісь «лук» — без повороту)
    ("лук", ("long bow with its string, the whole bow standing as a tall curved arc", "hand_l", 0.75, 0.5, "лук")),
]


def predmety(z):
    """«Меч і щит» → [меч, щит]; «Два вигнуті клинки» → клинок у правій і лівій."""
    z = z.lower().strip().rstrip(".")
    chastyny = [c.strip() for c in re.split(r",| і | та | й ", z) if c.strip()]
    rez = []
    for ch in chastyny:
        for kl, (en, kist, dov, khvat, vis) in PREDMETY:
            if kl in ch:
                rez.append({"ключ": kl, "опис": ch, "en": en, "кістка": kist, "довжина": dov,
                            "хват": khvat, "вісь": vis})
                if ch.startswith("два ") or ch.startswith("дві "):
                    rez.append(dict(rez[-1], кістка="hand_l" if kist == "hand_r" else "hand_r"))
                break
    return rez


def instr(p):
    return ("From the image take only the " + p["en"] + " of the creature (described in Ukrainian "
            "as: «" + p["опис"] + "») and show it alone as a clean prop reference for 3D modeling: "
            "one single object, the whole item, standing perfectly upright and vertical with the "
            "handle or grip at the BOTTOM and the blade tip or head at the TOP, seen "
            "straight from the front, centered, filling most of the image height. No creature, no "
            "hands, no body parts, no second item, no stand, no text. "
            + ma.SVITLO.split(" Plain")[0] + " Plain light grey seamless background, "
            "photorealistic, sharp detail.")


def main():
    vyd, teka = sys.argv[1], os.path.abspath(sys.argv[2])
    os.makedirs(teka, exist_ok=True)
    b = ma.bestiarii()[vyd]
    z = ma.zbroia(b)
    sp = predmety(z) if z else []
    print("зброя «%s» → %s" % (z, [p["ключ"] + "→" + p["кістка"] for p in sp]), flush=True)
    import monster3d as m  # noqa: E402
    import bronia_2var as b2  # noqa: E402
    ref = os.path.join(ma.KORIN, "wiki/img/monstry", vyd + ".png")
    gotovi = []
    for i, p in enumerate(sp):
        imia = "%d-%s" % (i, p["ключ"])
        kadr = os.path.join(teka, imia + ".png")
        if not os.path.exists(kadr):
            ma.zapustyty(m, b2, ref, None, instr(p), kadr)
            print("кадр", kadr, flush=True)
        glb = os.path.join(teka, imia + ".glb")
        if not os.path.exists(glb):
            subprocess.run([sys.executable, "-u", os.path.join(TUT, "trellis_rich.py"), kadr, glb,
                            "--граней", "20000"], check=True)
        gotovi.append(dict(p, файл=glb, кадр=kadr))
    json.dump(gotovi, open(os.path.join(teka, "зброя.json"), "w"), ensure_ascii=False, indent=1)
    print("готово", len(gotovi), "предметів →", teka, flush=True)


if __name__ == "__main__":
    main()
