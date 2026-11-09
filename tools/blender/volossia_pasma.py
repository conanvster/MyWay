"""Зачіски з пасом-карток (hair cards) під голову скан-аватара (12.10.2026).

Слово замовника: «очікував, що волосся буде складатися з більшої кількості
пасм, як на прикладах різні типи перук»; «крізь поверхню тіла ні одяг, ні
волосся проходити не будуть»; друга ітерація: «додай … зачіски та колір
зачіски» (приклади — напівхвіст з хвилястим низом, напівзібране з косою,
розпущене хвилясте) і «Волосся здається не покриває всю голову».

Стилі (`--стиль`):
  розпущене — довге хвилясте, проділ посередині;
  зачесане  — гладке пряме назад до лопаток (як на кадрі-основі);
  напівхвіст — верх зібраний на потилиці в хвіст, низ і хвіст хвилясті;
  коса      — верх і боки зачесані назад у косу з трьох пасом, низ вільний;
  каре      — коротке до підборіддя, кінці трохи всередину;
  пряме     — орчиха (12.10.2026, приклад замовника — рендер «ORC FEMALE»):
              довге пряме, проділ посередині, бічні пасма частково
              спереду на плечах і грудях, вуха — крізь волосся;
  коси      — орчиха (приклад замовника — орчиха в обладунку): усе
              зачесане назад до потилиці, ззаду три коси.
  коротке   — чоловіча коротка стрижка (09.11.2026, усі раси): пасма
              5–8 см, зачесані назад і вбік, впритул до голови;
  вузол     — орк (кадр вікі): усе зібране у вузол на маківці, з вузла
              короткий хвіст донизу;
  борода    — не зачіска, а борода з вусами окремою сіткою «Борода-…»:
              корені на щелепі, підборідді й над губою, пасма 2–5 см.
Висоти кінчиків — для голови на висоті 1,739 м (людина-жінка); інші раси —
пропорційно своєму зросту.

Спільне:
  1. корені — на сфері черепа (підбір по маківці), лінія росту волосся
     нижче на чолі й скронях, ніж першого разу (маківка була рідкою),
     + «шапка» коротких пасом впритул до шкіри — голова вкрита скрізь;
  2. пасмо росте кроками 1,5 см за полем напрямку стилю; після кожного
     кроку — відштовхування від тіла (BVH, зазор шару), нижче очей —
     лише позаду площини вух (не на обличчя й груди);
  3. пасмо → картка 1,2–2,2 см, звужена на кінці;
  4. текстура волосинок нейтрально-світла: колір задає гра (множник
     матеріалу), тож одна сітка — будь-який колір;
  5. → `<вихід.blend>` з об'єктом «Волосся-<стиль>».

    blender -b -P tools/blender/volossia_pasma.py -- <основа.blend> <вихід.blend>
        [--стиль розпущене] [--пасом 1300] [--зерно 7]
"""
import math
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


STYL = arg("--стиль", str, "розпущене")
PASOM = arg("--пасом", int, 1300)
# Природніше (08.11.2026, пілот MPFB; слово замовника про ельфійок: «додані
# очікувані параметри, але все ще виглядає не природньо»): пасма збиваються
# в пучки до кінчиків, кілька вибиваються, картки вужчі, текстура
# 1024×2048 з тонкими волосинками різного тону й м'якими кінчиками.
PRYRODNE = "--природне" in ARGS
random.seed(arg("--зерно", int, 7))
KOLIR = (0.93, 0.92, 0.90)          # нейтральний: колір — множником у грі
KROK = 0.015
SHARY = (0.004, 0.008, 0.013)
PERED = -1.0                        # перед моделі в основі — −Y
NAZAD = Vector((0, -PERED, 0))
VNYZ = Vector((0, 0, -1))

# Стиль: висота кінчиків (м), хвиля (амплітуда, м; період у кроках),
# розкид, частка «верхніх» коренів, що йдуть у хвіст/косу.
STYLI = {
    # період хвилі 12–18 кроків (18–27 см): 5–8 кроків давали «гофре»
    "розпущене": dict(kintsi=1.02, hv_a=(0.008, 0.016), hv_t=(12.0, 17.0), rozkyd=0.04),
    "зачесане": dict(kintsi=1.22, hv_a=(0.0, 0.002), hv_t=(14.0, 18.0), rozkyd=0.015),
    "напівхвіст": dict(kintsi=1.06, hv_a=(0.008, 0.015), hv_t=(11.0, 15.0), rozkyd=0.035),
    "коса": dict(kintsi=1.12, hv_a=(0.004, 0.010), hv_t=(12.0, 18.0), rozkyd=0.06),
    "каре": dict(kintsi=1.53, hv_a=(0.001, 0.003), hv_t=(7.0, 9.0), rozkyd=0.02),
    "пряме": dict(kintsi=1.12, hv_a=(0.0, 0.002), hv_t=(14.0, 18.0), rozkyd=0.012),
    "коси": dict(kintsi=1.10, hv_a=(0.0, 0.002), hv_t=(12.0, 18.0), rozkyd=0.01),
    "коротке": dict(kintsi=1.55, hv_a=(0.0, 0.001), hv_t=(8.0, 10.0), rozkyd=0.02),
    "вузол": dict(kintsi=1.25, hv_a=(0.0, 0.002), hv_t=(12.0, 18.0), rozkyd=0.01),
    "борода": dict(kintsi=1.40, hv_a=(0.0, 0.001), hv_t=(8.0, 10.0), rozkyd=0.03),
}
S = STYLI[STYL]

