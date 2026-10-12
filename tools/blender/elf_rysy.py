"""Риси обличчя ельфійки — форм-ключі (blend shapes) для вибору в грі
(12.10.2026). Слово замовника: «додай … Очі, Вуха, Ніс, Губи … 3 типи
носу, Губ та інш.».

Точки обличчя G (x, z; `avatar_build.py --обличчя` пише `oblychchia-G.npy`
поруч із виходом) → 3D променем спереду. Кожен ключ — гладкі гаусові
зсуви навколо точок (текстура їде разом із вершинами, тож намальовані губи
й очі міняють форму разом із сіткою):

  Ніс-кирпатий, Ніс-з-горбинкою, Ніс-вузький;
  Губи-повні, Губи-тонкі, Губи-усмішка;
  Очі-мигдалеві, Очі-великі, Очі-вузькі;
  Вуха-довгі, Вуха-короткі, Вуха-підняті.

    blender -b -P tools/blender/elf_rysy.py -- <основа.blend> <G.npy> <вихід.blend>
"""
import sys

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

a = sys.argv[sys.argv.index("--") + 1:]
OSNOVA, G_NPY, VYKHID = a[0], a[1], a[2]
PERED = -1.0                      # перед основи — −Y

bpy.ops.wm.open_mainfile(filepath=OSNOVA)
tilo = max([o for o in bpy.context.scene.objects if o.type == "MESH"],
           key=lambda o: len(o.data.vertices))
me = tilo.data
mw = tilo.matrix_world
co = np.array([(mw @ v.co)[:] for v in me.vertices])
dg = bpy.context.evaluated_depsgraph_get()
tree = BVHTree.FromObject(tilo, dg)
inv = mw.inverted()
G = np.load(G_NPY)


def P(i):
    """3D точка обличчя i: промінь спереду в (x, z)."""
    x, z = G[i]
    hit = tree.ray_cast(inv @ Vector((x, PERED * 1.0, z)),
                        (inv.to_3x3() @ Vector((0, -PERED, 0))).normalized(), 2.0)
    return np.array((mw @ hit[0])[:]) if hit[0] is not None else np.array((x, 0.0, z))


x_mid = float(np.median(G[[1, 4, 6, 168, 0, 17, 152], 0]))
hd_y = float(np.median(co[co[:, 2] > G[:, 1].min(), 1]))
pered_m = (co[:, 1] - hd_y) * PERED > -0.01      # передня половина голови


def gaus(c, sigma, lyshe_pered=True):
    w = np.exp(-((co - c) ** 2).sum(1) / (2 * sigma ** 2))
    if lyshe_pered:
        w *= pered_m
    w[w < 1e-3] = 0
    return w


def kliuch(imia, zsuv):
    if me.shape_keys is None:
        tilo.shape_key_add(name="Basis", from_mix=False)
    k = tilo.shape_key_add(name=imia, from_mix=False)
    loc = (inv.to_3x3() @ np.eye(3)).T if False else None
    m3 = np.array(inv.to_3x3())
    d_loc = zsuv @ m3.T
    base = np.array([v.co[:] for v in me.vertices])
    k.data.foreach_set("co", (base + d_loc).ravel())
    print("[риси] %-16s вершин %5d, найбільший зсув %.1f мм"
          % (imia, int((np.abs(zsuv).sum(1) > 1e-5).sum()), np.abs(zsuv).max() * 1000))


VP = np.array([0, PERED, 0])      # уперед
UP = np.array([0, 0, 1.0])


def bik(i):
    return np.array([np.sign(G[i, 0] - x_mid), 0, 0])


# ── Ніс ──
z = np.zeros_like(co)
z += gaus(P(4), 0.007)[:, None] * (UP * 0.0030 - VP * 0.0004)
z += gaus(P(2), 0.005)[:, None] * (UP * 0.0020)
z += gaus(P(1), 0.006)[:, None] * (UP * 0.0018)
kliuch("Ніс-кирпатий", z * 1.7)
z = np.zeros_like(co)
z += gaus((P(197) + P(195)) / 2, 0.006)[:, None] * (VP * 0.0026)
z += gaus(P(4), 0.006)[:, None] * (-UP * 0.0025 + VP * 0.0008)
kliuch("Ніс-з-горбинкою", z * 1.7)
z = np.zeros_like(co)
for i in (98, 327, 129, 358, 48, 278):
    z += gaus(P(i), 0.005)[:, None] * (-bik(i) * 0.0020)
w_ = gaus(P(6), 0.009)
z[:, 0] += -(co[:, 0] - x_mid) * 0.25 * w_
kliuch("Ніс-вузький", z)

