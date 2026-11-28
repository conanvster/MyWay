# Гуманоїд-монстр зі сітки в Т-позі → скелет гравця (65 кісток UAL) під ЙОГО пропорції + рухи UAL1/UAL2
# з почерком виду (П-297, 28.11.2026; план `spec/монстри-3d-рух-план.md` §3–4).
#
# 1. Сітка: обличчям у −Y (як манекен), зріст = `--зріст` (бестіарій), ступні на 0.
# 2. Орієнтири сітки: висота рук (смуга найбільшої ширини у верхній половині), розмах, ширина плечей,
#    середини ніг біля ступень, глибина тулуба. Манекен (`Superhero_Male_FullBody.gltf`, Т-поза)
#    деформується кусково-лінійно під ці орієнтири — і його тіло, і кістки. Пропорції монстра
#    лишаються його (не як `avatar_build.py`, що тягне скан під манекен).
# 3. Ваги — з деформованого тіла манекена на найближчу грань сітки (Data Transfer). Хвіст (якщо є в
#    описі) — ланцюжок кісток уздовж вершин позаду таза, ваги — за найближчою кісткою ланцюжка.
# 4. Рухи — світовий поворот кожної кістки = поворот кістки манекена в русі × поправка спокою
#    (як `mpfb_avatar.perenapravyty`), таз зсувається з масштабом висоти таза; поверх — почерк:
#    сутулість, голова вперед, руки від тіла, ширина стійки, темп; хвіст гойдається сам.
# 5. GLB: кліпи Idle, Walk, Run, Attack, Attack2, Cast, Hit, Hit2, Death, Death2 (NLA-доріжки).
#
#   blender -b -P tools/blender/monstr_rig.py -- <сітка.glb> <вихід.glb> --манера <манера.json>
#       [--поворот <град>] [--кадри <тека>]
# манера.json: {"зріст": 2.2, "хвіст": true, "кліпи": {"Idle": "U1:Idle_Loop", …},
#               "почерк": {"сутулість": 12, "голова": -6, "руки": 8, "стійка": 4, "темп": 0.9}}
# Кліп «дзеркало:U1:Death01» — той самий рух, ліве ↔ праве.
import json
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector
from mathutils.kdtree import KDTree

A = sys.argv[sys.argv.index("--") + 1:]
VHID, VYHID = os.path.abspath(A[0]), os.path.abspath(A[1])


def arg(k, d):
    return type(d)(A[A.index(k) + 1]) if k in A else d


MANERA = json.load(open(arg("--манера", "")))
ZRIST = float(MANERA["зріст"])
POCHERK = MANERA.get("почерк", {})
KADRY = arg("--кадри", "")
KORIN = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MANEKEN = os.path.join(KORIN, "game/models/player/Superhero_Male_FullBody.gltf")
UAL = {"U1": os.path.join(KORIN, "game/models/player/animations/UAL1_Standard.glb"),
       "U2": os.path.join(KORIN, "game/models/player/animations/UAL2_Standard.glb")}


def log(*a):
    print("[монстр-риг]", *a, flush=True)


bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene

# ---------- 1. сітка монстра ----------
bpy.ops.import_scene.gltf(filepath=VHID)
ms = [o for o in sc.objects if o.type == "MESH"]
for o in ms:                     # світове положення — до того, як прибрати батьків (поворот Y-up)
    mw_ = o.matrix_world.copy()
    o.parent = None
    o.matrix_world = mw_
for o in list(sc.objects):
    if o.type not in ("MESH",):
        bpy.data.objects.remove(o)
bpy.ops.object.select_all(action="DESELECT")
for o in ms:
    o.select_set(True)
bpy.context.view_layer.objects.active = ms[0]
if len(ms) > 1:
    bpy.ops.object.join()
tilo = bpy.context.view_layer.objects.active
tilo.name = "Тіло"
tilo.parent = None
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
# ігрова сітка: зварити й спростити (Hunyuan дає ~650 тис. граней, кожна з власними вершинами);
# UV (проєкція кольору) лежить на кутах граней і переживає спрощення
GRANEI = arg("--граней", 40000)
import bmesh
bm = bmesh.new()
bm.from_mesh(tilo.data)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
bm.to_mesh(tilo.data)
bm.free()
if len(tilo.data.polygons) > GRANEI:
    dm = tilo.modifiers.new("спрощення", "DECIMATE")
    dm.ratio = GRANEI / len(tilo.data.polygons)
    bpy.context.view_layer.objects.active = tilo
    bpy.ops.object.modifier_apply(modifier=dm.name)
