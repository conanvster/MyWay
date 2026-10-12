"""Основа ельфійки під авто-скелет Mixamo (12.10.2026).

Слово замовника: «дуже помітні склейки рук біля зап'ястя та ніг біля
щиколоток, та трохи вирівняв положення колін та тазу». Бере вихід
`avatar_build.py --кисті-скану` (суцільний скан, без кистей манекена),
знімає скелет манекена, згладжує наколінки (Pixal3D ліпить їх кулями) і
пише: `<тека>/основа.blend` (сітка з текстурою — для збірки в гру),
`<тека>/основа.obj` (лише форма — для завантаження в Mixamo) і заміри для
міток авто-скелета (підборіддя, зап'ястя, лікті, коліна, пах).

    blender -b --factory-startup -P tools/blender/elf_osnova.py -- <вхід.gltf> <тека>
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

a = sys.argv[sys.argv.index("--") + 1:]
src, teka = a[0], a[1]
os.makedirs(teka, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
ms = [o for o in bpy.context.scene.objects
      if o.type == "MESH" and not o.name.startswith("Icosphere")]
for o in ms:
    for m in list(o.modifiers):
        if m.type == "ARMATURE":
            o.modifiers.remove(m)
    mw = o.matrix_world.copy()
    o.parent = None
    o.matrix_world = mw
for o in [o for o in bpy.context.scene.objects if o not in ms]:
    bpy.data.objects.remove(o)
for o in ms:
    o.select_set(True)
bpy.context.view_layer.objects.active = ms[0]
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
tilo = max(ms, key=lambda o: len(o.data.vertices))
vs = [v.co for v in tilo.data.vertices]
z0 = min(v.z for v in vs)
H = max(v.z for v in vs) - z0

# Наколінки згладжує `avatar_build.py --коліна N` — до проєкції текстури
# (тут, після запікання, текстура розтягувалась смугами).


def shar(z, dz=0.006):
    return [v.co for v in tilo.data.vertices if abs(v.co.z - z) < dz]


# Заміри (метри, світ: X — праворуч кадру, Z — угору).
nogy = [p for p in shar(z0 + H * 0.29) if p.x < 0]
# лише вище 60% зросту: у орчихи (12.10.2026) стегна ширші за 0,25 м і
# тягнули середню висоту руки вниз (1,206 замість ~1,36)
ruka = [v.co for v in tilo.data.vertices if v.co.x < -0.25 and v.co.z > z0 + H * 0.6]
kinchyk = min(p.x for p in ruka) if ruka else None
pl = max(p.x for p in ruka) if ruka else None
# пах: знизу вгору — перша висота, де між ногами вже немає щілини
pakh = None
for i in range(200):
    z = z0 + H * 0.35 + i * 0.002
    xs = sorted(p.x for p in shar(z, 0.003) if abs(p.x) < 0.12)
    if xs and not any(b - a_ > 0.012 for a_, b in zip(xs, xs[1:])
                      if a_ < 0 < b or abs((a_ + b) / 2) < 0.02):
        pakh = z
        break
ruka_z = sum(p.z for p in ruka) / len(ruka) if ruka else None
zap = kinchyk + 0.17 if kinchyk else None
print("[заміри] зріст %.3f, низ %.3f" % (H, z0))
print("[заміри] пах z %.3f (%.0f%% зросту)" % (pakh, 100 * (pakh - z0) / H))
# мітка Mixamo — не по краю промежини, а на 3 см вище (замовник, орчиха
# 12.10.2026: «точку тазу підніми на 3 см, а не по краю»)
print("[заміри] мітка паху z %.3f" % (pakh + 0.03))
print("[заміри] коліно z %.3f x %.3f" % (z0 + H * 0.285,
      sum(p.x for p in nogy) / len(nogy)))
print("[заміри] рука z %.3f, кінчик x %.3f, зап'ястя x %.3f, лікоть x %.3f"
      % (ruka_z, kinchyk, zap, (zap + (-0.19)) / 2))
print("[заміри] підборіддя z ≈ %.3f" % (z0 + H * 0.877))
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(teka, "основа.blend"))
bpy.ops.wm.obj_export(filepath=os.path.join(teka, "основа.obj"),
                      export_selected_objects=False, export_materials=False,
                      forward_axis="NEGATIVE_Z", up_axis="Y")
print("[основа] →", teka)
