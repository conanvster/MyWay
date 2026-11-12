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
    for sh in shmatky[1:3]:
        if len(sh) > 2000:                 # великий відкинутий шматок — це не порожнина, а втрата
            zz = [v.co.z for v in sh]
            log("%s: УВАГА, відкинуто шматок %d вершин, z %.3f…%.3f" % (o.name, len(sh), min(zz), max(zz)))
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
    # погруддя Pixal3D — порожня оболонка зі стінкою 2,5 мм (після зменшення ~1 мм, тонше за
    # воксель): спільний ремеш може розкришити голову на тисячі уламків (орчиха-3, 12.11.2026).
    # --стінка-голови d: потовщити стінку на d з кожного боку (у сирому масштабі) до спільного
    # ремешу, а після нього здути зовнішню поверхню голови назад на d·s.
    STINKA = arg("--стінка-голови", float, 0.0)
    if STINKA:
        hol.data.update()
        zapysaty(hol, tochky(hol) + STINKA * np.array([v.normal[:] for v in hol.data.vertices]))
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
    vidrizaty(hol, SH_P - SH_N * arg("--зріз-голови", float, 0.035), SH_N, False)
    najbilsha(hol)
    aktyv(tilo)
    hol.select_set(True)
    bpy.ops.object.join()
    tilo.name = "обєм"
    voksel(tilo, VOKSEL)
    najbilsha(tilo)
    if STINKA:
        tilo.data.update()
        P_ = tochky(tilo)
        dp = (P_ - np.array(SH_P)) @ np.array(SH_N)
        w_ = np.clip(dp / 0.02, 0, 1)[:, None]
        zapysaty(tilo, P_ - w_ * STINKA * float(z["s"]) * np.array([v.normal[:] for v in tilo.data.vertices]))
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
# (12.11.2026, слово замовника: «перехід між шиєю та плечима треба вирівняти»: край вирізу
# під голову лишався рваним уступом-«коміром» на трапеціях. Смуга ширша — до 30 см від центру
# голови й 9 см нижче площини, за вухами — до 6 см вище; закриття 15 мм замість 6, згладжування
# 40 проходів; краї смуги згасають плавно, інакше на її межі лишався рубець-«намисто».)
def vaga_smuhy(co):
    d = (co - SH_P).dot(SH_N)
    r = (co - HOL_C).length
    if r > 0.30:
        return 0.0
    hi = 0.035 if co.y < -0.02 else 0.06   # спереду — не чіпати щелепу; за вухами — вище
    return max(0.0, min(1.0, (d + 0.09) / 0.04, (hi - d) / 0.02, (0.30 - r) / 0.06))


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


ZAKR = arg("--закриття", float, 0.015)
if "--без-закриття" not in A:
    rozduty(o, ZAKR)
    voksel(o, VOKSEL)
    najbilsha(o)
    rozduty(o, -ZAKR)
bm = bmesh.new()
bm.from_mesh(o.data)
smuha = [v for v in bm.verts if vaga_smuhy(v.co) > 0.3]
for _ in range(arg("--стик", int, 40)):
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
            if not (-0.16 < d < 0.05 and (c - HOL_C).length < arg("--промахи-радіус", float, 0.34)):
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
    if vyd == "колір" and not (mi == 0 and "--без-промахів-тіла" in A):
        zle = maska_uv(mi, r, True) & (px[..., :3].max(2) < arg("--промах-поріг", float, 0.09 if mi else 0.17))
        zle = cv2.dilate(zle.astype(np.uint8), np.ones((ROZSHYR, ROZSHYR), np.uint8)) > 0
        POHANI[mat.name] = zle
    zle = POHANI.get(mat.name)
    if zle is not None:
        ye = ye & ~zle
        log("%s %s: промахів на стику шиї — %d точок" % (mat.name, vyd, int(zle.sum())))
    px[..., :3] = rozklasty(px[..., :3], ye)
    if zle is not None and "--латка-гладка" in A:
        # великі латки пірамідою виходять «квадратиками» (залишки лямок топа на шиї орчихи)
        rozm = cv2.GaussianBlur(px[..., :3], (0, 0), 14)
        px[..., :3][zle] = rozm[zle]
    px[..., 3] = 1.0
    im.pixels.foreach_set(px.ravel())