for mt in tilo.data.materials:       # матова шкіра/луска: без блиску (рендер давав білі плями)
    if mt and mt.use_nodes and "Principled BSDF" in mt.node_tree.nodes:
        bs = mt.node_tree.nodes["Principled BSDF"]
        bs.inputs["Roughness"].default_value = 0.9
        if "Specular IOR Level" in bs.inputs:
            bs.inputs["Specular IOR Level"].default_value = 0.2
for pl in tilo.data.polygons:
    pl.use_smooth = True
log("сітка: %d вершин, %d граней" % (len(tilo.data.vertices), len(tilo.data.polygons)))
if arg("--поворот", 0.0):
    tilo.data.transform(Matrix.Rotation(math.radians(arg("--поворот", 0.0)), 4, "Z"))
V = np.array([v.co[:] for v in tilo.data.vertices])
zmin, zmax = V[:, 2].min(), V[:, 2].max()
k = ZRIST / (zmax - zmin)
cx, cy = (V[:, 0].min() + V[:, 0].max()) / 2, np.median(V[:, 1])
tilo.data.transform(Matrix.Scale(k, 4) @ Matrix.Translation((-cx, -cy, -zmin)))
V = np.array([v.co[:] for v in tilo.data.vertices])
H = ZRIST


# точки поверхні для замірів: вершини + центри граней (на великих гранях спрощеної сітки самих
# вершин мало — у смугах виходили «дірки»)
_F = np.array([p.center[:] for p in tilo.data.polygons])
VP = np.concatenate([V, _F]) if len(_F) else V


def smuha(z0, z1):
    return VP[(VP[:, 2] >= z0) & (VP[:, 2] < z1)]


# висота рук — смуга найбільшої ширини у верхній половині
best = (0, 0.75 * H)
for z in np.arange(0.5 * H, 0.95 * H, 0.01 * H):
    s = smuha(z, z + 0.02 * H)
    if len(s) > 20:
        w = np.percentile(s[:, 0], 99.5) - np.percentile(s[:, 0], 0.5)
        if w > best[0]:
            best = (w, z + 0.01 * H)
SHYR, Z_RUK = best
s = smuha(Z_RUK - 0.03 * H, Z_RUK + 0.03 * H)
ROZMAH_L, ROZMAH_R = np.percentile(s[:, 0], 99.7), -np.percentile(s[:, 0], 0.3)
def sutsilna(znach, krok, vid=0.0):
    """Півширина суцільної смуги навколо `vid`: від середини назовні, поки клітинки зайняті
    (густота вершин не важить — лише чи є там тіло; окремі руки чи хвіст за проміжком не
    рахуються)."""
    if len(znach) == 0:
        return 0.0
    kl = set(np.floor((znach - vid) / krok).astype(int))
    pr = 0
    while pr in kl or (pr + 1) in kl:
        pr += 1
    lv = 0
    while -lv - 1 in kl or -lv - 2 in kl:
        lv += 1
    return (pr + lv) / 2 * krok


KROK = 0.015 * H
s = smuha(Z_RUK - 0.14 * H, Z_RUK - 0.09 * H)          # груди під плечима — без рук
PLECHI = sutsilna(s[:, 0], KROK) if len(s) else 0.2 * H
_t = s[np.abs(s[:, 0]) < PLECHI * 0.6] if len(s) else s
GLYB = (np.percentile(_t[:, 1], 92) - np.percentile(_t[:, 1], 8)) if len(_t) > 20 else 0.2 * H
s = smuha(0.03 * H, 0.10 * H)
if len(s):                                   # без хвоста, що лежить позаду ступень
    s = s[s[:, 1] < np.percentile(s[:, 1], 55)]
    s = s[np.abs(s[:, 0]) < PLECHI * 1.3]     # хвіст чи зброя збоку на землі — не нога
# ноги: дві суцільні смуги по X — середина кожної
NOGA = 0.06 * H
if len(s):
    kl = sorted(set(np.floor(s[:, 0] / KROK).astype(int)))
    smugy, poch = [], kl[0]
    for a_, b_ in zip(kl, kl[1:] + [None]):
        if b_ is None or b_ > a_ + 2:
            smugy.append((poch, a_))
            poch = b_
    smugy.sort(key=lambda q: -(q[1] - q[0]))
    if len(smugy) >= 2:
        c1, c2 = [(q[0] + q[1] + 1) / 2 * KROK for q in smugy[:2]]
        NOGA = abs(c1 - c2) / 2
    else:
        NOGA = (smugy[0][1] - smugy[0][0]) * KROK / 4
