"""Перенести суглоби рук і пальців з іншого файлу (09.11.2026).

Скелет, поставлений замовником (`skelet-vruchnu*.blend`), — на нове тіло з
кадру в тій самій позі (топлес-орк): голова, хвіст і закрутка кісток руки,
кисті й пальців беруться з файлу-джерела як є (сітка лягає в той самий
зріст і центр — `rig_sitky.py`). Далі — `skelet_tiunynh.py` (центрування в
новій сітці) і `vagy_z_ruchnoho.py` (ваги).

    blender -b <нове.blend> -P tools/blender/perenesty_kistky.py -- <джерело.blend> <вихід.blend>
"""
import sys

import bpy

A = sys.argv[sys.argv.index("--") + 1:]
DZHERELO, VYKHID = A
ROD = ("upperarm", "lowerarm", "hand", "thumb", "index", "middle", "ring", "pinky")
rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
with bpy.data.libraries.load(DZHERELO) as (src, dst):
    dst.armatures = list(src.armatures)
dz = dst.armatures[0]
dani = {b.name: (b.head_local.copy(), b.tail_local.copy()) for b in dz.bones if b.name.split("_")[0] in ROD}
# закрутку беремо з edit bones джерела через тимчасовий об'єкт
tmp = bpy.data.objects.new("тимч", dz)
bpy.context.scene.collection.objects.link(tmp)
bpy.context.view_layer.objects.active = tmp
bpy.ops.object.mode_set(mode="EDIT")
roll = {b.name: b.roll for b in dz.edit_bones if b.name in dani}
bpy.ops.object.mode_set(mode="OBJECT")
bpy.data.objects.remove(tmp)
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
n = 0
for b in rig.data.edit_bones:
    if b.name in dani:
        b.head, b.tail = dani[b.name]
        b.roll = roll[b.name]
        n += 1
bpy.ops.object.mode_set(mode="OBJECT")
bpy.ops.wm.save_as_mainfile(filepath=VYKHID)
print("[перенесення] кісток перенесено:", n, "→", VYKHID, flush=True)
