"""Підбір статури MPFB під силуети референсів (02.10.2026).

Модель ставиться в позу кадру (руки опущені), її вершини — точками в маску
спереду (і збоку, якщо є), з тим самим масштабом за зростом, і рахується
IoU з маскою референсу. Покоординатний спуск по повзунках (макро MPFB і
двополюсні цілі) шукає найбільший збіг.

Використання — з `mpfb_avatar.py`: `pidibraty(h, arm, maska_pered,
maska_bik)`.
"""
import math
import os

import bpy
import numpy as np
from mathutils import Vector

try:    # рендер оцінки (`avatar_render`) бере лише постановку пози — без MPFB
    from bl_ext.blender_org.mpfb.services.targetservice import TargetService
    from bl_ext.blender_org.mpfb.entities.objectproperties import \
        HumanObjectProperties
except Exception:   # без MPFB (--factory-startup) — TypeError, не ImportError
    TargetService = HumanObjectProperties = None

N = 384                     # бік маски підбору, пікселів
NAKLADKA = None             # шлях PNG накладки масок (для ока)
MAKRO = ["muscle", "weight", "proportions"]
TSILI = ["torso/torso-scale-horiz", "torso/torso-vshape",
         "torso/torso-scale-depth", "hip/hip-scale-horiz",
         "hip/hip-scale-depth", "neck/neck-scale-horiz",
         "head/head-scale-horiz", "head/head-scale-vert",
         "legs/measure-thigh-circ", "legs/measure-calf-circ",
         "torso/measure-waist-circ", "torso/measure-bust-circ",
         "arms/measure-upperarm-circ", "torso/torso-muscle-dorsi",
         # Постава голови — видно лише в профіль («голова зміщена вперед -
         # треба її трохи вирівняти», замовник 02.10.2026).
         "head/head-trans", "neck/neck-trans",
         # Об'єм спереду-ззаду — видно в профіль (жінка: на кадрі збоку
         # повніша за модель, і підбір довертав профіль до 30°, MPFB-ж4).
         "buttocks/buttocks-volume", "stomach/stomach-pregnant"]
# TSILI_BEZ="a/b,c/d" — цілі поза підбором (жінка: обхват грудей стискав
# груди, замовник: «моделі грудей якісні але незмогли відтворити»).
TSILI = [t for t in TSILI if t not in
         os.environ.get("TSILI_BEZ", "").split(",")]
# Полюси цілей, що звуться не incr/decr: (додатний, від'ємний).
POLIUSY = {"head/head-trans": ("backward", "forward"),
           "neck/neck-trans": ("backward", "forward")}
# Парні (лівий і правий разом): довжина й товщина рук — підбір їх не бачив,
# поки з міри відрізали бічні стовпці, і руки MPFB лишались довшими й
# тоншими за кадр.
TSILI_LR = ["arms/upperarm-scale-vert", "arms/lowerarm-scale-vert",
            "arms/upperarm-scale-horiz", "arms/lowerarm-scale-horiz",
            # Знизу передпліччя й дельти — на кадрі товщі (MPFB-16).
            "arms/lowerarm-muscle", "arms/upperarm-muscle",
            "arms/upperarm-shoulder-muscle"]


# Масштаб — від ступень до рівня ОЧЕЙ (02.10.2026): верх голови на кадрі
# — об'ємна зачіска, у лисої моделі — тім'я, і масштаб «за зростом»
# розтягував модель (обличчя лягало на ~15 px повз очні ямки).
OKO = 0.80                  # очі — на цій частці N над ступнями (+4% поля)


def bez_volossia(m, kadr, vyd):
    """Маска кадру без розпущеного волосся (рядок 0 — низ). Жінка
    02.10.2026: у профіль волосся позаду спини йшло в силует, і підбір
    «добудовував» тулуб, стегна й сідниці (замовник: «у жінки статури не
    схожі»). Профіль: темне вище 70% висоти й позаду середини тулуба; зад:
    темне вище 78% висоти."""
    img = bpy.data.images.load(kadr, check_existing=True)
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    temne = px.reshape(h, w, 4)[..., :3].max(-1) < 0.22
    ys, xs = np.where(m)
    y0, y1 = ys.min(), ys.max() + 1
    vys = y1 - y0
    yy = np.arange(h)[:, None]
    if vyd == "бік":
        tul = (ys > y1 - 0.45 * vys) & (ys < y1 - 0.30 * vys)
        cx = float(np.median(xs[tul]))
        volos = temne & (yy > y0 + 0.70 * vys) & \
            (np.arange(w)[None, :] > cx)
    else:
        volos = temne & (yy > y0 + 0.78 * vys)
    return m & ~volos


def maska_ref(shliakh, oko_y=None, kadr=None, vyd=None):
    """`oko_y` — рівень очей на кадрі, пікселі ЗНИЗУ (None — за зростом)."""
    """Маска кадру → квадрат N×N: масштаб за висотою фігури, центр — за
    габаритом, ступні внизу з полем 4%."""
    img = bpy.data.images.load(shliakh)
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    m = px.reshape(h, w, 4)[..., 0] > 0.5           # рядок 0 — низ
    if kadr:
        m = bez_volossia(m, kadr, vyd)
    ys, xs = np.where(m)
    y0, y1 = ys.min(), ys.max() + 1
    # Центр — за тулубом (рядки 30–45% висоти від маківки), не за габаритом:
    # габарит перекошують підняті розкриті кисті (модель «з'їжджала» вбік).
    vys = y1 - y0
    tul = (ys > y1 - 0.45 * vys) & (ys < y1 - 0.30 * vys)
    cx = float(np.median(xs[tul])) if tul.any() else (xs.min() + xs.max()) / 2
    k = (N * 0.92) / (y1 - y0) if oko_y is None else (N * OKO) / (oko_y - y0)
    out = np.zeros((N, N), bool)
    yy, xx = np.where(m)
    ny = ((yy - y0) * k + N * 0.04).astype(int)
    nx = ((xx - cx) * k + N / 2).astype(int)
    ok = (ny >= 0) & (ny < N) & (nx >= 0) & (nx < N)
    out[ny[ok], nx[ok]] = True
    return out


def _vys_masky(shliakh):
    img = bpy.data.images.load(shliakh, check_existing=True)
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    ys = np.where((px.reshape(h, w, 4)[..., 0] > 0.5).any(1))[0]
    return ys.min(), ys.max() + 1


