# Пахва в А-позі (25.11.2026, П-289): тіло зі скелетом (`rig_sitky.py`) — скульпт із опущеними
# руками, зворотним скінінгом переведений у спокій скелета (А-поза). Ваги плеча й тулуба на пахві
# переходять різко — у спокої клин шкіри від грудей до руки, біцепс «спаяний» з тулубом.
# Тут: тіло ставиться з опущеними руками (як у грі в русі), ваги навколо плечового суглоба
# згладжуються по сітці (перехід ширший), і спокій обчислюється наново зворотним скінінгом —
# з опущеними руками тіло лишається точно тим самим, змінюється лише А-поза.
#   blender -b <тіло.blend> -P tools/blender/pakhva_vahy.py -- <вихід.blend> \
#       [--кут-руки 12] [--радіус 0.16] [--проходів 20]
import math
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

A = sys.argv[sys.argv.index("--") + 1:]
def arg(k, d):
    return type(d)(A[A.index(k) + 1]) if k in A else d
VYHID = A[0]
KUT = arg("--кут-руки", 12.0)
RADIUS = arg("--радіус", 0.16)
PROHODIV = arg("--проходів", 6)
def log(*a):
    print("[пахва]", *a, flush=True)

arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
tilo = next(o for o in bpy.data.objects if o.type == "MESH" and o.name.startswith("Тіло"))
aw = arm.matrix_world

# 1. руки опущені (як `natiah_rich.py --поза-речі`)
for bik in ("_r", "_l"):
    pb = arm.pose.bones["upperarm" + bik]
    h, t = aw @ pb.head, aw @ pb.tail
    zn = 1.0 if h.x > 0 else -1.0
    tsil = Vector((zn * math.sin(math.radians(KUT)), 0.0, -math.cos(math.radians(KUT))))
    q = (t - h).normalized().rotation_difference(tsil)
    Rw = Matrix.Translation(h) @ q.to_matrix().to_4x4() @ Matrix.Translation(-h)
    pb.matrix = aw.inverted() @ Rw @ aw @ pb.matrix
    bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
te = tilo.evaluated_get(dg); tm = te.to_mesh()
P = np.array([tilo.matrix_world @ v.co for v in tm.vertices]); te.to_mesh_clear()
n = len(P)

# 2. ваги й сусіди
nazvy = [g.name for g in tilo.vertex_groups]
kist = np.array([nm in arm.pose.bones for nm in nazvy])
W = np.zeros((n, len(nazvy)))
for v in tilo.data.vertices:
    for g in v.groups:
        W[v.index, g.group] = g.weight
E = np.array([e.vertices[:] for e in tilo.data.edges])
stup = np.bincount(E.ravel(), minlength=n).astype(float)

# Причина (заміри 25.11): шкіра середини плеча (3–7 см від осі) у 20–40 % вершин має вагу
# хребта (spine_02/03) — з опущеними руками внутрішній бік руки прилягав до тулуба й узяв його
# ваги; у А-позі вона лишається з тулубом — перетинка від пахви до ліктя. Тут: належність до
# руки — за відстанню ВЗДОВЖ СІТКИ (поза з опущеними руками) від середини руки й від середини
# тулуба; ближче до руки — вага хребта/ключиці переходить кістці плеча, у складці — плавно.
import heapq
dl = np.linalg.norm(P[E[:, 0]] - P[E[:, 1]], axis=1)
sus = [[] for _ in range(n)]
for (a, b), l in zip(E, dl):
    sus[a].append((b, l)); sus[b].append((a, l))
def geod(dzherela):
    d_ = np.full(n, np.inf); h_ = [(0.0, int(i)) for i in dzherela]
    for _, i in h_:
        d_[i] = 0.0
    heapq.heapify(h_)
    while h_:
        dd, i = heapq.heappop(h_)
        if dd > d_[i]:
            continue
        for j, l in sus[i]:
            if dd + l < d_[j]:
                d_[j] = dd + l; heapq.heappush(h_, (dd + l, j))
    return d_
