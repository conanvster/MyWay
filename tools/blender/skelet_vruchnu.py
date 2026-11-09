"""Файл для ручного ставлення суглобів орка-пілота (09.11.2026).

Слово замовника: «бачу помилки в сітці - скелеті орка, можливо можу
допомогти зробити привязку?». Тіло й скелет у спокої, скелет — палички
поверх тіла з назвами кісток, тіло не виділяється (не зсунути випадково).

    blender -b <орк.blend> -P tools/blender/skelet_vruchnu.py -- <вихід.blend>
"""
import sys

import bpy

VYKHID = sys.argv[sys.argv.index("--") + 1]
rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
rig.data.pose_position = "REST"
rig.data.display_type = "STICK"
rig.data.show_names = True
rig.show_in_front = True
for o in bpy.data.objects:
    if o.type == "MESH":
        o.hide_select = True
for sc in bpy.data.screens:
    for ar in sc.areas:
        if ar.type == "VIEW_3D":
            for sp in ar.spaces:
                if sp.type == "VIEW_3D":
                    sp.shading.show_xray = True
                    sp.shading.xray_alpha = 0.5
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
bpy.ops.wm.save_as_mainfile(filepath=VYKHID)
print("[скелет вручну] →", VYKHID)
