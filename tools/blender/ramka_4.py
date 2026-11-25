# Рамка скульпту з кількох видів у метрах пози скульпту (25.11.2026, П-288, спосіб Б): межі
# постаті на кадрах (`kadry_4.py`, виріз x0 y0 ширина висота) → x (спереду), y (зліва), z.
#   blender -b -P tools/blender/ramka_4.py -- <3-сітка.glb> --виріз 192 0 640 470 \
#       --спереду a.png --зліва c.png   → друкує «РАМКА x0 x1 y0 y1 z0 z1»
import math
import os
import sys

import bpy
import numpy as np

A = sys.argv[sys.argv.index("--") + 1:]
def arg(k, d):
    return type(d)(A[A.index(k) + 1]) if k in A else d
i = A.index("--виріз")
X0, Y0, CW, CH = (int(A[i + 1 + j]) for j in range(4))
TILO = arg("--тіло", "")
if A[0].endswith(".glb"):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(A[0]))
else:                                # модель з MPFB: тіло в позі спокою
    bpy.ops.wm.open_mainfile(filepath=os.path.abspath(A[0]))
    for rig in [o for o in bpy.data.objects if o.type == "ARMATURE"]:
        for pb in rig.pose.bones:
            pb.matrix_basis.identity()
    for o in list(bpy.data.objects):
        if o.type == "MESH" and o.name != (TILO or "Human"):
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
P = []
for o in bpy.context.scene.objects:
    if o.type == "MESH":
        ev = o.evaluated_get(dg)
        P += [(ev.matrix_world @ v.co)[:] for v in ev.data.vertices]
P = np.array(P)
N_TILA = len(P)
zmin, zmax = P[:, 2].min(), P[:, 2].max()
H = zmax - zmin
cx = (P[:, 0].min() + P[:, 0].max()) / 2
cy = (P[:, 1].min() + P[:, 1].max()) / 2
S = H / 0.93
R = 1024

def maska(shliakh):
    img = bpy.data.images.load(os.path.abspath(shliakh))
    w, h = img.size
    a = np.array(img.pixels[:]).reshape(h, w, 4)[::-1, :, :3]
    tlo = np.median(np.concatenate([a[:6].reshape(-1, 3), a[:, :6].reshape(-1, 3), a[:, -6:].reshape(-1, 3)]), 0)
    hh, ww = a.shape[:2]
    kil = np.concatenate([a[int(hh * 0.1):int(hh * 0.9), int(ww * 0.12)].reshape(-1, 3),
                          a[int(hh * 0.1):int(hh * 0.9), int(ww * 0.88)].reshape(-1, 3)])
    m = (np.abs(a - tlo).sum(2) > 0.09) & (np.abs(a - np.median(kil, 0)).sum(2) > 0.09)
    ys, xs = np.nonzero(m)
    # у координатах вирізу (кадр зведено до вирізу, розмір той самий)
    k = CW / w
    return xs.min() * k, xs.max() * k, ys.min() * k, (h - 1) * k

def u_svit(px, c):
    return c + (X0 + px - R / 2) / R * S

f = maska(arg("--спереду", ""))
x0, x1 = u_svit(f[0], cx), u_svit(f[1], cx)
z1 = zmin + H / 2 - (Y0 + f[2] - R / 2) / R * S
z0 = zmin + H / 2 - (Y0 + f[3] - R / 2) / R * S
# глибина: Hunyuan тримає пропорції — масштаб із ширини й висоти, середина — тіла в цій смузі
sk = bpy.data.objects.new  # noqa
bpy.ops.import_scene.gltf(filepath=os.path.abspath(arg("--скульпт", "")))
Q = []
for o in bpy.context.scene.objects:
    if o.type == "MESH" and o.data.users and len(o.data.vertices) != N_TILA:
        Q += [(o.matrix_world @ v.co)[:] for v in o.data.vertices]
Q = np.array(Q)
# межі стійко (без крайніх 0,5 %): кришку по краю кадру Hunyuan розкльошує вбік — повні межі
# від неї роздуті, а з ними й середина; у рамку йдуть повні межі через знайдені масштаб і середини
qmin, qmax = Q.min(0), Q.max(0)
seredni = Q[(Q[:, 2] > qmin[2] + 0.04 * (qmax[2] - qmin[2])) & (Q[:, 2] < qmax[2] - 0.04 * (qmax[2] - qmin[2]))]
qlo, qhi = np.percentile(seredni, 0.5, axis=0), np.percentile(seredni, 99.5, axis=0)
qlo[2], qhi[2] = qmin[2], qmax[2]
k = (z1 - z0) / (qhi[2] - qlo[2])
kx = (x1 - x0) / (qhi[0] - qlo[0])
print("масштаб за шириною %.4f, за висотою %.4f" % (kx, k))
smuga = P[(P[:, 2] > z0) & (P[:, 2] < z1)]
c_svit = np.array([(x0 + x1) / 2, (smuga[:, 1].min() + smuga[:, 1].max()) / 2, (z0 + z1) / 2])
c_sit = (qlo + qhi) / 2
x0, y0, z0 = c_svit + k * (qmin - c_sit)
x1, y1, z1 = c_svit + k * (qmax - c_sit)
# дотягнути (Y, трохи X і Z) так, щоб сітка найщільніше лягла на тіло: більша її частина — тіло
from mathutils import Vector
from mathutils.bvhtree import BVHTree
tila = [o for o in bpy.context.scene.objects if o.type == "MESH" and len(o.data.vertices) == N_TILA]
if not tila:
    tila = [o for o in bpy.context.scene.objects if o.type == "MESH"][:1]
tl = tila[0].evaluated_get(bpy.context.evaluated_depsgraph_get())
bvh = BVHTree.FromPolygons([tl.matrix_world @ v.co for v in tl.data.vertices], [p.vertices[:] for p in tl.data.polygons])
rng = np.random.default_rng(7)
QW = np.stack([[x0, y0, z0][q] + (Q[:, q] - qmin[q]) / max(qmax[q] - qmin[q], 1e-9) * ([x1, y1, z1][q] - [x0, y0, z0][q])
               for q in range(3)], 1)
vyb = QW[rng.choice(len(QW), min(3000, len(QW)), replace=False)]
def med(dx, dy, dz=0.0):
    return np.median([bvh.find_nearest(Vector(q + (dx, dy, dz)))[3] for q in vyb])
dy = min(np.linspace(-0.2, 0.2, 41), key=lambda d: med(0.0, d))
dy = min(np.linspace(dy - 0.01, dy + 0.01, 11), key=lambda d: med(0.0, d))
dx = min(np.linspace(-0.03, 0.03, 13), key=lambda d: med(d, dy))
dz = min(np.linspace(-0.02, 0.02, 9), key=lambda d: med(dx, dy, d))
print("дотягнуто dx %+.3f dy %+.3f dz %+.3f, медіана сітки до тіла %.1f мм" % (dx, dy, dz, med(dx, dy, dz) * 1000))
x0, x1, y0, y1, z0, z1 = x0 + dx, x1 + dx, y0 + dy, y1 + dy, z0 + dz, z1 + dz
print("РАМКА %.4f %.4f %.4f %.4f %.4f %.4f" % (x0, x1, y0, y1, z0, z1))
