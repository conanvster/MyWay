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
import os
import sys

import bpy
import math

import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

A = sys.argv[sys.argv.index("--") + 1:]
GLB, VYKHID = A[0], A[1]
GRANEI = int(A[A.index("--граней") + 1]) if "--граней" in A else 150000


def log(*a):
    print("[риг сітки]", *a, flush=True)


h = bpy.data.objects["Human"]
rig = bpy.data.objects["Human.rig"]
# скелет — під статуру основи: у пілота орка він лишився від типової людини
# (кисть за 24 см, пальці за 21 см від своїх кісток) — у русі пальці
# розліталися «гілками» (09.11)
if "--без-refit" not in A:
    from bl_ext.blender_org.mpfb.services.humanservice import HumanService
    HumanService.refit(h)
    log("скелет підігнано під тіло (MPFB refit)")
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
# генератор віддає металевість 1 на все тіло (синій канал карти — 255): у грі
# шкіра — темний метал, а пришиті кисті поруч — сірі (09.11). Шкіра й шкіра
# пояса — не метал.
for mt in gm.materials:
    for n in (mt.node_tree.nodes if mt and mt.node_tree else []):
        if n.type == "BSDF_PRINCIPLED":
            for l in list(n.inputs["Metallic"].links):
                mt.node_tree.links.remove(l)
            n.inputs["Metallic"].default_value = 0.0
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


def holova(kist):
    bpy.context.view_layer.update()
    return np.array((rig.matrix_world @ rig.pose.bones[kist].head)[:])


def khvist(kist):
    bpy.context.view_layer.update()
    return np.array((rig.matrix_world @ rig.pose.bones[kist].tail)[:])


def vis_ruky(bik):
    """Вісь руки сітки: центри перерізів від плеча до кінчиків."""
    sh = holova("upperarm_" + ("l" if bik > 0 else "r"))
    m = GV[:, 0] * bik > abs(sh[0]) + 0.02
    Q = GV[m]
    tip = kraini(GV, bik, True)
    ax = (tip - sh) / np.linalg.norm(tip - sh)
    t = (Q - sh) @ ax
    # лише рука: ближче 12 см до прямої плече → кінчики (стегно й пояс
    # теж лежать за плечем по X і тягли вісь до тіла)
    rad = np.linalg.norm((Q - sh) - np.outer(t, ax), axis=1)
    Q, t = Q[rad < 0.12], t[rad < 0.12]
    L = np.linalg.norm(tip - sh)
    tochky = [sh]
    for a in np.linspace(0.06, 0.94, 23):
        s_ = np.abs(t - a * L) < 0.025 * L
        if s_.sum() > 20:
            tochky.append(Q[s_].mean(0))
    tochky.append(tip)
    P = np.array(tochky)
    dl = np.r_[0, np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))]
    vis = lambda f: np.array([np.interp(f * dl[-1], dl, P[:, k]) for k in range(3)])
    # зап'ястя — найвужчий переріз між 55 і 92 % довжини (у орка кисть велика,
    # пропорції людини ставили зап'ястя в долоню, 09.11)
    prof = []
    for f in np.linspace(0.55, 0.92, 38):
        c = vis(f)
        s_ = np.abs((Q - c) @ ax) < 0.012
        if s_.sum() > 15:
            prof.append((np.linalg.norm(Q[s_] - c, axis=1).mean(), f))
    vis.zap = min(prof)[1] if prof else None
    return vis


for bik, sfx in ((1, "l"), (-1, "r")):
    if "--рука-по-суглобах" not in A:
        naviaty("upperarm_" + sfx, kraini(B, bik, True), kraini(GV, bik, True))
        naviaty("thigh_" + sfx, kraini(B, bik, False), kraini(GV, bik, False))
        continue
    # (`--рука-по-суглобах`, спроба 09.11: руки в T-позі прямі, але пальці
    # сітки після цього визначаються хибно — суглоби ставить замовник вручну,
    # `skelet_vruchnu.py`)
    # рука — по суглобах: плече на лікоть, передпліччя на зап'ястя, кисть на
    # кінчики (лише плече на кінчик лишало передпліччя під кутом — у T-позі
    # й ударі лікті ламалися, слово замовника 09.11)
    vis = vis_ruky(bik)
    Lu = np.linalg.norm(khvist("upperarm_" + sfx) - holova("upperarm_" + sfx))
    Ll = np.linalg.norm(holova("hand_" + sfx) - holova("lowerarm_" + sfx))
    Lh = np.linalg.norm(khvist("middle_03_" + sfx) - holova("hand_" + sfx))
    Lt = Lu + Ll + Lh
    # (найвужчий переріз по всій руці хибив: 55 % зліва, 88 % справа — тож
    # пропорції; зап'ястя уточнює крок пальців локально)
    fz = (Lu + Ll) / Lt
    naviaty("upperarm_" + sfx, holova("lowerarm_" + sfx), vis(fz * Lu / (Lu + Ll)))
    naviaty("lowerarm_" + sfx, holova("hand_" + sfx), vis(fz))
    naviaty("hand_" + sfx, khvist("middle_03_" + sfx), vis(1.0))
    log("рука %s: зап'ястя на %.0f %% довжини, лікоть %s, зап'ястя %s, кінчик %s" % (sfx, 100 * fz,
        vis(fz * Lu / (Lu + Ll)).round(3), vis(fz).round(3), vis(1.0).round(3)))
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


