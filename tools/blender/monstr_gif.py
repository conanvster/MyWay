# Кадри для GIF рухів моделі монстра (П-297): рухи підряд, вигляд 3/4, рівне світло; склеює
# tools/monstr_gif_zbyraty.py.  blender -b <модель.blend> -P tools/blender/monstr_gif.py -- <тека>
#   [--рухи Idle,Run,Attack,Cast,Hit,Death] [--крок 2] [--розмір 360]
import math
import os
import sys

import bpy
from mathutils import Vector

A = sys.argv[sys.argv.index("--") + 1:]
TEKA = os.path.abspath(A[0])
RUKHY = A[A.index("--рухи") + 1].split(",") if "--рухи" in A else \
    ["Idle", "Walk", "Run", "Attack", "Attack2", "Cast", "Hit", "Hit2", "Death", "Death2"]
KROK = int(A[A.index("--крок") + 1]) if "--крок" in A else 2
R = int(A[A.index("--розмір") + 1]) if "--розмір" in A else 360
os.makedirs(TEKA, exist_ok=True)
sc = bpy.context.scene
rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
tilo = next((o for o in bpy.data.objects if o.type == "MESH" and o.name == "Тіло"),
            next(o for o in bpy.data.objects if o.type == "MESH"))
for tr in rig.animation_data.nla_tracks:
    tr.mute = True
H = max(v.co.z for v in tilo.data.vertices)
sc.render.engine = "BLENDER_EEVEE"
sc.render.resolution_x = sc.render.resolution_y = R
sc.view_settings.view_transform = "Standard"
sc.world = bpy.data.worlds.new("тло")
sc.world.use_nodes = True
bg = sc.world.node_tree.nodes["Background"]
bg.inputs[0].default_value = (0.62, 0.62, 0.64, 1)
bg.inputs[1].default_value = 0.9
sun = bpy.data.objects.new("с", bpy.data.lights.new("с", "SUN"))
sun.data.energy = 1.2
sun.rotation_euler = (math.radians(55), 0, math.radians(-30))
sc.collection.objects.link(sun)
cam = bpy.data.objects.new("к", bpy.data.cameras.new("к"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.type = "ORTHO"
cam.data.ortho_scale = H * 1.55
a = math.radians(35)
cam.location = Vector((math.sin(a) * 10, -math.cos(a) * 10, H * 0.5))
cam.rotation_euler = (math.pi / 2, 0, a)
n = 0
spys = []
for r in RUKHY:
    dia = bpy.data.actions.get(r)
    if dia is None:
        continue
    rig.animation_data.action = dia
    if hasattr(rig.animation_data, "action_slot") and dia.slots:
        rig.animation_data.action_slot = dia.slots[0]
    f0, f1 = (int(x) for x in dia.frame_range)
    povtor = 2 if r in ("Idle", "Walk", "Run", "Cast") and f1 - f0 < 40 else 1
    for _ in range(povtor):
        for f in range(f0, f1 + 1, KROK):
            sc.frame_set(f)
            sc.render.filepath = os.path.join(TEKA, "%04d.png" % n)
            bpy.ops.render.render(write_still=True)
            spys.append("%04d %s" % (n, r))
            n += 1
    if r.startswith("Death"):                 # полежати
        for _ in range(6):
            sc.render.filepath = os.path.join(TEKA, "%04d.png" % n)
            bpy.ops.render.render(write_still=True)
            spys.append("%04d %s" % (n, r))
            n += 1
open(os.path.join(TEKA, "рухи.txt"), "w").write("\n".join(spys))
print("[gif-кадри] %d → %s" % (n, TEKA))