def maska_modeli(tochky, vis_x, oko_z=None):
    """Точки моделі (x/y, z) → маска N×N тим самим правилом."""
    z = tochky[:, 2]
    x = tochky[:, vis_x]
    z0, z1 = z.min(), z.max()
    k = (N * 0.92) / (z1 - z0) if oko_z is None else (N * OKO) / (oko_z - z0)
    tul = (z > z1 - 0.45 * (z1 - z0)) & (z < z1 - 0.30 * (z1 - z0))
    cx = float(np.median(x[tul])) if tul.any() else (x.min() + x.max()) / 2
    ny = ((z - z0) * k + N * 0.04).astype(int)
    nx = ((x - cx) * k + N / 2).astype(int)
    out = np.zeros((N, N), bool)
    ok = (ny >= 0) & (ny < N) & (nx >= 0) & (nx < N)
    out[ny[ok], nx[ok]] = True
    # Розширити на 1 px — точок тепер густо.
    for _ in range(1):
        out = out | np.roll(out, 1, 0) | np.roll(out, -1, 0) \
            | np.roll(out, 1, 1) | np.roll(out, -1, 1)
    return out


# Що з міри прибрано: смуга вільних шортів (тіла під ними не видно — підбір
# «надував» стегна) і кисті (на кадрі розкриті й підняті, в моделі — інша
# поза). Рядки — частки висоти N (0 — низ), стовпці — від центру.
OBLAST = np.ones((N, N), bool)
_r0, _r1 = int(N * (0.04 + 0.92 * 0.36)), int(N * (0.04 + 0.92 * 0.56))
OBLAST[_r0:_r1, :] = False
# Кисті тепер у позі кадру — у мірі (без них руки лишались закороткими).
# Зачіска: усе вище брів (очі + 4% N) — у моделі її немає (окрема накладка).
OBLAST[int(N * (0.04 + OKO + 0.04)):, :] = False
# Профіль — без вирізу шортів: збоку вони щільні, а без цієї смуги глибина
# стегон «гуляла» до 0,99 (жінка ж9). Лише зачіска.
OBLAST_BIK = np.ones((N, N), bool)
OBLAST_BIK[int(N * (0.04 + OKO + 0.04)):, :] = False


def oko_modeli(h):
    """Рівень очей моделі — центри кубиків `joint-l/r-eye` (маску MPFB на
    час обчислення вимкнено, щоб номери вершин збігались)."""
    mm = [m for m in h.modifiers if m.type == "MASK"]
    for m in mm:
        m.show_viewport = False
    dg = bpy.context.evaluated_depsgraph_get()
    ev = h.evaluated_get(dg)
    me = ev.to_mesh()
    idx = [h.vertex_groups[g].index for g in ("joint-l-eye", "joint-r-eye")]
    zz = [me.vertices[v.index].co.z for v in h.data.vertices
          if any(gr.group in idx for gr in v.groups)]
    ev.to_mesh_clear()
    for m in mm:
        m.show_viewport = True
    return float(np.mean(zz)) * h.matrix_world[2][2] + h.matrix_world[2][3]


def iou(a, b, oblast=None):
    o = OBLAST if oblast is None else oblast
    a, b = a & o, b & o
    return (a & b).sum() / max(1, (a | b).sum())


def postavyty_ruky(arm, kut_vid_vertykali=10.0):
    """Руки — вниз уздовж тіла, як на кадрі (кут від вертикалі, градуси)."""
    from mathutils import Matrix
    # Кисті й ступні — з нуля: їхні повороти відносні й накопичувались би
    # при кожній новій постановці (підбір кута рук ставить позу багато разів).
    for pb_ in arm.pose.bones:
        if pb_.name.split("_")[0] in ("lowerarm", "hand", "foot", "calf", "thumb",
                                      "index", "middle", "ring", "pinky"):
            pb_.matrix_basis.identity()
    bpy.context.view_layer.update()
    for bik, znak in (("l", 1), ("r", -1)):
        pk = arm.pose.bones.get("clavicle_" + bik)
        if pk is not None:
            pk.rotation_mode = "QUATERNION"
            pk.matrix_basis.identity()
            bpy.context.view_layer.update()
            if KLIUCH[0]:
                _krutnuty(arm, pk.name, Vector((0, 1, 0)),
                          math.radians(KLIUCH[0]) * znak)
        pb = arm.pose.bones.get("upperarm_" + bik)
        if pb is None:
            continue
        pb.rotation_mode = "QUATERNION"
        holova = arm.matrix_world @ pb.head
        hvist = arm.matrix_world @ pb.tail
        teper = (hvist - holova).normalized()
        a = math.radians(kut_vid_vertykali)
        # Бік руки — знак X хвоста кістки.
        s = 1 if hvist.x > holova.x else -1
        tsil = Vector((math.sin(a) * s, 0, -math.cos(a)))
        r = teper.rotation_difference(tsil)
        m = pb.matrix.copy()
        t = m.translation.copy()
        m = r.to_matrix().to_4x4() @ m
        m.translation = t
        pb.matrix = m
    bpy.context.view_layer.update()
    postavyty_nohy(arm, KUT_NIH[0])
    postavyty_kysti_stopy(arm)


# Поза кадру, крім кута рук (02.10.2026): на кадрі кисті долонями вперед
# і зап'ястки зігнуті вгору, ступні — носками назовні.
STOPY_NAZOVNI = 18.0


KUT_NIH = [0.0]   # кут стегон до середини (+) чи назовні (−), градуси
KUT_LIKTIA = [0.0]  # передпліччя вгору (+) від лінії плеча, градуси
STOPY = [STOPY_NAZOVNI]  # носки назовні, градуси
KOLINO = [0.0]   # гомілки до середини (+), градуси: на кадрі гомілки ближче
KLIUCH = [0.0]   # ключиці донизу (+), градуси: на кадрі плечі спадисті


def postavyty_nohy(arm, kut):
    _postavyty_stehna(arm, kut)
    if KOLINO[0]:
        for bik, znak in (("l", 1), ("r", -1)):
            if "calf_" + bik in arm.pose.bones:
                arm.pose.bones["calf_" + bik].rotation_mode = "QUATERNION"
                _krutnuty(arm, "calf_" + bik, Vector((0, 1, 0)),
                          math.radians(KOLINO[0]) * znak)


