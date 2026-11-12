"""Річ броні зі скульпту ЗОНИ великим планом (13.11.2026, `spec/сети-броні-дослідження.md`).

Слово замовника: «якість зараз неналежна, треба якісніше», «так роби. Порядок: взуття → наручі →
наплічники з ременями → пояс із набедреником». Пілот (`odiah_zi_skulptu.py`) знімав усі речі з
одного скульпту цілої постаті — на річ лишалось мало деталі. Тут на кожну річ свій скульпт: наша
частина тіла великим планом в одній речі. Кроки — як у художника, але кодом:

  1. суміщення скульпту зони з нашим тілом ЗА ШКІРОЮ (стегна й коліна над чобітьми), у позі скульпту;
  2. річ — зовнішні грані «не кольору шкіри», зв'язні шматки на кістках зони;
  3. замкнена форма з товщиною (без плівок і дірок): стінка всередину + воксельний ремеш;
  4. ігрова сітка: спрощення до бюджету, своя розгортка, ЗАПІКАННЯ кольору й нормалей із
     неспрощеного скульпту (текстура 2048 на річ);
  5. ваги — лише кістки зони свого боку (халява не тягнеться за стегном);
  6. тіло під річчю ховається: атрибут вершин `під_одяг` (канал зони) → `hide_under` шейдера шкіри;
  7. у позу спокою — оберненим скінінгом (матриці «спокій → скульпт» найменшими квадратами).

    blender -b <модель.blend> -P tools/blender/odiah_zona.py -- <зона.glb> <вихід.blend> \
        --сітка <3-сітка/модель.glb> --зона чоботи|наручі|наплічники|пояс [--верх м] [--низ м]
        [--тип важка] [--огляд <png>]

`--верх`, `--низ` — на якій висоті тіла (м, у позі скульпту) кадр зони обрізано згори й знизу;
без ключа з того боку кадр доходить до краю тіла (підошви, маківка, кінчики пальців). Зона
не знає раси: усе береться з моделі (`Тіло`, `Human.rig`) і її сітки в позі скульпту.
"""
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector, kdtree
from mathutils.bvhtree import BVHTree

A = sys.argv[sys.argv.index("--") + 1:]
SKULPT, VYHID = os.path.abspath(A[0]), os.path.abspath(A[1])
PREF = os.path.splitext(VYHID)[0]


def arg(k, typ, d):
    return typ(A[A.index(k) + 1]) if k in A else d


def log(*a):
    print("[зона]", *a, flush=True)


TYP = arg("--тип", str, "важка")
ZONA = arg("--зона", str, "чоботи")
# комірка гри; кістки зони; канал `під_одяг`; кістки, що ховаються під річчю завжди; бюджет
# трикутників; де в скульпті зони шкіра (частки його висоти) — звідти береться колір шкіри
PALTSI = ("index_", "middle_", "ring_", "pinky_", "thumb_")
ZONY = {
    # komirka — комірка гри; kistky — кістки, на яких сидить річ; kadr — кістки тіла, що є в кадрі
    # зони (None — усі; з них і ціль суміщення); kanal — канал `під_одяг` (None — тіло не ховати);
    # zavzhdy — кістки, що під річчю ховаються цілком; tryk — бюджет трикутників; tex — текстура;
    # pidhin — місцева підгонка речі («нога»: за віссю гомілки й стопою; «шкіра»: за шкірою поруч);
    # pid_kistky, vidstup — кінцівка під річчю ховається за висотою: вершини цих кісток між низом
    # речі + vidstup[0] і її верхом − vidstup[1] (річ охоплює кінцівку цілком);
    # dzerkalo — у кадрі одна кінцівка (бік `bik`), друга робиться дзеркалом; tverdi/tverdist —
    # частини, що не гнуться (ваги — до середнього по своєму боку); zaminiuie — пілотні деталі геть
    "чоботи": dict(komirka="взуття", kistky=("calf_", "foot_", "ball_"),
                   kadr=("pelvis", "thigh_", "calf_", "foot_", "ball_", "hand_") + PALTSI,
                   kanal=2, zavzhdy=("foot_", "ball_"), tryk=12000, tex=2048, pidhin="нога",
                   pid_kistky=("calf_",), vidstup=(0.0, 0.05)),
    "наручі": dict(komirka="рукавиці", kistky=("lowerarm_", "hand_"),
                   kadr=("upperarm_", "lowerarm_", "hand_") + PALTSI,
                   kanal=3, zavzhdy=(), tryk=9000, tex=2048, dzerkalo=True, bik="_r", pidhin="шкіра",
                   pid_kistky=("lowerarm_",), vidstup=(0.03, 0.04)),
    "наплічники": dict(komirka="тіло", kistky=("clavicle_", "upperarm_", "spine_01", "spine_02", "spine_03", "neck_01"),
                       kadr=None, kanal=None, zavzhdy=(), tryk=18000, tex=4096,
                       tverdi=("clavicle_", "upperarm_"), tverdist=0.6),
    "пояс": dict(komirka="тіло", kistky=("pelvis", "spine_01", "spine_02", "thigh_"),
                 kadr=("pelvis", "spine_01", "spine_02", "thigh_", "lowerarm_", "hand_") + PALTSI,
                 kanal=None, zavzhdy=(), tryk=16000, tex=4096, zaminiuie=("набедреник",)),
}
Z = ZONY[ZONA]
BARVA = arg("--барва", float, 0.07)
STINKA = arg("--стінка", float, 0.008)
VOKSEL = arg("--воксель", float, 0.003)
ROZMIR = arg("--текстура", int, Z["tex"])

