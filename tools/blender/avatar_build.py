"""Аватар зі скану на скелеті манекена — щоб працювали рухи людини UAL1.

Слово замовника 01.10.2026: «створи 3D модель людини з референсу Людина,
чоловік — варіант 1 з рухами, які є у переліку `./run.sh --рухи-людини`»;
«модель не змінювалась незалежно від одягу, без одягу — пов'язка».

Рухи UAL1 гра не перецілює, а пересаджує (`skinned_model.gd:
_borrow_player`): вони працюють лише на скелеті манекена
(`Superhero_Male_FullBody.gltf`, 65 кісток) з тими самими назвами. Тож
скелет НЕ чіпається — під нього підганяється скан (Pixal3D з референсу в
T-позі, `tools/comfyui/avatar_ref.py --база`):

  1. скан обертається обличчям туди ж, куди манекен, і масштабується до
     його зросту (ступні на нулі);
  2. руки дотягуються: від плеча назовні X розтягується так, щоб кінчики
     пальців збіглися з манекеновими, а висота руки — з висотою кісток
     руки манекена (плавно від плеча, тулуб не зсувається);
  3. ваги кісток переносяться з тіла манекена на найближчу грань скану
     (Data Transfer) — пов'язка й волосся беруть вагу тіла під ними;
  4. тіло манекена прибирається, скан лишається на його скелеті.

    blender -b --factory-startup -P tools/blender/avatar_build.py -- \\
        <скан.glb> <куди.gltf> [тека_кадрів]

Тека кадрів — рендер спокою спереду й збоку та кількох рухів UAL1
(перевірка деформації ДО гри, спека 4а.3).
"""
import math
import os
import sys

import functools

import bpy
from mathutils import Vector

print = functools.partial(print, flush=True)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MANEKEN = os.path.join(ROOT, "game/models/player/Superhero_Male_FullBody.gltf")
RUKHY = os.path.join(ROOT, "game/models/player/animations/UAL1_Standard.glb")
PERED = -1
ARGS = sys.argv[sys.argv.index("--") + 1:]
REF = REF_MASKA = None
# кроки дифузії локального тону (~0,5 ребра за крок, ребро ~5 мм)
TON_KROKY = 200
if "--референс" in ARGS:
    i_ = ARGS.index("--референс")
    REF, REF_MASKA = ARGS[i_ + 1], ARGS[i_ + 2]
    del ARGS[i_:i_ + 3]
PO_RYADKAKH = False
# Прив'язка проєкції (02.10.2026, перебір): осі «однаково» чи «окремо»,
# уточнення «підбір» чи «ні». Задається ключем --прив'язка осі,уточнення.
PRYVIAZKA_OSI, PRYVIAZKA = "однаково", "ні"
if "--прив'язка" in ARGS:
    i_ = ARGS.index("--прив'язка")
    PRYVIAZKA_OSI, PRYVIAZKA = ARGS[i_ + 1].split(",")
    del ARGS[i_:i_ + 2]
# Сторона текстури тіла (11.10.2026): 2048 на все тіло давало обличчю
# замало пікселів — ельфійка йде з 4096.
TEKSTURA = 2048
if "--текстура" in ARGS:
    i_ = ARGS.index("--текстура")
    TEKSTURA = int(ARGS[i_ + 1])
    del ARGS[i_:i_ + 2]
OBLYCHCHIA = "--обличчя" in ARGS
OCHI = "--очі" in ARGS
for k_ in ("--обличчя", "--очі"):
    if k_ in ARGS:
        ARGS.remove(k_)
ODNA_OBOLONKA = "--одна-оболонка" in ARGS
if ODNA_OBOLONKA:
    ARGS.remove("--одна-оболонка")
KOLINA = 0
if "--коліна" in ARGS:
    i_ = ARGS.index("--коліна")
    KOLINA = int(ARGS[i_ + 1])
    del ARGS[i_:i_ + 2]
# --перед-скану ±1 (28.11.2026, NPC з Hunyuan3D-2mv): перед скана відомий (вісь Y glTF→Blender) —
# пошук за ступнями плутають чоботи з каблуком (коваль вийшов спиною вперед)
PERED_SKANU = None
if "--перед-скану" in ARGS:
    i_ = ARGS.index("--перед-скану")
    PERED_SKANU = int(ARGS[i_ + 1])
    del ARGS[i_:i_ + 2]
KYSTI_SKANU = "--кисті-скану" in ARGS
if KYSTI_SKANU:
    ARGS.remove("--кисті-скану")
PERUKA = None
if "--перука" in ARGS:
    PERUKA = ARGS[ARGS.index("--перука") + 1]
    del ARGS[ARGS.index("--перука"):ARGS.index("--перука") + 2]
SKAN, KUDY = ARGS[0], ARGS[1]
KADRY = ARGS[2] if len(ARGS) > 2 else None
POVERNUTO = False
# Рухи для кадрів перевірки: назва в UAL1 → кадр, на якому знімати.
PEREVIRKA = [("Idle_Loop", 10), ("Walk_Loop", 8), ("Sword_Attack", 14),
             ("Punch_Jab", 6), ("Death01", 40)]


def svit(o):
    return [o.matrix_world @ v.co for v in o.data.vertices]


def mezhi(tochky):
    lo = Vector((min(p.x for p in tochky), min(p.y for p in tochky),
                 min(p.z for p in tochky)))
    hi = Vector((max(p.x for p in tochky), max(p.y for p in tochky),
                 max(p.z for p in tochky)))
    return lo, hi


