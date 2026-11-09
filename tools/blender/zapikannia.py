"""Форма, колір і рельєф з генерованої 3D-сітки — на основу MPFB (09.11.2026).

Пілот 2 орка (слово замовника: «спробуй ті нові декілька інструментів щоб
отримати 3 варіанти згенеровані різними інструментами»). Сітка з референсу
(TRELLIS.2 або Pixal3D, `tools/comfyui/ork_pilot_3d.py`) має деталі (обличчя,
м'язи, вени), але зрощена з одягом і волоссям і без скелета. Основа MPFB —
навпаки: скелет, розгортка, рухи, броня. Тут основа бере в сітки:

  1. сітка стоячи, у зрості основи, обличчям у −Y;
  2. руки й ноги основи — у позу сітки (кисті й ступні — на її кисті й ступні);
  3. кожна вершина тіла притягується до поверхні сітки (промінь уздовж
     нормалі, інакше найближча точка); де сітка — не шкіра (пояс, штани,
     коси, борода: за кольором), кисті й пальці — зміщення нема; поле зміщень
     згладжене; помічники MPFB (під брови, вії, одяг) — за найближчою вершиною;
  4. зворотний скінінг — нова форма в позі спокою, у сітку тіла замість форм;
  5. колір і нормалі розгортки — з найближчої точки сітки (шкіра); не шкіра —
     базова шкіра в тоні шкіри сітки, рельєф рівний.

    blender -b <pilot.blend> -P tools/blender/zapikannia.py -- <сітка.glb> <вихід-префікс> \
        <базова шкіра.png> [--розмір 2048]
→ <префікс>.blend (нова основа), <префікс>-шкіра.png, <префікс>-нормалі.png
"""
import colorsys
import math
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

A = sys.argv[sys.argv.index("--") + 1:]
GLB, PREF, BAZA = A[0], A[1], A[2]
N = int(A[A.index("--розмір") + 1]) if "--розмір" in A else 2048
print_ = print


def log(*a):
    print_("[запікання]", *a, flush=True)


h = bpy.data.objects["Human"]
rig = bpy.data.objects["Human.rig"]
for pb in rig.pose.bones:
    pb.matrix_basis.identity()
me = h.data

# ── 0. форми — у сітку (як pilot_osnova), модифікатори крім скелета — вимкнути ──
if me.shape_keys:
    bpy.context.view_layer.objects.active = h
    h.shape_key_add(name="змішано", from_mix=True)
    for k in list(me.shape_keys.key_blocks):
        if k.name != "змішано":
            h.shape_key_remove(k)
    h.shape_key_remove(me.shape_keys.key_blocks["змішано"])
stan_mod = {}
for md in h.modifiers:
    stan_mod[md.name] = md.show_viewport
    if md.type != "ARMATURE":
        md.show_viewport = False
bpy.context.view_layer.update()
gi = {g.name: g.index for g in h.vertex_groups}
NV = len(me.vertices)
tilo = np.array([any(g.group == gi["body"] and g.weight > 0.5 for g in v.groups) for v in me.vertices])
REST = np.array([v.co[:] for v in me.vertices])
B = REST[tilo]
log("вершин %d, тіла %d" % (NV, tilo.sum()))

# ── 1. генерована сітка ──────────────────────────────────────────────
pered = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=GLB)
gen = [o for o in bpy.data.objects if o not in pered and o.type == "MESH"][0]
gm = gen.data
gm.calc_loop_triangles()
GV = np.array([(gen.matrix_world @ v.co)[:] for v in gm.vertices])
zr_t = B[:, 2].max() - B[:, 2].min()
zr_g = GV[:, 2].max() - GV[:, 2].min()
s = zr_t / zr_g
GV = (GV - np.array([0, 0, GV[:, 2].min()])) * s
# по осях X, Y — центр тулуба (верхня половина без рук)
def tsentr_tulub(P, z0, z1, xmax):
    m = (P[:, 2] > z0) & (P[:, 2] < z1) & (np.abs(P[:, 0]) < xmax)
    return P[m, :2].mean(0)
z0 = B[:, 2].min()
zz = (z0 + zr_t * 0.55, z0 + zr_t * 0.75)
GV[:, :2] += tsentr_tulub(B, *zz, 0.2) - tsentr_tulub(GV, *zz, 0.2)
GV[:, 2] += z0
GN = np.array([v.normal[:] for v in gm.vertices])
GT = np.array([t.vertices[:] for t in gm.loop_triangles])
uv_g = gm.uv_layers.active.data
GUV = np.array([[uv_g[l].uv[:] for l in t.loops] for t in gm.loop_triangles])
img = None
for mt in gen.data.materials:
    for n in mt.node_tree.nodes:
        if n.type == "TEX_IMAGE" and n.image is not None and img is None:
            img = n.image
