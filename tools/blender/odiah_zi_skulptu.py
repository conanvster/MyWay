"""Одяг зі скульпту вдягненого (12.11.2026): «вдягнений мінус голий».

Слово замовника: «зроби сет одягу — почни з сету важкої броні для орка» (кадр вікі
орк-чоловік-v3). Наш лисий орк у білизні вдягається картинкою (Qwen-Image-Edit, друга картинка —
кадр вікі), з неї — скульпт Pixal3D у тій самій позі. Тут скульпт вдягненого суміщається з готовою
моделлю гри, і все, що не шкіра, вирізається окремими деталями на скелеті:

    Одяг-тіло-<тип>-наплічники    наплічники з хутром і ремені на грудях
    Одяг-тіло-<тип>-набедреник    шкіряна спідниця з пластинами
    Одяг-тіло-<тип>-пояс          пояси (окремих важких поясів у items.json немає)
    Одяг-рукавиці-<тип>-наручі    наручі
    Одяг-взуття-<тип>-чоботи      чоботи з хутром

Деталі несуть текстуру скульпту (матеріал `скульпт-одяг`): гра їх не перефарбовує.

Поза спокою моделі гри — не поза скульпту (скелет розводить руки). Тож усе рахується в позі
скульпту, на ігровій сітці до скелета (`3-сітка/<модель>.glb`, ті самі вершини), а в позу спокою
деталі переносить обернений скінінг: матриці кісток «спокій → скульпт» підбираються найменшими
квадратами за вершинами тіла.

    blender -b <6-волосся/модель.blend> -P tools/blender/odiah_zi_skulptu.py -- \
        <вдягнений.glb> <вихід.blend> --сітка <3-сітка/модель.glb> [--тип важка] [--огляд <png>]
        [--колір 0.16] [--зазор 0.004]
"""
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

A = sys.argv[sys.argv.index("--") + 1:]
SKULPT, VYHID = os.path.abspath(A[0]), os.path.abspath(A[1])


def arg(k, typ, d):
    return typ(A[A.index(k) + 1]) if k in A else d


def log(*a):
    print("[одяг]", *a, flush=True)


TYP = arg("--тип", str, "важка")
T_KOLIR = arg("--колір", float, 0.16)      # різниця кольору «не шкіра» (корінь із лінійного RGB)
ZAZOR = arg("--зазор", float, 0.006)       # річ не ближче до шкіри, ніж стільки
DALEKO = arg("--далеко", float, 0.05)      # далі від шкіри — одяг навіть кольору шкіри (хутро)

rig = bpy.data.objects["Human.rig"]
tilo = bpy.data.objects["Тіло"]
for pb in rig.pose.bones:
    pb.matrix_basis.identity()
bpy.context.view_layer.update()


def podibnist(X, Y, masshtab=True):
    """Umeyama: s, R, t таке, що s·R·x + t ≈ y."""
    mx, my = X.mean(0), Y.mean(0)
    Xc, Yc = X - mx, Y - my
    U, S, Vt = np.linalg.svd(Yc.T @ Xc / len(X))
    D = np.eye(3)
    if np.linalg.det(U) * np.linalg.det(Vt) < 0:
        D[2, 2] = -1
    R = U @ D @ Vt
    s = float(np.trace(np.diag(S) @ D) / (Xc ** 2).sum() * len(X)) if masshtab else 1.0
    return s, R, my - s * R @ mx


def kartynka(mat):
    for n in mat.node_tree.nodes:
        if n.type == "BSDF_PRINCIPLED" and n.inputs["Base Color"].links:
            v = n.inputs["Base Color"].links[0].from_node
            while v.type != "TEX_IMAGE" and v.inputs and v.inputs[0].links:
                v = v.inputs[0].links[0].from_node
            if v.type == "TEX_IMAGE":
                return v.image
    return next(n.image for n in mat.node_tree.nodes if n.type == "TEX_IMAGE" and n.image)


def pikseli(im):
    w, h_ = im.size
    return np.array(im.pixels[:], np.float32).reshape(h_, w, 4)[..., :3]


