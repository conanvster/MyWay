"""Скелет поверх сітки (09.11.2026): усі кістки — кольорові трубки (хребет і
голова — білі, ліва рука — червона, права — синя, ноги — зелені, пальці —
жовті), тіло напівпрозоре, спокій скелета; спереду, збоку й рука зблизька.

    blender -b <файл.blend> -P tools/blender/skelet_render.py -- <вихід-префікс>
"""
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector

OUT = sys.argv[sys.argv.index("--") + 1]
rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
rig.data.pose_position = "REST"
mw = rig.matrix_world


def kolir(n):
    if n.split("_")[0] in ("thumb", "index", "middle", "ring", "pinky"):
        return (1, 0.85, 0)
    if n.endswith("_l") and n.split("_")[0] in ("clavicle", "upperarm", "lowerarm", "hand"):
        return (1, 0.15, 0.1)
    if n.endswith("_r") and n.split("_")[0] in ("clavicle", "upperarm", "lowerarm", "hand"):
        return (0.1, 0.35, 1)
    if n.split("_")[0] in ("thigh", "calf", "foot", "ball"):
        return (0.1, 0.8, 0.2)
    return (1, 1, 1)


for o in bpy.data.objects:
    if o.type == "MESH":
        for md in o.modifiers:
            if md.type == "ARMATURE":
                md.show_render = md.show_viewport = False
        mt = bpy.data.materials.new("тіло")
        mt.diffuse_color = (0.6, 0.6, 0.6, 1)
        o.data.materials.clear()
        o.data.materials.append(mt)
grupy = {}
for b in rig.data.bones:
    if b.name == "root":
        continue
    h, t = mw @ b.head_local, mw @ b.tail_local
    d = t - h
    if d.length < 1e-4:
        continue
    k = kolir(b.name)
    bm = grupy.setdefault(k, bmesh.new())
    r = 0.006 if k == (1, 0.85, 0) else 0.012
    res = bmesh.ops.create_cone(bm, cap_ends=True, segments=10, radius1=r, radius2=r * 0.4, depth=d.length)
    q = Vector((0, 0, 1)).rotation_difference(d.normalized())
    for v in res["verts"]:
        v.co = q @ v.co + (h + t) / 2
    sf = bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=6, radius=r * 1.3)
    for v in sf["verts"]:
        v.co = v.co + h
for k, bm in grupy.items():
    me = bpy.data.meshes.new("кістки")
    bm.to_mesh(me)
    ob = bpy.data.objects.new("кістки", me)
    bpy.context.scene.collection.objects.link(ob)
    mt = bpy.data.materials.new("к")
    mt.diffuse_color = (*k, 1)
    me.materials.append(mt)
    ob.show_in_front = True
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.color_type = "MATERIAL"
sc.display.shading.show_xray = True
sc.display.shading.xray_alpha = 0.35
sc.render.resolution_x, sc.render.resolution_y = 1400, 1400
cam = bpy.data.objects.new("c", bpy.data.cameras.new("c"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.type = "ORTHO"
for nazva, d, c, sz in (("перед", (0, 1, 0), (0, 0, 0.95), 2.1), ("бік", (-1, 0, 0), (0, 0, 0.95), 2.1),
                        ("рука-л", (0, 1, 0), (0.6, 0, 1.05), 0.75), ("рука-л-згори", (0, 0, -1), (0.6, -0.1, 1.05), 0.75)):
    d = Vector(d)
    cam.data.ortho_scale = sz
    cam.location = Vector(c) - d * 3
    if abs(d.z) < 0.9:                       # погляд збоку — вертикаль кадру = Z світу
        cam.rotation_euler = (1.5708, 0, {(0, 1, 0): 0.0, (-1, 0, 0): 1.5708}.get(tuple(round(x) for x in d), 0.0))
    else:
        cam.rotation_euler = (0, 0, 0)
    sc.render.filepath = "%s-%s.png" % (OUT, nazva)
    bpy.ops.render.render(write_still=True)
print("[скелет] готово", OUT)