def _postavyty_stehna(arm, kut):
    """Стегна до середини на `kut` градусів (гомілки моделі стояли ширше,
    ніж на кадрі)."""
    from mathutils import Matrix
    for bik, znak in (("l", 1), ("r", -1)):
        pb = arm.pose.bones.get("thigh_" + bik)
        if pb is None:
            continue
        pb.rotation_mode = "QUATERNION"
        pb.matrix_basis.identity()
        bpy.context.view_layer.update()
        m = pb.matrix.copy()
        t = m.translation.copy()
        m = Matrix.Rotation(math.radians(kut * znak), 4, "Y") @ m
        m.translation = t
        pb.matrix = m
    bpy.context.view_layer.update()


PALTSI = ("index", "middle", "ring", "pinky")


def _holova(arm, n):
    return arm.matrix_world @ arm.pose.bones[n].head


def _napryamyty(arm, n, kudy, tsil):
    """Повернути кістку `n` навколо її голови так, щоб напрямок голова→`kudy`
    (точка у світі, зазвичай голова дочірньої кістки) став `tsil`.
    Через голови суглобів, не хвости: імпорт glTF хвости вгадує."""
    pb = arm.pose.bones[n]
    pb.rotation_mode = "QUATERNION"
    hd = _holova(arm, n)
    r = (kudy() - hd).normalized().rotation_difference(tsil.normalized())
    m = pb.matrix.copy()
    t = m.translation.copy()
    m = r.to_matrix().to_4x4() @ m
    m.translation = t
    pb.matrix = m
    bpy.context.view_layer.update()


def _krutnuty(arm, n, vis, kut_rad):
    pb = arm.pose.bones[n]
    from mathutils import Matrix
    m = pb.matrix.copy()
    t = m.translation.copy()
    m = Matrix.Rotation(kut_rad, 4, vis) @ m
    m.translation = t
    pb.matrix = m
    bpy.context.view_layer.update()


def postavyty_kysti_stopy(arm, nazovni=None):
    """Як на кадрі: лікоть прямий, кисть продовжує передпліччя, долоня
    на камеру, великий палець угору, пальці разом і прямі.
    (У спокої MPFB передпліччя дивиться на камеру під ~45°, а стара
    постановка поворотами навколо осей світу ставила кисть сторч —
    руки спереду виходили закороткими, ітерація MPFB-10.)"""
    from mathutils import Matrix
    if nazovni is None:
        nazovni = STOPY[0]
    pbs = arm.pose.bones
    for bik, znak in (("l", 1), ("r", -1)):
        if "lowerarm_" + bik not in pbs:
            continue
        pl = (_holova(arm, "lowerarm_" + bik) -
              _holova(arm, "upperarm_" + bik)).normalized()
        # Лікоть: на кадрі плече трохи вниз, передпліччя — вище (≠ одна
        # пряма; ітерація MPFB-12: руки моделі вище кадрових).
        vg = Vector((0, 0, 1))
        vg_p = (vg - vg.dot(pl) * pl).normalized()
        pleche = (pl + math.tan(math.radians(KUT_LIKTIA[0])) * vg_p) \
            .normalized()
        _napryamyty(arm, "lowerarm_" + bik,
                    lambda: _holova(arm, "hand_" + bik), pleche)
        _napryamyty(arm, "hand_" + bik,
                    lambda: _holova(arm, "middle_01_" + bik), pleche)
        # Крутнути кисть навколо передпліччя: вказівний над мізинцем
        # (долоня на камеру, великий палець угору).
        a_ = _holova(arm, "index_01_" + bik) - _holova(arm, "pinky_01_" + bik)
        vgoru = Vector((0, 0, 1))
        a_p = (a_ - a_.dot(pleche) * pleche).normalized()
        v_p = (vgoru - vgoru.dot(pleche) * pleche).normalized()
        kut = a_p.angle(v_p)
        if a_p.cross(v_p).dot(pleche) < 0:
            kut = -kut
        _krutnuty(arm, "hand_" + bik, pleche, kut)
        # Пальці прямі, уздовж кисті.
        for p_ in PALTSI:
            for i in (1, 2):
                n = "%s_0%d_%s" % (p_, i, bik)
                nx = "%s_0%d_%s" % (p_, i + 1, bik)
                if n in pbs and nx in pbs:
                    _napryamyty(arm, n, lambda nx=nx: _holova(arm, nx), pleche)
            n3 = "%s_03_%s" % (p_, bik)
            if n3 in pbs:
                pb3 = pbs[n3]
                _napryamyty(arm, n3, lambda pb3=pb3: arm.matrix_world @
                            pb3.tail, pleche)
        # Великий — угору й трохи вперед, як на кадрі (≈60° від кисті).
        vel = (0.45 * pleche + Vector((0, -0.3, 0.85))).normalized()
        for i in (1, 2):
            n = "thumb_0%d_%s" % (i, bik)
            nx = "thumb_0%d_%s" % (i + 1, bik)
            if n in pbs and nx in pbs:
                _napryamyty(arm, n, lambda nx=nx: _holova(arm, nx), vel)
        if "thumb_03_" + bik in pbs:
            pb3 = pbs["thumb_03_" + bik]
            _napryamyty(arm, pb3.name, lambda pb3=pb3: arm.matrix_world @
                        pb3.tail, vel)
        pf = pbs.get("foot_" + bik)
        if pf is not None:
            pf.rotation_mode = "QUATERNION"
            m = pf.matrix.copy()
            t = m.translation.copy()
            m = Matrix.Rotation(math.radians(nazovni * znak), 4, "Z") @ m
            m.translation = t
            pf.matrix = m
            bpy.context.view_layer.update()


def tochky_tila(h):
    h.data.update()
    bpy.context.view_layer.update()
    return _tochky_tila(h)