log("зріст %.2f · руки на %.2f, розмах %.2f/%.2f, плечі %.2f, глибина %.2f, ноги ±%.2f" % (
    H, Z_RUK, ROZMAH_L, ROZMAH_R, PLECHI, GLYB, NOGA))

# ---------- 2. манекен під орієнтири ----------
bpy.ops.import_scene.gltf(filepath=MANEKEN)
rig = next(o for o in sc.objects if o.type == "ARMATURE")
man = next(o for o in sc.objects if o.type == "MESH" and o.name.startswith("SuperHero"))
for o in list(sc.objects):
    if o.type == "MESH" and o not in (tilo, man):
        bpy.data.objects.remove(o)
M = np.array([(man.matrix_world @ v.co)[:] for v in man.data.vertices])
mzmax = M[:, 2].max()
b = {n: rig.matrix_world @ rig.data.bones[n].head_local for n in
     ("pelvis", "upperarm_l", "hand_l", "thigh_l", "neck_01")}
m_ruk = b["upperarm_l"].z
m_taz = b["pelvis"].z
m_plechi = b["upperarm_l"].x
m_rozmah = M[:, 0].max()
m_noga = b["thigh_l"].x
sm = M[(M[:, 2] > m_ruk - 0.14 * mzmax) & (M[:, 2] < m_ruk - 0.09 * mzmax)]
m_glyb = np.percentile(sm[:, 1], 97) - np.percentile(sm[:, 1], 3)
# висоти: ступні → таз → руки → маківка; таз — у тій самій частці між ступнями й руками
z_taz = Z_RUK * m_taz / m_ruk
KZ = [(0.0, 0.0), (m_taz, z_taz), (m_ruk, Z_RUK), (mzmax, H)]


def wz(z):
    for (a0, b0), (a1, b1) in zip(KZ, KZ[1:]):
        if z <= a1:
            return b0 + (z - a0) * (b1 - b0) / (a1 - a0)
    a0, b0 = KZ[-2]
    a1, b1 = KZ[-1]
    return b0 + (z - a0) * (b1 - b0) / (a1 - a0)


def wx(x, z):
    ax = abs(x)
    zn = 1 if x >= 0 else -1
    rozmah = ROZMAH_L if x >= 0 else ROZMAH_R
    k_tul = PLECHI / m_plechi
    k_nog = NOGA / max(m_noga, 1e-3)
    t = min(1.0, max(0.0, (z - m_taz * 0.85) / (m_taz * 0.3)))      # ноги → тулуб
    k_niz = k_nog * (1 - t) + k_tul * t
    tulub = ax * k_niz
    if ax <= m_plechi:
        return zn * tulub
    ruka = PLECHI + (ax - m_plechi) * (rozmah - PLECHI) / (m_rozmah - m_plechi)
    blend = min(1.0, (ax - m_plechi) / (0.15 * m_plechi))           # плавно від плеча
    return zn * ((m_plechi * k_niz) * (1 - blend) + ruka * blend) if blend < 1 else zn * ruka


KY = GLYB / max(m_glyb, 1e-3)


def W(p):
    return Vector((wx(p.x, p.z), p.y * KY, wz(p.z)))


for v in man.data.vertices:
    v.co = man.matrix_world.inverted() @ W(man.matrix_world @ v.co)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
mw = rig.matrix_world
iw = mw.inverted()
for eb in rig.data.edit_bones:
    h, t = mw @ eb.head, mw @ eb.tail
    roll = eb.roll
    eb.head, eb.tail = iw @ W(h), iw @ W(t)
    eb.roll = roll
bpy.ops.object.mode_set(mode="OBJECT")

# ---------- 3. ваги ----------
tilo.vertex_groups.clear()
for vg in man.vertex_groups:
    tilo.vertex_groups.new(name=vg.name)
dt = tilo.modifiers.new("ваги", "DATA_TRANSFER")
dt.object = man
dt.use_vert_data = True
dt.data_types_verts = {"VGROUP_WEIGHTS"}
dt.vert_mapping = "POLYINTERP_NEAREST"
dt.layers_vgroup_select_src = "ALL"
dt.layers_vgroup_select_dst = "NAME"
bpy.context.view_layer.objects.active = tilo
bpy.ops.object.modifier_apply(modifier=dt.name)

