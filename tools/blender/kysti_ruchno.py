"""Файл для ручної посадки кистей орка-пілота (09.11.2026).

Слово замовника: «чи можу я якось допомогти поєднати частини? схоже ти не
розрізняєш деталей». Тіло В (Pixal3D, скелет підігнано) + згенеровані кисті
кожного варіанта окремими колекціями; точка обертання кисті — на голові
кістки кисті (зап'ястя), скелет — палички поверх моделі.

    blender -b <орк-k<перший>.blend> -P tools/blender/kysti_ruchno.py -- <вихід.blend> <орк-k<інший>.blend>…
"""
import sys

import bpy
from mathutils import Vector

A = sys.argv[sys.argv.index("--") + 1:]
VYKHID, INSHI = A[0], A[1:]
rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")


def zibraty(mitka):
    kol = bpy.data.collections.new("кисті-" + mitka)
    bpy.context.scene.collection.children.link(kol)
    return kol


def pidhotuvaty(ob, mitka, kol):
    for md in list(ob.modifiers):
        ob.modifiers.remove(md)
    for g in list(ob.vertex_groups):
        ob.vertex_groups.remove(g)
    ob.parent = None
    bik = "l" if ob.name.endswith("ліва") or "ліва" in ob.name else "r"
    zap = rig.matrix_world @ rig.data.bones["hand_" + bik].head_local
    # точка обертання — зап'ястя скелета
    me = ob.data
    for v in me.vertices:
        v.co = v.co - (zap - ob.location)
    ob.location = zap
    ob.name = "Кисть-%s-%s" % ("ліва" if bik == "l" else "права", mitka)
    for c in list(ob.users_collection):
        c.objects.unlink(ob)
    kol.objects.link(ob)


perva = bpy.path.basename(bpy.data.filepath).split("-k")[-1].split(".")[0]
kol = zibraty(perva)
for ob in [o for o in bpy.data.objects if o.type == "MESH" and o.name.startswith("Кисть-")]:
    pidhotuvaty(ob, perva, kol)
for f in INSHI:
    mitka = bpy.path.basename(f).split("-k")[-1].split(".")[0]
    with bpy.data.libraries.load(f) as (src, dst):
        dst.objects = [n for n in src.objects if n.startswith("Кисть-")]
    kol = zibraty(mitka)
    for ob in dst.objects:
        bpy.context.scene.collection.objects.link(ob)
        pidhotuvaty(ob, mitka, kol)
    kol.hide_viewport = False
rig.data.pose_position = "REST"
rig.data.display_type = "STICK"
rig.show_in_front = True
for o in bpy.data.objects:
    if o.type == "MESH" and o.name == "Тіло":
        o.hide_select = True
bpy.ops.wm.save_as_mainfile(filepath=VYKHID)
print("[вручну] →", VYKHID, [o.name for o in bpy.data.objects if o.name.startswith("Кисть-")])
