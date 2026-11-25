# Річ, зроблену окремо (TRELLIS.2 з кадру речі без тіла), натягнути на тіло будь-якої раси
# (25.11.2026, П-289, проба). Одна річ на всі тіла — різні лише розмір і посадка.
#   1. масштаб за коробкою ділянки тіла (кіраса — тулуб від талії до шиї з плечима;
#      чобіт — гомілка зі стопою однієї ноги; друга нога — дзеркалом);
#   2. внутрішня стінка речі (нормаль до тіла, близько) і все, що всередині тіла (кришки
#      отворів шиї/рук), — геть: тіло під річчю ховається;
#   3. виштовхування назовні до відступу від шкіри полем зсувів, згладженим по сітці —
#      пластини не мнуться, тягнеться лише те, що лізло в тіло.
#   blender -b -P tools/blender/natiah_rich.py -- <тіло.glb> <річ.glb> <вихід.blend> \
#       --зона кіраса|чобіт [--відступ 0.008] [--кут 0] [--огляд огляд.png]
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

A = sys.argv[sys.argv.index("--") + 1:]
def arg(k, d):
    return type(d)(A[A.index(k) + 1]) if k in A else d
TILO, RICH, VYHID = [os.path.abspath(x) for x in A[:3]]
ZONA = arg("--зона", "кіраса")
VIDSTUP = arg("--відступ", 0.008)
KUT = arg("--кут", 0.0)
def log(*a):
    print("[натяг]", *a, flush=True)

if TILO.endswith(".blend"):        # тіло зі скелетом (5-скелет): ваги кісток і суглоби
    bpy.ops.wm.open_mainfile(filepath=TILO)
else:
    bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene

def imp(f):
    pered = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=f)
    return [o for o in bpy.data.objects if o not in pered]

# тіло: найбільша сітка (з іменем «Тіло», якщо є); координати світу в позі спокою
nove = list(bpy.data.objects) if TILO.endswith(".blend") else imp(TILO)
sitky = [o for o in nove if o.type == "MESH"]
tilo = next((o for o in sitky if o.name.startswith("Тіло")), max(sitky, key=lambda o: len(o.data.vertices)))
for o in sitky:
    if o is not tilo:
        o.hide_render = True
        o.hide_viewport = True
# --поза-речі: тіло зі скелетом спершу ставиться в позу кадру речі (руки опущені, трохи
# назовні) — річ сідає так само, як на тіло з опущеними руками; потім ваги кісток із тіла
# і зворотний скінінг повертають річ у позу спокою скелета (А-поза)
POZA = "--поза-речі" in A
KUT_RUKY = arg("--кут-руки", 12.0)
ARM = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
if POZA and ARM:
    from mathutils import Matrix
    for bik in ("_r", "_l"):
        pb = ARM.pose.bones["upperarm" + bik]
        aw = ARM.matrix_world
        h, t = aw @ pb.head, aw @ pb.tail
        zn = 1.0 if h.x > 0 else -1.0
        tsil = Vector((zn * math.sin(math.radians(KUT_RUKY)), 0.0, -math.cos(math.radians(KUT_RUKY))))
        q = (t - h).normalized().rotation_difference(tsil)
        Rw = Matrix.Translation(h) @ q.to_matrix().to_4x4() @ Matrix.Translation(-h)
        pb.matrix = aw.inverted() @ Rw @ aw @ pb.matrix
        bpy.context.view_layer.update()
        log("поза речі: рука%s → %.0f° від вертикалі (повернуто на %.1f°)" % (bik, KUT_RUKY, math.degrees(q.angle)))
dg = bpy.context.evaluated_depsgraph_get()
te = tilo.evaluated_get(dg)
tm = te.to_mesh()
VB = np.array([tilo.matrix_world @ v.co for v in tm.vertices])
FB = [p.vertices[:] for p in tm.polygons]
te.to_mesh_clear()
bvh = BVHTree.FromPolygons([Vector(v) for v in VB], FB)
z0, z1 = VB[:, 2].min(), VB[:, 2].max()
H = z1 - z0
CX = float(np.median(VB[:, 0]))
_t = Vector((CX, VB[:, 1].min() - 0.5, z0 + 0.7 * H))
_l, _n, _, _ = bvh.find_nearest(_t)
ZNAK_T = 1.0 if (_t - _l).dot(_n) > 0 else -1.0     # нормалі тіла назовні чи всередину
log("нормалі тіла %s" % ("назовні" if ZNAK_T > 0 else "всередину — обертаю знак"))
log("тіло %s: %d вершин, зріст %.3f" % (tilo.name, len(VB), H))
# головна кістка вершини → маска рук; суглоби → висоти (частки зросту)
RUKA = None
HOLOVNA = None
SUHL = {}
SUHL_X = {}
SUHL3 = {}
KINETS = {}
if tilo.vertex_groups:
    nazvy = [g.name for g in tilo.vertex_groups]
    W = np.zeros((len(tilo.data.vertices), len(nazvy)))
    for v in tilo.data.vertices:
        for g in v.groups:
            W[v.index, g.group] = g.weight
    holovna = np.array(nazvy)[W.argmax(1)]
    RUKA = np.array([any(k in h for k in ("upperarm", "lowerarm", "hand")) for h in holovna])
    HOLOVNA = holovna
    arm = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
    if arm:
        for b in arm.pose.bones:          # у поточній позі (без --поза-речі — це спокій)
            SUHL[b.name] = ((arm.matrix_world @ b.head).z - z0) / H
            SUHL_X[b.name] = (arm.matrix_world @ b.head).x
            SUHL3[b.name] = np.array((arm.matrix_world @ b.head)[:])
            KINETS[b.name] = np.array((arm.matrix_world @ b.tail)[:])
    WB, NAZVY = W, nazvy
    log("ваги: рук %d вершин; суглоби %s" % (RUKA.sum(), {k: round(SUHL[k], 3) for k in
        ("thigh_r", "spine_01", "spine_03", "neck_01") if k in SUHL}))

