#!/usr/bin/env python3
"""Манера рухів гуманоїда-монстра з бестіарію (П-297, 28.11.2026; `spec/монстри-3d-рух-план.md` §3).

Слово замовника: «мене трохи бентежить що у всих монстрів буде однакові рухи — тому намагайся
робити рухи трохи варіативнішими». Три рівні:
  1. набір кліпів UAL1/UAL2 — за манерою (зброя й опис: важка, щит, кігті, нежить, кастер, воїн);
  2. почерк — сутулість, голова, руки від тіла, стійка: за манерою + свій зсув виду (з назви,
     сталий), темп — від зросту (більший — повільніший);
  3. (у грі) темп і фаза особини, варіант удару/влучання/смерті — `skinned_model.gd`.

    python3 tools/monstr_manera.py <вид> [<вихід.json>]     # друк або запис для monstr_rig.py
"""
import hashlib
import json
import os
import sys

KORIN = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
BEST = os.path.join(KORIN, "spec", "бестіарій.json")

# кліпи: U1 — UAL1_Standard, U2 — UAL2_Standard (той самий скелет)
BAZA = {"Idle": "U1:Idle_Loop", "Walk": "U1:Walk_Loop", "Run": "U1:Jog_Fwd_Loop",
        "Attack": "U1:Sword_Attack", "Attack2": "U2:Melee_Hook",
        "Cast": "U1:Spell_Simple_Idle_Loop", "Hit": "U1:Hit_Chest", "Hit2": "U1:Hit_Head",
        "Death": "U1:Death01", "Death2": "дзеркало:U1:Death01"}
MANERY = {
    "важка": ({"Idle": "U1:Idle_Loop", "Attack": "U1:Sword_Attack", "Attack2": "U1:Punch_Cross",
               "Hit2": "U1:Hit_Chest"},
              {"сутулість": 10, "голова": -4, "руки": 10, "стійка": 5, "темп": 0.88}),
    "щит": ({"Idle": "U2:Idle_Shield_Loop", "Attack2": "U2:Shield_OneShot", "Hit": "U2:Sword_Block"},
            {"сутулість": 5, "голова": -2, "руки": 4, "стійка": 4, "темп": 1.0}),
    "кігті": ({"Idle": "U1:Sword_Idle", "Attack": "U1:Punch_Jab", "Attack2": "U2:Zombie_Scratch"},
              {"сутулість": 16, "голова": -10, "руки": 12, "стійка": 6, "темп": 1.1}),
    "нежить": ({"Idle": "U2:Zombie_Idle_Loop", "Walk": "U2:Zombie_Walk_Fwd_Loop",
                "Attack": "U2:Zombie_Scratch", "Attack2": "U1:Punch_Cross"},
               {"сутулість": 14, "голова": -8, "руки": 6, "стійка": 3, "темп": 0.92}),
    "кастер": ({"Idle": "U1:Idle_Loop", "Attack": "U1:Spell_Simple_Shoot", "Attack2": "U2:OverhandThrow",
                "Hit2": "U1:Hit_Head"},
               {"сутулість": 8, "голова": -3, "руки": 3, "стійка": 2, "темп": 1.0}),
    # UAL не має лука: постріл з пістоля дзеркально — ліва рука з луком витягнута на ціль
    "лучник": ({"Idle": "U1:Idle_Loop", "Attack": "дзеркало:U1:Pistol_Shoot", "Attack2": "U1:Punch_Jab",
                "Cast": "дзеркало:U1:Pistol_Aim_Neutral"},
               {"сутулість": 4, "голова": -2, "руки": 3, "стійка": 4, "темп": 1.05}),
    "воїн": ({"Idle": "U1:Sword_Idle"},
             {"сутулість": 6, "голова": -3, "руки": 5, "стійка": 4, "темп": 1.0}),
}
# ключові слова (нижній регістр, основи) → манера; перша, що збіглась, у порядку списку
SLOVA = [
    ("щит", ("щит",)),
    ("лучник", ("лучник", " лук", "арбалет")),
    ("кастер", ("шаман", "жрец", "жриц", "маг", "чаклун", "відьм", "посох", "жезл", "бубон",
                "книг", "ритуал", "некромант", "заклин")),
    ("нежить", ("зомбі", "кадавр", "мрець", "упир", "гуль", "мумі", "скелет", "нежит", "гнилі")),
    ("важка", ("молот", "сокир", "булав", "громил", "велет", "кийок", "дубин", "колос", "голем")),
    ("кігті", ("кігт", "пазур", "лапи", "руки.")),
]


def manera(vyd):
    b = {x["назва"]: x for x in json.load(open(BEST))}[vyd]
    om = b.get("опис моделі", {})
    zbroia = (om.get("зброя") or "").lower()
    tekst = (vyd + " " + zbroia + " " + " ".join(v for v in om.values() if isinstance(v, str))).lower()
    nazva = "воїн"
    for m, slova in SLOVA:
        # зброя важить більше за опис: спершу шукаємо в ній і в назві
        if any(s in (" " + vyd + " " + zbroia).lower() for s in slova):
            nazva = m
            break
    else:
        for m, slova in SLOVA:
            if any(s in tekst for s in slova):
                nazva = m
                break
    klipy = dict(BAZA)
    klipy.update(MANERY[nazva][0])
    pocherk = dict(MANERY[nazva][1])
    # свій зсув виду — сталий (з назви), ±25 % від манери
    h = hashlib.sha1(vyd.encode()).digest()
    for i, k in enumerate(("сутулість", "голова", "руки", "стійка")):
        pocherk[k] = round(pocherk.get(k, 0) * (0.75 + 0.5 * h[i] / 255), 1)
    zrist = float(b.get("вигляд", {}).get("розмір") or 2.0)
    # більший — повільніший (крок довший): темп ∝ (2 м / зріст)^0,35
    pocherk["темп"] = round(pocherk.get("темп", 1.0) * (2.0 / zrist) ** 0.35, 3)
    khvist = (om.get("хвіст") or "").strip().rstrip(".").lower() not in ("", "немає", "нема")
    return {"вид": vyd, "манера": nazva, "зріст": zrist, "хвіст": khvist, "кліпи": klipy,
            "почерк": pocherk}


if __name__ == "__main__":
    r = manera(sys.argv[1])
    s = json.dumps(r, ensure_ascii=False, indent=1)
    if len(sys.argv) > 2:
        open(sys.argv[2], "w").write(s)
    print(s)
