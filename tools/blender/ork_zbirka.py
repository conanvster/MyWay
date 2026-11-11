"""Орк з нуля, крок 3: скульпти тіла й голови → одна ігрова сітка (spec/орк-з-нуля.md).

Два скульпти Pixal3D: тіло на повний зріст і окремо голова з великого плану (у рази
детальніша). Тут:
  1. з обох прибирається внутрішня стінка (Pixal3D дає тонкостінну подвійну оболонку) —
     парність перетинів променя вздовж нормалі;
  2. тіло — у зріст, ступні на землі; голова суміщається з головою тіла (подібність:
     масштаб + поворот + зсув, найближчі точки, ітераціями);
  3. площина шиї (горло спереду — потилична ямка ззаду) ріже обидві сітки: нижче — тіло,
     вище — детальна голова; краї зшиваються й згладжуються;
  4. спрощення: тіло й голова окремо, до заданої кількості трикутників;
  5. розгортка: голова — свій матеріал і своя текстура (обличчя одним островом), тіло — свій;
  6. запікання з обох скульптів: колір і карта нормалей (разом із власною картою нормалей
     скульпту — зморшки, пори).

    blender -b --factory-startup -P tools/blender/ork_zbirka.py -- <тіло.glb> <голова.glb> <вихід.blend> \
        [--зріст 1.9] [--тіло-трикутників 34000] [--голова-трикутників 26000] [--до суміщення|шов|сітка]
"""
import math
import os
import random
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector, kdtree
from mathutils.bvhtree import BVHTree

A = sys.argv[sys.argv.index("--") + 1:]
TILO, HOLOVA, VYHID = os.path.abspath(A[0]), os.path.abspath(A[1]), os.path.abspath(A[2])
PREF = os.path.splitext(VYHID)[0]


def arg(k, typ, d):
    return typ(A[A.index(k) + 1]) if k in A else d


ZRIST = arg("--зріст", float, 1.9)
N_TILO = arg("--тіло-трикутників", int, 34000)
N_HOL = arg("--голова-трикутників", int, 26000)
DO = arg("--до", str, "")


def log(*a):
    print("[збірка]", *a)
    sys.stdout.flush()


def vvesty(path, nazva):
    bpy.ops.import_scene.gltf(filepath=path)
    o = next(x for x in bpy.context.selected_objects if x.type == "MESH")
    for x in list(bpy.context.selected_objects):
        if x != o:
            bpy.data.objects.remove(x)
    o.name = nazva
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return o


