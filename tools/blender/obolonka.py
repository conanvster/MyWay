# Спосіб В порівняння (24.11.2026, П-288): лати — оболонка нашого тіла. Тіло в позі скульпту
# (`3-сітка/<модель>.glb`, те саме, з якого `kadry_4.py` робив кадри) + ділянка під кірасою,
# відсунута назовні на товщину лат (над плечима — на висоту наплічника), з кольором кадрів
# Qwen-Edit спереду/ззаду/збоку. Прив'язка точна: камера кадрів відома (кадр 1024, маківка
# 0,035, підошви 0,965, середина рамки тіла), кадр зони — виріз (x0, y0, ширина, висота).
# Вихід — GLB тіла й оболонки з однією текстурою, як від Pixal3D: далі той самий `odiah_zona.py`.
#   blender -b -P tools/blender/obolonka.py -- <3-сітка.glb> <вихід.glb> --виріз 192 0 640 470 \
#       --спереду a.png --ззаду b.png [--зліва c.png] [--справа d.png] [--низ 1.0] [--шия 0.86]
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

A = sys.argv[sys.argv.index("--") + 1:]
def arg(k, d):
    return type(d)(A[A.index(k) + 1]) if k in A else d
VHID, VYHID = os.path.abspath(A[0]), os.path.abspath(A[1])
i = A.index("--виріз")
X0, Y0, CW, CH = (int(A[i + 1 + j]) for j in range(4))
NYZ = arg("--низ", 1.0)
SHYIA = arg("--шия", 0.86)          # частка зросту, де починається шия
TOVSHCH = arg("--товщина", 0.012)
NAPL = arg("--наплічник", 0.035)
TEX = arg("--текстура", 2048)
R = 1024

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=VHID)
tilo = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
bpy.context.view_layer.objects.active = tilo
tilo.select_set(True)
tilo.parent = None
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
me = tilo.data
P = np.array([v.co[:] for v in me.vertices])
zmin, zmax = P[:, 2].min(), P[:, 2].max()
H = zmax - zmin
cx = (P[:, 0].min() + P[:, 0].max()) / 2
cy = (P[:, 1].min() + P[:, 1].max()) / 2
S = H / 0.93                         # ortho_scale кадру (kadry_4.py)

def piksel(p, kut):
    """Світ → піксель повного кадру 1024 для боку kut (як камера kadry_4.py)."""
    a = math.radians(kut)
    # праве кадру: для спереду (+X), ззаду (−X), зліва (з +X дивимось на −X: праве — +Y), справа (−Y)
    pr = Vector((math.cos(a), math.sin(a), 0))
    u = (Vector(p) - Vector((cx, cy, 0))).dot(pr)
    v = zmin + H / 2 - p[2]
    return R / 2 + u / S * R, R / 2 + v / S * R

VYDY = {"--спереду": (0, Vector((0, -1, 0))), "--ззаду": (180, Vector((0, 1, 0))),
        "--зліва": (90, Vector((1, 0, 0))), "--справа": (-90, Vector((-1, 0, 0)))}
kadry = {}
for k, (kut, d) in VYDY.items():
    if k in A:
        img = bpy.data.images.load(os.path.abspath(arg(k, "")))
        w, h = img.size
        kadry[k] = (kut, d, np.array(img.pixels[:]).reshape(h, w, 4)[::-1, :, :3], w, h)

# колір тіла — з його ж текстури (для суміщення за шкірою досить)
tex_tila = next((n.image for m in me.materials if m and m.node_tree for n in m.node_tree.nodes
                 if n.type == "TEX_IMAGE" and n.image), None)
bm = bmesh.new()
bm.from_mesh(me)
uvl = bm.loops.layers.uv.active
kol_t = np.zeros((len(bm.verts), 3))
if tex_tila is not None:
    tw, th = tex_tila.size
    tp = np.array(tex_tila.pixels[:]).reshape(th, tw, 4)
    bm.verts.ensure_lookup_table()
    for v in bm.verts:
        if v.link_loops:
            u_, v_ = v.link_loops[0][uvl].uv
            kol_t[v.index] = tp[int(np.clip(v_ % 1 * th, 0, th - 1)), int(np.clip(u_ % 1 * tw, 0, tw - 1)), :3]

# ділянка під кірасою
z_shyi = zmin + SHYIA * H
z_pakhv = zmin + 0.76 * H            # пахви — нижче руки висять окремо від тулуба
def pid_kirasoiu(c):
    if c.z < NYZ or c.z > z_shyi:
        return False
    x = abs(c.x - cx)
    return x < 0.105 * H or (c.z > z_pakhv and x < 0.16 * H)
obl = [f for f in bm.faces if all(pid_kirasoiu(v.co) for v in f.verts)]
nove = bmesh.ops.duplicate(bm, geom=obl)
nv = [e for e in nove["geom"] if isinstance(e, bmesh.types.BMVert)]
nf = [e for e in nove["geom"] if isinstance(e, bmesh.types.BMFace)]
bm.normal_update()
for v in nv:
    x = abs(v.co.x - cx)
    plech = max(0.0, min(1.0, (x - 0.07 * H) / (0.05 * H))) * max(0.0, min(1.0, (v.co.z - z_pakhv) / (0.04 * H)))
    v.co += v.normal * (TOVSHCH + NAPL * plech)
# колір оболонки — з кадрів: найпрямший бік, звідки видно
bm.verts.ensure_lookup_table()
bvh = BVHTree.FromBMesh(bm)
kol = np.vstack([kol_t, np.zeros((len(bm.verts) - len(kol_t), 3))]) if len(bm.verts) > len(kol_t) else kol_t.copy()
bm.normal_update()
nema = 0
for v in nv:
    krashche, c_ = -9, None
    for k, (kut, d, a, w, h) in kadry.items():
        dn = v.normal.dot(d)
        if dn <= krashche:
            continue
        if bvh.ray_cast(v.co + d * 0.004, d, 3.0)[0] is not None:
            continue
        px, py = piksel(v.co, kut)
        qx, qy = (px - X0) / CW * w, (py - Y0) / CH * h
        if 0 <= qx < w and 0 <= qy < h:
            krashche, c_ = dn, a[int(qy), int(qx)]
    if c_ is None:
        nema += 1
        c_ = np.array([0.15, 0.15, 0.16])
    kol[v.index] = c_
print("[оболонка] граней %d, вершин без кадру %d" % (len(nf), nema))
bm.to_mesh(me)
me.update()
kol = np.where(kol <= 0.04045, kol / 12.92, ((kol + 0.055) / 1.055) ** 2.4)   # sRGB → лінійний
attr = me.color_attributes.new("Колір", "FLOAT_COLOR", "POINT")
attr.data.foreach_set("color", np.concatenate([kol[:len(me.vertices)], np.ones((len(me.vertices), 1))], 1).ravel())
# товщина лат — солідифікація лише оболонки (окремий об'єкт для простоти — ні: одна сітка, як Pixal)
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
bpy.ops.export_scene.gltf(filepath=VYHID, export_format="GLB", export_texcoords=True)
print("[оболонка] →", VYHID)