def tulub(lo, hi):
    """Точки тулуба між частками зросту lo..hi: у кожному шарі — центральний шматок по X
    (руки в А-позі окремо від тулуба нижче пахви)."""
    m = (VB[:, 2] > z0 + lo * H) & (VB[:, 2] < z0 + hi * H)
    if RUKA is not None:
        return VB[m & ~RUKA]
    P = VB[m]
    keep = np.zeros(len(P), bool)
    sh = np.floor((P[:, 2] - z0) / 0.01).astype(int)
    for s in np.unique(sh):
        j = np.nonzero(sh == s)[0]
        x = P[j, 0]
        o = np.argsort(x)
        xs = x[o]
        rozryv = np.nonzero(np.diff(xs) > 0.015)[0]
        mezhi = np.concatenate([[0], rozryv + 1, [len(xs)]])
        for a, b in zip(mezhi[:-1], mezhi[1:]):
            if xs[a] <= CX <= xs[b - 1]:
                keep[j[o[a:b]]] = True
    return P[keep]

def noha(lo, hi, znak):
    m = (VB[:, 2] > z0 + lo * H) & (VB[:, 2] < z0 + hi * H) & ((VB[:, 0] - CX) * znak > 0.01)
    return VB[m]

def zavantazhyty_rich(dzerkalo=False):
    nove = imp(RICH)
    ms = [o for o in nove if o.type == "MESH"]
    for o in bpy.context.scene.objects:
        o.select_set(o in ms)
    bpy.context.view_layer.objects.active = ms[0]
    if len(ms) > 1:
        bpy.ops.object.join()
    r = bpy.context.view_layer.objects.active
    r.parent = None
    r.rotation_euler[2] += math.radians(KUT)
    if dzerkalo:
        r.scale[0] *= -1
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # glTF ріже вершини по швах розгортки — зшити, інакше сітка «розсипана» на острівці
    bm = bmesh.new(); bm.from_mesh(r.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    if dzerkalo:
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
    bm.to_mesh(r.data); bm.free(); r.data.update()
    return r

def vpysaty(r, P, zapas_x, zapas_y, z_lo, z_hi):
    """Коробку речі — в коробку точок тіла P (із запасом по X і Y), по Z — від z_lo до z_hi."""
    V = np.array([v.co[:] for v in r.data.vertices])
    lo, hi = V.min(0), V.max(0)
    plo, phi = P.min(0), P.max(0)
    ciel_lo = np.array([plo[0] - zapas_x, plo[1] - zapas_y, z_lo])
    ciel_hi = np.array([phi[0] + zapas_x, phi[1] + zapas_y, z_hi])
    s = (ciel_hi - ciel_lo) / np.maximum(hi - lo, 1e-6)
    V2 = ciel_lo + (V - lo) * s
    r.data.vertices.foreach_set("co", V2.ravel())
    r.data.update()
    log("масштаб x%.3f y%.3f z%.3f" % tuple(s))

def vpysaty_tulub(r, nyz, verh, m=0.022):
    """Висота — від nyz до verh зросту; ширина X — за талією (там кіраса без наплічників),
    глибина Y і зсув по Y — за грудьми (руки збоку, у шар грудей не потрапляють)."""
    V = np.array([v.co[:] for v in r.data.vertices])
    lo, hi = V.min(0), V.max(0)
    f = lambda zb: (zb - nyz) / (verh - nyz)          # частка зросту → частка висоти речі
    def shar_rechi(zb, w=0.03):
        t = lo[2] + f(zb) * (hi[2] - lo[2])
        return V[np.abs(V[:, 2] - t) < w * (hi[2] - lo[2])]
    def shar_tila(zb):
        return tulub(zb - 0.01, zb + 0.01)
    ZT, ZG = SUHL.get("spine_01", 0.60) + 0.02, SUHL.get("spine_03", 0.70) + 0.02
    rt, tt = shar_rechi(ZT), shar_tila(ZT)
    rg, tg = shar_rechi(ZG), shar_tila(ZG)
    w_r = np.percentile(rt[:, 0], 98) - np.percentile(rt[:, 0], 2)
    w_t = tt[:, 0].max() - tt[:, 0].min()
    d_r = np.percentile(rg[:, 1], 99) - np.percentile(rg[:, 1], 1)
    d_t = tg[:, 1].max() - tg[:, 1].min()
    sx = (w_t + 2 * m) / w_r
    sy = (d_t + 2 * m) / d_r
    sz = (verh - nyz) * H / (hi[2] - lo[2])
    cy_r = (np.percentile(rg[:, 1], 99) + np.percentile(rg[:, 1], 1)) / 2
    cy_t = (tg[:, 1].max() + tg[:, 1].min()) / 2
    cx_r = (np.percentile(rt[:, 0], 98) + np.percentile(rt[:, 0], 2)) / 2
    V2 = np.stack([CX + (V[:, 0] - cx_r) * sx, cy_t + (V[:, 1] - cy_r) * sy,
                   z0 + nyz * H + (V[:, 2] - lo[2]) * sz], 1)
    r.data.vertices.foreach_set("co", V2.ravel())
    r.data.update()
    log("масштаб x%.3f y%.3f z%.3f (талія тіла %.3f, груди %.3f)" % (sx, sy, sz, w_t, d_t))

def rozdut(r, m=0.006, kvantyl=80.0):
    """Без виштовхування поверхні (воно мне наплічники й край під пахвою): річ роздувається
    цілою в X і Y навколо осі тулуба. Для кожної вершини тулуба (не рук) між стегном і шиєю —
    горизонтальний промінь ззовні до осі: перше влучання в річ — її зовнішня поверхня;
    потрібне роздуття = (радіус шкіри + m) / радіус поверхні. Береться квантиль — решту
    (м'язи, що випинають) ховає `під_одяг`. Нормалі сітки TRELLIS ненадійні — тут не потрібні."""
    me = r.data
    V = np.array([v.co[:] for v in me.vertices])
    rb = BVHTree.FromPolygons([Vector(v) for v in V], [p.vertices[:] for p in me.polygons])
    cy = float(np.median(V[:, 1]))
    za, zb = z0 + (SUHL.get("thigh_r", 0.52) + 0.06) * H, z0 + (SUHL.get("neck_01", 0.85) - 0.04) * H
    m_ = (VB[:, 2] > za) & (VB[:, 2] < zb)
    if RUKA is not None:
        m_ &= ~RUKA
    idx = np.nonzero(m_)[0][::3]
    potr = []
    for i in idx:
        b_ = VB[i]
        d2 = np.array([b_[0] - CX, b_[1] - cy])
        rb_ = np.linalg.norm(d2)
        if rb_ < 1e-4:
            continue
        u = d2 / rb_
        o = Vector((CX + u[0] * 1.5, cy + u[1] * 1.5, b_[2]))
        hit = rb.ray_cast(o, Vector((-u[0], -u[1], 0.0)), 1.5)[0]
        if hit is None:
            continue
        ri = np.hypot(hit.x - CX, hit.y - cy)
        potr.append((rb_ + m) / max(ri, 1e-4))
    potr = np.array(potr)
    k = float(np.clip(np.percentile(potr, kvantyl), 1.0, 1.1))
    log("роздуття: потрібно (медіана %.3f, %d-й квантиль %.3f) → %.3f; пробито при ньому %.1f %%"
        % (np.median(potr), kvantyl, np.percentile(potr, kvantyl), k, 100.0 * (potr > k).mean()))
    V[:, 0] = CX + (V[:, 0] - CX) * k
    V[:, 1] = cy + (V[:, 1] - cy) * k
    me.vertices.foreach_set("co", V.ravel()); me.update()

V0_NAPL, SH_NAPL = arg("--наплічник-від", 0.55), arg("--наплічник-перехід", 0.2)

OSTROVY = None      # острівець сітки кожної вершини (TRELLIS ліпить пластини наплічника окремо)

def ostrovy(r):
    """Номер зв'язного острівця для кожної вершини; 0 — найбільший (корпус кіраси)."""
    me = r.data
    E = np.array([e.vertices[:] for e in me.edges])
    n = len(me.vertices)
    bat = np.arange(n)
    def kor(i):
        while bat[i] != i:
            bat[i] = bat[bat[i]]
            i = bat[i]
        return i
    for a, b in E:
        ra, rb_ = kor(a), kor(b)
        if ra != rb_:
            bat[ra] = rb_
    k = np.array([kor(i) for i in range(n)])
    _, inv, cnt = np.unique(k, return_inverse=True, return_counts=True)
    poriadok = np.argsort(-cnt)
    nomer = np.empty_like(poriadok); nomer[poriadok] = np.arange(len(poriadok))
    return nomer[inv], cnt[poriadok]

def vaha_naplichnyka(V, bik):
    """0 — кіраса, 1 — наплічник цього боку. Корпус кіраси (найбільший острівець) — завжди 0:
    стінка під пахвою не повертається з рукою (інакше вона вивертається назовні й пахва
    «ламається»). Пластини наплічника — окремі острівці збоку над пахвою: вага плавно від
    коміра до краю плеча; дрібні острівці (заклепки, ремінці) — як найближча пластина."""
    J = SUHL3["upperarm" + bik]
    jx = J[0] - CX
    zn = np.sign(jx)
    t = np.clip(((V[:, 0] - CX) * zn - V0_NAPL * abs(jx)) / (SH_NAPL * abs(jx)), 0, 1)
    t *= np.clip((V[:, 2] - (J[2] - 0.12 * H)) / (0.05 * H), 0, 1)
    t = t * t * (3 - 2 * t)
    if OSTROVY is None:
        return t
    nom, cnt = OSTROVY
    velyki = cnt >= 0.01 * cnt.sum()
    w = np.zeros(len(V))
    for i in range(1, len(cnt)):
        q = nom == i
        if not velyki[i]:
            continue
        c = V[q].mean(0)
        if (c[0] - CX) * zn > V0_NAPL * abs(jx) and c[2] > J[2] - 0.12 * H:
            w[q] = t[q]
    dribni = ~velyki[nom] & (nom > 0)
    if dribni.any():
        from mathutils.kdtree import KDTree
        vel = np.nonzero(velyki[nom])[0]
        kd = KDTree(len(vel))
        for j, i in enumerate(vel):
            kd.insert(Vector(V[i]), j)
        kd.balance()
        for i in np.nonzero(dribni)[0]:
            w[i] = w[vel[kd.find(Vector(V[i]))[1]]]
    return w

def pole_rozduttia(r, m=0.008, kutiv=48, krok=0.02):
    """Роздуття тулуба кіраси полем: сітка «кут навколо осі × висота»; у клітинці —
    потрібне (радіус шкіри + m) / радіус зовнішньої поверхні речі (промінь ззовні до осі).
    Поле розширене на сусідні клітинки й згладжене — пластина роздувається плавно, без
    зморшок; наплічники (вага > 0) не чіпаються. Лише ≥ 1: де річ і так ширша — без змін."""
    me = r.data
    V = np.array([v.co[:] for v in me.vertices])
    rb = BVHTree.FromPolygons([Vector(v) for v in V], [p.vertices[:] for p in me.polygons])
    cy = float(np.median(V[:, 1]))
    za, zb = z0 + (SUHL.get("thigh_r", 0.52) + 0.03) * H, z0 + (SUHL.get("neck_01", 0.85) - 0.01) * H
    zh = np.arange(za, zb + krok, krok)
    G = np.ones((len(zh), kutiv))
    m_ = (VB[:, 2] > za) & (VB[:, 2] < zb)
    if RUKA is not None:
        m_ &= ~RUKA
    for i in np.nonzero(m_)[0]:
        b_ = VB[i]
        d2 = np.array([b_[0] - CX, b_[1] - cy]); rr = np.linalg.norm(d2)
        if rr < 1e-3:
            continue
        u = d2 / rr
        hit = rb.ray_cast(Vector((CX + u[0] * 1.5, cy + u[1] * 1.5, b_[2])), Vector((-u[0], -u[1], 0.0)), 1.5)[0]
        if hit is None:
            continue
        ri = np.hypot(hit.x - CX, hit.y - cy)
        th = int(((np.arctan2(u[1], u[0]) + np.pi) / (2 * np.pi) * kutiv)) % kutiv
        zi = int(np.clip(round((b_[2] - za) / krok), 0, len(zh) - 1))
        G[zi, th] = max(G[zi, th], (rr + m) / max(ri, 1e-3))
    G = np.clip(G, 1.0, 1.35)
    for _ in range(2):                         # розширити (макс по сусідах)
        G = np.maximum.reduce([G, np.roll(G, 1, 1), np.roll(G, -1, 1),
                               np.vstack([G[:1], G[:-1]]), np.vstack([G[1:], G[-1:]])])
    for _ in range(4):                         # згладити
        G = (G * 4 + np.roll(G, 1, 1) + np.roll(G, -1, 1) + np.vstack([G[:1], G[:-1]]) + np.vstack([G[1:], G[-1:]])) / 8
    th_v = (np.arctan2(V[:, 1] - cy, V[:, 0] - CX) + np.pi) / (2 * np.pi) * kutiv
    zf = (V[:, 2] - za) / krok
    t0 = np.floor(th_v).astype(int) % kutiv; t1 = (t0 + 1) % kutiv; ft = th_v - np.floor(th_v)
    z0i = np.clip(np.floor(zf).astype(int), 0, len(zh) - 1); z1i = np.clip(z0i + 1, 0, len(zh) - 1)
    fz = np.clip(zf - np.floor(zf), 0, 1)
    k = ((G[z0i, t0] * (1 - ft) + G[z0i, t1] * ft) * (1 - fz) + (G[z1i, t0] * (1 - ft) + G[z1i, t1] * ft) * fz)
    poza = np.clip(np.maximum(za - V[:, 2], V[:, 2] - zb) / 0.04, 0, 1)    # за смугою — плавно до 1
    k = 1 + (k - 1) * (1 - poza)
    wp = np.zeros(len(V))
    if "upperarm_r" in SUHL3:
        wp = np.maximum(vaha_naplichnyka(V, "_r"), vaha_naplichnyka(V, "_l"))
    k = 1 + (k - 1) * (1 - wp)
    V[:, 0] = CX + (V[:, 0] - CX) * k
    V[:, 1] = cy + (V[:, 1] - cy) * k
    me.vertices.foreach_set("co", V.ravel()); me.update()
    log("поле роздуття: клітинок %dx%d, найбільше %.3f, середнє %.3f" % (len(zh), kutiv, G.max(), G.mean()))

CHASTKA_KUTA = arg("--частка-кута", 0.8)

def naplichnyky(r, m=0.010, kvantyl=95.0):
    """Наплічник кожного боку — окремо: роздути навколо плечового суглоба (голова
    upperarm), доки дельта й трапеція майже не пробивають. Вага спадає до тулуба плавно,
    щоб пластина не відірвалась від кіраси. Решту ховає `під_одяг`."""
    if "upperarm_r" not in SUHL3:
        return
    me = r.data
    V = np.array([v.co[:] for v in me.vertices])
    for bik in ("_r", "_l"):
        J = SUHL3["upperarm" + bik]
        w = vaha_naplichnyka(V, bik)
        # наплічник іде за рукою: у кадрі речі рука опущена (трохи назовні), у тілі — як
        # кістка плеча (А-поза ~45°). Поворот навколо суглоба на частку кута; вага плавна —
        # біля коміра пластина лишається на кірасі
        zn = np.sign(J[0] - CX)
        ref = np.array([zn * np.sin(np.radians(KUT_RUKY)), 0.0, -np.cos(np.radians(KUT_RUKY))])
        kist_d = KINETS["upperarm" + bik] - J
        kist_d /= np.linalg.norm(kist_d)
        os_ = np.cross(ref, kist_d)
        sn = np.linalg.norm(os_)
        if sn > 1e-4:
            os_ /= sn
            kut = np.arctan2(sn, np.dot(ref, kist_d)) * CHASTKA_KUTA
            K_ = np.array([[0, -os_[2], os_[1]], [os_[2], 0, -os_[0]], [-os_[1], os_[0], 0]])
            for q in np.nonzero(w > 0.01)[0]:
                a_ = kut * w[q]
                R_ = np.eye(3) + np.sin(a_) * K_ + (1 - np.cos(a_)) * K_ @ K_
                V[q] = J + R_ @ (V[q] - J)
            log("наплічник%s: поворот за рукою %.1f° (кут руки %.1f°)" % (bik, np.degrees(kut), np.degrees(kut / CHASTKA_KUTA)))
        rb = BVHTree.FromPolygons([Vector(v) for v in V], [p.vertices[:] for p in me.polygons])
        hol = np.array([any(k in h for k in ("upperarm" + bik, "clavicle" + bik)) for h in HOLOVNA])
        # верх дельти й трапеція + плече під наплічником (до 12 см від суглоба: наплічник
        # уже повернуто за рукою, тож плече під ним — частина того, що він має накрити)
        sel = np.nonzero(hol & ((VB[:, 2] > J[2] - 0.02 * H) | (np.linalg.norm(VB - J, axis=1) < 0.12)))[0][::2]
        potr = []
        for i in sel:
            d = VB[i] - J
            rr = np.linalg.norm(d)
            if rr < 0.02:
                continue
            u = d / rr
            hit = rb.ray_cast(Vector(J + u * 1.0), Vector(-u), 1.0)[0]
            if hit is None:
                continue
            potr.append((rr + m) / max(np.linalg.norm(np.array(hit[:]) - J), 1e-4))
        if not potr:
            continue
        potr = np.array(potr)
        k = float(np.clip(np.percentile(potr, kvantyl), 1.0, 1.35))
        V = V + (w * (k - 1))[:, None] * (V - J)
        log("наплічник%s: роздуття %.3f (медіана потреби %.3f), вершин під вагою %d"
            % (bik, k, np.median(potr), int((w > 0.01).sum())))
    me.vertices.foreach_set("co", V.ravel()); me.update()

def pidniaty_plechi(r, m=0.012, krok=0.02, naibilshe=0.07):
    """Трапеція й верх плеча, що стирчать над кірасою (орк: шия низько, трапеція горбом),
    — верх кіраси підняти полем «x × y» над плечима: у клітинці — на скільки шкіра + m вища
    за верхню поверхню речі (промінь згори вниз). Поле розширене й згладжене, донизу
    згасає до нуля на рівні пахви — пластини піднімаються цілими, без горбів."""
    if HOLOVNA is None or "upperarm_r" not in SUHL3:
        return
    me = r.data
    V = np.array([v.co[:] for v in me.vertices])
    rb = BVHTree.FromPolygons([Vector(v) for v in V], [p.vertices[:] for p in me.polygons])
    Jz = (SUHL3["upperarm_r"][2] + SUHL3["upperarm_l"][2]) / 2
    shyia = HOLOVNA == "neck_01"
    zs = z0 + SUHL["neck_01"] * H + 0.03 * H
    q = VB[shyia & (np.abs(VB[:, 2] - zs) < 0.01)]
    r_shyi = np.percentile(np.abs(q[:, 0] - CX), 95) if len(q) > 10 else 0.06
    plechi = np.isin(HOLOVNA, ["clavicle_r", "clavicle_l", "spine_03", "neck_01", "upperarm_r", "upperarm_l"])
    sel = np.nonzero(plechi & (VB[:, 2] > Jz - 0.03 * H) & (np.abs(VB[:, 0] - CX) > r_shyi + 0.01))[0]
    x0, x1 = V[:, 0].min() - krok, V[:, 0].max() + krok
    y0, y1 = V[:, 1].min() - krok, V[:, 1].max() + krok
    nx, ny = int((x1 - x0) / krok) + 2, int((y1 - y0) / krok) + 2
    G = np.zeros((nx, ny))
    for i in sel:
        b_ = VB[i]
        hit = rb.ray_cast(Vector((b_[0], b_[1], b_[2] + 0.5)), Vector((0, 0, -1)), 0.5 + 0.08)[0]
        if hit is None:
            continue
        potr = b_[2] + m - hit.z
        if potr > 0:
            ix, iy = int((b_[0] - x0) / krok), int((b_[1] - y0) / krok)
            G[ix, iy] = max(G[ix, iy], potr)
    vymir = G.max()
    G = np.minimum(G, naibilshe)
    # над шиєю точок немає — місток між боками на кожному ряду Y (комір піднімається рівно,
    # без «рогів» над трапецією)
    xc = x0 + (np.arange(nx) + 0.5) * krok
    sh = np.abs(xc - CX) < r_shyi + 0.03
    li, pr = np.nonzero((xc < CX) & ~sh)[0], np.nonzero((xc > CX) & ~sh)[0]
    if len(li) and len(pr):
        for j in range(ny):
            a = G[li[-6:], j].max(); b = G[pr[:6], j].max()
            G[sh, j] = np.maximum(G[sh, j], min(a, b))
    for _ in range(2):
        G = np.maximum.reduce([G, np.roll(G, 1, 0), np.roll(G, -1, 0), np.roll(G, 1, 1), np.roll(G, -1, 1)])
    for _ in range(6):
        G = (G * 4 + np.roll(G, 1, 0) + np.roll(G, -1, 0) + np.roll(G, 1, 1) + np.roll(G, -1, 1)) / 8
    fx, fy = (V[:, 0] - x0) / krok, (V[:, 1] - y0) / krok
    i0 = np.clip(np.floor(fx).astype(int), 0, nx - 2); j0 = np.clip(np.floor(fy).astype(int), 0, ny - 2)
    ax, ay = np.clip(fx - i0, 0, 1), np.clip(fy - j0, 0, 1)
    dz = (G[i0, j0] * (1 - ax) + G[i0 + 1, j0] * ax) * (1 - ay) + (G[i0, j0 + 1] * (1 - ax) + G[i0 + 1, j0 + 1] * ax) * ay
    t = np.clip((V[:, 2] - (Jz - 0.10 * H)) / (0.08 * H), 0, 1)
    V[:, 2] += dz * t * t * (3 - 2 * t)
    me.vertices.foreach_set("co", V.ravel()); me.update()
    log("плечі: шкіра над кірасою до %.1f мм (точок %d), підйом поля до %.1f мм; шия r=%.3f"
        % (vymir * 1000, len(sel), dz.max() * 1000, r_shyi))

def zalataty(r, z_do_svit):
    """Дірки сітки (TRELLIS лишає отвір на підйомі стопи) — залатати; верхній отвір халяви
    (найбільший край угорі) лишається. Межа — у координатах речі до вписування: латаємо всі
    отвори, крім найвищого."""
    bm = bmesh.new(); bm.from_mesh(r.data)
    kraj = [e for e in bm.edges if e.is_boundary]
    # зв'язні петлі країв
    bachene, petli = set(), []
    for e in kraj:
        if e.index in bachene:
            continue
        st, pl = [e], []
        bachene.add(e.index)
        while st:
            g = st.pop(); pl.append(g)
            for v in g.verts:
                for e2 in v.link_edges:
                    if e2.is_boundary and e2.index not in bachene:
                        bachene.add(e2.index); st.append(e2)
        petli.append(pl)
    if len(petli) > 1:
        vys = [np.mean([v.co.z for e in pl for v in e.verts]) for pl in petli]
        verkh = int(np.argmax(vys))
        lat = [e for i, pl in enumerate(petli) if i != verkh for e in pl]
        res = bmesh.ops.holes_fill(bm, edges=lat, sides=0)
        log("латки: петель країв %d, залатано %d граней (верхній отвір лишився)" % (len(petli), len(res["faces"])))
    bm.to_mesh(r.data); bm.free(); r.data.update()

def vpysaty_nohu(r, znak, m=0.010):
    """Чобіт уздовж осі ноги: на кожній висоті вище кісточки центр речі — у центр гомілки
    (ноги в А-позі навскіс); масштаб у X і Y — один на всю халяву (наколінник не плющиться);
    стопа — від п'яти до носка тіла з запасом."""
    bik = "_r" if (SUHL_X.get("thigh_r", -1) - CX) * znak > 0 else "_l"
    V = np.array([v.co[:] for v in r.data.vertices])
    lo, hi = V.min(0), V.max(0)
    koliano = z0 + SUHL["calf" + bik] * H
    kist = z0 + SUHL["foot" + bik] * H
    verh = koliano + 0.035 * H
    noh = np.isin(HOLOVNA, ["thigh" + bik, "calf" + bik])
    stopa = np.isin(HOLOVNA, ["foot" + bik, "ball" + bik])
    PN, PS = VB[noh], VB[stopa]
    # підйом стопи: найвища висота, де глибина (Y) ще > 1,5 мінімальної глибини гомілки
    def pidiom(P, z_lo, z_hi):
        zz = np.linspace(z_lo, z_lo + 0.45 * (z_hi - z_lo), 60)
        dl = []
        for z in zz:
            q = P[np.abs(P[:, 2] - z) < 0.006 * (z_hi - z_lo) / 0.5]
            dl.append(np.percentile(q[:, 1], 97) - np.percentile(q[:, 1], 3) if len(q) > 10 else np.nan)
        dl = np.array(dl)
        dmin = np.nanmin(dl[len(dl) // 3:])
        vysoki = np.nonzero(dl > 1.5 * dmin)[0]
        return zz[vysoki.max()] if len(vysoki) else z_lo + 0.12 * (z_hi - z_lo)
    # висота — один масштаб (пропорції речі: стопа не розтягується до підйому тіла)
    sz = (verh - z0 + 0.003) / (hi[2] - lo[2])
    Z = z0 - 0.003 + (V[:, 2] - lo[2]) * sz
    shary = np.arange(kist, verh + 0.011, 0.01)
    def tsentry(P, Zp):
        c = np.full((len(shary), 4), np.nan)
        for i, z in enumerate(shary):
            q = P[np.abs(Zp - z) < 0.008]
            if len(q) > 10:
                a0, a1 = np.percentile(q[:, 0], [3, 97]); b0, b1 = np.percentile(q[:, 1], [3, 97])
                c[i] = [(a0 + a1) / 2, (b0 + b1) / 2, a1 - a0, b1 - b0]
        for k in range(4):                    # дірки — найближчим
            ok = ~np.isnan(c[:, k])
            c[:, k] = np.interp(shary, shary[ok], c[ok, k])
        return c
    cb, ci = tsentry(PN, PN[:, 2]), tsentry(V, Z)
    hal = (shary > kist + 0.06) & (shary < koliano - 0.05)
    # переріз халяви — одним масштабом за ширшою з потреб, не далі ±30 % від висотного:
    # що лишилось у металі (литка, коліно), ховає `під_одяг`
    s_w = max(np.median((cb[hal, 2] + 2 * m) / ci[hal, 2]), np.median((cb[hal, 3] + 2 * m) / ci[hal, 3]))
    sx = sy = float(np.clip(s_w, 0.9 * sz, 1.3 * sz))
    zi = np.clip(Z, shary[0], shary[-1])
    X = np.interp(zi, shary, cb[:, 0]) + (V[:, 0] - np.interp(zi, shary, ci[:, 0])) * sx
    Yh = np.interp(zi, shary, cb[:, 1]) + (V[:, 1] - np.interp(zi, shary, ci[:, 1])) * sy
    # стопа: лише якщо стопа тіла довша — Y речі нижче кісточки дотягти до носка й п'яти
    nyz = Z < kist
    iy0, iy1 = Yh[nyz].min(), Yh[nyz].max()
    by0, by1 = min(PS[:, 1].min() - 1.5 * m, iy0), max(PS[:, 1].max() + m, iy1)
    Yf = by0 + (Yh - iy0) * (by1 - by0) / (iy1 - iy0)
    w = np.clip((kist + 0.03 - Z) / 0.06, 0, 1)    # плавний перехід халява → стопа
    w = w * w * (3 - 2 * w)
    Y = Yh * (1 - w) + Yf * w
    # стопа вшир: якщо стопа тіла ширша за носок речі — розширити низ навколо осі стопи
    ix0, ix1 = np.percentile(X[nyz], [2, 98])
    bx0, bx1 = PS[:, 0].min() - m, PS[:, 0].max() + m
    kx = 1.0          # стопа тіла під чоботом схована — носок не розширюємо
    cxf = (bx0 + bx1) / 2
    X = X + w * ((cxf + (X - (ix0 + ix1) / 2) * kx) - X)
    log("чобіт: стопа вшир x%.2f" % kx)
    # поле роздуття халяви навколо осі ноги (кут × висота), як у кіраси: литка й коліно
    # більші, ніж у речі, — метал розширюється плавно рівно там, де треба
    axx_f = lambda z: np.interp(np.clip(z, shary[0], shary[-1]), shary, cb[:, 0])
    axy_f = lambda z: np.interp(np.clip(z, shary[0], shary[-1]), shary, cb[:, 1])
    FI = [p.vertices[:] for p in r.data.polygons]
    rb = BVHTree.FromPolygons([Vector(v) for v in np.stack([X, Y, Z], 1)], FI)
    kutiv, krok = 36, 0.02
    za, zb = kist + 0.02, verh - 0.01
    zh = np.arange(za, zb + krok, krok)
    G = np.ones((len(zh), kutiv))
    for b_ in PN[(PN[:, 2] > za) & (PN[:, 2] < zb)]:
        cx_, cy_ = axx_f(b_[2]), axy_f(b_[2])
        d2 = np.array([b_[0] - cx_, b_[1] - cy_]); rr = np.linalg.norm(d2)
        if rr < 1e-3:
            continue
        u = d2 / rr
        hit = rb.ray_cast(Vector((cx_ + u[0] * 0.6, cy_ + u[1] * 0.6, b_[2])), Vector((-u[0], -u[1], 0.0)), 0.6)[0]
        if hit is None:
            continue
        ri = np.hypot(hit.x - cx_, hit.y - cy_)
        th = int((np.arctan2(u[1], u[0]) + np.pi) / (2 * np.pi) * kutiv) % kutiv
        zi_ = int(np.clip(round((b_[2] - za) / krok), 0, len(zh) - 1))
        G[zi_, th] = max(G[zi_, th], (rr + 0.006) / max(ri, 1e-3))
    G = np.clip(G, 1.0, 1.6)
    for _ in range(3):
        G = np.maximum.reduce([G, np.roll(G, 1, 1), np.roll(G, -1, 1), np.vstack([G[:1], G[:-1]]), np.vstack([G[1:], G[-1:]])])
    for _ in range(10):                      # халява гладка, без горбів по м'язах
        G = (G * 4 + np.roll(G, 1, 1) + np.roll(G, -1, 1) + np.vstack([G[:1], G[:-1]]) + np.vstack([G[1:], G[-1:]])) / 8
    AX, AY = axx_f(Z), axy_f(Z)
    th_v = (np.arctan2(Y - AY, X - AX) + np.pi) / (2 * np.pi) * kutiv
    zf = (Z - za) / krok
    t0 = np.floor(th_v).astype(int) % kutiv; t1 = (t0 + 1) % kutiv; ft = th_v - np.floor(th_v)
    z0i = np.clip(np.floor(zf).astype(int), 0, len(zh) - 1); z1i = np.clip(z0i + 1, 0, len(zh) - 1)
    fz = np.clip(zf - np.floor(zf), 0, 1)
    kk = ((G[z0i, t0] * (1 - ft) + G[z0i, t1] * ft) * (1 - fz) + (G[z1i, t0] * (1 - ft) + G[z1i, t1] * ft) * fz)
    poza = np.clip(np.maximum(za - Z, Z - zb) / 0.03, 0, 1)
    kk = 1 + (kk - 1) * (1 - poza)
    X = AX + (X - AX) * kk
    Y = AY + (Y - AY) * kk
    log("чобіт: поле роздуття найбільше %.3f, середнє %.3f" % (G.max(), G.mean()))
    log("чобіт: висота x%.3f, переріз x%.3f (за шириною треба %.3f)" % (sz, sx, s_w))
    r.data.vertices.foreach_set("co", np.stack([X, Y, Z], 1).ravel()); r.data.update()
    log("чобіт%s: масштаб халяви x%.3f y%.3f, стопа %.3f м (тіла %.3f)"
        % (bik, sx, sy, by1 - by0, PS[:, 1].max() - PS[:, 1].min()))

def nablyzh(V):
    d = np.zeros(len(V)); n = np.zeros((len(V), 3)); q = np.zeros((len(V), 3))
    for i, p in enumerate(V):
        loc, nor, _, dist = bvh.find_nearest(Vector(p))
        nor = nor * ZNAK_T
        q[i] = loc; n[i] = nor
        d[i] = np.dot(p - np.array(loc), np.array(nor))      # знак: + назовні
    return d, n, q

def chystka(r):
    """Геть: грані всередині тіла і внутрішню стінку (нормаль грані — до тіла, ближче 3 см)."""
    me = r.data
    C = np.array([p.center[:] for p in me.polygons])
    N = np.array([p.normal[:] for p in me.polygons])
    d, n, q = nablyzh(C)
    vseredyni = d < -0.004
    vnutr = ((N * n).sum(1) < -0.2) & (d < 0.03)
    geть = vseredyni | vnutr
    bm = bmesh.new(); bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[bm.faces[i] for i in np.nonzero(geть)[0]], context="FACES")
    # дрібні острівці, що лишились від стінок
    bm.verts.ensure_lookup_table()
    ostriv = []
    bachene = set()
    for f in bm.faces:
        if f.index in bachene:
            continue
        st, gr = [f], []
        bachene.add(f.index)
        while st:
            g = st.pop(); gr.append(g)
            for e in g.edges:
                for f2 in e.link_faces:
                    if f2.index not in bachene:
                        bachene.add(f2.index); st.append(f2)
        ostriv.append(gr)
    vsogo = sum(len(g) for g in ostriv)
    dribni = [f for g in ostriv if len(g) < 0.01 * vsogo for f in g]
    bmesh.ops.delete(bm, geom=dribni, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(me); bm.free(); me.update()
    log("геть: всередині тіла %d, внутрішня стінка %d, дрібних %d; лишилось граней %d"
        % (vseredyni.sum(), (vnutr & ~vseredyni).sum(), len(dribni), len(me.polygons)))

def vyshtovkhnuty(r, krokiv=4, zhladzh=12, z_do=None, vidstup=None):
    me = r.data
    V = np.array([v.co[:] for v in me.vertices])
    E = np.array([e.vertices[:] for e in me.edges])
    stup = np.bincount(E.ravel(), minlength=len(V)).astype(float)
    for k in range(krokiv):
        d, n, q = nablyzh(V)
        if k == 0:
            NV = np.array([v.normal[:] for v in me.vertices])
            zovn = (NV * n).sum(1) > 0.0     # внутрішня стінка (дивиться на тіло) лишається: її не видно
            if z_do is not None:             # лише нижня смуга (підйом стопи гладкий — не мнеться);
                zovn = V[:, 2] < z_do        # стопа чобота суцільна — нормалі TRELLIS ненадійні, не питаємо
        D = (np.maximum(0.0, (vidstup or VIDSTUP) - d) * zovn)[:, None] * n
        for _ in range(zhladzh):       # поле зсувів гладке: пластина зсувається цілою
            S = np.zeros_like(D)
            np.add.at(S, E[:, 0], D[E[:, 1]]); np.add.at(S, E[:, 1], D[E[:, 0]])
            Dm = S / np.maximum(stup, 1)[:, None]
            D = np.where((np.linalg.norm(D, axis=1) > np.linalg.norm(Dm, axis=1))[:, None], D, Dm)
        V = V + D
        log("виштовхування %d: у тілі/ближче відступу було %d вершин, найглибше %.1f мм"
            % (k + 1, int(((d < VIDSTUP) & zovn).sum()), max(0, -d[zovn].min()) * 1000))
    me.vertices.foreach_set("co", V.ravel()); me.update()

rechi = []
if ZONA == "кіраса":
    # кіраса з набедреними пластинами: від верху стегон до шиї
    # верх — основа шиї, низ — набедреники до середини стегна (від суглоба стегна вниз)
    VERH = SUHL["neck_01"] + 0.01 if "neck_01" in SUHL else 0.845
    NYZ = SUHL["thigh_r"] - 0.045 if "thigh_r" in SUHL else arg("--низ", 0.50)
    log("кіраса: частки зросту %.3f…%.3f" % (NYZ, VERH))
    r = zavantazhyty_rich()
    OSTROVY = ostrovy(r)
    log("острівці: %d, найбільші %s" % (len(OSTROVY[1]), OSTROVY[1][:6].tolist()))
    vpysaty_tulub(r, NYZ, VERH, m=0.022)
    "--чистка" in A and chystka(r)
    if "--виштовхнути" in A:
        vyshtovkhnuty(r)
    else:
        pole_rozduttia(r)
        if arg("--дамп", ""):
            np.savez(arg("--дамп", ""), V=np.array([v.co[:] for v in r.data.vertices]), VB=VB,
                     HOL=HOLOVNA, J=np.array([SUHL3["upperarm_r"], SUHL3["upperarm_l"]]), CX=CX, H=H, z0=z0)
        naplichnyky(r)
        pidniaty_plechi(r)
    rechi.append(r)
elif ZONA == "чобіт":
    for znak, dz in ((-1, False), (1, True)):
        r = zavantazhyty_rich(dzerkalo=dz)
        vpysaty_nohu(r, znak)
        # стопа (foot_, ball_) під чоботом у грі ховається завжди (`odiah_zona`: zavzhdy) —
        # носок не підганяється й не виштовхується, лишається як у речі
        "--виштовхнути" in A and vyshtovkhnuty(r)
        rechi.append(r)
def skinning(r, k=6):
    """Ваги кісток для речі — з найближчих вершин тіла (у позі, де річ сідала). Корпус
    кіраси (острівець 0) бере ваги лише з вершин тулуба — стінка під пахвою не їде з рукою;
    пластини наплічника — з усіх (плече, ключиця). Потім зворотний скінінг: позиція в позі →
    позиція в спокої скелета, і річ отримує модифікатор скелета, як тіло."""
    from mathutils.kdtree import KDTree
    me = r.data
    V = np.array([v.co[:] for v in me.vertices])
    kist = np.array([n in ARM.pose.bones for n in NAZVY])
    vsi = np.arange(len(VB))
    tulub_ = np.nonzero(~RUKA)[0]
    def kd_z(ids):
        kd = KDTree(len(ids))
        for j, i in enumerate(ids):
            kd.insert(Vector(VB[i]), j)
        kd.balance()
        return kd, ids
    kd_t, kd_v = kd_z(tulub_), kd_z(vsi)
    nom = OSTROVY[0] if OSTROVY is not None else np.zeros(len(V), int)
    wp = np.zeros(len(V))
    if "upperarm_r" in SUHL3 and OSTROVY is not None:
        wp = np.maximum(vaha_naplichnyka(V, "_r"), vaha_naplichnyka(V, "_l"))
    Wr = np.zeros((len(V), len(NAZVY)))
    for i, p in enumerate(V):
        kd, ids = kd_v if (nom[i] > 0 and wp[i] > 0.01) else kd_t
        nb = kd.find_n(Vector(p), k)
        d = np.array([x[2] for x in nb]) + 1e-4
        ww = (1 / d) / (1 / d).sum()
        Wr[i] = (WB[ids[[x[1] for x in nb]]] * ww[:, None]).sum(0)
    Wr[:, ~kist] = 0
    # пластина металу не гнеться: острівець наплічника — одна спільна вага на весь шматок;
    # дрібні острівці (ремінці, заклепки) — як найближча вершина великого
    if OSTROVY is not None:
        cnt = OSTROVY[1]
        velyki = cnt >= 0.01 * cnt.sum()
        for o_ in range(1, len(cnt)):
            q = nom == o_
            if velyki[o_] and (wp[q] > 0.01).any():
                Wr[q] = Wr[q].mean(0)
        dribni = np.nonzero(~velyki[nom])[0]
        vel = np.nonzero(velyki[nom])[0]
        if len(dribni):
            kd = KDTree(len(vel))
            for j, i in enumerate(vel):
                kd.insert(Vector(V[i]), j)
            kd.balance()
            for i in dribni:
                Wr[i] = Wr[vel[kd.find(Vector(V[i]))[1]]]
    # лишити 4 найбільші, нормувати
    o = np.argsort(-Wr, 1)[:, 4:]
    np.put_along_axis(Wr, o, 0, 1)
    Wr /= np.maximum(Wr.sum(1, keepdims=True), 1e-8)
    # зворотний скінінг
    aw = ARM.matrix_world
    D = {}
    for j, n in enumerate(NAZVY):
        if kist[j]:
            pb = ARM.pose.bones[n]
            D[j] = np.array(aw @ pb.matrix @ pb.bone.matrix_local.inverted() @ aw.inverted())
    V2 = np.zeros_like(V)
    for i, p in enumerate(V):
        S = np.zeros((4, 4))
        for j in np.nonzero(Wr[i] > 0)[0]:
            S += Wr[i, j] * D[j]
        V2[i] = (np.linalg.inv(S) @ np.append(p, 1.0))[:3]
    me.vertices.foreach_set("co", V2.ravel()); me.update()
    for j, n in enumerate(NAZVY):
        if kist[j] and Wr[:, j].max() > 0:
            g = r.vertex_groups.new(name=n)
            for i in np.nonzero(Wr[:, j] > 0)[0]:
                g.add([int(i)], float(Wr[i, j]), "REPLACE")
    md = r.modifiers.new("скелет", "ARMATURE")
    md.object = ARM
    r.parent = ARM
    r.matrix_parent_inverse = ARM.matrix_world.inverted()
    log("скінінг: груп %d; зсув у спокій до %.1f см" % (len(r.vertex_groups), 100 * np.linalg.norm(V2 - V, axis=1).max()))

if POZA and ARM:
    for r in rechi:
        skinning(r)
for r in rechi:
    r.name = "Одяг-%s" % ZONA
bpy.ops.wm.save_as_mainfile(filepath=VYHID)
log("збережено", VYHID)

OHLIAD = arg("--огляд", "")
if OHLIAD:
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = sc.render.resolution_y = 900
    w = bpy.data.worlds.new("w"); sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.3, 0.3, 0.32, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.8
    cam = bpy.data.objects.new("кам", bpy.data.cameras.new("кам"))
    sc.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    VR = np.concatenate([np.array([r.matrix_world @ v.co for v in r.data.vertices]) for r in rechi])
    lo, hi = VR.min(0), VR.max(0)
    cam.data.ortho_scale = max(hi[0] - lo[0], hi[2] - lo[2]) * 1.35
    sc.camera = cam
    for i, (e, k) in enumerate([(3.0, (55, 0, 35)), (1.5, (60, 0, -120))]):
        L = bpy.data.objects.new("св%d" % i, bpy.data.lights.new("св%d" % i, "SUN"))
        L.data.energy = e
        L.rotation_euler = [math.radians(a) for a in k]
        sc.collection.objects.link(L)
    c = (lo + hi) / 2
    # тіло під річчю сховати, як `під_одяг` у грі: вершина, від якої по нормалі назовні
    # (або вона вже зовні речі) до речі ближче 8 см
    from mathutils.bvhtree import BVHTree as _B
    rb = []
    for r in rechi:
        mw = r.matrix_world
        rb.append(_B.FromPolygons([mw @ v.co for v in r.data.vertices], [p.vertices[:] for p in r.data.polygons]))
    NBv = np.array([v.normal[:] for v in tilo.data.vertices]) * ZNAK_T
    vydno = []
    for i, p in enumerate(VB):
        o_ = Vector(p); n_ = Vector(NBv[i])
        skh = "--ховати" in A and any(b.ray_cast(o_ - n_ * 0.002, n_, 0.08)[0] is not None for b in rb)
        if skh and RUKA is not None and RUKA[i]:
            skh = False                # руку не ховати: у грі вона рухається з-під наплічника
        if ZONA == "чобіт" and HOLOVNA is not None and HOLOVNA[i].startswith(("foot_", "ball_")):
            skh = True                 # як у грі: стопа під чоботом схована завжди
        if not skh:
            vydno.append(i)
    g = tilo.vertex_groups.new(name="видно")
    g.add(vydno, 1.0, "REPLACE")
    mk = tilo.modifiers.new("під_одяг", "MASK")
    mk.vertex_group = "видно"
    log("огляд: сховано під річчю %d вершин тіла" % (len(VB) - len(vydno)))
    def znimky(OHLIAD):
        kadry = []
        for i, (kut, lyshe) in enumerate([(0, False), (35, True), (110, True), (180, False)]):
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
    znimky(OHLIAD)
    if POZA and ARM:            # та сама річ у позі спокою скелета (А-поза) — через ваги
        for pb in ARM.pose.bones:
            pb.matrix_basis.identity()
        bpy.context.view_layer.update()
        znimky(OHLIAD.replace('.png', '-спокій.png'))
