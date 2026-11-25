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
SUHL = {}
if tilo.vertex_groups:
    nazvy = [g.name for g in tilo.vertex_groups]
    W = np.zeros((len(tilo.data.vertices), len(nazvy)))
    for v in tilo.data.vertices:
        for g in v.groups:
            W[v.index, g.group] = g.weight
    holovna = np.array(nazvy)[W.argmax(1)]
    RUKA = np.array([any(k in h for k in ("upperarm", "lowerarm", "hand")) for h in holovna])
    arm = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
    if arm:
        for b in arm.data.bones:
            SUHL[b.name] = ((arm.matrix_world @ b.head_local).z - z0) / H
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

def vyshtovkhnuty(r, krokiv=4, zhladzh=12):
    me = r.data
    V = np.array([v.co[:] for v in me.vertices])
    E = np.array([e.vertices[:] for e in me.edges])
    stup = np.bincount(E.ravel(), minlength=len(V)).astype(float)
    for k in range(krokiv):
        d, n, q = nablyzh(V)
        if k == 0:
            NV = np.array([v.normal[:] for v in me.vertices])
            zovn = (NV * n).sum(1) > 0.0     # внутрішня стінка (дивиться на тіло) лишається: її не видно
        D = (np.maximum(0.0, VIDSTUP - d) * zovn)[:, None] * n
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
    vpysaty_tulub(r, NYZ, VERH)
    "--чистка" in A and chystka(r)
    vyshtovkhnuty(r)
    rechi.append(r)
elif ZONA == "чобіт":
    for znak, dz in ((-1, False), (1, True)):
        P = noha(0.0, 0.30, znak)
        r = zavantazhyty_rich(dzerkalo=dz)
        vpysaty(r, P, 0.012, 0.022, z0 - 0.003, z0 + SUHL.get("calf_r", 0.28) * H + 0.035 * H)
        "--чистка" in A and chystka(r)
        vyshtovkhnuty(r)
        rechi.append(r)
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