# тканина між ногами (поли, спідниця — Hunyuan з'єднує її з обома ногами): не за однією ногою, а
# порівну таз і обидва стегна — інакше в кроці полотнище рветься за ногою
# Поли спереду й ззаду — свої ланцюжки кісток `cloth_f_1..2`, `cloth_b_1..2` (у грі на них пружини,
# `skinned_model._body_springs`): вага кістки поли росте донизу, решта — таз і стегна.
vg = {g.name: g for g in tilo.vertex_groups}
taz_y = W(b["pelvis"]).y
mizh = {"f": [], "b": []}
for v in tilo.data.vertices:
    p = v.co
    if 0.28 * H < p.z < z_taz and abs(p.x) < NOGA * 0.55:
        mizh["f" if p.y < taz_y else "b"].append(v.index)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
POLY = {}
for bik, idx in mizh.items():
    if len(idx) < 30:
        continue
    pts = np.array([tilo.data.vertices[i].co[:] for i in idx])
    y_ = float(np.median(pts[:, 1]))
    z_vg, z_nyz = z_taz - 0.02 * H, float(pts[:, 2].min())
    zs = [z_vg, (z_vg + z_nyz) / 2, z_nyz]
    batko = rig.data.edit_bones["pelvis"]
    for j in range(2):
        eb = rig.data.edit_bones.new("cloth_%s_%d" % (bik, j + 1))
        eb.head = iw @ Vector((0, y_, zs[j]))
        eb.tail = iw @ Vector((0, y_, zs[j + 1]))
        eb.parent = batko
        eb.use_connect = j > 0
        batko = eb
    POLY[bik] = (idx, z_vg, z_nyz)
bpy.ops.object.mode_set(mode="OBJECT")
for bik, (idx, z_vg, z_nyz) in POLY.items():
    g1 = tilo.vertex_groups.new(name="cloth_%s_1" % bik)
    g2 = tilo.vertex_groups.new(name="cloth_%s_2" % bik)
    for i in idx:
        z = tilo.data.vertices[i].co.z
        t = min(1.0, max(0.0, (z_vg - z) / max(z_vg - z_nyz, 1e-6)))
        for g in tilo.vertex_groups:
            g.remove([i])
        vg["pelvis"].add([i], 0.5 * (1 - t), "REPLACE")
        vg["thigh_l"].add([i], 0.25 * (1 - t), "REPLACE")
        vg["thigh_r"].add([i], 0.25 * (1 - t), "REPLACE")
        (g1 if t < 0.5 else g2).add([i], t, "REPLACE")
log("поли: %s" % {k: len(v[0]) for k, v in POLY.items()})
KHVIST = []
if MANERA.get("хвіст"):
    taz = W(b["pelvis"])
    Vw = np.array([v.co[:] for v in tilo.data.vertices])
    # позаду тулуба (y більше за спину на рівні таза) і нижче поясу
    spyna = np.percentile(Vw[(Vw[:, 2] > z_taz - 0.1 * H) & (Vw[:, 2] < z_taz + 0.1 * H)
                             & (np.abs(Vw[:, 0]) < PLECHI * 0.6)][:, 1], 92)
    hv = np.where((Vw[:, 1] > spyna + 0.03 * H) & (Vw[:, 2] < z_taz + 0.1 * H))[0]
    if len(hv) > 30:
        d = np.linalg.norm(Vw[hv] - np.array(taz[:]), axis=1)
        poriad = hv[np.argsort(d)]
        shmatky = np.array_split(poriad, 5)
        tochky = [Vector(np.array(taz[:]) + (np.array([0, spyna - taz.y, 0]) * 0.8))]
        tochky += [Vector(Vw[s].mean(0)) for s in shmatky if len(s)]
        bpy.context.view_layer.objects.active = rig
        bpy.ops.object.mode_set(mode="EDIT")
        batko = rig.data.edit_bones["pelvis"]
        for i in range(len(tochky) - 1):
            eb = rig.data.edit_bones.new("tail_%d" % (i + 1))
            eb.head, eb.tail = iw @ tochky[i], iw @ tochky[i + 1]
            eb.parent = batko
            eb.use_connect = i > 0
            batko = eb
            KHVIST.append(eb.name)
        bpy.ops.object.mode_set(mode="OBJECT")
        # ваги хвоста: вершина позаду — повністю найближчій кістці хвоста
        segs = [(tochky[i], tochky[i + 1]) for i in range(len(tochky) - 1)]
        grupy = [tilo.vertex_groups.new(name=n) for n in KHVIST]
        for vi in hv:
            p = Vector(Vw[vi])
            dd = []
            for a_, b_ in segs:
                ab = b_ - a_
                t = max(0.0, min(1.0, (p - a_).dot(ab) / max(ab.length_squared, 1e-9)))
                dd.append((p - (a_ + ab * t)).length)
            j = int(np.argmin(dd))
            for vg in tilo.vertex_groups:
                vg.remove([int(vi)])
            grupy[j].add([int(vi)], 1.0, "REPLACE")
        log("хвіст: %d кісток, %d вершин" % (len(KHVIST), len(hv)))
    else:
        log("‼ хвоста не знайдено за тілом — без кісток хвоста")