def _tochky_tila(h):
    """Точки поверхні: вершини + центр і середини ребер кожного
    трикутника — маска з самих вершин була діравою (точки рідші за
    пікселі) і занижувала збіг."""
    dg = bpy.context.evaluated_depsgraph_get()
    ev = h.evaluated_get(dg)
    me = ev.to_mesh()
    me.calc_loop_triangles()
    p = np.empty(len(me.vertices) * 3, dtype=np.float64)
    me.vertices.foreach_get("co", p)
    p = p.reshape(-1, 3)
    tri = np.empty(len(me.loop_triangles) * 3, dtype=np.int64)
    me.loop_triangles.foreach_get("vertices", tri)
    ev.to_mesh_clear()
    tri = tri.reshape(-1, 3)
    a_, b_, c_ = p[tri[:, 0]], p[tri[:, 1]], p[tri[:, 2]]
    p = np.concatenate([p, (a_ + b_ + c_) / 3, (a_ + b_) / 2, (b_ + c_) / 2,
                        (a_ + c_) / 2])
    mw = np.array(h.matrix_world)
    return p @ mw[:3, :3].T + mw[:3, 3]


MEZHI_TILA = {"stomach/stomach-pregnant": (-1.0, 0.2),
              "buttocks/buttocks-volume": (-1.0, 0.5),
              "hip/hip-scale-depth": (-1.0, 0.5),
              # −0,87 сплющувало груди й грудну клітку (зл8, зл9)
              "torso/torso-scale-depth": (-0.3, 0.6)}
# Межі макро з оточення: MEZHI_MAKRO="muscle=0.3:0.55,weight=0.4:0.7".
# Жінка: підбір спереду гнав «muscle» до 0,75 — руки й ноги виходили
# атлетичні, на кадрі — м'яка статура (замовник: «статури не схожі»).
MEZHI_MAKRO = {}
for _p in os.environ.get("MEZHI_MAKRO", "").split(","):
    if "=" in _p:
        _k, _v = _p.split("=")
        _a, _b = _v.split(":")
        MEZHI_MAKRO[_k.strip()] = (float(_a), float(_b))


class Povzunky:
    """Двополюсні цілі як пари ключів форми (incr/decr) і макро MPFB."""

    def __init__(self, h):
        self.h = h
        self.kl = {}
        for t in TSILI:
            for kinets, polius in zip(("incr", "decr"),
                                      POLIUSY.get(t, ("incr", "decr"))):
                imia = "%s-%s" % (t.split("/")[-1], polius)
                try:
                    shl = TargetService.target_full_path(imia)
                except Exception:
                    shl = None
                if not shl:
                    continue
                TargetService.load_target(h, shl, weight=0.0, name=imia)
                self.kl[(t, kinets)] = imia
        for t in TSILI_LR:
            for bik in ("l", "r"):
                for kinets in ("incr", "decr"):
                    imia = "%s-%s-%s" % (bik, t.split("/")[-1], kinets)
                    shl = TargetService.target_full_path(imia)
                    if shl:
                        TargetService.load_target(h, shl, weight=0.0, name=imia)
                        self.kl[(t, bik, kinets)] = imia
        self.znach = {t: 0.0 for t in TSILI if (t, "incr") in self.kl}
        for t in TSILI_LR:
            if (t, "l", "incr") in self.kl:
                self.znach[t] = 0.0
        for mk in MAKRO:
            self.znach[mk] = float(HumanObjectProperties.get_value(
                mk, entity_reference=h))

    def postavyty(self, imia, v):
        self.znach[imia] = v
        if imia in MAKRO or imia == "cupsize":
            HumanObjectProperties.set_value(imia, v, entity_reference=self.h)
            TargetService.reapply_macro_details(self.h)
            return
        kb = self.h.data.shape_keys.key_blocks
        if imia in TSILI_LR:
            for bik in ("l", "r"):
                kb[self.kl[(imia, bik, "incr")]].value = max(0.0, v)
                if (imia, bik, "decr") in self.kl:
                    kb[self.kl[(imia, bik, "decr")]].value = max(0.0, -v)
            return
        kb[self.kl[(imia, "incr")]].value = max(0.0, v)
        if (imia, "decr") in self.kl:
            kb[self.kl[(imia, "decr")]].value = max(0.0, -v)

    def mezhi(self, imia):
        if imia in MAKRO or imia == "cupsize":
            return MEZHI_MAKRO.get(imia, (0.0, 1.0))
        # Живіт і сідниці не надувати: профіль Kontext буває повнішим за кадр
        # спереду, і підбір давав жінці живіт і сідниці (замовник 02.10.2026:
        # «у жінки статури не схожі»).
        return MEZHI_TILA.get(imia, (-1.0, 1.0))


# Проходів на крок. Один — повзунок від нуля сягав лише 0,46; п'ять і
# чотири — повзунки тіла йшли в край, пропорції голови до тіла розходились
# і обличчя на оцінці падало до ~0,5…0,64 (MPFB-18…21, 27). Три — найкраще
# на симетричному кадрі (MPFB-24, 29).
PROKHODY = int(os.environ.get("PROKHODY", "3"))


# Профіль Kontext ставить руки вниз уздовж тіла (T-позу збоку він малює
# на три чверті, s911) — тож для профілю й модель так само.
KUT_BIK = 6.0
# Жінка 02.10.2026: «необхідно щов у сих ракурсах було Т» — профіль теж у
# T-позі; тоді модель для профілю стоїть так само, як спереду.
BIK_T = os.environ.get("BIK_T", "") not in ("", "0")


def kut_biku(kut_ruk):
    return kut_ruk if BIK_T else KUT_BIK
# Що видно лише збоку: постава голови й шиї, глибина тулуба, стегон, шиї.
TSILI_BIK = ["head/head-trans", "neck/neck-trans", "torso/torso-scale-depth",
             "hip/hip-scale-depth", "neck/neck-scale-depth",
             "head/head-scale-depth", "buttocks/buttocks-volume",
             "stomach/stomach-pregnant", "cupsize"]


KADR_BIK = [None]    # кольоровий кадр профілю — щоб зняти з маски волосся
PROFIL_KUT = [0.0]   # на скільки «профіль» кадру не рівно 90°, градуси
# Зсув профілю, метри «праворуч у кадрі»: центр за тулубом у профіль
# збивала рука (на кадрі жінки вона висить позаду, у моделі — посередині;
# модель стояла на ~10 px лівіше, MPFB-ж5).
PROFIL_ZSUV = [0.0]
_ZSUV_PX = [0]