def zrazok(px, uv):
    h_, w = px.shape[:2]
    return px[np.clip((uv[:, 1] % 1.0 * h_).astype(int), 0, h_ - 1), np.clip((uv[:, 0] % 1.0 * w).astype(int), 0, w - 1)]


# ── тіло гри: ваги (поза спокою) і та сама сітка в позі скульпту ─────────
mw = np.array(tilo.matrix_world)
BR = np.array([v.co[:] for v in tilo.data.vertices]) @ mw[:3, :3].T + mw[:3, 3]
hrupy = [g.name for g in tilo.vertex_groups]
kistky = {b.name for b in rig.data.bones}
W = np.zeros((len(BR), len(hrupy)), np.float32)
for v in tilo.data.vertices:
    for g in v.groups:
        if hrupy[g.group] in kistky:
            W[v.index, g.group] = g.weight
W /= np.maximum(W.sum(1, keepdims=True), 1e-6)
t_kistka = np.array([hrupy[i] for i in W.argmax(1)])

do = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=os.path.abspath(arg("--сітка", str, "")))
ss = next(o for o in bpy.data.objects if o not in do and o.type == "MESH")
bpy.ops.object.select_all(action="DESELECT")
ss.select_set(True)
bpy.context.view_layer.objects.active = ss
bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bm = bmesh.new()
bm.from_mesh(ss.data)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
bm.to_mesh(ss.data)
bm.free()
tm = ss.data
BV = np.array([v.co[:] for v in tm.vertices])
if len(BV) != len(BR):
    raise SystemExit("[одяг] сітка скульпту (%d вершин) не та, що в моделі (%d)" % (len(BV), len(BR)))
# матриці кісток «спокій → скульпт»: BV_i = Σ_b w_ib · M_b · [BR_i, 1]
akt = [i for i in range(W.shape[1]) if W[:, i].max() > 0.01]
R1 = np.concatenate([BR, np.ones((len(BR), 1))], 1)
Aw = np.concatenate([W[:, [b]] * R1 for b in akt], 1)            # (n, 4·кісток)
Mx, *_ = np.linalg.lstsq(Aw.astype(np.float64), BV.astype(np.float64), rcond=None)
M = {b: Mx[4 * j:4 * j + 4].T for j, b in enumerate(akt)}        # 3×4 кожна
nev = np.linalg.norm(Aw @ Mx - BV, axis=1)
log("спокій → скульпт: кісток %d, нев'язка медіана %.1f мм, 99 %%: %.1f мм" % (len(akt), np.median(nev) * 1000, np.percentile(nev, 99) * 1000))

bvh_t = BVHTree.FromPolygons([Vector(p) for p in BV], [tuple(p.vertices) for p in tm.polygons])
t_hran_v = np.array([p.vertices[0] for p in tm.polygons])
t_hran_mat = np.array([1 if "голова" in ss.material_slots[p.material_index].material.name else 0 for p in tm.polygons])
uvt = tm.uv_layers.active.data
t_hran_uv = np.array([np.mean([uvt[l].uv[:] for l in p.loop_indices], 0) for p in tm.polygons])
t_px = [pikseli(kartynka(s_.material)) for s_ in ss.material_slots]
t_hran_k = np.zeros((len(tm.polygons), 3), np.float32)
t_slot = np.array([p.material_index for p in tm.polygons])
for mi_, px in enumerate(t_px):
    m = t_slot == mi_
    t_hran_k[m] = zrazok(px, t_hran_uv[m])
Hb = BV[:, 2].max() - BV[:, 2].min()
log("тіло: %d вершин, зріст у позі скульпту %.3f м" % (len(BV), Hb))

# ── скульпт вдягненого ───────────────────────────────────────────────────
do = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=SKULPT)
novi = [o for o in bpy.data.objects if o not in do and o.type == "MESH"]
bpy.ops.object.select_all(action="DESELECT")
for o in novi:
    o.select_set(True)
bpy.context.view_layer.objects.active = novi[0]
if len(novi) > 1:
    bpy.ops.object.join()