bpy.data.objects.remove(man)

# ---------- ваги: манекен + «тепло» по власній сітці (крок «3 — точніші ваги») ----------
# Перенесені з тонкого манекена ваги в широких видів тягнули наплічники й живіт не туди; автоматичні
# ваги Blender рахуються по самій сітці (після воксельної перебудови вона суцільна). Змішуємо 50/50,
# хвіст і поли лишаються своїми.
SVOI = set(KHVIST) | {"cloth_f_1", "cloth_f_2", "cloth_b_1", "cloth_b_2"}
def teplo(voksel):
    """«Тепло» на копії сітки: чистка + (якщо voksel) груба воксельна копія. → [{кістка: вага}] на
    кожну вершину тіла або None. Різні тіла падають на різному: гнол — на чищеній, кабанолюд —
    на воксельній, тож пробуємо по черзі."""
    import bmesh as _bm
    kop = tilo.copy()
    kop.data = tilo.data.copy()
    sc.collection.objects.link(kop)
    kop.vertex_groups.clear()
    kop.modifiers.clear()
    b_ = _bm.new()
    b_.from_mesh(kop.data)
    _bm.ops.remove_doubles(b_, verts=b_.verts, dist=0.002 * H)
    _bm.ops.dissolve_degenerate(b_, edges=b_.edges, dist=0.001 * H)
    _bm.ops.delete(b_, geom=[v for v in b_.verts if not v.link_faces], context="VERTS")
    b_.to_mesh(kop.data)
    b_.free()
    if voksel:
        rm_ = kop.modifiers.new("в", "REMESH")
        rm_.mode = "VOXEL"
        rm_.voxel_size = H / voksel
        bpy.context.view_layer.objects.active = kop
        bpy.ops.object.modifier_apply(modifier=rm_.name)
    bpy.ops.object.select_all(action="DESELECT")
    kop.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    rez = None
    try:
        bpy.ops.object.parent_set(type="ARMATURE_AUTO")
        tep = {g.index: g.name for g in kop.vertex_groups}
        n_tep = sum(1 for v in kop.data.vertices if len(v.groups))
        if n_tep > 0.9 * len(kop.data.vertices) and n_tep > 0:
            po_k = [{tep[g.group]: g.weight for g in v.groups} for v in kop.data.vertices]
            kd_ = KDTree(len(kop.data.vertices))
            for v in kop.data.vertices:
                kd_.insert(v.co, v.index)
            kd_.balance()
            rez = [po_k[kd_.find(v.co)[1]] for v in tilo.data.vertices]
    except RuntimeError as e:
        log("‼ тепло:", e)
    bpy.data.objects.remove(kop)
    return rez


if "--без-тепла" not in A:
    # кістки поза тілом (root на підлозі, пальці й кінчики) валили «тепло» для всієї сітки:
    # на час розрахунку — без деформації (пальцям лишаються ваги манекена)
    PALCI = ("thumb", "index", "middle", "ring", "pinky")
    bulo = {bn.name: bn.use_deform for bn in rig.data.bones}
    for bn in rig.data.bones:
        if bn.name == "root" or "leaf" in bn.name or bn.name.split("_")[0] in PALCI \
                or bn.name in SVOI:
            bn.use_deform = False
    po_v, sposib = None, ""
    for vx in (150, 0, 90):
        po_v = teplo(vx)
        if po_v:
            sposib = "воксель 1/%d" % vx if vx else "чищена сітка"
            break
    for bn in rig.data.bones:
        bn.use_deform = bulo[bn.name]
    if po_v:
        grupy = {g.name: g for g in tilo.vertex_groups}
        for v in tilo.data.vertices:
            stari_ = {tilo.vertex_groups[g.group].name: g.weight for g in v.groups}
            if any(n in SVOI for n in stari_):
                continue                       # хвіст, поли — свої ваги
            novi_ = {n: w for n, w in po_v[v.index].items() if n not in SVOI}
            imena = set(stari_) | set(novi_)
            mix = {n: 0.5 * stari_.get(n, 0.0) + 0.5 * novi_.get(n, 0.0) for n in imena}
            sm = sum(mix.values()) or 1.0
            for n, w in mix.items():
                if n not in grupy:
                    grupy[n] = tilo.vertex_groups.new(name=n)
                if w / sm > 0.01:
                    grupy[n].add([v.index], w / sm, "REPLACE")
                else:
                    grupy[n].remove([v.index])
        log("ваги: манекен + тепло (%s)" % sposib)
    else:
        log("‼ тепло не вийшло жодним способом — лише манекен")