rig = bpy.data.objects["Human.rig"]
tilo = bpy.data.objects["Тіло"]
for pb in rig.pose.bones:
    pb.matrix_basis.identity()
bpy.context.view_layer.update()


def podibnist(X, Y, masshtab=True):
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
    return next(n.image for n in mat.node_tree.nodes if n.type == "TEX_IMAGE" and n.image
                and n.image.colorspace_settings.name != "Non-Color")


def pikseli(im):
    w, h_ = im.size
    return np.array(im.pixels[:], np.float32).reshape(h_, w, 4)[..., :3]


def zrazok(px, uv):
    h_, w = px.shape[:2]
    return px[np.clip((uv[:, 1] % 1.0 * h_).astype(int), 0, h_ - 1), np.clip((uv[:, 0] % 1.0 * w).astype(int), 0, w - 1)]


def barva(k):
    return k / np.maximum(k.sum(-1, keepdims=True), 1e-4)


def aktyv(o):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o


def vvesty(path):
    do = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    novi = [o for o in bpy.data.objects if o not in do and o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in novi:
        o.select_set(True)
    bpy.context.view_layer.objects.active = novi[0]
    if len(novi) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for x in list(bpy.data.objects):
        if x not in do and x is not o:
            bpy.data.objects.remove(x)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.to_mesh(o.data)
    bm.free()
    return o


# ── тіло гри: ваги (спокій) і та сама сітка в позі скульпту ─────────────
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
ss = vvesty(os.path.abspath(arg("--сітка", str, "")))
tm = ss.data
BV = np.array([v.co[:] for v in tm.vertices])
if len(BV) != len(BR):
    raise SystemExit("[зона] сітка скульпту (%d вершин) не та, що в моделі (%d)" % (len(BV), len(BR)))
akt = [i for i in range(W.shape[1]) if W[:, i].max() > 0.01]
R1 = np.concatenate([BR, np.ones((len(BR), 1))], 1)
Aw = np.concatenate([W[:, [b]] * R1 for b in akt], 1)
Mx, *_ = np.linalg.lstsq(Aw.astype(np.float64), BV.astype(np.float64), rcond=None)
M = np.array([Mx[4 * j:4 * j + 4].T for j in range(len(akt))])
bvh_t = BVHTree.FromPolygons([Vector(p) for p in BV], [tuple(p.vertices) for p in tm.polygons])
t_hran_v = np.array([p.vertices[0] for p in tm.polygons])
kd = kdtree.KDTree(len(BV))
for i, p in enumerate(BV):
    kd.insert(p, i)
kd.balance()
log("тіло: %d вершин, зріст у позі скульпту %.3f м" % (len(BV), BV[:, 2].max() - BV[:, 2].min()))

# ціль суміщення — лише ті частини тіла, що є в кадрі зони (рука біля стегна не липне до стегна)
def u_kadri(bik):
    if Z["kadr"] is None:
        return np.ones(len(BV), bool)
    return np.array([k.startswith(Z["kadr"]) and (bik is None or not k.endswith(("_l", "_r")) or k.endswith(bik))
                     for k in t_kistka])


# ── скульпт зони ─────────────────────────────────────────────────────────
sk = vvesty(SKULPT)
sm = sk.data
P_SYRE = np.array([v.co[:] for v in sm.vertices])
s_px = pikseli(kartynka(sk.material_slots[0].material))
n = len(sm.polygons)
uvs = sm.uv_layers.active.data
s_uv = np.array([np.mean([uvs[l].uv[:] for l in p.loop_indices], 0) for p in sm.polygons])
s_k = zrazok(s_px, s_uv)
tri = np.array([p.vertices[:] for p in sm.polygons])


def tsentry(P):
    return P[tri].mean(1)


# зовнішні грані: хоч один промінь виходить назовні
C0 = tsentry(P_SYRE)
bvh_s = BVHTree.FromPolygons([Vector(p) for p in P_SYRE], [tuple(t) for t in tri])
NAPR = [Vector(d).normalized() for d in
        [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]
        + [(a, b, c) for a in (-1, 1) for b in (-1, 1) for c in (-1, 1)]]
vydno = np.zeros(n, bool)
ep = 0.0006 * (P_SYRE[:, 2].max() - P_SYRE[:, 2].min())
for i, p in enumerate(sm.polygons):
    c = Vector(C0[i])
    for d in [p.normal] + [d for d in NAPR if d.dot(p.normal) > 0.2]:
        if bvh_s.ray_cast(c + d * ep, d)[0] is None:
            vydno[i] = True
            break
# колір шкіри скульпту: спершу грані, близькі барвою до шкіри нашого тіла, потім їх медіана
t_px = pikseli(kartynka(ss.material_slots[0].material))[::8, ::8].reshape(-1, 3)
t_shk = np.median(t_px[t_px.max(1) > 0.12], 0)
blyzki = vydno & (np.linalg.norm(barva(s_k) - barva(t_shk), axis=1) < 0.14) & (s_k.sum(1) > 0.3 * t_shk.sum())
shk = np.median(s_k[blyzki], 0) if blyzki.sum() > 500 else t_shk
jas = s_k.sum(1)
ne_shkira = (np.linalg.norm(barva(s_k) - barva(shk), axis=1) > BARVA) | (jas < 0.35 * shk.sum())
shkira = vydno & ~ne_shkira
log("зовнішніх граней %d з %d; шкіра тіла %s, скульпту %s, граней шкіри %d"
    % (int(vydno.sum()), n, t_shk.round(3), shk.round(3), int(shkira.sum())))

plosh0 = np.array([p.area for p in sm.polygons])
po_rebru = {}
for i, t_ in enumerate(tri):
    for a_, b_ in ((t_[0], t_[1]), (t_[1], t_[2]), (t_[2], t_[0])):
        po_rebru.setdefault((min(a_, b_), max(a_, b_)), []).append(i)
sus = [[] for _ in range(n)]
for fs in po_rebru.values():
    if len(fs) == 2:
        sus[fs[0]].append(fs[1])
        sus[fs[1]].append(fs[0])


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
        yield np.array(sh)


VERH = arg("--верх", float, 0.0)            # висота тіла (м), де кадр зони обрізано згори
NYZ = arg("--низ", float, -1.0)             # …і знизу; без ключа — край тіла в кадрі
rng = np.random.default_rng(7)
vysoki = []
varianty = [(False, Z.get("bik"))]
if Z.get("dzerkalo"):
    varianty.append((True, "_l" if Z["bik"] == "_r" else "_r"))
for dzerkalo, bik in varianty:
    P = P_SYRE * ([-1, 1, 1] if dzerkalo else [1, 1, 1])
    mk = u_kadri(bik)
    if VERH:
        mk &= BV[:, 2] < VERH
    if NYZ >= 0:
        mk &= BV[:, 2] > NYZ
    khmara = BV[mk]
    hran_k = np.nonzero(mk[t_hran_v])[0]
    bvh_k = BVHTree.FromPolygons([Vector(p) for p in BV], [tuple(tm.polygons[f].vertices) for f in hran_k])
    z_nyz = NYZ if NYZ >= 0 else khmara[:, 2].min()
    z_verh = VERH if VERH else khmara[:, 2].max()
    P = P * ((z_verh - z_nyz) / (P[:, 2].max() - P[:, 2].min()))
    P += [(khmara[:, 0].max() + khmara[:, 0].min()) / 2 - (P[:, 0].max() + P[:, 0].min()) / 2,
          np.median(khmara[:, 1]) - np.median(P[:, 1]), z_nyz - P[:, 2].min()]
    ish = np.nonzero(shkira)[0]
    ish = ish[rng.choice(len(ish), min(8000, len(ish)), replace=False)]
    for mezha in [0.08] * 10 + [0.04] * 15 + [0.02] * 20 + [0.01] * 20:
        Q = tsentry(P)[ish]
        X, Y = [], []
        for q in Q:
            loc, _n, _f, d = bvh_k.find_nearest(Vector(q))
            if d < mezha:
                X.append(q)
                Y.append(loc[:])
        if len(X) < 200:
            break
        s_, R, t = podibnist(np.array(X), np.array(Y))
        P = s_ * (P @ R.T) + t
    C = tsentry(P)
    vid = np.array([bvh_k.find_nearest(Vector(q))[3] for q in C[ish]])
    log("%sсуміщення за шкірою: пар %d з %d, медіана %.1f мм, 90 %%: %.1f мм"
        % ("дзеркало, " if dzerkalo else "", len(X), len(ish), np.median(vid) * 1000, np.percentile(vid, 90) * 1000))
    # річ: зв'язні шматки «не шкіри» на кістках зони
    plosh = plosh0 * (np.linalg.norm(P[tri[:, 1]] - P[tri[:, 0]], axis=1).mean()
                      / max(1e-9, np.linalg.norm(P_SYRE[tri[:, 1]] - P_SYRE[tri[:, 0]], axis=1).mean())) ** 2
    bf = np.array([bvh_t.find_nearest(Vector(c))[2] for c in C])
    kist = t_kistka[t_hran_v[bf]]
    u_zoni = np.array([k.startswith(Z["kistky"]) for k in kist])
    # грань речі має лежати біля кісток зони (вага > 0,15): генератор буває перемальовує шкіру
    # поза зоною (плече над наручем стало рожевим) — це «не шкіра», але й не річ
    zk_i = [i for i, g_ in enumerate(hrupy) if g_.startswith(Z["kistky"])]
    bilia = W[:, zk_i].sum(1)[t_hran_v[bf]] > 0.15
    rich = np.zeros(n, bool)
    for sh in ostrivtsi(vydno & ne_shkira & bilia):
        if plosh[sh].sum() > 0.003 and (plosh[sh] * u_zoni[sh]).sum() > 0.6 * plosh[sh].sum():
            rich[sh] = True
    for sh in list(ostrivtsi(vydno & ~rich)):       # дірки < 10 см² усередині речі
        if plosh[sh].sum() < 0.001:
            rich[sh] = True
    log("річ: %d граней, %.2f м²" % (int(rich.sum()), float(plosh[rich].sum())))
    # місцева підгонка: гомілка вдягненого скульпту стоїть не там, де наша (суміщено за стегнами),
    # а шкіри під чоботом немає. Халява — довкола осі нашої гомілки, підошва — під нашою стопою,
    # носок — туди ж, куди наші пальці. Для наручів — жорстке досуміщення за шкірою кисті й ліктя.
    for zn in ((1, -1) if Z.get("pidhin") else ()):
        bk = "_l" if zn > 0 else "_r"
        fi = np.nonzero(rich & (C[:, 0] * zn > 0))[0]
        if len(fi) < 200:
            continue
        vi = np.unique(tri[fi])
        L = BV[np.array([k.startswith(Z["kistky"]) and k.endswith(bk) for k in t_kistka])]
        Q0 = P[vi].copy()
        Q = Q0.copy()
        if Z["pidhin"] == "нога":
            for _ in range(8):
                X, Y = [], []
                z0 = max(L[:, 2].min() + 0.14, Q[:, 2].min() + 0.14)
                for z_ in np.arange(z0, min(Q[:, 2].max(), L[:, 2].max()), 0.02):
                    a_, b_ = Q[np.abs(Q[:, 2] - z_) < 0.01], L[np.abs(L[:, 2] - z_) < 0.01]
                    if len(a_) > 10 and len(b_) > 10:
                        ca, cb = a_.mean(0), b_.mean(0)
                        X.append(ca)
                        Y.append([cb[0], cb[1], ca[2]])
                st_q, st_l = Q[Q[:, 2] < Q[:, 2].min() + 0.10], L[L[:, 2] < L[:, 2].min() + 0.08]
                dz = (L[:, 2].min() - 0.02) - Q[:, 2].min()          # підошва 2 см нижче стопи
                ca, cb = st_q.mean(0), st_l.mean(0)
                ns_q = st_q[st_q[:, 1] < np.percentile(st_q[:, 1], 15)].mean(0)
                ns_l = st_l[st_l[:, 1] < np.percentile(st_l[:, 1], 15)].mean(0)
                for _k in range(4):
                    X += [ca, ns_q]
                    Y += [[cb[0], cb[1], ca[2] + dz], [ns_l[0], ns_l[1], ns_q[2] + dz]]
                _s, R, t = podibnist(np.array(X), np.array(Y), False)
                Q = Q @ R.T + t
        else:
            ms = shkira & np.array([k.startswith(Z["kadr"]) and k.endswith(bk) for k in kist]) & (C[:, 0] * zn > 0)
            if ms.sum() > 300:
                js = np.nonzero(ms)[0]
                js = js[rng.choice(len(js), min(3000, len(js)), replace=False)]
                G0 = C[js]
                G = G0.copy()
                for mezha in [0.03] * 10 + [0.015] * 15 + [0.008] * 10:
                    X, Y = [], []
                    for q in G:
                        loc, _n, _f, d = bvh_k.find_nearest(Vector(q))
                        if d < mezha:
                            X.append(q)
                            Y.append(loc[:])
                    if len(X) < 100:
                        break
                    _s, R, t = podibnist(np.array(X), np.array(Y), False)
                    G = G @ R.T + t
                _s, R, t = podibnist(G0, G, False)
                Q = Q0 @ R.T + t
        P[vi] = Q
        log("  підгонка %s%s: зсув медіана %.1f мм, найбільший %.1f мм"
            % (Z["pidhin"], bk, np.median(np.linalg.norm(Q - Q0, axis=1)) * 1000, np.linalg.norm(Q - Q0, axis=1).max() * 1000))
    # високополігональна річ — з текстурою скульпту (джерело запікання)
    bm = bmesh.new()
    bm.from_mesh(sm)
    bm.verts.ensure_lookup_table()
    for v in bm.verts:
        v.co = P[v.index]
    bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if not rich[f.index]], context="FACES")
    if dzerkalo:
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
    me_ = bpy.data.meshes.new("висока")
    bm.to_mesh(me_)
    bm.free()
    ob_ = bpy.data.objects.new("висока", me_)
    bpy.context.scene.collection.objects.link(ob_)
    ob_.data.materials.append(sk.material_slots[0].material)
    vysoki.append(ob_)
