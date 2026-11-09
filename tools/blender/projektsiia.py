"""Деталі з виглядів на 360° — у текстуру й карту нормалей аватара (09.11.2026).

Пілот орка (слово замовника: «так, роби пілот орка …»). Вигляди — рендер
нашої ж основи з 8 кутів, перемальований FLUX (`tools/comfyui/ork_pilot_vydy.py`),
і нормалі Marigold до кожного (`marigold_normals.py`). Камери — ті самі, що
в рендері (ортографічні, кути навколо осі Z, висота й масштаб — за сіткою).

Кожен тексель розгортки MPFB: точка й нормаль на тілі → вага кожного
вигляду (поворот до камери)^3, затулене іншою частиною тіла — геть (промінь
до камери). Світло FLUX запечене в кадр, тож у текстуру йде лише дрібна
деталь (кадр / розмитий кадр — пори, вени, шрами, рельєф м'язів) поверх
базової шкіри; нормалі — теж лише дрібний рельєф (мінус розмита).

    blender -b <pilot.blend> -P tools/blender/projektsiia.py -- <тека видів> <вихід-префікс> \
        <базова шкіра.png> [--розмір 2048] [--кути 0,45,…]
→ <префікс>-шкіра.png, <префікс>-нормалі.png, <префікс>-покриття.png
"""
import math
import sys

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ARGS = sys.argv[sys.argv.index("--") + 1:]
VYDY, PREF, BAZA = ARGS[0], ARGS[1], ARGS[2]


def arg(k, typ, d):
    return typ(ARGS[ARGS.index(k) + 1]) if k in ARGS else d


N = arg("--розмір", int, 2048)
KUTY = [int(k) for k in arg("--кути", str, "0,45,90,135,180,225,270,315").split(",")]

h = bpy.data.objects["Human"]
dg = bpy.context.evaluated_depsgraph_get()
ev = h.evaluated_get(dg)
me = ev.to_mesh()
me.calc_loop_triangles()
mw = h.matrix_world
V = np.array([(mw @ v.co)[:] for v in me.vertices])
VN = np.array([(mw.to_3x3() @ v.normal).normalized()[:] for v in me.vertices])
uvl = me.uv_layers.active.data
T = np.array([t.vertices[:] for t in me.loop_triangles])
TUV = np.array([[uvl[l].uv[:] for l in t.loops] for t in me.loop_triangles])
print("[проєкція] трикутників %d, вершин %d" % (len(T), len(V)))
zmin, zmax = V[:, 2].min(), V[:, 2].max()
SKALA = (zmax - zmin) * 1.12          # як у рендері видів
ZC = (zmax + zmin) / 2
bvh = BVHTree.FromPolygons([tuple(v) for v in V], [tuple(t) for t in T])

# ── растеризація розгортки ──────────────────────────────────────────
tri_id = np.full((N, N), -1, np.int32)
bary = np.zeros((N, N, 3), np.float32)
for i, uv in enumerate(TUV):
    p = uv * N
    x0, y0 = np.floor(p.min(0)).astype(int)
    x1, y1 = np.ceil(p.max(0)).astype(int)
    x0, y0 = max(x0, 0), max(y0, 0)
    x1, y1 = min(x1, N - 1), min(y1, N - 1)
    if x1 < x0 or y1 < y0:
        continue
    xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
    a, b, c = p
    det = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
    if abs(det) < 1e-12:
        continue
    l0 = ((b[1] - c[1]) * (xs - c[0]) + (c[0] - b[0]) * (ys - c[1])) / det
    l1 = ((c[1] - a[1]) * (xs - c[0]) + (a[0] - c[0]) * (ys - c[1])) / det
    l2 = 1 - l0 - l1
    ok = (l0 >= -1e-4) & (l1 >= -1e-4) & (l2 >= -1e-4)
    yy, xx = (ys[ok] - 0.5).astype(int), (xs[ok] - 0.5).astype(int)
    tri_id[yy, xx] = i
    bary[yy, xx] = np.stack([l0[ok], l1[ok], l2[ok]], -1)
yy, xx = np.nonzero(tri_id >= 0)
ti = tri_id[yy, xx]
bc = bary[yy, xx]
P = (V[T[ti]] * bc[..., None]).sum(1)
NR = (VN[T[ti]] * bc[..., None]).sum(1)
NR /= np.linalg.norm(NR, axis=1, keepdims=True) + 1e-9
print("[проєкція] текселів на тілі %d" % len(ti))

# дотичний базис кожного трикутника (для карти нормалей)
e1 = V[T[:, 1]] - V[T[:, 0]]
e2 = V[T[:, 2]] - V[T[:, 0]]
d1 = TUV[:, 1] - TUV[:, 0]
d2 = TUV[:, 2] - TUV[:, 0]
r = 1.0 / np.where(np.abs(d1[:, 0] * d2[:, 1] - d2[:, 0] * d1[:, 1]) < 1e-12, 1e-12,
                   d1[:, 0] * d2[:, 1] - d2[:, 0] * d1[:, 1])
TAN = (e1 * d2[:, 1:2] - e2 * d1[:, 1:2]) * r[:, None]


def chytaty(shliakh):
    img = bpy.data.images.load(shliakh)
    w, hh = img.size
    a = np.array(img.pixels[:], np.float32).reshape(hh, w, img.channels)[::-1, :, :3]
    bpy.data.images.remove(img)
    return a


