"""Тіло моделі в позі іншої моделі (27.11.2026, слово замовника: «ельфійка в позі T, а сет в позі А»).

Скульпти зон сету знято з кадру тіла-донора в його позі (людина-жінка MPFB — спокій, А-поза);
щоб сумістити їх з іншою моделлю, її тіло ставиться в ту саму позу: кожна кістка списку
повертається навколо своєї голови так, щоб її напрям у світі збігся з напрямом тієї ж кістки
донора (донор — у спокої). Вершини «Тіло» після скелета → .npy (той самий порядок, що в моделі) —
для `odiah_zona.py --сітка <.npy>`.

    blender -b <модель.blend> -P tools/blender/poza_yak.py -- <донор.blend> <вихід.npy>
"""
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

A = sys.argv[sys.argv.index("--") + 1:]
DONOR, OUT = A[0], A[1]
KISTKY = ["clavicle", "upperarm", "lowerarm", "thigh", "calf", "foot"]   # кисть — ні: у донора інший напрям кістки кисті, поворот крутить зап'ястя

# напрями кісток донора (світ, спокій)
with bpy.data.libraries.load(DONOR) as (src, dst):
    dst.objects = [n for n in src.objects]
don = next(o for o in dst.objects if o is not None and o.type == "ARMATURE")
dw = don.matrix_world
NAP = {}
for b in don.data.bones:
    NAP[b.name] = ((dw @ b.tail_local) - (dw @ b.head_local)).normalized()

rig = next(o for o in bpy.data.objects if o.type == "ARMATURE" and o.library is None and o.name in bpy.context.scene.objects)
aw = rig.matrix_world
for pb in rig.pose.bones:
    pb.matrix_basis.identity()
bpy.context.view_layer.update()
for k in KISTKY:
    for bik in ("_l", "_r"):
        nm = k + bik
        if nm not in rig.pose.bones or nm not in NAP:
            continue
        pb = rig.pose.bones[nm]
        h, t = aw @ pb.head, aw @ pb.tail
        q = (t - h).normalized().rotation_difference(NAP[nm])
        pb.matrix = aw.inverted() @ (Matrix.Translation(h) @ q.to_matrix().to_4x4() @ Matrix.Translation(-h)) @ aw @ pb.matrix
        bpy.context.view_layer.update()
        print("[поза] %s: поворот %.1f°" % (nm, np.degrees(q.angle)), flush=True)
tilo = bpy.data.objects["Тіло"]
dg = bpy.context.evaluated_depsgraph_get()
ev = tilo.evaluated_get(dg)
me = ev.to_mesh()
P = np.array([ev.matrix_world @ v.co for v in me.vertices], np.float32)
ev.to_mesh_clear()
if len(P) != len(tilo.data.vertices):
    raise SystemExit("[поза] ‼ кількість вершин після скелета інша")
np.save(OUT, P)
print("[поза] → %s: %d вершин, зріст %.3f" % (OUT, len(P), P[:, 2].max() - P[:, 2].min()), flush=True)