# ── 4а. пальці сітки (`--пальці-сітки`, 09.11.2026) ───────────────────
# Слово замовника: «оригінальна рука досить нормальна, проблема в
# підключенні кісток до руки». Перевірка (`vagy_kysti.py`): кістки пальців
# основи стирчали за кінчиками в порожнечу (пальці сітки звисають), майже
# вся кисть мала ваги великого пальця й долоні. Тут кістки кисті й пальців
# стають у пальці сітки, а ваги кисті — за належністю вершини до пальця.
PALTSI = ("thumb", "index", "middle", "ring", "pinky")


def palci_sitky():
    import heapq
    from mathutils.kdtree import KDTree
    CO = np.array([v.co[:] for v in gm.vertices])
    # шви розгортки розрізають вершини — зшити за збігом координат
    # (округлення координат зшивало не все — палець розпадався на дві смуги
    # і ставав двома «пальцями», ланцюжки кісток здвоювались, 09.11)
    kdz = KDTree(len(CO))
    for i, c in enumerate(CO):
        kdz.insert(c, i)
    kdz.balance()
    bat_ = np.arange(len(CO))

    def kor_(x):
        while bat_[x] != x:
            bat_[x] = bat_[bat_[x]]
            x = bat_[x]
        return x

    for i, c in enumerate(CO):
        for _, j, _ in kdz.find_range(c, 0.0006):
            a, b = kor_(i), kor_(j)
            if a != b:
                bat_[max(a, b)] = min(a, b)
    korin = np.array([kor_(i) for i in range(len(CO))])
    _, rid = np.unique(korin, return_inverse=True)
    U = np.zeros((rid.max() + 1, 3))
    U[rid] = CO
    sus = [set() for _ in range(len(U))]
    for e in gm.edges:
        a, b = rid[e.vertices[0]], rid[e.vertices[1]]
        if a != b:
            sus[a].add(b)
            sus[b].add(a)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    eb = rig.data.edit_bones
    mw = rig.matrix_world
    vdalo = set()
    for bik in ("l", "r"):
        sx = 1 if bik == "l" else -1
        wr = np.array((mw @ eb["hand_" + bik].head)[:])
        lo = np.array((mw @ eb["lowerarm_" + bik].head)[:])
        os_ = (wr - lo) / np.linalg.norm(wr - lo)
        # зап'ястя сітки — найвужчий переріз у межах ±6 см від зап'ястя скелета
        blyz = (U[:, 0] * sx > 0) & (np.linalg.norm(U - wr, axis=1) < 0.2)
        prof = []
        # не глибше 2 см у кисть: у розчепірених кистях найвужчий переріз —
        # уже пальці (основи орків 09.11 — знаходилось лише 2 пальці)
        for zs in np.linspace(-0.04, 0.02, 25):
            c0 = wr + os_ * zs
            s_ = blyz & (np.abs((U - c0) @ os_) < 0.006)
            if s_.sum() > 15:
                q = U[s_]
                cc = q.mean(0)
                prof.append((np.linalg.norm((q - cc) - np.outer((q - cc) @ os_, os_), axis=1).mean(), zs))
        if prof:
            wr = wr + os_ * min(prof)[1]
            log("пальці %s: зап'ястя сітки зсунуто на %.1f см від скелета" % (bik, 100 * min(prof)[1]))
        pr = (U - wr) @ os_
        H = (pr > -0.02) & (U[:, 0] * sx > 0) & (np.linalg.norm(U - wr, axis=1) < 0.35)
        Hi = np.nonzero(H)[0]
        # зап'ястя сітки — кільце поблизу площини кістки кисті
        kil = Hi[np.abs(pr[Hi]) < 0.008]
        log("пальці %s: зап'ястя скелета %s, вершин за ним %d, у кільці %d, найближча вершина сітки %.3f м"
            % (bik, wr.round(3), len(Hi), len(kil), np.linalg.norm(U - wr, axis=1).min()))
        if len(kil) == 0:
            continue
        wr_g = U[kil].mean(0)
        # відстань по поверхні від кільця (Дейкстра в межах кисті)
        d = np.full(len(U), np.inf)
        hp = []
        for i in kil:
            d[i] = 0.0
            hp.append((0.0, i))
        heapq.heapify(hp)
        while hp:
            dd, i = heapq.heappop(hp)
            if dd > d[i]:
                continue
            for j in sus[i]:
                if not H[j]:
                    continue
                nd = dd + np.linalg.norm(U[i] - U[j])
                if nd < d[j]:
                    d[j] = nd
                    heapq.heappush(hp, (nd, j))
        Hi = Hi[np.isfinite(d[Hi])]
        # дерево злиттів зі стійкістю: від найдальших вершин униз; горбик,
        # нижчий за ПОРІГ над місцем злиття, — шум, вливається в сусіда;
        # вищий — палець, що тут закінчується (злився з долонею)
        POROG = 0.012
        bat, pik, zakryto = {}, {}, {}
        pershe = {}
        mitka0 = np.full(len(U), -1)

        def koren(x):
            while bat[x] != x:
                bat[x] = bat[bat[x]]
                x = bat[x]
            return x

        def zhyvyi(x):
            x = koren(x)
            while x in zakryto:
                x = koren(zakryto[x][1])
            return x

        nova = 0
        for i in Hi[np.argsort(-d[Hi])]:
            R = {zhyvyi(mitka0[j]) for j in sus[i] if mitka0[j] >= 0}
            if not R:
                bat[nova], pik[nova] = nova, (d[i], i)
                mitka0[i] = nova
                nova += 1
                continue
            R = sorted(R, key=lambda r: -pik[r][0])
            main = R[0]
            for r in R[1:]:
                if pik[r][0] - d[i] < POROG:
                    bat[r] = main
                else:
                    zakryto[r] = (d[i], main)
                    pershe.setdefault(main, d[i])
            mitka0[i] = main
        kand = []
        for r in set(koren(x) for x in bat):
            kin = zakryto[r][0] if r in zakryto else pershe.get(r)
            if kin is None:
                continue
            dovzh = pik[r][0] - kin
            if dovzh > 0.025:
                kand.append((dovzh, r, pik[r][1], kin))
        kand.sort(reverse=True)
        log("пальці %s: кисть %d, кільце %d, вершин %d, відростків %s, макс відстань %.3f"
            % (bik, len(Hi), len(kil), nova, [round(k[0], 3) for k in kand[:8]], d[Hi].max()))
        # лише вздовж кисті: кінчик пальця далеко від зап'ястя вздовж осі
        # кисті; клапті наруча звисають убік біля зап'ястя (09.11)
        dal = Hi[d[Hi] > 0.5 * d[Hi].max()]
        ax_k = U[dal].mean(0) - wr_g
        ax_k /= np.linalg.norm(ax_k)
        dov_k = ((U[Hi] - wr_g) @ ax_k).max()
        kand = [k_ for k_ in kand if (U[k_[2]] - wr_g) @ ax_k > 0.55 * dov_k]
        # без дублів: кінчик і основа — далі 2 см від уже вибраних
        nalezh = np.array([koren(mitka0[i]) if mitka0[i] >= 0 else -1 for i in range(len(U))])
        vybr = []
        for k_ in kand:
            dovzh, r_, tip, d0 = k_
            vv_ = Hi[(nalezh[Hi] == r_) & (d[Hi] >= d0)]
            osn = U[vv_[d[vv_] < d0 + 0.01]].mean(0) if (d[vv_] < d0 + 0.01).any() else U[vv_].mean(0)
            blyzh = [(np.linalg.norm(U[tip] - U[t2]), np.linalg.norm(osn - o2)) for _, _, t2, _, o2 in vybr]
            # кінчики різних пальців орка — далі 4 см; ближче 2,5 см — той самий
            # палець (подвійний шар сітки генератора)
            # (лише кінчик < 2,5 см відсіював справжні сусідні пальці в
            # розчепірених пазурах — кінчики сходяться на 3 см; основи орків 09.11)
            dubl = any(a < 0.015 or (a < 0.025 and b < 0.015) for a, b in blyzh)
            log("  кандидат %.3f кінчик %s основа %s до вибраних %s%s" % (
                dovzh, U[tip].round(3), osn.round(3), [(round(a, 3), round(b, 3)) for a, b in blyzh],
                " — дубль" if dubl else ""))
            if not dubl:
                vybr.append((dovzh, r_, tip, d0, osn))
            if len(vybr) == 5:
                break
        kand = [k[:4] for k in vybr]
        if len(kand) < 4:
            log("пальці %s: знайдено лише %d — без змін" % (bik, len(kand)))
            continue
        palci = []
        for dovzh, m_, tip, d0 in kand:
            vv = Hi[(nalezh[Hi] == m_) & (d[Hi] >= d0)]
            # вісь пальця: центри рівнів відстані
            rivni = np.linspace(d0, d[tip], 9)
            tochky = []
            for a, b in zip(rivni[:-1], rivni[1:]):
                s_ = vv[(d[vv] >= a) & (d[vv] < b)]
                if len(s_):
                    tochky.append(U[s_].mean(0))
            tochky.append(U[tip] - (U[tip] - tochky[-1]) * 0.15)
            palci.append({"m": m_, "osi": np.array(tochky), "d0": d0, "dt": d[tip], "vv": vv})
        # великий — найближчий основою до великого пальця скелета; решта —
        # за віддаленням основи від великого
        # великий — той, що відгалужується найближче до зап'ястя (найменша
        # відстань злиття по поверхні); кістка великого скелета як орієнтир
        # хибила — скелет стояв під рівну кисть MPFB (09.11)
        # великий — основа найближча до центру зап'ястя в просторі (у скелеті
        # MPFB так само); і злиття по поверхні, і кістка великого скелета хибили
        palci.sort(key=lambda p: np.linalg.norm(p["osi"][0] - wr_g))
        log("пальці %s: основи від зап'ястя %s см" % (bik, [round(100 * np.linalg.norm(p["osi"][0] - wr_g), 1) for p in palci]))
        velykyi = palci[0]
        inshi = sorted(palci[1:], key=lambda p: np.linalg.norm(p["osi"][0] - velykyi["osi"][0]))
        if len(inshi) == 3:
            # генератор зліпив два пальці в один: найширший — два ланцюжки
            # поруч (зсув поперек на третину ширини), вершини — за боком
            for p in inshi:
                o = p["osi"]
                p["shyr"] = np.mean([np.min(np.linalg.norm(o - U[i], axis=1)) for i in p["vv"]])
            k = int(np.argmax([p["shyr"] for p in inshi]))
            p = inshi[k]
            sus_p = inshi[k + 1] if k + 1 < 3 else inshi[k - 1]
            ax = p["osi"][-1] - p["osi"][0]
            ax /= np.linalg.norm(ax)
            lat = sus_p["osi"][0] - p["osi"][0]
            lat -= ax * (lat @ ax)
            lat /= np.linalg.norm(lat)
            if k + 1 >= 3:
                lat = -lat                      # «назовні» — від сусіда
            zs = 0.6 * p["shyr"]
            bik_v = (U[p["vv"]] - p["osi"][0]) @ lat
            blyzhche = {"osi": p["osi"] - lat * zs, "d0": p["d0"], "dt": p["dt"], "vv": p["vv"][bik_v <= 0]}
            dali = {"osi": p["osi"] + lat * zs, "d0": p["d0"], "dt": p["dt"], "vv": p["vv"][bik_v > 0]}
            # порядок від великого: ближчий до сусіда-ліворуч іде першим
            para = sorted([blyzhche, dali], key=lambda q: np.linalg.norm(q["osi"][0] - velykyi["osi"][0]))
            inshi = inshi[:k] + para + inshi[k + 1:]
            log("пальці %s: 4 пальці — %d-й (від великого) злиплий, ширина %.1f см → два ланцюжки"
                % (bik, k + 1, 200 * p["shyr"]))
        nazvy = dict(zip(PALTSI, [velykyi] + inshi))
        # кістки — уздовж осі пальця (довжина дуги), закрутка — разом із напрямом
        for nz, p in nazvy.items():
            osi = p["osi"]
            dl = np.r_[0, np.cumsum(np.linalg.norm(np.diff(osi, axis=0), axis=1))]
            frak = (0, 0.4, 0.7, 1.0) if nz == "thumb" else (0, 0.45, 0.75, 1.0)
            tch = [np.array([np.interp(f * dl[-1], dl, osi[:, k]) for k in range(3)]) for f in frak]
            for j in range(3):
                b = eb["%s_%02d_%s" % (nz, j + 1, bik)]
                st = (b.tail - b.head).normalized()
                z_old = b.z_axis.copy()
                b.head = mw.inverted() @ Vector(tch[j])
                b.tail = mw.inverted() @ Vector(tch[j + 1])
                q = st.rotation_difference((b.tail - b.head).normalized())
                b.align_roll(q @ z_old)
            p["kistky"] = [(tch[j], tch[j + 1]) for j in range(3)]
        hb_ = eb["hand_" + bik]
        st = (hb_.tail - hb_.head).normalized()
        z_old = hb_.z_axis.copy()
        hb_.head = mw.inverted() @ Vector(wr_g)
        hb_.tail = mw.inverted() @ Vector(nazvy["middle"]["osi"][0])
        hb_.align_roll(st.rotation_difference((hb_.tail - hb_.head).normalized()) @ z_old)
        # ваги кисті
        W = {}
        for nz, p in nazvy.items():
            for i in p["vv"]:
                ds = []
                for j, (h_, t_) in enumerate(p["kistky"]):
                    ab = t_ - h_
                    tt = np.clip((U[i] - h_) @ ab / (ab @ ab), 0, 1)
                    ds.append(np.linalg.norm(U[i] - (h_ + tt * ab)))
                ds = np.array(ds)
                w = 1.0 / (ds + 0.003) ** 3
                w /= w.sum()
                W[i] = {"%s_%02d_%s" % (nz, j + 1, bik): float(x) for j, x in enumerate(w) if x > 0.02}
        for i in Hi:
            if i in W:
                continue
            # долоня й зап'ястя: кисть, біля зап'ястя — з передпліччям,
            # біля основ пальців — з першими кістками пальців
            w = {"hand_" + bik: 1.0}
            if d[i] < 0.015:
                k = d[i] / 0.015
                w = {"hand_" + bik: 0.5 + 0.5 * k, "lowerarm_" + bik: 0.5 - 0.5 * k}
            for nz, p in nazvy.items():
                ds = np.linalg.norm(U[i] - p["osi"][0])
                if ds < 0.02:
                    k = 0.5 * (1 - ds / 0.02)
                    w = {kk: x * (1 - k) for kk, x in w.items()}
                    w["%s_01_%s" % (nz, bik)] = w.get("%s_01_%s" % (nz, bik), 0) + k
            W[i] = w
        # згладжування ваг між пальцями й долонею (слово замовника 09.11:
        # «згладь ваги між пальцями на обох руках»): 4 проходи — половина
        # своєї ваги, половина — середнє сусідів по поверхні
        for _ in range(4):
            W2 = {}
            for i, w in W.items():
                sus_w = [W[j] for j in sus[i] if j in W]
                if not sus_w:
                    W2[i] = w
                    continue
                acc = {k: 0.5 * x for k, x in w.items()}
                for sw in sus_w:
                    for k, x in sw.items():
                        acc[k] = acc.get(k, 0.0) + 0.5 * x / len(sus_w)
                W2[i] = acc
            W = W2
        for i, w in W.items():
            top = sorted(w.items(), key=lambda kv: -kv[1])[:4]
            sm_ = sum(x for _, x in top) or 1.0
            W[i] = {k: x / sm_ for k, x in top if x / sm_ > 0.01}
        # на вершини сітки (до зшивання)
        zmineno = 0
        for v in range(len(CO)):
            r_ = rid[v]
            if r_ in W:
                vagy[v] = W[r_]
                zmineno += 1
        vdalo.add(bik)
        log("пальці %s: великий + 4, довжини %s см, вершин кисті %d"
            % (bik, [round(100 * nazvy[n]["dt"] - 100 * nazvy[n]["d0"], 1) for n in PALTSI], zmineno))
    # одна кисть не вдалась — її пальці дзеркально з другої (тіла майже
    # симетричні; центрування `skelet_tiunynh.py` потім садить їх у сітку), 09.11
    if len(vdalo) == 1:
        dob = vdalo.pop()
        pog = "r" if dob == "l" else "l"
        dz = Matrix.Scale(-1, 4, (1, 0, 0))
        for nz in PALTSI + ("hand",):
            for j in ((1, 2, 3) if nz != "hand" else (0,)):
                n1 = "%s_%02d_%s" % (nz, j, dob) if nz != "hand" else "hand_" + dob
                n2 = n1[:-1] + pog
                b1, b2 = eb[n1], eb[n2]
                b2.head = mw.inverted() @ (dz @ (mw @ b1.head))
                b2.tail = mw.inverted() @ (dz @ (mw @ b1.tail))
                b2.roll = -b1.roll
        log("пальці %s: не знайдено — дзеркально з %s" % (pog, dob))
    bpy.ops.object.mode_set(mode="OBJECT")


