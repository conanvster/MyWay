"""Карти шкіри аватара MPFB для шейдера (П-285, крок 1, 11.11.2026).

    blender -b --factory-startup -P tools/blender/shkira_karty.py -- <модель.glb> [--розмір 2048]

Поруч із моделлю пише (усе — процесор, без генерації):
  <модель>_карти.png    R — затінення в заглибинах (AO), G — «тонке» (вуха, ніс, пальці:
                        1 — світло проходить наскрізь), B — опуклість (0,5 — рівно; чоло,
                        ніс, вилиці > 0,5 — блищать сильніше)
  <модель>_нормалі.png  рельєф із малюнка самої текстури шкіри (зморшки, пори MakeHuman)
і один раз на гру — game/shaders/pory_normal.png (плиткова карта пор).

Значення рахуються по вершинах тіла (промені BVH) і розкладаються в розгортку; розгортка
MakeHuman одна на всі шкіри, тож карти годяться кожній шкірі моделі.
"""
import math
import os
import sys

import bmesh
import bpy
import cv2
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

args = sys.argv[sys.argv.index("--") + 1:]
MODEL = os.path.abspath(args[0])
SIZE = int(args[args.index("--розмір") + 1]) if "--розмір" in args else 2048
BASE = os.path.splitext(MODEL)[0]
PORY = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "game", "shaders",
                    "pory_normal.png")


def log(*a):
    print("[карти]", *a)
    sys.stdout.flush()


def zapys(path, img):
    """cv2.imwrite не бере кирилицю в шляху на всіх збірках — через буфер."""
    ok, buf = cv2.imencode(".png", img)
    assert ok
    with open(path, "wb") as f:
        f.write(buf.tobytes())


def chytaty(path, flags=cv2.IMREAD_COLOR):
    return cv2.imdecode(np.fromfile(path, dtype=np.uint8), flags)


# ── сітка тіла ──────────────────────────────────────────────────────────────
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=MODEL)
meshes = [o for o in bpy.data.objects if o.type == "MESH"
          and not o.name.startswith(("Волосся", "Одяг", "Брови", "Вії", "Борода", "білизна",
                                     "Icosphere", "підклад"))
          and "poly" not in o.name]
body = max(meshes, key=lambda o: len(o.data.vertices))
me = body.data
log("тіло", body.name, len(me.vertices), "вершин")

bm = bmesh.new()
bm.from_mesh(me)
bm.verts.ensure_lookup_table()
bm.faces.ensure_lookup_table()
bm.normal_update()
tree = BVHTree.FromBMesh(bm)
N = len(bm.verts)
co = np.array([v.co[:] for v in bm.verts])
no = np.array([v.normal[:] for v in bm.verts])

rng = np.random.default_rng(7)


def pivsfera(n, k):
    """k напрямків у півсфері довкола n, косинусно зважені."""
    a = Vector((1, 0, 0)) if abs(n.x) < 0.9 else Vector((0, 1, 0))
    t = n.cross(a).normalized()
    b = n.cross(t)
    out = []
    for _ in range(k):
        u, v = rng.random(), rng.random()
        r, ph = math.sqrt(u), 2 * math.pi * v
        out.append((t * (r * math.cos(ph)) + b * (r * math.sin(ph)) + n * math.sqrt(1 - u)).normalized())
    return out


ao = np.ones(N)
thin = np.zeros(N)
AO_D, AO_K = 0.12, 40
TH_D, TH_K = 0.024, 10
for i, v in enumerate(bm.verts):
    n = v.normal
    p = v.co + n * 0.0015
    zakryto = 0.0
    for d in pivsfera(n, AO_K):
        hit = tree.ray_cast(p, d, AO_D)
        if hit[0] is not None:
            zakryto += 1.0 - hit[3] / AO_D
    ao[i] = 1.0 - zakryto / AO_K
    # товщина: промені всередину; коротка дорога наскрізь — тонке місце
    p2 = v.co - n * 0.0015
    ds = []
    for d in pivsfera(-n, TH_K):
        hit = tree.ray_cast(p2, d, TH_D)
        ds.append(hit[3] if hit[0] is not None else TH_D)
    thin[i] = 1.0 - min(1.0, float(np.median(ds)) / TH_D)

