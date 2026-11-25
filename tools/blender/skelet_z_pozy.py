# Скелет і ваги з тіла в позі скульпту (25.11.2026, П-289). Слово замовника: «на етапі тіло-4 ще
# не виставляли точки прив'язок — перестворити з нього», «спробуй ті суглоби що вибрано автоматично».
# Вхід — файл `rig_sitky.py --до-суглобів` (після `skelet_tiunynh.py` чи рук замовника): тіло-4 з
# опущеними руками, спокій скелета = поза скульпту; у властивостях — спокій гри (А-поза) і поза.
#   1. ваги — зі старого тіла раси за номером вершини (те саме тіло-4, ті самі вершини):
#      хребет, ноги, голова, кисті й пальці; рука (плече, передпліччя) — наново за відстанню до
#      нових кісток (обернений квадрат відстані до відрізків кісток, 4-й степінь);
#   2. під пахвою рука прилягає до тулуба — поділ геометричний (як `pakhva_vahy.py`): зовні від
#      внутрішнього краю руки — лише кістки руки, всередині — лише хребет; перехід 1,5 см;
#   3. скелет — у спокій гри з новими суглобами, тіло — туди ж зворотним скінінгом.
#   blender -b <суглоби-центр.blend> -P tools/blender/skelet_z_pozy.py -- <старе тіло.blend> <вихід.blend>
import json
import sys

import bpy
import numpy as np
from mathutils import Matrix

A = sys.argv[sys.argv.index("--") + 1:]
STARE, VYHID = A[0], A[1]
def log(*a):
    print("[скелет з пози]", *a, flush=True)

rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
tilo = bpy.data.objects["Тіло"]
aw = np.array(rig.matrix_world)
P = np.array([tilo.matrix_world @ v.co for v in tilo.data.vertices])
n = len(P)
Ms = {b.name: aw @ np.array(b.matrix_local) for b in rig.data.bones}          # поза скульпту (світ)
POZA = {k: np.array(v) for k, v in json.loads(rig["поза_основи"]).items()}

# ── 1. старі ваги за номером вершини ──────────────────────────────────
with bpy.data.libraries.load(STARE) as (src, dst):
    dst.objects = [nm for nm in src.objects if nm.startswith("Тіло")]
staryi = dst.objects[0]
assert len(staryi.data.vertices) == n, "старе тіло має %d вершин, тіло-4 — %d" % (len(staryi.data.vertices), n)
nazvy = [g.name for g in staryi.vertex_groups]
kosti = list(rig.data.bones.keys())
W = np.zeros((n, len(kosti)))
for v in staryi.data.vertices:
    for g in v.groups:
        nm = nazvy[g.group]
        if nm in kosti:
            W[v.index, kosti.index(nm)] = g.weight
log("старі ваги: вершин %d, кісток із вагою %d" % (n, int((W.sum(0) > 0).sum())))
hol = np.array(kosti)[W.argmax(1)]

def vidrizok(p, a, b):
    ab = b - a
    t = np.clip(((p - a) @ ab) / (ab @ ab), 0, 1)
    return np.linalg.norm(p - (a + np.outer(t, ab)), axis=1)

E = np.array([e.vertices[:] for e in tilo.data.edges])
stup = np.bincount(E.ravel(), minlength=n).astype(float)
CX = float(np.median(P[:, 0]))
# шкіра руки, що вздовж сітки ближча до середини руки, ніж до середини тулуба, — вага
# хребта/ключиці переходить плечу (як `pakhva_vahy.py`; інакше біцепс «спаяний» з тулубом)
import heapq
dl = np.linalg.norm(P[E[:, 0]] - P[E[:, 1]], axis=1)
sus = [[] for _ in range(n)]
for (a, b_), l in zip(E, dl):
    sus[a].append((b_, l)); sus[b_].append((a, l))
