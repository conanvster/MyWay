"""Орк з нуля, крок 6: волосся й борода окремими сітками (spec/орк-з-нуля.md, 11.11.2026).

Вхід — модель на скелеті (`tools/ork_znulia_skelet.sh` → 5-скелет/орк.blend). Голова — зі
скульпту, тож орієнтири беруться з самої сітки: сфера черепа (центр C, радіус R), кути
довкола C: θ — від переду (0°) до потилиці (180°), φ — від горизонту вгору.

  * зачесане назад — вузькі картки з прозорою текстурою волосинок, три шари;
  * коси — справжнє плетіння: три джгути довкола осі, вісь лягає з-за вуха на груди й
    не заходить у тіло;
  * борода — картки вниз від щелепи, з об'ємом;
  * підклад — темна шкірка під волоссям (щоб крізь картки не світила шкіра).

Колір — нейтрально-світлий у текстурі: гра множить на вибраний (`base_albedo` — чорний).

    blender -b <орк.blend> -P tools/blender/ork_volossia.py -- <вихід.blend> [--маска <png>]
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

A = sys.argv[sys.argv.index("--") + 1:]
VYHID = os.path.abspath(A[0])
random.seed(7)
rng = np.random.default_rng(7)


def arg(k, typ, d):
    return typ(A[A.index(k) + 1]) if k in A else d


def log(*a):
    print("[волосся]", *a)
    sys.stdout.flush()


tilo = bpy.data.objects["Тіло"]
rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
rig.data.pose_position = "REST"
bpy.context.view_layer.update()
me = tilo.data
mw = tilo.matrix_world
bm = bmesh.new()
bm.from_mesh(me)
bm.transform(mw)
bm.normal_update()
bm.verts.ensure_lookup_table()
bm.faces.ensure_lookup_table()
tree = BVHTree.FromBMesh(bm)
gi = tilo.vertex_groups["head"].index
dl = bm.verts.layers.deform.active
HOL = np.array([v[dl].get(gi, 0.0) > 0.5 for v in bm.verts])
P = np.array([v.co[:] for v in bm.verts])
PH = P[HOL]
ZTOP = PH[:, 2].max()
cr = PH[PH[:, 2] > ZTOP - 0.11]
M = np.c_[2 * cr, np.ones(len(cr))]
c4 = np.linalg.lstsq(M, (cr ** 2).sum(1), rcond=None)[0]
C = Vector(c4[:3])
C.x = 0.0
R = float(math.sqrt(c4[3] + (c4[:3] ** 2).sum()))
# профіль по середині: ніс — найдалі вперед; рот — заглибина під носом; підборіддя — низ
ser = PH[np.abs(PH[:, 0]) < 0.012]
i_nis = int(np.argmin(ser[:, 1]))
Z_NIS = float(ser[i_nis, 2])
pid = ser[(ser[:, 2] < Z_NIS - 0.02) & (ser[:, 1] < C.y - 0.5 * R)]
# у орка найдалі вперед не ніс, а губи з іклами: знайдена точка — рівень рота
Z_ROT = Z_NIS
ZHINKA = arg("--стать", str, "ч") == "ж"
if ZHINKA:
    # орчиха без великих ікол: найдалі вперед — ніс, рот на 4,5 см нижче
    Z_ROT = Z_NIS - 0.045
Z_PIDB = Z_ROT - 0.05
vukha = PH[np.abs(PH[:, 0]) > 0.86 * np.abs(PH[:, 0]).max()]
Z_VUKHO = float(vukha[:, 2].mean())
log("череп: C=(%.3f %.3f %.3f) R=%.3f · маківка %.3f · ніс %.3f · підборіддя %.3f · вуха %.3f"
    % (C.x, C.y, C.z, R, ZTOP, Z_NIS, Z_PIDB, Z_VUKHO))


def kuty(p):
    v = p - C
    th = math.degrees(math.atan2(abs(v.x), -v.y))
    ph = math.degrees(math.atan2(v.z, math.hypot(v.x, v.y)))
    return th, ph


# лінія росту волосся: (θ, найнижче φ). Чоло з «мисом» посередині й залисинами на скронях
LINIIA = arg("--лінія", str, "0:30,25:31,50:25,78:14,100:4,125:-10,180:-28" if ZHINKA
             else "0:45,22:53,50:40,78:22,100:12,125:-6,180:-24")
LINIIA = [tuple(float(x) for x in t.split(":")) for t in LINIIA.split(",")]


def nyz_volossia(th):
    for (a, fa), (b, fb) in zip(LINIIA, LINIIA[1:]):
        if a <= th <= b:
            return fa + (fb - fa) * (th - a) / (b - a)
    return LINIIA[-1][1]


def v_skalp(p):
    """0…1: наскільки точка в зоні волосся (м'який край 6°)."""
    th, ph = kuty(p)
    if (p - C).length > R * 1.25:           # вуха
        return 0.0
    return max(0.0, min(1.0, (ph - nyz_volossia(th)) / 6.0))


def v_boroda(p):
    """Борода: щелепа від вух до підборіддя, під нижньою губою, трохи шиї; рот та ікла — ні."""
    th, ph = kuty(p)
    if th > 108 or p.z > Z_VUKHO - 0.005:
        return 0.0
    ax = abs(p.x)
    # верхня межа: під губою посередині; до вух піднімається (бакенбарди)
    verh = Z_ROT - 0.022 + max(0.0, ax - 0.06) * 1.6
    verh = min(verh, Z_VUKHO - 0.015)
    if ax < 0.085 and p.z > Z_ROT - 0.022:
        return 0.0
    niz = Z_PIDB - 0.045
    w = min((verh - p.z) / 0.012, (p.z - niz) / 0.015, (108 - th) / 10.0)
    return max(0.0, min(1.0, w))


if "--маска" in A:
    ca = me.color_attributes.new("зони", "FLOAT_COLOR", "POINT")
    for i, v in enumerate(bm.verts):
        s, b = (v_skalp(v.co), v_boroda(v.co)) if (v.co - C).length < 0.25 else (0, 0)
        ca.data[i].color = (0.55 + 0.45 * s - 0.4 * b, 0.55 - 0.45 * s - 0.3 * b, 0.5 - 0.4 * s + 0.5 * b, 1)
    for mat in me.materials:
        nt = mat.node_tree
        out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
        vc = nt.nodes.new("ShaderNodeVertexColor")
        vc.layer_name = "зони"
        bs = nt.nodes.new("ShaderNodeBsdfDiffuse")
        nt.links.new(vc.outputs[0], bs.inputs[0])
        nt.links.new(bs.outputs[0], out.inputs[0])
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = sc.render.resolution_y = 700
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.9, 0.9, 0.9, 1)
    cam = bpy.data.objects.new("кам", bpy.data.cameras.new("кам"))
    sc.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 0.42
    sc.camera = cam
    ark = np.zeros((700, 2800, 4), np.float32)
    for i, kut in enumerate((0, 50, 90, 180)):
        a = math.radians(kut)
        cam.location = (math.sin(a) * 5, C.y - math.cos(a) * 5, C.z - 0.03)
        cam.rotation_euler = (math.pi / 2, 0, a)
        sc.render.filepath = A[A.index("--маска") + 1] + ".%d.png" % i
        bpy.ops.render.render(write_still=True)
        im = bpy.data.images.load(sc.render.filepath)
        ark[:, i * 700:(i + 1) * 700] = np.array(im.pixels[:], np.float32).reshape(700, 700, 4)
        os.remove(sc.render.filepath)
    o = bpy.data.images.new("a", 2800, 700)
    o.pixels = ark.ravel()
    o.filepath_raw = A[A.index("--маска") + 1]
    o.file_format = "PNG"
    o.save()
    sys.exit(0)