def zastosuvaty(o):
    bpy.context.view_layer.objects.active = o
    for x in bpy.context.selected_objects:
        x.select_set(False)
    o.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=MANEKEN)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    tilo = bpy.data.objects["SuperHero_Male"]
    for imia in ("Icosphere", "Eyebrows", "Eyes"):
        if imia in bpy.data.objects:
            bpy.data.objects.remove(bpy.data.objects[imia])
    kist = {b.name: arm.matrix_world @ b.head_local for b in arm.data.bones}
    # Перед манекена — куди від кісточки дивляться пальці ступні. «Найдальша
    # точка голови» не годиться: волосся на потилиці стирчить далі за ніс
    # (перша спроба 01.10.2026 зняла кадри спиною).
    pered_manekena = 1 if kist["ball_l"].y > kist["foot_l"].y else -1
    global PERED
    PERED = pered_manekena
    t_lo, t_hi = mezhi(svit(tilo))

    stari = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=SKAN)
    novi = [o for o in bpy.data.objects if o not in stari]
    sitky = [o for o in novi if o.type == "MESH"]
    for o in novi:
        if o.type != "MESH":
            # Вузли-обгортки glTF: перенести трансформ на сітку й прибрати.
            pass
    for o in sitky:
        o.select_set(True)
        zastosuvaty(o)
    skan = sitky[0]
    if len(sitky) > 1:
        bpy.context.view_layer.objects.active = skan
        for o in sitky:
            o.select_set(True)
        bpy.ops.object.join()
    for o in novi:
        if o.name in bpy.data.objects and o.type != "MESH":
            bpy.data.objects.remove(o)
    skan.parent = None
    zastosuvaty(skan)
    skan.name = "Аватар"

    # 1. Обличчя туди ж, куди манекен — теж за ступнями: смуга підошви
    # (пальці) виступає вперед від смуги кісточок.
    p = svit(skan)
    lo, hi = mezhi(p)
    vys = hi.z - lo.z
    pidoshva = [q.y for q in p if q.z < lo.z + vys * 0.02]
    kistochky = [q.y for q in p if lo.z + vys * 0.05 < q.z < lo.z + vys * 0.08]
    pered_skanu = 1 if (sum(pidoshva) / len(pidoshva)
                        > sum(kistochky) / len(kistochky)) else -1
    print("[аватар] перед скану за ступнями: %+d%s" % (pered_skanu, "" if PERED_SKANU is None else
          ", задано %+d" % PERED_SKANU))
    if PERED_SKANU is not None:
        pered_skanu = PERED_SKANU
    if pered_skanu != pered_manekena:
        skan.rotation_euler = (0, 0, math.pi)
        zastosuvaty(skan)
        global POVERNUTO
        POVERNUTO = True
    # Зріст — як у манекена, ступні на нулі, вісь по центру.
    p = svit(skan)
    lo, hi = mezhi(p)
    k = (t_hi.z - t_lo.z) / (hi.z - lo.z)
    tsentr = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    for v in skan.data.vertices:
        v.co = (v.co - tsentr) * k
    print("[аватар] зріст скану %.3f → %.3f м (×%.3f), перед %+d"
          % (hi.z - lo.z, t_hi.z - t_lo.z, k, pered_manekena))
    if ODNA_OBOLONKA:
        # `--одна-оболонка` (12.10.2026, слово замовника: «артефакти колін»,
        # «неприродні контури навколо очей»): Pixal3D дає ПОДВІЙНУ оболонку —
        # зовнішню (нормалі назовні) і внутрішню на ~5 мм глибше (нормалі
        # всередину, 46% вершин). Будь-яка правка форми зовнішньої (коліна)
        # пускала внутрішню назовні темними «тріщинами». Внутрішня грань —
        # та, чий промінь уздовж нормалі за 1,5 см упирається в поверхню.
        import bmesh as _bm
        from mathutils.bvhtree import BVHTree as _BVH
        b_ = _bm.new()
        b_.from_mesh(skan.data)
        b_.normal_update()
        tree_ = _BVH.FromBMesh(b_)
        # Друга ітерація (12.10.2026, слово замовника: «невеликі дефекти
        # колін та долонь з пальцями … у попередньої моделі було краще»).
        # Замір: сітка — ОДНЕ суцільне тонкостінне тіло (стінки ~6 мм,
        # з'єднані по краях), внутрішня стінка майже повна (282 тис. граней
        # мають за спиною протилежно повернуту грань ближче 7 мм).
        # Перший критерій («промінь уздовж нормалі за 1,5 см у щось
        # упирається») ловив не її, а бік пальця біля сусіднього пальця,
        # коліно біля коліна. Тепер — парність: промінь від грані вздовж
        # нормалі назовні перетинає поверхню 0, 4, 8… разів від зовнішньої
        # стінки і 2, 6… — від внутрішньої (крізь порожнину й протилежну
        # стінку). Три промені з легким відхиленням, більшість.
        import random as _rnd
        _rnd.seed(3)

        def perety(c, d):
            n_ = 0
            p_ = c + d * 0.0003
            for _ in range(24):
                h_ = tree_.ray_cast(p_, d, 5.0)
                if h_[0] is None:
                    break
                n_ += 1
                p_ = h_[0] + d * 0.0003
            return n_
        vnutr = []
        for f in b_.faces:
            c = f.calc_center_median()
            golosy = 0
            for k_ in range(3):
                d = f.normal.copy()
                if k_:
                    d = (d + Vector((_rnd.uniform(-0.15, 0.15), _rnd.uniform(-0.15, 0.15),
                                     _rnd.uniform(-0.15, 0.15)))).normalized()
                golosy += (perety(c, d) // 2) % 2
            if golosy >= 2:
                vnutr.append(f)
        do = len(b_.faces)
        _bm.ops.delete(b_, geom=vnutr, context="FACES")
        _bm.ops.remove_doubles(b_, verts=b_.verts, dist=0.0002)
        # Уламки (окремі шматки < 400 вершин) — «пластівці» біля голови й
        # у очах, що мерехтіли поруч із поверхнею.
        b_.verts.ensure_lookup_table()
        bachyly = set()
        dribni = []
        for v0 in b_.verts:
            if v0.index in bachyly:
                continue
            ostriv, stek = [], [v0]
            bachyly.add(v0.index)
            while stek:
                v = stek.pop()
                ostriv.append(v)
                for e in v.link_edges:
                    u = e.other_vert(v)
                    if u.index not in bachyly:
                        bachyly.add(u.index)
                        stek.append(u)
            if len(ostriv) < 400:
                dribni.extend(ostriv)
        _bm.ops.delete(b_, geom=dribni, context="VERTS")
        print("[аватар] одна оболонка: уламків вершин %d" % len(dribni))
        b_.to_mesh(skan.data)
        b_.free()
        print("[аватар] одна оболонка: внутрішніх граней %d з %d" % (len(vnutr), do))
    if KOLINA:
        # `--коліна` (12.10.2026, «трохи вирівняй положення колін»):
        # Pixal3D ліпить наколінки кулями. Згладжувати ДО проєкції —
        # після неї текстура розтягувалась смугами. Друга ітерація: смуга
        # з різким краєм лишала на межі валик («дефекти колін») — тепер
        # Taubin (без усадки) з вагою, що плавно згасає від центру коліна
        # (радіус 9 см), N×10 проходів.
        import numpy as np
        hh = t_hi.z - t_lo.z
        me_ = skan.data
        nv_ = len(me_.vertices)
        co_ = np.empty(nv_ * 3)
        me_.vertices.foreach_get("co", co_)
        co_ = co_.reshape(nv_, 3)
        ed = np.empty(len(me_.edges) * 2, dtype=np.int64)
        me_.edges.foreach_get("vertices", ed)
        ed = ed.reshape(-1, 2)
        stup = np.bincount(ed.ravel(), minlength=nv_).astype(float)
        vaga = np.zeros(nv_)
        for znak in (-1, 1):
            noga = (co_[:, 0] * znak > 0.02) & (np.abs(co_[:, 2] - hh * 0.285) < 0.02)
            if not noga.any():
                continue
            i0 = np.where(noga)[0]
            pered_i = i0[np.argmax(co_[i0, 1] * pered_manekena)]
            c_ = co_[pered_i] - np.array([0, pered_manekena * 0.03, 0])
            d_ = np.linalg.norm(co_ - c_, axis=1)
            vaga = np.maximum(vaga, np.clip(1 - (d_ / 0.09) ** 2, 0, 1) ** 2)
        def lapl(x):
            s_ = np.zeros_like(x)
            np.add.at(s_, ed[:, 0], x[ed[:, 1]])
            np.add.at(s_, ed[:, 1], x[ed[:, 0]])
            return s_ / np.maximum(stup, 1)[:, None] - x
        for _ in range(KOLINA * 10):
            co_ += (0.5 * vaga)[:, None] * lapl(co_)
            co_ += (-0.53 * vaga)[:, None] * lapl(co_)
        me_.vertices.foreach_set("co", co_.ravel())
        me_.update()
        print("[аватар] коліна: вершин з вагою %d, проходів %d"
              % (int((vaga > 0.01).sum()), KOLINA * 10))
    if REF:
        proektsiia(skan, pered_manekena)
        if OBLYCHCHIA:
            G_ = vyrivniaty_oblychchia(skan, pered_manekena)
            if G_ is not None:
                rukhomi = None
                if OCHI:
                    G_, rukhomi = zgladyty_ochi(skan, pered_manekena, G_)
                pryviazaty_uv(skan, pered_manekena, G_, rukhomi)
                skalp(skan, pered_manekena, G_)
                import numpy as np
                os.makedirs(os.path.dirname(os.path.abspath(KUDY)), exist_ok=True)
                np.save(os.path.join(os.path.dirname(os.path.abspath(KUDY)),
                                     "oblychchia-G.npy"), G_)

    # 2. Руки: плече манекена → кінчик пальців. Числа рахуються тут, а
    # застосовуються в 2в — до СКЕЛЕТА й тіла манекена, не до скану
    # (02.10.2026: скан, деформований під манекен, втрачав силует
    # референсу; рухи UAL1 гра тепер ставить на скелет без доріжок
    # положення, `skinned_model.gd`).
    plече = abs(kist["upperarm_l"].x)
    kinets_m = t_hi.x
    p = svit(skan)
    lo, hi = mezhi(p)
    kinets_s = max(hi.x, -lo.x)
    ruka_z_m = (kist["upperarm_l"].z + kist["hand_l"].z) / 2
    dal = [q.z for q in p if abs(q.x) > plече + (kinets_s - plече) * 0.5
           and q.z > 1.1]
    ruka_z_s = sorted(dal)[len(dal) // 2] if dal else ruka_z_m
    k_inv = (kinets_s - plече) / max(0.01, kinets_m - plече)
    print("[аватар] руки: кінчики скану %.3f, манекена %.3f (скелет ×%.3f), "
          "висота руки %.3f / %.3f м" % (kinets_s, kinets_m, k_inv, ruka_z_s,
                                         ruka_z_m))

    # 2а. Глибина (Y): скан центровано за габаритом, а кістки манекена
    # лежать на своїй Y — передпліччя стояло на 14 см убік від зап'ястка,
    # і ваги брались не з тих граней (руки й обличчя «їхали», 01.10.2026).
    # Середня Y смуги рук скану стає Y кісток руки манекена.
    ruky = [v.co.y for v in skan.data.vertices
            if plече + 0.1 < abs(v.co.x) < kinets_m - 0.15]
    if ruky:
        dy = (kist["upperarm_l"].y + kist["hand_l"].y) / 2 \
            - sorted(ruky)[len(ruky) // 2]
        for v in skan.data.vertices:
            v.co.y += dy
        print("[аватар] глибина: скан зсунуто на %+.3f м по Y" % dy)

    # 2б. Ноги: центр смуги на висоті ступні, коліна й стегна — скан
    # проти тіла манекена (не кістки: пальці в обох однаково попереду).
    tilo_p = svit(tilo)

    def tsentr(tochky, z, znak):
        smuga = [c for c in tochky if abs(c.z - z) < 0.025
                 and c.x * znak > 0.02 and abs(c.x) < 0.35]
        if not smuga:
            return None
        return (sum(c.x for c in smuga) / len(smuga),
                sum(c.y for c in smuga) / len(smuga))
    rivni = [kist["foot_l"].z, kist["calf_l"].z, kist["thigh_l"].z - 0.1]
    VERKH = kist["thigh_l"].z + 0.12
    zsuvy = {}
    skan_p = [v.co.copy() for v in skan.data.vertices]
    for znak in (1, -1):
        zs = []
        for z in rivni:
            a_, b_ = tsentr(tilo_p, z, znak), tsentr(skan_p, z, znak)
            # Скільки треба зсунути МАНЕКЕН, щоб він став на скан.
            zs.append((z, (b_[0] - a_[0], b_[1] - a_[1]) if a_ and b_
                       else (0.0, 0.0)))
        zsuvy[znak] = zs
        print("[аватар] нога %s: манекен → скан x/y на ступні %+.3f/%+.3f, "
              "коліні %+.3f/%+.3f, стегні %+.3f/%+.3f" % (
                  "ліва" if znak > 0 else "права",
                  *zs[0][1], *zs[1][1], *zs[2][1]))

    def zsuv(znak, z):
        zs = zsuvy[znak]
        if z <= zs[0][0]:
            return zs[0][1]
        for (z0, d0), (z1, d1) in zip(zs, zs[1:]):
            if z <= z1:
                t = (z - z0) / (z1 - z0)
                return (d0[0] + (d1[0] - d0[0]) * t,
                        d0[1] + (d1[1] - d0[1]) * t)
        z0, d0 = zs[-1]
        t = max(0.0, 1.0 - (z - z0) / (VERKH - z0))
        return (d0[0] * t, d0[1] * t)

    # Вісь руки скану (ітерація 8): на кадрі руки йдуть трохи вгору до
    # кистей, а скелет стояв горизонтально — кисті манекена опинялись
    # нижче кистей референсу. Медіана Y/Z вершин руки в 48 смугах по X.
    import numpy as np
    sp = np.array([(c.x, c.y, c.z) for c in skan_p])
    os_ruky = {}
    for znak in (1, -1):
        r_ = sp[(sp[:, 0] * znak > plече) & (sp[:, 2] > 1.1)]
        xs_ = np.linspace(plече, kinets_s, 48)
        cy, cz = [], []
        for x0 in xs_:
            sm = r_[np.abs(np.abs(r_[:, 0]) - x0) < 0.02]
            cy.append(np.median(sm[:, 1]) if len(sm) else np.nan)
            cz.append(np.median(sm[:, 2]) if len(sm) else np.nan)
        cy, cz = np.array(cy), np.array(cz)
        for a_ in (cy, cz):
            ok_ = ~np.isnan(a_)
            a_[~ok_] = np.interp(np.where(~ok_)[0], np.where(ok_)[0], a_[ok_])
        os_ruky[znak] = (xs_, np.convolve(np.pad(cy, 3, "edge"),
                                          np.ones(7) / 7, "valid"),
                         np.convolve(np.pad(cz, 3, "edge"), np.ones(7) / 7,
                                     "valid"))
        print("[аватар] вісь руки %s: плече z %.3f → кінчики z %.3f"
              % ("ліва" if znak > 0 else "права", cz[0], cz[-1]))
    plече_m = kist["upperarm_l"]
    kysty_m = kist["hand_l"]

    # Ступні скану: довжина й кут (головна вісь точок нижче кісточки).
    stopy = {}
    for znak in (1, -1):
        f_ = sp[(sp[:, 0] * znak > 0.03) & (sp[:, 2] < 0.1)]
        fm = np.array([(c.x, c.y, c.z) for c in tilo_p
                       if c.x * znak > 0.03 and c.z < 0.1])
        def vis(pts):
            c = pts[:, :2].mean(0)
            u_, s_, vt = np.linalg.svd(pts[:, :2] - c, full_matrices=False)
            d = vt[0] if vt[0][1] * (-1 if pered_manekena < 0 else 1) >= 0 \
                else -vt[0]
            proj = (pts[:, :2] - c) @ d
            return c, d, proj.max() - proj.min()
        if len(f_) > 50 and len(fm) > 20:
            cs, ds, ls = vis(f_)
            cm, dm, lm = vis(fm)
            kut = math.atan2(ds[1], ds[0]) - math.atan2(dm[1], dm[0])
            kut = (kut + math.pi) % (2 * math.pi) - math.pi
            stopy[znak] = (kut, ls / lm)
            print("[аватар] ступня %s: кут %+.1f°, довжина ×%.2f"
                  % ("ліва" if znak > 0 else "права", math.degrees(kut),
                     ls / lm))

    def maneken_na_skan(q):
        """Точка манекена → де вона на скані (руки й ноги)."""
        q = q.copy()
        ax = abs(q.x)
        if ax > plече and q.z > 1.1:
            znak = 1 if q.x > 0 else -1
            xs_, cy, cz = os_ruky[znak]
            t = (ax - plече) / max(0.01, kinets_m - plече)
            x_s = plече + t * (kinets_s - plече)
            # Центр руки манекена тут — лінія плече→кисть його кісток.
            tm = min(1.0, (ax - plече) / max(0.01, abs(kysty_m.x) - plече))
            my = plече_m.y + (kysty_m.y - plече_m.y) * tm
            mz = plече_m.z + (kysty_m.z - plече_m.z) * tm
            sy = float(np.interp(x_s, xs_, cy))
            sz = float(np.interp(x_s, xs_, cz))
            w = min(1.0, (ax - plече) / 0.12)
            q.x = znak * (plече + (ax - plече) * (1 + (k_inv - 1) * w))
            q.y += (sy - my) * w
            q.z += (sz - mz) * w
        if q.z < VERKH and abs(q.x) < 0.4 and abs(q.x) > 1e-6:
            znak = 1 if q.x > 0 else -1
            vaga_x = min(1.0, abs(q.x) / 0.06)
            # Ступня: кут і довжина як у скану, навколо кісточки.
            if znak in stopy and q.z < kist["foot_l"].z + 0.05:
                kut, dl = stopy[znak]
                kis = kist["foot_l" if znak > 0 else "foot_r"]
                vx, vy = q.x - kis.x, q.y - kis.y
                vx, vy = vx * dl, vy * dl
                c_, s_ = math.cos(kut), math.sin(kut)
                q.x = kis.x + vx * c_ - vy * s_
                q.y = kis.y + vx * s_ + vy * c_
            dx, dy = zsuv(znak, q.z)
            q.x += dx * vaga_x
            q.y += dy
        return q

    # 2в. Скелет і тіло манекена — на скан.
    mw = tilo.matrix_world
    mwi = mw.inverted()
    for v in tilo.data.vertices:
        v.co = mwi @ maneken_na_skan(mw @ v.co)
    bpy.context.view_layer.objects.active = arm
    for x in bpy.context.selected_objects:
        x.select_set(False)
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    am_ = arm.matrix_world
    ami = am_.inverted()
    for eb in arm.data.edit_bones:
        eb.head = ami @ maneken_na_skan(am_ @ eb.head)
        eb.tail = ami @ maneken_na_skan(am_ @ eb.tail)
    bpy.ops.object.mode_set(mode="OBJECT")
    for b_ in arm.data.bones:
        kist[b_.name] = arm.matrix_world @ b_.head_local
    print("[аватар] скелет на скані: кисть %.3f м, ступня %.3f/%.3f"
          % (kist["hand_l"].x, kist["foot_l"].x, kist["foot_l"].y))

    # 3. Ваги з тіла манекена.
    for g in tilo.vertex_groups:
        skan.vertex_groups.new(name=g.name)
    dt = skan.modifiers.new("ваги", "DATA_TRANSFER")
    dt.object = tilo
    dt.use_vert_data = True
    dt.data_types_verts = {"VGROUP_WEIGHTS"}
    dt.vert_mapping = "POLYINTERP_NEAREST"
    dt.layers_vgroup_select_src = "ALL"
    dt.layers_vgroup_select_dst = "NAME"
    bpy.context.view_layer.objects.active = skan
    bpy.ops.object.modifier_apply(modifier=dt.name)
    # Голова — жорстко на `Head`: обличчя скану стоїть попереду обличчя
    # манекена, і найближча грань давала бороді й щокам вагу шиї —
    # обличчя «з'їжджало» (01.10.2026). У смузі шиї — плавний перехід.
    h_z, n_z = kist["Head"].z, kist["neck_01"].z
    g_head = skan.vertex_groups["Head"]
    g_neck = skan.vertex_groups["neck_01"]
    # Від n_z − 6 см до Head − 2 см ваги манекена плавно переходять у
    # «жорстку голову»: різка межа рвала шию (01.10.2026: «розрив на
    # рівні шиї»). Рахується за положенням, тож шви текстури (glTF
    # дублює там вершини) отримують однакові ваги й не розходяться.
    niz, verkh = n_z - 0.06, h_z - 0.02
    for v in skan.data.vertices:
        if abs(v.co.x) > 0.16 or v.co.z < niz:
            continue
        t = min(1.0, (v.co.z - niz) / max(0.01, verkh - niz))
        # Ціль: на верху смуги — уся вага Head, у середині — шия з головою.
        tsil = {"Head": t, "neck_01": 1.0 - t} if v.co.z > n_z else \
            {"neck_01": 1.0}
        tsil_t = min(1.0, (v.co.z - niz) / 0.06) if v.co.z <= n_z else 1.0
        bulo = {skan.vertex_groups[g.group].name: g.weight for g in v.groups}
        nove = {}
        for k_ in set(bulo) | set(tsil):
            nove[k_] = bulo.get(k_, 0.0) * (1 - tsil_t) + tsil.get(k_, 0.0) * tsil_t
        suma = sum(nove.values()) or 1.0
        for g in list(v.groups):
            skan.vertex_groups[g.group].remove([v.index])
        for k_, w_ in nove.items():
            if w_ / suma > 0.001:
                skan.vertex_groups[k_].add([v.index], w_ / suma, "REPLACE")
    porozhni = sum(1 for v in skan.data.vertices if not v.groups)
    print("[аватар] вершин %d, без ваги %d" % (len(skan.data.vertices),
                                               porozhni))

    if REF:
        zapekty(skan)

    # 3а. Кисті й ступні — манекенові. Pixal3D ліпить розкриту долоню в
    # «рукавицю», а ступню — грудкою без пальців, і на кістках пальців вони
    # вивертаються (01.10.2026: «бачу руки неправильної форми», «чужі руки з
    # розривом, та незакінчені пальці ніг»). Кінець руки й ноги скану
    # відрізається й плавно звужується до кільця манекена, а кисть і ступня
    # манекена заходять у нього на ЗАХІД — шва-щілини немає. Колір — власна
    # текстура шкіри манекена (нігті, складки), помножена під тон скану.
    # `--кисті-скану` (12.10.2026, слово замовника: «дуже помітні склейки
    # рук біля зап'ястя та ніг біля щиколоток»): кисть манекена (чоловіча,
    # r 3,5 см) на тонкій ельфійці (r 1,7 см) — стрибок товщини й тону;
    # суцільний скан без підміни — шва немає, пальці злиті.
    kysti = None
    if not KYSTI_SKANU:
        import bmesh
        ZAHID = 0.02
        DOVZH = 0.08
        zapiastok = abs(kist["hand_l"].x) - 0.015
        kistochka = kist["foot_l"].z + 0.04
        # Частина тіла: (чи вершина належить кисті/ступні, «вздовж» — відстань
        # до зрізу (додатна — у бік тіла), поперечні осі, межа для манекена).
        chastyny = [
            ("кисть", 1, lambda c: abs(c.x) > zapiastok and c.x > 0,
             lambda c: zapiastok - abs(c.x), ("y", "z")),
            ("кисть", -1, lambda c: abs(c.x) > zapiastok and c.x < 0,
             lambda c: zapiastok - abs(c.x), ("y", "z")),
            ("ступня", 1, lambda c: c.z < kistochka and c.x > 0,
             lambda c: c.z - kistochka, ("x", "y")),
            ("ступня", -1, lambda c: c.z < kistochka and c.x < 0,
             lambda c: c.z - kistochka, ("x", "y")),
        ]

        def kilce(tochky, vzdovzh, osi, shyr):
            smuga = [c for c in tochky if 0 <= vzdovzh(c) < shyr]
            if not smuga:
                return None, 0.0
            a0 = sum(getattr(c, osi[0]) for c in smuga) / len(smuga)
            a1 = sum(getattr(c, osi[1]) for c in smuga) / len(smuga)
            r = sorted(math.hypot(getattr(c, osi[0]) - a0, getattr(c, osi[1]) - a1)
                       for c in smuga)
            return (a0, a1), r[len(r) // 2]

        tilo_p = svit(tilo)
        bm = bmesh.new()
        bm.from_mesh(skan.data)
        for nazva, znak, nalezhyt, vzdovzh, osi in chastyny:
            bik = [c for c in tilo_p if c.x * znak > 0]
            c_m, r_m = kilce(bik, vzdovzh, osi, 0.03)
            zaivi = [v for v in bm.verts if nalezhyt(v.co)]
            bmesh.ops.delete(bm, geom=zaivi, context="VERTS")
            c_s, r_s = kilce([v.co for v in bm.verts if v.co.x * znak > 0],
                             vzdovzh, osi, 0.012)
            if c_m is None or c_s is None or r_s < 1e-4:
                print("[аватар] ‼ %s %+d: кільця не знайдено" % (nazva, znak))
                continue
            # Кінець скану трохи ширший за манекена — кисть сидить у ньому.
            r_m *= 1.1
            for v in bm.verts:
                if v.co.x * znak <= 0:
                    continue
                d = vzdovzh(v.co)
                if d < 0 or d >= DOVZH:
                    continue
                t = 1.0 - d / DOVZH
                f = 1.0 + (r_m / r_s - 1.0) * t
                for i, os_ in enumerate(osi):
                    c0 = c_s[i] + (c_m[i] - c_s[i]) * t
                    setattr(v.co, os_, c0 + (getattr(v.co, os_) - c_s[i]) * f)
            print("[аватар] %s %s: r %.3f → %.3f м, центр зсунуто на %.3f м"
                  % (nazva, "ліва" if znak > 0 else "права", r_s, r_m,
                     math.hypot(c_m[0] - c_s[0], c_m[1] - c_s[1])))
        kraj = [e for e in bm.edges if e.is_boundary and all(
            abs(x.co.x) > zapiastok - 0.02 or x.co.z < kistochka + 0.02
            for x in e.verts)]
        bmesh.ops.holes_fill(bm, edges=kraj, sides=0)
        bm.to_mesh(skan.data)
        bm.free()
        kolir = kolir_shkiry(skan, zapiastok)

        kysti = tilo.copy()
        kysti.data = tilo.data.copy()
        kysti.name = "Кисті й ступні"
        bpy.context.scene.collection.objects.link(kysti)
        mw = kysti.matrix_world
        bm = bmesh.new()
        bm.from_mesh(kysti.data)
        zaivi = [v for v in bm.verts
                 if not (abs((mw @ v.co).x) > zapiastok - ZAHID
                         or (mw @ v.co).z < kistochka + ZAHID)]
        bmesh.ops.delete(bm, geom=zaivi, context="VERTS")
        bm.to_mesh(kysti.data)
        bm.free()
        # Рідний матеріал манекена, колір помножено під скан: glTF віддає це
        # як baseColorFactor поверх текстури.
        mk = tilo.data.materials[0].copy()
        mk.name = "шкіра кистей і ступень"
        nodes, links = mk.node_tree.nodes, mk.node_tree.links
        bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
        # У манекена колір = текстура × колір вершин (вузол Mix); колір
        # вершин замінюємо множником під тон скану.
        mix = next((l.from_node for l in bsdf.inputs["Base Color"].links
                    if l.from_node.type == "MIX"), None)
        tex = next((l.from_node for i in (mix.inputs if mix else [])
                    for l in i.links if l.from_node.type == "TEX_IMAGE"), None)
        if mix is not None and tex is not None:
            sered = serednii_kolir(tex.image, kysti)
            syri = [kolir[i] / max(sered[i], 1e-3) for i in range(3)]
            # glTF не дає множника понад 1: якщо якийсь канал більший, ділимо
            # усі на нього — відтінок шкіри лишається точним, лише трохи темніше
            # (обрізання одного каналу зсувало відтінок у холодний).
            verkh = max(1.0, max(syri))
            mnozh = tuple(c / verkh for c in syri)
            print("[аватар]   шкіра скану %s, текстура манекена %s"
                  % (tuple(round(c, 3) for c in kolir),
                     tuple(round(c, 3) for c in sered)))
            # Тон — прямо в картинку: множник вузлом бачив Godot, але не
            # Workbench (оцінка) і не кожен експорт.
            import numpy as np
            src = tex.image
            w_, h_ = src.size
            px = np.empty(w_ * h_ * 4, dtype=np.float32)
            src.pixels.foreach_get(px)
            px = px.reshape(-1, 4)
            lin = np.where(px[:, :3] <= 0.04045, px[:, :3] / 12.92,
                           ((px[:, :3] + 0.055) / 1.055) ** 2.4) * np.array(mnozh)
            px[:, :3] = np.where(lin <= 0.0031308, lin * 12.92,
                                 1.055 * np.power(np.maximum(lin, 0), 1 / 2.4) - 0.055)
            nove = bpy.data.images.new("шкіра-кистей", w_, h_)
            nove.pixels.foreach_set(px.ravel())
            nove.pack()
            tex.image = nove
            links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
            nodes.remove(mix)
            print("[аватар] кисті й ступні: вершин %d, текстура манекена ×%s"
                  % (len(kysti.data.vertices), tuple(round(c, 2) for c in mnozh)))
        else:
            print("[аватар] ‼ у матеріалі манекена не знайшлось текстури кольору")
        mk.use_backface_culling = False
        kysti.data.materials.clear()
        kysti.data.materials.append(mk)

    # 3б. Перука зі скану голови (слово замовника 01.10.2026).
    peruka = zrobyty_peruku(PERUKA, skan, kist) if PERUKA else None

    # 4. На скелет.
    bpy.data.objects.remove(tilo)
    for o in [x for x in (skan, kysti, peruka) if x is not None]:
        o.parent = arm
        if not any(m.type == "ARMATURE" for m in o.modifiers):
            am = o.modifiers.new("Armature", "ARMATURE")
            am.object = arm
    # Двобічно: на грудях і животі в скані є перевернуті грані, і крізь
    # них було видно нутро («отвори у тулубі», 01.10.2026).
    for m in skan.data.materials:
        if m:
            m.use_backface_culling = False
    for m in skan.data.materials:
        for n in (m.node_tree.nodes if m and m.use_nodes else []):
            if n.type == "TEX_IMAGE" and n.image \
                    and n.image.size[0] > TEKSTURA:
                n.image.scale(TEKSTURA, TEKSTURA)
    # Нормалі — з форми (13.10.2026): імпорт glTF приносить нормалі
    # Pixal3D у вершинах, а підгонка плечей, колін і одна стінка рухали
    # вершини.
    import bmesh
    bm_ = bmesh.new()
    bm_.from_mesh(skan.data)
    # Складки (13.10.2026): дрібні загини сітки Pixal3D — трикутник
    # повернутий тильним боком проти сусідів (на ключицях e1903 ~20, на
    # руках і плечах ~300) — на світлі темні.
    def skladky():
        out = []
        for f in bm_.faces:
            s_ = f.normal * 0
            for e in f.edges:
                for g in e.link_faces:
                    if g is not f:
                        s_ += g.normal * g.calc_area()
            if s_.length > 0 and f.normal.dot(s_.normalized()) < 0:
                out.append(f)
        return out
    # Дрібні дірки (13.10.2026): одна стінка лишала ~470 отворів до 24 ребер
    # (250 — трикутні), крізь них видно виворіт — бурі цятки на ключицях
    # e1903. Латка — з розгорткою кута сусіда тієї ж вершини.
    uv_b = bm_.loops.layers.uv.get("UVMap")
    krai = [e for e in bm_.edges if e.is_boundary]
    lat = bmesh.ops.holes_fill(bm_, edges=krai, sides=24)["faces"]
    lat_s = set(lat)
    for f in lat:
        f.smooth = True
        for lp in f.loops:
            inshi = [l2 for l2 in lp.vert.link_loops if l2.face not in lat_s]
            if inshi and uv_b is not None:
                lp[uv_b].uv = inshi[0][uv_b].uv
    bm_.normal_update()
    print("[аватар] дірки: країв %d, латок %d, лишилось країв %d"
          % (len(krai), len(lat), sum(1 for e in bm_.edges if e.is_boundary)))
    # Розгладжування їх не розгортає (437 → 388) — загин ~0,1 мм, тож
    # грань просто перевертається за сусідами: шейдинг більше не темний.
    # (Перерахунок «назовні» для всієї сітки — ні: латки очей — окремі
    # острівці, і він перевертав їх задом наперед — «скляні окуляри».)
    pochatok = len(skladky())
    for _ in range(10):
        sk = skladky()
        if not sk:
            break
        bmesh.ops.reverse_faces(bm_, faces=sk)
        bm_.normal_update()
    print("[аватар] складки: %d → %d" % (pochatok, len(skladky())))
    bm_.to_mesh(skan.data)
    bm_.free()
    if skan.data.has_custom_normals:
        with bpy.context.temp_override(object=skan, active_object=skan):
            bpy.ops.mesh.customdata_custom_splitnormals_clear()
    skan.data.polygons.foreach_set("use_smooth", [True] * len(skan.data.polygons))
    print("[аватар] нормалі з форми, власних нормалей:", skan.data.has_custom_normals)
    # Мапа нормалей Pixal3D — геть (13.10.2026): після одної стінки, колін,
    # підгонки плечей і латок очей вона вже не збігається з сіткою; на
    # латках очей (новий прямокутник атласу) — сміття, «скляні окуляри».
    for m in skan.data.materials:
        for n in (m.node_tree.nodes if m and m.use_nodes else []):
            if n.type == "BSDF_PRINCIPLED":
                for l in list(n.inputs["Normal"].links):
                    m.node_tree.links.remove(l)
    os.makedirs(os.path.dirname(KUDY), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=KUDY, export_format="GLTF_SEPARATE",
                              export_animations=False, export_skins=True,
                              export_yup=True)
    print("[аватар] →", KUDY)
    if KADRY:
        kadry(arm, skan)


def vyrivniaty_oblychchia(skan, pered):
    """`--обличчя` (12.10.2026, слово замовника: «неприродні контури навколо
    очей»): голова в кадрі й голова Pixal3D мають трохи різні пропорції, і
    лінійна проєкція клала намальовані очі й губи на ~2 см вище за виліплені
    — під очима виднілись ободки очниць. Тут: рендер голови скану спереду →
    MediaPipe (`tools/oblychchia_holova.py`) → точки обличчя G у (x, z)
    сітки; ті самі точки F на кадрі (`tools/oblychchia.py`). Нев'язку
    розгортки «Проєкція» в точках G розносимо гаусовим RBF (σ 1,2 см), що
    згасає поза обличчям. Повертає G (478×2, x/z) або None."""
    import subprocess
    import numpy as np
    venv = os.path.expanduser("~/Програми/cv-venv/bin/python")
    tut = os.path.dirname(os.path.abspath(REF_MASKA))
    npy_f = os.path.join(tut, os.path.basename(REF)[:-4] + "-tochky.npy")
    if not os.path.exists(npy_f):
        r = subprocess.run([venv, os.path.join(ROOT, "tools", "oblychchia.py"),
                            os.path.abspath(REF), os.path.abspath(REF_MASKA), npy_f],
                           capture_output=True, text=True)
        print(r.stdout.strip() or r.stderr[-300:])
    F = np.load(npy_f)
    me = skan.data
    mw = skan.matrix_world
    co = np.array([(mw @ v.co)[:] for v in me.vertices])
    ztop = co[:, 2].max()
    # 1. Рендер голови спереду (Workbench, текстура Pixal3D).
    sc = bpy.context.scene
    stari = {o: o.hide_render for o in sc.objects}
    for o in sc.objects:
        o.hide_render = o is not skan
    RES, SCALE = 1024, 0.30
    cz = ztop - 0.12
    hd = co[co[:, 2] > ztop - 0.25]
    cx = float(np.median(hd[:, 0]))
    kam_d = bpy.data.cameras.new("obl")
    kam_d.type = "ORTHO"
    kam_d.ortho_scale = SCALE
    kam = bpy.data.objects.new("obl", kam_d)
    sc.collection.objects.link(kam)
    kam.location = (cx, pered * 3.0, cz)
    kam.rotation_euler = (Vector((cx, 0, cz)) - Vector(kam.location)).to_track_quat(
        "-Z", "Y").to_euler()
    stara_kam, stary_eng = sc.camera, sc.render.engine
    sc.camera = kam
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "FLAT"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = RES
    sc.render.resolution_percentage = 100
    png = os.path.join(tut, os.path.basename(REF)[:-4] + "-holova-render.png")
    sc.render.filepath = png
    bpy.ops.render.render(write_still=True)
    sc.camera, sc.render.engine = stara_kam, stary_eng
    sc.render.film_transparent = False
    bpy.data.objects.remove(kam)
    for o, b_ in stari.items():
        o.hide_render = b_
    npy_g = png[:-4] + ".npy"
    r = subprocess.run([venv, os.path.join(ROOT, "tools", "oblychchia_holova.py"),
                        png, npy_g], capture_output=True, text=True)
    print(r.stdout.strip() or r.stderr[-300:])
    if r.returncode != 0:
        print("[аватар] ‼ обличчя: точок на рендері немає — без вирівнювання")
        return None
    Lg = np.load(npy_g)
    # камера з боку `pered`: праворуч кадру +X, якщо pered < 0
    sx = 1.0 if pered < 0 else -1.0
    G = np.stack([cx + sx * (Lg[:, 0] / RES - 0.5) * SCALE,
                  cz + (0.5 - Lg[:, 1] / RES) * SCALE], 1)
    return G


def pryviazaty_uv(skan, pered, G, rukhomi=None):
    """Нев'язку розгортки «Проєкція» в точках обличчя G (x, z сітки) —
    до тих самих точок F на кадрі, гаусовим RBF (σ 1,2 см). `rukhomi` —
    вершини, які `zgladyty_ochi` пересунула: їхні кути спершу отримують
    лінійну проєкцію з нового положення."""
    import numpy as np
    tut = os.path.dirname(os.path.abspath(REF_MASKA))
    F = np.load(os.path.join(tut, os.path.basename(REF)[:-4] + "-tochky.npy"))
    me = skan.data
    mw = skan.matrix_world
    co = np.array([(mw @ v.co)[:] for v in me.vertices])
    # 2. Розгортка «Проєкція»: лінійна від (x, z) — підбір по самих вершинах.
    uvl = me.uv_layers["Проєкція"].data
    vi_l = np.empty(len(me.loops), dtype=np.int64)
    me.loops.foreach_get("vertex_index", vi_l)
    uv = np.empty(len(me.loops) * 2, dtype=np.float32)
    uvl.foreach_get("uv", uv)
    uv = uv.reshape(-1, 2).astype(float)
    xz = co[vi_l][:, [0, 2]]
    A = np.c_[np.ones(len(xz)), xz]
    stali = np.ones(len(xz), bool) if rukhomi is None else ~rukhomi[vi_l]
    cu = np.linalg.lstsq(A[stali][::7], uv[stali][::7, 0], rcond=None)[0]
    cv = np.linalg.lstsq(A[stali][::7], uv[stali][::7, 1], rcond=None)[0]
    if rukhomi is not None:
        r_ = ~stali
        uv[r_, 0] = A[r_] @ cu
        uv[r_, 1] = A[r_] @ cv
    w_, h_ = bpy.data.images.load(os.path.abspath(REF)).size
    Fu = F[:, 0] / w_
    Fv = 1.0 - F[:, 1] / h_
    Ag = np.c_[np.ones(len(G)), G]
    R = np.stack([Fu - Ag @ cu, Fv - Ag @ cv], 1)
    zsuv_cm = np.abs(R[:, 1]).mean() / abs(cv[2]) * 100
    # 3. RBF: лише кути з передньої півсфери голови
    nr = np.array([(mw.to_3x3() @ v.normal)[:] for v in me.vertices])[vi_l]
    tut_m = (xz[:, 1] > G[:, 1].min() - 0.06) & (nr[:, 1] * pered > -0.3)
    S2 = 2 * 0.012 ** 2
    idx = np.where(tut_m)[0]
    for s0 in range(0, len(idx), 20000):
        ch = idx[s0:s0 + 20000]
        d2 = ((xz[ch, None, :] - G[None, :, :]) ** 2).sum(-1)
        wg = np.exp(-d2 / S2)
        uv[ch] += (wg @ R) / (wg.sum(1, keepdims=True) + 0.05)
    uvl.foreach_set("uv", uv.astype(np.float32).ravel())
    print("[аватар] обличчя: точок %d, середній зсув текстури %.1f см, кутів %d"
          % (len(G), zsuv_cm, len(idx)))
    # Видимість — наново для зсунутих кутів (13.10.2026): «Видимість»
    # рахувалась до RBF, і кути боків голови після зсуву брали тло кадру
    # за силуетом — сірі латки на скронях і шиї (e1903, l2002). Тепер кут,
    # чий новий піксель поза звуженою маскою, бере Pixal3D.
    if "Видимість" in me.color_attributes:
        mi = bpy.data.images.load(os.path.abspath(REF_MASKA))
        mw_, mh_ = mi.size
        mp = np.empty(mw_ * mh_ * 4, dtype=np.float32)
        mi.pixels.foreach_get(mp)
        vuzka = mp.reshape(mh_, mw_, 4)[..., 0] > 0.5
        for _ in range(max(5, int(round(5 * mw_ / 1024)))):
            vuzka = vuzka & np.roll(vuzka, 1, 0) & np.roll(vuzka, -1, 0) \
                & np.roll(vuzka, 1, 1) & np.roll(vuzka, -1, 1)
        vyd = me.color_attributes["Видимість"]
        kol = np.empty(len(me.loops) * 4, dtype=np.float32)
        vyd.data.foreach_get("color", kol)
        kol = kol.reshape(-1, 4)
        ch = idx
        yy = np.clip((uv[ch, 1] * mh_).astype(int), 0, mh_ - 1)
        xx = np.clip((uv[ch, 0] * mw_).astype(int), 0, mw_ - 1)
        poza = ~vuzka[yy, xx] & (kol[ch, 0] > 0)
        # латки очей — не чіпати: у Pixal3D під ними нічого (новий атлас)
        if rukhomi is not None:
            poza &= ~rukhomi[vi_l[ch]]
        kol[ch[poza], :3] = 0.0
        vyd.data.foreach_set("color", kol.ravel())
        print("[аватар] обличчя: кутів поза силуетом після зсуву %d → Pixal3D"
              % int(poza.sum()))


def zgladyty_ochi(skan, pered, G):
    """`--очі` — очниці наново, симетрично (12.10.2026, третя ітерація;
    слово замовника: «очні впадини не симетрично знову мають артефакти»).

    Замір: сітка Pixal3D навколо очей зібгана — у кільці 12…20 мм від
    контуру половина граней повернута назад; правка глибини чи
    розтягування наявних вершин складок не прибирали. Тепер:
      1. контур ока — середнє лівого й дзеркального правого (вісь — ніс,
         губи, підборіддя);
      2. грані очниці (≤21 мм від контуру, без перенісся ±7 мм) — геть, лишається дірка;
      3. дірка — нова рівна сітка: точки через 1,8 мм + край дірки,
         обмежена тріангуляція Делоне (mathutils.geometry.delaunay_2d_cdt);
      4. глибина — квадратична поверхня, спільна для обох очей
         (дзеркально) + власний нахил кожного боку; очна щілина на
         1,5 мм глибше, повіка +0,6 мм; нев'язка з краєм дірки згасає за
         6 мм;
      5. розгортка «UVMap» латки — у вільне місце атласу (запікання
         малює туди очі з кадру).
    Повертає (G з симетричними контурами, маска нових/крайових вершин)."""
    import numpy as np
    import bmesh
    from mathutils import geometry as mg
    OKO = ([33, 7, 163, 144, 145, 153, 154, 155, 133, 173, 157, 158, 159, 160, 161, 246],
           [263, 249, 390, 373, 374, 380, 381, 382, 362, 398, 384, 385, 386, 387, 388, 466])
    # 21 мм: зібгана смуга сягає 20 мм (замір), 16 мм лишали сіре кільце
    RZ, OPORA1, KROK_S, NIS = 0.021, 0.027, 0.0018, 0.007
    G = G.copy()
    x_mid = float(np.median(G[[1, 4, 5, 6, 168, 197, 195, 0, 17, 152, 13, 14], 0]))

    def dzerk(p):
        q = p.copy()
        q[..., 0] = 2 * x_mid - q[..., 0]
        return q
    L, R_ = G[OKO[0]], G[OKO[1]]
    Ls = (L + dzerk(R_)) / 2
    print("[аватар] очі: асиметрія контурів до %.1f мм (середня %.1f)"
          % (np.abs(L - dzerk(R_)).max() * 1000, np.abs(L - dzerk(R_)).mean() * 1000))
    G[OKO[0]] = Ls
    G[OKO[1]] = dzerk(Ls)
    ir = (G[468] + dzerk(G[473][None])[0]) / 2
    G[468:473] += ir - G[468]
    G[473:478] += dzerk(ir[None])[0] - G[473]
    konturs = (G[OKO[0]], G[OKO[1]])

    def vidstan(xz, kontur):
        c = kontur.mean(0)
        ax = max((kontur[:, 0].max() - kontur[:, 0].min()) / 2, 1e-3)
        az = max((kontur[:, 1].max() - kontur[:, 1].min()) / 2, 1e-3)
        dx, dz = xz[:, 0] - c[0], xz[:, 1] - c[1]
        k = np.sqrt((dx / ax) ** 2 + (dz / az) ** 2)
        th = np.arctan2(dz, dx)
        r_dir = 1.0 / np.sqrt((np.cos(th) / ax) ** 2 + (np.sin(th) / az) ** 2)
        return (k - 1.0) * r_dir

    me = skan.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    co = np.array([v.co[:] for v in bm.verts])
    hd = co[co[:, 2] > G[:, 1].min() - 0.02]
    cy = float(np.median(hd[:, 1]))
    pered_m = (co[:, 1] - cy) * pered > 0.0
    d_k = [vidstan(co[:, [0, 2]], k_) for k_ in konturs]
    storona = [np.sign(co[:, 0] - x_mid) == np.sign(k_[:, 0].mean() - x_mid) for k_ in konturs]

    # Поверхня глибини (друга проба: квадратика давала «куполи» з ямою
    # довкола — у грі брови кидали на них темну смугу тіні): згладжена
    # форма самого скану. Площина кожного боку — по кільцю RZ…OPORA1;
    # відхил від площини — гаусове середнє (σ 4 мм) вершин скану обох очей
    # (правого — дзеркально), повернутих уперед: складки (грані назад)
    # не беруться, обидві очниці однакові.
    def v_liva(x, k):
        return x if k == 0 else 2 * x_mid - x
    bm.normal_update()
    nrm_y = np.array([v.normal.y for v in bm.verts])
    plaskyny = []
    tochky = []
    for k in range(2):
        i = np.where(pered_m & storona[k] & (d_k[k] >= RZ) & (d_k[k] <= OPORA1)
                     & (np.abs(co[:, 0] - x_mid) > NIS))[0]
        if len(i) < 12:
            print("[аватар] ‼ очі: мало опорних вершин", len(i))
            bm.free()
            return G, None
        A = np.c_[np.ones(len(i)), co[i, 0], co[i, 2]]
        pl = np.linalg.lstsq(A, co[i, 1], rcond=None)[0]
        plaskyny.append(pl)
        j = np.where(pered_m & storona[k] & (d_k[k] < OPORA1) & (nrm_y * pered > 0.25))[0]
        tochky.append(np.c_[v_liva(co[j, 0], k), co[j, 2],
                            co[j, 1] - (pl[0] + pl[1] * co[j, 0] + pl[2] * co[j, 2])])
    tochky = np.vstack(tochky)

    def glyb(x, z, k):
        pl = plaskyny[k]
        xl = v_liva(x, k)
        d2 = (xl[:, None] - tochky[None, :, 0]) ** 2 + (z[:, None] - tochky[None, :, 1]) ** 2
        w = np.exp(-d2 / (2 * 0.004 ** 2))
        vidkh = (w @ tochky[:, 2]) / np.maximum(w.sum(1), 1e-9)
        y = pl[0] + pl[1] * x + pl[2] * z + vidkh
        d = vidstan(np.stack([x, z], -1), konturs[k])
        shchil = np.where(d < 0, -0.0012 * np.clip(-d / 0.002, 0, 1),
                          0.0005 * np.clip(1 - np.abs(d - 0.0012) / 0.0012, 0, 1))
        return y + pered * shchil

    uv_l = bm.loops.layers.uv["UVMap"]
    vyd_l = bm.loops.layers.float_color.get("Видимість")
    # зайнятість атласу (256²) — для місця латки
    zain = np.zeros((256, 256), bool)
    for f in bm.faces:
        us = [l[uv_l].uv for l in f.loops]
        u0_, u1_ = min(u.x for u in us), max(u.x for u in us)
        v0_, v1_ = min(u.y for u in us), max(u.y for u in us)
        zain[int(np.clip(v0_, 0, 1) * 255):int(np.clip(v1_, 0, 1) * 255) + 1,
             int(np.clip(u0_, 0, 1) * 255):int(np.clip(u1_, 0, 1) * 255) + 1] = True
    nove_v = []
    for k in range(2):
        # не далі 1 см за зовнішнім кутиком ока (13.10.2026): на вузькій
        # голові ельфійки e1903 зона 2,1 см від контуру в проєкції спереду
        # заходила на скроню й бік голови — латка з видимістю 1 розмазувала
        # там кадр сірими плямами
        kraj_x = np.abs(konturs[k][:, 0] - x_mid).max() + 0.01
        zona = pered_m & storona[k] & (d_k[k] < RZ) & (np.abs(co[:, 0] - x_mid) > NIS) \
            & (np.abs(co[:, 0] - x_mid) < kraj_x)
        zv = set(np.where(zona)[0].tolist())
        geth = [f for f in bm.faces if any(v.index in zv for v in f.verts)]
        bmesh.ops.delete(bm, geom=geth, context="FACES")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        c_ok = konturs[k].mean(0)
        # зубці по краю дірки (грань з ≥2 граничними ребрами) — геть, кілька
        # проходів: інакше край розпадається на кілька петель і між латкою й
        # обличчям лишається рвана щілина (проба 12.10)
        for _ in range(6):
            zubtsi = [f for f in bm.faces
                      if sum(1 for e in f.edges if e.is_boundary) >= 2
                      and np.hypot(f.calc_center_median().x - c_ok[0],
                                   f.calc_center_median().z - c_ok[1]) < 0.05
                      and (f.calc_center_median().y - cy) * pered > 0]
            if not zubtsi:
                break
            bmesh.ops.delete(bm, geom=zubtsi, context="FACES")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        bm.verts.ensure_lookup_table()
        bm.verts.index_update()
        # край дірки: граничні ребра поблизу ока, найдовша петля
        kr = [e for e in bm.edges if e.is_boundary and all(
            (v.co.y - cy) * pered > 0 and np.hypot(v.co.x - c_ok[0], v.co.z - c_ok[1]) < 0.05
            for v in e.verts)]
        sus = {}
        for e in kr:
            a_, b_ = e.verts
            sus.setdefault(a_, []).append(b_)
            sus.setdefault(b_, []).append(a_)
        petli, bachyly = [], set()
        for v0 in sus:
            if v0 in bachyly:
                continue
            petlia, v, prev = [v0], v0, None
            bachyly.add(v0)
            while True:
                nxt = [u for u in sus[v] if u is not prev and u not in bachyly]
                if not nxt:
                    break
                prev, v = v, nxt[0]
                bachyly.add(v)
                petlia.append(v)
            petli.append(petlia)
        petlia = max(petli, key=len)
        bxz = np.array([(v.co.x, v.co.z) for v in petlia])
        # точки всередині (не ближче 1,2 мм до краю)
        def vseredyni(pt, poly):
            x, z = pt[:, 0], pt[:, 1]
            ins = np.zeros(len(pt), bool)
            j = len(poly) - 1
            for i in range(len(poly)):
                xi, zi = poly[i]
                xj, zj = poly[j]
                perekr = ((zi > z) != (zj > z)) & \
                    (x < (xj - xi) * (z - zi) / (zj - zi + 1e-12) + xi)
                ins ^= perekr
                j = i
            return ins
        x0_, z0_ = bxz.min(0)
        x1_, z1_ = bxz.max(0)
        gx, gz = np.meshgrid(np.arange(x0_, x1_, KROK_S), np.arange(z0_, z1_, KROK_S))
        gp = np.stack([gx.ravel(), gz.ravel()], 1)
        gp[1::2, 0] += KROK_S / 2 * 0           # рівна сітка
        gp = gp[vseredyni(gp, bxz)]
        if len(gp):
            dmin = np.min(np.linalg.norm(gp[:, None, :] - bxz[None, :, :], axis=2), 1)
            gp = gp[dmin > 0.0012]
        # CCW
        plosha = 0.5 * np.sum(bxz[:, 0] * np.roll(bxz[:, 1], -1) - np.roll(bxz[:, 0], -1) * bxz[:, 1])
        poryadok = list(range(len(petlia)))
        if plosha < 0:
            poryadok = poryadok[::-1]
        nb = len(petlia)
        vc = [Vector((float(x), float(z))) for x, z in np.vstack([bxz, gp])]
        out = mg.delaunay_2d_cdt(vc, [], [poryadok], 1, 1e-7, True)
        o_vc, _, o_f, o_orig = out[0], out[1], out[2], out[3]
        print("[аватар] очі: CDT вершин %d→%d, крайових у виході %d з %d" % (
            len(vc), len(o_vc), sum(1 for o_ in o_orig if any(x < nb for x in o_)), nb))
        # нев'язка краю: глибина краю − поверхня, згасає за 6 мм
        nev = np.array([v.co.y for v in petlia]) - glyb(bxz[:, 0], bxz[:, 1], k)
        bverts = []
        for oi, p2 in enumerate(o_vc):
            orig = [x for x in o_orig[oi] if x < nb]
            if orig:
                bverts.append(petlia[orig[0]])
                continue
            x, z = float(p2.x), float(p2.y)
            y = float(glyb(np.array([x]), np.array([z]), k)[0])
            dd = np.hypot(bxz[:, 0] - x, bxz[:, 1] - z)
            w = 1.0 / np.maximum(dd, 1e-4) ** 2
            y += float((w * nev).sum() / w.sum()) * float(np.clip(1 - dd.min() / 0.006, 0, 1))
            nv_ = bm.verts.new((x, y, z))
            bverts.append(nv_)
            nove_v.append(nv_)
        bm.verts.index_update()
        # місце в атласі: прямокутник за розміром латки (3000 px/м на 4096)
        shyr_uv = (x1_ - x0_) * 3000 / 4096
        vys_uv = (z1_ - z0_) * 3000 / 4096
        nw, nh = int(shyr_uv * 256) + 3, int(vys_uv * 256) + 3
        mistse = None
        for r0 in range(0, 256 - nh, 2):
            for c0 in range(0, 256 - nw, 2):
                if not zain[r0:r0 + nh, c0:c0 + nw].any():
                    mistse = (r0, c0)
                    break
            if mistse:
                break
        if mistse is None:
            mistse = (0, 0)
            print("[аватар] ‼ очі: в атласі немає вільного місця")
        zain[mistse[0]:mistse[0] + nh, mistse[1]:mistse[1] + nw] = True
        u_0, v_0 = (mistse[1] + 1) / 256, (mistse[0] + 1) / 256
        latky = []
        for tri in o_f:
            vv = [bverts[i] for i in tri]
            if len(set(vv)) < 3:
                continue
            try:
                f = bm.faces.new(vv)
            except ValueError:
                continue
            f.normal_update()
            if f.normal.y * pered < 0:
                f.normal_flip()
            f.smooth = True
            latky.append(f)
            for lp in f.loops:
                lp[uv_l].uv = (u_0 + (lp.vert.co.x - x0_) * 3000 / 4096,
                               v_0 + (lp.vert.co.z - z0_) * 3000 / 4096)
                if vyd_l is not None:
                    lp[vyd_l] = (1, 1, 1, 1)
        print("[аватар] очі: бік %d — край %d вершин, нових %d, трикутників %d, атлас (%.3f, %.3f)"
              % (k, nb, len(gp), len(latky), u_0, v_0))
        bm.verts.ensure_lookup_table()
        co = np.array([v.co[:] for v in bm.verts])
        pered_m = (co[:, 1] - cy) * pered > 0.0
        d_k = [vidstan(co[:, [0, 2]], k_) for k_ in konturs]
        storona = [np.sign(co[:, 0] - x_mid) == np.sign(k_[:, 0].mean() - x_mid) for k_ in konturs]
        bm.normal_update()
        nrm_y = np.array([v.normal.y for v in bm.verts])
    # дрібні дірки, що лишились між латкою й обличчям, — латками з
    # розгорткою в точку (кут сусіда)
    for k in range(2):
        c_ok = konturs[k].mean(0)
        kr = [e for e in bm.edges if e.is_boundary and all(
            (v.co.y - cy) * pered > 0 and np.hypot(v.co.x - c_ok[0], v.co.z - c_ok[1]) < 0.045
            for v in e.verts)]
        print("[аватар] очі: бік %d — граничних ребер після латки %d" % (k, len(kr)))
        if not kr:
            continue
        dod = bmesh.ops.holes_fill(bm, edges=kr, sides=60)["faces"]
        dod_s = set(dod)
        for f in dod:
            f.smooth = True
            dz = None
            for lp in f.loops:
                inshi = [l2 for l2 in lp.vert.link_loops if l2.face not in dod_s]
                if inshi:
                    dz = inshi[0]
                    break
            for lp in f.loops:
                # кожен кут — розгортка своєї вершини (13.10.2026): з одним
                # кутом сусіда на всю латку вона була одного кольору —
                # біла риска від кутика ока e1903
                inshi = [l2 for l2 in lp.vert.link_loops if l2.face not in dod_s]
                if inshi:
                    lp[uv_l].uv = inshi[0][uv_l].uv
                elif dz is not None:
                    lp[uv_l].uv = dz[uv_l].uv
                if vyd_l is not None:
                    lp[vyd_l] = (1, 1, 1, 1)
        print("[аватар] очі: бік %d — дрібних дірок закрито %d" % (k, len(dod)))
    # м'який шов: глибина нових вершин і першого кільця сусідів —
    # кілька проходів середнього (лише y)
    shov = set(nove_v)
    for v in nove_v:
        for e in v.link_edges:
            shov.add(e.other_vert(v))
    shov = [v for v in shov if not v.is_boundary]
    for _ in range(6):
        nove_y = {v: sum(e.other_vert(v).co.y for e in v.link_edges) / len(v.link_edges)
                  for v in shov if v.link_edges}
        for v, y in nove_y.items():
            v.co.y += (y - v.co.y) * 0.5
    # смуга вздовж шва (RZ−4…RZ+9 мм): Taubin усіх координат — розгорнути
    # рештки складок за межею латки; перед обличчя біля очей — колір з
    # кадру (Видимість 1), не сіра текстура Pixal3D з виворіту складки
    bm.verts.ensure_lookup_table()
    bm.verts.index_update()
    cur = np.array([v.co[:] for v in bm.verts])
    dmin = np.minimum(vidstan(cur[:, [0, 2]], konturs[0]), vidstan(cur[:, [0, 2]], konturs[1]))
    front_c = (cur[:, 1] - cy) * pered > 0.0
    w5 = np.where(front_c, np.clip(1 - np.abs(dmin - (RZ + 0.0025)) / 0.0065, 0, 1), 0.0)
    # перенісся між латками — теж (зібгане, лишало щілину)
    nis_ = front_c & (np.abs(cur[:, 0] - x_mid) < NIS + 0.003) & (dmin < RZ + 0.004) \
        & (cur[:, 2] > min(k_[:, 1].min() for k_ in konturs) - 0.01)
    w5 = np.maximum(w5, nis_.astype(float))
    ed5 = np.array([(e.verts[0].index, e.verts[1].index) for e in bm.edges])
    st5 = np.bincount(ed5.ravel(), minlength=len(cur)).astype(float)

    def lap5(x):
        s_ = np.zeros_like(x)
        np.add.at(s_, ed5[:, 0], x[ed5[:, 1]])
        np.add.at(s_, ed5[:, 1], x[ed5[:, 0]])
        return s_ / np.maximum(st5, 1)[:, None] - x
    for _ in range(60):
        cur += (0.5 * w5)[:, None] * lap5(cur)
        cur += (-0.53 * w5)[:, None] * lap5(cur)
    for vi in np.where(w5 > 0)[0]:
        bm.verts[vi].co = cur[vi]
    if vyd_l is not None:
        blyz = front_c & (dmin < RZ + 0.012)
        # і лише грані, хоч трохи повернуті вперед (13.10.2026): «передня
        # половина» на 3,3 см від очей — це й бік вузької голови e1903; але
        # й скроню (нахил від 0,15) — кадр: у Pixal3D довкола очей темні
        # «окуляри», і суміш давала сіру пляму біля кутика ока
        bm.normal_update()
        for f in bm.faces:
            if f.normal.y * pered < 0.15:
                continue
            if all(blyz[v.index] for v in f.verts):
                for lp in f.loops:
                    lp[vyd_l] = (1, 1, 1, 1)
    nove_v = set(nove_v) | {bm.verts[i] for i in np.where(w5 > 0)[0]}
    bm.verts.index_update()
    nove_i = {v.index for v in nove_v}
    rukhomi = np.zeros(len(bm.verts), bool)
    rukhomi[list(nove_i)] = True
    bm.to_mesh(me)
    bm.free()
    me.update()
    if os.environ.get("OCHI_DBG"):
        bpy.ops.wm.save_as_mainfile(filepath=os.environ["OCHI_DBG"])
    return G, rukhomi


def skalp(skan, pered, G):
    """Атрибут вершин «Скальп» (1 — волосяна частина голови) для маски
    кольору зачіски там, де кадр спереду голови не бачить (потилиця,
    маківка згори). Сфера черепа — підбір по вершинах вище лінії росту
    волосся (точка 10); вуха стирчать за 1,1 радіуса й не входять."""
    import numpy as np
    me = skan.data
    co = np.array([v.co[:] for v in me.vertices])
    z_chola = G[10, 1]
    verkh = co[co[:, 2] > z_chola]
    A = np.c_[2 * verkh, np.ones(len(verkh))]
    b = (verkh ** 2).sum(1)
    c4 = np.linalg.lstsq(A, b, rcond=None)[0]
    C = c4[:3]
    R = float(np.sqrt(c4[3] + (C ** 2).sum()))
    d = np.linalg.norm(co - C, axis=1)
    z_potylytsi = G[13, 1]                    # лінія росту ззаду ≈ рівень губ
    nazad = (co[:, 1] - C[1]) * pered < -0.25 * R
    m = (d < R * 1.1) & ((co[:, 2] > z_chola + 0.004)
                         | (nazad & (co[:, 2] > z_potylytsi)))
    # м'який край: 1 см униз від межі
    w = m.astype(float)
    at = me.color_attributes.new("Скальп", "FLOAT_COLOR", "POINT")
    kol = np.zeros((len(co), 4), np.float32)
    kol[:, :3] = w[:, None]
    kol[:, 3] = 1
    at.data.foreach_set("color", kol.ravel())
    print("[аватар] скальп: сфера R %.3f м, вершин %d" % (R, int(m.sum())))


def proektsiia(skan, pered):
    """Друга розгортка «Проєкція» — піксель референсу, з якого видно кожну
    вершину спереду, і «Видимість» — наскільки грань дивиться на камеру.

    Pixal3D будує сітку саме з цього кадру, тож у сирій формі (до підгонки
    рук і ніг під манекен) габарит сітки спереду лягає на габарит фігури
    на кадрі. Колір звідси, а не з розмитої текстури Pixal3D — обличчя,
    пасма спереду, тон шкіри й тканина (02.10.2026, «схожою на референс
    не менш як на 95%»)."""
    import numpy as np
    skan.data.update()
    m = bpy.data.images.load(os.path.abspath(REF_MASKA))
    w, h = m.size
    px = np.empty(w * h * 4, dtype=np.float32)
    m.pixels.foreach_get(px)
    maska = px.reshape(h, w, 4)[..., 0] > 0.5     # рядок 0 — низ кадру
    # Звужена маска: на краю фігури проєкція брала пікселі тла (сірі
    # смуги по силуету, ітерація 1).
    vuzka = maska.copy()
    # 5 px — на кадрі 1024; на 4K — пропорційно (13.10.2026: 5 px 4K лишали
    # змішані з тлом пікселі краю — сіро-блакитні смуги на скронях e1903)
    for _ in range(max(5, int(round(5 * w / 1024)))):
        vuzka = vuzka & np.roll(vuzka, 1, 0) & np.roll(vuzka, -1, 0) \
            & np.roll(vuzka, 1, 1) & np.roll(vuzka, -1, 1)
    ys, xs = np.where(maska)
    u0, u1 = xs.min() / w, (xs.max() + 1) / w
    v0, v1 = ys.min() / h, (ys.max() + 1) / h
    me = skan.data
    lo, hi = mezhi([v.co for v in me.vertices])
    if PRYVIAZKA_OSI != "однаково":
        pass
    # Однаковий масштаб по обох осях (ітерація 9): кадр і ортопроєкція
    # зберігають пропорції, а ширину габариту задають кінчики пальців —
    # розчепірені на кадрі й злиплі в скані, і розтягнення ширини окремо
    # стискало все по X. Масштаб — з висоти, центр по X — з габариту.
    if PRYVIAZKA_OSI == "однаково":
        px_na_m = (v1 - v0) * h / (hi.z - lo.z)
        shyr_u = (hi.x - lo.x) * px_na_m / w
        cu = (u0 + u1) / 2
        u0, u1 = cu - shyr_u / 2, cu + shyr_u / 2
    # Прив'язка по рядках (ітерація 3) — ВИМКНЕНА: на висоті рук «краї» —
    # кінчики пальців, а розчепірені на кадрі й злиплі в скані пальці різної
    # ширини, і груди розтягувало (71,6% проти 74,8%). Лінійна проєкція
    # спереду й ортокамера лінійні обидві — проєкція відтворює кадр.
    ryadky = 512
    def gladko(a_):
        k_ = 5
        p_ = np.pad(a_, k_, mode="edge")
        return np.convolve(p_, np.ones(2 * k_ + 1) / (2 * k_ + 1), "valid")
    rL = np.full(ryadky, np.nan)
    rR = np.full(ryadky, np.nan)
    for i in range(ryadky):
        y = int(v0 * h + (i + 0.5) / ryadky * (v1 - v0) * h)
        xs_ = np.where(maska[min(h - 1, y)])[0]
        if xs_.size:
            rL[i], rR[i] = xs_.min() / w, (xs_.max() + 1) / w
    sL = np.full(ryadky, np.nan)
    sR = np.full(ryadky, np.nan)
    for v in me.vertices:
        i = min(ryadky - 1, int((v.co.z - lo.z) / (hi.z - lo.z) * ryadky))
        x = (v.co.x - lo.x) / (hi.x - lo.x)
        if pered > 0:
            x = 1.0 - x
        sL[i] = x if np.isnan(sL[i]) else min(sL[i], x)
        sR[i] = x if np.isnan(sR[i]) else max(sR[i], x)
    for a_ in (rL, rR, sL, sR):
        ok_ = ~np.isnan(a_)
        a_[~ok_] = np.interp(np.where(~ok_)[0], np.where(ok_)[0], a_[ok_])
    rL, rR, sL, sR = gladko(rL), gladko(rR), gladko(sL), gladko(sR)
    # Точна прив'язка (ітерація 6): габарит сітки Pixal3D після згладження
    # трохи більший за фігуру на кадрі, тож масштаб і зсув «габарит →
    # маска» хибили на кілька пікселів (найбільше на обличчі). Підбираємо
    # окремо по кожній осі: профіль заповнення рядків (стовпців) точками
    # сітки проти профілю маски.
    # Профіль — стільки клітин, скільки рядків у маски (кадр квадратний):
    # стале 1024 падало на кадрі 4K (11.10.2026, обличчя ельфійки).
    N = h
    tochky = np.array([((v.co.x - lo.x) / (hi.x - lo.x),
                        (v.co.z - lo.z) / (hi.z - lo.z))
                       for v in me.vertices])
    if pered > 0:
        tochky[:, 0] = 1.0 - tochky[:, 0]
    # Профіль форми: на кожному рядку — ширина фігури (крайній правий −
    # крайній лівий піксель), на кожному стовпці — висота. Голова, плечі,
    # руки, талія, ноги дають різну ширину, і на ній видно зсув і масштаб.
    def rozmah(m2, vis):
        any_ = m2.any(axis=vis)
        perv = np.argmax(m2, axis=vis)
        ost = m2.shape[vis] - 1 - np.argmax(np.flip(m2, axis=vis), axis=vis)
        return np.where(any_, ost - perv, 0).astype(float) / m2.shape[vis]
    # Лише центральна смуга ±20% ширини фігури: розчепірені пальці кадру й
    # злиплі кисті скану різної ширини і тягли масштаб u в межу (ітер. 6).
    cx = (u0 + u1) / 2
    pol = (u1 - u0) * 0.2
    smuga_m = maska.copy()
    kol = np.arange(w) / w
    smuga_m[:, (kol < cx - pol) | (kol > cx + pol)] = False
    shyr_ref = rozmah(smuga_m, 1)
    vys_ref = rozmah(smuga_m, 0)
    tsentralni = np.abs(tochky[:, 0] - 0.5) < 0.2
    tochky = tochky[tsentralni]

    def pidbir(t, a0, a1, inshi, i0, i1, prof):
        """t — координата вздовж осі, inshi — поперечна (вже в кадрі)."""
        best = (1e9, 1.0, 0.0)
        c = (a0 + a1) / 2
        for sk in np.arange(0.95, 1.0501, 0.0025):
            for zs in np.arange(-0.02, 0.0201, 0.001):
                k = c + ((a0 + t * (a1 - a0)) - c) * sk + zs
                idx = np.clip((k * N).astype(int), 0, N - 1)
                mn = np.full(N, np.inf)
                mx = np.full(N, -np.inf)
                np.minimum.at(mn, idx, inshi)
                np.maximum.at(mx, idx, inshi)
                ye = np.isfinite(mn)
                prof_s = np.where(ye, mx - mn, 0.0)
                vazh = prof > 0
                err = np.abs(prof_s - prof)[vazh].mean()
                if err < best[0]:
                    best = (err, sk, zs)
        return best
    inshi_u = v0 + tochky[:, 1] * (v1 - v0)     # поперечна для стовпців — v
    inshi_v = u0 + tochky[:, 0] * (u1 - u0)     # для рядків — u
    bv = pidbir(tochky[:, 1], v0, v1, inshi_v, u0, u1, shyr_ref)
    bu = pidbir(tochky[:, 0], u0, u1, inshi_u, v0, v1, vys_ref)
    # Профільний підбір лише друкується: ітерація 9 з ним гірша за 8 без
    # нього; точну прив'язку дає оптичний потік нижче.
    # Потік DIS між розмитою текстурою Pixal3D і чітким кадром хаотичний
    # (середній 8 px навіть після згладження) — вимкнено.
    potik = None
    if PRYVIAZKA == "підбір":
        cu, cv = (u0 + u1) / 2, (v0 + v1) / 2
        u0, u1 = cu + (u0 - cu) * bu[1] + bu[2], cu + (u1 - cu) * bu[1] + bu[2]
        v0, v1 = cv + (v0 - cv) * bv[1] + bv[2], cv + (v1 - cv) * bv[1] + bv[2]
    print("[аватар] прив'язка: u ×%.4f %+.4f (похибка %.4f), v ×%.4f %+.4f (%.4f)"
          % (bu[1], bu[2], bu[0], bv[1], bv[2], bv[0]))
    uv = me.uv_layers.new(name="Проєкція")
    vyd = me.color_attributes.new("Видимість", "FLOAT_COLOR", "CORNER")
    # Масово (11.10.2026): цикл по кутах через RNA на 300 тис. граней не
    # закінчився й за 35 хв; ті самі формули масивами — секунди.
    nl, nv = len(me.loops), len(me.vertices)
    vi = np.empty(nl, dtype=np.int64)
    me.loops.foreach_get("vertex_index", vi)
    co = np.empty(nv * 3, dtype=np.float64)
    me.vertices.foreach_get("co", co)
    co = co.reshape(nv, 3)[vi]
    nr = np.empty(nv * 3, dtype=np.float64)
    me.vertices.foreach_get("normal", nr)
    nr = nr.reshape(nv, 3)[vi]
    tz = (co[:, 2] - lo.z) / (hi.z - lo.z)
    tx = (co[:, 0] - lo.x) / (hi.x - lo.x)
    if pered > 0:
        tx = 1.0 - tx
    uu = u0 + tx * (u1 - u0)
    vv = v0 + tz * (v1 - v0)
    if potik is not None:
        # Пікселі: x — зліва, y — ЗВЕРХУ (як у кадрі й потоці).
        px_ = np.clip((uu * w).astype(int), 0, w - 1)
        py_ = np.clip(((1.0 - vv) * h).astype(int), 0, h - 1)
        fl = potik[py_, px_]
        uu = uu + fl[:, 0] / w
        vv = vv - fl[:, 1] / h
    uv.data.foreach_set("uv", np.stack([uu, vv], 1).astype(np.float32)
                        .ravel())
    # Усе, що хоч трохи повернуте до камери, на кадрі видно саме так —
    # повна вага вже з 0,15 (суміш із розмитим Pixal3D на опуклостях
    # давала двоїння, ітерація 2–3).
    # Плавно 0,2…0,45 (13.10.2026): з повною вагою вже з 0,15 скроні й бік
    # голови брали кадр під гострим кутом — розмазаний і блідий; з локальним
    # тоном (zapekty) суміш двох джерел уже однакова за тоном.
    ww = np.clip((nr[:, 1] * pered - 0.2) / 0.25, 0.0, 1.0)
    vydno = vuzka[np.clip((vv * h).astype(int), 0, h - 1),
                  np.clip((uu * w).astype(int), 0, w - 1)]
    ww = np.where(vydno, ww, 0.0)
    kol = np.ones((nl, 4), dtype=np.float32)
    kol[:, :3] = ww[:, None]
    vyd.data.foreach_set("color", kol.ravel())
    me.uv_layers.active = me.uv_layers["UVMap"] if "UVMap" in me.uv_layers \
        else me.uv_layers[0]
    print("[аватар] проєкція: кадр u %.3f–%.3f, v %.3f–%.3f" % (u0, u1, v0, v1))


def optychnyi_potik(skan, pered, lo, hi, u0, u1, v0, v1, w, h):
    """Рендер сирого скану з текстурою Pixal3D у ТІЙ САМІЙ прив'язці, що й
    проєкція, і потік від нього до кадру (`tools/potik.py`)."""
    import subprocess
    import numpy as np
    sc = bpy.context.scene
    stari = {o: o.hide_render for o in bpy.data.objects}
    for o in bpy.data.objects:
        o.hide_render = o is not skan
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "FLAT"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.film_transparent = True
    sc.view_settings.view_transform = "Standard"
    sc.render.resolution_x, sc.render.resolution_y = w, h
    kam = bpy.data.objects.new("камера-потоку", bpy.data.cameras.new("кп"))
    sc.collection.objects.link(kam)
    sc.camera = kam
    kam.data.type = "ORTHO"
    shyr_m = (hi.x - lo.x) / (u1 - u0)          # метрів на всю ширину кадру
    kam.data.ortho_scale = shyr_m
    # Центр кадру (u = v = 0,5) у світі.
    tx_c = (0.5 - u0) / (u1 - u0)
    if pered > 0:
        tx_c = 1.0 - tx_c
    x_c = lo.x + tx_c * (hi.x - lo.x)
    z_c = lo.z + (0.5 - v0) / (v1 - v0) * (hi.z - lo.z)
    kam.location = (x_c, pered * 10.0, z_c)
    kam.rotation_euler = (Vector((x_c, 0, z_c)) - Vector(kam.location)) \
        .to_track_quat("-Z", "Y").to_euler()
    kam.data.clip_end = 30
    tut = os.path.join(os.path.dirname(os.path.abspath(REF_MASKA)))
    kadr = os.path.join(tut, "potik-render.png")
    sc.render.filepath = kadr
    bpy.ops.render.render(write_still=True)
    for o, b_ in stari.items():
        o.hide_render = b_
    bpy.data.objects.remove(kam)
    npy = os.path.join(tut, "potik.npy")
    venv = os.path.expanduser("~/Програми/cv-venv/bin/python")
    r = subprocess.run([venv, os.path.join(ROOT, "tools", "potik.py"),
                        os.path.abspath(REF), os.path.abspath(REF_MASKA),
                        kadr, npy], capture_output=True, text=True)
    print(r.stdout.strip() or r.stderr[-500:])
    if r.returncode != 0:
        print("[аватар] ‼ потік не пораховано — лінійна прив'язка")
        return None
    return np.load(npy)


def zapekty(skan):
    """Запікання: спереду — референс, ззаду — Pixal3D під тон референсу."""
    import numpy as np
    me = skan.data
    # Запобіжник: грань, чия площа в атласі в 50+ разів більша за медіанне
    # співвідношення «атлас/сітка», — стягнути в точку (інакше запікання
    # малює її поверх чужих острівців).
    uvd = me.uv_layers["UVMap"].data
    zlamani = 0
    pl = np.array([p.area for p in me.polygons])
    uvp = np.zeros(len(me.polygons))
    for p in me.polygons:
        u = [uvd[li].uv for li in p.loop_indices]
        a_ = 0.0
        for k in range(1, len(u) - 1):
            a_ += abs((u[k] - u[0]).cross(u[k + 1] - u[0])) / 2
        uvp[p.index] = a_
    rel = uvp / np.maximum(pl, 1e-12)
    med = np.median(rel[pl > 0])
    for p in me.polygons:
        if uvp[p.index] > 1e-4 and rel[p.index] > med * 50:
            u0 = uvd[p.loop_indices[0]].uv.copy()
            for li in p.loop_indices:
                uvd[li].uv = u0
            zlamani += 1
    print("[аватар] розгортка: стягнуто велетенських граней %d" % zlamani)
    mat = me.materials[0]
    nt = mat.node_tree
    nodes, links = nt.nodes, nt.links
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    tex_p = next(l.from_node for l in bsdf.inputs["Base Color"].links)
    ref = bpy.data.images.load(os.path.abspath(REF))
    # Тон Pixal3D → тон референсу: медіани на добре видимих спереду кутах.
    def pikseli(obraz):
        w, h = obraz.size
        px = np.empty(w * h * 4, dtype=np.float32)
        obraz.pixels.foreach_get(px)
        return px.reshape(h, w, 4)
    pp, pr = pikseli(tex_p.image), pikseli(ref)
    uv_p, uv_r = me.uv_layers["UVMap"].data, me.uv_layers["Проєкція"].data
    vyd = me.color_attributes["Видимість"].data
    a_, b_ = [], []
    for li in range(0, len(me.loops), 7):
        if vyd[li].color[0] < 0.9:
            continue
        u, v = uv_p[li].uv
        a_.append(pp[min(pp.shape[0] - 1, int(v * pp.shape[0])),
                     min(pp.shape[1] - 1, int(u * pp.shape[1])), :3])
        u, v = uv_r[li].uv
        b_.append(pr[min(pr.shape[0] - 1, int(v * pr.shape[0])),
                     min(pr.shape[1] - 1, int(u * pr.shape[1])), :3])
    gain = np.median(np.array(b_), 0) / np.maximum(np.median(np.array(a_), 0),
                                                    1e-3)
    gain = np.clip(gain, 0.3, 3.0)
    print("[аватар] тон Pixal3D → референс: ×%s" % np.round(gain, 3))
    # Тон локально (13.10.2026): кадр освітлений спереду й блідіший за
    # Pixal3D на скронях і щоках, і один множник на все тіло лишав на межі
    # проєкції світлі латки (e1903). Відношення кадр/Pixal3D — по вершинах,
    # де видно спереду, і дифузією по ребрах — на боки й спину.
    nl_ = len(me.loops)
    vi_ = np.empty(nl_, dtype=np.int64)
    me.loops.foreach_get("vertex_index", vi_)
    up_ = np.empty(nl_ * 2, dtype=np.float32)
    uv_p.foreach_get("uv", up_)
    up_ = up_.reshape(-1, 2)
    ur_ = np.empty(nl_ * 2, dtype=np.float32)
    uv_r.foreach_get("uv", ur_)
    ur_ = ur_.reshape(-1, 2)
    vk_ = np.empty(nl_ * 4, dtype=np.float32)
    vyd.foreach_get("color", vk_)
    vk_ = vk_.reshape(-1, 4)[:, 0]
    tut_ = vk_ >= 0.9
    def proba(px_, uv_):
        h_, w_ = px_.shape[:2]
        return px_[np.clip((uv_[:, 1] * h_).astype(int), 0, h_ - 1),
                   np.clip((uv_[:, 0] * w_).astype(int), 0, w_ - 1), :3]
    nv_ = len(me.vertices)
    Sr = np.zeros((nv_, 3))
    Sp = np.zeros((nv_, 3))
    np.add.at(Sr, vi_[tut_], proba(pr, ur_[tut_]))
    np.add.at(Sp, vi_[tut_], proba(pp, up_[tut_]))
    ed_ = np.empty(len(me.edges) * 2, dtype=np.int64)
    me.edges.foreach_get("vertices", ed_)
    ed_ = ed_.reshape(-1, 2)
    st_ = np.bincount(ed_.ravel(), minlength=nv_).astype(float)
    def serednie(x):
        s_ = np.zeros_like(x)
        np.add.at(s_, ed_[:, 0], x[ed_[:, 1]])
        np.add.at(s_, ed_[:, 1], x[ed_[:, 0]])
        return 0.5 * x + 0.5 * s_ / np.maximum(st_, 1)[:, None]
    for _ in range(TON_KROKY):
        Sr, Sp = serednie(Sr), serednie(Sp)
    ton = np.where(Sp.sum(1, keepdims=True) > 1e-4, Sr / np.maximum(Sp, 1e-4), gain[None, :])
    ton = np.clip(ton, 0.3, 3.0)
    at_t = me.color_attributes.new("Тон", "FLOAT_COLOR", "POINT")
    kt = np.ones((nv_, 4), np.float32)
    kt[:, :3] = ton
    at_t.data.foreach_set("color", kt.ravel())
    print("[аватар] тон локально: вершин спереду %d, множник %s…%s"
          % (int((np.bincount(vi_[tut_], minlength=nv_) > 0).sum()),
             np.round(np.percentile(ton, 5, 0), 2), np.round(np.percentile(ton, 95, 0), 2)))
    uvp = nodes.new("ShaderNodeUVMap")
    uvp.uv_map = "UVMap"
    links.new(uvp.outputs["UV"], tex_p.inputs["Vector"])
    mnozh = nodes.new("ShaderNodeMix")
    mnozh.data_type, mnozh.blend_type = "RGBA", "MULTIPLY"
    mnozh.inputs["Factor"].default_value = 1.0
    links.new(tex_p.outputs["Color"], mnozh.inputs[6])
    mnozh.inputs[7].default_value = (*[float(x) for x in gain], 1.0)
    at_n = nodes.new("ShaderNodeVertexColor")
    at_n.layer_name = "Тон"
    links.new(at_n.outputs["Color"], mnozh.inputs[7])
    uvr = nodes.new("ShaderNodeUVMap")
    uvr.uv_map = "Проєкція"
    tex_r = nodes.new("ShaderNodeTexImage")
    tex_r.image = ref
    tex_r.extension = "EXTEND"
    links.new(uvr.outputs["UV"], tex_r.inputs["Vector"])
    attr = nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Видимість"
    mix = nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    links.new(attr.outputs["Color"], mix.inputs["Factor"])
    links.new(mnozh.outputs[2], mix.inputs[6])
    links.new(tex_r.outputs["Color"], mix.inputs[7])
    links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    # Метал — геть ДО запікання: прохід «колір дифузії» Cycles = колір ×
    # (1 − метал), і металевість Pixal3D темнила все на ~25% (ітерація 4:
    # торс 0,76 від референсу; Workbench сам передає колір точно).
    for k_ in ("Metallic", "Roughness"):
        for l in list(bsdf.inputs[k_].links):
            links.remove(l)
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = 0.6
    cil = bpy.data.images.new("аватар-колір", TEKSTURA, TEKSTURA)
    tex_c = nodes.new("ShaderNodeTexImage")
    tex_c.image = cil
    nodes.active = tex_c
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    # На відеокарті: на процесорі запікання 2048² з ~150 тис. граней ішло
    # пів години.
    try:
        pr = bpy.context.preferences.addons["cycles"].preferences
        for typ in ("OPTIX", "CUDA"):
            try:
                pr.compute_device_type = typ
                pr.get_devices()
                if any(d.type == typ for d in pr.devices):
                    for d in pr.devices:
                        d.use = d.type == typ
                    sc.cycles.device = "GPU"
                    print("[аватар] запікання на %s" % typ)
                    break
            except TypeError:
                continue
    except Exception as e:
        print("[аватар] ‼ GPU для запікання недоступна: %s" % e)
    sc.cycles.samples = 1
    sc.render.bake.margin = 8
    if os.environ.get("AVATAR_DEBUG_BLEND"):      # налагодження: сцена перед запіканням
        bpy.ops.wm.save_as_mainfile(filepath=os.environ["AVATAR_DEBUG_BLEND"], copy=True)
    for o in bpy.context.selected_objects:
        o.select_set(False)
    skan.select_set(True)
    bpy.context.view_layer.objects.active = skan
    me.uv_layers["UVMap"].active = True
    me.uv_layers["UVMap"].active_render = True
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"})
    cil.pack()
    zapekty_masky(me, nodes, links, tex_r, mix, mnozh, tex_c)
    tex_c.image = cil
    # Матеріал: запечений колір, нормаль Pixal3D, без металу (метал
    # темнив і червонив шкіру в Godot).
    for n in (mix, mnozh, tex_r, uvr, attr):
        nodes.remove(n)
    links.new(tex_c.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(uvp.outputs["UV"], tex_c.inputs["Vector"])
    for k_ in ("Metallic", "Roughness"):
        for l in list(bsdf.inputs[k_].links):
            links.remove(l)
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = 0.6
    me.uv_layers.remove(me.uv_layers["Проєкція"])
    print("[аватар] запечено: %s" % (cil.size[:],))


def zapekty_masky(me, nodes, links, tex_r, mix, mnozh, tex_c):
    """Маски рис обличчя (`tools/maski_oblychchia.py`) — тією ж проєкцією в
    ту ж розгортку, що й колір: R райдужка, G підводка, B губи, A волосся
    на голові (спереду — з кадру, ззаду — атрибут «Скальп»). Пише
    `аватар-маски.png` поруч із виходом — у грі колір очей, губ, шкіри й
    скальпу (`game/shaders/avatar_skin.gdshader`)."""
    import subprocess
    import numpy as np
    pm, pv = REF[:-4] + "-maski.png", REF[:-4] + "-maska-volossia.png"
    tochky = REF[:-4] + "-tochky.npy"
    if not (os.path.exists(pm) and os.path.exists(pv)):
        if not os.path.exists(tochky):
            print("[аватар] ‼ маски: немає точок обличчя — без масок")
            return
        r = subprocess.run([os.path.expanduser("~/Програми/cv-venv/bin/python"),
                            os.path.join(ROOT, "tools", "maski_oblychchia.py"),
                            os.path.abspath(REF), os.path.abspath(REF_MASKA),
                            tochky, pm, pv], capture_output=True, text=True)
        print(r.stdout.strip() or r.stderr[-300:])
    for l in list(mix.inputs[6].links):
        links.remove(l)
    rez = []
    for shliakh, zzadu in ((pm, None), (pv, "Скальп")):
        im = bpy.data.images.load(os.path.abspath(shliakh))
        im.colorspace_settings.name = "Non-Color"
        tex_r.image = im
        for l in list(mix.inputs[6].links):
            links.remove(l)
        if zzadu and zzadu in me.color_attributes:
            at = nodes.new("ShaderNodeVertexColor")
            at.layer_name = zzadu
            links.new(at.outputs["Color"], mix.inputs[6])
        else:
            mix.inputs[6].default_value = (0, 0, 0, 1)
        tsil = bpy.data.images.new("маска", TEKSTURA, TEKSTURA)
        tsil.colorspace_settings.name = "Non-Color"
        tex_c.image = tsil
        nodes.active = tex_c
        bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"})
        px = np.empty(TEKSTURA * TEKSTURA * 4, dtype=np.float32)
        tsil.pixels.foreach_get(px)
        rez.append(px.reshape(TEKSTURA, TEKSTURA, 4))
    out = np.concatenate([rez[0][..., :3], rez[1][..., :1]], -1)
    kin = bpy.data.images.new("аватар-маски", TEKSTURA, TEKSTURA, alpha=True)
    kin.colorspace_settings.name = "Non-Color"
    kin.pixels.foreach_set(out.clip(0, 1).ravel())
    kin.filepath_raw = os.path.join(os.path.dirname(os.path.abspath(KUDY)),
                                    "аватар-маски.png")
    kin.file_format = "PNG"
    os.makedirs(os.path.dirname(kin.filepath_raw), exist_ok=True)
    kin.save()
    print("[аватар] маски →", kin.filepath_raw)


def zrobyty_peruku(shliakh, skan, kist):
    """Волосся зі скану голови → окрема сітка «Перука» на кістці Head."""
    import bmesh
    import numpy as np
    stari = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=shliakh)
    novi = [o for o in bpy.data.objects if o not in stari]
    h = next(o for o in novi if o.type == "MESH")
    for o in novi:
        if o is not h:
            bpy.data.objects.remove(o)
    h.parent = None
    zastosuvaty(h)
    h.name = "Перука"
    # Той самий поворот, що й скану тіла: обидва з Pixal3D, одна
    # орієнтація.
    if POVERNUTO:
        h.rotation_euler = (0, 0, math.pi)
        zastosuvaty(h)
    # Голова тіла — усе вище шиї; скан голови — від шиї до маківки.
    n_z = kist["neck_01"].z
    tilo_h = [v.co for v in skan.data.vertices
              if v.co.z > n_z and abs(v.co.x) < 0.2]
    lo_t, hi_t = mezhi(tilo_h)
    p = [v.co.copy() for v in h.data.vertices]
    lo_h, hi_h = mezhi(p)
    # Масштаб — за шириною голови (вуха скану голови можуть виходити за
    # межі, тож за висотою від шиї до маківки, яка стійкіша).
    k = (hi_t.z - lo_t.z) / (hi_h.z - lo_h.z)
    tsil = Vector(((lo_t.x + hi_t.x) / 2, (lo_t.y + hi_t.y) / 2, lo_t.z))
    dzh = Vector(((lo_h.x + hi_h.x) / 2, (lo_h.y + hi_h.y) / 2, lo_h.z))
    for v in h.data.vertices:
        v.co = tsil + (v.co - dzh) * k
    # Лише волосся: темний колір текстури й висота — спереду вище брів,
    # ззаду (за серединою голови) вище потилиці.
    obraz = None
    for m in h.data.materials:
        for n in (m.node_tree.nodes if m else []):
            if n.type == "TEX_IMAGE" and any(
                    l.to_socket.name == "Base Color" for l in n.outputs[0].links):
                obraz = n.image
    w, hh = obraz.size
    px = np.empty(w * hh * 4, dtype=np.float32)
    obraz.pixels.foreach_get(px)
    px = px.reshape(hh, w, 4)
    uv = h.data.uv_layers.active.data
    lo_t2, hi_t2 = mezhi([v.co for v in h.data.vertices])
    vys = hi_t2.z - lo_t2.z
    sered_y = (lo_t2.y + hi_t2.y) / 2
    zad = 1 if PERED < 0 else -1      # бік потилиці по Y
    bm = bmesh.new()
    bm.from_mesh(h.data)
    uv_l = bm.loops.layers.uv.active
    zaivi = []
    for f in bm.faces:
        c = f.calc_center_median()
        u = sum(l[uv_l].uv[0] for l in f.loops) / len(f.loops)
        vv = sum(l[uv_l].uv[1] for l in f.loops) / len(f.loops)
        r, g, b = px[min(hh - 1, int(vv * hh)), min(w - 1, int(u * w)), :3]
        temne = 0.299 * r + 0.587 * g + 0.114 * b < 0.33
        t = (c.z - lo_t2.z) / vys
        pozadu = (c.y - sered_y) * zad > 0
        if not (temne and (t > 0.72 or (pozadu and t > 0.45))):
            zaivi.append(f)
    bmesh.ops.delete(bm, geom=zaivi, context="FACES")
    # Дрібні клапті (брови, тіні) — геть: лишаються шматки від 200 граней.
    bm.faces.ensure_lookup_table()
    bachyly, shmatky = set(), []
    for f in bm.faces:
        if f.index in bachyly:
            continue
        stos, shm = [f], []
        bachyly.add(f.index)
        while stos:
            x = stos.pop()
            shm.append(x)
            for e in x.edges:
                for y in e.link_faces:
                    if y.index not in bachyly:
                        bachyly.add(y.index)
                        stos.append(y)
        shmatky.append(shm)
    dribni = [f for shm in shmatky if len(shm) < 200 for f in shm]
    bmesh.ops.delete(bm, geom=dribni, context="FACES")
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * 0.003
    bm.to_mesh(h.data)
    bm.free()
    for m in h.data.materials:
        if m:
            m.use_backface_culling = False
    g = h.vertex_groups.new(name="Head")
    g.add(list(range(len(h.data.vertices))), 1.0, "REPLACE")
    print("[аватар] перука: граней %d, ×%.3f" % (len(h.data.polygons), k))
    return h


def serednii_kolir(obraz, ob):
    """Медіанний колір текстури під вершинами об'єкта (лінійний RGB)."""
    import numpy as np
    w, h = obraz.size
    px = np.empty(w * h * 4, dtype=np.float32)
    obraz.pixels.foreach_get(px)
    px = px.reshape(h, w, 4)
    uv = ob.data.uv_layers.active.data
    proby = [px[min(h - 1, int(uv[i].uv[1] * h)),
                min(w - 1, int(uv[i].uv[0] * w)), :3]
             for i in range(0, len(uv), 3)]
    c = np.median(np.array(proby), axis=0)
    return tuple(float(((x + 0.055) / 1.055) ** 2.4) for x in c)


def kolir_shkiry(skan, zapiastok):
    """Середній колір текстури скану на передпліччі (лінійний RGB)."""
    import numpy as np
    # Лише картинка, підключена до Base Color: у матеріалі Pixal3D ще є
    # металевість-шорсткість і нормаль, і перша спроба взяла саме їх —
    # кисті вийшли білими.
    obraz = None
    for m in skan.data.materials:
        for n in (m.node_tree.nodes if m and m.use_nodes else []):
            if n.type == "TEX_IMAGE" and n.image and any(
                    l.to_socket.name == "Base Color" for l in n.outputs[0].links):
                obraz = n.image
    if obraz is None:
        return (0.55, 0.38, 0.3)
    w, h = obraz.size
    px = np.empty(w * h * 4, dtype=np.float32)
    obraz.pixels.foreach_get(px)
    px = px.reshape(h, w, 4)
    uv = skan.data.uv_layers.active.data
    proby = []
    for poly in skan.data.polygons:
        for li in poly.loop_indices:
            v = skan.data.vertices[skan.data.loops[li].vertex_index]
            if zapiastok - 0.12 < abs(v.co.x) < zapiastok - 0.03:
                u, vv = uv[li].uv
                proby.append(px[min(h - 1, int(vv * h)), min(w - 1, int(u * w)), :3])
    if not proby:
        return (0.55, 0.38, 0.3)
    c = np.median(np.array(proby), axis=0)
    # Текстура в sRGB, колір матеріалу — лінійний.
    return tuple(float(((x + 0.055) / 1.055) ** 2.4) for x in c)


def fcurves_of(action):
    """Криві дії і в старому API, і в шаруватому Blender 5."""
    if hasattr(action, "fcurves") and action.fcurves is not None:
        try:
            return list(action.fcurves)
        except Exception:
            pass
    out = []
    for layer in getattr(action, "layers", []):
        for strip in layer.strips:
            for bag in strip.channelbags:
                out.extend(bag.fcurves)
    return out


def remove_fcurve(action, fc):
    for layer in getattr(action, "layers", []):
        for strip in layer.strips:
            for bag in strip.channelbags:
                if fc in list(bag.fcurves):
                    bag.fcurves.remove(fc)
                    return
    try:
        action.fcurves.remove(fc)
    except Exception:
        pass


def kadry(arm, skan):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [
        e.identifier for e in bpy.types.RenderSettings.bl_rna
        .properties["engine"].enum_items] else "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = 640, 800
    svit_ = bpy.data.worlds.new("тло")
    svit_.use_nodes = True
    svit_.node_tree.nodes["Background"].inputs["Color"].default_value = \
        (0.6, 0.6, 0.62, 1)
    sc.world = svit_
    for kut in (40, -50):
        l = bpy.data.objects.new("світло", bpy.data.lights.new("с", "SUN"))
        l.data.energy = 3.0
        l.rotation_euler = (math.radians(50), 0, math.radians(kut))
        sc.collection.objects.link(l)
    kam = bpy.data.objects.new("камера", bpy.data.cameras.new("к"))
    sc.collection.objects.link(kam)
    sc.camera = kam
    kam.data.lens = 50
    os.makedirs(KADRY, exist_ok=True)

    def znimok(imia, kut):
        r = 4.6
        kam.location = (math.sin(kut) * r, PERED * math.cos(kut) * r, 1.0)
        napr = Vector((0, 0, 0.9)) - Vector(kam.location)
        kam.rotation_euler = napr.to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(KADRY, imia + ".png")
        bpy.ops.render.render(write_still=True)

    # Камера — з боку обличчя (PERED, визначено з тіла манекена).
    znimok("спокій-перед", 0.0)
    znimok("спокій-бік", math.radians(90))
    # Рухи з UAL1: та сама арматура за назвами кісток.
    stari = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=RUKHY)
    for o in set(bpy.data.objects) - stari:
        o.hide_render = True
    # Як у грі (`skinned_model.gd:_rotations_only`): положення лише root і
    # pelvis, інакше кістки скелета-під-скан стрибали б на манекенові місця.
    for a_ in bpy.data.actions:
        for fc in list(fcurves_of(a_)):
            if fc.data_path.endswith(".location") and not any(
                    '"%s"' % k in fc.data_path for k in ("root", "pelvis")):
                remove_fcurve(a_, fc)
    arm.animation_data_create()
    for imia, kadr in PEREVIRKA:
        dii = [a for a in bpy.data.actions if a.name.startswith(imia)]
        if not dii:
            print("[аватар] ‼ руху %s немає" % imia)
            continue
        arm.animation_data.action = dii[0]
        # Blender 5: дія грає лише через свій слот.
        if hasattr(arm.animation_data, "action_slot") and dii[0].slots:
            arm.animation_data.action_slot = dii[0].slots[0]
        sc.frame_set(kadr)
        znimok("рух-" + imia, math.radians(30))
    print("[аватар] кадри →", KADRY)


main()
