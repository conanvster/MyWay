"""Генерована сітка (TRELLIS.2 / Pixal3D) — аватар на скелеті MPFB (09.11.2026).

Пілот 2 орка, варіанти А і В: сама сітка з референсу стає тілом — уся її
форма й текстура (обличчя, м'язи, вени, коси, пояс) лишаються. Скелет —
`game_engine` основи MPFB (рухи UAL1, переглядач, гра):

  1. сітка стоячи, у зрості основи, обличчям у −Y;
  2. руки й ноги основи — у позу сітки (кисті й ступні на її кисті й ступні);
  3. сітка спрощується до `--граней`;
  4. ваги кісток — з найближчої точки основи в тій самій позі (барицентрично),
     згладжено по сусідах, не більше 4 кісток на вершину;
  5. зворотний скінінг — сітка в позу спокою скелета; тіло MPFB і його
     сітки (очі, брови, вії, зачіски) — геть.

    blender -b <pilot.blend> -P tools/blender/rig_sitky.py -- <сітка.glb> <вихід.blend> [--граней 60000]
"""
import sys

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

A = sys.argv[sys.argv.index("--") + 1:]
GLB, VYKHID = A[0], A[1]
GRANEI = int(A[A.index("--граней") + 1]) if "--граней" in A else 150000


def log(*a):
    print("[риг сітки]", *a, flush=True)


h = bpy.data.objects["Human"]
rig = bpy.data.objects["Human.rig"]
for pb in rig.pose.bones:
    pb.matrix_basis.identity()
me = h.data
if me.shape_keys:
    bpy.context.view_layer.objects.active = h
    h.shape_key_add(name="змішано", from_mix=True)
    for k in list(me.shape_keys.key_blocks):
        if k.name != "змішано":
            h.shape_key_remove(k)
    h.shape_key_remove(me.shape_keys.key_blocks["змішано"])
for md in h.modifiers:
    if md.type != "ARMATURE":
        md.show_viewport = False
bpy.context.view_layer.update()
gi = {g.name: g.index for g in h.vertex_groups}
imena = {g.index: g.name for g in h.vertex_groups}
kosti = set(rig.data.bones.keys())
tilo = np.array([any(g.group == gi["body"] and g.weight > 0.5 for g in v.groups) for v in me.vertices])
REST = np.array([v.co[:] for v in me.vertices])
B = REST[tilo]

# ── 1. сітка ─────────────────────────────────────────────────────────
pered = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=GLB)
gen = [o for o in bpy.data.objects if o not in pered and o.type == "MESH"][0]
for o in [o for o in bpy.data.objects if o not in pered and o != gen]:
    bpy.data.objects.remove(o)
gen.parent = None
bpy.context.view_layer.objects.active = gen
gen.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
dc = gen.modifiers.new("спростити", "DECIMATE")
dc.ratio = min(1.0, GRANEI / max(1, len(gen.data.polygons)))
bpy.ops.object.modifier_apply(modifier=dc.name)
gm = gen.data
# власні нормалі з GLB після спрощення лишались пласкими — обличчя в грі
# гранчасте (09.11); геть, нормалі — з самої сітки, згладжено
if gm.has_custom_normals:
    bpy.ops.mesh.customdata_custom_splitnormals_clear()
GV = np.array([v.co[:] for v in gm.vertices])
zr_t = B[:, 2].max() - B[:, 2].min()
s = zr_t / (GV[:, 2].max() - GV[:, 2].min())
GV = (GV - np.array([0, 0, GV[:, 2].min()])) * s


def tsentr(P, z0, z1):
    m = (P[:, 2] > z0) & (P[:, 2] < z1) & (np.abs(P[:, 0]) < 0.2)
    return P[m, :2].mean(0)


z0 = B[:, 2].min()
zz = (z0 + zr_t * 0.55, z0 + zr_t * 0.75)
GV[:, :2] += tsentr(B, *zz) - tsentr(GV, *zz)
GV[:, 2] += z0
log("сітка: вершин %d, граней %d, масштаб %.3f" % (len(GV), len(gm.polygons), s))


# ── 2. поза основи — як у сітки ──────────────────────────────────────
def kraini(P, bik, ruky):
    if ruky:
        m = P[:, 0] * bik > 0.25 * np.abs(P[:, 0]).max()
        Q = P[m]
        return Q[np.argsort(-Q[:, 0] * bik)[:40]].mean(0)
    m = (P[:, 2] < P[:, 2].min() + 0.06) & (P[:, 0] * bik > 0.02)
    return P[m].mean(0)


def naviaty(kist, vid, do):
    pb = rig.pose.bones[kist]
    bpy.context.view_layer.update()
    holova = rig.matrix_world @ pb.head
    q = (Vector(vid) - holova).normalized().rotation_difference((Vector(do) - holova).normalized())
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
polys = [tuple(p.vertices) for p in me.polygons if all(tilo[i] for i in p.vertices)]
bvh = BVHTree.FromPolygons([tuple(v) for v in POZ], polys)
log("поза основи — як у сітки")

