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
SKAN, KUDY = ARGS[0], ARGS[1]
KADRY = ARGS[2] if len(ARGS) > 2 else None
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
    for v in skan.data.vertices:
        if abs(v.co.x) > 0.16 or v.co.z < n_z:
            continue
        t = min(1.0, (v.co.z - n_z) / max(0.01, (h_z - 0.02) - n_z))
        for g in list(v.groups):
            skan.vertex_groups[g.group].remove([v.index])
        g_head.add([v.index], t, "REPLACE")
        if t < 1.0:
            g_neck.add([v.index], 1.0 - t, "REPLACE")
    porozhni = sum(1 for v in skan.data.vertices if not v.groups)
    print("[аватар] вершин %d, без ваги %d" % (len(skan.data.vertices),
                                               porozhni))

    # 3а. Кисті — манекенові. Pixal3D ліпить розкриту долоню в «рукавицю»
    # (пальці злиплись, великий — обрубок), і на кістках пальців вона
    # вивертається (01.10.2026: «бачу руки неправильної форми»). Тож кисть
    # скану відрізається по зап'ясток, а на її місце стає кисть манекена з
    # рідними вагами, кольором шкіри скану.
    zapiastok = abs(kist["hand_l"].x) - 0.015
    import bmesh
    # Зап'ясток манекена й кінець передпліччя скану — кожен зі СВОЇМ
    # центром (вісь руки скану не збігається з віссю кісток: перша спроба
    # міряла від кістки й стягла передпліччя в конус).
    def kilce(verts, znak, shyr=0.012):
        # Манекен низькополігональний (7281 вершина): у вузькій смузі біля
        # зрізу його кільця може не бути зовсім — йому смуга ширша.
        smuga = [c for c in verts if c.x * znak > 0
                 and abs(abs(c.x) - zapiastok) < shyr]
        print("[аватар]   смуга зап'ястка %+d: вершин %d (з %d)"
              % (znak, len(smuga), len(verts)))
        if not smuga:
            return None, 0.0
        cy = sum(c.y for c in smuga) / len(smuga)
        cz = sum(c.z for c in smuga) / len(smuga)
        r = sorted(math.hypot(c.y - cy, c.z - cz) for c in smuga)
        return (cy, cz), r[len(r) // 2]
    bm = bmesh.new()
    bm.from_mesh(skan.data)
    zaivi = [v for v in bm.verts if abs(v.co.x) > zapiastok]
    bmesh.ops.delete(bm, geom=zaivi, context="VERTS")
    DOVZH = 0.08
    for znak in (1, -1):
        c_m, r_m = kilce([tilo.matrix_world @ v.co
                          for v in tilo.data.vertices], znak, 0.03)
        c_s, r_s = kilce([v.co for v in bm.verts], znak)
        if c_m is None or c_s is None or r_s < 1e-4:
            continue
        r_m *= 1.06
        for v in bm.verts:
            if v.co.x * znak <= 0:
                continue
            t = (abs(v.co.x) - (zapiastok - DOVZH)) / DOVZH
            if t <= 0:
                continue
            t = min(1.0, t)
            f = 1.0 + (r_m / r_s - 1.0) * t
            cy = c_s[0] + (c_m[0] - c_s[0]) * t
            cz = c_s[1] + (c_m[1] - c_s[1]) * t
            v.co.y = cy + (v.co.y - c_s[0]) * f
            v.co.z = cz + (v.co.z - c_s[1]) * f
        print("[аватар] зап'ясток %s: передпліччя r %.3f → %.3f м, центр "
              "зсунуто на %.3f м" % ("лівий" if znak > 0 else "правий",
                                     r_s, r_m, math.hypot(c_m[0] - c_s[0],
                                                          c_m[1] - c_s[1])))
    kraj = [e for e in bm.edges if e.is_boundary
            and all(abs(x.co.x) > zapiastok - 0.02 for x in e.verts)]
    bmesh.ops.holes_fill(bm, edges=kraj, sides=0)
    bm.to_mesh(skan.data)
    bm.free()
    kolir = kolir_shkiry(skan, zapiastok)
    kysti = tilo.copy()
    kysti.data = tilo.data.copy()
    kysti.name = "Кисті"
    bpy.context.scene.collection.objects.link(kysti)
    bm = bmesh.new()
    bm.from_mesh(kysti.data)
    zaivi = [v for v in bm.verts if abs(v.co.x) <= zapiastok]
    bmesh.ops.delete(bm, geom=zaivi, context="VERTS")
    bm.to_mesh(kysti.data)
    bm.free()
    mk = bpy.data.materials.new("шкіра кистей")
    mk.use_nodes = True
    bsdf = mk.node_tree.nodes["Principled BSDF"]
    # У текстуру скану запечене затінення — гладкий колір кисті без нього
    # світліший за руку; трохи темніше.
    bsdf.inputs["Base Color"].default_value = (*(c * 0.85 for c in kolir),
                                               1.0)
    bsdf.inputs["Roughness"].default_value = 0.6
    kysti.data.materials.clear()
    kysti.data.materials.append(mk)
    print("[аватар] кисті манекена: вершин %d, колір шкіри %s"
          % (len(kysti.data.vertices), tuple(round(c, 3) for c in kolir)))

    # 4. На скелет.
    bpy.data.objects.remove(tilo)
    for o in (skan, kysti):
        o.parent = arm
        if not any(m.type == "ARMATURE" for m in o.modifiers):
            am = o.modifiers.new("Armature", "ARMATURE")
            am.object = arm
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