tilo.parent = rig

# ---------- зброя в руках (--зброя <зброя.json> з tools/comfyui/zbroia_monstra.py) ----------
ZBROIA = []
if arg("--зброя", ""):
    for pr in json.load(open(arg("--зброя", ""))):
        stari = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=pr["файл"])
        novi = [o for o in bpy.data.objects if o not in stari]
        zm = [o for o in novi if o.type == "MESH"]
        for o in zm:
            mw_ = o.matrix_world.copy()
            o.parent = None
            o.matrix_world = mw_
        for o in novi:
            if o.type != "MESH":
                bpy.data.objects.remove(o)
        bpy.ops.object.select_all(action="DESELECT")
        for o in zm:
            o.select_set(True)
        bpy.context.view_layer.objects.active = zm[0]
        if len(zm) > 1:
            bpy.ops.object.join()
        zo = bpy.context.view_layer.objects.active
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        P_ = np.array([v.co[:] for v in zo.data.vertices])
        lo_, hi_ = P_.min(0), P_.max(0)
        rozm = hi_ - lo_
        if pr["вісь"] == "вістря" and abs(pr["хват"] - 0.5) > 0.05:
            # де руків'я (28.11: «дракон-воїн б'є руків'ям меча» — Qwen малює меч вістрям донизу,
            # а хват рахується від низу): найширший переріз — гарда клинка чи голова молота/сокири.
            # Клинок: руків'я — коротший бік від гарди; решта: руків'я — довший бік від голови.
            sh = []
            for i_ in range(40):
                z0 = lo_[2] + rozm[2] * i_ / 40
                s_ = P_[(P_[:, 2] >= z0) & (P_[:, 2] < z0 + rozm[2] / 40)]
                sh.append(np.ptp(s_[:, 0]) if len(s_) > 2 else 0)
            zw = (int(np.argmax(sh)) + 0.5) / 40
            klynok = any(k in pr["ключ"] for k in ("меч", "клин", "ніж", "кинджал", "рапір", "шабл"))
            ruk_vgori = (zw > 0.5) if klynok else (zw < 0.5)
            if ruk_vgori:
                zo.data.transform(Matrix.Rotation(math.pi, 4, "Y"))
                P_ = np.array([v.co[:] for v in zo.data.vertices])
                lo_, hi_ = P_.min(0), P_.max(0)
                rozm = hi_ - lo_
            log("зброя %s: найширше на %.2f висоти → руків'я %s" % (
                pr["ключ"], zw, "вгорі (перевернуто)" if ruk_vgori else "внизу"))
        if pr["вісь"] == "вістря":
            # стоїть сторч: довжина — Z; хват — частка від низу (руків'я внизу — див. вище)
            k_ = pr["довжина"] * H / max(rozm[2], 1e-6)
            khvat = Vector(((lo_[0] + hi_[0]) / 2, (lo_[1] + hi_[1]) / 2,
                            lo_[2] + pr["хват"] * rozm[2]))
            # вістря (+Z) — уперед (−Y), як меч у кулаці з долонею донизу
            obert = Matrix.Rotation(math.radians(90), 4, "X")
        else:
            # пласке лицем до камери (−Y): розмір — більший з X/Z; хват — на задній стороні, на
            # висоті «хват» (щит — середина, бубон — нижній край обода)
            k_ = pr["довжина"] * H / max(rozm[0], rozm[2], 1e-6)
            khvat = Vector(((lo_[0] + hi_[0]) / 2, hi_[1], lo_[2] + pr["хват"] * rozm[2]))
            if pr["вісь"] == "лук":
                # лук — у кулаці вздовж великого пальця (як держак: +Z → −Y у Т-позі), хват посередині:
                # у пострілі (рука вперед, палець угору) лук стоїть сторч
                k_ = pr["довжина"] * H / max(rozm[2], 1e-6)
                khvat = Vector(((lo_[0] + hi_[0]) / 2, (lo_[1] + hi_[1]) / 2, lo_[2] + 0.5 * rozm[2]))
                obert = Matrix.Rotation(math.radians(90), 4, "X")
            elif pr["ключ"] == "щит":
                # щит на передпліччі: лице — у бік тильної сторони кисті (+Z у Т-позі, долоня
                # донизу); у блоці рука перед тілом — щит стоїть сторч і закриває тулуб (28.11:
                # «повинен захищати тіло будучи вертикально, а не горизонтально»)
                obert = Matrix.Rotation(math.radians(-90), 4, "X")
            else:
                obert = Matrix.Identity(4)
        zo.data.transform(Matrix.Translation(-khvat))
        zo.data.transform(Matrix.Scale(k_, 4))
        zo.data.transform(obert)
        kist = pr["кістка"]
        rb = rig.data.bones[kist]
        hd = rig.matrix_world @ rb.head_local
        bik = kist[-2:]
        palm = (rig.matrix_world @ rig.data.bones["middle_01" + bik].head_local
                if "middle_01" + bik in rig.data.bones else hd + (rig.matrix_world.to_3x3() @
                                                                     (rb.tail_local - rb.head_local)))
        tsil = hd + (palm - hd) * 0.6
        if pr["ключ"] == "щит":
            tsil = tsil + Vector((0, 0, 0.03 * H))       # над тильною стороною, не крізь кулак
        mw_z = Matrix.Translation(tsil)
        zo.matrix_world = mw_z
        zo.name = "Тримає-" + pr["ключ"]
        zo.parent = rig
        zo.parent_type = "BONE"
        zo.parent_bone = kist
        zo.matrix_world = mw_z
        ZBROIA.append(zo)
        log("зброя: %s → %s, %.2f м" % (pr["ключ"], kist, pr["довжина"] * H))
