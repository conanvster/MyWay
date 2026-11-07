"""Пілот гібриду Б+Г (П-281, 07.11.2026): з'єднання моделі Hunyuan з основою MPFB.

Слово замовника: «так, скачуй і продовжуй з'єднання». Вхід — основа MPFB
(`pilot_b.py`, `pilot.blend`) і модель Hunyuan 3D V3.1 з кадру вікі (GLB,
лише на диску). Вихід — `з-єднання.blend`: тіло MPFB на скелеті
`game_engine` + одяг і волосся з моделі окремими сітками на тому ж скелеті,
у позі спокою MPFB; тіло під кожною річчю ховає своя маска.

Кроки:
  1. модель — стоячи (ступні на нулі), зріст основи, обличчям у −Y;
  2. розріз моделі за кольором текстури й місцем: черевики, штани, верх
     (сорочка, жилет, ремені, плащ), волосся, відкрита шкіра;
  3. руки й ноги основи — у позу моделі (цілі — центри кистей і черевиків);
  4. шкіра уточнюється відстанню до тіла (голова, шия, кисті) — її сітка
     не береться, там видно тіло MPFB;
  5. кожна річ спрощується до свого бюджету, отримує нову розгортку й
     запечений колір з повної моделі (1,5 млн граней);
  6. ваги — з найближчого тіла: руки лише для рукавів, плащ нижче пояса —
     до таза, волосся — голова/шия/спина за висотою;
  7. зворотний скінінг: речі переходять у позу спокою MPFB;
  8. маски тіла «під_<річ>» (промінь із тіла + кістки під річчю).

Усе — на процесорі (Cycles CPU).

    blender -b <pilot.blend> -P tools/blender/pilot_zyednannia.py -- \\
        <модель.glb> <тека> [--текстура 2048]
"""
import functools
import math
import os
import sys
import time

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

print = functools.partial(print, flush=True)
ARGS = sys.argv[sys.argv.index("--") + 1:]
TEX = 2048
if "--текстура" in ARGS:
    i = ARGS.index("--текстура")
    TEX = int(ARGS[i + 1])
    del ARGS[i:i + 2]
GLB, KUDY = os.path.abspath(ARGS[0]), os.path.abspath(ARGS[1])
os.makedirs(os.path.join(KUDY, "текстури"), exist_ok=True)
T0 = time.time()

ZRIST = 1.75
BUDGET = {"верх": 12000, "штани": 5000, "взуття": 4000, "волосся": 5000}
K = {"взуття": 0, "штани": 1, "верх": 2, "волосся": 3, "шкіра": 4}
ARM = ("upperarm", "lowerarm")
HANDISH = ("hand", "thumb", "index", "middle", "ring", "pinky")


def log(*a):
    print("[з'єднання %3ds]" % (time.time() - T0), *a)


# ---------- 1. модель стоячи ----------
rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
body = max((o for o in bpy.data.objects if o.type == "MESH"),
           key=lambda o: len(o.data.vertices))
for o in list(bpy.data.objects):
    if o.type == "MESH" and "long01" in o.name.lower():
        bpy.data.objects.remove(o)       # зачіска — з моделі
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=GLB)
hi = next(o for o in bpy.data.objects if o not in before and o.type == "MESH")
for o in bpy.data.objects:
    o.select_set(o is hi)
bpy.context.view_layer.objects.active = hi
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
# GLB ріже сітку по швах розгортки — тисячі окремих клаптиків; зшити, інакше
# спрощення рве поверхню, а нова розгортка — по трикутнику на острів.
bm = bmesh.new()
bm.from_mesh(hi.data)
v0 = len(bm.verts)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
log("зшито вершин", v0 - len(bm.verts))
bm.to_mesh(hi.data)
bm.free()
co = np.empty(len(hi.data.vertices) * 3)
hi.data.vertices.foreach_get("co", co)
co = co.reshape(-1, 3)
co[:, 2] -= co[:, 2].min()
s = ZRIST / co[:, 2].max()
co *= s
co[:, 0] -= (co[:, 0].max() + co[:, 0].min()) / 2
co[:, 1] -= (co[:, 1].max() + co[:, 1].min()) / 2 + 0.03
foot = co[co[:, 2] < 0.05]
if foot[:, 1].mean() > co[:, 1].mean():            # носки мають дивитись у −Y
    co[:, :2] *= -1
hi.data.vertices.foreach_set("co", co.ravel())
hi.data.update()
hi.name = "модель"
log("модель", len(hi.data.polygons), "граней, масштаб %.3f" % s)