bpy.ops.wm.open_mainfile(filepath=OSNOVA)
tilo = max([o for o in bpy.context.scene.objects if o.type == "MESH"],
           key=lambda o: len(o.data.vertices))
bm_t = bmesh.new()
bm_t.from_mesh(tilo.data)
bm_t.transform(tilo.matrix_world)
co = np.array([v.co[:] for v in bm_t.verts])
# Руки в T-позі горизонтальні: пасма лягали на них і стирчали вбік, коли
# руки опускались (проба в грі 12.10). Зіткнення — лише голова й тулуб.
bm_t.verts.ensure_lookup_table()
ztop = co[:, 2].max()
# Межа рук — півширина тулуба під грудьми (0,32…0,38 зросту від маківки,
# нижче опущених кистей у T-позі)
# + 5 см; стала 0,20 м зрізала плечі орчихи, і пасма провалювались у них.
H_T = ztop - co[:, 2].min()
grudy = co[(co[:, 2] < ztop - 0.32 * H_T) & (co[:, 2] > ztop - 0.38 * H_T)]
MEZHA_X = float(np.percentile(np.abs(grudy[:, 0]), 99)) + 0.07 if len(grudy) else 0.20
print("[пасма] межа рук |x| %.3f м" % MEZHA_X)
bmesh.ops.delete(bm_t, geom=[v for v in bm_t.verts if abs(v.co.x) > MEZHA_X], context="VERTS")

# Сфера черепа: вершини верхніх 7 см (вище кінчиків вух).
verkh = co[co[:, 2] > ztop - 0.07]
A = np.c_[2 * verkh, np.ones(len(verkh))]
c4 = np.linalg.lstsq(A, (verkh ** 2).sum(1), rcond=None)[0]
C = Vector(c4[:3])
R = float(math.sqrt(c4[3] + (c4[:3] ** 2).sum()))
# центр голови по висоті очей (для правила «нижче очей — позаду вух»)
ZTOP_REF = 1.739
MASHTAB = ztop / ZTOP_REF
Z_OCHI = ztop - 0.12 * MASHTAB
print("[пасма] стиль %s; череп: центр %s, R %.3f, маківка %.3f"
      % (STYL, tuple(round(v, 3) for v in C), R, ztop))
# Вуха — геть із зіткнень: великі вуха орчихи відштовхували пасма вбік
# (зачіска стирчала); на прикладі замовника вуха проходять крізь волосся.
bm_t.verts.ensure_lookup_table()
vukha = [v for v in bm_t.verts if abs(v.co.x - C.x) > R * 0.75
         and Z_OCHI - 0.08 < v.co.z < Z_OCHI + 0.10 and (v.co - C).length > R + 0.012]
print("[пасма] вершин вух без зіткнень: %d" % len(vukha))
bmesh.ops.delete(bm_t, geom=vukha, context="VERTS")
tree = BVHTree.FromBMesh(bm_t)


def na_shkiri(d):
    p0 = C + d * 0.4
    hit = tree.ray_cast(p0, -d, 0.5)
    return (hit[0], hit[1]) if hit[0] is not None else (None, None)


def vidshtovhnuty(p, zazor):
    loc, nrm, _, dist = tree.find_nearest(p, 0.2)
    if loc is None:
        return p
    if (p - loc).dot(nrm) < 0 or dist < zazor:
        return loc + nrm * zazor
    return p


def korin_dozvolenyi(d):
    """Лінія росту: чоло — до ~40° над горизонталлю, скроні — перед вухами
    вище мочок, ззаду — до потилиці."""
    vpered = d.y * PERED
    vys = d.z
    if vpered > 0.45 and vys < 0.50:
        return False              # чоло
    if vpered > 0.0 and vys < 0.12:
        return False              # скроні/вуха спереду
    if abs(d.x) > 0.80 and vys < 0.28 and vpered > -0.45:
        return False              # вуха
    return vys > -0.45


