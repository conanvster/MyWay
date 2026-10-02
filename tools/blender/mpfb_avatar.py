"""Аватар на MPFB/MakeHuman (02.10.2026) — параметрична людина замість скану.

Слова замовника — у `spec/DECIDED.md` («Аватар — параметрична модель
MPFB…»). Цей скрипт — основа: статура повзунками, скелет `game_engine`,
очі, брови, вії окремими сітками, реалістична шкіра MakeHuman (CC0), експорт
у glTF без допоміжних сіток MPFB.

    blender -b -P tools/blender/mpfb_avatar.py -- <куди.gltf> [тека_кадрів]
        [--макро gender=1,age=0.45,muscle=0.85,...]
"""
import functools
import json
import math
import os
import sys

import bpy
from mathutils import Vector

from bl_ext.blender_org.mpfb.services.humanservice import HumanService
from bl_ext.blender_org.mpfb.services.exportservice import ExportService
from bl_ext.blender_org.mpfb.services.locationservice import LocationService

print = functools.partial(print, flush=True)
ARGS = sys.argv[sys.argv.index("--") + 1:]
MAKRO = {"gender": 1.0, "age": 0.45, "muscle": 0.85, "weight": 0.55,
         "proportions": 0.6, "height": 0.6, "cupsize": 0.5, "firmness": 0.5,
         "race": {"caucasian": 1.0, "african": 0.0, "asian": 0.0}}
if "--макро" in ARGS:
    i_ = ARGS.index("--макро")
    for pair in ARGS[i_ + 1].split(","):
        k, v = pair.split("=")
        MAKRO[k] = float(v)
    del ARGS[i_:i_ + 2]
RUKHY = None          # None — усі; інакше перелік назв
if "--рухи" in ARGS:
    i_ = ARGS.index("--рухи")
    RUKHY = ARGS[i_ + 1].split(",")
    del ARGS[i_:i_ + 2]
UAL1 = os.path.join(os.path.dirname(__file__), "..", "..", "game", "models",
                    "player", "animations", "UAL1_Standard.glb")
KUDY = ARGS[0]
KADRY = ARGS[1] if len(ARGS) > 1 else None
DANI = LocationService.get_user_data()


def asset(*chastyny):
    return os.path.join(DANI, *chastyny)


def main():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    h = HumanService.create_human(macro_detail_dict=MAKRO)
    HumanService.add_builtin_rig(h, "game_engine")
    for typ, shliakh in (("Eyes", asset("eyes", "high-poly", "high-poly.mhclo")),
                         ("Eyebrows", asset("eyebrows", "eyebrow001",
                                            "eyebrow001.mhclo")),
                         ("Eyelashes", asset("eyelashes", "eyelashes01",
                                             "eyelashes01.mhclo"))):
        HumanService.add_mhclo_asset(shliakh, h, asset_type=typ,
                                     material_type="GAMEENGINE")
    HumanService.set_character_skin(
        asset("skins", "middleage_caucasian_male",
              "middleage_caucasian_male.mhmat"), h, skin_type="GAMEENGINE")
    # Шкіра MPFB «GAMEENGINE» має ще й картинку прозорості на Alpha — у
    # експорті тіло ставало клаптями напівпрозорим. Шкірі прозорість не
    # потрібна (бровам і віям — так, їх не чіпаємо).
    for m in h.data.materials:
        b = next((n for n in m.node_tree.nodes
                  if n.type == "BSDF_PRINCIPLED"), None)
        if b is not None:
            for l in list(b.inputs["Alpha"].links):
                m.node_tree.links.remove(l)
            b.inputs["Alpha"].default_value = 1.0
        if hasattr(m, "surface_render_method"):
            m.surface_render_method = "DITHERED"
        m.blend_method = "OPAQUE" if hasattr(m, "blend_method") else None
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    sitky = [o for o in bpy.data.objects if o.type == "MESH"]
    print("[mpfb] сітки: %s" % ", ".join("%s(%d)" % (o.name, len(o.data.vertices))
                                         for o in sitky))
    print("[mpfb] кісток %d: %s" % (len(arm.data.bones),
                                    [b.name for b in arm.data.bones][:12]))
    # Форми (shape keys) — у сітку; допоміжні частини MPFB ховає модифікатор
    # «маска», і експортер застосує його сам (export_apply), лишивши скін.
    # (ExportService.bake_modifiers_remove_helpers потребує інтерфейсу.)
    for o in sitky:
        if o.data.shape_keys:
            bpy.context.view_layer.objects.active = o
            o.shape_key_add(name="змішано", from_mix=True)
            for k in list(o.data.shape_keys.key_blocks):
                if k.name != "змішано":
                    o.shape_key_remove(k)
            o.shape_key_remove(o.data.shape_keys.key_blocks["змішано"])
    print("[mpfb] модифікатори тіла: %s" % [m.type for m in h.modifiers])
    perenapravyty(arm)
    os.makedirs(os.path.dirname(os.path.abspath(KUDY)), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=KUDY, export_format="GLTF_SEPARATE",
                              export_animations=True,
                              export_animation_mode="NLA_TRACKS",
                              export_skins=True, export_apply=True)
    print("[mpfb] →", KUDY)
    if KADRY:
        kadry(h)