# робоча копія (150 тис.) — для розрізу й речей
lo = hi.copy()
lo.data = hi.data.copy()
lo.name = "модель-робоча"
bpy.context.scene.collection.objects.link(lo)
m = lo.modifiers.new("dec", "DECIMATE")
m.ratio = 150000 / len(hi.data.polygons)
bpy.context.view_layer.objects.active = lo
bpy.ops.object.modifier_apply(modifier="dec")
me = lo.data
n = len(me.vertices)
co = np.empty(n * 3)
me.vertices.foreach_get("co", co)
co = co.reshape(-1, 3)
x, y, z = co.T

# колір текстури у вершинах
img = next(nd.image for nd in me.materials[0].node_tree.nodes
           if nd.type == "TEX_IMAGE" and nd.image
           and not any(k in nd.image.name for k in ("metal", "normal", "rough")))
W_, H_ = img.size
px = np.empty(W_ * H_ * 4, np.float32)
img.pixels.foreach_get(px)
px = px.reshape(H_, W_, 4)
uv = np.empty(len(me.loops) * 2)
me.uv_layers.active.data.foreach_get("uv", uv)
uv = uv.reshape(-1, 2)
vi = np.empty(len(me.loops), int)
me.loops.foreach_get("vertex_index", vi)
c = px[np.clip((uv[:, 1] * H_).astype(int), 0, H_ - 1),
       np.clip((uv[:, 0] * W_).astype(int), 0, W_ - 1), :3]
col = np.zeros((n, 3))
cnt = np.zeros(n)
np.add.at(col, vi, c)
np.add.at(cnt, vi, 1)
col /= np.maximum(cnt, 1)[:, None]
r, g, b = col.T
mx, mn = col.max(1), col.min(1)
sat = (mx - mn) / np.maximum(mx, 1e-6)
d = np.maximum(mx - mn, 1e-6)
hue = np.where(mx == r, ((g - b) / d) % 6,
               np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) / 6
skinc = (hue > 0.0) & (hue < 0.11) & (sat > 0.15) & (mx > 0.14)
hairc = (sat < 0.25) & (mx < 0.26)

# ---------- 3. поза основи ----------
P = rig.pose.bones


def aim(name, cur_fn, target):
    bpy.context.view_layer.update()
    pb = P[name]
    q = cur_fn().normalized().rotation_difference((target - pb.head).normalized())
    pm = pb.matrix.to_quaternion()
    pb.rotation_mode = "QUATERNION"
    pb.rotation_quaternion = (pm.inverted() @ q @ pm) @ pb.rotation_quaternion


for side, sx in (("l", 1), ("r", -1)):
    hand = skinc & (z > 0.65) & (z < 0.95) & (sx * x > 0.15)
    boot = (z < 0.12) & (sx * x > 0)
    hc = Vector(co[hand].mean(0)) if hand.sum() > 50 else None
    bc = Vector(co[boot].mean(0))
    sh = P["upperarm_" + side].head.copy()
    if hc is not None:
        wrist = hc + Vector((0, 0.02, 0.085))
        elbow = sh + (wrist - sh) * 0.52 + Vector((0, 0.025, 0))
        aim("upperarm_" + side, lambda: P["upperarm_" + side].tail - P["upperarm_" + side].head, elbow)
        aim("lowerarm_" + side, lambda: P["lowerarm_" + side].tail - P["lowerarm_" + side].head, wrist)
    ankle = Vector((bc.x, bc.y + 0.055, 0.073))
    aim("thigh_" + side, lambda: P["calf_" + side].tail - P["thigh_" + side].head, ankle)
    aim("calf_" + side, lambda: P["calf_" + side].tail - P["calf_" + side].head, ankle)
    log("поза", side, "кисть", hc and tuple(round(v, 3) for v in hc),
        "черевик", tuple(round(v, 3) for v in bc))
bpy.context.view_layer.update()
POSE = {pb.name: pb.rotation_quaternion.copy() for pb in P}

# ---------- тіло: поза моделі й спокій ----------
bones = {bn.name for bn in rig.data.bones}