def geod(dz):
    d_ = np.full(n, np.inf); h_ = [(0.0, int(i)) for i in dz]
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
d_t = geod(np.nonzero(np.isin(hol, ["spine_02", "spine_03"]) & (np.abs(P[:, 0] - CX) < 0.06))[0])
chuzhi = np.array([k.startswith(("spine", "clavicle")) for k in kosti])
for b in ("_r", "_l"):
    h = Ms["upperarm" + b][:3, 3]; t = (aw @ np.append(np.array(rig.data.bones["upperarm" + b].tail_local), 1))[:3]
    ax = (t - h) / np.linalg.norm(t - h); L = np.linalg.norm(t - h)
    s_ = (P - h) @ ax / L
    r_ = np.linalg.norm((P - h) - np.outer(s_ * L, ax), axis=1)
    d_r = geod(np.nonzero((hol == "upperarm" + b) & (s_ > 0.55) & (s_ < 0.75) & (r_ < 0.045))[0])
    f = np.clip((d_t - d_r) / 0.06, 0, 1); f = f * f * (3 - 2 * f)
    f *= np.clip((s_ - 0.12) / 0.15, 0, 1) * (s_ < 1.1)
    per = W[:, chuzhi] * f[:, None]
    W[:, chuzhi] -= per; W[:, kosti.index("upperarm" + b)] += per.sum(1)
    log("рука%s: вагу хребта/ключиці перенесено плечу в %d вершинах" % (b, int((per.sum(1) > 0.05).sum())))
hol = np.array(kosti)[W.argmax(1)]
for b in ("_r", "_l"):
    lan = ["upperarm" + b, "lowerarm" + b, "hand" + b]
    hv = {k: Ms[k][:3, 3] for k in lan}
    tv = {k: (aw @ np.append(np.array(rig.data.bones[k].tail_local), 1))[:3] for k in lan}
    ruka = np.isin(hol, ["upperarm" + b, "lowerarm" + b])
    D = np.stack([vidrizok(P, hv[k], tv[k]) for k in lan], 1) + 1e-3
    w = 1 / D ** 4
    w /= w.sum(1, keepdims=True)
    idx = [kosti.index(k) for k in lan]
    chastka = W[:, idx].sum(1)                     # частка руки лишається, розподіл — за відстанню
    for j, k in enumerate(idx):
        W[ruka, k] = (chastka * w[:, j])[ruka]
    # ── 2. поділ під пахвою ──
    h = hv["upperarm" + b]; t = tv["upperarm" + b]
    ax = (t - h) / np.linalg.norm(t - h); Ld = np.linalg.norm(t - h)
    zn = np.sign(h[0] - CX)
    iu = kosti.index("upperarm" + b)
    ruchni = np.array([k.startswith(("upperarm" + b, "lowerarm" + b)) for k in kosti])
    tulubni = np.array([k.startswith(("spine", "clavicle")) for k in kosti])
    s_ = (P - h) @ ax
    vis = h + np.outer(s_, ax)
    r3 = np.linalg.norm(P - vis, axis=1)
    smuga = (P[:, 2] < h[2] - 0.04) & (s_ > 0) & (s_ < 0.85 * Ld)
    yadro = smuga & ruka
    a_ = np.zeros(n); obr = np.zeros(n, bool)
    for z in np.arange(h[2] - Ld, h[2] - 0.04, 0.01):
        q = yadro & (np.abs(P[:, 2] - z) < 0.008)
        if q.sum() < 6:
            continue
        R = np.percentile(r3[q], 75)
        sh = smuga & (np.abs(P[:, 2] - z) < 0.005) & (r3 < R + 0.05)
        mezha = (vis[sh, 0] - CX) * zn - R * 0.95
        a_[sh] = np.clip(((P[sh, 0] - CX) * zn - mezha) / 0.015 + 0.5, 0, 1)
        obr |= sh
    Wt = W[:, tulubni] * (a_ * obr)[:, None]
    W[:, tulubni] -= Wt; W[:, iu] += Wt.sum(1)
    Wr = W[:, ruchni] * ((1 - a_) * obr)[:, None]
    zr = Wr.sum(1); W[:, ruchni] -= Wr
    z_s3 = Ms["spine_03"][2, 3]
    ks = np.where(P[:, 2] > z_s3, kosti.index("spine_03"), kosti.index("spine_02"))
    np.add.at(W, (np.arange(n), ks), zr)
    log("рука%s: вершин руки %d, ваги за відстанню до нових кісток; під пахвою рука %d, тулуб %d"
        % (b, ruka.sum(), int((a_ * obr > 0.5).sum()), int((zr > 0.05).sum())))