def koreni(n, shary=SHARY):
    out, sproby = [], 0
    while len(out) < n and sproby < n * 60:
        sproby += 1
        th = math.acos(random.uniform(-0.95, 0.0) if BORODA else random.uniform(-0.45, 1.0))
        ph = random.uniform(0, 2 * math.pi)
        d = Vector((math.sin(th) * math.cos(ph), math.sin(th) * math.sin(ph), math.cos(th)))
        if not korin_dozvolenyi(d):
            continue
        p, nrm = na_shkiri(d)
        if p is None:
            continue
        shar = shary[len(out) % len(shary)]
        out.append((p + nrm * shar, nrm, shar, d))
    return out


def rist(p0, d0, zazor, pole_f, kinets, maks=140, hv=None, zminy=None, vpered=False,
         prylyp=False):
    """Пасмо від p0: напрям — суміш пам'яті й поля `pole_f(p, i)`; хвиля
    поперек; відштовхування від тіла; нижче очей — позаду вух (крім
    `vpered`: бічні пасма стилю «пряме» лягають на плечі й груди)."""
    pts = [p0.copy()]
    d = d0.normalized()
    hv_a = random.uniform(*S["hv_a"]) if hv is None else hv
    hv_t = random.uniform(*S["hv_t"])
    hv_f = random.uniform(0, 6.28)
    bik = Vector((random.uniform(-1, 1), random.uniform(-0.3, 0.3), 0)) * S["rozkyd"]
    for i in range(maks):
        p = pts[-1]
        tsil = pole_f(p, i)
        d = (d * 0.55 + tsil * 0.45 + bik).normalized()
        q = p + d * KROK
        if not vpered and q.z < Z_OCHI + 0.01 and (q.y - C.y) * PERED > -0.012:
            q.y = C.y - PERED * 0.012
        q = vidshtovhnuty(q, zazor)
        if prylyp:
            # коротке й борода: уздовж шкіри, впритул (не стирчить у повітря)
            loc, nrm, _, _ = tree.find_nearest(q, 0.1)
            if loc is not None:
                d_t = d - nrm * d.dot(nrm)
                if d_t.length > 0.2:
                    q = loc + nrm * zazor + d_t.normalized() * KROK * 0.15
                    q = vidshtovhnuty(q, zazor)
                else:
                    break                    # під підборіддям — далі нікуди
        # хвиля поперек напряму, у площині «вбік»
        poperek = d.cross(Vector((0, 0, 1)))
        if poperek.length < 0.2:
            poperek = Vector((1, 0, 0))
        poperek.normalize()
        sila = min(1.0, max(0.0, (Z_OCHI - q.z) / 0.08))   # хвиля нижче вух
        q += poperek * (math.sin(i * 2 * math.pi / hv_t + hv_f)
                        - math.sin((i - 1) * 2 * math.pi / hv_t + hv_f)) * hv_a * sila
        d = (q - p).normalized() if (q - p).length > 1e-5 else d
        if PRYRODNE and not vpered and q.z < Z_OCHI - 0.06 and q.z > p.z - KROK * 0.4:
            # уперлось у плече й не йде вниз — зсковзує назад за спину
            # (інакше пасма збивались на плечах у клапті)
            d = (d * 0.3 + NAZAD * 0.8 + VNYZ * 0.3).normalized()
            q = vidshtovhnuty(p + d * KROK, zazor)
        pts.append(q)
        if q.z < kinets:
            break
    return pts


def pole_vnyz(prodil=True, bik_sila=0.5):
    """Від проділу вбік і вниз; ззаду — вниз за спину. `bik_sila` 0,5 у
    «пряме» розводила пасма коробкою ширше за вуха — там 0,15."""
    def f(p, i):
        v = p - C
        bok = Vector((1 if v.x > 0 else -1, 0, 0)) if prodil else Vector((0, 0, 0))
        if p.z > C.z + R * 0.3:
            return (bok * bik_sila + NAZAD * 0.25 + VNYZ * 0.6).normalized()
        return (VNYZ + NAZAD * 0.12).normalized()
    return f


def pole_nazad():
    """Зачесане назад через маківку, тоді вниз уздовж потилиці."""
    def f(p, i):
        v = p - C
        if v.y * -PERED < R * 0.55 and p.z > C.z - R * 0.2:
            return (NAZAD * 0.8 + VNYZ * 0.35 + Vector((0.15 if v.x > 0 else -0.15, 0, 0))).normalized()
        return (VNYZ + NAZAD * 0.1).normalized()
    return f