sk = bpy.context.view_layer.objects.active
bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in list(bpy.data.objects):
    if o not in do and o is not sk:
        bpy.data.objects.remove(o)
bm = bmesh.new()
bm.from_mesh(sk.data)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
bmesh.ops.triangulate(bm, faces=bm.faces)
bm.to_mesh(sk.data)
bm.free()
sm = sk.data
P0 = np.array([v.co[:] for v in sm.vertices])
s_px = pikseli(kartynka(sk.material_slots[0].material))

# ── суміщення: зріст → ICP з відсіканням (одяг — викиди) ──────────────────
s0 = Hb / (P0[:, 2].max() - P0[:, 2].min())
P = P0 * s0
P += [(BV[:, 0].max() + BV[:, 0].min()) / 2 - (P[:, 0].max() + P[:, 0].min()) / 2,
      np.median(BV[:, 1]) - np.median(P[:, 1]), BV[:, 2].min() - P[:, 2].min()]
rng = np.random.default_rng(7)
idx = rng.choice(len(P), 9000, replace=False)


def icp(P, idx, mezhi, masshtab):
    for it, mezha in enumerate(mezhi):
        X, Y = [], []
        for i in idx:
            loc, _n, _f, d = bvh_t.find_nearest(Vector(P[i]))
            if loc is not None and d < mezha:
                X.append(P[i])
                Y.append(loc[:])
        if len(X) < 200:
            break
        s, R, t = podibnist(np.array(X), np.array(Y), masshtab)
        P = s * (P @ R.T) + t
    return P, len(X)


P, par = icp(P, idx, [0.08] * 10 + [0.04] * 15 + [0.02] * 20 + [0.01] * 15, True)
vid = np.array([bvh_t.find_nearest(Vector(P[i]))[3] for i in idx])
log("суміщення: пар %d з %d, медіана %.1f мм, 25 %%: %.1f мм" % (par, len(idx), np.median(vid) * 1000, np.percentile(vid, 25) * 1000))
sm.vertices.foreach_set("co", P.ravel())
sm.update()

# ── грані скульпту: відстань до шкіри, кістка, різниця кольору ────────────
uvs = sm.uv_layers.active.data
n = len(sm.polygons)
C = np.array([p.center[:] for p in sm.polygons])
s_uv = np.array([np.mean([uvs[l].uv[:] for l in p.loop_indices], 0) for p in sm.polygons])
s_k = zrazok(s_px, s_uv)
dist = np.zeros(n, np.float32)
zovni = np.zeros(n, bool)
bf = np.zeros(n, int)
for i in range(n):
    loc, nrm, f, d = bvh_t.find_nearest(Vector(C[i]))
    dist[i] = d
    bf[i] = f
    zovni[i] = (Vector(C[i]) - loc).dot(nrm) > -0.002
# зовнішня поверхня скульпту: з грані хоч один промінь виходить назовні, нічого не зачепивши.
# Pixal3D лишає всередині сміттєві грані (темні — зійшли б за «не шкіру») і шкіру під речами.
bvh_s = BVHTree.FromPolygons([Vector(p) for p in P], [tuple(p.vertices) for p in sm.polygons])
NAPR = [Vector(d).normalized() for d in
        [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]
        + [(a, b, c) for a in (-1, 1) for b in (-1, 1) for c in (-1, 1)]]
Nf = [p.normal.copy() for p in sm.polygons]
vydno = np.zeros(n, bool)
for i in range(n):
    c = Vector(C[i])
    nf = Nf[i]
    for d in [nf] + [d for d in NAPR if d.dot(nf) > 0.2]:
        if bvh_s.ray_cast(c + d * 0.0006, d)[0] is None:
            vydno[i] = True
            break
