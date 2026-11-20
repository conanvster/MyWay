# Спідниця до талії (20.11.2026, людина-жінка: скульпт пояса нахилений — спереду верх відстає від
# живота, ззаду опущений нижче сідниць, з-під нього видно білизну). По колу навколо тулуба:
#  • верхній край підтягується до рівня --талія (подол на місці, між ними — рівномірне розтягнення);
#  • верхній пасок (вище --від) зсувається радіально до тіла так, щоб внутрішній бік лежав на
#    --зазор від шкіри,
#    а відстань від неї стискається до ≤ --зазор + --стиск (монотонно — шари не міняються місцями).
#   blender -b <сет>.blend -P tools/blender/spidnytsia_talia.py -- [--річ Одяг-тіло-важка-пояс]
#       [--тіло Human] [--талія 1.03] [--від 0.88] [--до 0.95] [--зазор 0.006] [--стиск 0.02]
import sys, math
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

A = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
def arg(k, d):
    return type(d)(A[A.index(k) + 1]) if k in A else d
RICH = arg("--річ", "Одяг-тіло-важка-пояс")
TILO = arg("--тіло", "Human")
TALIA = arg("--талія", 1.03)
VID, DO = arg("--від", 0.88), arg("--до", 0.95)
ZAZOR = arg("--зазор", 0.006)
STYSK = arg("--стиск", 0.02)
N = 48

rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
for pb in rig.pose.bones:
    pb.matrix_basis.identity()
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
sk = bpy.data.objects[RICH]
bd = bpy.data.objects[TILO].evaluated_get(dg)
bm = bd.to_mesh()
bv = BVHTree.FromPolygons([bd.matrix_world @ v.co for v in bm.vertices],
                          [p.vertices[:] for p in bm.polygons])
mw = sk.matrix_world
mi = mw.inverted()

def hit(o, d):
    h = bv.ray_cast(o, d, 1.0)
    return h[0]

def centr(z):
    o = Vector((0, -0.025, z))
    f, b = hit(o, Vector((0, -1, 0))), hit(o, Vector((0, 1, 0)))
    l, r = hit(o, Vector((-1, 0, 0))), hit(o, Vector((1, 0, 0)))
    cy = (f.y + b.y) / 2 if f and b else -0.025
    cx = (l.x + r.x) / 2 if l and r else 0.0
    return cx, cy

CZ = {round(z, 2): centr(z) for z in [0.80 + 0.01 * i for i in range(36)]}
def c_at(z):
    return CZ[round(min(max(z, 0.80), 1.15), 2)]

def kut(p):
    cx, cy = c_at(p.z)
    return math.atan2(p.x - cx, -(p.y - cy))

def sektor(a):
    return int((a + math.pi) / (2 * math.pi) * N) % N

P = [mw @ v.co for v in sk.data.vertices]
top = [-9.0] * N
bot = [9.0] * N
for p in P:
    s = sektor(kut(p))
    top[s] = max(top[s], p.z)
    bot[s] = min(bot[s], p.z)
def gladko(a, k=2):
    return [sum(a[(i + j) % N] for j in range(-k, k + 1)) / (2 * k + 1) for i in range(N)]
top, bot = gladko(top), gladko(bot)
print("[спідниця] верх по колу: %.3f…%.3f, подол %.3f…%.3f" % (min(top), max(top), min(bot), max(bot)))

def interp(a, ang):
    f = (ang + math.pi) / (2 * math.pi) * N - 0.5
    i = math.floor(f)
    t = f - i
    return a[i % N] * (1 - t) + a[(i + 1) % N] * t

# 1) по висоті
Q = []
for p in P:
    a = kut(p)
    t0, b0 = interp(top, a), interp(bot, a)
    k = (TALIA - b0) / max(t0 - b0, 0.05)
    Q.append(Vector((p.x, p.y, b0 + (p.z - b0) * k)))

# 2) радіально: внутрішній бік верхнього паска — на зазор від шкіри
def r_tila(z, a):
    cx, cy = c_at(z)
    d = Vector((math.sin(a), -math.cos(a), 0))
    h = hit(Vector((cx, cy, z)), d)
    return (h - Vector((cx, cy, z))).length if h else None

zsuv = 0
for i, q in enumerate(Q):
    if q.z < VID:
        continue
    a = kut(q)
    cx, cy = c_at(q.z)
    rv = Vector((q.x - cx, q.y - cy, 0))
    rb = r_tila(q.z, a)
    if rb is None or rb > 0.3:
        continue
    d = rv.length - rb
    # монотонно стиснута відстань від шкіри: шари не міняються місцями, всередині тіла — назовні
    d2 = ZAZOR + STYSK * math.tanh(max(d, 0.0) / STYSK)
    w = min(max((q.z - VID) / (DO - VID), 0.0), 1.0)
    w = w * w * (3 - 2 * w)
    Q[i] = q + rv.normalized() * (d2 - d) * w
    zsuv += 1
print("[спідниця] радіально стиснуто %d вершин" % zsuv)
for v, q in zip(sk.data.vertices, Q):
    v.co = mi @ q
sk.data.update()
bpy.ops.wm.save_mainfile()
print("[спідниця] збережено")