ROZSHYR = 13 if "--латка-гладка" in A else 5
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
if "--чистити-шкіру" in A:
    # слово замовника 12.11.2026 (ельфійка): «підчисти шкіру на внутрішній стороні рук та ніг та тіла
    # та шиї». Руки скульпту опущені до стегон: чорне від білизни запеклося на передпліччі, по
    # внутрішньому боці стегон і тулуба — темні смуги, на шиї — латки. Чорне лишається тільки там,
    # де воно білизна: великий темний шматок на тулубі (не на руці) у поясі висоти, де темного багато.
    # Решта темного замальовується шкірою, а плями середнього розміру вирівнюються.
    import cv2
    uvd = me.uv_layers.active.data
    im = karty[(mt.name, "колір")]
    r = im.size[0]
    px = np.array(im.pixels[:], np.float32).reshape(r, r, 4)
    k3 = px[..., :3]
    uvm = maska_uv(0, r) > 0
    sv = k3.max(2)
    med = float(np.median(sv[uvm & (sv > 0.25)]))
    temne_px = sv < 0.45 * med
    nv = len(me.vertices)
    V = np.array([v.co[:] for v in me.vertices])
    # руки: найвищий зріз, під яким сітка ділиться на тулуб і дві бічні гілки
    rebra = np.array([e.vertices[:] for e in me.edges])
    ruka = np.zeros(nv, bool)
    for zr in np.arange(0.82 * ZRIST, 0.45 * ZRIST, -0.01):
        bat = np.arange(nv)

        def kor(i):
            while bat[i] != i:
                bat[i] = bat[bat[i]]
                i = bat[i]
            return i
        for a_, b_ in rebra:
            if V[a_, 2] < zr and V[b_, 2] < zr:
                ra, rb = kor(a_), kor(b_)
                if ra != rb:
                    bat[ra] = rb
        kk = np.array([kor(i) for i in range(nv)])
        kk[V[:, 2] >= zr] = -1
        ids, cnt = np.unique(kk[kk >= 0], return_counts=True)
        vel = [i for i, c_ in zip(ids, cnt) if c_ > 300]
        bichni = [i for i in vel if abs(V[kk == i, 0].mean()) > 0.1 and V[kk == i, 2].max() > zr - 0.03]
        if len(vel) >= 3 and len(bichni) == 2:
            for i in bichni:
                ruka |= kk == i
            log("чистити шкіру: руки окремо нижче z=%.2f, вершин рук %d" % (zr, int(ruka.sum())))
            break
    # темні грані тіла (за текселем у центрі грані) і частка темного по висоті на тулубі
    pol = [p_ for p_ in me.polygons if p_.material_index == 0]
    tc = np.array([sum((V[i] for i in p_.vertices), np.zeros(3)) / len(p_.vertices) for p_ in pol])
    tuv = np.array([sum((np.array(uvd[l].uv[:]) for l in p_.loop_indices), np.zeros(2)) / len(p_.loop_indices) for p_ in pol])
    tem = temne_px[np.clip((tuv[:, 1] * r).astype(int), 0, r - 1), np.clip((tuv[:, 0] * r).astype(int), 0, r - 1)]
    na_rutsi = np.array([all(ruka[i] for i in p_.vertices) for p_ in pol])
    kosh = np.clip((tc[:, 2] / 0.01).astype(int), 0, 400)
    usi = np.bincount(kosh[~na_rutsi], minlength=401).astype(float)
    chastka = np.bincount(kosh[~na_rutsi & tem], minlength=401) / np.maximum(usi, 1)
    poias = chastka > arg("--білизна-частка", float, 0.2)
    # зв'язні шматки темних граней тулуба в поясах білизни
    idx = {p_.index: j for j, p_ in enumerate(pol)}
    kand = tem & ~na_rutsi & poias[kosh]
    po_rebru = {}
    for j, p_ in enumerate(pol):
        if kand[j]:
            for ek in p_.edge_keys:
                po_rebru.setdefault(ek, []).append(j)
    sus_ = {}
    for js in po_rebru.values():
        if len(js) == 2:
            sus_.setdefault(js[0], []).append(js[1])
            sus_.setdefault(js[1], []).append(js[0])
    bilyzna = np.zeros(len(pol), bool)
    bachyv = set()
    for j0 in np.nonzero(kand)[0]:
        if j0 in bachyv:
            continue
        sh, st = [], [j0]
        bachyv.add(j0)
        while st:
            j = st.pop()
            sh.append(j)
            for u in sus_.get(j, ()):
                if u not in bachyv:
                    bachyv.add(u)
                    st.append(u)
        if sum(pol[j].area for j in sh) > 0.01:        # > 100 см² — білизна, а не слід
            bilyzna[sh] = True
    Mb = np.zeros((r, r), np.uint8)
    for j in np.nonzero(bilyzna)[0]:
        pts = np.array([[uvd[l].uv.x * r, uvd[l].uv.y * r] for l in pol[j].loop_indices], np.int32)
        cv2.fillPoly(Mb, [pts], 255)
    # діри в білизні (світла пляма посеред топа): замкнені острівці всередині темного — зафарбувати
    zamk = cv2.morphologyEx(Mb, cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))
    zovni = zamk.copy()
    cv2.floodFill(zovni, np.zeros((r + 2, r + 2), np.uint8), (0, 0), 128)
    for kut_ in ((r - 1, 0), (0, r - 1), (r - 1, r - 1)):
        if zovni[kut_[1], kut_[0]] == 0:
            cv2.floodFill(zovni, np.zeros((r + 2, r + 2), np.uint8), kut_, 128)
    diry = (zovni == 0) & uvm
    if diry.any() and Mb.any():
        kb = np.median(k3[(Mb > 0) & temne_px], 0)
        wd = cv2.GaussianBlur(diry.astype(np.float32), (0, 0), 1.5)[..., None]
        k3[:] = k3 * (1 - wd) + kb * wd
        temne_px = temne_px | diry
        Mb[diry] = 255
        log("чистити шкіру: дір у білизні зафарбовано %d точок" % int(diry.sum()))
    # пояси висоти, де тулуб переважно темний (смуга топа, верх трусів): світлі грані там — діра
    sucilni = chastka > arg("--білизна-суцільна", float, 0.62)
    Md = np.zeros((r, r), np.uint8)
    # лише біля середини тіла: збоку на цій висоті — плечі опущених рук, їх чіпати не можна
    for j in np.nonzero(~tem & ~na_rutsi & sucilni[kosh] & (np.abs(tc[:, 0]) < 0.07))[0]:
        pts = np.array([[uvd[l].uv.x * r, uvd[l].uv.y * r] for l in pol[j].loop_indices], np.int32)
        cv2.fillPoly(Md, [pts], 255)
    if Md.any() and Mb.any():
        kb = np.median(k3[(Mb > 0) & temne_px], 0)
        Md = cv2.dilate(Md, np.ones((5, 5), np.uint8))
        wd = cv2.GaussianBlur((Md > 0).astype(np.float32), (0, 0), 1.5)[..., None]
        k3[:] = k3 * (1 - wd) + kb * wd
        temne_px = temne_px | (Md > 0)
        Mb[Md > 0] = 255
        log("чистити шкіру: світлих граней у суцільних поясах білизни зафарбовано %d точок" % int((Md > 0).sum()))
    Mb = cv2.dilate(Mb, np.ones((7, 7), np.uint8)) > 0     # край білизни не чіпати
    brud = cv2.dilate((temne_px & uvm & ~Mb).astype(np.uint8), np.ones((9, 9), np.uint8)) > 0
    brud &= ~Mb
    shkira = (uvm & ~brud & ~Mb & ~temne_px).astype(np.float32)
    sg = r * 0.012
    zalyv = cv2.GaussianBlur(k3 * shkira[..., None], (0, 0), sg) / np.maximum(
        cv2.GaussianBlur(shkira, (0, 0), sg)[..., None], 1e-3)
    # там, де шкіри поруч немає (великий слід), — ширше розмиття
    sg_ = r * 0.05
    zalyv2 = cv2.GaussianBlur(k3 * shkira[..., None], (0, 0), sg_) / np.maximum(
        cv2.GaussianBlur(shkira, (0, 0), sg_)[..., None], 1e-3)
    blyzko = np.clip(cv2.GaussianBlur(shkira, (0, 0), sg) / 0.15, 0, 1)[..., None]
    zalyv = zalyv * blyzko + zalyv2 * (1 - blyzko)
    wb = cv2.GaussianBlur(brud.astype(np.float32), (0, 0), 2.5)[..., None]
    k3[:] = k3 * (1 - wb) + zalyv * wb
    # плями середнього розміру (латки, смуги): дрібний тон → до широкого тону, лише шкіра
    shk = (uvm & ~Mb).astype(np.float32)
    dr = cv2.GaussianBlur(k3 * shk[..., None], (0, 0), r * 0.006) / np.maximum(cv2.GaussianBlur(shk, (0, 0), r * 0.006)[..., None], 1e-3)
    sh_ = cv2.GaussianBlur(k3 * shk[..., None], (0, 0), r * 0.04) / np.maximum(cv2.GaussianBlur(shk, (0, 0), r * 0.04)[..., None], 1e-3)
    mn = np.clip(sh_ / np.maximum(dr, 1e-3), 0.6, 1.6)
    k3[:] = np.where(shk[..., None] > 0, np.clip(k3 * (1 + (mn - 1) * 0.75), 0, 1), k3)
    # «комір»: смуга тіла біля шиї після лікування промахів блідіша за плечі й груди — її широкий
    # тон звести до тону шкіри довкола смуги
    sm = (maska_uv(0, r, True) > 0) & ~Mb
    if sm.any():
        poza = (uvm & ~sm & ~Mb & ~temne_px).astype(np.float32)
        smf = sm.astype(np.float32)
        tut = cv2.GaussianBlur(k3 * smf[..., None], (0, 0), r * 0.012) / np.maximum(cv2.GaussianBlur(smf, (0, 0), r * 0.012)[..., None], 1e-3)
        dov = np.median(k3[poza > 0], 0)
        mn = np.clip(dov / np.maximum(tut, 1e-3), 0.6, 1.6)
        ws = cv2.GaussianBlur(smf, (0, 0), 4)[..., None] * smf[..., None]
        k3[:] = np.clip(k3 * (1 + (mn - 1) * 0.85 * ws), 0, 1)
    log("чистити шкіру: білизна — %d граней, замальовано %.1f %% розгортки тіла"
        % (int(bilyzna.sum()), 100.0 * brud.sum() / max(1, uvm.sum())))
    im.pixels.foreach_set(px.ravel())
    im.save()
    # карта нормалей тіла: де промінь запікання влучив у сусідню поверхню (рука біля стегна,
    # ноги одна біля одної, пальці), нормаль дивиться вбік — такі точки вирівняти до плоскої
    imn = karty[(mt.name, "нормалі")]
    pn = np.array(imn.pixels[:], np.float32).reshape(r, r, 4)
    nz = pn[..., 2] * 2 - 1
    kryvi = cv2.dilate((uvm & (nz < arg("--нормаль-поріг", float, 0.8))).astype(np.uint8), np.ones((9, 9), np.uint8))
    wn = cv2.GaussianBlur(kryvi.astype(np.float32), (0, 0), 3)[..., None]
    pn[..., :3] = pn[..., :3] * (1 - wn) + np.array([0.5, 0.5, 1.0], np.float32) * wn
    log("чистити шкіру: нормалей вирівняно %.1f %% розгортки тіла" % (100.0 * kryvi.sum() / max(1, uvm.sum())))
    imn.pixels.foreach_set(pn.ravel())
    imn.save()