# ── Губи ──
gv, gn = (P(0) + P(13)) / 2, (P(14) + P(17)) / 2
z = np.zeros_like(co)
z += gaus(gv, 0.007)[:, None] * (VP * 0.0018 + UP * 0.0008)
z += gaus(gn, 0.007)[:, None] * (VP * 0.0018 - UP * 0.0010)
kliuch("Губи-повні", z * 1.7)
z = np.zeros_like(co)
z += gaus(gv, 0.007)[:, None] * (-VP * 0.0012 - UP * 0.0006)
z += gaus(gn, 0.007)[:, None] * (-VP * 0.0012 + UP * 0.0007)
kliuch("Губи-тонкі", z * 1.7)
z = np.zeros_like(co)
for i in (61, 291):
    z += gaus(P(i), 0.006)[:, None] * (bik(i) * 0.0010 - VP * 0.0005 + UP * 0.0022)
kliuch("Губи-усмішка", z * 1.7)

# ── Очі ──
OKO = ([33, 7, 163, 144, 145, 153, 154, 155, 133, 173, 157, 158, 159, 160, 161, 246],
       [263, 249, 390, 373, 374, 380, 381, 382, 362, 398, 384, 385, 386, 387, 388, 466])
z = np.zeros_like(co)
for zovn in (33, 263):
    z += gaus(P(zovn), 0.005)[:, None] * (UP * 0.0018 + bik(zovn) * 0.0008)
kliuch("Очі-мигдалеві", z)
z = np.zeros_like(co)
z2 = np.zeros_like(co)
for kontur in OKO:
    c = np.mean([P(i) for i in kontur], 0)
    w_ = gaus(c, 0.009)[:, None]
    r = co - c
    r[:, 1] = 0
    z += w_ * r * 0.16
    z2 += w_ * np.c_[np.zeros(len(co)), np.zeros(len(co)), -(co[:, 2] - c[2]) * 0.28]
kliuch("Очі-великі", z)
kliuch("Очі-вузькі", z2)

# ── Вуха: що стирчить за 1,06 радіуса черепа збоку ──
ztop = co[:, 2].max()
verkh = co[co[:, 2] > ztop - 0.07]
A = np.c_[2 * verkh, np.ones(len(verkh))]
c4 = np.linalg.lstsq(A, (verkh ** 2).sum(1), rcond=None)[0]
C = c4[:3]
R = float(np.sqrt(c4[3] + (C ** 2).sum()))
d = np.linalg.norm(co - C, axis=1)
z_lo = G[[234, 454], 1].min() - 0.02
vukho = (d > R * 1.06) & (np.abs(co[:, 0] - C[0]) > R * 0.55) & (co[:, 2] > z_lo) \
    & (co[:, 2] < C[2] + R * 0.9) & (np.abs(co[:, 1] - C[1]) < R * 0.8)
zd, zk, zp = (np.zeros_like(co) for _ in range(3))
for znak in (-1, 1):
    # корінь вуха — точка 234/454 (край обличчя на рівні козелка), без
    # пластини волосся збоку: не далі 7,5 см від кореня
    i_k = 234 if np.sign(G[234, 0] - C[0]) == znak else 454
    k0 = np.array([G[i_k, 0], C[1], G[i_k, 1]])
    blyzko = np.linalg.norm(co - k0, axis=1) < 0.075
    # вухо — над козелком (мочка до 1,5 см нижче); нижче — пасма скану
    # вздовж щоки (перша проба «довгих» тягла їх униз)
    vyshche = co[:, 2] > G[i_k, 1] - 0.015
    # і не попереду козелка: там пасма скану вздовж щоки
    ne_pered = (co[:, 1] - C[1]) * PERED < R * 0.25
    blyzko = blyzko & vyshche & ne_pered
    m = vukho & blyzko & (np.sign(co[:, 0] - C[0]) == znak)
    if m.sum() < 20:
        continue
    tsentr = co[m].mean(0)
    napr = (tsentr - C) / np.linalg.norm(tsentr - C)
    korin = C + (k0 - C) / np.linalg.norm(k0 - C) * R
    r = co - korin
    dist = np.linalg.norm(r, axis=1)
    kinets = min(np.percentile(dist[m], 98), 0.07)
    t = np.clip((dist - 0.008) / max(kinets - 0.008, 1e-3), 0, 1) ** 1.5
    # плавно до 1 у межах вуха й ще 6 мм навколо (без шва біля черепа)
    obl = np.clip(1 - (R * 1.06 - d) / 0.006, 0, 1) * (np.sign(co[:, 0] - C[0]) == znak)
    obl *= (co[:, 2] > z_lo - 0.01) * blyzko
    w_ = (t * obl)[:, None]
    zd += w_ * r * 0.45
    zk += w_ * r * -0.35
    zp += w_ * (UP * 0.018 - VP * 0.004) * (dist / max(kinets, 1e-3))[:, None]
    print("[риси] вухо %+d: вершин %d, довжина %.1f см" % (znak, int(m.sum()), kinets * 100))
kliuch("Вуха-довгі", zd)
kliuch("Вуха-короткі", zk)
kliuch("Вуха-підняті", zp)
bpy.ops.wm.save_as_mainfile(filepath=VYKHID)
print("[риси] →", VYKHID)