# опуклість: зсув вершини від середнього сусідів уздовж нормалі, у частках довжини ребра
conv = np.zeros(N)
for i, v in enumerate(bm.verts):
    if not v.link_edges:
        continue
    nb = [e.other_vert(v) for e in v.link_edges]
    c = sum((w.co for w in nb), Vector()) / len(nb)
    ln = sum(e.calc_length() for e in v.link_edges) / len(v.link_edges)
    conv[i] = (v.co - c).dot(v.normal) / max(ln, 1e-6)


def zhladyty(x, kroky):
    sus = [[e.other_vert(v).index for e in v.link_edges] for v in bm.verts]
    for _ in range(kroky):
        y = x.copy()
        for i, s in enumerate(sus):
            if s:
                y[i] = 0.5 * x[i] + 0.5 * x[s].mean()
        x = y
    return x


ao = zhladyty(ao, 2)
thin = zhladyty(thin, 2)
conv = zhladyty(conv, 6)          # широкі зони (чоло, ніс, вилиці), не кожна грань
conv_n = np.clip(0.5 + conv / (2.5 * np.percentile(np.abs(conv), 95) + 1e-9), 0, 1)
log("AO %.2f…%.2f · тонке > 0,5: %d вершин · опуклість 5/95 %%: %.3f/%.3f" % (
    ao.min(), ao.max(), int((thin > 0.5).sum()), np.percentile(conv, 5), np.percentile(conv, 95)))

# ── у розгортку ─────────────────────────────────────────────────────────────
uvl = bm.loops.layers.uv.active
bmesh.ops.triangulate(bm, faces=bm.faces[:])
bm.faces.ensure_lookup_table()


def u_rozhortku(mat_i, kudy):
    """mat_i — лише грані цього матеріалу (None — усі): модель зі скульпту має окремі
    текстури голови й тіла в тому самому просторі розгортки."""
    img = np.zeros((SIZE, SIZE, 3), np.float32)
    mask = np.zeros((SIZE, SIZE), np.uint8)
    for f in bm.faces:
        if mat_i is not None and f.material_index != mat_i:
            continue
        pts = np.array([[l[uvl].uv.x * SIZE, (1.0 - l[uvl].uv.y) * SIZE] for l in f.loops], np.float32)
        idx = [l.vert.index for l in f.loops]
        x0, y0 = np.floor(pts.min(0)).astype(int) - 1
        x1, y1 = np.ceil(pts.max(0)).astype(int) + 1
        x0, y0, x1, y1 = max(x0, 0), max(y0, 0), min(x1, SIZE - 1), min(y1, SIZE - 1)
        if x1 <= x0 or y1 <= y0:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        a, b, c = pts
        den = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(den) < 1e-9:
            continue
        w0 = ((b[1] - c[1]) * (xs - c[0]) + (c[0] - b[0]) * (ys - c[1])) / den
        w1 = ((c[1] - a[1]) * (xs - c[0]) + (a[0] - c[0]) * (ys - c[1])) / den
        w2 = 1 - w0 - w1
        ins = (w0 >= -0.02) & (w1 >= -0.02) & (w2 >= -0.02)
        if not ins.any():
            continue
        for ch, arr in enumerate((ao, thin, conv_n)):
            val = w0 * arr[idx[0]] + w1 * arr[idx[1]] + w2 * arr[idx[2]]
            sub = img[y0:y1 + 1, x0:x1 + 1, ch]
            sub[ins] = val[ins]
        mask[y0:y1 + 1, x0:x1 + 1][ins] = 255
    # поля островів — розтягнути назовні, щоб на швах і в міпах не лізло тло
    for _ in range(12):
        dil = cv2.dilate(img, np.ones((3, 3), np.uint8))
        mdil = cv2.dilate(mask, np.ones((3, 3), np.uint8))
        nove = (mdil > 0) & (mask == 0)
        img[nove] = dil[nove]
        mask = mdil
    img[mask == 0] = (1.0, 0.0, 0.5)
    img = cv2.GaussianBlur(img, (0, 0), SIZE / 1024.0)
    out = (np.clip(img, 0, 1) * 255).astype(np.uint8)
    zapys(kudy, out[:, :, ::-1])       # cv2 — BGR
    log("→", kudy)


