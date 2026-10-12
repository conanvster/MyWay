"""Зачіска з сотень пасом (hair cards) під голову скан-аватара (12.10.2026).

Слово замовника: «очікував, що волосся буде складатися з більшої кількості
пасм, як на прикладах різні типи перук»; «крізь поверхню тіла ні одяг, ні
волосся проходити не будуть». Зачіска MakeHuman long01 була кількома
широкими смугами, бічні пасма лежали на плечах спереду й проходили крізь
них у русі.

  1. корені — промені з центру голови на шкіру голови (маківка, потилиця,
     боки над вухами; чоло відкрите), кілька шарів (об'єм);
  2. кожне пасмо «спадає»: крок 1,5 см униз і трохи назад, після кроку —
     відштовхування від тіла (BVH найближча точка, зазор за шаром), тож у
     позі спокою пасма лежать НА плечах і спині, не в них;
  3. пасмо → смужка-картка 0,8–1,6 см, звужена на кінці, лежить уздовж
     поверхні волосся; хвиля й розкид — випадкові на пасмо;
  4. текстура волосинок генерується (сріблясто-біла, прозорість між
     волосинками й на кінцях);
  5. → `<вихід.blend>` з об'єктом «Волосся» (як `mpfb_volossia.py`).

    blender -b -P tools/blender/volossia_pasma.py -- <основа.blend> <вихід.blend>
        [--пасом 520] [--кінці 1.05] [--колір 0.92,0.91,0.88] [--зерно 7]
"""
import math
import os
import random
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ARGS = sys.argv[sys.argv.index("--") + 1:]
OSNOVA, VYKHID = ARGS[0], ARGS[1]


def arg(k, typ, default):
    return typ(ARGS[ARGS.index(k) + 1]) if k in ARGS else default


PASOM = arg("--пасом", int, 1100)
KINTSI = arg("--кінці", float, 1.05)          # висота кінчиків, м
KOLIR = [float(c) for c in arg("--колір", str, "0.92,0.91,0.88").split(",")]
random.seed(arg("--зерно", int, 7))
KROK = 0.015
SHARY = (0.004, 0.009, 0.015)                 # зазор над шкірою — шари об'єму

bpy.ops.wm.open_mainfile(filepath=OSNOVA)
tilo = max([o for o in bpy.context.scene.objects if o.type == "MESH"],
           key=lambda o: len(o.data.vertices))
dg = bpy.context.evaluated_depsgraph_get()
bm_t = bmesh.new()
bm_t.from_mesh(tilo.data)
bm_t.transform(tilo.matrix_world)
tree = BVHTree.FromBMesh(bm_t)
co = np.array([v.co[:] for v in bm_t.verts])
ztop = co[:, 2].max()
hd = co[co[:, 2] > ztop - 0.24]
# центр голови: середина перерізу на висоті очей (вуха поза ±7 см)
zc = ztop - 0.12
sl = hd[(np.abs(hd[:, 2] - zc) < 0.01)]
cx = float(np.median(sl[:, 0]))
sl = sl[np.abs(sl[:, 0] - cx) < 0.07]
cy = float((sl[:, 1].min() + sl[:, 1].max()) / 2)
C = Vector((cx, cy, zc))
PERED = -1.0 if sl[:, 1].min() - cy < -(sl[:, 1].max() - cy) * 0.9 else 1.0
# перед моделі в основі — −Y (як у `elf_osnova.py`)
PERED = -1.0
print("[пасма] центр голови %s, маківка %.3f" % (tuple(round(v, 3) for v in C), ztop))


def na_shkiri(d):
    """Точка шкіри голови в напрямку d від центру (промінь іззовні)."""
    p0 = C + d * 0.4
    hit = tree.ray_cast(p0, -d, 0.5)
    return (hit[0], hit[1]) if hit[0] is not None else (None, None)


def vidshtovhnuty(p, zazor):
    """Якщо точка ближче до тіла за `zazor` (або всередині) — на поверхню
    + зazor уздовж нормалі."""
    loc, nrm, _, dist = tree.find_nearest(p, 0.2)
    if loc is None:
        return p
    v = p - loc
    vseredyni = v.dot(nrm) < 0
    if vseredyni or dist < zazor:
        return loc + nrm * zazor
    return p


def korin_dozvolenyi(d):
    """Напрямок кореня: чоло (перед, нижче 35° від маківки) — ні; вуха й
    обличчя — ні (нижче центру голови спереду/збоку)."""
    vpered = d.y * PERED          # >0 — до обличчя
    vys = d.z                     # 1 — маківка
    if vpered > 0.35 and vys < 0.82:
        return False              # лінія росту на чолі
    if vys < 0.15 and vpered > -0.55:
        return False              # вуха/скроні — лише ззаду нижче
    return vys > -0.35


# 1. Корені.
koreni = []
sproby = 0
while len(koreni) < PASOM and sproby < PASOM * 40:
    sproby += 1
    th = math.acos(random.uniform(-0.35, 1.0))
    ph = random.uniform(0, 2 * math.pi)
    d = Vector((math.sin(th) * math.cos(ph), math.sin(th) * math.sin(ph), math.cos(th)))
    if not korin_dozvolenyi(d):
        continue
    p, n = na_shkiri(d)
    if p is None:
        continue
    shar = SHARY[len(koreni) % len(SHARY)]
    koreni.append((p + n * shar, n, shar))
print("[пасма] коренів %d (спроб %d)" % (len(koreni), sproby))