w_, h_ = img.size
TEXG = np.array(img.pixels[:], np.float32).reshape(h_, w_, img.channels)[..., :3]
log("сітка: вершин %d, граней %d, масштаб %.3f, текстура %dx%d" % (len(GV), len(GT), s, w_, h_))
bvh_g = BVHTree.FromPolygons([tuple(v) for v in GV], [tuple(t) for t in GT])


def kolir_v(tri, p):
    """Колір текстури сітки в точці p трикутника tri."""
    a, b, c = GV[GT[tri]]
    v0, v1, v2 = b - a, c - a, p - a
    d00, d01, d11 = v0 @ v0, v0 @ v1, v1 @ v1
    d20, d21 = v2 @ v0, v2 @ v1
    den = d00 * d11 - d01 * d01 + 1e-12
    bb = (d11 * d20 - d01 * d21) / den
    cc = (d00 * d21 - d01 * d20) / den
    aa = 1 - bb - cc
    uv = GUV[tri, 0] * aa + GUV[tri, 1] * bb + GUV[tri, 2] * cc
    x = int(np.clip(uv[0] * w_, 0, w_ - 1))
    y = int(np.clip(uv[1] * h_, 0, h_ - 1))
    nn = GN[GT[tri, 0]] * aa + GN[GT[tri, 1]] * bb + GN[GT[tri, 2]] * cc
    return TEXG[y, x], nn / (np.linalg.norm(nn) + 1e-9)


def shkira_li(c):
    """Колір не відрізняє шкіру від штанів (тони однакові) — тут лише темне
    (волосся, борода) геть; одяг — зонами кісток (`ZONA`)."""
    vv = max(float(x) ** (1 / 2.2) for x in c)
    return float(np.clip((vv - 0.26) / 0.10, 0, 1))


# ── 2. руки й ноги — у позу сітки ─────────────────────────────────────
def kraini(P, bik, ruky):
    if ruky:
        m = P[:, 0] * bik > 0.25 * np.abs(P[:, 0]).max()
        Q = P[m]
        return Q[np.argsort(-Q[:, 0] * bik)[:40]].mean(0)
    m = (P[:, 2] < P[:, 2].min() + 0.06) & (P[:, 0] * bik > 0.02)
    return P[m].mean(0)


def naviaty(kist, kinets_t, tsil):
    pb = rig.pose.bones[kist]
    bpy.context.view_layer.update()
    holova = rig.matrix_world @ pb.head
    a = (Vector(kinets_t) - holova).normalized()
    b = (Vector(tsil) - holova).normalized()
    q = a.rotation_difference(b)
    m = pb.matrix.copy()
    t = m.translation.copy()
    m = q.to_matrix().to_4x4() @ m
    m.translation = t
    pb.matrix = m
    bpy.context.view_layer.update()


for bik, sfx in ((1, "l"), (-1, "r")):
    naviaty("upperarm_" + sfx, kraini(B, bik, True), kraini(GV, bik, True))
    naviaty("thigh_" + sfx, kraini(B, bik, False), kraini(GV, bik, False))
dg = bpy.context.evaluated_depsgraph_get()
pm = h.evaluated_get(dg).to_mesh()
POZ = np.array([v.co[:] for v in pm.vertices])
PN = np.array([v.normal[:] for v in pm.vertices])
log("поза: кисті й ступні — на сітку")

# ── 2б. зони одягу й волосся за кістками основи (0 — одяг, 1 — шкіра) ──
def vaga_kistok(*imena):
    out = np.zeros(NV)
    for nm in imena:
        idx = gi.get(nm)
        if idx is None:
            continue
        for v in me.vertices:
            for g in v.groups:
                if g.group == idx:
                    out[v.index] += g.weight
    return out


koliano = rig.data.bones["calf_l"].head_local.z
poyas = rig.data.bones["spine_01"].tail_local.z
guby = vaga_kistok("lips") if "lips" in gi else np.zeros(NV)
z_rot = REST[guby > 0.5, 2].mean() if (guby > 0.5).any() else rig.data.bones["head"].head_local.z
ZONA = np.ones(NV)
ZONA[(REST[:, 2] < poyas + 0.02) & (REST[:, 2] > koliano - 0.12)] = 0.0       # пояс, штани, наколінники
hol = vaga_kistok("head")
ZONA[(hol > 0.5) & (REST[:, 2] < z_rot - 0.008) & (REST[:, 1] < rig.data.bones["head"].head_local.y)] = 0.0  # борода
grud = (REST[:, 2] < rig.data.bones["neck_01"].head_local.z) & (REST[:, 2] > poyas) & \
    (np.abs(REST[:, 0]) > 0.03) & (np.abs(REST[:, 0]) < 0.13) & (REST[:, 1] < 0)