log("зовнішніх граней скульпту %d з %d" % (int(vydno.sum()), n))
kist = t_kistka[t_hran_v[bf]]
holova = t_hran_mat[bf] == 1
dk = np.linalg.norm(np.sqrt(np.clip(s_k, 0, 1)) - np.sqrt(np.clip(t_hran_k[bf], 0, 1)), axis=1)
# шкіра самого скульпту: медіана кольору граней, що лежать на тілі й схожі на нього
na_tili = (dist < 0.006) & (dk < T_KOLIR * 0.6) & ~holova
shk = np.median(s_k[na_tili], 0) if na_tili.sum() > 500 else np.median(t_hran_k, 0)
log("шкіра скульпту %s (зразків %d)" % (shk.round(3), int(na_tili.sum())))
# «не шкіра» — за барвою (частки каналів) або дуже темне (шкіра, залізо); яскравість шкіри сама
# гуляє від світлотіні, тож вона — не ознака. Тіло вдягненого скульпту повніше за наше, і частина
# речей (ремені на грудях) лежить ПІД нашою шкірою — тож відстань до шкіри тут не питається:
# річ потім виштовхується назовні.
def barva(k):
    return k / np.maximum(k.sum(-1, keepdims=True), 1e-4)


jas = s_k.sum(1)
ne_shkira = (np.linalg.norm(barva(s_k) - barva(shk), axis=1) > arg("--барва", float, 0.07)) | (jas < 0.35 * shk.sum())
odiah = vydno & ~holova & (ne_shkira | (zovni & (dist > DALEKO)))
KYST = ("hand_", "index_", "middle_", "ring_", "pinky_", "thumb_")
kyst = np.array([k.startswith(KYST) for k in kist])
odiah &= ~(kyst & ~ne_shkira)            # пальці скульпту стоять інакше — це не рукавиці
log("граней %d, одяг %d (%.0f %%)" % (n, int(odiah.sum()), 100.0 * odiah.mean()))

# сусіди граней — прибрати дрібні острівці одягу й залатати дрібні дірки
po_rebru = {}
for p in sm.polygons:
    for ek in p.edge_keys:
        po_rebru.setdefault(ek, []).append(p.index)
sus = [[] for _ in range(n)]
for fs in po_rebru.values():
    if len(fs) == 2:
        sus[fs[0]].append(fs[1])
        sus[fs[1]].append(fs[0])
plosh = np.array([p.area for p in sm.polygons])


def ostrivtsi(maska):
    bach = np.zeros(n, bool)
    for i0 in np.nonzero(maska)[0]:
        if bach[i0]:
            continue
        sh, st = [], [i0]
        bach[i0] = True
        while st:
            i = st.pop()
            sh.append(i)
            for u in sus[i]:
                if maska[u] and not bach[u]:
                    bach[u] = True
                    st.append(u)
        yield sh


for sh in list(ostrivtsi(odiah)):
    if plosh[sh].sum() < 0.0015:           # < 15 см² — сміття
        odiah[sh] = False
for sh in list(ostrivtsi(~odiah)):
    if plosh[sh].sum() < 0.0008:           # дірка < 8 см² у речі
        odiah[sh] = True
log("після чищення: одяг %d граней, %.2f м²" % (int(odiah.sum()), float(plosh[odiah].sum())))

# ── деталі за кісткою найближчої шкіри ───────────────────────────────────
bik = np.where(C[:, 0] > 0, "l", "r")


def za(*poch):
    return np.array([k.startswith(poch) for k in kist])


nohy = za("calf_", "foot_", "ball_")
ruky = za("lowerarm_", "hand_") | kyst
stehna = za("pelvis", "spine_01", "thigh_")
verh = ~(nohy | ruky | stehna)
z_poias = C[odiah & stehna, 2].max() - arg("--пояс-висота", float, 0.16) if (odiah & stehna).any() else 0
DETALI = [
    ("взуття", "чоботи", nohy, True, 0.25),
    ("рукавиці", "наручі", ruky, True, 0.7),
    ("тіло", "пояс", stehna & (C[:, 2] >= z_poias), False, 0.5),      # важких поясів у грі немає — пояс іде з панциром
    ("тіло", "набедреник", stehna & (C[:, 2] < z_poias), False, 0.3),
    ("тіло", "наплічники", verh, False, 0.35),
]
TRYK = {"чоботи": 7000, "наручі": 5000, "пояс": 5000, "набедреник": 8000, "наплічники": 14000}
mat = bpy.data.materials.new("скульпт-одяг")
mat.use_nodes = True
b_ = mat.node_tree.nodes["Principled BSDF"]
tx = mat.node_tree.nodes.new("ShaderNodeTexImage")
tx.image = kartynka(sk.material_slots[0].material)
mat.node_tree.links.new(tx.outputs[0], b_.inputs["Base Color"])
b_.inputs["Roughness"].default_value = 0.75
mat.use_backface_culling = False