def pole_do(T):
    def f(p, i):
        return (T - p).normalized()
    return f


def tochka_potylytsi(vys):
    """Точка на потилиці на висоті `vys` (частка R над центром)."""
    d = (NAZAD * math.sqrt(max(0.0, 1 - vys * vys)) + Vector((0, 0, vys))).normalized()
    p, n = na_shkiri(d)
    return (p if p is not None else C + d * R), (n if n is not None else d)


def khvist(T, n_t, offset, kinets, hv_a, rad0=0.012, rad1=0.035):
    """Пасмо хвоста від резинки T: вісь — униз уздовж спини, перетин
    розширюється, позиція в перетині — `offset` (2D, одиничний круг)."""
    pts = [T + n_t * 0.01]
    p = pts[0].copy()
    hv_t = random.uniform(*S["hv_t"])
    hv_f = random.uniform(0, 6.28)
    vis = p.copy()
    i = 0
    while vis.z > kinets and i < 140:
        i += 1
        vis = vis + (VNYZ * 0.92 + NAZAD * 0.25).normalized() * KROK
        vis = vidshtovhnuty(vis, 0.03)
        t = min(1.0, i / 25.0)
        rad = rad0 + (rad1 - rad0) * t
        q = vis + Vector((offset[0] * rad, offset[1] * rad * 0.6 * -PERED, 0))
        q += Vector((1, 0, 0)) * math.sin(i * 2 * math.pi / hv_t + hv_f) * hv_a * t
        q = vidshtovhnuty(q, 0.008)
        pts.append(q)
    return pts


