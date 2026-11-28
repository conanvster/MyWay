# Ігрова сітка з сирої (П-297): зварити, спростити до N граней, гладкі нормалі. Колір проєктувати
# ПІСЛЯ цього (proektsiia_4.py) — спрощення по готовій розгортці рвало текстуру.
#   blender -b -P tools/blender/sproshchennia.py -- <сира.glb> <вихід.glb> [--граней 40000]
import os
import sys

import bpy

A = sys.argv[sys.argv.index("--") + 1:]
N = int(A[A.index("--граней") + 1]) if "--граней" in A else 40000
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.abspath(A[0]))
ms = [o for o in bpy.data.objects if o.type == "MESH"]
for o in ms:
    mw = o.matrix_world.copy()
    o.parent = None
    o.matrix_world = mw
for o in list(bpy.data.objects):
    if o.type != "MESH":
        bpy.data.objects.remove(o)
bpy.ops.object.select_all(action="SELECT")
bpy.context.view_layer.objects.active = ms[0]
if len(ms) > 1:
    bpy.ops.object.join()
o = bpy.context.view_layer.objects.active
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
# воксельна перебудова (крок 1/400 зросту): суцільна, з однаково повернутими гранями. Пряме
# спрощення сирої сітки Hunyuan/TRELLIS давало зім'яту поверхню з гранями врізнобіч (медіанний
# кут між сусідніми 70°): гранчасте світло, розгортка на окремі грані, порожня текстура
f_syri = len(o.data.polygons)
rm = o.modifiers.new("в", "REMESH")
rm.mode = "VOXEL"
rm.voxel_size = o.dimensions.z / 400
bpy.ops.object.modifier_apply(modifier=rm.name)
f0 = len(o.data.polygons)
if f0 > N:
    d = o.modifiers.new("с", "DECIMATE")
    d.ratio = N / f0
    bpy.ops.object.modifier_apply(modifier=d.name)
for p in o.data.polygons:
    p.use_smooth = True
bpy.ops.export_scene.gltf(filepath=os.path.abspath(A[1]), export_format="GLB")
print("[спрощення] %d → воксель → %d граней, %d вершин → %s" % (f_syri, len(o.data.polygons), len(o.data.vertices), A[1]))
