# Колір сітки з чотирьох кадрів (24.11.2026, П-288, спосіб Б порівняння: Hunyuan3D-2mv дає лише
# форму). Кожна вершина бере колір з того кадру, на який дивиться найпрямше і звідки її видно
# (промінь до камери не перетинає сітку). Кадри ортографічні, одного масштабу; відповідність
# — за рамкою: межі сітки ↔ межі не-тла на кадрі. Далі — розгортка й запікання кольору в
# текстуру, вихід — GLB з текстурою, як у Pixal3D (його й їсть `odiah_zona.py`).
#   blender -b -P tools/blender/proektsiia_4.py -- <сітка.glb> <вихід.glb> \
#       --спереду a.png --ззаду b.png [--зліва c.png] [--справа d.png] [--текстура 2048]
import os
import sys

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

A = sys.argv[sys.argv.index("--") + 1:]
def arg(k, d):
    return type(d)(A[A.index(k) + 1]) if k in A else d
VHID, VYHID = os.path.abspath(A[0]), os.path.abspath(A[1])
TEX = arg("--текстура", 2048)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=VHID)
ms = [o for o in bpy.context.scene.objects if o.type == "MESH"]
for o in bpy.context.scene.objects:
    o.select_set(o in ms)
bpy.context.view_layer.objects.active = ms[0]
if len(ms) > 1:
    bpy.ops.object.join()
ob = bpy.context.view_layer.objects.active
ob.parent = None
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
me = ob.data
P = np.array([v.co[:] for v in me.vertices])
lo, hi = P.min(0), P.max(0)
print("[проекція] вершин %d, рамка %s…%s" % (len(P), lo.round(3), hi.round(3)))

def zchytaty(shliakh):
    img = bpy.data.images.load(os.path.abspath(shliakh))
    w, h = img.size
    a = np.array(img.pixels[:]).reshape(h, w, 4)[::-1, :, :3]   # рядок 0 — верх
    tlo = np.median(np.concatenate([a[:6].reshape(-1, 3), a[:, :6].reshape(-1, 3),
                                    a[:, -6:].reshape(-1, 3)]), 0)
    maska = np.abs(a - tlo).sum(2) > 0.09
    ys, xs = np.nonzero(maska)
    return a, maska, (xs.min(), xs.max(), ys.min(), ys.max())

# Blender після імпорту glTF: угору — Z; «спереду» — з −Y (як у kadry_4.py)
VYDY = {"--спереду": (Vector((0, -1, 0)), 0, 1), "--ззаду": (Vector((0, 1, 0)), 0, -1),
        "--зліва": (Vector((1, 0, 0)), 1, -1), "--справа": (Vector((-1, 0, 0)), 1, 1)}
kadry = {}
for k, (d, os_u, znak) in VYDY.items():
    if k in A:
        kadry[k] = (d, os_u, znak) + zchytaty(arg(k, ""))

bvh = BVHTree.FromPolygons([v.co for v in me.vertices], [p.vertices[:] for p in me.polygons])
me.calc_loop_triangles() if hasattr(me, "calc_loop_triangles") else None
N = np.array([v.normal[:] for v in me.vertices])
kol = np.zeros((len(P), 3))
bal = np.full(len(P), -9.0)
diag = float(np.linalg.norm(hi - lo))
# --бокові-запас: бокові кадри Qwen малює не в лад із переднім і заднім (наплічники інші) —
# з них колір лише там, куди спереду й ззаду не видно
ZAPAS = "--бокові-запас" in A
for k, (d, os_u, znak, a, maska, (x0, x1, y0, y1)) in kadry.items():
    dn = N @ np.array(d[:])
    if ZAPAS and k in ("--зліва", "--справа"):
        dn = dn - 2.0
    h, w = a.shape[:2]
    # u: для спереду — X сітки (ліве на кадрі — −X? камера з −Y дивиться на +Y: праве кадру = +X)
    uu = P[:, os_u] * znak
    ulo, uhi = (lo[os_u] * znak, hi[os_u] * znak)
    ulo, uhi = min(ulo, uhi), max(ulo, uhi)
    px = x0 + (uu - ulo) / max(uhi - ulo, 1e-6) * (x1 - x0)
    py = y0 + (hi[2] - P[:, 2]) / max(hi[2] - lo[2], 1e-6) * (y1 - y0)
    for i in np.nonzero(dn > bal)[0]:
        o = Vector(P[i]) + d * (diag * 0.002)
        if bvh.ray_cast(o, d, diag * 2)[0] is not None:
            continue
        yy, xx = int(np.clip(py[i], 0, h - 1)), int(np.clip(px[i], 0, w - 1))
        if not maska[yy, xx]:          # тло — кадри зведено неточно; колір дасть інший бік
            continue
        bal[i] = dn[i]
        kol[i] = a[yy, xx]
print("[проекція] без кольору вершин: %d" % int((bal < -5).sum()))
# дірки — колір найближчого сусіда з кольором
if (bal < -5).any():
    from mathutils import kdtree
    kd = kdtree.KDTree(int((bal >= -5).sum()))
    idx = np.nonzero(bal >= -5)[0]
    for j, i in enumerate(idx):
        kd.insert(Vector(P[i]), j)
    kd.balance()
    for i in np.nonzero(bal < -5)[0]:
        kol[i] = kol[idx[kd.find(Vector(P[i]))[1]]]
kol = np.where(kol <= 0.04045, kol / 12.92, ((kol + 0.055) / 1.055) ** 2.4)   # sRGB → лінійний
attr = me.color_attributes.new("Колір", "FLOAT_COLOR", "POINT")
attr.data.foreach_set("color", np.concatenate([kol, np.ones((len(P), 1))], 1).ravel())
# розгортка й запікання кольору вершин у текстуру
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.003)
bpy.ops.object.mode_set(mode="OBJECT")
img = bpy.data.images.new("колір", TEX, TEX)
mat = bpy.data.materials.new("скульпт")
mat.use_nodes = True
nt = mat.node_tree
bsdf = nt.nodes["Principled BSDF"]
ca = nt.nodes.new("ShaderNodeVertexColor")
ca.layer_name = "Колір"
tx = nt.nodes.new("ShaderNodeTexImage")
tx.image = img
nt.links.new(ca.outputs["Color"], bsdf.inputs["Base Color"])
me.materials.clear()
me.materials.append(mat)
nt.nodes.active = tx
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = 1
sc.render.bake.use_pass_direct = False
sc.render.bake.use_pass_indirect = False
sc.render.bake.margin = 4
bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"})
nt.links.new(tx.outputs["Color"], bsdf.inputs["Base Color"])
nt.nodes.remove(ca)
# кольори вершин — геть: імпорт glTF множить на них текстуру (порожні від Hunyuan давали чорне)
for c_ in list(me.color_attributes):
    me.color_attributes.remove(c_)
img.filepath_raw = VYHID.replace(".glb", "-колір.png")
img.file_format = "PNG"
img.save()
bpy.ops.export_scene.gltf(filepath=VYHID, export_format="GLB", use_selection=False,
                          export_texcoords=True, export_image_format="AUTO")
print("[проекція] →", VYHID)