# ── пасма: ріст по поверхні ──────────────────────────────────────────
def poverkhnia(p):
    """Найближча точка тіла, нормаль і висота точки над поверхнею (зі знаком)."""
    s_, n_, _, _ = tree.find_nearest(p)
    return s_, n_, (p - s_).dot(n_)


def koreni(vaga, n, mat_i=1):
    """n коренів на гранях голови, де vaga(p) > 0, пропорційно площі й вазі."""
    fs, ws = [], []
    for f in bm.faces:
        if f.material_index != mat_i:
            continue
        w = vaga(f.calc_center_median())
        if w > 0.05:
            fs.append(f)
            ws.append(w * f.calc_area())
    if not fs:
        return []
    ws = np.array(ws)
    out = []
    for i in rng.choice(len(fs), n, p=ws / ws.sum()):
        f = fs[i]
        a, b = sorted((random.random(), random.random()))
        v = [x.co for x in f.verts]
        out.append((v[0] * a + v[1] * (b - a) + v[2] * (1 - b), f.normal.copy()))
    return out


def rist(p0, n0, pole, dovzh, pidiom, krok=0.012, vilno=0.0):
    """Пасмо від кореня: напрям — поле `pole(p, t)`, спроєктоване на поверхню; висота над
    шкірою не менша за `pidiom(t)`; з t > `vilno` пасмо може відійти від тіла (борода)."""
    pts = [p0 + n0 * 0.001]
    p = pts[0].copy()
    d = None
    n_kr = max(3, int(dovzh / krok))
    for k in range(1, n_kr + 1):
        t = k / n_kr
        s_, n_, h = poverkhnia(p)
        f = pole(p, t)
        if t <= vilno or vilno <= 0:
            f = f - n_ * f.dot(n_)
        if f.length < 1e-4:
            f = Vector((0, 0, -1)) - n_ * n_.z
        f.normalize()
        d = f if d is None else (d * 0.55 + f * 0.45).normalized()
        q = p + d * krok
        s_, n_, h = poverkhnia(q)
        hm = pidiom(t)
        if h < hm or t <= vilno or vilno <= 0:
            q = s_ + n_ * max(hm, min(h, hm + 0.004) if vilno > 0 and t > vilno else hm)
        pts.append(q)
        p = q
    return pts


