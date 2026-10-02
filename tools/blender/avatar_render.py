"""Рендер аватара для оцінки схожості з референсом (02.10.2026).

Спокій (T-поза скелета), ортокамера спереду, плоске світло Workbench —
лише колір текстури, як на референсі; тло прозоре.

    blender -b --factory-startup -P tools/blender/avatar_render.py -- \\
        <модель.gltf> <кадр.png> [перед|бік|зад]
"""
import math
import sys

import bpy
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:]
MODEL, KUDY = ARGS[0], ARGS[1]
VYD = ARGS[2] if len(ARGS) > 2 else "перед"

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=MODEL)
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
sitky = [o for o in bpy.data.objects if o.type == "MESH"]
tochky = [o.matrix_world @ v.co for o in sitky for v in o.data.vertices]
lo = Vector([min(p[i] for p in tochky) for i in range(3)])
hi = Vector([max(p[i] for p in tochky) for i in range(3)])
# Перед — за ступнями скелета (як у avatar_build): пальці попереду кісточки.
b = arm.data.bones
pered = 1 if (arm.matrix_world @ b["ball_l"].head_local).y > \
    (arm.matrix_world @ b["foot_l"].head_local).y else -1
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.light = "FLAT"
sc.display.shading.color_type = "TEXTURE"
sc.render.film_transparent = True
sc.render.resolution_x = sc.render.resolution_y = 1024
sc.view_settings.view_transform = "Standard"
kam = bpy.data.objects.new("камера", bpy.data.cameras.new("камера"))
sc.collection.objects.link(kam)
sc.camera = kam
kam.data.type = "ORTHO"
kam.data.ortho_scale = max(hi.x - lo.x, hi.z - lo.z) * 1.06
c = (lo + hi) / 2
kut = {"перед": 0.0, "бік": math.pi / 2, "зад": math.pi}[VYD]
napr = Vector((math.sin(kut), pered * math.cos(kut), 0)) * 6
kam.location = c + napr
kam.rotation_euler = (c - kam.location).to_track_quat("-Z", "Y").to_euler()
sc.render.filepath = KUDY
bpy.ops.render.render(write_still=True)
print("[рендер] →", KUDY)