Wk = W                                      # ваги тіла по вершинах
from mathutils import kdtree as _kd         # noqa: E402
kd = _kd.KDTree(len(BV))
for i, p in enumerate(BV):
    kd.insert(p, i)
kd.balance()
shkira_hr = ~odiah & ~holova & (dist < 0.03)   # шкіра скульпту біля тіла — для місцевого суміщення
gotovi = []
for komirka, nazva, maska, po_bokakh, zhorst in DETALI:
    chastyny = []
    for b in (("l", "r") if po_bokakh else (None,)):
        m = odiah & maska & ((bik == b) if b else True)
        if m.sum() < 100:
            continue
        # місцеве жорстке суміщення: шкіра скульпту тих самих кісток поруч із деталлю
        ms = shkira_hr & maska & ((bik == b) if b else True)
        R, t = np.eye(3), np.zeros(3)
        if ms.sum() > 300:
            Q = C[ms][rng.choice(int(ms.sum()), min(3000, int(ms.sum())), replace=False)]
            Q0 = Q.copy()
            Q, par = icp(Q, range(len(Q)), [0.03] * 10 + [0.015] * 15, False)
            _s, R, t = podibnist(Q0, Q, False)
            zs = np.linalg.norm(Q - Q0, axis=1)
            log("  %s %s: місцеве суміщення за %d точками шкіри, зсув %.1f мм" % (nazva, b or "", len(Q), np.median(zs) * 1000))
        fi = np.nonzero(m)[0]
        vi = sorted({v for f in fi for v in sm.polygons[f].vertices})
        nom = {v: j for j, v in enumerate(vi)}
        bm = bmesh.new()
        uvl = bm.loops.layers.uv.new("UVMap")
        vs = [bm.verts.new(P[v] @ R.T + t) for v in vi]
        for f in fi:
            p = sm.polygons[f]
            try:
                fa = bm.faces.new([vs[nom[v]] for v in p.vertices])
            except ValueError:
                continue
            for lp, l in zip(fa.loops, p.loop_indices):
                lp[uvl].uv = uvs[l].uv
            fa.smooth = True
        me = bpy.data.meshes.new("ч")
        bm.to_mesh(me)
        bm.free()
        chastyny.append(me)
    if not chastyny:
        log("деталі «%s» немає" % nazva)
        continue
    obs = []
    for me in chastyny:
        o = bpy.data.objects.new("ч", me)
        bpy.context.scene.collection.objects.link(o)
        obs.append(o)
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    if len(obs) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = "Одяг-%s-%s-%s" % (komirka, TYP, nazva)
    o.data.name = o.name
    o.data.materials.append(mat)
    tr = sum(len(p.vertices) - 2 for p in o.data.polygons)
    if tr > TRYK[nazva]:
        d = o.modifiers.new("с", "DECIMATE")
        d.ratio = TRYK[nazva] / tr
        bpy.ops.object.modifier_apply(modifier=d.name)
    # назовні: жодна вершина речі не ближче ZAZOR до шкіри й не під нею
    V = np.array([v.co[:] for v in o.data.vertices])
    vyshtovkhnuto = 0
    for i, p in enumerate(V):
        loc, nrm, _f, _d = bvh_t.find_nearest(Vector(p))
        gl = (Vector(p) - loc).dot(nrm)
        if gl < ZAZOR:
            V[i] = (loc + nrm * ZAZOR)[:]
            vyshtovkhnuto += 1
    o.data.vertices.foreach_set("co", V.ravel())
    o.data.update()
    log("  %s: виштовхнуто назовні %d з %d вершин" % (nazva, vyshtovkhnuto, len(V)))
    # ваги: 4 найближчі вершини тіла, далі — частково до середнього по деталі (тверда річ)
    V = np.array([v.co[:] for v in o.data.vertices])
    Wo = np.zeros((len(V), W.shape[1]), np.float32)
    for i, p in enumerate(V):
        for _co, j, d_ in kd.find_n(p, 4):
            Wo[i] += Wk[j] / (d_ + 0.005)
    Wo /= np.maximum(Wo.sum(1, keepdims=True), 1e-6)
    for zn in ((1, -1) if po_bokakh or nazva == "наплічники" else (0,)):
        mb = (V[:, 0] * zn > 0) if zn else np.ones(len(V), bool)
        if mb.any():
            Wo[mb] = Wo[mb] * (1 - zhorst) + Wo[mb].mean(0) * zhorst
    # у позу спокою: обернена до змішаної матриці кісток
    Wa = Wo[:, akt].astype(np.float64)
    Wa /= np.maximum(Wa.sum(1, keepdims=True), 1e-9)
    Mv = np.einsum("ib,bjk->ijk", Wa, np.array([M[b] for b in akt]))    # (n, 3, 4)
    Vr = np.einsum("ijk,ik->ij", np.linalg.inv(Mv[:, :, :3]), V - Mv[:, :, 3])
    o.data.vertices.foreach_set("co", Vr.ravel())
    o.data.update()
    for gi, gn in enumerate(hrupy):
        if gn not in kistky or Wo[:, gi].max() < 0.01:
            continue
        g = o.vertex_groups.new(name=gn)
        for i in np.nonzero(Wo[:, gi] > 0.01)[0]:
            g.add([int(i)], float(Wo[i, gi]), "REPLACE")
    o.parent = rig
    am = o.modifiers.new("Armature", "ARMATURE")
    am.object = rig
    gotovi.append(o)
    log("%s: %d трикутників, %d вершин" % (o.name, sum(len(p.vertices) - 2 for p in o.data.polygons), len(V)))