if "--вирівняти-тон" in A:
    # орчиха (12.11.2026): скульпт голови з великого плану вийшов блідішим за тіло — обличчя
    # бежеве на оливковому тілі. Тон голови — множником по каналах до тону тіла на шиї:
    # медіана кольору граней голови під площиною шиї проти граней тіла одразу нижче.
    uvd = me.uv_layers.active.data
    zrazky = {0: [], 1: []}
    pxs = {}
    for mi_, mat in ((0, mt), (1, mh)):
        im = karty[(mat.name, "колір")]
        r = im.size[0]
        pxs[mi_] = np.array(im.pixels[:], np.float32).reshape(r, r, 4)
    for p_ in me.polygons:
        c = sum((me.vertices[i].co for i in p_.vertices), Vector()) / len(p_.vertices)
        d = (c - SH_P).dot(SH_N)
        if (c - HOL_C).length > 0.25:
            continue
        if not ((-0.03 < d < 0.0) if p_.material_index == 1 else (-0.08 < d < -0.03)):
            continue
        uv = sum((uvd[l].uv for l in p_.loop_indices), Vector((0, 0))) / len(p_.loop_indices)
        px = pxs[p_.material_index]
        r = px.shape[0]
        k_ = px[min(r - 1, int(uv.y * r)), min(r - 1, int(uv.x * r)), :3]
        if k_.max() > 0.08:
            zrazky[p_.material_index].append(k_)
    # обличчя вище площини шиї — свій множник (генератор дав обличчя ще блідішим за шию):
    # вага 0 на площині → 1 за 6 см над нею, растром по гранях і розмита
    import cv2
    px = pxs[1]
    r = px.shape[0]
    W = np.zeros((r, r), np.float32)
    oblychchia = []
    for p_ in me.polygons:
        if p_.material_index != 1:
            continue
        c = sum((me.vertices[i].co for i in p_.vertices), Vector()) / len(p_.vertices)
        # лише перед голови: потилиця й тім'я в скульпті вже в тон тіла, бліде саме обличчя
        w_ = max(0.0, min(1.0, (c - SH_P).dot(SH_N) / 0.06)) * max(0.0, min(1.0, (-0.02 - c.y) / 0.06))
        pts = np.array([[uvd[l].uv.x * r, uvd[l].uv.y * r] for l in p_.loop_indices], np.int32)
        cv2.fillPoly(W, [pts], float(w_))
        if w_ >= 1.0:
            uv = sum((uvd[l].uv for l in p_.loop_indices), Vector((0, 0))) / len(p_.loop_indices)
            k_ = px[min(r - 1, int(uv.y * r)), min(r - 1, int(uv.x * r)), :3]
            if k_.max() > 0.15:
                oblychchia.append(k_)
    if len(zrazky[0]) > 50 and len(zrazky[1]) > 50 and len(oblychchia) > 500:
        tilo_k = np.median(zrazky[0], 0)
        # обличчя — до тону всього тіла (шкіра без чорної білизни), а не лише смуги під шиєю:
        # смуга зеленіша за плечі й груди, і обличчя виходило м'ятним на оливковому тілі
        pt = pxs[0][::8, ::8, :3][maska_uv(0, pxs[0].shape[0])[::8, ::8]]
        pt = pt[pt.max(1) > 0.12]
        tilo_vse = np.median(pt, 0)
        m_shyi = np.clip(tilo_k / np.maximum(np.median(zrazky[1], 0), 1e-4), 0.5, 2.0)
        m_obl = np.clip(tilo_vse / np.maximum(np.median(oblychchia, 0), 1e-4), 0.4, 2.0)
        log("тон голови: множник шиї %s, обличчя %s (зразків тіла %d, шиї %d, обличчя %d)"
            % (m_shyi.round(3), m_obl.round(3), len(zrazky[0]), len(zrazky[1]), len(oblychchia)))
        W = cv2.GaussianBlur(cv2.dilate(W, np.ones((9, 9), np.uint8)), (0, 0), 6)[..., None]
        def shkira_maska(k3):
            """Шкіра голови без губ, носа й вух (червоніші за медіану шкіри) і без брів та очей (темні).
            Поріг — від медіани самої шкіри, а не «r < 1,3·g»: у світлої ельфійки вся шкіра рожева."""
            u = maska_uv(1, r) > 0
            ch = k3[..., 0] / np.maximum(k3.sum(2), 1e-4)
            sv = k3.max(2)
            zr = u & (sv > 0.2)
            return (zr & (ch < np.median(ch[zr]) + 0.045) & (sv > 0.45 * np.median(sv[zr]))).astype(np.float32)

        if "--тон-плавний" in A:
            # слово замовника 12.11: «тон обличчя та тіла не співпадають». Один множник на все
            # обличчя лишав бліду середину й зелені краї: генератор освітлив обличчя плямою.
            # Тож рівняється низькочастотний тон: розмитий колір голови → тон тіла (на шиї — тон
            # смуги тіла під шиєю, вище — всього тіла), дрібні деталі (зморшки, брови, губи) лишаються.
            # тон міряється лише по шкірі: губи (червоне) й брови, очі (темне) у розмиття не йдуть —
            # інакше довкола рота лишалась зеленкувата пляма, а губи блідли
            k3 = px[..., :3]
            mk = shkira_maska(k3)
            sg = r * arg("--тон-розмиття", float, 0.02)
            rozm = cv2.GaussianBlur(px[..., :3] * mk[..., None], (0, 0), sg) / np.maximum(
                cv2.GaussianBlur(mk, (0, 0), sg)[..., None], 1e-3)
            Wv = np.zeros((r, r), np.float32)
            for p_ in me.polygons:
                if p_.material_index != 1:
                    continue
                c = sum((me.vertices[i].co for i in p_.vertices), Vector()) / len(p_.vertices)
                pts = np.array([[uvd[l].uv.x * r, uvd[l].uv.y * r] for l in p_.loop_indices], np.int32)
                cv2.fillPoly(Wv, [pts], float(max(0.0, min(1.0, (c - SH_P).dot(SH_N) / 0.06))))
            Wv = cv2.GaussianBlur(cv2.dilate(Wv, np.ones((9, 9), np.uint8)), (0, 0), 6)[..., None]
            cil = tilo_k * (1 - Wv) + tilo_vse * Wv
            syla = arg("--тон-сила", float, 0.85)
            mn = np.clip(cil / np.maximum(rozm, 1e-3), 0.4, 2.5)
            px[..., :3] = np.clip(px[..., :3] * (1 + (mn - 1) * syla), 0, 1)
            # другий, дрібний прохід (--тон-плями): зеленкуваті й темні плями завбільшки з щоку,
            # які перший прохід не бере (орчиха-2: довкола рота; орчиха-3: на шиї й вилицях)
            sg2 = r * arg("--тон-плями", float, 0.0)
            if sg2:
                k3 = px[..., :3]
                mk = shkira_maska(k3)
                rozm = cv2.GaussianBlur(k3 * mk[..., None], (0, 0), sg2) / np.maximum(
                    cv2.GaussianBlur(mk, (0, 0), sg2)[..., None], 1e-3)
                mn = np.clip(cil / np.maximum(rozm, 1e-3), 0.6, 1.6)
                px[..., :3] = np.clip(k3 * (1 + (mn - 1) * 0.7), 0, 1)
            log("тон голови плавний: ціль шиї %s, тіла %s, сила %.2f" % (tilo_k.round(3), tilo_vse.round(3), syla))
        else:
            px[..., :3] = np.clip(px[..., :3] * (m_shyi * (1 - W) + m_obl * W), 0, 1)
        im.pixels.foreach_set(px.ravel())
        im.save()
    else:
        log("тон голови: замало зразків (%d, %d, %d) — без змін" % (len(zrazky[0]), len(zrazky[1]), len(oblychchia)))
