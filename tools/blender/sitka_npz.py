"""Сітка тіла «Human» (з формами й модифікаторами, у спокої) → npz:
вершини, трикутники, UV кутів, нормалі вершин. Для MV-Adapter і запікань.
    blender -b <pilot.blend> -P tools/blender/sitka_npz.py -- <вихід.npz>"""
import sys
import bpy
import numpy as np
out = sys.argv[sys.argv.index("--") + 1]
h = bpy.data.objects["Human"]
dg = bpy.context.evaluated_depsgraph_get()
me = h.evaluated_get(dg).to_mesh()
me.calc_loop_triangles()
mw = h.matrix_world
V = np.array([(mw @ v.co)[:] for v in me.vertices], np.float32)
VN = np.array([(mw.to_3x3() @ v.normal).normalized()[:] for v in me.vertices], np.float32)
F = np.array([t.vertices[:] for t in me.loop_triangles], np.int32)
uvl = me.uv_layers.active.data
UV = np.array([[uvl[l].uv[:] for l in t.loops] for t in me.loop_triangles], np.float32)
np.savez(out, V=V, VN=VN, F=F, UV=UV)
print("NPZ", out, V.shape, F.shape)