bpy.data.objects.remove(sk)
bpy.data.objects.remove(ss)
bpy.ops.wm.save_as_mainfile(filepath=VYHID)
log("→", VYHID)

OHLIAD = arg("--огляд", str, "")
if OHLIAD:
    for o in bpy.data.objects:
        if o.type == "MESH" and o.name.startswith(("Волосся", "Борода")):
            o.hide_render = True
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = sc.render.resolution_y = 900
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.3, 0.3, 0.32, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.8
    cam = bpy.data.objects.new("кам", bpy.data.cameras.new("кам"))
    sc.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = (BR[:, 2].max() - BR[:, 2].min()) * 1.25
    sc.camera = cam
    for i, (e, k) in enumerate([(3.0, (55, 0, 35)), (1.5, (60, 0, -120))]):
        L = bpy.data.objects.new("св%d" % i, bpy.data.lights.new("св%d" % i, "SUN"))
        L.data.energy = e
        L.rotation_euler = [math.radians(a) for a in k]
        sc.collection.objects.link(L)
    c = (BR.max(0) + BR.min(0)) / 2
    kadry = []
    for i, (kut, lyshe) in enumerate([(0, False), (140, False), (35, True), (215, True)]):
        tilo.hide_render = lyshe
        a = math.radians(kut)
        cam.location = (c[0] + math.sin(a) * 10, c[1] - math.cos(a) * 10, c[2])
        cam.rotation_euler = (math.pi / 2, 0, a)
        sc.render.filepath = OHLIAD + ".%d.png" % i
        bpy.ops.render.render(write_still=True)
        kadry.append(sc.render.filepath)
    ark = np.zeros((900, 3600, 4), np.float32)
    for i, f in enumerate(kadry):
        im = bpy.data.images.load(f)
        ark[:, i * 900:(i + 1) * 900] = np.array(im.pixels[:], np.float32).reshape(900, 900, 4)
        os.remove(f)
    im = bpy.data.images.new("ark", 3600, 900)
    im.pixels = ark.ravel()
    im.filepath_raw = OHLIAD
    im.file_format = "PNG"
    im.save()
    log("огляд →", OHLIAD)