def pole_nazad(p, t):
    """Зачесане назад і трохи вниз; на боках — більше вниз-назад."""
    bik = min(1.0, abs(p.x - C.x) / R)
    return Vector((0.12 * math.copysign(bik, p.x), 1.0, -0.25 - 0.9 * bik * bik))


def pole_borody(p, t):
    return Vector((0.10 * (p.x / 0.1), -0.28 + 0.2 * t, -1.0))


def pole_irokez(p, t):
    return Vector((0, 0.55, 1.0))


# ── картки ───────────────────────────────────────────────────────────
SMUHY = ((0, 0.20), (1, 0.20), (2, 0.16), (3, 0.14), (4, 0.11), (5, 0.09), (6, 0.07), (7, 0.03))


def hladka(pts, krok=0.012):
    Pk = [pts[0]] + list(pts) + [pts[-1]]
    out = []
    for i in range(1, len(Pk) - 2):
        p0, p1, p2, p3 = Pk[i - 1], Pk[i], Pk[i + 1], Pk[i + 2]
        n = max(1, int(round((p2 - p1).length / krok)))
        for k in range(n):
            t = k / n
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(pts[-1].copy())
    return out


def ridshe(pts, kut=12.0, maks=0.05):
    if len(pts) < 4:
        return pts
    out = [pts[0]]
    d_ost = (pts[1] - pts[0]).normalized()
    for i in range(1, len(pts) - 1):
        d_n = pts[i + 1] - pts[i]
        if d_n.length < 1e-6:
            continue
        d_n = d_n.normalized()
        if math.degrees(d_ost.angle(d_n, 0.0)) > kut or (pts[i] - out[-1]).length > maks:
            out.append(pts[i])
            d_ost = d_n
    out.append(pts[-1])
    return out