am = tilo.modifiers.new("скелет", "ARMATURE")
am.object = rig

# ---------- 4. рухи ----------
rig.animation_data_create()
for pb in rig.pose.bones:
    pb.rotation_mode = "QUATERNION"
dzherela = {}
for kl, shl in UAL.items():
    stari = set(bpy.data.objects)
    staridii = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=shl)
    novi = [o for o in bpy.data.objects if o not in stari]
    src = next(o for o in novi if o.type == "ARMATURE")
    for o in novi:
        if o.type == "MESH":
            bpy.data.objects.remove(o)
    src.animation_data_create()
    dii = {a.name.split("|")[-1].split(".")[0]: a for a in bpy.data.actions if a not in staridii}
    dzherela[kl] = (src, dii)
    log("%s: %d рухів" % (kl, len(dii)))


def postav_dii(src, dia, f):
    src.animation_data.action = dia
    if hasattr(src.animation_data, "action_slot") and dia.slots:
        src.animation_data.action_slot = dia.slots[0]
    sc.frame_set(f)


# поправка спокою — окремо для кожної бібліотеки (спокій скелета UAL2 ≠ UAL1): A_TPose джерела ↔
# спокій нашого (обидва в Т-позі)
for pb in rig.pose.bones:
    pb.matrix_basis.identity()
bpy.context.view_layer.update()
NAZVY = [b.name for b in rig.data.bones]          # батьки раніше дітей
CC = {}
for kl, (src, dii) in dzherela.items():
    postav_dii(src, dii["A_TPose"], int(dii["A_TPose"].frame_range[0]))
    CC[kl] = {n: (src.matrix_world @ src.pose.bones[n].matrix).to_quaternion().inverted() @
              (rig.matrix_world @ rig.pose.bones[n].matrix).to_quaternion()
              for n in NAZVY if n in src.pose.bones}
src1, dii1 = dzherela["U1"]
C = CC["U1"]
taz_t = rig.matrix_world @ rig.data.bones["pelvis"].head_local
k_taz = z_taz / m_taz

DZERK = {}
for n in NAZVY:
    for a_, b_ in (("_l", "_r"), ("_r", "_l")):
        if n.endswith(a_) and n[:-2] + b_ in C:
            DZERK[n] = n[:-2] + b_
# поправка дзеркала (спокій A_TPose): R_n ≈ (DZ·R_пари·DZ)·MC[n]
DZ = Matrix.Scale(-1, 4, (1, 0, 0))
MC = {}
for n in NAZVY:
    sn = DZERK.get(n, n)
    if n in src1.pose.bones and sn in src1.pose.bones:
        ms_ = (DZ @ (src1.matrix_world @ src1.pose.bones[sn].matrix) @ DZ).to_quaternion()
        MC[n] = ms_.inverted() @ (src1.matrix_world @ src1.pose.bones[n].matrix).to_quaternion()
SPYNA = {"spine_01": 1 / 3, "spine_02": 2 / 3, "spine_03": 1.0, "neck_01": 1.0}
RUKA = ("clavicle", "upperarm", "lowerarm", "hand", "thumb", "index", "middle", "ring", "pinky")
NOGA_K = ("thigh", "calf", "foot", "ball")