ZONA[grud] *= 0.5                                                              # коси — лише світле
log("зони: одяг і борода — %d вершин" % int((ZONA == 0).sum()))

# ── 3. притягнути тіло ───────────────────────────────────────────────
kisti = np.zeros(NV)
for nm in gi:
    if nm.split("_")[0] in ("hand", "thumb", "index", "middle", "ring", "pinky"):
        idx = gi[nm]
        for v in me.vertices:
            for g in v.groups:
                if g.group == idx:
                    kisti[v.index] += g.weight
disp = np.zeros((NV, 3))
vaga = np.zeros(NV)
for i in np.nonzero(tilo)[0]:
    p, n = Vector(POZ[i]), Vector(PN[i])
    naib = None
    for nap in (n, -n):
        hit = bvh_g.ray_cast(p - nap * 0.002, nap, 0.08)
        if hit[0] is not None and (naib is None or hit[3] < naib[3]):
            naib = hit
    if naib is None:
        hit = bvh_g.find_nearest(p, 0.04)
        if hit[0] is None:
            continue
        naib = (hit[0], hit[1], hit[2], hit[3])
    c, _ = kolir_v(naib[2], np.array(naib[0]))
    w = shkira_li(c) * (1 - min(1.0, kisti[i])) * (ZONA[i] > 0.99)
    disp[i] = np.array(naib[0]) - POZ[i]
    vaga[i] = w
sus = [[] for _ in range(NV)]
for e in me.edges:
    a, b = e.vertices
    sus[a].append(b)
    sus[b].append(a)
# згладити: нормоване (лише з вагою) + маска плавно
dw = disp * vaga[:, None]
for _ in range(6):
    dw = np.array([(dw[i] + sum(dw[j] for j in sus[i])) / (1 + len(sus[i])) for i in range(NV)])
    vaga = np.array([(vaga[i] + sum(vaga[j] for j in sus[i])) / (1 + len(sus[i])) for i in range(NV)])
disp = dw / np.maximum(vaga, 0.15)[:, None] * np.clip(vaga / 0.5, 0, 1)[:, None]
disp[~tilo] = 0
# помічники й не-тіло — за найближчою вершиною тіла
kd = KDTree(int(tilo.sum()))
ti = np.nonzero(tilo)[0]
for j, i in enumerate(ti):
    kd.insert(POZ[i], j)
kd.balance()
for i in np.nonzero(~tilo)[0]:
    _, j, _ = kd.find(POZ[i])
    disp[i] = disp[ti[j]]
NOVE_POZ = POZ + disp
log("зміщення: середнє %.4f м, макс %.4f м" % (np.linalg.norm(disp[tilo], axis=1).mean(),
                                              np.linalg.norm(disp[tilo], axis=1).max()))

# ── 4. зворотний скінінг → поза спокою ────────────────────────────────
mat = {}
for pb in rig.pose.bones:
    mat[pb.name] = np.array(pb.matrix @ pb.bone.matrix_local.inverted())
nove = np.zeros((NV, 3))
imena = {g.index: g.name for g in h.vertex_groups}
for v in me.vertices:
    M = np.zeros((4, 4))
    sw = 0
    for g in v.groups:
        nm = imena[g.group]
        if nm in mat and g.weight > 0:
            M += mat[nm] * g.weight
            sw += g.weight
    if sw < 1e-6:
        nove[v.index] = NOVE_POZ[v.index]
        continue
    M /= sw
    nove[v.index] = (np.linalg.inv(M) @ np.append(NOVE_POZ[v.index], 1))[:3]
for pb in rig.pose.bones:
    pb.matrix_basis.identity()
for v in me.vertices:
    v.co = nove[v.index]
me.update()
for md in h.modifiers:
    md.show_viewport = stan_mod.get(md.name, True)
log("нова форма в позі спокою")