def povernuty_profil(p, kut):
    """Точки → (x, «праворуч у кадрі», z) для камери збоку, поверненої на
    `kut`° (0 — рівно на +X). Kontext малює профіль із доворотом до
    глядача на 15–20° — без цього тулуб на кадрі «глибший» за модель."""
    t = math.radians(kut)
    hor = p[:, 0] * math.sin(t) + p[:, 1] * math.cos(t)
    return np.stack([p[:, 0], hor, p[:, 2]], 1)


def pidibraty_profil(h, arm, pv, m_b, z_okom, kut_ruk):
    """Другий етап: модель руками вниз, міра — силует у профіль; повзунки
    лише ті, що спереду не видно (силует спереду вони не міняють)."""
    postavyty_ruky(arm, kut_biku(kut_ruk))
    pv.znach["бік у T-позі"] = 1.0 if BIK_T else 0.0

    def otsinka_b(z_poshukom=False):
        p = povernuty_profil(tochky_tila(h), PROFIL_KUT[0])
        mb_ = maska_modeli(p, 1, oko_modeli(h) if z_okom else None)
        # Без дзеркала: обидва профілі дивляться ліворуч кадру (так рахує й
        # проєкція), і знак кута має значення.
        if z_poshukom:
            kr = max((iou(np.roll(mb_, dx, 1), m_b, OBLAST_BIK), dx)
                     for dx in range(-16, 17, 2))
            _ZSUV_PX[0] = kr[1]
            return kr[0]
        return iou(np.roll(mb_, _ZSUV_PX[0], 1), m_b, OBLAST_BIK)
    naikr, krashchyi = -1, 0.0
    # Лише доворот грудьми до глядача (камера зміщується до −Y, перед
    # моделі): силует сам знака не розрізняє — m33 вибрав −10°, і на бік
    # лягла спина замість грудей (у Kontext профіль завжди трохи грудьми).
    # Не далі 15°: на 30° модель жінки виходила на три чверті, хоча кадр —
    # майже рівний профіль (підбір довертав замість об'єму, MPFB-ж4).
    zs = 0
    for kut in np.arange(0, 15.1, 2.5):
        PROFIL_KUT[0] = kut
        s_ = otsinka_b(True)
        if s_ > naikr:
            naikr, krashchyi, zs = s_, kut, _ZSUV_PX[0]
    PROFIL_KUT[0] = krashchyi
    _ZSUV_PX[0] = zs
    pv.znach["кут профілю"] = krashchyi
    print("[підбір] профіль: кут %+.1f°, початок: %.4f" % (krashchyi, naikr),
          flush=True)
    if "cupsize" not in pv.znach:
        pv.znach["cupsize"] = float(HumanObjectProperties.get_value(
            "cupsize", entity_reference=h))
    # BIK_BEZ — цілі поза профільним підбором (жінка: постава голови й шиї
    # з профілю псувала шию — «некрасиву шию та форму голови»).
    bez_ = os.environ.get("BIK_BEZ", "").split(",")
    imena = [t for t in TSILI_BIK if t in pv.znach and t not in bez_]
    for krok in (0.25, 0.12, 0.06, 0.03):
        for _prokhid in range(PROKHODY):
            bulo = naikr
            for imia in imena:
                lo, hi = pv.mezhi(imia)
                for znak in (1, -1):
                    v0 = pv.znach[imia]
                    v1 = min(hi, max(lo, v0 + znak * krok))
                    if v1 == v0:
                        continue
                    pv.postavyty(imia, v1)
                    s_ = otsinka_b()
                    if s_ > naikr + 1e-4:
                        naikr = s_
                        break
                    pv.postavyty(imia, v0)
            if naikr <= bulo + 1e-4:
                break
    # Зсув у пікселях маски → метри (маска: N·OKO пікселів від ступень до
    # очей).
    p_ = tochky_tila(h)
    k_n = N * OKO / (oko_modeli(h) - p_[:, 2].min()) if z_okom else \
        N * 0.92 / (p_[:, 2].max() - p_[:, 2].min())
    PROFIL_ZSUV[0] = _ZSUV_PX[0] / k_n
    pv.znach["зсув профілю"] = PROFIL_ZSUV[0]
    print("[підбір] профіль: %.4f, зсув %+d px; %s"
          % (naikr, _ZSUV_PX[0], {t: round(pv.znach[t], 2) for t in imena}),
          flush=True)
    if NAKLADKA:
        p = povernuty_profil(tochky_tila(h), PROFIL_KUT[0])
        mb_ = np.roll(maska_modeli(p, 1, oko_modeli(h) if z_okom else None),
                      _ZSUV_PX[0], 1)
        if iou(np.fliplr(mb_), m_b) > iou(mb_, m_b):
            mb_ = np.fliplr(mb_)
        img = np.zeros((N, N, 4), np.float32)
        img[..., 3] = 1
        img[..., 0], img[..., 2], img[..., 1] = m_b, mb_, m_b & mb_
        im = bpy.data.images.new("накладка-бік", N, N)
        im.pixels.foreach_set(img.ravel())
        im.filepath_raw = NAKLADKA.replace(".png", "-бік.png")
        im.file_format = "PNG"
        im.save()
    postavyty_ruky(arm, kut_ruk)
    return naikr