bpy.ops.object.select_all(action="DESELECT")
for ob_ in vysoki:
    ob_.select_set(True)
bpy.context.view_layer.objects.active = vysoki[0]
if len(vysoki) > 1:
    bpy.ops.object.join()
vys = bpy.context.view_layer.objects.active
vys_me = vys.data
bpy.data.objects.remove(sk)

# ── замкнена форма з товщиною → ігрова сітка ─────────────────────────────
nyz = bpy.data.objects.new("низька", vys_me.copy())
bpy.context.scene.collection.objects.link(nyz)
nyz.data.materials.clear()
aktyv(nyz)
m = nyz.modifiers.new("т", "SOLIDIFY")
m.thickness = STINKA
m.offset = -1.0
bpy.ops.object.modifier_apply(modifier=m.name)
m = nyz.modifiers.new("в", "REMESH")
m.mode = "VOXEL"
m.voxel_size = VOKSEL
m.use_smooth_shade = True
bpy.ops.object.modifier_apply(modifier=m.name)
# дрібні уламки ремешу — геть
bm = bmesh.new()
bm.from_mesh(nyz.data)
bm.verts.ensure_lookup_table()
seen, shm = set(), []
for v0 in bm.verts:
    if v0.index in seen:
        continue
    ost, st = [], [v0]
    seen.add(v0.index)
    while st:
        v = st.pop()
        ost.append(v)
        for e in v.link_edges:
            u = e.other_vert(v)
            if u.index not in seen:
                seen.add(u.index)
                st.append(u)
    shm.append(ost)
