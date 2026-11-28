# Аркуш рухів моделі монстра (П-297): ряд — рух, 5 кадрів по довжині руху, вигляд 3/4 спереду.
#   blender -b <модель.blend> -P tools/blender/monstr_kadry.py -- <вихід.png> [--рухи Idle,Run,…]
import math
import os
import sys

import bpy
from mathutils import Vector

A = sys.argv[sys.argv.index("--") + 1:]
VYHID = os.path.abspath(A[0])
RUKHY = (A[A.index("--рухи") + 1].split(",") if "--рухи" in A else
         ["Idle", "Walk", "Run", "Attack", "Attack2", "Cast", "Hit", "Hit2", "Death", "Death2"])
sc = bpy.context.scene
rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
tilo = next((o for o in bpy.data.objects if o.type == "MESH" and o.name == "Тіло"),
            next(o for o in bpy.data.objects if o.type == "MESH"))
for tr in rig.animation_data.nla_tracks:
    tr.mute = True
H = max(v.co.z for v in tilo.data.vertices)   # спокій, не поточний рух
sc.render.engine = "BLENDER_EEVEE"
sc.render.resolution_x, sc.render.resolution_y = 300, 330
sc.render.film_transparent = False
sc.world = bpy.data.worlds.new("тло")
sc.world.use_nodes = True
bg = sc.world.node_tree.nodes["Background"]
bg.inputs[0].default_value = (0.75, 0.75, 0.77, 1)
bg.inputs[1].default_value = 1.2          # рівне світло з усіх боків, як на аркушах
sun = bpy.data.objects.new("с", bpy.data.lights.new("с", "SUN"))
sun.data.energy = 1.5
sun.rotation_euler = (math.radians(50), 0, math.radians(30))
sc.collection.objects.link(sun)
sc.view_settings.view_transform = "Standard"
cam = bpy.data.objects.new("к", bpy.data.cameras.new("к"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.type = "ORTHO"
cam.data.ortho_scale = H * 1.3
a = math.radians(35)
cam.location = Vector((math.sin(a) * 10, -math.cos(a) * 10, H * 0.55))
cam.rotation_euler = (math.pi / 2, 0, a)
import tempfile
tmp = tempfile.mkdtemp()
kadry = []
for r in RUKHY:
    dia = bpy.data.actions.get(r)
    if dia is None:
        continue
    rig.animation_data.action = dia
    if hasattr(rig.animation_data, "action_slot") and dia.slots:
        rig.animation_data.action_slot = dia.slots[0]
    f0, f1 = dia.frame_range
    ryad = []
    for i in range(5):
        f = f0 + (f1 - f0) * i / 4
        sc.frame_set(int(f), subframe=f - int(f))
        p = os.path.join(tmp, "%s-%d.png" % (r, i))
        sc.render.filepath = p
        bpy.ops.render.render(write_still=True)
        ryad.append(p)
    kadry.append((r, ryad))
# склеїти без PIL: через зображення Blender
W, Hh = 300, 330
out = bpy.data.images.new("аркуш", W * 5 + 120, Hh * len(kadry))
px = [0.95] * (4 * out.size[0] * out.size[1])
import numpy as np
big = np.full((Hh * len(kadry), W * 5 + 120, 4), 0.95, np.float32)
for j, (r, ryad) in enumerate(kadry):
    for i, p in enumerate(ryad):
        im = bpy.data.images.load(p)
        a_ = np.array(im.pixels[:], np.float32).reshape(Hh, W, 4)
        y0 = (len(kadry) - 1 - j) * Hh
        big[y0:y0 + Hh, 120 + i * W:120 + (i + 1) * W] = a_
out.pixels = big.ravel()
out.filepath_raw = VYHID
out.file_format = "PNG"
out.save()
open(VYHID[:-4] + ".txt", "w").write("\n".join(r for r, _ in kadry))
print("[кадри-рухів] →", VYHID, len(kadry))
