#!/usr/bin/env python3
"""Латка готового GLB без переекспорту (П-281, 09.11.2026).

Пілот орка: в `орк-пілот.glb` очі (`high-poly`) посилались на білу заглушку
1×1 (`Image`) замість `brown_eye` — у грі очі світились білим; зайва сітка
брів `eyebrow010` (брови — набори `Брови-<n>`) — білі дуги над очима.

    python3 tools/glb_latka.py <модель.glb> [--текстура <матеріал> <картинка.png>]... \
        [--прибрати <частина назви вузла>]...
Файл переписується на місці (копія — <модель>.glb.bak).
"""
import json
import shutil
import struct
import sys

A = sys.argv[1:]
GLB = A[0]
TEKSTURY, PRYBRATY = [], []
i = 1
while i < len(A):
    if A[i] == "--текстура":
        TEKSTURY.append((A[i + 1], A[i + 2]))
        i += 3
    elif A[i] == "--прибрати":
        PRYBRATY.append(A[i + 1])
        i += 2
    else:
        sys.exit("невідомий аргумент: " + A[i])

dani = open(GLB, "rb").read()
magic, ver, _ = struct.unpack("<III", dani[:12])
assert magic == 0x46546C67, "не GLB"
n_j, _ = struct.unpack("<II", dani[12:20])
j = json.loads(dani[20:20 + n_j])
p = 20 + n_j
n_b, _ = struct.unpack("<II", dani[p:p + 8])
bin_ = bytearray(dani[p + 8:p + 8 + n_b])

for mat_im, png in TEKSTURY:
    mats = [m for m in j["materials"] if mat_im in m["name"]]
    if not mats:
        sys.exit("немає матеріалу «%s»" % mat_im)
    while len(bin_) % 4:
        bin_.append(0)
    bajty = open(png, "rb").read()
    j["bufferViews"].append({"buffer": 0, "byteOffset": len(bin_), "byteLength": len(bajty)})
    bin_ += bajty
    j["images"].append({"bufferView": len(j["bufferViews"]) - 1, "mimeType": "image/png",
                        "name": png.rsplit("/", 1)[-1].rsplit(".", 1)[0].split("_", 1)[-1]})
    j["textures"].append({"sampler": 0, "source": len(j["images"]) - 1})
    for m in mats:
        m.setdefault("pbrMetallicRoughness", {})["baseColorTexture"] = {"index": len(j["textures"]) - 1}
        print("текстура:", m["name"], "→", png)

for chastyna in PRYBRATY:
    vuzly = {k for k, n in enumerate(j["nodes"]) if chastyna in n.get("name", "")
             or ("mesh" in n and chastyna in j["meshes"][n["mesh"]]["name"])}
    if not vuzly:
        sys.exit("немає вузла «%s»" % chastyna)
    for n in j["nodes"]:
        if "children" in n:
            n["children"] = [c for c in n["children"] if c not in vuzly]
    for s in j["scenes"]:
        s["nodes"] = [c for c in s["nodes"] if c not in vuzly]
    print("прибрано вузли:", [j["nodes"][k].get("name") for k in vuzly])

j["buffers"][0]["byteLength"] = len(bin_)
js = json.dumps(j, ensure_ascii=False, separators=(",", ":")).encode()
js += b" " * (-len(js) % 4)
while len(bin_) % 4:
    bin_.append(0)
shutil.copy(GLB, GLB + ".bak")
with open(GLB, "wb") as f:
    f.write(struct.pack("<III", magic, ver, 12 + 8 + len(js) + 8 + len(bin_)))
    f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
    f.write(struct.pack("<II", len(bin_), 0x004E4942) + bytes(bin_))
print("→", GLB)