def obolonka(o):
    """Лишити зовнішню стінку: внутрішня — та, чий промінь назовні перетинає 2, 6… стінок."""
    random.seed(3)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.normal_update()
    tree = BVHTree.FromBMesh(bm)

    def perety(c, d):
        n, p = 0, c + d * 0.0003
        for _ in range(24):
            h = tree.ray_cast(p, d, 9.0)
            if h[0] is None:
                break
            n += 1
            p = h[0] + d * 0.0003
        return n
    vn = []
    for f in bm.faces:
        c = f.calc_center_median()
        g = 0
        for k in range(3):
            d = f.normal.copy()
            if k:
                d = (d + Vector((random.uniform(-.15, .15), random.uniform(-.15, .15),
                                 random.uniform(-.15, .15)))).normalized()
            g += (perety(c, d) // 2) % 2
        if g >= 2:
            vn.append(f)
    do = len(bm.faces)
    bmesh.ops.delete(bm, geom=vn, context="FACES")
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.verts.ensure_lookup_table()
    seen, dribni = set(), []
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
        if len(ost) < 400:
            dribni.extend(ost)
    bmesh.ops.delete(bm, geom=dribni, context="VERTS")
    bm.to_mesh(o.data)
    bm.free()
    log("%s: внутрішніх граней %d з %d, уламків вершин %d → %d граней"
        % (o.name, len(vn), do, len(dribni), len(o.data.polygons)))


def tochky(o):
    n = len(o.data.vertices)
    a = np.empty(n * 3)
    o.data.vertices.foreach_get("co", a)
    return a.reshape(n, 3)


def zapysaty(o, P):
    o.data.vertices.foreach_set("co", P.ravel())
    o.data.update()


def podibnist(X, Y):
    """Umeyama: s, R, t таке, що s·R·x + t ≈ y."""
    mx, my = X.mean(0), Y.mean(0)
    Xc, Yc = X - mx, Y - my
    U, D, Vt = np.linalg.svd(Yc.T @ Xc / len(X))
    S = np.eye(3)
    if np.linalg.det(U) * np.linalg.det(Vt) < 0:
        S[2, 2] = -1
    R = U @ S @ Vt
    s = np.trace(np.diag(D) @ S) / (Xc ** 2).sum(1).mean()
    return s, R, my - s * R @ mx


bpy.ops.wm.read_factory_settings(use_empty=True)

if not os.path.exists(PREF + "-суміщено.blend") or DO == "суміщення":
    tilo = vvesty(TILO, "скульпт-тіло")
    hol = vvesty(HOLOVA, "скульпт-голова")
    obolonka(tilo)
    obolonka(hol)
    # тіло — у зріст
    P0 = tochky(tilo)
    k = ZRIST / (P0[:, 2].max() - P0[:, 2].min())
    P = (P0 - [(P0[:, 0].max() + P0[:, 0].min()) / 2, 0, P0[:, 2].min()]) * k
    ymed = np.median(P[:, 1])
    P[:, 1] -= ymed
    zapysaty(tilo, P)
    # голова тіла: верхні 20 см (вуха, чоло, ніс) — для масштабу; ціль суміщення — верхні 32 см
    T = P[P[:, 2] > ZRIST - 0.32]
    Tv = P[P[:, 2] > ZRIST - 0.20]
    H0 = tochky(hol)
    hz = H0[:, 2].max() - H0[:, 2].min()
    verh = H0[:, 2] > H0[:, 2].min() + hz * 0.5
    Hv = H0[verh]
    s0 = (Tv[:, 0].max() - Tv[:, 0].min()) / (Hv[:, 0].max() - Hv[:, 0].min())
    kd = kdtree.KDTree(len(T))
    for i, p in enumerate(T):
        kd.insert(p, i)
    kd.balance()
    rng = np.random.default_rng(5)
    idx = rng.choice(np.nonzero(verh)[0], 5000, replace=False)
    najkr = None
    for nahyl in (0, 15, 30, 45):          # голова тіла нахилена вперед — спробувати кілька
        a_ = math.radians(nahyl)
        Rx = np.array([[1, 0, 0], [0, math.cos(a_), math.sin(a_)], [0, -math.sin(a_), math.cos(a_)]])
        H = (H0 * s0) @ Rx.T
        Hv = H[verh]
        H = H + np.array([(Tv[:, 0].max() + Tv[:, 0].min()) / 2 - (Hv[:, 0].max() + Hv[:, 0].min()) / 2,
                          Tv[:, 1].min() - Hv[:, 1].min(), Tv[:, 2].max() - Hv[:, 2].max()])
        for it in range(50):
            mezha = 0.05 if it < 15 else (0.025 if it < 30 else 0.012)
            X, Y = [], []
            for i in idx:
                co, j, d = kd.find(H[i])
                if d < mezha:
                    X.append(H[i])
                    Y.append(T[j])
            if len(X) < 300:
                break
            s, R, t = podibnist(np.array(X), np.array(Y))
            H = s * (H @ R.T) + t
        vid = np.array([kd.find(H[i])[2] for i in idx])
        oc = np.median(vid)
        log("нахил %d°: пар %d, медіана %.1f мм, 90 %%: %.1f мм" % (nahyl, len(X), oc * 1000, np.percentile(vid, 90) * 1000))
        if najkr is None or oc < najkr[0]:
            najkr = (oc, H.copy())
    H = najkr[1]
    log("суміщення: медіана %.1f мм; ширина голови %.3f м" % (najkr[0] * 1000, H[verh][:, 0].max() - H[verh][:, 0].min()))
    zapysaty(hol, H)
    sH, RH, tH = podibnist(H0, H)          # сирий скульпт голови → на місце
    np.savez(PREF + "-суміщення.npz", k=k, zsuv=np.array([(P0[:, 0].max() + P0[:, 0].min()) / 2, 0, P0[:, 2].min()]),
             ymed=ymed, s=sH, R=RH, t=tH)
    bpy.ops.wm.save_as_mainfile(filepath=PREF + "-суміщено.blend")
    log("→", PREF + "-суміщено.blend")
    # профіль по середині — щоб вибрати площину шиї
    for o in (tilo, hol):
        Q = tochky(o)
        m = np.abs(Q[:, 0]) < 0.012
        Q = Q[m & (Q[:, 2] > ZRIST * 0.72)]
        np.save(PREF + "-профіль-%s.npy" % o.name, Q[:, 1:])
    if DO == "суміщення":
        sys.exit(0)


# ── 3. шов: об'єднання об'ємів ───────────────────────────────────────
# площина шиї (профіль по середині, заміряно на суміщених скульптах): горло спереду —
# потилична ямка ззаду; вище — детальна голова, нижче — тіло
SH_P = Vector((0, arg("--горло-y", float, -0.085), arg("--горло-z", float, 1.60)))
_nap = Vector((0, arg("--потилиця-y", float, 0.05), arg("--потилиця-z", float, 1.775)))
_d = (_nap - SH_P).normalized()
SH_N = Vector((0, -_d.z, _d.y))            # угору-вперед: бік голови
HOL_C = Vector((0, -0.05, ZRIST - 0.15))
VOKSEL = arg("--воксель", float, 0.0025)


def aktyv(o):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o


def voksel(o, rozmir):
    aktyv(o)
    bm = bmesh.new()                      # шви розгортки розривають сітку — зварити
    bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(o.data)
    bm.free()
    m = o.modifiers.new("в", "REMESH")
    m.mode = "VOXEL"
    m.voxel_size = rozmir
    m.use_smooth_shade = True
    bpy.ops.object.modifier_apply(modifier=m.name)


def najbilsha(o):
    """Лишити найбільший зв'язний шматок (зовнішню поверхню; порожнини — геть)."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.verts.ensure_lookup_table()
    seen, shmatky = set(), []
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
        shmatky.append(ost)
    shmatky.sort(key=len, reverse=True)
    for sh in shmatky[1:]:
        bmesh.ops.delete(bm, geom=sh, context="VERTS")
    bm.to_mesh(o.data)
    bm.free()
    log("%s: шматків %d, лишився найбільший (%d вершин)" % (o.name, len(shmatky), len(shmatky[0])))


def vidrizaty(o, tochka, normal, lyshyty_nyz):
    """Відняти брус по один бік площини (булеве віднімання — об'єм лишається замкненим)."""
    r = 0.3
    bpy.ops.mesh.primitive_cube_add(size=1)
    c = bpy.context.active_object
    c.scale = (2 * r, 2 * r, 2 * r)
    n = normal.normalized() if lyshyty_nyz else -normal.normalized()
    c.rotation_euler = n.to_track_quat("Z", "Y").to_euler()
    c.location = tochka + n * r
    aktyv(o)
    m = o.modifiers.new("б", "BOOLEAN")
    m.operation = "DIFFERENCE"
    m.object = c
    m.solver = "EXACT"
    bpy.ops.object.modifier_apply(modifier=m.name)
    bpy.data.objects.remove(c)


if not os.path.exists(PREF + "-обєм.blend") or DO == "шов":
    z = np.load(PREF + "-суміщення.npz")
    tilo = vvesty(TILO, "обєм-тіло")
    P = (tochky(tilo) - z["zsuv"]) * float(z["k"])
    P[:, 1] -= float(z["ymed"])
    zapysaty(tilo, P)
    voksel(tilo, 0.003)
    najbilsha(tilo)
    hol = vvesty(HOLOVA, "обєм-голова")
    voksel(hol, 0.0025)                    # у сирому масштабі: стінка ~6 мм, після зменшення — 1,5
    najbilsha(hol)
    zapysaty(hol, float(z["s"]) * (tochky(hol) @ z["R"].T) + z["t"])
    # голову тіла прибрати опуклою оболонкою детальної голови (трохи роздутою), а не площиною:
    # площина зрізала й трапеції за шиєю — лишався рівний уступ-«комір»
    H = tochky(hol)
    nad = H[(H - np.array(SH_P)) @ np.array(SH_N) > 0]
    nad = nad[np.random.default_rng(1).choice(len(nad), min(30000, len(nad)), replace=False)]
    cn = nad.mean(0)
    nad = cn + (nad - cn) * arg("--роздути", float, 1.07)
    bmh = bmesh.new()
    for p_ in nad:
        bmh.verts.new(p_)
    r_ = bmesh.ops.convex_hull(bmh, input=bmh.verts)
    bmesh.ops.delete(bmh, geom=[v for v in bmh.verts if not v.link_faces], context="VERTS")
    bmesh.ops.recalc_face_normals(bmh, faces=bmh.faces)
    mh_ = bpy.data.meshes.new("різак")
    bmh.to_mesh(mh_)
    bmh.free()
    rizak = bpy.data.objects.new("різак", mh_)
    bpy.context.scene.collection.objects.link(rizak)
    aktyv(tilo)
    mb = tilo.modifiers.new("б", "BOOLEAN")
    mb.operation = "DIFFERENCE"
    mb.object = rizak
    mb.solver = "EXACT"
    bpy.ops.object.modifier_apply(modifier=mb.name)
    bpy.data.objects.remove(rizak)
    najbilsha(tilo)
    vidrizaty(hol, SH_P - SH_N * 0.035, SH_N, False)
    najbilsha(hol)
    aktyv(tilo)
    hol.select_set(True)
    bpy.ops.object.join()
    tilo.name = "обєм"
    voksel(tilo, VOKSEL)
    najbilsha(tilo)
    # стик: згладити смугу біля площини шиї (не обличчя: лише нижче площини + 1 см над нею)
    bm = bmesh.new()
    bm.from_mesh(tilo.data)
    smuha = [v for v in bm.verts
             if -0.03 < (v.co - SH_P).dot(SH_N) < 0.012 and (v.co - HOL_C).length < 0.26]
    for _ in range(3):
        bmesh.ops.smooth_vert(bm, verts=smuha, factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    bm.to_mesh(tilo.data)
    bm.free()
    log("об'єм: %d вершин, %d граней; згладжено на стику %d" % (len(tilo.data.vertices), len(tilo.data.polygons), len(smuha)))
    bpy.ops.wm.save_as_mainfile(filepath=PREF + "-обєм.blend")
    log("→", PREF + "-обєм.blend")
    if DO == "шов":
        sys.exit(0)


# ── 4–6. ігрова сітка, розгортка, запікання ──────────────────────────
def bik_holovy(co, zapas=0.03):
    """Матеріал і щільність голови — із запасом 3 см нижче площини шиї (кути щелепи)."""
    return (co - SH_P).dot(SH_N) > -zapas and (co - HOL_C).length < 0.215


bpy.ops.wm.open_mainfile(filepath=PREF + "-обєм.blend")
o = bpy.data.objects["обєм"]
o.name = "Тіло"
aktyv(o)
# різак-оболонка ширший за шию детальної голови — довкола шиї лишається щілина ~6 мм.
# Закрити: смугу шиї роздути на 6 мм, перелити вокселями, здути назад (лише смуга)
def vaga_smuhy(co):
    d = (co - SH_P).dot(SH_N)
    if (co - HOL_C).length > 0.23:
        return 0.0
    return max(0.0, min(1.0, (d + 0.06) / 0.02, (0.035 - d) / 0.02))


def rozduty(o_, na):
    g = o_.vertex_groups.new(name="смуга")
    for v in o_.data.vertices:
        w = vaga_smuhy(v.co)
        if w > 0:
            g.add([v.index], w, "REPLACE")
    m_ = o_.modifiers.new("р", "DISPLACE")
    m_.direction = "NORMAL"
    m_.mid_level = 0.0
    m_.strength = na
    m_.vertex_group = "смуга"
    bpy.ops.object.modifier_apply(modifier=m_.name)
    o_.vertex_groups.remove(o_.vertex_groups["смуга"])


if "--без-закриття" not in A:
    rozduty(o, 0.006)
    voksel(o, VOKSEL)
    najbilsha(o)
    rozduty(o, -0.006)
bm = bmesh.new()
bm.from_mesh(o.data)
smuha = [v for v in bm.verts if vaga_smuhy(v.co) > 0.5]
for _ in range(arg("--стик", int, 12)):
    bmesh.ops.smooth_vert(bm, verts=smuha, factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
bm.to_mesh(o.data)
bm.free()
me = o.data
me.materials.clear()                       # матеріали сирих скульптів — геть
# голова й тіло спрощуються окремо, але в одній сітці (без розривів): група вершин обмежує
# спрощувач своєю частиною; разом він віддавав голові 52 тис. трикутників із 60
def trykutnykiv():
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def chastyna(holova, tsil):
    me_ = o.data
    hol_t = 0
    for p in me_.polygons:
        c = sum((me_.vertices[i].co for i in p.vertices), Vector()) / len(p.vertices)
        if bik_holovy(c):
            hol_t += len(p.vertices) - 2
    use = trykutnykiv()
    svoi = hol_t if holova else use - hol_t
    g = o.vertex_groups.new(name="с")
    g.add([v.index for v in me_.vertices if bik_holovy(v.co) == holova], 1.0, "REPLACE")
    m = o.modifiers.new("с", "DECIMATE")
    m.ratio = max(0.001, (use - svoi + tsil) / use)
    m.vertex_group = "с"
    m.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=m.name)
    o.vertex_groups.remove(o.vertex_groups["с"])
    log("%s: %d → ціль %d; усього тепер %d" % ("голова" if holova else "тіло", svoi, tsil, trykutnykiv()))


chastyna(False, N_TILO)
chastyna(True, N_HOL)
me = o.data
for p in me.polygons:
    p.use_smooth = True

mt = bpy.data.materials.new("шкіра-тіло")
mh = bpy.data.materials.new("шкіра-голова")
me.materials.append(mt)
me.materials.append(mh)
V = [v.co.copy() for v in me.vertices]
hol_f = []
for p in me.polygons:
    c = sum((V[i] for i in p.vertices), Vector()) / len(p.vertices)
    p.material_index = 1 if bik_holovy(c) else 0
    if p.material_index:
        hol_f.append(p.index)
log("ігрова сітка: %d трикутників, з них голова %d" % (len(me.polygons), len(hol_f)))
if "--лише-лічити" in A:
    sys.exit(0)

# розгортка голови: обличчя (перед вухами) — один острів, решта — другий
hx = np.array([V[i][:] for p in (me.polygons[j] for j in hol_f) for i in p.vertices])
vukha = hx[np.abs(hx[:, 0]) > 0.9 * np.abs(hx[:, 0]).max()]
y_riz = float(vukha[:, 1].min()) - 0.012
klas = {}
for j in hol_f:
    p = me.polygons[j]
    c = sum((V[i] for i in p.vertices), Vector()) / len(p.vertices)
    klas[j] = c.y < y_riz
bm = bmesh.new()
bm.from_mesh(me)
bm.faces.ensure_lookup_table()
for e in bm.edges:
    fs = e.link_faces
    if len(fs) == 2:
        a, b = fs[0], fs[1]
        if a.material_index != b.material_index or (a.material_index and klas[a.index] != klas[b.index]):
            e.seam = True
bm.to_mesh(me)
bm.free()
me.uv_layers.new(name="UVMap")
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_mode(type="FACE")
bpy.ops.mesh.select_all(action="DESELECT")
bpy.ops.object.mode_set(mode="OBJECT")
for j in hol_f:
    me.polygons[j].select = True
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.uv.unwrap(method="ANGLE_BASED", margin=0.01)
bpy.ops.object.mode_set(mode="OBJECT")
# обличчю — ліві 62 % текстури, потилиці — решта (кожну частину вписати у свій прямокутник)
uv = me.uv_layers.active.data
for pered, (x0, x1) in ((True, (0.004, 0.62)), (False, (0.628, 0.996))):
    ls = [l for j in hol_f if klas[j] == pered for l in me.polygons[j].loop_indices]
    if not ls:
        continue
    U = np.array([uv[l].uv[:] for l in ls])
    lo_, hi_ = U.min(0), U.max(0)
    k_ = min((x1 - x0) / (hi_[0] - lo_[0]), 0.992 / (hi_[1] - lo_[1]))
    U = (U - lo_) * k_ + [x0, 0.004]
    for l, u_ in zip(ls, U):
        uv[l].uv = u_
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="INVERT")
bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.002)
bpy.ops.object.mode_set(mode="OBJECT")

# джерела: сирі скульпти на своїх місцях (промінь іззовні перший зустрічає зовнішню стінку;
# очищені від внутрішньої стінки мали дірки — чорні плями на плечах)
z = np.load(PREF + "-суміщення.npz")
dzh = []
for path, nazva in ((TILO, "скульпт-тіло"), (HOLOVA, "скульпт-голова")):
    s = vvesty(path, nazva)
    Q = tochky(s)
    if nazva == "скульпт-тіло":
        Q = (Q - z["zsuv"]) * float(z["k"])
        Q[:, 1] -= float(z["ymed"])
    else:
        Q = float(z["s"]) * (Q @ z["R"].T) + z["t"]
    zapysaty(s, Q)
    bm = bmesh.new()
    bm.from_mesh(s.data)
    if nazva == "скульпт-тіло":
        # голова тіла — геть, але трапеції довкола шиї лишити: вони зовні від тонкої шиї
        # детальної голови, і без них на стику лишалась темна рвана смуга
        hb = bmesh.new()
        bpy.ops.import_scene.gltf(filepath=HOLOVA)
        ho = next(x for x in bpy.context.selected_objects if x.type == "MESH")
        hb.from_mesh(ho.data)
        hb.transform(ho.matrix_world)
        for v in hb.verts:
            v.co = Vector(float(z["s"]) * (z["R"] @ np.array(v.co)) + z["t"])
        for x in list(bpy.context.selected_objects):
            bpy.data.objects.remove(x)
        htree = BVHTree.FromBMesh(hb)

        def het_tilo(c):
            if not bik_holovy(c, 0.0):
                return False
            if (c - SH_P).dot(SH_N) > 0.03 and (c - HOL_C).length < 0.16:
                return True
            n_ = htree.find_nearest(c, 0.025)
            return n_[0] is not None
        het = [f for f in bm.faces if het_tilo(f.calc_center_median())]
        hb.free()
    else:
        # погруддя скульпту голови (плечі, груди) — геть: лишається голова й шия
        het = [f for f in bm.faces if not bik_holovy(f.calc_center_median(), 0.045)]
    bmesh.ops.delete(bm, geom=het, context="FACES")
    bm.to_mesh(s.data)
    bm.free()
    for p in s.data.polygons:
        p.use_smooth = True
    for mat in s.data.materials:
        b = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        for l in list(b.inputs["Metallic"].links):
            mat.node_tree.links.remove(l)
        b.inputs["Metallic"].default_value = 0.0
    dzh.append(s)

ROZ = {"шкіра-тіло": arg("--текстура-тіла", int, 4096), "шкіра-голова": arg("--текстура-голови", int, 4096)}
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
except Exception as e:                      # без відеокарти — процесор
    log("запікання на процесорі:", e)
sc.view_settings.view_transform = "Standard"
bk = sc.render.bake
bk.use_selected_to_active = True
bk.cage_extrusion = 0.012
bk.max_ray_distance = 0.035
bk.margin = 8
bk.normal_space = "TANGENT"
bk.use_pass_direct = False
bk.use_pass_indirect = False
bk.use_pass_color = True
bpy.ops.object.select_all(action="DESELECT")
for s in dzh:
    s.select_set(True)
o.select_set(True)
bpy.context.view_layer.objects.active = o
vuzly = {}
for mat in (mt, mh):
    mat.use_nodes = True
    n = mat.node_tree.nodes.new("ShaderNodeTexImage")
    mat.node_tree.nodes.active = n
    vuzly[mat.name] = n
def rozklasty(px, ye):
    """Тло між островами — кольором найближчого острова (піраміда: стиснути, розтягнути)."""
    rivni = []
    a, m = px * ye[..., None], ye.astype(np.float32)
    while min(a.shape[:2]) > 2:
        rivni.append((a, m))
        h, w = a.shape[0] // 2 * 2, a.shape[1] // 2 * 2
        a = a[:h, :w].reshape(h // 2, 2, w // 2, 2, -1).sum((1, 3))
        m = m[:h, :w].reshape(h // 2, 2, w // 2, 2).sum((1, 3))
    kol = a / np.maximum(m, 1e-6)[..., None]
    for a, m in reversed(rivni):
        up = np.repeat(np.repeat(kol, 2, 0), 2, 1)
        up = np.pad(up, ((0, a.shape[0] - up.shape[0]), (0, a.shape[1] - up.shape[1]), (0, 0)), mode="edge")
        kol = np.where((m > 0)[..., None], a / np.maximum(m, 1e-6)[..., None], up)
    return np.where(ye[..., None], px, kol).astype(np.float32)


def maska_uv(mat_i, r, lyshe_smuha=False):
    """Розгортка матеріалу растром: де є грані (і, окремо, грані смуги шиї)."""
    import cv2
    m = np.zeros((r, r), np.uint8)
    uvd = me.uv_layers.active.data
    for p in me.polygons:
        if p.material_index != mat_i:
            continue
        if lyshe_smuha:
            c = sum((me.vertices[i].co for i in p.vertices), Vector()) / len(p.vertices)
            d = (c - SH_P).dot(SH_N)
            if not (-0.16 < d < 0.05 and (c - HOL_C).length < 0.34):
                continue
        pts = np.array([[uvd[l].uv.x * r, uvd[l].uv.y * r] for l in p.loop_indices], np.int32)
        cv2.fillPoly(m, [pts], 255)
    return m > 0


def dopysaty(im, mat, vyd):
    """Після запікання: темні промахи на стику шиї й тло між островами — сусіднім кольором."""
    import cv2
    r = im.size[0]
    px = np.array(im.pixels[:], np.float32).reshape(r, r, 4)
    mi = 0 if mat == mt else 1
    ye = maska_uv(mi, r)
    if vyd == "колір":
        zle = maska_uv(mi, r, True) & (px[..., :3].max(2) < (0.09 if mi else 0.17))
        zle = cv2.dilate(zle.astype(np.uint8), np.ones((5, 5), np.uint8)) > 0
        POHANI[mat.name] = zle
    zle = POHANI.get(mat.name)
    if zle is not None:
        ye = ye & ~zle
        log("%s %s: промахів на стику шиї — %d точок" % (mat.name, vyd, int(zle.sum())))
    px[..., :3] = rozklasty(px[..., :3], ye)
    px[..., 3] = 1.0
    im.pixels.foreach_set(px.ravel())


POHANI = {}
karty = {}
for vyd, typ in (("колір", "DIFFUSE"), ("нормалі", "NORMAL")):
    for mat in (mt, mh):
        r = ROZ[mat.name]
        im = bpy.data.images.new("%s-%s" % (mat.name, vyd), r, r, alpha=False)
        if vyd == "нормалі":
            im.colorspace_settings.name = "Non-Color"
        vuzly[mat.name].image = im
        karty[(mat.name, vyd)] = im
    bpy.ops.object.bake(type=typ)
    for mat in (mt, mh):
        im = karty[(mat.name, vyd)]
        dopysaty(im, mat, vyd)
        im.filepath_raw = "%s_%s-%s.png" % (PREF, mat.name, vyd)
        im.file_format = "PNG"
        im.save()
        log("→", im.filepath_raw)
for s in dzh:
    bpy.data.objects.remove(s)
for mat in (mt, mh):
    nt = mat.node_tree
    b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    nt.nodes.remove(vuzly[mat.name])
    tc = nt.nodes.new("ShaderNodeTexImage")
    tc.image = karty[(mat.name, "колір")]
    nt.links.new(tc.outputs[0], b.inputs["Base Color"])
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = karty[(mat.name, "нормалі")]
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(tn.outputs[0], nm.inputs["Color"])
    nt.links.new(nm.outputs[0], b.inputs["Normal"])
    b.inputs["Roughness"].default_value = 0.62
    b.inputs["Metallic"].default_value = 0.0
bpy.ops.wm.save_as_mainfile(filepath=VYHID)
bpy.ops.object.select_all(action="DESELECT")
o.select_set(True)
bpy.ops.export_scene.gltf(filepath=PREF + ".glb", use_selection=True, export_apply=True)
log("→", VYHID, "і", PREF + ".glb")