naib = max(len(s_) for s_ in shm)
for s_ in shm:
    if len(s_) < 0.05 * naib:
        bmesh.ops.delete(bm, geom=s_, context="VERTS")
# згладити перед спрощенням: шпичаки хутра спрощення перетворює на гострі уламки; дрібний
# рельєф (хутро, пряжки, шви) повернеться картою нормалей із неспрощеного скульпту
for _ in range(arg("--гладити", int, 10)):
    bmesh.ops.smooth_vert(bm, verts=bm.verts, factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
bm.to_mesh(nyz.data)
bm.free()
tr = sum(len(p.vertices) - 2 for p in nyz.data.polygons)
m = nyz.modifiers.new("с", "DECIMATE")
m.ratio = min(1.0, Z["tryk"] / tr)
bpy.ops.object.modifier_apply(modifier=m.name)
bpy.ops.object.shade_smooth()
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.004)
bpy.ops.object.mode_set(mode="OBJECT")
log("ігрова сітка: %d → %d трикутників, шматків %d" % (tr, sum(len(p.vertices) - 2 for p in nyz.data.polygons), sum(len(s_) >= 0.05 * naib for s_ in shm)))

# ── запікання: колір, нормалі, маска влучань ─────────────────────────────
mat = bpy.data.materials.new("скульпт-одяг-%s" % ZONA)
mat.use_nodes = True
nt = mat.node_tree
bsdf = nt.nodes["Principled BSDF"]
vuzol = nt.nodes.new("ShaderNodeTexImage")
nt.nodes.active = vuzol
nyz.data.materials.append(mat)
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.samples = 1
try:
    pr = bpy.context.preferences.addons["cycles"].preferences
    pr.compute_device_type = "OPTIX"
    pr.get_devices()
    for d in pr.devices:
        d.use = d.type == "OPTIX"
    sc.cycles.device = "GPU"