hol = np.array(nazvy)[W.argmax(1)]
CXb = float(np.median(P[:, 0]))
tulub_dz = np.nonzero(np.isin(hol, ["spine_02", "spine_03"]) & (np.abs(P[:, 0] - CXb) < 0.06))[0]
d_t = geod(tulub_dz)
zminy = 0
for b in ("_r", "_l"):
    pb = arm.pose.bones["upperarm" + b]
    h, t = np.array((aw @ pb.head)[:]), np.array((aw @ pb.tail)[:])
    ax = t - h; L = np.linalg.norm(ax); ax /= L
    s_ = (P - h) @ ax / L
    r_ = np.linalg.norm((P - h) - np.outer(s_ * L, ax), axis=1)
    iu, il = nazvy.index("upperarm" + b), nazvy.index("lowerarm" + b)
    ruka_dz = np.nonzero((hol == "upperarm" + b) & (s_ > 0.55) & (s_ < 0.75) & (r_ < 0.045))[0]
    d_r = geod(ruka_dz)
    f = np.clip((d_t - d_r) / 0.06, 0, 1)                   # 1 — рука, 0 — тулуб
    f = f * f * (3 - 2 * f)
    f *= np.clip((s_ - 0.12) / 0.15, 0, 1)                  # шапка плеча (дельта) — як була
    f *= (s_ < 1.1)
    chuzhi = np.array([nm.startswith(("spine", "clavicle")) for nm in nazvy])
    perenos = W[:, chuzhi] * f[:, None]
    zm = perenos.sum(1)
    W[:, chuzhi] -= perenos
    W[:, iu] += zm
    zminy += int((zm > 0.05).sum())
    log("рука%s: джерел руки %d, вершин із перенесеною вагою > 0,05: %d (до %.2f)" % (b, len(ruka_dz), (zm > 0.05).sum(), zm.max()))
# легке згладжування вздовж сітки довкола плеча — перехід у складці пахви без сходинки
J = {b: np.array((aw @ arm.pose.bones["upperarm" + b].head)[:]) for b in ("_r", "_l")}
d = np.minimum(np.linalg.norm(P - J["_r"], axis=1), np.linalg.norm(P - J["_l"], axis=1))
zona = d < RADIUS
zona &= ~np.array([h_.startswith(("hand", "lowerarm", "head", "thumb", "index", "middle", "ring", "pinky")) for h_ in hol])
syla = np.clip((RADIUS - d) / (0.35 * RADIUS), 0, 1) * zona
log("зона згладжування: %d вершин (радіус %.2f м)" % (zona.sum(), RADIUS))
W0 = W.copy()
for _ in range(PROHODIV):
    S = np.zeros_like(W)
    np.add.at(S, E[:, 0], W[E[:, 1]]); np.add.at(S, E[:, 1], W[E[:, 0]])
    Wm = S / np.maximum(stup, 1)[:, None]
    W = W + (0.5 * syla)[:, None] * (Wm - W)
W[:, ~kist] = 0
o = np.argsort(-W, 1)[:, 4:]
np.put_along_axis(W, o, 0, 1)
W /= np.maximum(W.sum(1, keepdims=True), 1e-8)
log("ваги: найбільша зміна %.3f, середня в зоні %.3f" % (np.abs(W - W0).max(), np.abs(W - W0)[zona].sum(1).mean()))

# 3. новий спокій: зворотний скінінг пози з опущеними руками
D = {}
for j, nm in enumerate(nazvy):
    if kist[j]:
        pb = arm.pose.bones[nm]
        D[j] = np.array(aw @ pb.matrix @ pb.bone.matrix_local.inverted() @ aw.inverted())
mi = np.array(tilo.matrix_world.inverted())
V2 = np.zeros_like(P)
for i in range(n):
    Sm = np.zeros((4, 4))
    for j in np.nonzero(W[i] > 0)[0]:
        Sm += W[i, j] * D[j]
    V2[i] = (mi @ (np.linalg.inv(Sm) @ np.append(P[i], 1.0)))[:3]
V0 = np.array([v.co[:] for v in tilo.data.vertices])
tilo.data.vertices.foreach_set("co", V2.ravel()); tilo.data.update()
for j, nm in enumerate(nazvy):
    g = tilo.vertex_groups[nm]
    g.remove(list(range(n)))
    ids = np.nonzero(W[:, j] > 0)[0]
    for i in ids:
        g.add([int(i)], float(W[i, j]), "REPLACE")
log("спокій перераховано: зсув вершин до %.1f см (у зоні)" % (100 * np.linalg.norm(V2 - V0, axis=1).max()))
for pb in arm.pose.bones:
    pb.matrix_basis.identity()
bpy.ops.wm.save_as_mainfile(filepath=VYHID)
log("збережено", VYHID)