def perenapravyty(arm):
    """Рухи UAL1 (скелет манекена, T-поза) → скелет game_engine MPFB
    (А-поза), запечені ключами — по дії на рух.

    Для кожної кістки один раз — поправка C: поворот, що суміщає напрям
    кістки MPFB з напрямом тієї ж кістки манекена у спокої (своя закрутка
    лишається). Далі в кожному кадрі світовий поворот кістки MPFB =
    світовий поворот кістки манекена × C. Таз ще й зсувається (масштаб —
    за висотою таза)."""
    from mathutils import Matrix, Quaternion
    stari = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(UAL1))
    novi = [o for o in bpy.data.objects if o not in stari]
    src = next(o for o in novi if o.type == "ARMATURE")
    for o in novi:
        o.hide_render = True
        o.hide_set(True)
    dii = [a for a in bpy.data.actions if RUKHY is None
           or any(a.name.startswith(r) for r in RUKHY)]
    dii = [a for a in dii if a.name.split("|")[0].split(".")[0] in
           {x.name.split("|")[0].split(".")[0] for x in dii}]
    po_nazvi = {b.name.lower(): b.name for b in src.data.bones}
    pary = []
    for b in arm.data.bones:
        sb = po_nazvi.get(b.name.lower())
        if sb:
            pary.append((b.name, sb))
    print("[mpfb] кісток у парі: %d з %d" % (len(pary), len(arm.data.bones)))
    # Поправка C на спокої.
    C = {}
    for tb, sb in pary:
        r_t = (arm.matrix_world @ arm.data.bones[tb].matrix_local).to_quaternion()
        r_s = (src.matrix_world @ src.data.bones[sb].matrix_local).to_quaternion()
        d_t = r_t @ Vector((0, 1, 0))
        d_s = r_s @ Vector((0, 1, 0))
        r_al = d_t.rotation_difference(d_s) @ r_t
        C[tb] = r_s.inverted() @ r_al
    vys_t = (arm.matrix_world @ arm.data.bones["pelvis"].head_local).z
    vys_s = (src.matrix_world @ src.data.bones[po_nazvi["pelvis"]].head_local).z
    k_vys = vys_t / max(vys_s, 1e-3)
    tazy_t = arm.matrix_world @ arm.data.bones["pelvis"].head_local
    tazy_s = src.matrix_world @ src.data.bones[po_nazvi["pelvis"]].head_local
    poriadok = [b.name for b in arm.data.bones]   # батьки раніше дітей
    # Кістки MPFB обертаються кутами Ейлера — ключі кватерніона лишались
    # порожні, і рухи не грали (перша спроба).
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    sc = bpy.context.scene
    arm.animation_data_create()
    src.animation_data_create()
    zrobleno = 0
    for dia in dii:
        imia = dia.name.split("|")[-1]
        src.animation_data.action = dia
        if hasattr(src.animation_data, "action_slot") and dia.slots:
            src.animation_data.action_slot = dia.slots[0]
        f0, f1 = (int(x) for x in dia.frame_range)
        nova = bpy.data.actions.new(imia)
        arm.animation_data.action = nova
        for f in range(f0, f1 + 1):
            sc.frame_set(f)
            for tb in poriadok:
                pb = arm.pose.bones[tb]
                sb = dict(pary).get(tb)
                if sb is None:
                    continue
                m_s = src.matrix_world @ src.pose.bones[sb].matrix
                r = m_s.to_quaternion() @ C[tb]
                poz = pb.matrix.translation.copy()
                if tb == "pelvis":
                    poz = tazy_t + (m_s.translation - tazy_s) * k_vys
                pb.matrix = Matrix.LocRotScale(poz, r, Vector((1, 1, 1)))
                bpy.context.view_layer.update()
                pb.keyframe_insert("rotation_quaternion", frame=f)
                if tb == "pelvis":
                    pb.keyframe_insert("location", frame=f)
        nova.use_fake_user = True
        track = arm.animation_data.nla_tracks.new()
        track.name = imia
        track.strips.new(imia, f0, nova)
        arm.animation_data.action = None
        zrobleno += 1
        print("[mpfb] рух %s: кадри %d–%d" % (imia, f0, f1))
    for o in novi:
        bpy.data.objects.remove(o)
    print("[mpfb] перенаправлено рухів: %d" % zrobleno)


def kadry(h):
    os.makedirs(KADRY, exist_ok=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = 600, 800
    svit = bpy.data.worlds.new("тло")
    svit.use_nodes = True
    svit.node_tree.nodes["Background"].inputs["Color"].default_value = \
        (0.6, 0.6, 0.62, 1)
    sc.world = svit
    l = bpy.data.objects.new("с", bpy.data.lights.new("с", "SUN"))
    l.data.energy = 3
    l.rotation_euler = (math.radians(50), 0, math.radians(30))
    sc.collection.objects.link(l)
    c = bpy.data.objects.new("к", bpy.data.cameras.new("к"))
    sc.collection.objects.link(c)
    sc.camera = c
    c.data.type = "ORTHO"
    c.data.ortho_scale = 2.0
    for nm, ang in (("перед", 0), ("бік", 90), ("зад", 180), ("обличчя", 0)):
        a = math.radians(ang)
        if nm == "обличчя":
            c.data.ortho_scale = 0.35
            ctr = Vector((0, 0, 1.62))
        else:
            c.data.ortho_scale = 2.0
            ctr = Vector((0, 0, 0.88))
        c.location = ctr + Vector((math.sin(a) * 6, -math.cos(a) * 6, 0))
        c.rotation_euler = (ctr - c.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(KADRY, nm + ".png")
        bpy.ops.render.render(write_still=True)


main()