# ── 3. ваги з основи ─────────────────────────────────────────────────
VW = {}
for v in me.vertices:
    VW[v.index] = {imena[g.group]: g.weight for g in v.groups
                   if imena[g.group] in kosti and g.weight > 0.001}
NG = len(GV)
vagy = [dict() for _ in range(NG)]
for i in range(NG):
    hit = bvh.find_nearest(Vector(GV[i]))
    poly = polys[hit[2]]
    p = np.array(hit[0])
    d = np.array([np.linalg.norm(POZ[j] - p) for j in poly])
    w = 1.0 / (d + 1e-4)
    w /= w.sum()
    acc = {}
    for wj, j in zip(w, poly):
        for k, x in VW[j].items():
            acc[k] = acc.get(k, 0.0) + wj * x
    vagy[i] = acc
sus = [[] for _ in range(NG)]
for e in gm.edges:
    a, b = e.vertices
    sus[a].append(b)
    sus[b].append(a)
for _ in range(2):
    nove = []
    for i in range(NG):
        acc = dict(vagy[i])
        for j in sus[i]:
            for k, x in vagy[j].items():
                acc[k] = acc.get(k, 0.0) + x
        nove.append(acc)
    vagy = nove
for i in range(NG):
    top = sorted(vagy[i].items(), key=lambda kv: -kv[1])[:4]
    sm = sum(x for _, x in top) or 1.0
    vagy[i] = {k: x / sm for k, x in top}
log("ваги перенесено")

# ── 4. зворотний скінінг ─────────────────────────────────────────────
mat = {pb.name: np.array(pb.matrix @ pb.bone.matrix_local.inverted()) for pb in rig.pose.bones}
for i, v in enumerate(gm.vertices):
    M = sum(mat[k] * x for k, x in vagy[i].items())
    v.co = (np.linalg.inv(M) @ np.append(GV[i], 1))[:3]
for pb in rig.pose.bones:
    pb.matrix_basis.identity()
for g in list(gen.vertex_groups):
    gen.vertex_groups.remove(g)
grupy = {}
for i in range(NG):
    for k, x in vagy[i].items():
        if k not in grupy:
            grupy[k] = gen.vertex_groups.new(name=k)
        grupy[k].add([i], x, "REPLACE")
gen.parent = rig
gen.modifiers.new("Armature", "ARMATURE").object = rig
for p in gm.polygons:
    p.use_smooth = True
# тіло MPFB і його сітки — геть
for o in [o for o in bpy.data.objects if o.type == "MESH" and o != gen]:
    bpy.data.objects.remove(o)
def zapovnyty(px, ye):
    """Тло між островами — кольором найближчих островів (піраміда push-pull):
    розтягування на 24 пікселі не закривало ширших щілин, і спрощена сітка,
    чиї трикутники перетинають шви, тягнула з них чорні рисочки (09.11)."""
    if ye.all() or not ye.any():
        return px
    w = ye.astype(np.float32)
    rivni = []
    a, m = px * w[..., None], w
    while min(a.shape[:2]) > 1:
        rivni.append((a, m))
        h2, w2 = a.shape[0] // 2 * 2, a.shape[1] // 2 * 2
        a = a[:h2, :w2].reshape(h2 // 2, 2, w2 // 2, 2, -1).sum((1, 3))
        m = m[:h2, :w2].reshape(h2 // 2, 2, w2 // 2, 2).sum((1, 3))
    kol = a / np.maximum(m, 1e-6)[..., None]
    for a, m in reversed(rivni):
        up = np.repeat(np.repeat(kol, 2, 0), 2, 1)
        up = np.pad(up, ((0, a.shape[0] - up.shape[0]), (0, a.shape[1] - up.shape[1]), (0, 0)), mode="edge")
        vl = a / np.maximum(m, 1e-6)[..., None]
        kol = np.where((m > 0)[..., None], vl, up)
    return np.where(ye[..., None], px, kol).astype(np.float32)


# шви розгортки: між островами текстури генератора чорне тло — при
# фільтрації в грі воно протікало чорними тріщинами; краї островів — на тло
for mt in gm.materials:
    for n in (mt.node_tree.nodes if mt and mt.node_tree else []):
        if n.type == "TEX_IMAGE" and n.image is not None:
            im = n.image
            w_, h_ = im.size
            px = np.array(im.pixels[:], np.float32).reshape(h_, w_, im.channels)
            ye = px[..., :3].max(2) > 0.02
            px = zapovnyty(px, ye)
            im.pixels.foreach_set(px.ravel())
            im.pack()
            log("текстура %s: шви закрито" % im.name)
gen.name = "Тіло"
gm.name = "Тіло"
bpy.ops.wm.save_as_mainfile(filepath=VYKHID)
log("→", VYKHID)