def pidibraty(h, arm, maska_pered, maska_bik=None, raundy=4, kut_ruk=90.0,
              oko_y=None):
    """`kut_ruk` — кут рук від вертикалі на кадрі (90 — T-поза); `oko_y` —
    рівень очей на кадрі спереду, пікселі знизу."""
    m_p = maska_ref(maska_pered, oko_y)
    # Профіль — у тому ж масштабі, що й перед: очей збоку MediaPipe певно
    # не бачить, тож їхній рівень — та сама частка висоти з зачіскою, що
    # спереду (та сама людина, той самий кадр Kontext).
    oko_b = None
    if maska_bik and oko_y is not None:
        y0f, y1f = _vys_masky(maska_pered)
        y0b, y1b = _vys_masky(maska_bik)
        oko_b = y0b + (oko_y - y0f) * (y1b - y0b) / (y1f - y0f)
    m_b = maska_ref(maska_bik, oko_b, KADR_BIK[0], "бік") if maska_bik \
        else None
    postavyty_ruky(arm, kut_ruk)
    pv = Povzunky(h)

    def otsinka():
        p = tochky_tila(h)
        oz = oko_modeli(h) if oko_y is not None else None
        s = iou(maska_modeli(p, 0, oz), m_p)
        return s

    stan = {"kut": kut_ruk}

    def zh_kut(k):
        stan["kut"] = k
        postavyty_ruky(arm, k)

    naikr = otsinka()
    print("[підбір] початок: %.4f" % naikr, flush=True)
    # Кут рук — окремо, до повзунків (руки на кадрі трохи нижче горизонталі).
    for k in np.arange(70, 96, 2.0):
        zh_kut(k)
        s_ = otsinka()
        if s_ > naikr:
            naikr, kut_ruk = s_, k
    zh_kut(kut_ruk)
    print("[підбір] кут рук %.0f° від вертикалі: %.4f" % (kut_ruk, naikr),
          flush=True)
    # Решта кутів пози — по черзі, двічі (впливають одне на одне).
    kuty = (("кут рук", None, np.arange(76, 100.1, 1.0)),
            ("ключиці", KLIUCH, np.arange(-6, 14.1, 1.0)),
            ("кут ліктя", KUT_LIKTIA, np.arange(-4, 16.1, 1.0)),
            ("кут ніг", KUT_NIH, np.arange(-6, 6.1, 1.0)),
            # Коліна (KOLINO) — підбір дав −1°, оцінка гірша (MPFB-25): поза
            # пошуком, кут лишається 0.
            # Стопи не далі 30°: підбір тягнув до 54° — ступні дивились убік
            # (на кадрі ≈25–30°; П6 «реалістично» важить більше за міру).
            ("стопи", STOPY, np.arange(6, 30.1, 2.0)))
    for _ in range(2):
        for imia, kom, diap in kuty:
            krashche = kut_ruk if kom is None else kom[0]
            for v in diap:
                if kom is None:
                    zh_kut(v)
                else:
                    kom[0] = v
                    zh_kut(kut_ruk)
                s_ = otsinka()
                if s_ > naikr + 1e-5:
                    naikr, krashche = s_, v
            if kom is None:
                kut_ruk = krashche
            else:
                kom[0] = krashche
            zh_kut(kut_ruk)
    print("[підбір] кути: рук %.0f°, ключиці %+.0f°, ліктя %+.0f°, ніг %+.0f°, "
          "стопи %.0f°: %.4f" % (kut_ruk, KLIUCH[0], KUT_LIKTIA[0], KUT_NIH[0],
                                 STOPY[0], naikr),
          flush=True)
    # Кожен крок — повторно, поки щось кращає: за один прохід на крок
    # повзунок від нуля сягав лише 0,25+0,12+0,06+0,03 = 0,46 (MPFB-17 —
    # пів десятка повзунків упирались саме в 0,46).
    for krok in (0.25, 0.12, 0.06, 0.03)[:raundy]:
        for _prokhid in range(PROKHODY):
            bulo = naikr
            for imia in list(pv.znach):
                lo, hi = pv.mezhi(imia)
                for znak in (1, -1):
                    v0 = pv.znach[imia]
                    v1 = min(hi, max(lo, v0 + znak * krok))
                    if v1 == v0:
                        continue
                    pv.postavyty(imia, v1)
                    s = otsinka()
                    if s > naikr + 1e-4:
                        naikr = s
                        break
                    pv.postavyty(imia, v0)
            if naikr <= bulo + 1e-4:
                break
        print("[підбір] крок %.2f: %.4f" % (krok, naikr), flush=True)
    if m_b is not None:
        pidibraty_profil(h, arm, pv, m_b, oko_y is not None, kut_ruk)
    print("[підбір] повзунки: %s" % {k: round(v, 3) for k, v in pv.znach.items()
                                      if abs(v) > 1e-3}, flush=True)
    # Накладка масок для ока: червоне — лише кадр, синє — лише модель,
    # біле — збіг.
    if NAKLADKA:
        p = tochky_tila(h)
        mm = maska_modeli(p, 0, oko_modeli(h) if oko_y is not None else None)
        img = np.zeros((N, N, 4), np.float32)
        img[..., 3] = 1
        img[..., 0] = m_p
        img[..., 2] = mm
        img[..., 1] = m_p & mm
        im = bpy.data.images.new("накладка", N, N)
        im.pixels.foreach_set(img.ravel())
        im.filepath_raw = NAKLADKA
        im.file_format = "PNG"
        im.save()
    # Поза спокою назад: скелет і рухи — від неї.
    for pb in arm.pose.bones:
        pb.matrix_basis.identity()
    bpy.context.view_layer.update()
    pv.znach["кут рук"] = kut_ruk
    pv.znach["кут ніг"] = KUT_NIH[0]
    pv.znach["кут ліктя"] = KUT_LIKTIA[0]
    pv.znach["стопи"] = STOPY[0]
    pv.znach["ключиці"] = KLIUCH[0]
    pv.znach["коліна"] = KOLINO[0]
    return naikr, pv.znach


# ── обличчя за опорними точками (02.10.2026) ─────────────────────────────
#
# Після підбору тіла: 478 точок обличчя на рендері моделі → найближчі
# вершини (будова MakeHuman стала, тож прив'язка не зміниться під час
# підбору), далі точки моделі — прямо з вершин, без рендеру, і повзунки
# голови й обличчя зближують їх із точками кадру.

# (назва, файл «+», файл «−», обидва боки l/r)
PARY_OBL = [
    ("head-scale-horiz", "head-scale-horiz-incr", "head-scale-horiz-decr", False),
    ("head-scale-vert", "head-scale-vert-incr", "head-scale-vert-decr", False),
    ("head-trans-v", "head-trans-up", "head-trans-down", False),
    # Обличчя на кадрі на ~5 px убік від центру тулуба — без цього повзунка
    # загальний зсув лишався, і жоден інший не покращував похибки.
    ("head-trans-h", "head-trans-out", "head-trans-in", False),
    ("forehead-scale-vert", "forehead-scale-vert-incr", "forehead-scale-vert-decr", False),
    ("chin-height", "chin-height-incr", "chin-height-decr", False),
    ("chin-width", "chin-width-incr", "chin-width-decr", False),
    ("nose-scale-vert", "nose-scale-vert-incr", "nose-scale-vert-decr", False),
    ("nose-scale-horiz", "nose-scale-horiz-incr", "nose-scale-horiz-decr", False),
    ("nose-trans-v", "nose-trans-up", "nose-trans-down", False),
    ("mouth-scale-horiz", "mouth-scale-horiz-incr", "mouth-scale-horiz-decr", False),
    ("mouth-trans-v", "mouth-trans-up", "mouth-trans-down", False),
    ("eyebrows-trans-v", "eyebrows-trans-up", "eyebrows-trans-down", False),
    ("eye-trans-v", "eye-trans-up", "eye-trans-down", True),
    ("eye-trans-h", "eye-trans-out", "eye-trans-in", True),
    ("eye-scale", "eye-scale-incr", "eye-scale-decr", True),
    ("eye-height2", "eye-height2-incr", "eye-height2-decr", True),
    ("cheek-bones", "cheek-bones-incr", "cheek-bones-decr", True),
]


