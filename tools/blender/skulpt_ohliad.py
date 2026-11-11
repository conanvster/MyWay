"""Огляд сітки: 4 кадри в ряд — колір спереду й у три чверті, глина збоку й у три чверті ззаду.

    blender -b --factory-startup -P tools/blender/skulpt_ohliad.py -- <сітка.glb|.blend> <аркуш.png> \
        [--голова]   # рамка лише на верхні 20 % (обличчя моделі на повний зріст)
"""
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Vector

A = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = os.path.abspath(A[0]), os.path.abspath(A[1])
if SRC.endswith(".blend"):
    bpy.ops.wm.open_mainfile(filepath=SRC)
else:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
ms = [o for o in bpy.data.objects if o.type == "MESH" and o.name != "Icosphere" and not o.hide_render]
P = np.array([(o.matrix_world @ v.co)[:] for o in ms for v in o.data.vertices])
lo, hi = P.min(0), P.max(0)
print("[огляд] вершин %d, розмір %s" % (len(P), np.round(hi - lo, 3)))
if "--голова" in A:
    lo = lo.copy()
    lo[2] = hi[2] - (hi[2] - lo[2]) * 0.2
    m = P[:, 2] > lo[2]
    lo[0], hi[0] = P[m, 0].min(), P[m, 0].max()
c = (lo + hi) / 2
S = max(hi[0] - lo[0], hi[2] - lo[2]) * 1.1

sc = bpy.context.scene
sc.render.engine = "BLENDER_EEVEE"
sc.render.resolution_x = sc.render.resolution_y = 900
sc.view_settings.view_transform = "Standard"
w = bpy.data.worlds.new("w")
sc.world = w
w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.22, 0.22, 0.24, 1)
w.node_tree.nodes["Background"].inputs[1].default_value = 0.6
cam = bpy.data.objects.new("кам", bpy.data.cameras.new("кам"))
sc.collection.objects.link(cam)
cam.data.type = "ORTHO"
cam.data.ortho_scale = S
cam.data.clip_end = 50
sc.camera = cam
for i, (e, k) in enumerate([(3.0, (55, 0, 35)), (1.2, (60, 0, -120))]):
    L = bpy.data.objects.new("св%d" % i, bpy.data.lights.new("св%d" % i, "SUN"))
    L.data.energy = e
    L.rotation_euler = [math.radians(a) for a in k]
    sc.collection.objects.link(L)

hlyna = bpy.data.materials.new("глина")
hlyna.use_nodes = True
b = hlyna.node_tree.nodes["Principled BSDF"]
b.inputs["Base Color"].default_value = (0.6, 0.58, 0.55, 1)
b.inputs["Roughness"].default_value = 0.6
stari = {o: [s.material for s in o.material_slots] for o in ms}
kadry = []
for i, (kut, glina) in enumerate([(0, False), (40, False), (90, True), (215, True)]):
    for o in ms:
        if not o.material_slots:
            o.data.materials.append(None)
        for j, s in enumerate(o.material_slots):
            s.material = hlyna if glina else (stari[o][j] if j < len(stari[o]) else None)
    a = math.radians(kut)
    cam.location = (c[0] + math.sin(a) * 10, c[1] - math.cos(a) * 10, c[2])
    cam.rotation_euler = (math.pi / 2, 0, a)
    f = OUT + ".%d.png" % i
    sc.render.filepath = f
    bpy.ops.render.render(write_still=True)
    kadry.append(f)
ims = [bpy.data.images.load(f) for f in kadry]
n = 900
ark = np.zeros((n, n * 4, 4), np.float32)
for i, im in enumerate(ims):
    ark[:, i * n:(i + 1) * n] = np.array(im.pixels[:], np.float32).reshape(n, n, 4)
o = bpy.data.images.new("ark", n * 4, n)
o.pixels = ark.ravel()
o.filepath_raw = OUT
o.file_format = "PNG"
o.save()
for f in kadry:
    os.remove(f)
print("[огляд] →", OUT)
