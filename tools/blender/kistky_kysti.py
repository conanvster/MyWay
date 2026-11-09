"""Звіт про кістки кистей (09.11.2026): кожна кістка — батько, довжина,
розрив між кінцем батька й початком дитини; пальці — порядок поперек долоні.

    blender -b <файл.blend> -P tools/blender/kistky_kysti.py
"""
import bpy
import numpy as np

rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
mw = rig.matrix_world
PALTSI = ("thumb", "index", "middle", "ring", "pinky")
for bik in ("l", "r"):
    vsi = [b for b in rig.data.bones if b.name.endswith("_" + bik)
           and b.name.split("_")[0] in PALTSI + ("hand",)]
    print("== кисть", bik, "кісток:", len(vsi), "(очікується 16)")
    h = rig.data.bones["hand_" + bik]
    hh, ht = np.array((mw @ h.head_local)[:]), np.array((mw @ h.tail_local)[:])
    print("  hand  довж %.3f" % np.linalg.norm(ht - hh))
    os_ = (ht - hh) / np.linalg.norm(ht - hh)
    for p in PALTSI:
        ryad = []
        for j in (1, 2, 3):
            b = rig.data.bones["%s_%02d_%s" % (p, j, bik)]
            he, te = np.array((mw @ b.head_local)[:]), np.array((mw @ b.tail_local)[:])
            rozryv = np.linalg.norm(he - np.array((mw @ b.parent.tail_local)[:])) if j > 1 else np.linalg.norm(he - hh)
            ryad.append("%s: довж %.3f, від батька %.3f" % (b.name, np.linalg.norm(te - he), rozryv))
        b1 = rig.data.bones["%s_01_%s" % (p, bik)]
        osn = np.array((mw @ b1.head_local)[:])
        b3 = rig.data.bones["%s_03_%s" % (p, bik)]
        kin = np.array((mw @ b3.tail_local)[:])
        print("  %-6s основа %s кінчик %s | %s" % (p, osn.round(3), kin.round(3), " ; ".join(ryad)))
    # інші кістки, що дочірні до кисті чи пальців
    dity = [b.name for b in rig.data.bones if b.parent and b.parent.name.endswith("_" + bik)
            and b.parent.name.split("_")[0] in PALTSI + ("hand",) and b.name.split("_")[0] not in PALTSI]
    print("  інші діти кисті/пальців:", dity)
print("усього кісток у скелеті:", len(rig.data.bones))