# Голова ширша за ±1 MakeHuman: при статурі кадру (вага 1) ширина голови
# упиралась у 1,0 і точки лишались за 3,5 px (MPFB-19).
MEZHI_OBL = {"head-scale-horiz": 1.6, "head-scale-vert": 1.6}


class PovzunkyObl:
    def __init__(self, h, pary=None):
        self.h, self.kl, self.znach = h, {}, {}
        self.odnopol = set()
        for imia, plus, minus, lr in (pary or PARY_OBL):
            boky = ("l-", "r-") if lr else ("",)
            ok = True
            if minus is None:
                self.odnopol.add(imia)
            for b in boky:
                for zn, f in (("+", plus), ("-", minus)):
                    if f is None:
                        continue
                    kb_ = h.data.shape_keys.key_blocks \
                        if h.data.shape_keys else {}
                    if b + f not in kb_:
                        shl = TargetService.target_full_path(b + f)
                        if not shl:
                            ok = False
                            continue
                        TargetService.load_target(h, shl, weight=0.0,
                                                  name=b + f)
                    self.kl.setdefault(imia, []).append((zn, b + f))
            if ok:
                # Другий раунд підбору бере вже поставлені значення.
                kb_ = h.data.shape_keys.key_blocks
                self.znach[imia] = sum(
                    (kb_[k].value if z == "+" else -kb_[k].value)
                    for z, k in self.kl[imia]) / len(boky)
            else:
                self.kl.pop(imia, None)
        print("[обличчя] повзунків: %d" % len(self.znach), flush=True)

    def postavyty(self, imia, v):
        self.znach[imia] = v
        kb = self.h.data.shape_keys.key_blocks
        for zn, k in self.kl[imia]:
            kb[k].slider_max = max(1.0, MEZHI_OBL.get(imia, 1.0))
            kb[k].value = max(0.0, v) if zn == "+" else max(0.0, -v)


# Ширина обличчя спереду (замовник 02.10.2026: «трохи витягнув модель
# облича, щоб воно було схоже на рендер, не таке широке»). Лише повзунки
# обрису — очі, ніс, рот (точки MediaPipe) на місці.
PARY_SHYR = [
    ("head-fat", "head-fat-incr", "head-fat-decr", False),
    ("chin-bones", "chin-bones-incr", "chin-bones-decr", False),
    ("chin-width", "chin-width-incr", "chin-width-decr", False),
    ("chin-jaw-drop", "chin-jaw-drop-incr", "chin-jaw-drop-decr", False),
    ("cheek-volume", "cheek-volume-incr", "cheek-volume-decr", True),
    ("cheek-inner", "cheek-inner-incr", "cheek-inner-decr", True),
    ("head-oval", "head-oval", None, False),
    ("chin-triangle", "chin-triangle", None, False),
    # Вуха моделі сиділи на ~10 px нижче й ширше за кадрові (мочки ширили
    # обрис на рівні щік).
    ("ear-trans-v", "ear-trans-up", "ear-trans-down", True),
    ("ear-scale", "ear-scale-incr", "ear-scale-decr", True),
    ("ear-wing", "ear-wing-incr", "ear-wing-decr", True),
    ("ear-lobe", "ear-lobe-incr", "ear-lobe-decr", True),
]


_DBG = [False]