def body_coords(posed):
    keep = [(md, md.show_viewport) for md in body.modifiers]
    for md, _ in keep:
        md.show_viewport = posed and md.type == "ARMATURE"
    dg = bpy.context.evaluated_depsgraph_get()
    ev = body.evaluated_get(dg)
    em = ev.to_mesh()
    assert len(em.vertices) == len(body.data.vertices)
    cc = np.array([body.matrix_world @ v.co for v in em.vertices])
    nn = np.array([(body.matrix_world.to_3x3() @ v.normal).normalized() for v in em.vertices])
    polys = [tuple(p.vertices) for p in em.polygons]
    ev.to_mesh_clear()
    for md, sv in keep:
        md.show_viewport = sv
    return cc, nn, polys


bco, bnor, bpolys = body_coords(True)
brest, _, _ = body_coords(False)
gnames = [gr.name for gr in body.vertex_groups if gr.name in bones]
gidx = {body.vertex_groups[nm].index: i for i, nm in enumerate(gnames)}
W = np.zeros((len(bco), len(gnames)), np.float32)
for v in body.data.vertices:
    for gr in v.groups:
        if gr.group in gidx:
            W[v.index, gidx[gr.group]] = gr.weight
has_w = W.sum(1) > 0
W /= np.maximum(W.sum(1, keepdims=True), 1e-6)
dom = np.array([gnames[i] for i in W.argmax(1)])
helper = np.zeros(len(bco), bool)
for nm in ("HelperGeometry", "JointCubes"):
    if nm in body.vertex_groups:
        gi = body.vertex_groups[nm].index
        for v in body.data.vertices:
            if any(gr.group == gi and gr.weight > 0.5 for gr in v.groups):
                helper[v.index] = True
real = has_w & ~helper
is_arm = np.array([any(a in t for a in ARM) for t in dom])
is_hand = np.array([any(a in t for a in HANDISH) for t in dom])


def kd_of(mask):
    ids = np.nonzero(mask)[0]
    t = KDTree(len(ids))
    for j, i in enumerate(ids):
        t.insert(bco[i], int(i))
    t.balance()
    return t


kd_all = kd_of(real)
kd_arm = kd_of(real & is_arm)
kd_core = kd_of(real & ~is_arm & ~is_hand)
kd_hand = kd_of(real & is_hand)   # уламки кистей моделі поруч — геть із речей

# ---------- 4. розріз ----------
near_d = np.zeros(n)
ndom = np.empty(n, dtype=object)
for i, cc in enumerate(co):
    _, j, dd = kd_all.find(cc)
    near_d[i] = dd
    ndom[i] = dom[j]
headb = np.isin(ndom, ["head", "neck_01"])
handb = np.array([any(a in t for a in HANDISH) for t in ndom])
cls = np.full(n, K["верх"])
cls[hairc & (z > 1.25) & ((y > -0.02) | (np.abs(x) > 0.07)) & ~((z < 1.45) & (y < -0.06))] = K["волосся"]
cls[z > 1.62] = K["волосся"]
# шкіра голови — лише обличчя спереду (проділ на маківці — волосся);
# кисті — усе, що лежить на кисті основи.
face = (y < -0.04) & (z < 1.70)
hairline = (z > 1.6) & (sat < 0.2)     # світлі відблиски на волоссі над лобом
skin = (headb & face & (near_d < 0.04) & ~hairc & ~hairline) | (headb & face & (near_d < 0.012) & skinc) \
    | (headb & face & (near_d < 0.015) & (y < -0.07)) | (handb & (near_d < 0.05))
cls[skin] = K["шкіра"]
belt = (hue < 0.135) & (sat > 0.22)
cls[(z > 0.28) & (z < 1.0) & ~belt & (cls == K["верх"])] = K["штани"]
cls[(z < 0.30) & (cls != K["шкіра"])] = K["взуття"]
ed = np.array([e.vertices[:] for e in me.edges])
for _ in range(4):
    votes = np.zeros((n, 5))
    np.add.at(votes, (ed[:, 0], cls[ed[:, 1]]), 1)
    np.add.at(votes, (ed[:, 1], cls[ed[:, 0]]), 1)
    votes[np.arange(n), cls] += 1.5
    cls = votes.argmax(1)
# Кисть моделі зрослася зі штанами/плащем — під нею тканини немає. Не
# вирізати (діра), а віддати найближчій тканині й притиснути до тіла основи.
handv = (cls == K["шкіра"]) & handb
cloth = (cls != K["шкіра"]) & ~handb & (z < 1.1)
kd_cloth = KDTree(int(cloth.sum()))
for i in np.nonzero(cloth)[0]:
    kd_cloth.insert(co[i], int(i))