# 2. Спадання.
def pasmo(p0, n0, zazor):
    pts = [p0.copy()]
    nazad = Vector((0, -PERED, 0))
    # передні корені — зачесані назад через маківку
    vpered = (p0.y - C.y) * PERED > 0.0
    d = ((n0 * 0.3 + nazad * 0.7 + Vector((0, 0, 0.2))) if vpered
         else (n0 * 0.7 + Vector((0, 0, 1)) * 0.3)).normalized()
    kinets = KINTSI + random.uniform(-0.07, 0.05)
    hvylia_f = random.uniform(0, 6.28)
    hvylia_a = random.uniform(0.0, 0.006)
    bik = Vector((random.uniform(-1, 1), 0, 0)) * 0.03
    while len(pts) < 120:
        p = pts[-1]
        # тяжіння, трохи назад, розкид убік, пам'ять напрямку
        d = (d * 0.55 + Vector((0, 0, -1)) * 0.45 + nazad * 0.08 + bik).normalized()
        q = p + d * KROK
        # нижче очей — лише позаду площини вух: не на обличчя й груди
        if q.z < C.z + 0.01 and (q.y - C.y) * PERED > -0.012:
            q.y = C.y - PERED * 0.012
        q = vidshtovhnuty(q, zazor)
        # хвиля поперек
        t = len(pts) * 0.35 + hvylia_f
        q += Vector((math.sin(t), 0, 0)) * hvylia_a
        d = (q - p).normalized() if (q - p).length > 1e-5 else d
        pts.append(q)
        if q.z < kinets:
            break
    return pts


pasma = [pasmo(p, n, z) for p, n, z in koreni]

# 3. Картки.
me = bpy.data.meshes.new("Волосся")
bm = bmesh.new()
uv_l = bm.loops.layers.uv.new("UVMap")
for k_, pts in enumerate(pasma):
    if len(pts) < 4:
        continue
    shyr = random.uniform(0.012, 0.022)
    u0 = random.choice((0.0, 0.25, 0.5, 0.75))        # 4 смуги текстури
    ryad = []
    for i, p in enumerate(pts):
        t = i / (len(pts) - 1)
        tang = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        nazovni = (p - Vector((C.x, C.y, p.z))).normalized()
        if nazovni.length < 0.5:
            nazovni = Vector((0, -PERED, 0))
        bok = tang.cross(nazovni).normalized()
        w = shyr * (1.0 - 0.7 * t * t)
        ryad.append((bm.verts.new(p - bok * w / 2), bm.verts.new(p + bok * w / 2), t))
    for (a0, b0, t0), (a1, b1, t1) in zip(ryad, ryad[1:]):
        f = bm.faces.new((a0, b0, b1, a1))
        for lp, (u, v) in zip(f.loops, ((u0, 1 - t0), (u0 + 0.25, 1 - t0),
                                        (u0 + 0.25, 1 - t1), (u0, 1 - t1))):
            lp[uv_l].uv = (u, v)
bm.to_mesh(me)
bm.free()
vol = bpy.data.objects.new("Волосся", me)
bpy.context.scene.collection.objects.link(vol)
print("[пасма] карток %d, граней %d" % (len(pasma), len(me.polygons)))

# 4. Текстура волосинок: 4 смуги по ширині (u 0…0.25…), кожна — пучок.
W, H = 512, 1024
img = np.zeros((H, W, 4), dtype=np.float32)
rng = np.random.default_rng(11)
for s in range(4):
    x0 = s * W // 4
    for _ in range(46):
        x = x0 + rng.uniform(3, W // 4 - 3)
        dovzh = rng.uniform(0.9, 1.0)
        jas = rng.uniform(0.7, 1.05)
        tovsh = rng.uniform(0.6, 1.6)
        for y in range(int(H * dovzh)):
            xx = x + math.sin(y * 0.01 + x) * 1.5
            for dx in (-1, 0, 1):
                xi = int(xx) + dx
                if x0 <= xi < x0 + W // 4:
                    a = max(0.0, 1.0 - abs(xi - xx) / tovsh)
                    kin = 1.0 - max(0.0, (y / H - (dovzh - 0.06)) / 0.06)
                    a *= kin
                    img[H - 1 - y, xi, :3] = np.maximum(img[H - 1 - y, xi, :3],
                                                        np.array(KOLIR) * jas * a)
                    img[H - 1 - y, xi, 3] = max(img[H - 1 - y, xi, 3], a)
# між волосинками — ледь видима основа смуги (щільність без «дірок»)
osn = np.zeros((H, W), dtype=np.float32)
for s in range(4):
    x0 = s * W // 4
    xx = np.arange(W // 4)
    profil = np.clip(1.0 - np.abs(xx - W / 8) / (W / 8), 0, 1) ** 0.7
    osn[:, x0:x0 + W // 4] = profil[None, :] * 0.85
# кінці прозорі лише в останніх 12% (рядок 0 — низ картинки = кінчик):
# гра відкидає прозоріше за 0,45 — довгий спад «обрізав» 40% пасма
osn *= np.clip(np.linspace(0, 1, H) / 0.12, 0, 1)[:, None]
img[..., 3] = np.maximum(img[..., 3], osn)
img[..., :3] = np.where(img[..., :3] > 0, img[..., :3], np.array(KOLIR) * 0.8)
im = bpy.data.images.new("волосинки", W, H, alpha=True)
im.pixels.foreach_set(img.clip(0, 1).ravel())
im.pack()
mat = bpy.data.materials.new("Волосся-пасма")
mat.use_nodes = True
nt = mat.node_tree
bsdf = nt.nodes["Principled BSDF"]
tex = nt.nodes.new("ShaderNodeTexImage")
tex.image = im
nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
bsdf.inputs["Roughness"].default_value = 0.5
mat.use_backface_culling = False
me.materials.append(mat)
for o in list(bpy.data.objects):
    if o is not vol:
        bpy.data.objects.remove(o)
bpy.ops.wm.save_as_mainfile(filepath=VYKHID)
print("[пасма] →", VYKHID)