class Sitka:
    """Збирач сітки зачіски: картки (матеріал 0) і джгути кіс та підклад (матеріал 1)."""

    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.uv2 = self.bm.loops.layers.uv.new("UV2")
        self.normali = {}
        self.vagy = {}                 # вершина → частка «грудей» (решта — голова)

    def kartka(self, pts, shyr, okremi=False, vybylas=0.0, husti=False, hrudy=None):
        """`hrudy(p)` → 0…1: частка кістки грудей у вершині (довге волосся нижче плечей)."""
        pts = ridshe(hladka(pts))
        if len(pts) < 3:
            return
        r_ = random.random()
        kol = 0
        for kol, ch in SMUHY:
            r_ -= ch
            if r_ <= 0:
                break
        if husti:
            kol = random.choice((0, 1, 2, 3))
        if okremi:
            kol = random.choice((5, 6, 7))
        u0, du = kol / 8.0, 1.0 / 8.0
        if random.random() < 0.5:
            u0, du = u0 + du, -du
        nid = random.random()
        dovzh = sum((b - a).length for a, b in zip(pts, pts[1:]))
        pro, ryad = 0.0, []
        for i, p in enumerate(pts):
            if i:
                pro += (p - pts[i - 1]).length
            t = pro / max(dovzh, 1e-6)
            tang = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
            _, naz, _ = poverkhnia(p)
            bok = tang.cross(naz)
            if bok.length < 0.1:
                bok = Vector((1, 0, 0))
            bok.normalize()
            w = shyr * (1.0 - 0.35 * t * t)
            p = p + naz * (vybylas * t * t)
            va, vb = self.bm.verts.new(p - bok * w / 2), self.bm.verts.new(p + bok * w / 2)
            nn = naz - tang * naz.dot(tang)
            nn = nn.normalized() if nn.length > 1e-4 else naz
            self.normali[va] = self.normali[vb] = nn
            if hrudy is not None:
                self.vagy[va] = self.vagy[vb] = 0.3 + 0.4 * hrudy(p)
            ryad.append((va, vb, t))
        for (a0, b0, t0), (a1, b1, t1) in zip(ryad, ryad[1:]):
            f = self.bm.faces.new((a0, b0, b1, a1))
            f.smooth = True
            for lp, (u, v), tt in zip(f.loops, ((u0, 1 - t0), (u0 + du, 1 - t0), (u0 + du, 1 - t1), (u0, 1 - t1)),
                                      (t0, t0, t1, t1)):
                lp[self.uv].uv = (u, v)
                lp[self.uv2].uv = (nid, 1 - tt)

    def pidklad(self, vaga, uv_potoku, porih=0.8, vidstup=0.0012):
        """Шар під волоссям: грані голови в зоні, трохи над шкірою, з малюнком волокон уздовж
        напряму волосся (`uv_potoku(p)`), матовий — щоб не читався «шоломом»."""
        nove = {}
        for f in bm.faces:
            if f.material_index != 1 or min(vaga(v.co) for v in f.verts) < porih:
                continue
            vs = []
            for v in f.verts:
                if v not in nove:
                    nove[v] = self.bm.verts.new(v.co + v.normal * vidstup)
                    self.normali[nove[v]] = v.normal.copy()
                vs.append(nove[v])
            nf = self.bm.faces.new(vs)
            nf.smooth = True
            nf.material_index = 1
            for lp, v in zip(nf.loops, f.verts):
                lp[self.uv].uv = uv_potoku(v.co)
                lp[self.uv2].uv = (0, 0)

    def kosa(self, vis, r0=0.0085, r1=0.0055, krok=0.006, sektoriv=5):
        """Плетіння з трьох джгутів довкола осі `vis` (точки з рівним кроком)."""
        vis = hladka(vis, krok)
        n = len(vis)
        dov = [0.0]
        for a, b in zip(vis, vis[1:]):
            dov.append(dov[-1] + (b - a).length)
        L = dov[-1]
        faza0 = random.uniform(0, 6.28)
        kiltsia = [[], [], []]
        for i, p in enumerate(vis):
            t = dov[i] / L
            T = (vis[min(i + 1, n - 1)] - vis[max(i - 1, 0)]).normalized()
            _, naz, _ = poverkhnia(p)
            N = naz - T * naz.dot(T)
            N = N.normalized() if N.length > 1e-3 else T.orthogonal().normalized()
            B = T.cross(N).normalized()
            rr = (r0 + (r1 - r0) * t) * min(1.0, 0.35 + t * 12.0) * min(1.0, 0.25 + (1 - t) * 10.0)
            fz = faza0 + dov[i] / (rr * 5.2) * 2 * math.pi / 2
            for j in range(3):
                f_ = fz + j * 2 * math.pi / 3
                c = p + B * (0.78 * rr * math.sin(f_)) + N * (0.42 * rr * math.sin(2 * f_))
                # дотична джгута — для кілець
                dT = (T + B * (0.78 * math.cos(f_) * 0.6) + N * (0.84 * math.cos(2 * f_) * 0.6)).normalized()
                a_ = dT.cross(N).normalized()
                b_ = dT.cross(a_).normalized()
                kil = []
                for s_i in range(sektoriv):
                    al = 2 * math.pi * s_i / sektoriv
                    nn = a_ * math.cos(al) + b_ * math.sin(al)
                    v = self.bm.verts.new(c + nn * rr * 0.62)
                    self.normali[v] = nn
                    self.vagy[v] = t
                    kil.append(v)
                kiltsia[j].append((kil, dov[i]))
        for j in range(3):
            u_zs = random.random()
            for (k0, d0), (k1, d1) in zip(kiltsia[j], kiltsia[j][1:]):
                for s_i in range(sektoriv):
                    s2 = (s_i + 1) % sektoriv
                    f = self.bm.faces.new((k0[s_i], k0[s2], k1[s2], k1[s_i]))
                    f.smooth = True
                    f.material_index = 1
                    ua, ub = u_zs + s_i / sektoriv * 0.5, u_zs + (s_i + 1) / sektoriv * 0.5
                    va_, vb_ = 0.06 + d0 * 9.0, 0.06 + d1 * 9.0
                    for lp, uvv in zip(f.loops, ((ua, va_), (ub, va_), (ub, vb_), (ua, vb_))):
                        lp[self.uv].uv = uvv
                        lp[self.uv2].uv = (0, 0)

    def obiekt(self, imia, maty):
        self.bm.verts.index_update()
        nlist = [tuple(self.normali.get(v, v.normal)) for v in self.bm.verts]
        vg = [self.vagy.get(v, 0.0) for v in self.bm.verts]
        m = bpy.data.meshes.new(imia)
        self.bm.to_mesh(m)
        self.bm.free()
        m.normals_split_custom_set_from_vertices(nlist)
        for mt_ in maty:
            m.materials.append(mt_)
        o = bpy.data.objects.new(imia, m)
        bpy.context.scene.collection.objects.link(o)
        gh = o.vertex_groups.new(name="head")
        gs = o.vertex_groups.new(name="spine_03")
        for i, w in enumerate(vg):
            # коса: верх тримається голови, нижня половина — грудей
            ws = max(0.0, min(1.0, (w - 0.3) / 0.4))
            gh.add([i], 1.0 - ws, "REPLACE")
            if ws > 0:
                gs.add([i], ws, "REPLACE")
        o.parent = rig
        md = o.modifiers.new("Armature", "ARMATURE")
        md.object = rig
        log("%s: вершин %d, трикутників %d" % (imia, len(m.vertices), sum(len(p.vertices) - 2 for p in m.polygons)))
        return o