def probka(img, u, v):
    hh, w = img.shape[:2]
    x = np.clip(u * w - 0.5, 0, w - 1.001)
    y = np.clip(v * hh - 0.5, 0, hh - 1.001)
    x0, y0 = x.astype(int), y.astype(int)
    fx, fy = (x - x0)[:, None], (y - y0)[:, None]
    return (img[y0, x0] * (1 - fx) * (1 - fy) + img[y0, x0 + 1] * fx * (1 - fy)
            + img[y0 + 1, x0] * (1 - fx) * fy + img[y0 + 1, x0 + 1] * fx * fy)


kol = np.zeros((len(ti), 3))
nrm = np.zeros((len(ti), 3))
vaga = np.zeros(len(ti))
for k in KUTY:
    try:
        kadr = chytaty("%s/вид-%03d.png" % (VYDY, k))
        nk = chytaty("%s/нормалі-%03d.png" % (VYDY, k))
    except RuntimeError:
        print("[проєкція] ‼ немає виду", k)
        continue
    rr = math.radians(k)
    do_kam = np.array([math.sin(rr), -math.cos(rr), 0.0])
    pravo = np.array([math.cos(rr), math.sin(rr), 0.0])
    w = np.clip(NR @ do_kam, 0, 1) ** 5
    u = P @ pravo / SKALA + 0.5
    v = 0.5 - (P[:, 2] - ZC) / SKALA
    # затулене іншою частиною тіла (рука перед боком) — геть
    for j in np.nonzero(w > 0.02)[0]:
        o = Vector(P[j] + NR[j] * 0.003 + do_kam * 0.002)
        if bvh.ray_cast(o, Vector(do_kam), 10.0)[0] is not None:
            w[j] = 0.0
    c = probka(kadr, u, v)
    # тло (сірий фон кадру) на краю силуету — не тіло
    tlo = kadr[5:40, 5:40].reshape(-1, 3).mean(0)
    w *= np.clip((np.abs(c - tlo).sum(1) - 0.04) / 0.08, 0, 1)
    n_kam = probka(nk, u, v) * 2 - 1
    n_sv = (pravo[None] * n_kam[:, :1] + np.array([0, 0, 1.0])[None] * n_kam[:, 1:2]
            + do_kam[None] * n_kam[:, 2:3])
    kol += c * w[:, None]
    nrm += n_sv * w[:, None]
    vaga += w
    print("[проєкція] кут %d: текселів з вагою %d" % (k, int((w > 0.05).sum())), flush=True)

ye = vaga > 1e-3
kol[ye] /= vaga[ye, None]
nrm[ye] /= np.linalg.norm(nrm[ye], axis=1, keepdims=True) + 1e-9


def u_kartu(znach, zapovn=0.0):
    a = np.full((N, N, znach.shape[1]), zapovn, np.float32)
    a[yy[ye], xx[ye]] = znach[ye]
    return a


def rozmyty(a, mask, s):
    """Гаусове розмиття лише по покритому (ділення на розмиту маску)."""
    import numpy.fft as F
    k = np.fft.fftfreq(N)
    g = np.exp(-2 * (math.pi * s) ** 2 * (k[None] ** 2 + k[:, None] ** 2))
    m = F.ifft2(F.fft2(mask) * g).real
    out = np.zeros_like(a)
    for ch in range(a.shape[2]):
        out[..., ch] = F.ifft2(F.fft2(a[..., ch] * mask) * g).real / np.maximum(m, 1e-4)
    return out


maska = np.zeros((N, N), np.float32)
maska[yy[ye], xx[ye]] = 1
K = u_kartu(kol)
NK = u_kartu(nrm)
# дрібна деталь кольору: кадр / розмитий кадр (~1,5 % розгортки)
detal = K / np.maximum(rozmyty(K, maska, N * 0.015), 1e-3)
detal = np.clip(detal, 0.75, 1.3)
baza = chytaty(BAZA)
if baza.shape[0] != N:                  # шкіра MPFB 4096 → розмір карти (ціле кратне)
    f = baza.shape[0] // N
    baza = baza[:N * f, :N * f].reshape(N, f, N, f, 3).mean((1, 3))
shkira = np.where(maska[..., None] > 0, baza * detal, baza)

# нормалі: світові → дотичні; лише дрібний рельєф
TBN_t = np.zeros((len(ti), 3))
t_ = TAN[ti]
t_ = t_ - NR * (t_ * NR).sum(1, keepdims=True)
t_ /= np.linalg.norm(t_, axis=1, keepdims=True) + 1e-9
b_ = np.cross(NR, t_)
n_ts = np.stack([(nrm * t_).sum(1), (nrm * b_).sum(1), (nrm * NR).sum(1)], -1)
NTS = u_kartu(n_ts)
NTS_d = NTS - rozmyty(NTS, maska, N * 0.02) + np.array([0, 0, 1.0])
SYLA = 0.7
NTS_d[..., :2] *= SYLA
NTS_d /= np.linalg.norm(NTS_d, axis=2, keepdims=True) + 1e-9
NTS_d = np.where(maska[..., None] > 0, NTS_d, np.array([0, 0, 1.0]))


def zapysaty(a, shliakh):
    img = bpy.data.images.new("out", N, N, alpha=False)
    rgba = np.concatenate([np.clip(a, 0, 1), np.ones((N, N, 1), np.float32)], 2)[::-1]
    img.pixels.foreach_set(rgba.astype(np.float32).ravel())
    img.filepath_raw = shliakh
    img.file_format = "PNG"
    img.save()
    print("[проєкція] →", shliakh)


zapysaty(shkira, PREF + "-шкіра.png")
zapysaty(NTS_d * 0.5 + 0.5, PREF + "-нормалі.png")
zapysaty(np.repeat(maska[..., None], 3, 2), PREF + "-покриття.png")