# ── 5. колір і нормалі розгортки ─────────────────────────────────────
me.calc_loop_triangles()
uvl = me.uv_layers.active.data
T = np.array([t.vertices[:] for t in me.loop_triangles])
TUV = np.array([[uvl[l].uv[:] for l in t.loops] for t in me.loop_triangles])
tilo_t = tilo[T].all(1)
tri_id = np.full((N, N), -1, np.int32)
bary = np.zeros((N, N, 3), np.float32)
for i in np.nonzero(tilo_t)[0]:
    p = TUV[i] * N
    x0, y0 = np.maximum(np.floor(p.min(0)).astype(int), 0)
    x1, y1 = np.minimum(np.ceil(p.max(0)).astype(int), N - 1)
    if x1 < x0 or y1 < y0:
        continue
    xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
    a, b, c = p
    det = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
    if abs(det) < 1e-12:
        continue
    l0 = ((b[1] - c[1]) * (xs - c[0]) + (c[0] - b[0]) * (ys - c[1])) / det
    l1 = ((c[1] - a[1]) * (xs - c[0]) + (a[0] - c[0]) * (ys - c[1])) / det
    l2 = 1 - l0 - l1
    ok = (l0 >= -1e-4) & (l1 >= -1e-4) & (l2 >= -1e-4)
    yy, xx = (ys[ok] - 0.5).astype(int), (xs[ok] - 0.5).astype(int)
    tri_id[yy, xx] = i
    bary[yy, xx] = np.stack([l0[ok], l1[ok], l2[ok]], -1)
yy, xx = np.nonzero(tri_id >= 0)
tt = tri_id[yy, xx]
bc = bary[yy, xx]
P = (NOVE_POZ[T[tt]] * bc[..., None]).sum(1)          # точка в позі сітки
NR = (PN[T[tt]] * bc[..., None]).sum(1)
NR /= np.linalg.norm(NR, axis=1, keepdims=True) + 1e-9
e1 = NOVE_POZ[T[:, 1]] - NOVE_POZ[T[:, 0]]
e2 = NOVE_POZ[T[:, 2]] - NOVE_POZ[T[:, 0]]
d1 = TUV[:, 1] - TUV[:, 0]
d2 = TUV[:, 2] - TUV[:, 0]
den = d1[:, 0] * d2[:, 1] - d2[:, 0] * d1[:, 1]
den = np.where(np.abs(den) < 1e-12, 1e-12, den)
TAN = (e1 * d2[:, 1:2] - e2 * d1[:, 1:2]) / den[:, None]
log("текселів %d" % len(tt))
KOL = np.zeros((len(tt), 3))
NG = np.zeros((len(tt), 3))
SK = np.zeros(len(tt))
for k in range(len(tt)):
    hit = bvh_g.find_nearest(Vector(P[k]), 0.05)
    if hit[0] is None:
        continue
    c, nn = kolir_v(hit[2], np.array(hit[0]))
    KOL[k], NG[k] = c, nn
    SK[k] = shkira_li(c)
SK *= (ZONA[T[tt]] * bc).sum(1) > 0.99
log("колір з сітки зібрано; шкіри %.0f %%" % (100 * (SK > 0.5).mean()))
baza = np.array(bpy.data.images.load(BAZA).pixels[:], np.float32)
nb = int(math.sqrt(len(baza) // 4))
baza = baza.reshape(nb, nb, 4)[..., :3]
if nb != N:
    f = nb // N
    baza = baza.reshape(N, f, N, f, 3).mean((1, 3))
# тон базової шкіри — до тону шкіри сітки
sk_g = KOL[SK > 0.8].mean(0)
sk_b = baza[yy[SK > 0.8], xx[SK > 0.8]].mean(0)
baza_t = np.clip(baza * (sk_g / np.maximum(sk_b, 1e-3)), 0, 1)
ALB = baza_t.copy()
ALB[yy, xx] = KOL * SK[:, None] + baza_t[yy, xx] * (1 - SK[:, None])
t_ = TAN[tt] - NR * (TAN[tt] * NR).sum(1, keepdims=True)
t_ /= np.linalg.norm(t_, axis=1, keepdims=True) + 1e-9
b_ = np.cross(NR, t_)
nts = np.stack([(NG * t_).sum(1), (NG * b_).sum(1), (NG * NR).sum(1)], -1)
nts = nts * SK[:, None] + np.array([0, 0, 1.0]) * (1 - SK[:, None])
nts /= np.linalg.norm(nts, axis=1, keepdims=True) + 1e-9
NOR = np.zeros((N, N, 3)) + np.array([0, 0, 1.0])
NOR[yy, xx] = nts


def zapysaty(a, shliakh):
    im = bpy.data.images.new("out", N, N, alpha=False)
    rgba = np.concatenate([np.clip(a, 0, 1), np.ones((N, N, 1))], 2).astype(np.float32)
    im.pixels.foreach_set(rgba.ravel())
    im.filepath_raw = shliakh
    im.file_format = "PNG"
    im.save()
    log("→", shliakh)


zapysaty(ALB, PREF + "-шкіра.png")
zapysaty(NOR * 0.5 + 0.5, PREF + "-нормалі.png")
bpy.data.objects.remove(gen)
bpy.ops.wm.save_as_mainfile(filepath=PREF + ".blend")
log("→", PREF + ".blend")