VUKHA = arg("--вуха-гостріші", float, 0.0)
if VUKHA:
    # слово замовника 12.11.2026 (ельфійка): «вуха трохи більш гострі і трошки більш стирчачі».
    # Вухо — вершини голови, що виступають за ширину черепа над вухами; тягнеться до кінчика
    # (довше й тонше) і відводиться від голови. Після запікання: розгортка й карти не міняються.
    V = np.array([v.co[:] for v in me.vertices])
    hol_v = np.zeros(len(V), bool)
    for p_ in me.polygons:
        if p_.material_index == 1:
            hol_v[list(p_.vertices)] = True
    STYR = arg("--вуха-стирчать", float, 0.02)
    for zn in (-1, 1):
        bik = hol_v & (V[:, 0] * zn > 0.03)
        ik = np.nonzero(bik)[0][np.argmax(V[bik, 0] * zn)]
        kin = V[ik]
        x0 = (V[bik & (V[:, 2] > kin[2] + 0.025), 0] * zn).max()
        vu = bik & (V[:, 0] * zn > x0)
        kor_ = V[vu & (V[:, 0] * zn < x0 + 0.004)].mean(0)
        d = kin - kor_
        dl = np.linalg.norm(d)
        d /= dl
        P = V[vu]
        t = np.clip((P - kor_) @ d / dl, 0, 1)
        vis = kor_ + np.outer(t * dl, d)
        P2 = vis + (P - vis) * (1 - 0.35 * VUKHA / 0.3 * t)[:, None] + np.outer(t * t * VUKHA * dl, d)
        P2[:, 0] += zn * STYR * t
        P2[:, 1] += 0.4 * STYR * t          # і трохи назад — вухо розвертається від черепа
        P2[:, 2] += 0.6 * STYR * t          # і вгору: кінчик дивиться вгору-назад, а не вбік
        V[vu] = P2
        log("вуха: бік %+d, вершин %d, довжина %.3f → %.3f м" % (zn, int(vu.sum()), dl, dl * (1 + VUKHA)))
    zapysaty(o, V)
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