if len(me.materials) > 1:
    for i_, m_ in enumerate(me.materials):
        u_rozhortku(i_, BASE + "_карти-" + m_.name + ".png")
    sys.exit(0)
u_rozhortku(None, BASE + "_карти.png")

# ── рельєф із малюнка текстури шкіри ────────────────────────────────────────
alb = None
for im in bpy.data.images:
    if "diffuse" in im.name or "skin" in im.name.lower():
        p = BASE + "_" + im.name + ".png"
        if os.path.exists(p):
            alb = chytaty(p)
            log("текстура шкіри", os.path.basename(p), alb.shape)
            break
if alb is not None:
    g = cv2.cvtColor(alb, cv2.COLOR_BGR2GRAY).astype(np.float32) / 255.0
    k = g.shape[0] / 2048.0
    # лише дрібне (пори, зморшки, складки): смуга частот, не загальна світлотінь
    h = cv2.GaussianBlur(g, (0, 0), 0.8 * k) - cv2.GaussianBlur(g, (0, 0), 7.0 * k)
    h = cv2.GaussianBlur(h, (0, 0), 0.6 * k)
    sx = cv2.Sobel(h, cv2.CV_32F, 1, 0, ksize=3)
    sy = cv2.Sobel(h, cv2.CV_32F, 0, 1, ksize=3)
    # межі островів і стики JPEG дають різкі гребені — обрізати
    lim = np.percentile(np.abs(sx), 98)
    sx, sy = np.clip(sx, -lim, lim), np.clip(sy, -lim, lim)
    sila = 0.5 / max(lim, 1e-6)
    nx, ny, nz = -sx * sila, sy * sila, np.ones_like(h)      # +Y вгору (OpenGL)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    nrm = np.dstack([nx / ln, ny / ln, nz / ln]) * 0.5 + 0.5
    zapys(BASE + "_нормалі.png", (nrm[:, :, ::-1] * 255).astype(np.uint8))
    log("→", BASE + "_нормалі.png")
else:
    log("‼ текстури шкіри поруч із моделлю не знайдено — _нормалі.png не пишу")

# ── плиткова карта пор (одна на гру) ────────────────────────────────────────
if not os.path.exists(PORY) or "--пори" in args:
    T = 512
    pts = rng.random((900, 2)) * T
    ys, xs = np.mgrid[0:T, 0:T].astype(np.float32)
    d1 = np.full((T, T), 1e9, np.float32)
    d2 = np.full((T, T), 1e9, np.float32)
    for px, py in pts:
        dx = np.abs(xs - px)
        dy = np.abs(ys - py)
        dx = np.minimum(dx, T - dx)        # плитка без шва
        dy = np.minimum(dy, T - dy)
        d = np.sqrt(dx * dx + dy * dy)
        m = d < d1
        d2 = np.where(m, d1, np.minimum(d2, d))
        d1 = np.where(m, d, d1)
    h = (d2 - d1)                          # борозенки між «клітинами» шкіри
    h = h / h.max()
    h = np.minimum(h * 3.0, 1.0)
    pad = np.pad(h, 8, mode="wrap").astype(np.float32)
    pad = cv2.GaussianBlur(pad, (0, 0), 1.0)
    sx = cv2.Sobel(pad, cv2.CV_32F, 1, 0, ksize=3)[8:-8, 8:-8]
    sy = cv2.Sobel(pad, cv2.CV_32F, 0, 1, ksize=3)[8:-8, 8:-8]
    nx, ny, nz = -sx * 2.2, sy * 2.2, np.ones_like(sx)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    nrm = np.dstack([nx / ln, ny / ln, nz / ln]) * 0.5 + 0.5
    zapys(os.path.abspath(PORY), (nrm[:, :, ::-1] * 255).astype(np.uint8))
    log("→", os.path.abspath(PORY))
