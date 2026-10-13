"""OBJ для Mixamo з мітками орієнтації (13.10.2026).

Порядок з `spec/аватар-ельфійка-mixamo.md` §3.1: пластина 15 см перед
животом і кулька біля **лівого** стегна поза силуетом — у вікні Orient
кулька праворуч від глядача = обличчям до камери (сірий силует без міток
двічі привів до розвороту задом наперед). Мітки на гру не впливають: сітку
Mixamo при збиранні викидаємо. Модель у Blender дивиться на −Y, отже ліве
стегно — +X.

    blender -b --factory-startup -P tools/blender/mixamo_mitky.py -- <основа.blend> <вихід.obj>
"""
import sys

import bpy
from mathutils import Vector

a = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.open_mainfile(filepath=a[0])
tilo = [o for o in bpy.context.scene.objects if o.type == "MESH"]
vs = [o.matrix_world @ v.co for o in tilo for v in o.data.vertices]
z0 = min(v.z for v in vs)
H = max(v.z for v in vs) - z0

# живіт — смуга 55…62% зросту; найближча до глядача точка
zhyvit = [v for v in vs if z0 + 0.55 * H < v.z < z0 + 0.62 * H]
pered = min(v.y for v in zhyvit)
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, pered - 0.08, z0 + 0.585 * H))
p = bpy.context.object
p.name = "мітка-пластина"
p.scale = (0.15, 0.01, 0.15)

# ліве стегно — смуга 40…48% зросту, x > 0
stehno = [v for v in vs if z0 + 0.40 * H < v.z < z0 + 0.48 * H and v.x > 0]
bik = max(v.x for v in stehno)
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.04, location=(bik + 0.10, 0, z0 + 0.44 * H))
bpy.context.object.name = "мітка-кулька"

print("[мітки] зріст %.3f, перед живота y %.3f, бік стегна x %.3f" % (H, pered, bik))
bpy.ops.wm.obj_export(filepath=a[1], export_selected_objects=False,
                      export_materials=False, forward_axis="NEGATIVE_Z", up_axis="Y")
print("[мітки] →", a[1])