except Exception as e:
    log("запікання на процесорі:", e)
sc.view_settings.view_transform = "Standard"
bk = sc.render.bake
bk.use_selected_to_active = True
bk.cage_extrusion = 0.012
bk.max_ray_distance = 0.03
bk.margin = 6
bk.normal_space = "TANGENT"
bk.use_pass_direct = False
bk.use_pass_indirect = False
bk.use_pass_color = True
bpy.ops.object.select_all(action="DESELECT")
vys.select_set(True)
nyz.select_set(True)
bpy.context.view_layer.objects.active = nyz
vmat = vys.material_slots[0].material
vb = next(nd for nd in vmat.node_tree.nodes if nd.type == "BSDF_PRINCIPLED")
vb.inputs["Metallic"].default_value = 0.0
for l in list(vb.inputs["Metallic"].links):
    vmat.node_tree.links.remove(l)
karty = {}


def zapekty():
    for vyd, typ in (("колір", "DIFFUSE"), ("нормалі", "NORMAL"), ("маска", "EMIT")):
        im = karty.get(vyd + "-im") or bpy.data.images.new("%s-%s-%s" % (ZONA, TYP, vyd), ROZMIR, ROZMIR, alpha=False)
        if vyd != "колір":
            im.colorspace_settings.name = "Non-Color"
        vuzol.image = im
        if vyd == "маска" and "маска-im" not in karty:   # де промінь влучив у скульпт — біле
            em = vmat.node_tree.nodes.new("ShaderNodeEmission")
            em.inputs[0].default_value = (1, 1, 1, 1)
            vyh = next(nd for nd in vmat.node_tree.nodes if nd.type == "OUTPUT_MATERIAL")
            karty["стара-поверхня"] = vyh.inputs["Surface"].links[0].from_socket
            vmat.node_tree.links.new(em.outputs[0], vyh.inputs["Surface"])
        bpy.ops.object.bake(type=typ)
        karty[vyd] = np.array(im.pixels[:], np.float32).reshape(ROZMIR, ROZMIR, 4)
        karty[vyd + "-im"] = im