# ── текстури ─────────────────────────────────────────────────────────
KOLIR = np.array((0.93, 0.92, 0.90), np.float32)


def atlas_volosynok():
    """2048², 8 смуг: густі → рідкі → окремі волосини; між волосинами прозоро."""
    W = H = 2048
    img = np.zeros((H, W, 4), np.float32)
    g = np.random.default_rng(11)
    yy = np.arange(H, dtype=np.float32)
    sw = W // 8
    for s_i, (n_vol, rozkyd) in enumerate(((70, 0.42), (70, 0.42), (52, 0.42), (52, 0.44),
                                           (36, 0.44), (36, 0.46), (16, 0.46), (7, 0.46))):
        x0 = s_i * sw
        for _ in range(n_vol):
            x = x0 + sw / 2 + float(np.clip(g.normal(0, 0.5), -1, 1)) * sw * rozkyd
            dovzh = g.uniform(0.62, 1.0) if s_i < 6 else g.uniform(0.45, 1.0)
            jas = float(np.clip(g.normal(0.80, 0.17), 0.35, 1.15))
            tovsh = g.uniform(1.6, 3.0)
            faza, amp = g.uniform(0, 6.28), g.uniform(1.0, 5.0) * (1.0 if s_i < 6 else 2.5)
            n = int(H * dovzh)
            t = yy[:n] / H
            xs = x + np.sin(yy[:n] * g.uniform(0.0015, 0.005) + faza) * amp * (0.3 + t)
            kinets = np.clip((dovzh - t) / 0.06, 0, 1)
            for dx in range(-3, 4):
                xi = np.floor(xs).astype(int) + dx
                ok = (xi >= x0 + 1) & (xi < x0 + sw - 1)
                a_ = np.clip(1.25 - np.abs(xi + 0.5 - xs) / (tovsh * 0.5 * (0.5 + 0.5 * kinets)), 0, 1) * kinets
                rows = (H - 1 - yy[:n].astype(int))[ok]
                cols = xi[ok]
                a_ = a_[ok]
                bil = a_ > img[rows, cols, 3]
                img[rows[bil], cols[bil], :3] = KOLIR * jas
                img[rows[bil], cols[bil], 3] = a_[bil]
    img[..., :3] = np.where(img[..., 3:4] > 0.02, img[..., :3], KOLIR * 0.7)
    img[-8:, -8:] = (0.20, 0.19, 0.18, 1.0)          # кут для підкладу (uv 0,998)
    return img


def volokna():
    """512×1024, суцільна: поздовжні волокна джгута коси (плиткою); низ — темний (підклад)."""
    W, H = 512, 1024
    g = np.random.default_rng(5)
    jas = np.clip(g.normal(0.74, 0.2, W), 0.25, 1.1).astype(np.float32)
    jas = np.convolve(np.r_[jas, jas[:8]], np.ones(3) / 3, "same")[:W]
    img = np.zeros((H, W, 4), np.float32)
    hv = 1.0 + 0.10 * np.sin(np.arange(H)[:, None] * 0.05 + g.uniform(0, 6.28, W)[None, :])
    img[..., :3] = (jas[None, :] * hv)[..., None] * KOLIR
    img[..., 3] = 1.0
    return img


