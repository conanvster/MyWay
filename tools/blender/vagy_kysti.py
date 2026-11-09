"""Перевірка зв'язку скелета з кистю (09.11.2026): кістки кисті й пальців —
кольорові трубки, сітка — кольором найсильнішої кістки кожної вершини
(великий — червоний, вказівний — помаранчевий, середній — жовтий,
безіменний — зелений, мізинець — синій, кисть — фіолетовий, передпліччя —
сірий). Спокій скелета, три ракурси.

    blender -b <файл.blend> -P tools/blender/vagy_kysti.py -- <вихід-префікс> [l|r]
"""
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector

A = sys.argv[sys.argv.index("--") + 1:]
OUT, BIK = A[0], (A[1] if len(A) > 1 else "l")
rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
rig.data.pose_position = "REST"
KOL = {"thumb": (1, 0.1, 0.1), "index": (1, 0.55, 0), "middle": (1, 1, 0), "ring": (0.1, 0.9, 0.1),
       "pinky": (0.1, 0.3, 1), "hand": (0.7, 0.2, 0.9), "lowerarm": (0.5, 0.5, 0.5)}


def kolir(nazva):
    for k, c in KOL.items():
        if nazva.startswith(k + "_") and nazva.endswith("_" + BIK):
            return c
    return None


sitky = [o for o in bpy.data.objects if o.type == "MESH" and o.modifiers and any(m.type == "ARMATURE" for m in o.modifiers)]
toch = []
for ob in sitky:
    me = ob.data
    vg = {g.index: g.name for g in ob.vertex_groups}
    ca = me.color_attributes.new("ваги", "FLOAT_COLOR", "POINT")
    for v in me.vertices:
        best = max(v.groups, key=lambda g: g.weight, default=None)
        c = kolir(vg[best.group]) if best is not None else None
        ca.data[v.index].color = (*(c or (0.85, 0.85, 0.85)), 1)
        if c is not None:
            toch.append((ob.matrix_world @ v.co)[:])
    me.color_attributes.active_color = ca
# кістки — трубки
bm = bmesh.new()
for b in rig.data.bones:
    if kolir(b.name) is None:
        continue
    h, t = rig.matrix_world @ b.head_local, rig.matrix_world @ b.tail_local
    d = t - h
    r = bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.004, radius2=0.002, depth=d.length)
    q = Vector((0, 0, 1)).rotation_difference(d.normalized())
    for v in r["verts"]:
        v.co = q @ v.co + (h + t) / 2
me = bpy.data.meshes.new("кістки")
bm.to_mesh(me)
kist = bpy.data.objects.new("кістки", me)
bpy.context.scene.collection.objects.link(kist)
mt = bpy.data.materials.new("кістки")
mt.diffuse_color = (0, 0, 0, 1)
me.materials.append(mt)
kist.show_in_front = True
P = np.array(toch)
c, size = (P.min(0) + P.max(0)) / 2, (P.max(0) - P.min(0)).max()
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.color_type = "VERTEX"
sc.display.shading.show_xray = True
sc.display.shading.xray_alpha = 0.6
sc.render.resolution_x = sc.render.resolution_y = 800
cam = bpy.data.objects.new("c", bpy.data.cameras.new("c"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.type = "ORTHO"
cam.data.ortho_scale = size * 1.3
for i, d in enumerate([(0, 1, 0), (0, 0, -1), (-1 if BIK == "l" else 1, 0, 0)]):
    d = Vector(d)
    cam.location = Vector(c) - d * 2
    cam.rotation_euler = d.to_track_quat("-Z", "Z" if abs(d.z) < 0.9 else "Y").to_euler()
    sc.render.filepath = "%s-%d.png" % (OUT, i)
    bpy.ops.render.render(write_still=True)
print("[ваги] вершин кисті з вагами пальців/кисті:", len(P))
