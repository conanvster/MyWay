# Менші труси (20.11.2026, слово замовника: «зробити чорні труси меншими, щоб не було
# видно з-під поясу»): труси основи намальовані на текстурі шкіри тіла; штанини боксерів
# зрізаємо по лінії промежини (+ зсув), замальовуємо тоном шкіри стегна, нормалі — рівні.
#   blender -b <модель.blend> -P tools/blender/trusy_menshi.py -- <вихід.blend>
#       [--зсув 0.0] [--підйом-спереду 0.7] [--підйом-ззаду 0.5] [--згладити 0.035 м, 0 — ні] [--огляд кадр.png] [--поріг 0.12]
# Координати текселів беремо запіканням позиції (Cycles EMIT, CPU) у float-зображення.
import sys
import bpy
import numpy as np

argv = sys.argv[sys.argv.index("--") + 1:]
VYHID = argv[0]
def arg(k, d):
    return type(d)(argv[argv.index(k) + 1]) if k in argv else d
ZSUV = arg("--зсув", 0.0)
PORIH = arg("--поріг", 0.12)
OHLIAD = arg("--огляд", "")
PID_PER = arg("--підйом-спереду", 0.7)
PID_ZAD = arg("--підйом-ззаду", 0.5)
ZHLAD = arg("--згладити", 0.035)

sc = bpy.context.scene
body = max((o for o in bpy.data.objects if o.type == "MESH" and o.name.startswith("Тіло")),
           key=lambda o: len(o.data.polygons))
mats = [m for m in body.data.materials if m]
mt = next(m for m in mats if m.name.startswith("шкіра-тіло"))
tex = next(n for n in mt.node_tree.nodes if n.type == "TEX_IMAGE" and n.image
           and n.image.name.endswith("колір"))
nrm = next((n for n in mt.node_tree.nodes if n.type == "TEX_IMAGE" and n.image
            and "нормалі" in n.image.name), None)
W, H = tex.image.size
print("[труси] тіло", body.name, "текстура", tex.image.name, W, H)

# --- запікання позиції ---
pos = bpy.data.images.new("tmp-позиція", W, H, float_buffer=True, alpha=True)
pos.generated_color = (0, 0, -10, 0)
dummy = bpy.data.images.new("tmp-заглушка", 64, 64)
saved = {}
for m in mats:
    nt = m.node_tree
    out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL" and n.is_active_output)
    saved[m.name] = out.inputs["Surface"].links[0].from_socket if out.inputs["Surface"].links else None
    g = nt.nodes.new("ShaderNodeNewGeometry")
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(g.outputs["Position"], em.inputs["Color"])
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    im = nt.nodes.new("ShaderNodeTexImage")
    im.image = pos if m is mt else dummy
    nt.nodes.active = im
    m["_tmp"] = [g.name, em.name, im.name]
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = 1
sc.render.bake.use_selected_to_active = False
sc.render.bake.target = "IMAGE_TEXTURES"
sc.render.bake.margin = 4
for o in bpy.context.view_layer.objects:
    o.select_set(False)
body.hide_set(False); body.hide_viewport = False; body.hide_render = False
body.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.bake(type="EMIT")
P = np.array(pos.pixels[:], dtype=np.float32).reshape(H, W, 4)
for m in mats:
    nt = m.node_tree
    for nm in m["_tmp"]:
        nt.nodes.remove(nt.nodes[nm])
    out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL" and n.is_active_output)
    if saved[m.name] is not None:
        nt.links.new(saved[m.name], out.inputs["Surface"])
    del m["_tmp"]
nt = mt.node_tree
nt.nodes.active = tex

# --- промежина: найнижча точка тіла між ногами ---
mw = body.matrix_world
V = np.array([mw @ v.co for v in body.data.vertices])
mid = V[np.abs(V[:, 0]) < 0.015]
mid = mid[(mid[:, 2] > 0.5) & (mid[:, 2] < 1.2)]
zc = float(mid[:, 2].min())
zcut = zc + ZSUV
print("[труси] промежина z=%.3f, зріз z=%.3f" % (zc, zcut))

C = np.array(tex.image.pixels[:], dtype=np.float32).reshape(H, W, 4)
lum = C[..., :3] @ np.array([0.3, 0.59, 0.11], dtype=np.float32)
cov = P[..., 2] > -5
z = P[..., 2]
dark = cov & (lum < PORIH) & (z > zc - 0.35) & (z < zc + 0.25)
# штанини: темне нижче скошеної лінії плавок — біля промежини низько, до стегна вгору
# (спереду вище, ззаду нижче, щоб сідниці лишались закриті)
x, y = P[..., 0], P[..., 1]
ax = np.abs(x)
tz = np.clip((y + 0.06) / 0.12, 0, 1)
pidiom = PID_PER * (1 - tz) + PID_ZAD * tz
zline = zcut + 0.02 + pidiom * np.maximum(ax - 0.03, 0)
cut = dark & (z < zline)
# пляма над поясом трусів (давня вада текстури): темне вище верхнього краю ззаду
def dilate(m, r):
    out = m.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            out |= np.roll(np.roll(m, dy, 0), dx, 1)
    return out