def material(imia, img, prozore):
    im = bpy.data.images.new(imia, img.shape[1], img.shape[0], alpha=True)
    im.pixels.foreach_set(img.clip(0, 1).ravel())
    im.pack()
    mat = bpy.data.materials.new(imia)
    mat.use_nodes = True
    nt = mat.node_tree
    b = nt.nodes["Principled BSDF"]
    tx = nt.nodes.new("ShaderNodeTexImage")
    tx.image = im
    kol = nt.nodes.new("ShaderNodeMix")        # множник кольору → baseColorFactor у glTF
    kol.data_type = "RGBA"
    kol.blend_type = "MULTIPLY"
    kol.inputs[0].default_value = 1.0
    kol.inputs[7].default_value = (0.07, 0.06, 0.055, 1)       # чорне волосся орка
    nt.links.new(tx.outputs["Color"], kol.inputs[6])
    nt.links.new(kol.outputs[2], b.inputs["Base Color"])
    if prozore:
        nt.links.new(tx.outputs["Alpha"], b.inputs["Alpha"])
    b.inputs["Roughness"].default_value = 0.62 if prozore else 0.85
    mat.use_backface_culling = False
    return mat


def uv_nazad(p):
    return (math.atan2(p.x, p.z - C.z + 0.02) / (2 * math.pi) * 9.0, p.y / 0.22 - p.z * 1.2)


def uv_vnyz(p):
    return (math.atan2(p.x, -(p.y - C.y)) / (2 * math.pi) * 10.0, -p.z / 0.2)


LYSHE_BORODY = "--лише-бороди" in A
if LYSHE_BORODY and "Волосся-пасма" in bpy.data.materials:
    # бороди до готової моделі (19.11.2026): ті самі матеріали, що й у зачісок, — без копій текстур
    MATY = [bpy.data.materials["Волосся-пасма"], bpy.data.materials["Волосся-джгут"]]
else:
    M_KARTKY = material("Волосся-пасма", atlas_volosynok(), True)
    M_DZHGUT = material("Волосся-джгут", volokna(), False)
    MATY = [M_KARTKY, M_DZHGUT]


# ── зачіски ──────────────────────────────────────────────────────────
def zachesane(s, n=arg("--пасом", int, 1700), dovzh=(0.09, 0.16)):
    for sh, (h0, chastka) in enumerate(((0.0015, 0.45), (0.0045, 0.33), (0.008, 0.22))):
        for p0, n0 in koreni(v_skalp, int(n * chastka)):
            ln = random.uniform(*dovzh)
            vyb = random.uniform(0.004, 0.010) if random.random() < 0.04 else 0.0
            pts = rist(p0, n0, pole_nazad, ln, lambda t, h0=h0: h0 + 0.004 * t)
            s.kartka(pts, random.uniform(0.007, 0.012), vybylas=vyb, husti=sh < 2)
    # пушок на лінії росту: короткі окремі волосини
    for p0, n0 in koreni(lambda p: 1.0 if 0.05 < v_skalp(p) < 0.6 else 0.0, int(n * 0.25)):
        pts = rist(p0, n0, pole_nazad, random.uniform(0.025, 0.05), lambda t: 0.001 + 0.003 * t)
        s.kartka(pts, random.uniform(0.004, 0.007), okremi=True)
    s.pidklad(v_skalp, uv_nazad)


def kosy(s, na_bik=3):
    """Коси з-за вуха на груди: вісь через опорні точки, виштовхнута з тіла."""
    for bik in (-1, 1):
        for i in range(na_bik):
            th = math.radians(100 + i * 14)
            ph = math.radians(8 - i * 3)
            d = Vector((bik * math.sin(th) * math.cos(ph), -math.cos(th) * math.cos(ph), math.sin(ph)))
            hit = tree.ray_cast(C + d * 0.4, -d, 0.5)
            if hit[0] is None:
                continue
            korin = hit[0]
            x_gr = bik * (0.085 + 0.045 * i)
            dov_k = 0.30 + 0.05 * (na_bik - 1 - i) + random.uniform(-0.02, 0.02)
            opory = [korin,
                     Vector((bik * (abs(korin.x) + 0.012), korin.y - 0.015, korin.z - 0.05)),
                     Vector((bik * (0.105 + 0.02 * i), C.y - 0.01 - 0.03 * i, Z_PIDB - 0.02)),
                     Vector((x_gr, C.y - 0.10, Z_PIDB - 0.10)),
                     Vector((x_gr, C.y - 0.14, Z_PIDB - 0.10 - (dov_k - 0.18) * 0.55)),
                     Vector((x_gr, C.y - 0.14, Z_PIDB - 0.10 - (dov_k - 0.18)))]
            vis = hladka(opory, 0.008)
            for _ in range(6):
                for k in range(1, len(vis)):
                    s_, n_, h = poverkhnia(vis[k])
                    if h < 0.011:
                        vis[k] = s_ + n_ * 0.011
                for k in range(1, len(vis) - 1):
                    vis[k] = vis[k] * 0.5 + (vis[k - 1] + vis[k + 1]) * 0.25
            for k in range(1, len(vis)):
                s_, n_, h = poverkhnia(vis[k])
                if h < 0.010:
                    vis[k] = s_ + n_ * 0.010
            s.kosa(vis)


