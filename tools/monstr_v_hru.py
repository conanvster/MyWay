#!/usr/bin/env python3
"""Модель монстра з рухами → гра (П-297, 28.11.2026): стиснути текстури (glb_stysk.py),
покласти в game/models/own/<вид>.glb, у mobs.json → вигляд.модель усіх особин цього виду.

    python3 tools/monstr_v_hru.py <вид> <модель.glb>
"""
import json
import os
import re
import subprocess
import sys

KORIN = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
vyd, dzherelo = sys.argv[1], sys.argv[2]
kudy = os.path.join(KORIN, "game/models/own", vyd + ".glb")
subprocess.run([sys.executable, os.path.join(KORIN, "tools/glb_stysk.py"), dzherelo, kudy], check=True)
# старі витягнуті Godot текстури цієї моделі — геть (імпорт витягне нові)
for f in os.listdir(os.path.dirname(kudy)):
    if re.match(re.escape(vyd) + r"_(Image_\d+|hmv-).*\.(png|jpg)(\.import)?$", f):
        os.remove(os.path.join(os.path.dirname(kudy), f))
MOBS = os.path.join(KORIN, "game/data/mobs.json")
t = open(MOBS).read()
m = json.loads(t)
novyi = "res://models/own/%s.glb" % vyd
n = 0
for k, x in m.items():
    if isinstance(x, dict) and x.get("назва") == vyd:
        stare = x["вигляд"]["модель"]
        # точкова заміна в тексті, щоб не переформатувати весь файл
        i = t.index('"назва": "%s"' % vyd)
        j = t.index(json.dumps(stare, ensure_ascii=False), i)
        t = t[:j] + json.dumps(novyi, ensure_ascii=False) + t[j + len(json.dumps(stare, ensure_ascii=False)):]
        n += 1
json.loads(t)
open(MOBS, "w").write(t)
print("[у гру] %s → %s, mobs.json: %d" % (vyd, kudy, n))
