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

import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MANEKEN = os.path.join(ROOT, "game/models/player/Superhero_Male_FullBody.gltf")
RUKHY = os.path.join(ROOT, "game/models/player/animations/UAL1_Standard.glb")
PERED = -1
ARGS = sys.argv[sys.argv.index("--") + 1:]
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

    # 2. Руки: плече манекена → кінчик пальців.
    plече = abs(kist["upperarm_l"].x)
    kinets_m = t_hi.x
    p = svit(skan)
    lo, hi = mezhi(p)
    kinets_s = max(hi.x, -lo.x)
    ruka_z_m = (kist["upperarm_l"].z + kist["hand_l"].z) / 2
    # Висота руки скану — середня Z вершин далеко від тулуба.
    dal = [q.z for q in p if abs(q.x) > plече + (kinets_s - plече) * 0.5]
    ruka_z_s = sorted(dal)[len(dal) // 2] if dal else ruka_z_m
    kx = (kinets_m - plече) / max(0.01, kinets_s - plече)
    for v in skan.data.vertices:
        ax = abs(v.co.x)
        if ax <= plече:
            continue
        znak = 1 if v.co.x > 0 else -1
        # Вага переходу: 0 біля плеча, 1 за 12 см від нього — тулуб на місці.
        w = min(1.0, (ax - plече) / 0.12)
        v.co.x = znak * (plече + (ax - plече) * (1 + (kx - 1) * w))
        v.co.z += (ruka_z_m - ruka_z_s) * w
    print("[аватар] руки: кінчики %.3f → %.3f м (×%.3f), висота руки "
          "%.3f → %.3f м" % (kinets_s, kinets_m, kx, ruka_z_s, ruka_z_m))

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

    # 2б. Ноги (01.10.2026: «не правильний вигін ніг»): ноги скану стояли
    # на 4–5 см попереду ніг манекена, ступні — ширше, і коліно брало ваги
    # не тих граней. На висоті стегна, коліна й ступні центр смуги скану
    # стає центром тієї ж смуги ТІЛА манекена (не кістки: пальці в обох
    # однаково попереду кісточки); між рівнями — плавно, вище таза — нуль.
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
    for znak in (1, -1):
        skan_p = [v.co.copy() for v in skan.data.vertices]
        zsuvy = []
        for z in rivni:
            a_, b_ = tsentr(tilo_p, z, znak), tsentr(skan_p, z, znak)
            zsuvy.append((z, (a_[0] - b_[0], a_[1] - b_[1]) if a_ and b_
                          else (0.0, 0.0)))
        print("[аватар] нога %s: зсув x/y на ступні %+.3f/%+.3f, коліні "
              "%+.3f/%+.3f, стегні %+.3f/%+.3f" % (
                  "ліва" if znak > 0 else "права",
                  *zsuvy[0][1], *zsuvy[1][1], *zsuvy[2][1]))

        def zsuv(z):
            if z <= zsuvy[0][0]:
                return zsuvy[0][1]
            for (z0, d0), (z1, d1) in zip(zsuvy, zsuvy[1:]):
                if z <= z1:
                    t = (z - z0) / (z1 - z0)
                    return (d0[0] + (d1[0] - d0[0]) * t,
                            d0[1] + (d1[1] - d0[1]) * t)
            z0, d0 = zsuvy[-1]
            t = max(0.0, 1.0 - (z - z0) / (VERKH - z0))
            return (d0[0] * t, d0[1] * t)
        for v in skan.data.vertices:
            if v.co.x * znak <= 0 or v.co.z > VERKH or abs(v.co.x) > 0.4:
                continue
            # Біля середньої лінії тіла (пах, пов'язка) зсув X слабшає —
            # дві ноги не тягнуть одну точку в різні боки.
            vaga_x = min(1.0, abs(v.co.x) / 0.06)
            dx, dy = zsuv(v.co.z)
            v.co.x += dx * vaga_x
            v.co.y += dy

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

    # 3а. Кисті й ступні — манекенові. Pixal3D ліпить розкриту долоню в
    # «рукавицю», а ступню — грудкою без пальців, і на кістках пальців вони
    # вивертаються (01.10.2026: «бачу руки неправильної форми», «чужі руки з
    # розривом, та незакінчені пальці ніг»). Кінець руки й ноги скану
    # відрізається й плавно звужується до кільця манекена, а кисть і ступня
    # манекена заходять у нього на ЗАХІД — шва-щілини немає. Колір — власна
    # текстура шкіри манекена (нігті, складки), помножена під тон скану.
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
        for i in mix.inputs:
            for l in list(i.links):
                if l.from_node.type == "VERTEX_COLOR":
                    links.remove(l)
                    i.default_value = (*mnozh, 1.0)
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
            if n.type == "TEX_IMAGE" and n.image and n.image.size[0] > 2048:
                n.image.scale(2048, 2048)
    os.makedirs(os.path.dirname(KUDY), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=KUDY, export_format="GLTF_SEPARATE",
                              export_animations=False, export_skins=True,
                              export_yup=True)
    print("[аватар] →", KUDY)
    if KADRY:
        kadry(arm, skan)


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
