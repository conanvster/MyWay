# Чоботи без клаптів шкіри (20.11.2026, людина-жінка: з халяв стирчали рожеві шматки гомілки, які
# генератор зліпив з відворотом). Грань, що лежить у верхній частині чобота (вище --від, частка
# висоти від підошви) і має на текстурі шкірний тон (r помітно більше за g, світла), — геть, разом
# з острівцями, що після цього відірвались від чобота (< --острів м²).
#   blender -b <сет>.blend -P tools/blender/choboty_bez_klaptiv.py -- [--річ Одяг-взуття-важка-чоботи]
#       [--від 0.6] [--rg 1.18] [--яскравість 0.38] [--острів 0.002] [--не-зберігати]
import sys
import bpy, bmesh
from mathutils import Vector

A = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
def arg(k, d):
    return type(d)(A[A.index(k) + 1]) if k in A else d
RICH = arg("--річ", "Одяг-взуття-важка-чоботи")
VID = arg("--від", 0.6)
RG = arg("--rg", 1.18)
JAS = arg("--яскравість", 0.38)
OSTRIV = arg("--острів", 0.002)

ob = bpy.data.objects[RICH]
img = None
for s in ob.material_slots:
    for nd in s.material.node_tree.nodes:
        if nd.type == "TEX_IMAGE" and nd.image and "нормал" not in nd.image.name:
            img = nd.image
            break
    if img:
        break
W, H = img.size
px = list(img.pixels)
def kolir(uv):
    x = min(max(int(uv.x % 1.0 * W), 0), W - 1)
    y = min(max(int(uv.y % 1.0 * H), 0), H - 1)
    i = (y * W + x) * 4
    return px[i], px[i + 1], px[i + 2]

bm = bmesh.new()
bm.from_mesh(ob.data)
bm.faces.ensure_lookup_table()
uvl = bm.loops.layers.uv.active
mw = ob.matrix_world
zs = [(mw @ v.co).z for v in bm.verts]
z0, z1 = min(zs), max(zs)
zvid = z0 + VID * (z1 - z0)
geth = set()
for f in bm.faces:
    c = mw @ f.calc_center_median()
    if c.z < zvid:
        continue
    uv = sum((l[uvl].uv for l in f.loops), Vector((0, 0))) / len(f.loops)
    r, g, b = kolir(uv)
    if r > JAS and r / max(g, 1e-3) > RG and r > b * 1.25:
        geth.add(f)
# острівці, що лишились малі
ok = [f for f in bm.faces if f not in geth]
okset = set(ok)
bach = set()
for f in ok:
    if f in bach:
        continue
    st, ost = [f], []
    bach.add(f)
    while st:
        g_ = st.pop()
        ost.append(g_)
        for e in g_.edges:
            for h in e.link_faces:
                if h in okset and h not in bach:
                    bach.add(h)
                    st.append(h)
    if sum(x.calc_area() for x in ost) * (mw.median_scale ** 2) < OSTRIV:
        geth.update(ost)
print("[чоботи] висота %.3f…%.3f, межа %.3f; геть %d граней з %d" % (z0, z1, zvid, len(geth), len(bm.faces)))
bmesh.ops.delete(bm, geom=list(geth), context="FACES")
bm.to_mesh(ob.data)
ob.data.update()
if "--не-зберігати" not in A:
    bpy.ops.wm.save_mainfile()
    print("[чоботи] збережено")