if "--пальці-сітки" in A:
    palci_sitky()


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


# ── 5. кисті основи (`--кисті-основи <шкіра MPFB.png>`, 09.11.2026) ──
# Генератор дає замість кисті злиту грудку з розмазаною текстурою, і ваги
# пальців її рвуть у русі. Тут кисть сітки (вага кисті й пальців > 0,5) —
# геть, а на її місце — кисть основи MPFB (справжні пальці, свої ваги й
# розгортка), підігнана за зап'ястям: центр і товщина кільця, тон шкіри.
def kysti_osnovy(png):
    import bmesh
    ruka = lambda k: k.startswith(("hand_", "thumb_", "index_", "middle_", "ring_", "pinky_"))
    vg_gen = {g.index: g.name for g in gen.vertex_groups}
    hv = np.array([sum(g.weight for g in v.groups if ruka(vg_gen[g.group])) for v in gm.vertices])
    side_g = np.array([v.co.x for v in gm.vertices])
    co_g = np.array([v.co[:] for v in gm.vertices])
    hb = np.array([sum(g.weight for g in v.groups if ruka(imena[g.group])) for v in me.vertices])
    co_b = REST.copy()
    # кільця зап'ястя: напівшлях між передпліччям і кистю
    # кільця — кінець передпліччя біля зап'ястя: на самій кисті сітки грудка
    # (товщина виходила ×2,5)
    lg = np.array([sum(g.weight for g in v.groups if vg_gen[g.group].startswith("lowerarm_"))
                   for v in gm.vertices])
    lb = np.array([sum(g.weight for g in v.groups if imena[g.group].startswith("lowerarm_"))
                   for v in me.vertices])
    kilce = {}
    for bik in (1, -1):
        rg = (hv > 0.02) & (hv < 0.3) & (lg > 0.5) & (side_g * bik > 0)
        rb = (hb > 0.02) & (hb < 0.3) & (lb > 0.5) & (co_b[:, 0] * bik > 0) & tilo
        cg, cb = co_g[rg].mean(0), co_b[rb].mean(0)
        r_g = np.linalg.norm(co_g[rg] - cg, axis=1).mean()
        r_b = np.linalg.norm(co_b[rb] - cb, axis=1).mean()
        kilce[bik] = (cg, cb, float(np.clip(r_g / r_b, 1.0, 1.6)))
        log("кисть %s: зсув %.3f м, товщина ×%.2f" % ("ліва" if bik > 0 else "права",
                                                       np.linalg.norm(cg - cb), r_g / r_b))
    # тон: колір сітки на кільці / колір шкіри основи на кільці
    def kolir_gen_v(idx):
        uv = gm.uv_layers.active.data
        img = None
        for mt in gm.materials:
            for n in mt.node_tree.nodes:
                if n.type == "BSDF_PRINCIPLED" and n.inputs["Base Color"].links:
                    img = n.inputs["Base Color"].links[0].from_node.image
        w_, h_ = img.size
        px = np.array(img.pixels[:], np.float32).reshape(h_, w_, img.channels)[..., :3]
        vy = set(idx)
        cs = [px[int(uv[l].uv[1] % 1 * (h_ - 1)), int(uv[l].uv[0] % 1 * (w_ - 1))]
              for p in gm.polygons for l, vi in zip(p.loop_indices, p.vertices) if vi in vy]
        return np.median(np.array(cs), 0)
    sk = bpy.data.images.load(png)
    w_, h_ = sk.size
    spx = np.array(sk.pixels[:], np.float32).reshape(h_, w_, sk.channels)[..., :3]
    uvb = me.uv_layers.active.data
    rb_all = set(np.nonzero((lb > 0.7) & (hb < 0.05) & tilo)[0])
    cb_ = np.median(np.array([spx[int(uvb[l].uv[1] % 1 * (h_ - 1)), int(uvb[l].uv[0] % 1 * (w_ - 1))]
                              for p in me.polygons for l, vi in zip(p.loop_indices, p.vertices)
                              if vi in rb_all]), 0)
    cg_ = kolir_gen_v(np.nonzero((lg > 0.7) & (hv < 0.05))[0])
    gain = cg_ / np.maximum(cb_, 1e-3)
    log("кисті: тон ×", np.round(gain, 2), "сітка", np.round(cg_ * 255), "основа", np.round(cb_ * 255))
    nova = bpy.data.images.new("кисті-шкіра", w_, h_, alpha=False)
    nova.pixels.foreach_set(np.concatenate([np.clip(spx * gain, 0, 1),
                                            np.ones((h_, w_, 1), np.float32)], 2).ravel())
    nova.pack()
    # кисть основи — окрема сітка
    kyst = h.copy()
    kyst.data = me.copy()
    kyst.name = kyst.data.name = "Кисті"
    bpy.context.collection.objects.link(kyst)
    for md in list(kyst.modifiers):
        kyst.modifiers.remove(md)
    bm = bmesh.new()
    bm.from_mesh(kyst.data)
    bm.verts.ensure_lookup_table()
    geth = [bm.verts[i] for i in range(len(bm.verts)) if not (tilo[i] and (hb[i] > 0.02 or (lb[i] > 0.5 and np.linalg.norm(co_b[i] - kilce[1 if co_b[i, 0] > 0 else -1][1]) < 0.07)))]
    bmesh.ops.delete(bm, geom=geth, context="VERTS")
    for v in bm.verts:
        bik = 1 if v.co.x > 0 else -1
        cg, cb, k = kilce[bik]
        v.co = Vector(cg + (np.array(v.co[:]) - cb) * k)
    bm.to_mesh(kyst.data)
    bm.free()
    # кістки кисті й пальців — тим самим перетворенням, що й вершини: інакше
    # збільшені пальці крутились довкола кісток осторонь і розліталися (09.11)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    mwr, mwi = rig.matrix_world, rig.matrix_world.inverted()
    for eb in rig.data.edit_bones:
        if not ruka(eb.name):
            continue
        bik = 1 if (mwr @ eb.head).x > 0 else -1
        cg, cb, k = kilce[bik]
        for attr in ("head", "tail"):
            w = np.array((mwr @ getattr(eb, attr))[:])
            setattr(eb, attr, mwi @ Vector(cg + (w - cb) * k))
    bpy.ops.object.mode_set(mode="OBJECT")
    kyst.data.materials.clear()
    mt = bpy.data.materials.new("Кисті")
    mt.use_nodes = True
    t = mt.node_tree.nodes.new("ShaderNodeTexImage")
    t.image = nova
    bsdf = mt.node_tree.nodes["Principled BSDF"]
    mt.node_tree.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.7
    kyst.data.materials.append(mt)
    for p in kyst.data.polygons:
        p.use_smooth = True
    kyst.parent = rig
    kyst.matrix_parent_inverse.identity()
    kyst.modifiers.new("Armature", "ARMATURE").object = rig
    # кисть сітки — геть; кінець передпліччя основи (7 см) лишається в рукаві
    # сітки — без щілини між рукою й кистю (09.11)
    bm = bmesh.new()
    bm.from_mesh(gm)
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[bm.verts[i] for i in np.nonzero(hv > 0.4)[0]], context="VERTS")
    bm.to_mesh(gm)
    bm.free()
    log("кисті основи пришито: вершин %d" % len(kyst.data.vertices))
    if KYST_GLB:
        return kysti_z_sitky(kyst, KYST_GLB, cg_)
    return kyst