def pocherk(n, r):
    """Почерк виду — повороти у світі (обличчя в −Y; +X — нахил уперед)."""
    sut = math.radians(POCHERK.get("сутулість", 0))
    if n in SPYNA:
        r = Quaternion((1, 0, 0), sut * SPYNA[n]) @ r
    elif n.lower() == "head":
        r = Quaternion((1, 0, 0), sut + math.radians(POCHERK.get("голова", 0))) @ r
    ruky = math.radians(POCHERK.get("руки", 0))
    if ruky and n.split("_")[0] in RUKA and n.split("_")[0] != "clavicle":
        r = Quaternion((0, 1, 0), -ruky if n.endswith("_l") else ruky) @ r
    st = math.radians(POCHERK.get("стійка", 0))
    if st and n.split("_")[0] in NOGA_K:
        r = Quaternion((0, 1, 0), -st if n.endswith("_l") else st) @ r
    return r



def zapekty(imia, dzherelo, temp):
    dzerk = dzherelo.startswith("дзеркало:")
    kl, nm = dzherelo.replace("дзеркало:", "").split(":")
    src, dii = dzherela[kl]
    C = CC[kl]
    dia = dii[nm]
    f0, f1 = (int(x) for x in dia.frame_range)
    nova = bpy.data.actions.new(imia)
    rig.animation_data.action = nova
    taz_s = src.matrix_world @ src.data.bones["pelvis"].head_local
    n_kadriv = f1 - f0
    for f in range(f0, f1 + 1):
        postav_dii(src, dia, f)
        fk = 1 + (f - f0) / temp
        for n in NAZVY:
            pb = rig.pose.bones[n]
            if n in KHVIST:
                # хвіст: повільна хвиля, сильніша на кінці; у русі — ширше
                faza = 2 * math.pi * (f - f0) / max(n_kadriv, 1)
                i = KHVIST.index(n) + 1
                amp = math.radians(6 + 3 * i) * (1.6 if imia in ("Run", "Walk") else 1.0)
                pb.rotation_quaternion = Quaternion((0, 0, 1), amp * math.sin(faza - 0.6 * i))
                pb.keyframe_insert("rotation_quaternion", frame=fk)
                continue
            sn = DZERK.get(n, n) if dzerk else n
            if sn not in C or sn not in src.pose.bones:
                continue
            m_s = src.matrix_world @ src.pose.bones[sn].matrix
            if dzerk:
                m_s = DZ @ m_s @ DZ
                r = m_s.to_quaternion() @ MC.get(n, Quaternion()) @ C[n]
            else:
                r = m_s.to_quaternion() @ C[n]
            r = pocherk(n, r)
            poz = pb.matrix.translation.copy()
            if n == "pelvis":
                poz = taz_t + (m_s.translation - (DZ @ taz_s if dzerk else taz_s)) * k_taz
            pb.matrix = Matrix.LocRotScale(poz, r, Vector((1, 1, 1)))
            bpy.context.view_layer.update()
            pb.keyframe_insert("rotation_quaternion", frame=fk)
            if n == "pelvis":
                pb.keyframe_insert("location", frame=fk)
    nova.use_fake_user = True
    tr = rig.animation_data.nla_tracks.new()
    tr.name = imia
    tr.strips.new(imia, 1, nova)
    rig.animation_data.action = None
    log("рух %s ← %s (%d кадрів, темп %.2f)" % (imia, dzherelo, n_kadriv + 1, temp))


TEMP = POCHERK.get("темп", 1.0)
for imia, dz in MANERA["кліпи"].items():
    try:
        zapekty(imia, dz, TEMP)
    except KeyError as e:
        log("‼ немає руху для", imia, dz, e)

for kl, (src, _) in dzherela.items():
    bpy.data.objects.remove(src)
for pb in rig.pose.bones:
    pb.matrix_basis.identity()
rig.name = "Скелет"

# ---------- 5. GLB ----------
bpy.ops.object.select_all(action="DESELECT")
rig.select_set(True)
tilo.select_set(True)
for zo in ZBROIA:
    zo.select_set(True)
bpy.ops.export_scene.gltf(filepath=VYHID, export_format="GLB", use_selection=True,
                          export_animations=True, export_animation_mode="NLA_TRACKS",
                          export_skins=True, export_apply=False)
bpy.ops.wm.save_as_mainfile(filepath=VYHID[:-4] + ".blend")
log("→", VYHID)