edge = dilate(cut, 6) & cov & (lum < 0.45) & (z < zline + 0.006)
# світлий край рубця (не темний, тож поріг його не бере): смуга навколо старого краю
zhem = float(np.percentile(z[dark & (ax > 0.06)], 0.5))
hem = cov & (np.abs(z - zhem) < 0.012) & (ax > 0.04) & (z < zline)
mask = (cut | edge).astype(np.float32)
mask = np.maximum(mask, hem * 0.7)
print("[труси] темних текселів %d, зрізаємо %d" % (dark.sum(), int(mask.sum())))

# тон шкіри стегна: світле нижче штанин
band = cov & ~dark & (lum > 0.25) & (z < zc - 0.05) & (z > zc - 0.30)
skin = np.median(C[band][:, :3], axis=0)
print("[труси] тон стегна", np.round(skin, 3), "з", int(band.sum()))
# м'який край
soft = mask.copy()
for _ in range(3):
    soft = (soft + np.roll(soft, 1, 0) + np.roll(soft, -1, 0) + np.roll(soft, 1, 1)
            + np.roll(soft, -1, 1)) / 5
soft = np.maximum(soft, mask)[..., None]
# легка нерівність, щоб пляма не була пласкою
rng = np.random.default_rng(7)
noise = (rng.normal(0, 0.012, (H // 16, W // 16, 1))).repeat(16, 0).repeat(16, 1)
fill = np.clip(skin[None, None, :] * (1 + noise), 0, 1)
C[..., :3] = C[..., :3] * (1 - soft) + fill * soft
# --- рубець старих штанин виліплено в сітці: згладжуємо смугу навколо нього ---
if ZHLAD > 0:
    import bmesh
    me = body.data
    bm = bmesh.new(); bm.from_mesh(me); bm.verts.ensure_lookup_table()
    Vw = np.array([mw @ v.co for v in bm.verts])
    band_v = (np.abs(Vw[:, 2] - zhem) < ZHLAD) & (np.abs(Vw[:, 0]) > 0.04)
    idx = np.nonzero(band_v)[0]
    nbr = [[e.other_vert(bm.verts[i]).index for e in bm.verts[i].link_edges] for i in idx]
    co = np.array([v.co[:] for v in bm.verts])
    orig = co.copy()
    for _ in range(25):
        new = co.copy()
        for k, i in enumerate(idx):
            if nbr[k]:
                avg = co[nbr[k]].mean(axis=0)
                # слабше біля країв смуги
                w = 0.5 * (1 - abs(Vw[i, 2] - zhem) / ZHLAD)
                new[i] = co[i] + w * (avg - co[i])
        co = new
    delta = co - orig
    bm.free()
    if me.shape_keys:
        for kb in me.shape_keys.key_blocks:
            d = np.array([p.co[:] for p in kb.data]) + delta
            kb.data.foreach_set("co", d.ravel())
    me.vertices.foreach_set("co", (orig + delta).ravel())
    me.update()
    print("[труси] рубець z=%.3f: згладжено %d вершин, найбільший зсув %.1f мм"
          % (zhem, len(idx), 1000 * np.linalg.norm(delta, axis=1).max()))
newname = tex.image.name + "-труси"
img = bpy.data.images.new(newname, W, H, alpha=True)
img.pixels.foreach_set(C.ravel())
img.pack()
tex.image = img
if nrm is not None:
    N = np.array(nrm.image.pixels[:], dtype=np.float32).reshape(H, W, 4)
    N[..., :3] = N[..., :3] * (1 - soft) + np.array([0.5, 0.5, 1.0]) * soft
    nimg = bpy.data.images.new(nrm.image.name + "-труси", W, H, alpha=True)
    nimg.colorspace_settings.name = nrm.image.colorspace_settings.name
    nimg.pixels.foreach_set(N.ravel())
    nimg.pack()
    nrm.image = nimg
bpy.data.images.remove(pos)
bpy.data.images.remove(dummy)
bpy.ops.wm.save_as_mainfile(filepath=VYHID)
print("[труси] збережено", VYHID)

if OHLIAD:
    # спереду, ззаду і збоку — лише тіло, Eevee
    import mathutils
    for o in bpy.data.objects:
        if o.type == "MESH" and o is not body:
            o.hide_render = True
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = 700, 900
    cam = bpy.data.objects.new("tmp-кам", bpy.data.cameras.new("tmp-кам"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.lens = 50
    if sc.world is None:
        sc.world = bpy.data.worlds.new("світ")
    sc.world.color = (0.5, 0.5, 0.52)
    lt = bpy.data.objects.new("tmp-світло", bpy.data.lights.new("tmp-світло", "SUN"))
    lt.data.energy = 3
    sc.collection.objects.link(lt)
    import os
    from math import radians
    tgt = mathutils.Vector((0, 0, zc + 0.05))
    shots = []
    for i, ang in enumerate([0, 180, 90]):
        a = radians(ang)
        cam.location = tgt + mathutils.Vector((-1.6 * np.sin(a), -1.6 * np.cos(a), 0.1))
        cam.rotation_euler = (tgt - cam.location).to_track_quat("-Z", "Y").to_euler()
        lt.rotation_euler = cam.rotation_euler
        f = OHLIAD.replace(".png", "-%d.png" % i)
        sc.render.filepath = f
        bpy.ops.render.render(write_still=True)
        shots.append(f)
    print("[труси] огляд", shots)