zapekty()
if karty["колір"][..., :3][karty["маска"][..., 0] > 0.5].mean() < 0.004:
    # відеокарта зайнята (ComfyUI) — OptiX мовчки віддає чорне: перепекти на процесорі
    log("запікання на відеокарті дало чорне — повтор на процесорі")
    sc.cycles.device = "CPU"
    vyh = next(nd for nd in vmat.node_tree.nodes if nd.type == "OUTPUT_MATERIAL")
    vmat.node_tree.links.new(karty["стара-поверхня"], vyh.inputs["Surface"])
    del karty["маска-im"]
    zapekty()
import cv2  # noqa: E402

vluch = karty["маска"][..., 0] > 0.5
uvm = np.zeros((ROZMIR, ROZMIR), np.uint8)
uvl = nyz.data.uv_layers.active.data
for p in nyz.data.polygons:
    pts = np.array([[uvl[l].uv.x * ROZMIR, uvl[l].uv.y * ROZMIR] for l in p.loop_indices], np.int32)
    cv2.fillPoly(uvm, [pts], 255)
uvm = cv2.dilate(uvm, np.ones((7, 7), np.uint8)) > 0
# промахи (внутрішня стінка, краї): колір — від сусідів, затемнений; нормаль — рівна
kol = karty["колір"][..., :3]
vag = vluch.astype(np.float32)
zal = kol * vag[..., None]
for sg in (4, 16, 64, 256):
    roz = cv2.GaussianBlur(zal, (0, 0), sg) / np.maximum(cv2.GaussianBlur(vag, (0, 0), sg)[..., None], 1e-4)
    bez = (vag < 0.5) & (cv2.GaussianBlur(vag, (0, 0), sg) > 0.02)
    kol[bez] = roz[bez] * 0.55
    vag[bez] = 1.0
nor = karty["нормалі"][..., :3]
nor[~vluch] = (0.5, 0.5, 1.0)
log("запікання: влучань %.0f %% розгортки" % (100.0 * (vluch & uvm).sum() / max(1, uvm.sum())))
for vyd, px in (("колір", kol), ("нормалі", nor)):
    im = karty[vyd + "-im"]
    full = np.ones((ROZMIR, ROZMIR, 4), np.float32)
    full[..., :3] = px
    im.pixels.foreach_set(full.ravel())
    im.filepath_raw = "%s-%s-%s.png" % (PREF, ZONA, vyd)
    im.file_format = "PNG"
    im.save()