def umeyama(P, Q):
    """Подібність (s, R, t): s·R·P + t ≈ Q (найменші квадрати)."""
    mp, mq = P.mean(0), Q.mean(0)
    A, B = P - mp, Q - mq
    U, S, Vt = np.linalg.svd(B.T @ A / len(P))
    d = np.sign(np.linalg.det(U @ Vt))
    D = np.diag([1, 1, d])
    R = U @ D @ Vt
    sc = (S * np.diag(D)).sum() / (A ** 2).sum(1).mean()
    return sc, R, mq - sc * R @ mp


def kysti_z_sitky(oriientyr, glb, kolir_ruky):
    """Згенерована кисть (`tools/comfyui/ork_kysti.py` → Pixal3D, одна кисть
    на весь кадр — пальці окремі) замість кисті основи: кисть основи вже
    стоїть на зап'ясті сітки й має підігнані кістки — вона орієнтир (куди й
    якого розміру) і джерело ваг, далі — геть. Слово замовника 09.11: «усе
    окрім долонь та пальців рук мене … влаштовує, виправлення яке ти додав
    ломає консистентність» — тож кисть сітки, не MPFB."""
    from mathutils.kdtree import KDTree
    import bmesh
    pered = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=glb)
    src = [o for o in bpy.data.objects if o not in pered and o.type == "MESH"][0]
    for o in [o for o in bpy.data.objects if o not in pered and o != src]:
        bpy.data.objects.remove(o)
    src.parent = None
    bpy.context.view_layer.objects.active = src
    for o in bpy.context.selected_objects:
        o.select_set(False)
    src.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    dc = src.modifiers.new("спростити", "DECIMATE")
    dc.ratio = min(1.0, 25000 / max(1, len(src.data.polygons)))
    bpy.ops.object.modifier_apply(modifier=dc.name)
    if src.data.has_custom_normals:
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    for mt in src.data.materials:
        for n in (mt.node_tree.nodes if mt and mt.node_tree else []):
            if n.type == "BSDF_PRINCIPLED":
                for l in list(n.inputs["Metallic"].links):
                    mt.node_tree.links.remove(l)
                n.inputs["Metallic"].default_value = 0.0
    sm = src.data
    S0 = np.array([v.co[:] for v in sm.vertices])
    # кінець передпліччя кисті — край отвору (межові ребра)
    lich = {}
    for e in sm.edges:
        lich[e.key] = 0
    for p in sm.polygons:
        for k in p.edge_keys:
            lich[k] = lich.get(k, 0) + 1
    mezha = np.array(sorted({i for k, c in lich.items() if c == 1 for i in k}))
    E0 = S0[mezha].mean(0) if len(mezha) else S0[np.argmax(np.linalg.norm(S0 - S0.mean(0), axis=1))]
    T0 = S0[np.argsort(-np.linalg.norm(S0 - E0, axis=1))[:200]].mean(0)
    # зап'ястя: на кадрі кисті (`ork_kysti.py`) передпліччя входить ліворуч
    # згори, межа маски FLUX — зап'ястя; частка ширини фігури — у
    # `zapiastia.json` поруч із GLB (вісь X сітки = x кадру). Перетин сітки
    # уздовж прямої осі зап'ястя не показує — кисть загнута донизу (09.11).
    import json as _json
    fx = _json.load(open(os.path.join(os.path.dirname(glb), "zapiastia.json")))["частка_x"]
    Xw = S0[:, 0].min() + fx * (S0[:, 0].max() - S0[:, 0].min())
    sp = S0[:, 0].max() - S0[:, 0].min()
    W0 = S0[np.abs(S0[:, 0] - Xw) < 0.02 * sp].mean(0)
    ruka_src = S0[:, 0] > Xw
    T0 = S0[ruka_src][np.argsort(-np.linalg.norm(S0[ruka_src] - W0, axis=1))[:200]].mean(0)
    kyst_src = S0[:, 0] > Xw - 0.03 * sp
    log("кисть сітки: зап'ястя x=%.3f, кисть %.0f %% вершин" % (Xw, 100 * ruka_src.mean()))
    ov = oriientyr.data
    O = np.array([v.co[:] for v in ov.vertices])
    vg_o = {g.index: g.name for g in oriientyr.vertex_groups}
    hb_o = np.array([sum(g.weight for g in v.groups if vg_o[g.group].startswith(
        ("hand_", "thumb_", "index_", "middle_", "ring_", "pinky_"))) for v in ov.vertices])
    kd_o = KDTree(len(O))
    for i, c in enumerate(O):
        kd_o.insert(c, i)
    kd_o.balance()
    nove = []
    for bik in (1, -1):
        Ob = O[O[:, 0] * bik > 0]
        hb_b = hb_o[O[:, 0] * bik > 0]
        E1 = Ob[hb_b < 0.05].mean(0)                       # передпліччя орієнтира
        T1 = Ob[np.argsort(-np.linalg.norm(Ob - E1, axis=1))[:200]].mean(0)
        W1 = Ob[(hb_b > 0.3) & (hb_b < 0.7)].mean(0)        # зап'ястя орієнтира
        Oh = Ob[hb_b > 0.3]                                  # лише кисть
        kd = KDTree(len(Oh))
        for i, c in enumerate(Oh):
            kd.insert(c, i)
        kd.balance()
        # кисть з кадру — ліва (кроп правої кисті кадру спереду, віддзеркалений):
        # на ліву руку (+X) як є, на праву — дзеркало. Рамки: вісь зап'ястя →
        # кінчики і бік великого пальця (на кадрі — праворуч, +X), подібність
        # без перебору (перебір із суміщенням чіплявся за загнуті пальці, 09.11)
        dzerk = 1 if bik > 0 else -1
        M_ = np.array([dzerk, 1, 1])
        W, T = W0 * M_, T0 * M_
        a = (T - W) / np.linalg.norm(T - W)
        t = np.array([dzerk, 0.0, 0.0])
        t = t - a * (t @ a); t /= np.linalg.norm(t)
        F_s = np.c_[a, t, np.cross(a, t)]
        a1 = (T1 - W1) / np.linalg.norm(T1 - W1)
        tb = np.array((rig.matrix_world @ rig.data.bones["thumb_01_" + ("l" if bik > 0 else "r")].head_local)[:]) - W1
        t1 = tb - a1 * (tb @ a1); t1 /= np.linalg.norm(t1)
        F_t = np.c_[a1, t1, np.cross(a1, t1)]
        R2 = F_t @ F_s.T
        if dzerk < 0:
            R2 = R2 @ np.diag(M_)          # дзеркало входить у перетворення
            W = W0
        s2 = np.linalg.norm(T1 - W1) / np.linalg.norm(T0 - W0)
        t2 = W1 - s2 * R2 @ W0
        log("кисть сітки %s: масштаб %.3f, дзеркало %d" % ("ліва" if bik > 0 else "права", s2, dzerk))
        ob = src.copy()
        ob.data = sm.copy()
        bpy.context.collection.objects.link(ob)
        P = s2 * S0 @ R2.T + t2
        for v, c in zip(ob.data.vertices, P):
            v.co = Vector(c)
        if dzerk < 0:
            ob.data.flip_normals()
        # передпліччя кисті — лише 3 см за зап'ястям орієнтира (решта в рукаві)
        os_ = a1
        zap = Ob[(hb_b > 0.3) & (hb_b < 0.7)].mean(0)
        proj = (P - zap) @ os_
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bm.verts.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[bm.verts[i] for i in np.nonzero(proj < -0.03)[0]], context="VERTS")
        bm.to_mesh(ob.data)
        bm.free()
        # ваги — з найближчих вершин орієнтира
        for g in list(ob.vertex_groups):
            ob.vertex_groups.remove(g)
        grupy = {}
        for v in ob.data.vertices:
            acc = {}
            for (c, j, d) in kd_o.find_n(v.co, 4):
                w = 1.0 / (d + 1e-4)
                for g in ov.vertices[j].groups:
                    acc[vg_o[g.group]] = acc.get(vg_o[g.group], 0.0) + w * g.weight
            top = sorted(acc.items(), key=lambda kv: -kv[1])[:4]
            sm_ = sum(x for _, x in top) or 1.0
            for k, x in top:
                if k not in grupy:
                    grupy[k] = ob.vertex_groups.new(name=k)
                grupy[k].add([v.index], x / sm_, "REPLACE")
        ob.name = ob.data.name = "Кисть-" + ("ліва" if bik > 0 else "права")
        nove.append(ob)
    # тон текстури кисті — під передпліччя сітки
    for mt in sm.materials:
        for n in (mt.node_tree.nodes if mt and mt.node_tree else []):
            if n.type == "BSDF_PRINCIPLED" and n.inputs["Base Color"].links:
                img = n.inputs["Base Color"].links[0].from_node.image
                w_, h_ = img.size
                px = np.array(img.pixels[:], np.float32).reshape(h_, w_, img.channels)
                ye = px[..., :3].max(2) > 0.02
                kol = np.median(px[ye][:, :3], 0)
                gain = np.asarray(kolir_ruky) / np.maximum(kol, 1e-3)
                gain = np.clip(gain, 0.6, 1.6)
                px[..., :3] = np.clip(px[..., :3] * gain, 0, 1)
                px = zapovnyty(px, ye)
                img.pixels.foreach_set(px.ravel())
                img.pack()
                log("кисть сітки: тон ×", np.round(gain, 2))
    for ob in nove:
        for p in ob.data.polygons:
            p.use_smooth = True
        ob.parent = rig
        ob.matrix_parent_inverse.identity()
        ob.modifiers.new("Armature", "ARMATURE").object = rig
    bpy.data.objects.remove(src)
    bpy.data.objects.remove(oriientyr)
    return nove


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


KYSTI = None
KYST_GLB = A[A.index("--кисті-сітки") + 1] if "--кисті-сітки" in A else None
if "--кисті-основи" in A:
    KYSTI = kysti_osnovy(A[A.index("--кисті-основи") + 1])
for p in gm.polygons:
    p.use_smooth = True
# тіло MPFB і його сітки — геть
for o in [o for o in bpy.data.objects if o.type == "MESH" and o != gen and o not in (KYSTI if isinstance(KYSTI, list) else [KYSTI])]:
    bpy.data.objects.remove(o)
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
