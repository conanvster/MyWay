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
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.abspath(A[0]))
P = []
for o in bpy.context.scene.objects:
    if o.type == "MESH":
        P += [(o.matrix_world @ v.co)[:] for v in o.data.vertices]
P = np.array(P)
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
    m = np.abs(a - tlo).sum(2) > 0.09
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
    if o.type == "MESH" and o.data.users and len(o.data.vertices) != len(P):
        Q += [(o.matrix_world @ v.co)[:] for v in o.data.vertices]
Q = np.array(Q)
qe = Q.max(0) - Q.min(0)
kx, kz = (x1 - x0) / qe[0], (z1 - z0) / qe[2]
# ширину роздуває кришка знизу (Hunyuan замикає сітку по краю кадру ширше за тіло) — масштаб
# лише за висотою, середина по X — постаті на кадрі
k = kz
xc = (x0 + x1) / 2
x0, x1 = xc - k * qe[0] / 2, xc + k * qe[0] / 2
smuga = P[(P[:, 2] > z0) & (P[:, 2] < z1)]
yc = (smuga[:, 1].min() + smuga[:, 1].max()) / 2
y0, y1 = yc - k * qe[1] / 2, yc + k * qe[1] / 2
print("масштаб за шириною %.4f, за висотою %.4f" % (kx, kz))
print("РАМКА %.4f %.4f %.4f %.4f %.4f %.4f" % (x0, x1, y0, y1, z0, z1))