def boroda(s, n=arg("--борода", int, 2400)):
    def dovzhyna(p):
        # найдовша під підборіддям, коротша до вух
        return 0.05 + 0.11 * max(0.0, 1.0 - abs(p.x) / 0.11) * max(0.0, min(1.0, (Z_ROT - p.z) / 0.04))
    for sh, (h0, chastka) in enumerate(((0.002, 0.3), (0.007, 0.3), (0.013, 0.22), (0.02, 0.18))):
        for p0, n0 in koreni(v_boroda, int(n * chastka)):
            ln = dovzhyna(p0) * random.uniform(0.75, 1.15)
            pts = rist(p0, n0, pole_borody, ln, lambda t, h0=h0: h0 + 0.016 * math.sin(math.pi * min(1.0, t * 1.2)),
                       krok=0.01, vilno=0.25)
            s.kartka(pts, random.uniform(0.009, 0.014), vybylas=random.uniform(0.0, 0.006), husti=True)
    for p0, n0 in koreni(lambda p: 1.0 if 0.05 < v_boroda(p) < 0.7 else 0.0, int(n * 0.3)):
        pts = rist(p0, n0, pole_borody, random.uniform(0.015, 0.03), lambda t: 0.001 + 0.004 * t, krok=0.008)
        s.kartka(pts, random.uniform(0.004, 0.006), okremi=True)
    s.pidklad(v_boroda, uv_vnyz, porih=0.75)


def boroda_korotka(s, n=arg("--борода", int, 2400)):
    """Коротка борода (19.11.2026, план 15.11 крок 6): та сама зона, що й повна, пасма 1,2–3 см,
    щільно до шкіри."""
    for h0, chastka in ((0.0015, 0.45), (0.004, 0.35), (0.007, 0.2)):
        for p0, n0 in koreni(v_boroda, int(n * chastka)):
            ln = random.uniform(0.012, 0.03) * (0.6 + 0.4 * v_boroda(p0))
            pts = rist(p0, n0, pole_borody, ln, lambda t, h0=h0: h0 + 0.004 * t, krok=0.006)
            s.kartka(pts, random.uniform(0.007, 0.011), husti=True)
    s.pidklad(v_boroda, uv_vnyz, porih=0.75)


def tochky_oblychchia():
    """Точки обличчя MediaPipe (`maski_z_nulia.py`, кадр 1024², 0,30 м) → світ (x, z)."""
    if "--точки" not in A:
        return None
    G = np.load(A[A.index("--точки") + 1])
    hi_ = next(i for i, m_ in enumerate(me.materials) if m_ and m_.name == "шкіра-голова")
    hv = np.zeros(len(P), bool)
    for f in me.polygons:
        if f.material_index == hi_:
            hv[list(f.vertices)] = True
    cz_ = P[hv, 2].max() - 0.13
    cx_ = float(np.median(P[hv, 0]))
    return np.c_[cx_ + (G[:, 0] / 1024 - 0.5) * 0.30, cz_ - (G[:, 1] / 1024 - 0.5) * 0.30]


def vusa(s, F, n=900):
    """Вуса (19.11.2026): між основою носа (точка 2) і верхньою губою (0), до кутиків рота
    (61, 291) і трохи вниз біля них; лише перед обличчя."""
    z_nis, z_guba = F[2, 1], F[0, 1]
    x_kut = (abs(F[61, 0] - F[1, 0]) + abs(F[291, 0] - F[1, 0])) / 2
    x0, z_kut = F[1, 0], (F[61, 1] + F[291, 1]) / 2

    def zona(p):
        if p.y > C.y - 0.4 * R:
            return 0.0
        ax = abs(p.x - x0)
        verh = z_nis - 0.003
        niz = z_guba + 0.001 if ax < x_kut * 0.7 else min(z_guba, z_kut) - 0.010 * (ax / x_kut)
        if ax > x_kut + 0.006:
            return 0.0
        return max(0.0, min(1.0, (verh - p.z) / 0.003, (p.z - niz) / 0.003,
                            (x_kut + 0.006 - ax) / 0.004))

    def pole_vus(p, t):
        bik = 1.0 if p.x > x0 else -1.0
        return Vector((0.55 * bik, -0.25, -0.8)).normalized()
    for h0, chastka in ((0.0015, 0.5), (0.004, 0.5)):
        for p0, n0 in koreni(zona, int(n * chastka)):
            pts = rist(p0, n0, pole_vus, random.uniform(0.012, 0.022), lambda t, h0=h0: h0 + 0.003 * t,
                       krok=0.005)
            s.kartka(pts, random.uniform(0.005, 0.008), husti=True)
    s.pidklad(zona, uv_vnyz, porih=0.6)