def kosa(B, kinets, n_pasom):
    """Коса з трьох пасом від B донизу: пасмо k — вісімка зі зсувом фази
    2π/3 (класичне плетіння), у кожному пасмі `n_pasom/3` карток."""
    out = []
    dovzh = B.z - kinets
    krokiv = int(dovzh / KROK)
    for k in range(3):
        for j in range(n_pasom // 3):
            jit = Vector((random.gauss(0, 0.0025), random.gauss(0, 0.0015), 0))
            pts = []
            vis = B.copy()
            for i in range(krokiv):
                vis = vis + (VNYZ * 0.95 + NAZAD * 0.2).normalized() * KROK
                vis = vidshtovhnuty(vis, 0.02)
                t = i * KROK / 0.035 * math.pi          # одна «ланка» — 3,5 см
                faza = t + 2 * math.pi * k / 3
                shyr = 0.016 * (1.0 - 0.45 * i / max(1, krokiv))
                q = vis + Vector((math.sin(faza) * shyr,
                                  -PERED * math.sin(2 * faza) * shyr * 0.35, 0)) + jit
                pts.append(q)
            out.append(pts)
    return out


# ── 1. Корені й пасма за стилем ─────────────────────────────────────────
pasma = []
bez_puchkiv = set()      # коси: своє плетіння, у пучки не збирати
kreslennia = []          # додаткові сітки: резинка
kintsi = ztop - (ZTOP_REF - S["kintsi"]) * MASHTAB
BORODA = STYL == "борода"


def korin_borody(d):
    """Борода: щелепа, підборіддя, щоки нижче вилиць і вуса над губою;
    рот і губи — вільні."""
    vpered = d.y * PERED
    if vpered < -0.15 or d.z > -0.30:
        return False
    rot = vpered > 0.55 and abs(d.x) < 0.30 and -0.62 < d.z < -0.42
    return not rot


def koreni_borody(n):
    """Корені бороди — на шкірі обличчя за кінчиком носа: від-під носа
    (вуса) до-під підборіддя, щоки до вух; губи вільні. Промінь від
    центру черепа сюди не годиться — ззовні влучав у груди й плечі."""
    tv = [(v.co.copy(), v.normal.copy()) for v in bm_t.verts]
    global NIS
    nis = NIS = min((c for c, _ in tv if abs(c.x) < 0.012 and Z_OCHI - 0.09 < c.z < Z_OCHI),
                    key=lambda c: c.y)
    print("[пасма] кінчик носа z %.3f y %.3f" % (nis.z, nis.y))
    out = []

    def mozhna(c):
        dz = nis.z - c.z
        if c.y > C.y + 0.01 or abs(c.x) > R * 0.98:
            return False
        if dz < 0.014 or dz > 0.105:
            return False
        if dz > 0.095 and c.y > nis.y + 0.07:      # під підборіддям — лише спереду
            return False
        if abs(c.x) < 0.030 and 0.026 < dz < 0.056 and c.y < nis.y + 0.045:
            return False                            # губи
        if dz < 0.026 and abs(c.x) > 0.032:
            return False                            # вуса — лише над губою
        if abs(c.x) > 0.03 and dz < 0.03 and abs(c.x) > 0.045:
            return False                            # щоки над кутиками рота
        return True
    # під щелепою (нормаль донизу) — ні: пасма йшли по шиї
    dozv = [(c, nr) for c, nr in tv if mozhna(c) and nr.z > -0.35]
    print("[пасма] вершин під бороду: %d" % len(dozv))
    for i in range(n):
        c, nr = random.choice(dozv)
        jit = Vector((random.gauss(0, 1), random.gauss(0, 1), random.gauss(0, 1))) * 0.002
        shar = 0.0015
        out.append((c + jit + nr * shar, nr, shar, nr))
    return out


vsi = koreni_borody(PASOM) if BORODA else koreni(PASOM)
if STYL in ("розпущене", "каре"):
    for p, n, z, d in vsi:
        pasma.append(rist(p, n * 0.3 + pole_vnyz()(p, 0), z, pole_vnyz(),
                          kintsi + random.uniform(-0.06, 0.04)))
elif STYL == "пряме":
    # бічні корені попереду вуха (≈ третина боків) — спереду на плечі
    for p, n, z, d in vsi:
        vpered = abs(d.x) > 0.45 and d.y * PERED > -0.15 and random.random() < 0.6
        pole = pole_vnyz(bik_sila=0.15) if not vpered else (
            lambda p_, i_, s_=(1 if d.x > 0 else -1): (VNYZ + Vector((s_ * 0.08, PERED * 0.18, 0))).normalized()
            if p_.z > Z_OCHI - 0.15 else (VNYZ + Vector((0, PERED * 0.12, 0))).normalized())
        pasma.append(rist(p, n * 0.3 + pole(p, 0), z, pole,
                          kintsi + random.uniform(-0.05, 0.05) + (0.06 if vpered else 0.0),
                          vpered=vpered))
elif STYL == "коси":
    T, n_t = tochka_potylytsi(-0.1)
    T = T + n_t * 0.006
    for p, n, z, d in vsi:
        pasma.append(rist(p, (T - p).normalized(), z, pole_do(T), -10.0,
                          maks=int((T - p).length / KROK) + 2, hv=0.0))
    for dx in (-0.034, 0.0, 0.034):
        bez_puchkiv.update(range(len(pasma), len(pasma) + 150))
        pasma += kosa(T + n_t * 0.004 + Vector((dx, 0, -0.01 * abs(dx) / 0.034)),
                      kintsi + random.uniform(-0.03, 0.03), 150)
    kreslennia.append(("резинка", T, n_t))
elif STYL == "коротке":
    for p, n, z, d in vsi:
        if d.z < -0.12:
            continue                                # потилиця — до рівня вух
        dovzh = random.randint(2, 4)
        pole = (lambda q, i: (NAZAD * 0.8 + VNYZ * 0.35).normalized()) \
            if d.y * PERED > -0.3 else pole_vnyz(prodil=False)
        pasma.append(rist(p, n * 0.25 + pole(p, 0), z * 0.6, pole, -10.0, maks=dovzh, hv=0.0,
                          prylyp=True))
elif BORODA:
    def pole_borody(p, i):
        return (VNYZ + Vector((0, PERED * 0.15, 0))).normalized()
    for p, n, z, d in vsi:
        if NIS.z - p.z < 0.028:             # вуса: коротко, від середини вбік і вниз
            bik_ = Vector((1 if p.x > 0 else -1, 0, 0))
            pole = (lambda b_: lambda q, i: (VNYZ * 0.6 + b_ * 0.7).normalized())(bik_)
            pasma.append(rist(p, n * 0.3 + pole(p, 0), 0.0025, pole, -10.0, maks=1,
                              hv=0.0, vpered=True))
            continue
        pasma.append(rist(p, n * 0.15 + pole_borody(p, 0), 0.0035, pole_borody,
                          p.z - random.uniform(0.012, 0.022),     # не нижче щелепи
                          maks=3, hv=0.0, vpered=True, prylyp=True))
elif STYL == "вузол":
    T, n_t = tochka_potylytsi(0.75)
    T = T + n_t * 0.006
    for p, n, z, d in vsi:
        pasma.append(rist(p, (T - p).normalized(), z, pole_do(T), -10.0,
                          maks=int((T - p).length / KROK) + 2, hv=0.0))
    for j in range(260):
        ang = random.uniform(0, 2 * math.pi)
        r = math.sqrt(random.random())
        pasma.append(khvist(T, n_t, (r * math.cos(ang), r * math.sin(ang)),
                            kintsi + random.uniform(-0.04, 0.04), 0.002, rad0=0.018, rad1=0.03))
    kreslennia.append(("резинка", T, n_t))
elif STYL == "зачесане":
    for p, n, z, d in vsi:
        pasma.append(rist(p, n * 0.2 + NAZAD, z, pole_nazad(),
                          kintsi + random.uniform(-0.04, 0.03)))
elif STYL in ("напівхвіст", "коса"):
    T, n_t = tochka_potylytsi(0.25 if STYL == "напівхвіст" else 0.0)
    T = T + n_t * 0.006
    for p, n, z, d in vsi:
        verkhni = d.z > 0.15 or (d.y * PERED > -0.2 and d.z > -0.05)
        if verkhni:
            # до резинки: через маківку/боки, притиснуто до голови
            shliakh = rist(p, (T - p).normalized(), z, pole_do(T), -10.0,
                           maks=int((T - p).length / KROK) + 2, hv=0.0)
            if STYL == "напівхвіст":
                ang = random.uniform(0, 2 * math.pi)
                r = math.sqrt(random.random())
                shliakh += khvist(T, n_t, (r * math.cos(ang), r * math.sin(ang)),
                                  kintsi + random.uniform(-0.05, 0.05),
                                  random.uniform(*S["hv_a"]))
            pasma.append(shliakh)
        else:
            pasma.append(rist(p, n * 0.3 + VNYZ, z, pole_vnyz(prodil=False),
                              kintsi + random.uniform(-0.08, 0.04)))
    if STYL == "коса":
        bez_puchkiv.update(range(len(pasma), len(pasma) + 180))
        pasma += kosa(T + n_t * 0.004, kintsi - 0.04, 180)
    # резинка/затискач — тор біля T
    kreslennia.append(("резинка", T, n_t))
# «Шапка»: короткі пасма впритул до шкіри, у напрямку стилю — голова
# вкрита суцільно, крізь картки не світить лисина.
for p, n, z, d in ([] if BORODA else koreni(PASOM // 2, shary=(0.0025,))):
    if STYL == "вузол":
        pole = pole_do(tochka_potylytsi(0.75)[0])
    elif STYL == "коротке":
        pole = (lambda q, i: (NAZAD * 0.8 + VNYZ * 0.35).normalized()) \
            if d.y * PERED > -0.3 else pole_vnyz(prodil=False)
    elif STYL in ("напівхвіст", "коса", "зачесане", "коси"):
        T_ = (tochka_potylytsi(0.25)[0] if STYL != "коси" else tochka_potylytsi(-0.1)[0]) \
            if STYL != "зачесане" else C + NAZAD * R
        pole = pole_do(T_) if STYL != "зачесане" else pole_nazad()
    else:
        pole = pole_vnyz()
    if STYL == "коротке" and d.z < -0.12:
        continue
    pasma.append(rist(p, pole(p, 0), 0.0025, pole, -10.0, maks=3 if STYL == "коротке" else 7,
                      hv=0.0))

# ── 1б. Пучки (--природне) ──────────────────────────────────────────────
# Справжнє волосся лягає пучками: сусідні пасма до кінчиків тягнуться до
# спільного «провідника», корені лишаються де були. 3 % вибиваються.
if PRYRODNE and sum(len(p_) >= 10 for p_ in pasma) >= 20:   # короткі стрижки — без пучків
    from mathutils.kdtree import KDTree
    dovgi = [i for i, p_ in enumerate(pasma)
             if len(p_) >= 10 and i not in bez_puchkiv]
    providni = random.sample(dovgi, max(1, len(dovgi) // 9))
    kd = KDTree(len(providni))
    for j, i in enumerate(providni):
        kd.insert(pasma[i][0], j)
    kd.balance()
    zibrano = 0
    for i in dovgi:
        s_ = pasma[i]
        if i in providni:
            continue
        if random.random() < 0.03:          # вибилось
            for k in range(2, len(s_)):
                t = k / (len(s_) - 1)
                s_[k] = vidshtovhnuty(s_[k] + Vector((random.gauss(0, 1), random.gauss(0, 1),
                                                      random.gauss(0, 0.5))) * 0.006 * t, 0.004)
            continue
        _, j, d_ = kd.find(s_[0])
        g = pasma[providni[j]]
        if d_ > 0.035 or abs(len(g) - len(s_)) > 0.35 * len(s_):
            continue
        zsuv = (s_[0] - g[0]) * 0.3
        sila = random.uniform(0.45, 0.75)
        for k in range(1, len(s_)):
            t = k / (len(s_) - 1)
            tsil = g[min(k, len(g) - 1)] + zsuv
            s_[k] = vidshtovhnuty(s_[k].lerp(tsil, sila * t ** 1.2), 0.004)
        zibrano += 1
    print("[пасма] пучків %d, зібрано пасом %d" % (len(providni), zibrano))

# ── 2. Картки ───────────────────────────────────────────────────────────
IMIA = "Борода-повна" if BORODA else "Волосся-" + STYL
me = bpy.data.meshes.new(IMIA)
bm = bmesh.new()
uv_l = bm.loops.layers.uv.new("UVMap")
for pts in pasma:
    if PRYRODNE and len(pts) > 6:
        # кожна друга точка (3 см на ланку): вигин той самий, граней удвічі менше
        pts = pts[::2] + ([pts[-1]] if (len(pts) - 1) % 2 else [])
    if len(pts) < 3:
        continue
    shyr = random.uniform(0.009, 0.017) if PRYRODNE else random.uniform(0.012, 0.022)
    if STYL == "коротке":
        shyr *= 0.5                                 # короткі картки вужчі
    elif STYL == "борода":
        shyr *= 0.8
    u0 = random.choice((0.0, 0.25, 0.5, 0.75))
    ryad = []
    for i, p in enumerate(pts):
        t = i / (len(pts) - 1)
        tang = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        nazovni = (p - Vector((C.x, C.y, p.z)))
        if nazovni.length < 0.01:
            nazovni = NAZAD.copy()
        nazovni.normalize()
        bok = tang.cross(nazovni)
        if bok.length < 0.1:
            bok = Vector((1, 0, 0))
        bok.normalize()
        w = shyr * (1.0 - 0.7 * t * t)
        ryad.append((bm.verts.new(p - bok * w / 2), bm.verts.new(p + bok * w / 2), t))
    for (a0, b0, t0), (a1, b1, t1) in zip(ryad, ryad[1:]):
        f = bm.faces.new((a0, b0, b1, a1))
        for lp, (u, v) in zip(f.loops, ((u0, 1 - t0), (u0 + 0.25, 1 - t0),
                                        (u0 + 0.25, 1 - t1), (u0, 1 - t1))):
            lp[uv_l].uv = (u, v)
# резинка: тор із 12×6, другий матеріал
for imia, T, n_t in kreslennia:
    vis = n_t.normalized()
    a = vis.orthogonal().normalized()
    b = vis.cross(a).normalized()
    kil = []
    for i in range(12):
        f_ = 2 * math.pi * i / 12
        cen = T + (a * math.cos(f_) + b * math.sin(f_)) * 0.016
        rad = (a * math.cos(f_) + b * math.sin(f_))
        kil.append([bm.verts.new(cen + (rad * math.cos(2 * math.pi * j / 6)
                                        + vis * math.sin(2 * math.pi * j / 6)) * 0.005)
                    for j in range(6)])
    for i in range(12):
        for j in range(6):
            f = bm.faces.new((kil[i][j], kil[(i + 1) % 12][j],
                              kil[(i + 1) % 12][(j + 1) % 6], kil[i][(j + 1) % 6]))
            f.material_index = 1
            for lp in f.loops:
                lp[uv_l].uv = (0.99, 0.99)
bm.to_mesh(me)
bm.free()
vol = bpy.data.objects.new(IMIA, me)
bpy.context.scene.collection.objects.link(vol)
print("[пасма] карток %d, граней %d" % (len(pasma), len(me.polygons)))

# ── 3. Текстура волосинок: 4 смуги-пучки, нейтрально-світла ─────────────
if PRYRODNE:
    # 1024×2048: у смузі ~170 волосинок завширшки 1–2,5 пкс, тон кожної свій
    # (світліші й темніші — глибина без кольору: колір дає гра), кінчики
    # звужуються й тоншають, корінь темніший, легкий вигин.
    W, H = 1024, 2048
    img = np.zeros((H, W, 4), dtype=np.float32)
    rng = np.random.default_rng(11)
    yy = np.arange(H, dtype=np.float32)
    for s in range(4):
        x0 = s * W // 4
        sw = W // 4
        for _ in range(170):
            x = x0 + rng.uniform(4, sw - 4)
            # кожна волосинка коротша/довша, щільніше посередині смуги
            x = x0 + sw / 2 + (x - x0 - sw / 2) * rng.uniform(0.55, 1.0)
            dovzh = rng.uniform(0.70, 1.0)
            jas = float(np.clip(rng.normal(0.85, 0.16), 0.45, 1.15))
            tovsh = rng.uniform(0.7, 1.4)
            faza, amp = rng.uniform(0, 6.28), rng.uniform(0.5, 2.5)
            n = int(H * dovzh)
            xs = x + np.sin(yy[:n] * rng.uniform(0.002, 0.006) + faza) * amp
            t = yy[:n] / H
            kinets = np.clip((dovzh - t) / 0.10, 0, 1)        # звуження до кінця
            for dx in (-2, -1, 0, 1, 2):
                xi = np.floor(xs).astype(int) + dx
                ok = (xi >= x0) & (xi < x0 + sw)
                a_ = np.clip(1.0 - np.abs(xi - xs) / (tovsh * (0.4 + 0.6 * kinets)), 0, 1) * kinets
                rows = (H - 1 - yy[:n].astype(int))[ok]
                cols = xi[ok]
                a_ = a_[ok]
                img[rows, cols, 3] = np.maximum(img[rows, cols, 3], a_)
                c_ = np.array(KOLIR) * jas
                img[rows, cols, :3] = np.maximum(img[rows, cols, :3], c_[None, :] * a_[:, None])
    # підшерсток: тло пучка, щоб крізь картку не світило. Щільне посередині
    # (0,95): гра відкидає прозоріше за 0,45, і на відстані (міп-рівні)
    # тонкі волосинки розмивались нижче — довге волосся зникало на бігу.
    osn = np.zeros((H, W), dtype=np.float32)
    xx = np.arange(W // 4)
    prof = np.clip(1.0 - np.abs(xx - W / 8) / (W / 8 * 0.92), 0, 1) ** 0.45 * 0.95
    for s in range(4):
        osn[:, s * W // 4:(s + 1) * W // 4] = prof[None, :]
    osn *= np.clip(np.linspace(0, 1, H) / 0.10, 0, 1)[:, None]
    img[..., 3] = np.maximum(img[..., 3], osn)
    pid = np.array(KOLIR) * 0.62
    m_ = img[..., 3:4]
    img[..., :3] = np.where(img[..., :3].sum(-1, keepdims=True) > 0, img[..., :3] / np.maximum(m_, 1e-3), pid)
    tin = np.clip(0.70 + 0.30 * np.linspace(0, 1, H) ** 0.6, 0, 1)[::-1]
    img[..., :3] *= tin[:, None, None]
    img[-8:, -8:] = (0.12, 0.11, 0.10, 1.0)
else:
    W, H = 512, 1024
    img = np.zeros((H, W, 4), dtype=np.float32)
    rng = np.random.default_rng(11)
    for s in range(4):
        x0 = s * W // 4
        for _ in range(52):
            x = x0 + rng.uniform(3, W // 4 - 3)
            dovzh = rng.uniform(0.88, 1.0)
            jas = rng.uniform(0.62, 1.05)
            tovsh = rng.uniform(0.6, 1.6)
            for y in range(int(H * dovzh)):
                xx = x + math.sin(y * 0.01 + x) * 1.5
                for dx in (-1, 0, 1):
                    xi = int(xx) + dx
                    if x0 <= xi < x0 + W // 4:
                        a = max(0.0, 1.0 - abs(xi - xx) / tovsh)
                        a *= 1.0 - max(0.0, (y / H - (dovzh - 0.06)) / 0.06)
                        img[H - 1 - y, xi, :3] = np.maximum(img[H - 1 - y, xi, :3],
                                                            np.array(KOLIR) * jas * a)
                        img[H - 1 - y, xi, 3] = max(img[H - 1 - y, xi, 3], a)
    osn = np.zeros((H, W), dtype=np.float32)
    for s in range(4):
        x0 = s * W // 4
        xx = np.arange(W // 4)
        osn[:, x0:x0 + W // 4] = np.clip(1.0 - np.abs(xx - W / 8) / (W / 8), 0, 1)[None, :] ** 0.7 * 0.85
    # кінці прозорі лише в останніх 12%: гра відкидає прозоріше за 0,45
    osn *= np.clip(np.linspace(0, 1, H) / 0.12, 0, 1)[:, None]
    img[..., 3] = np.maximum(img[..., 3], osn)
    # корінь трохи темніший (глибина пучка) — природніше на будь-якому кольорі
    tin = np.clip(0.78 + 0.22 * np.linspace(0, 1, H) ** 0.5, 0, 1)[::-1]
    img[..., :3] = np.where(img[..., :3] > 0, img[..., :3], np.array(KOLIR) * 0.8)
    img[..., :3] *= tin[:, None, None]
    img[-8:, -8:] = (0.12, 0.11, 0.10, 1.0)      # кут для резинки (uv 0,99)
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
mr = bpy.data.materials.new("Резинка")
mr.use_nodes = True
mr.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.05, 0.045, 0.04, 1)
me.materials.append(mr)
for o in list(bpy.data.objects):
    if o is not vol:
        bpy.data.objects.remove(o)
bpy.ops.wm.save_as_mainfile(filepath=VYKHID)
print("[пасма] →", VYKHID)