# легке згладжування довкола плечей
J = [Ms["upperarm" + b][:3, 3] for b in ("_r", "_l")]
d = np.minimum(*[np.linalg.norm(P - j, axis=1) for j in J])
syla = np.clip((0.16 - d) / 0.056, 0, 1) * ~np.array([h_.startswith(("hand", "head", "thumb", "index", "middle", "ring", "pinky")) for h_ in hol])
for _ in range(6):
    S = np.zeros_like(W)
    np.add.at(S, E[:, 0], W[E[:, 1]]); np.add.at(S, E[:, 1], W[E[:, 0]])
    W = W + (0.5 * syla)[:, None] * (S / np.maximum(stup, 1)[:, None] - W)
o = np.argsort(-W, 1)[:, 4:]
np.put_along_axis(W, o, 0, 1)
W /= np.maximum(W.sum(1, keepdims=True), 1e-8)

# ── 3. спокій гри з новими суглобами: R'_b = R'_бат · Ms_бат⁻¹ · Ms_b · P_b⁻¹ ──
awi = np.linalg.inv(aw)
Rn = {}
poriadok = []
def _obh(b):
    poriadok.append(b)
    for c in b.children:
        _obh(c)
for b in rig.data.bones:
    if b.parent is None:
        _obh(b)
for b in poriadok:                              # батьки раніше дітей
    Pb = POZA.get(b.name, np.eye(4))
    msb = awi @ Ms[b.name]
    if b.parent:
        Rn[b.name] = Rn[b.parent.name] @ np.linalg.inv(awi @ Ms[b.parent.name]) @ msb @ np.linalg.inv(Pb)
    else:
        Rn[b.name] = msb @ np.linalg.inv(Pb)
dovzh = {b.name: b.length for b in rig.data.bones}
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
for eb in rig.data.edit_bones:
    eb.use_connect = False
for eb in rig.data.edit_bones:
    eb.matrix = Matrix(Rn[eb.name].tolist())
    eb.length = dovzh[eb.name]
bpy.ops.object.mode_set(mode="OBJECT")
# зворотний скінінг: вершина в позі скульпту → спокій гри
Dm = {k: Ms[k] @ np.linalg.inv(aw @ Rn[k]) for k in kosti}
mi = np.array(tilo.matrix_world.inverted())
V2 = np.zeros_like(P)
for i in range(n):
    Sm = np.zeros((4, 4))
    for j in np.nonzero(W[i] > 0)[0]:
        Sm += W[i, j] * Dm[kosti[j]]
    V2[i] = (mi @ (np.linalg.inv(Sm) @ np.append(P[i], 1.0)))[:3]
tilo.data.vertices.foreach_set("co", V2.ravel()); tilo.data.update()
tilo.vertex_groups.clear()
for j, k in enumerate(kosti):
    ids = np.nonzero(W[:, j] > 0)[0]
    if len(ids):
        g = tilo.vertex_groups.new(name=k)
        for i in ids:
            g.add([int(i)], float(W[i, j]), "REPLACE")
md = next((m for m in tilo.modifiers if m.type == "ARMATURE"), None) or tilo.modifiers.new("скелет", "ARMATURE")
md.object = rig
tilo.parent = rig
tilo.matrix_parent_inverse = rig.matrix_world.inverted()
tilo.hide_select = False
rig.data.pose_position = "POSE"
rig.data.display_type = "OCTAHEDRAL"; rig.data.show_names = False; rig.show_in_front = False
# перевірка: у позі скульпту тіло = тіло-4
for pb in rig.pose.bones:
    pb.matrix_basis = Matrix(POZA.get(pb.name, np.eye(4)).tolist())
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get(); te = tilo.evaluated_get(dg); tm = te.to_mesh()
Pc = np.array([tilo.matrix_world @ v.co for v in tm.vertices]); te.to_mesh_clear()
log("перевірка: у позі скульпту відхилення від тіла-4 до %.2f мм" % (1000 * np.linalg.norm(Pc - P, axis=1).max()))
for pb in rig.pose.bones:
    pb.matrix_basis.identity()
bpy.ops.wm.save_as_mainfile(filepath=VYHID)
log("→", VYHID)
