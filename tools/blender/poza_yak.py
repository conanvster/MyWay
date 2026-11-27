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
# --донор-сітка <glb>: донор сам знятий не в спокої, а в позі свого скульпту (людина-чоловік «з
# нуля»: 3-сітка/<модель>.glb, вершини в порядку «Тіло» донора) — поворот кожної кістки з
# вершин, що на ній (вага > 0,6), найменшими квадратами (Кабш), напрям = поворот × напрям у спокої
if "--донор-сітка" in A:
    dt = next(o for o in dst.objects if o is not None and o.type == "MESH" and o.name.split(".")[0] == "Тіло")
    BRd = np.array([dt.matrix_world @ v.co for v in dt.data.vertices])
    pered = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=A[A.index("--донор-сітка") + 1])
    sm = next(o for o in bpy.data.objects if o not in pered and o.type == "MESH")
    import bmesh
    bm_ = bmesh.new()
    bm_.from_mesh(sm.data)
    bmesh.ops.remove_doubles(bm_, verts=bm_.verts, dist=1e-5)   # як vvesty() в odiah_zona.py
    bm_.to_mesh(sm.data)
    bm_.free()
    BVd = np.array([sm.matrix_world @ v.co for v in sm.data.vertices])
    for o in [o for o in bpy.data.objects if o not in pered]:
        bpy.data.objects.remove(o)
    if len(BVd) != len(BRd):
        raise SystemExit("[поза] ‼ сітка донора (%d) не та, що «Тіло» донора (%d)" % (len(BVd), len(BRd)))
    gi = {g.index: g.name for g in dt.vertex_groups}
    for k in KISTKY:
        for bik in ("_l", "_r"):
            nm = k + bik
            if nm not in NAP:
                continue
            idx = [v.index for v in dt.data.vertices if any(gi[g.group] == nm and g.weight > 0.6 for g in v.groups)]
            if len(idx) < 10:
                continue
            X, Y = BRd[idx] - BRd[idx].mean(0), BVd[idx] - BVd[idx].mean(0)
            U, _, Vt = np.linalg.svd(X.T @ Y)
            Rm = (U @ np.diag([1, 1, np.sign(np.linalg.det(U @ Vt))]) @ Vt).T
            NAP[nm] = Vector(Rm @ np.array(NAP[nm])).normalized()
            print("[поза] донор %s у позі скульпту: %d вершин" % (nm, len(idx)), flush=True)

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