kd_cloth.balance()
core_tris = [t for t in bpolys if all(real[list(t)]) and not any(is_arm[list(t)] | is_hand[list(t)])]
bvh_core = BVHTree.FromPolygons([Vector(c_) for c_ in bco], core_tris)
for i in np.nonzero(handv)[0]:
    _, j, _ = kd_cloth.find(co[i])
    cls[i] = cls[j]
    loc, nrm, _, _ = bvh_core.find_nearest(Vector(co[i]))
    co[i] = loc + nrm * 0.012
    me.vertices[int(i)].co = co[i]
me.update()
log("кисті моделі → тканина", int(handv.sum()))
log("розріз", {k: int((cls == i).sum()) for k, i in K.items()})

# ---------- 5. речі: спрощення, розгортка, запікання ----------
# запікати з моделі без кистей: латки на місці кисті беруть колір речі,
# а не темний низ кисті
bm = bmesh.new()
bm.from_mesh(hi.data)
bmesh.ops.delete(bm, geom=[v for v in bm.verts if kd_hand.find(v.co)[2] < 0.03],
                 context="VERTS")
bm.to_mesh(hi.data)
bm.free()
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = 1
bk = sc.render.bake
bk.use_selected_to_active = True
bk.cage_extrusion = 0.015
bk.max_ray_distance = 0.06
bk.margin = 8
bk.use_pass_direct = False
bk.use_pass_indirect = False
bk.use_pass_color = True
pieces = {}
for nm in BUDGET:
    i = K[nm]
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    near_hand = set()
    bmesh.ops.delete(bm, geom=[f for f in bm.faces
                               if sum(cls[v.index] == i for v in f.verts) < 2
                               or any(v.index in near_hand for v in f.verts)],
                     context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    # дрібні відірвані клаптики (уламки на обличчі, біля кистей) — геть
    seen = set()
    for f in bm.faces:
        if f in seen:
            continue
        comp, stack = [], [f]
        seen.add(f)
        while stack:
            q_ = stack.pop()
            comp.append(q_)
            for e in q_.edges:
                for f2 in e.link_faces:
                    if f2 not in seen:
                        seen.add(f2)
                        stack.append(f2)
        if len(comp) < 120:
            bmesh.ops.delete(bm, geom=comp, context="FACES")
    # дірки, де модель зливала річ із кистю (до 28 см по краю) — латати
    bnd = [e for e in bm.edges if e.is_boundary]
    parent = {}

    def root(v):
        while parent.get(v, v) is not v:
            v = parent[v]
        return v
    for e in bnd:
        a_, b2 = root(e.verts[0]), root(e.verts[1])
        if a_ is not b2:
            parent[a_] = b2
    loops = {}
    for e in bnd:
        loops.setdefault(root(e.verts[0]), []).append(e)
    def patch(es):
        per = sum(x.calc_length() for x in es)
        mid = sum((x.verts[0].co for x in es), Vector()) / len(es)
        # дрібні — завжди; більші — лише там, де кисть моделі зрослася з річчю
        return per < 0.28 or (per < 0.8 and kd_hand.find(mid)[2] < 0.12)
    holes = [es for es in loops.values() if patch(es)]
    if holes:
        bmesh.ops.holes_fill(bm, edges=[e for es in holes for e in es], sides=0)
    log("річ", nm, "латок", len(holes))
    pm_ = bpy.data.meshes.new(nm)
    bm.to_mesh(pm_)
    bm.free()
    for uvl in list(pm_.uv_layers):
        pm_.uv_layers.remove(uvl)
    ob = bpy.data.objects.new(nm, pm_)
    sc.collection.objects.link(ob)
    f0 = len(pm_.polygons)
    dec = ob.modifiers.new("dec", "DECIMATE")
    dec.ratio = min(1.0, BUDGET[nm] / max(f0, 1))
    for o in bpy.data.objects:
        o.select_set(False)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.modifier_apply(modifier="dec")
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004)
    bpy.ops.object.mode_set(mode="OBJECT")
    for p in pm_.polygons:
        p.use_smooth = True
    size = TEX if nm == "верх" else TEX // 2
    im = bpy.data.images.new(nm, size, size)
    # тло — середній колір речі: латки, куди промінь запікання не влучив
    base = np.median(col[cls == i], 0)
    im.pixels.foreach_set(np.tile(np.append(base, 1.0), size * size).astype(np.float32))
    mat = bpy.data.materials.new(nm)
    mat.use_nodes = True
    nt = mat.node_tree
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = im
    nt.links.new(tn.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
    nt.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.8
    nt.nodes.active = tn
    pm_.materials.append(mat)
    hi.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.bake(type="DIFFUSE")
    # куди промінь не влучив (латки) — запікання пише чорне: колір речі
    pxl = np.empty(size * size * 4, np.float32)
    im.pixels.foreach_get(pxl)
    pxl = pxl.reshape(-1, 4)
    pxl[pxl[:, :3].sum(1) < 0.004, :3] = base
    im.pixels.foreach_set(pxl.ravel())
    im.filepath_raw = os.path.join(KUDY, "текстури", nm + ".png")
    im.file_format = "PNG"
    im.save()
    pieces[nm] = ob
    log("річ", nm, f0, "→", len(pm_.polygons), "граней, текстура", size)

# ---------- 6–7. ваги й поза спокою ----------
pel = gnames.index("pelvis")
Ms = np.array([np.array(rig.matrix_world @ P[g_].matrix
                        @ rig.data.bones[g_].matrix_local.inverted()
                        @ rig.matrix_world.inverted()) for g_ in gnames])


def blend(tree, c, k=4):
    res = tree.find_n(c, k)
    ws = np.array([1 / max(dd, 1e-4) for _, _, dd in res])
    ids = [j for _, j, _ in res]
    return (W[ids] * ws[:, None]).sum(0) / ws.sum(), min(dd for _, _, dd in res)


kd_lo = KDTree(n)
for i, cc in enumerate(co):
    kd_lo.insert(cc, i)
kd_lo.balance()
SEGS = [(P[b + s].head.copy(), P[b + s].tail.copy())
        for b in ("upperarm_", "lowerarm_") for s in "lr"]


def to_arm_axis(c):
    p = Vector(c)
    best = 9.0
    for a, b_ in SEGS:
        ab = b_ - a
        t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
        best = min(best, (a + ab * t - p).length)
    return best


for nm, ob in pieces.items():
    pm_ = ob.data
    pc = np.array([v.co[:] for v in pm_.vertices])
    HW = np.zeros((len(pc), len(gnames)), np.float32)
    for i, cc in enumerate(pc):
        wc, dc = blend(kd_core, cc)
        if nm == "верх":
            # рукав — за відстанню до осі кістки руки (не до поверхні: між
            # опущеною рукою й боком поверхня тулуба ближча), перехід плавний
            ax = to_arm_axis(cc)
            t = np.clip((dc - 0.02) / 0.06, 0, 1) * (cc[2] < 1.0)
            wc = wc * (1 - t)
            wc[pel] += t
            _, jl, _ = kd_lo.find(cc)
            shirt = (0.12 < hue[jl] < 0.4 and mx[jl] > 0.2) or ax < 0.042
            if cc[2] > 0.86 and ax < 0.09 and shirt:
                wa, _ = blend(kd_arm, cc)
                k = 1.0 - np.clip((ax - 0.06) / 0.03, 0, 1)
                wc = wa * k + wc * (1 - k)
        HW[i] = wc
    if nm == "верх":
        # модель зрощує рукав із боком тулуба — нижче пахви розрізати по межі
        # «рука / тулуб», інакше піднята рука тягне перетинку
        armw = HW[:, [gnames.index(g_) for g_ in gnames if any(a in g_ for a in ARM)]].sum(1)
        bm = bmesh.new()
        bm.from_mesh(pm_)
        cut = [e for e in bm.edges
               if (armw[e.verts[0].index] - 0.5) * (armw[e.verts[1].index] - 0.5) < 0
               and max(pc[e.verts[0].index][2], pc[e.verts[1].index][2]) < 1.25]
        dead = list({f for e in cut for f in e.link_faces})
        bmesh.ops.delete(bm, geom=dead, context="FACES_ONLY")
        bm.to_mesh(pm_)
        bm.free()
        assert len(pm_.vertices) == len(pc)
        log("річ", nm, "розрізано рукав/бік, ребер", len(cut))
    # згладити ваги по сітці (перехід рукав → бік без складок)
    ed_ = np.array(sorted({k for p in pm_.polygons for k in p.edge_keys}))
    for _ in range(3):
        acc = HW.copy()
        cnt_ = np.ones(len(pc))
        np.add.at(acc, ed_[:, 0], HW[ed_[:, 1]])
        np.add.at(acc, ed_[:, 1], HW[ed_[:, 0]])
        np.add.at(cnt_, ed_[:, 0], 1)
        np.add.at(cnt_, ed_[:, 1], 1)
        HW = 0.5 * HW + 0.5 * acc / cnt_[:, None]
    if nm == "волосся":
        zz = pc[:, 2]
        HW[:] = 0
        HW[:, gnames.index("head")] = np.clip((zz - 1.45) / 0.1, 0, 1)
        HW[:, gnames.index("neck_01")] = np.clip(1 - np.abs(zz - 1.42) / 0.1, 0, 1) * (zz < 1.55)
        HW[:, gnames.index("spine_03")] = np.clip((1.40 - zz) / 0.1, 0, 1)
    HW /= np.maximum(HW.sum(1, keepdims=True), 1e-6)
    Mv = np.einsum("vb,bij->vij", HW, Ms)
    rest = np.linalg.solve(Mv, np.concatenate([pc, np.ones((len(pc), 1))], 1)[:, :, None])[:, :3, 0]
    pm_.vertices.foreach_set("co", rest.ravel())
    pm_.update()
    for gi, g_ in enumerate(gnames):
        ids = np.nonzero(HW[:, gi] > 0.01)[0]
        if len(ids):
            vg = ob.vertex_groups.new(name=g_)
            for j in ids:
                vg.add([int(j)], float(HW[j, gi]), "REPLACE")
    ob.parent = rig
    am = ob.modifiers.new("Armature", "ARMATURE")
    am.object = rig
    ob["П-281"] = "з моделі Hunyuan V3.1 (людина-жінка в1)"

# ---------- 8. маски тіла ----------
lo_co = co
lo_tris = [tuple(p.vertices) for p in me.polygons]
cover = {}
for nm in ("верх", "штани", "взуття", "волосся"):
    sel = cls == K[nm]
    tris = [t for t in lo_tris if sum(sel[list(t)]) >= 2]
    bv = BVHTree.FromPolygons([Vector(c_) for c_ in lo_co], tris)
    msk = np.zeros(len(bco), bool)
    for i in np.nonzero(real)[0]:
        reach = 0.025 if dom[i] == "neck_01" else 0.15   # тісний комір — так, розріз — ні
        h = bv.ray_cast(Vector(bco[i]) - Vector(bnor[i]) * 0.002, Vector(bnor[i]), reach)
        msk[i] = h[0] is not None
    cover[nm] = msk
rz = brest[:, 2]
for nm in ("верх", "штани", "взуття"):
    cover[nm] &= ~np.array([t == "head" for t in dom])   # обличчя променями не ховати
has = lambda *ks: np.array([any(k_ in t for k_ in ks) for t in dom])
cover["взуття"] |= has("foot", "ball") | (has("calf") & (rz < 0.32))
cover["штани"] |= has("thigh") | (has("calf") & (rz >= 0.28)) | (has("pelvis") & (rz < 1.0))
# передпліччя — лише променями (біля кисті рукав вирізано); шия й верх грудей
# під коміром не ховаються — у розрізі коміра видно шкіру, а не порожнечу
open_neck = has("spine_03", "clavicle") & (rz > 1.38) & (brest[:, 1] < -0.03) \
    & (np.abs(brest[:, 0]) < 0.07)
cover["верх"] |= (((has("spine") & (rz < 1.36)) | has("clavicle", "upperarm")) & ~open_neck) \
    | (has("pelvis") & (rz >= 0.95))
hair_rays = cover.pop("волосся") & ~has("head")
cover["верх"] |= hair_rays                  # пасма на грудях/спині — разом із верхом
# голова основи трохи більша за голову моделі — скальп і вуха під зачіскою
ry = brest[:, 1]
cover["волосся"] = has("head") & (((rz > 1.66) & (ry > -0.04)) | ((ry > -0.02) & (rz > 1.50)))
for nm, msk in cover.items():
    msk &= real
    vg = body.vertex_groups.new(name="під_" + nm)
    vg.add([int(i) for i in np.nonzero(msk)[0]], 1.0, "REPLACE")
    md = body.modifiers.new("ховати_" + nm, "MASK")
    md.vertex_group = vg.name
    md.invert_vertex_group = True
    log("маска", nm, int(msk.sum()))

bpy.data.objects.remove(lo)
bpy.data.objects.remove(hi)
for pb in P:
    pb.rotation_quaternion = (1, 0, 0, 0)
rig["поза_моделі"] = {k: list(v) for k, v in POSE.items()}
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(KUDY, "з-єднання.blend"))
log("готово", os.path.join(KUDY, "з-єднання.blend"))
