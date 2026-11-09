"""Кисті, поставлені замовником вручну (`kysti_ruchno.py`) → аватар (09.11.2026).

Бере з файлу посадки кисті одного варіанта (положення, поворот і розмір —
як поставив замовник), застосовує перетворення, ваги — від кісток скелета
(Blender «автоматичні ваги»: кисть, пальці й передпліччя), решта варіантів —
геть. Далі `pilot_eksport.py` — рухи й GLB.

    blender -b <kysti-vruchnu.blend> -P tools/blender/kysti_z_ruchnoho.py -- <варіант, напр. s2203> <вихід.blend>
"""
import sys

import bpy

A = sys.argv[sys.argv.index("--") + 1:]
VAR, VYKHID = A[0], A[1]
rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
RUKA = ("hand_", "thumb_", "index_", "middle_", "ring_", "pinky_", "lowerarm_")


def log(*a):
    print("[вручну]", *a, flush=True)


for ob in [o for o in bpy.data.objects if o.type == "MESH" and o.name.startswith("Кисть-")]:
    if not ob.name.endswith(VAR):
        bpy.data.objects.remove(ob)
kysti = [o for o in bpy.data.objects if o.type == "MESH" and o.name.startswith("Кисть-")]
assert len(kysti) == 2, [o.name for o in kysti]
rig.data.pose_position = "POSE"
for pb in rig.pose.bones:
    pb.matrix_basis.identity()
for ob in kysti:
    log(ob.name, "розташування", tuple(round(x, 3) for x in ob.location),
        "поворот", tuple(round(x, 3) for x in ob.rotation_euler), "розмір", tuple(round(x, 3) for x in ob.scale))
    ob.hide_select = False
    ob.hide_set(False)
    for o in bpy.context.selected_objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # ваги від кісток: лише кисть, пальці й передпліччя свого боку
    bik = "_l" if "ліва" in ob.name else "_r"
    ob.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    for g in list(ob.vertex_groups):
        if not (g.name.endswith(bik) and g.name.startswith(RUKA)):
            ob.vertex_groups.remove(g)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.vertex_group_normalize_all(lock_active=False)
    ob.name = ob.data.name = ob.name.rsplit("-", 1)[0]
    log(ob.name, "ваги:", len(ob.vertex_groups), "груп")
bpy.ops.wm.save_as_mainfile(filepath=VYKHID)
log("→", VYKHID)