bpy.data.images.remove(karty["маска-im"])
nt.nodes.remove(vuzol)
tc = nt.nodes.new("ShaderNodeTexImage")
tc.image = karty["колір-im"]
nt.links.new(tc.outputs[0], bsdf.inputs["Base Color"])
tn = nt.nodes.new("ShaderNodeTexImage")
tn.image = karty["нормалі-im"]
nm = nt.nodes.new("ShaderNodeNormalMap")
nt.links.new(tn.outputs[0], nm.inputs["Color"])
nt.links.new(nm.outputs[0], bsdf.inputs["Normal"])
bsdf.inputs["Roughness"].default_value = 0.7
bsdf.inputs["Metallic"].default_value = 0.0
bpy.data.objects.remove(vys)

# ── тіло під річчю ───────────────────────────────────────────────────────
NV = np.array([v.co[:] for v in nyz.data.vertices])
if Z["kanal"] is not None:
    bvh_n = BVHTree.FromPolygons([Vector(p) for p in NV], [tuple(p.vertices) for p in nyz.data.polygons])
    pid = np.zeros(len(BV), bool)
    kandy = np.nonzero((BV[:, 0] > NV[:, 0].min()) & (BV[:, 0] < NV[:, 0].max()) & (BV[:, 1] > NV[:, 1].min())
                       & (BV[:, 1] < NV[:, 1].max()) & (BV[:, 2] > NV[:, 2].min()) & (BV[:, 2] < NV[:, 2].max()))[0]
    for i in kandy:
        holosy = 0
        for d in (Vector((1, 0.013, 0.007)), Vector((-0.011, 1, 0.017)), Vector((0.009, -0.015, 1))):
            k_, p_ = 0, Vector(BV[i])
            while k_ < 40:
                h = bvh_n.ray_cast(p_, d)
                if h[0] is None:
                    break
                k_ += 1
                p_ = h[0] + d * 1e-5
            holosy += k_ % 2
        pid[i] = holosy >= 2
    # поруч із річчю зсередини (стінка 8 мм) — теж під нею
    for i in kandy:
        if not pid[i]:
            loc, nrm, _f, d = bvh_n.find_nearest(Vector(BV[i]))
            if d < 0.004:
                pid[i] = True
    sus_t = [[] for _ in range(len(BV))]
    for e in tm.edges:
        a_, b_ = e.vertices
        sus_t[a_].append(b_)
        sus_t[b_].append(a_)
    zavzhdy = np.array([k.startswith(Z["zavzhdy"]) for k in t_kistka]) if Z["zavzhdy"] else np.zeros(len(BV), bool)
    for zn in ((1, -1) if Z.get("pid_kistky") else ()):
        bk = "_l" if zn > 0 else "_r"
        nb = NV[NV[:, 0] * zn > 0]
        if len(nb):
            zavzhdy |= (np.array([k.startswith(Z["pid_kistky"]) and k.endswith(bk) for k in t_kistka])
                        & (BV[:, 2] > nb[:, 2].min() + Z["vidstup"][0]) & (BV[:, 2] < nb[:, 2].max() - Z["vidstup"][1]))
    pid |= zavzhdy
    zviz = pid.copy()
    for _ in range(2):                         # відступ від краю речі: два кільця вершин
        z2 = zviz.copy()
        for i in np.nonzero(zviz)[0]:
            if not zavzhdy[i] and not all(zviz[j] for j in sus_t[i]):
                z2[i] = False
        zviz = z2
    at = tilo.data.color_attributes.get("під_одяг") or tilo.data.color_attributes.new("під_одяг", "FLOAT_COLOR", "POINT")
    kol_v = np.zeros(len(BV) * 4, np.float32)
    at.data.foreach_get("color", kol_v)
    kol_v = kol_v.reshape(-1, 4)
    if not arg("--доповнити-канали", int, 1) or kol_v[:, :3].min() > 0.99:
        kol_v[:] = 0.0                           # новий атрибут Blender заливає білим
    kol_v[:, Z["kanal"]] = zviz
    at.data.foreach_set("color", kol_v.ravel())
    log("тіло під річчю: %d вершин (канал %d)" % (int(zviz.sum()), Z["kanal"]))