def dovhe(s, n=arg("--довгих", int, 800)):
    """Довге пряме волосся (орчиха, 12.11.2026): зачесане назад по черепу й вільно вниз по
    спині до лопаток; із скронь — пасма спереду плечей на груди. Нижче плечей тримається грудей."""
    z_pl = C.z - 0.20

    def hrudy(p):
        return max(0.0, min(1.0, (z_pl - p.z) / 0.10))

    def pole_spyna(p, t):
        if t < 0.14:
            return pole_nazad(p, t)
        return Vector((0.04 * math.copysign(min(1.0, abs(p.x) / 0.1), p.x), 0.10, -1.0))

    def pole_pered(p, t):
        return Vector((0.10 * math.copysign(1.0, p.x), -0.04 - 0.10 * min(1.0, t * 3), -1.0))

    def skronia(p):
        th, ph = kuty(p)
        return v_skalp(p) if 58 < th < 88 and ph < 38 else 0.0

    def potylytsia(p):
        th, ph = kuty(p)
        return v_skalp(p) if th > 80 else 0.0

    for sh, (h0, chastka) in enumerate(((0.002, 0.4), (0.006, 0.33), (0.011, 0.27))):
        for p0, n0 in koreni(potylytsia, int(n * chastka)):
            pts = rist(p0, n0, pole_spyna, random.uniform(0.48, 0.66), lambda t, h0=h0: h0 + 0.012 * t,
                       krok=0.02, vilno=0.14)
            s.kartka(pts, random.uniform(0.012, 0.02), husti=sh < 2, hrudy=hrudy)
        for p0, n0 in koreni(skronia, int(n * 0.24 * chastka)):
            pts = rist(p0, n0, pole_pered, random.uniform(0.40, 0.56), lambda t, h0=h0: h0 + 0.010 * t,
                       krok=0.02, vilno=0.05)
            s.kartka(pts, random.uniform(0.010, 0.016), husti=sh < 2, hrudy=hrudy)


def irokez(s, n=900):
    def smuha(p):
        return v_skalp(p) * max(0.0, 1.0 - abs(p.x) / 0.03)
    for p0, n0 in koreni(smuha, n):
        ln = random.uniform(0.05, 0.09)
        pts = [p0 + n0 * 0.001]
        d = (n0 * 1.0 + Vector((random.uniform(-0.15, 0.15), 0.35, 0.2))).normalized()
        for k in range(1, 5):
            pts.append(pts[-1] + (d + Vector((0, 0.10 * k, 0))).normalized() * ln / 4)
        s.kartka(pts, random.uniform(0.006, 0.010))
    s.pidklad(smuha, uv_nazad, porih=0.5)


if LYSHE_BORODY:
    # лише нові бороди до готової моделі зі зачісками й рисами (7-риси/*.blend)
    for o_ in [o_ for o_ in bpy.data.objects if o_.name in ("Борода-коротка", "Борода-вуса")]:
        bpy.data.objects.remove(o_)
    s = Sitka()
    boroda_korotka(s)
    s.obiekt("Борода-коротка", MATY)
    F_ = tochky_oblychchia()
    if F_ is not None:
        s = Sitka()
        vusa(s, F_)
        s.obiekt("Борода-вуса", MATY)
    bm.free()
    if me.shape_keys:          # риси вимкнено (ключі з elf_rysy.py до 19.11 мали вагу 1)
        for k_ in me.shape_keys.key_blocks:
            k_.value = 0.0
    rig.data.pose_position = "POSE"
    bpy.ops.wm.save_as_mainfile(filepath=VYHID)
    log("→", VYHID)
    sys.exit(0)
s = Sitka()
zachesane(s)
kosy(s)
s.obiekt("Волосся-коси", MATY)
s = Sitka()
zachesane(s, dovzh=(0.07, 0.12))
s.obiekt("Волосся-зачесане", MATY)
s = Sitka()
irokez(s)
s.obiekt("Волосся-ірокез", MATY)
if ZHINKA:
    s = Sitka()
    zachesane(s, dovzh=(0.10, 0.18))
    dovhe(s)
    s.obiekt("Волосся-довге", MATY)
else:
    s = Sitka()
    boroda(s)
    s.obiekt("Борода-повна", MATY)
bm.free()
rig.data.pose_position = "POSE"
bpy.ops.wm.save_as_mainfile(filepath=VYHID)
log("→", VYHID)