def pidibraty_shyrynu(h, arm, kut_ruk, proekt, maska_ref, L_ref):
    """Обрис голови спереду між очима й підборіддям — під кадр (IoU у цій
    смузі). `proekt(co) → (x, y зверху)` у пікселях кадру."""
    import cv2
    postavyty_ruky(arm, kut_ruk)
    img = bpy.data.images.load(maska_ref, check_existing=True)
    w, hh = img.size
    px = np.empty(w * hh * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    m_ref = (px.reshape(hh, w, 4)[..., 0] > 0.5)[::-1]       # y зверху
    y_oko = (L_ref[33, 1] + L_ref[263, 1]) / 2
    y_b = int(L_ref[152, 1]) + 2
    # від верху вух (≈ на третину відстані очі—підборіддя вище очей)
    y_a = int(y_oko - 0.35 * (y_b - y_oko))
    cx = float(L_ref[1, 0])
    pol = 1.4 * float(L_ref[454, 0] - L_ref[234, 0]) / 2
    smuha = np.zeros((hh, w), bool)
    smuha[y_a:y_b, int(cx - pol):int(cx + pol)] = True
    holova = np.zeros(len(h.data.vertices))
    gi = h.vertex_groups["head"].index
    gb = h.vertex_groups["body"].index
    for v in h.data.vertices:
        # лише тіло — допоміжна сітка волосся MPFB теж на кістці голови й
        # висіла клаптями обабіч (перша спроба: збіг 0,75 і не рухався)
        if not any(g.group == gb and g.weight > 0.5 for g in v.groups):
            continue
        for g in v.groups:
            if g.group == gi:
                holova[v.index] = g.weight
    mm = [m for m in h.modifiers if m.type == "MASK"]

    def otsinka():
        co, _ = vershyny_bez_masky(h)
        for m in mm:
            m.show_viewport = False
        bpy.context.view_layer.update()
        ev = h.evaluated_get(bpy.context.evaluated_depsgraph_get())
        me = ev.to_mesh()
        me.calc_loop_triangles()
        tris = np.array([t.vertices[:] for t in me.loop_triangles])
        ev.to_mesh_clear()
        for m in mm:
            m.show_viewport = True
        P = proekt(co)
        t = tris[(holova[tris] > 0.3).all(1)]
        mk = np.zeros((hh, w), np.uint8)
        for tr in np.round(P[t]).astype(np.int32):
            cv2.fillConvexPoly(mk, tr, 1)
        mk = mk > 0
        if _DBG[0]:
            import os as _o
            o_ = np.zeros((hh, w, 3), np.uint8)
            o_[m_ref] = (0, 0, 200)
            o_[mk] = (0, 200, 0)
            o_[mk & m_ref] = (200, 200, 200)
            o_[smuha & ~(mk | m_ref)] = (60, 60, 0)
            cv2.imwrite(_o.environ["SHYRYNA_DEBUG"], o_)
        a, b = mk & smuha, m_ref & smuha
        return (a & b).sum() / max(1, (a | b).sum())
    pv = PovzunkyObl(h, PARY_SHYR)
    naikr = otsinka()
    import os as _o
    if _o.environ.get("SHYRYNA_DEBUG"):
        _DBG[0] = True
        otsinka()
        _DBG[0] = False
    print("[ширина] початок: %.4f" % naikr, flush=True)
    for krok in (0.3, 0.3, 0.15, 0.15, 0.07):
        for imia in list(pv.znach):
            lo = 0.0 if imia in pv.odnopol else -1.0
            for znak in (1, -1):
                v0 = pv.znach[imia]
                v1 = min(1.0, max(lo, v0 + znak * krok))
                if v1 == v0:
                    continue
                pv.postavyty(imia, v1)
                s_ = otsinka()
                if s_ > naikr + 1e-4:
                    naikr = s_
                    break
                pv.postavyty(imia, v0)
        print("[ширина] крок %.2f: %.4f" % (krok, naikr), flush=True)
    print("[ширина] повзунки: %s" % {k: round(v, 2) for k, v in pv.znach.items()
                                     if abs(v) > 1e-3}, flush=True)
    for pb in arm.pose.bones:
        pb.matrix_basis.identity()
    bpy.context.view_layer.update()
    return naikr


def vershyny_bez_masky(h):
    mm = [m for m in h.modifiers if m.type == "MASK"]
    for m in mm:
        m.show_viewport = False
    # Без цього зміни ключів форми не доходили до обчисленої сітки, і підбір
    # обличчя «не бачив» жодного повзунка (ітерація MPFB-5).
    h.data.update()
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    ev = h.evaluated_get(dg)
    me = ev.to_mesh()
    p = np.empty(len(me.vertices) * 3, dtype=np.float64)
    me.vertices.foreach_get("co", p)
    nn = np.empty(len(me.vertices) * 3, dtype=np.float64)
    me.vertices.foreach_get("normal", nn)
    ev.to_mesh_clear()
    for m in mm:
        m.show_viewport = True
    mw = np.array(h.matrix_world)
    return p.reshape(-1, 3) @ mw[:3, :3].T + mw[:3, 3], nn.reshape(-1, 3)


def pidibraty_oblychchia(h, arm, ref, maska, kut_ruk, render_fn, L_ref,
                         oko_y_px, hh):
    """`render_fn(h) -> (точки_моделі (478,2) у пікселях кадру, функція
    проєкції вершин у ті самі пікселі)`; `L_ref` — точки кадру."""
    import numpy as np_
    rez = None
    # Один раунд. Другий (новий рендер, свіжі точки MediaPipe, нові
    # заступники) почав з 4,4 px і скінчив на 2,9 — точки на рендері без
    # волосся шумні, обличчя на оцінці впало до 0,54 (MPFB-26).
    for raund, kroky in enumerate(((0.3, 0.3, 0.15, 0.15, 0.07, 0.07, 0.03),
                                   )):
        rez = _pidibraty_oblychchia(h, arm, kut_ruk, render_fn, L_ref,
                                    kroky, raund)
    return rez


def _pidibraty_oblychchia(h, arm, kut_ruk, render_fn, L_ref, kroky, raund):
    import numpy as np_
    postavyty_ruky(arm, kut_ruk)
    L_mod, proekt = render_fn(h)
    co, nrm = vershyny_bez_masky(h)
    gi = h.vertex_groups["body"].index
    tilo = np_.array([any(g.group == gi and g.weight > 0.5 for g in v.groups)
                      for v in h.data.vertices])
    P = proekt(co)
    pered = (-nrm[:, 1] > 0.05) & tilo
    idx = np_.where(pered)[0]
    vibr = []
    for lx, ly in L_mod:
        d = np_.hypot(P[idx, 0] - lx, P[idx, 1] - ly)
        # З кількох найближчих — найближча до глядача (найменша Y).
        blyz = idx[np_.argsort(d)[:6]]
        vibr.append(blyz[np_.argmin(co[blyz, 1])])
    vibr = np_.array(vibr)
    print("[обличчя] прив'язка до вершин: середня похибка %.2f px"
          % np_.hypot(*(P[vibr] - L_mod).T).mean(), flush=True)
    pv = PovzunkyObl(h)

    def otsinka():
        c2, _ = vershyny_bez_masky(h)
        return float(np_.hypot(*(proekt(c2)[vibr] - L_ref).T).mean())

    naikr = otsinka()
    print("[обличчя] раунд %d, початок: %.2f px" % (raund + 1, naikr),
          flush=True)
    # Кроки повторюються, доки дають виграш: сума одного проходу (0,52)
    # упиралась у стелю, хоча повзунки мають ±1 (ітерація MPFB-7).
    for krok in kroky:
        for imia in list(pv.znach):
            for znak in (1, -1):
                v0 = pv.znach[imia]
                m_ = MEZHI_OBL.get(imia, 1.0)
                v1 = min(m_, max(-m_, v0 + znak * krok))
                if v1 == v0:
                    continue
                pv.postavyty(imia, v1)
                s_ = otsinka()
                if s_ < naikr - 1e-3:
                    naikr = s_
                    break
                pv.postavyty(imia, v0)
        print("[обличчя] крок %.2f: %.2f px" % (krok, naikr), flush=True)
    print("[обличчя] повзунки: %s" % {k: round(v, 2) for k, v in pv.znach.items()
                                      if abs(v) > 1e-3}, flush=True)
    for pb in arm.pose.bones:
        pb.matrix_basis.identity()
    bpy.context.view_layer.update()
    return naikr