# ── ваги: лише кістки зони свого боку; у позу спокою ─────────────────────
zk = {b: hrupy[b] for b in akt if hrupy[b].startswith(Z["kistky"])}
Wo = np.zeros((len(NV), W.shape[1]), np.float32)
for i, p in enumerate(NV):
    bik = "_l" if p[0] > 0 else "_r"
    for _co, j, d_ in kd.find_n(p, 8):
        for b, nm_ in zk.items():
            if nm_.endswith(bik) or not nm_.endswith(("_l", "_r")):
                Wo[i, b] += W[j, b] / (d_ + 0.005)
    if Wo[i].sum() < 1e-6:                  # поруч лише чужі кістки — найближча своя
        b = min((b for b, nm_ in zk.items() if nm_.endswith(bik) or not nm_.endswith(("_l", "_r"))),
                key=lambda b: np.abs(BV[W[:, b] > 0.5] - p).sum(1).min() if (W[:, b] > 0.5).any() else 9.0)
        Wo[i, b] = 1.0
Wo /= Wo.sum(1, keepdims=True)
# згладити по сусідах речі (стик халяви й стопи)
sus_n = [[] for _ in range(len(NV))]
for e in nyz.data.edges:
    a_, b_ = e.vertices
    sus_n[a_].append(b_)
    sus_n[b_].append(a_)
for _ in range(4):
    Wo = np.array([(Wo[i] + Wo[sus_n[i]].mean(0)) / 2 if sus_n[i] else Wo[i] for i in range(len(NV))])
if Z.get("tverdist"):                       # тверда пластина не гнеться: ваги — до середнього по боку
    holovna = np.array([hrupy[i] for i in Wo.argmax(1)])
    for bik in ("_l", "_r"):
        mt_ = np.array([k.startswith(Z["tverdi"]) and k.endswith(bik) for k in holovna])
        if mt_.any():
            Wo[mt_] = Wo[mt_] * (1 - Z["tverdist"]) + Wo[mt_].mean(0) * Z["tverdist"]
Wa = Wo[:, akt].astype(np.float64)
Wa /= np.maximum(Wa.sum(1, keepdims=True), 1e-9)
Mv = np.einsum("ib,bjk->ijk", Wa, M)
Vr = np.einsum("ijk,ik->ij", np.linalg.inv(Mv[:, :, :3]), NV - Mv[:, :, 3])
nyz.data.vertices.foreach_set("co", Vr.ravel())
nyz.data.update()
for gi, gn in enumerate(hrupy):
    if gn not in kistky or Wo[:, gi].max() < 0.01:
        continue
    g = nyz.vertex_groups.new(name=gn)
    for i in np.nonzero(Wo[:, gi] > 0.01)[0]:
        g.add([int(i)], float(Wo[i, gi]), "REPLACE")
nazva = "Одяг-%s-%s-%s" % (Z["komirka"], TYP, ZONA)
for stara in [nazva] + ["Одяг-%s-%s-%s" % (Z["komirka"], TYP, x) for x in Z.get("zaminiuie", ())]:
    ob_ = bpy.data.objects.get(stara)
    if ob_ is not None:
        me_ = ob_.data
        bpy.data.objects.remove(ob_)
        if me_.users == 0:
            bpy.data.meshes.remove(me_)
nyz.name = nazva
nyz.data.name = nazva
nyz.parent = rig
am = nyz.modifiers.new("Armature", "ARMATURE")
am.object = rig
bpy.data.objects.remove(ss)
bpy.ops.wm.save_as_mainfile(filepath=VYHID)
log("%s: %d трикутників → %s" % (nazva, sum(len(p.vertices) - 2 for p in nyz.data.polygons), VYHID))

OHLIAD = arg("--огляд", str, "")
if OHLIAD:
    for o in bpy.data.objects:
        if o.type == "MESH" and o is not nyz and o is not tilo:
            o.hide_render = True
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = sc.render.resolution_y = 900
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.3, 0.3, 0.32, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.8
    cam = bpy.data.objects.new("кам", bpy.data.cameras.new("кам"))
    sc.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    lo, hi = Vr.min(0), Vr.max(0)
    cam.data.ortho_scale = max(hi[0] - lo[0], hi[2] - lo[2]) * 1.25
    sc.camera = cam
    for i, (e, k) in enumerate([(3.0, (55, 0, 35)), (1.5, (60, 0, -120))]):
        L = bpy.data.objects.new("св%d" % i, bpy.data.lights.new("св%d" % i, "SUN"))
        L.data.energy = e
        L.rotation_euler = [math.radians(a) for a in k]
        sc.collection.objects.link(L)
    c = (lo + hi) / 2
    kadry = []
    for i, (kut, lyshe) in enumerate([(0, False), (35, True), (110, True), (180, True)]):
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
