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
PIDBIR = None         # (маска спереду, маска збоку або None)
if "--підбір" in ARGS:
    i_ = ARGS.index("--підбір")
    mb_ = ARGS[i_ + 2] if i_ + 2 < len(ARGS) and ARGS[i_ + 2].endswith(".png") \
        else None
    PIDBIR = (ARGS[i_ + 1], mb_)
    del ARGS[i_:i_ + (3 if mb_ else 2)]
REF = None            # (кадр спереду, його маска) для проєкції
if "--референс" in ARGS:
    i_ = ARGS.index("--референс")
    REF = (ARGS[i_ + 1], ARGS[i_ + 2])
    del ARGS[i_:i_ + 3]
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
KUT_RUK = [90.0]       # кут рук від вертикалі на кадрі — з підбору
OKO_REF = [None]       # рівень очей на кадрі, пікселі знизу


def oko_kadru(ref, maska):
    """Точки обличчя кадру (`tools/oblychchia.py`) → рівень очей знизу."""
    import subprocess
    import numpy as np
    out = os.path.join(os.path.dirname(maska), "tochky-ref.npy")
    venv = os.path.expanduser("~/Програми/cv-venv/bin/python")
    korin = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
    r = subprocess.run([venv, os.path.join(korin, "tools", "oblychchia.py"),
                        ref, maska, out], capture_output=True, text=True)
    if r.returncode != 0:
        print("[mpfb] ‼ точки обличчя кадру не знайдено — масштаб за зростом")
        return None
    L = np.load(out)
    img = bpy.data.images.load(maska)
    y_top = float((L[33, 1] + L[263, 1]) / 2)
    print("[mpfb] очі на кадрі: %.1f px зверху" % y_top)
    return img.size[1] - y_top


def farba_ochei(ref, tochky):
    """Райдужка MakeHuman «brown» червонувата, на кадрі очі темні сіро-карі.
    Середній колір райдужки кадру (точки 468/473 + радіус з 469–471) →
    перефарбувати райдужку текстури очей: пікселі, що помітно відрізняються
    від білка (насиченість), домножаються, щоб їхнє середнє дорівнювало
    кадровому. Зіниця лишається, білок теж. Нова картинка — поруч із
    моделлю, ассет MPFB не чіпаємо."""
    import numpy as np
    L = np.load(tochky)
    im = bpy.data.images.load(ref)
    w, hh = im.size
    a = np.array(im.pixels[:], dtype=np.float32).reshape(hh, w, 4)[::-1, :, :3]
    yy, xx = np.mgrid[:hh, :w]
    px = []
    for c in (468, 473):
        r = max(1.5, 0.35 * np.linalg.norm(L[c + 1] - L[c + 3]))
        px.append(a[(xx - L[c, 0]) ** 2 + (yy - L[c, 1]) ** 2 < r * r])
    tsil = np.concatenate(px).mean(0)
    # Білок: усередині контуру повік, без кола райдужки. На кадрі він у
    # тіні повік і сіруватий; білосніжний білок MakeHuman давав «витріщені»
    # очі (ітерація MPFB-13).
    def vseredyni_mnohokutnyka(pts, poly):
        """Парність перетинів променя (у Blender немає matplotlib)."""
        x, y = pts[:, 0], pts[:, 1]
        res = np.zeros(len(pts), bool)
        for i in range(len(poly)):
            x1, y1 = poly[i]
            x2, y2 = poly[i - 1]
            perekh = (y1 > y) != (y2 > y)
            xp = x1 + (y - y1) * (x2 - x1) / (y2 - y1 + 1e-12)
            res ^= perekh & (x < xp)
        return res
    kontury = ((33, 7, 163, 144, 145, 153, 154, 155, 133, 173, 157, 158,
                159, 160, 161, 246),
               (263, 249, 390, 373, 374, 380, 381, 382, 362, 398, 384, 385,
                386, 387, 388, 466))
    bil = []
    sit = np.stack([xx.ravel() + 0.5, yy.ravel() + 0.5], 1)
    for kon, c in zip(kontury, (468, 473)):
        r = np.linalg.norm(L[c + 1] - L[c + 3]) / 2
        vseredyni = vseredyni_mnohokutnyka(sit, L[list(kon)]).reshape(hh, w)
        poza = (xx - L[c, 0]) ** 2 + (yy - L[c, 1]) ** 2 > (1.1 * r) ** 2
        bil.append(a[vseredyni & poza])
    bil = np.concatenate(bil)
    # Контур захоплює й повіки з віями (середнє виходило буре, MPFB-14) —
    # білок це найсвітліша третина.
    if len(bil) > 5:
        yask = bil.sum(1)
        tsil_bil = bil[yask >= np.percentile(yask, 70)].mean(0)
    else:
        tsil_bil = None
    bpy.data.images.remove(im)
    # Сітка очей MPFB зветься «Human.high-poly» — шукаємо за картинкою.
    for o in bpy.data.objects:
        if o.type != "MESH":
            continue
        for m in o.data.materials:
            for n in (m.node_tree.nodes if m and m.node_tree else []):
                if n.type != "TEX_IMAGE" or n.image is None \
                        or "_eye" not in n.image.name.lower():
                    continue
                t = n.image
                tw, th = t.size
                e = np.array(t.pixels[:], dtype=np.float32).reshape(th, tw, 4)
                rgb = e[..., :3]
                nas = rgb.max(-1) - rgb.min(-1)
                rai = (nas > 0.12) & (rgb.max(-1) > 0.08)
                if rai.sum() < 50:
                    continue
                k = tsil / np.maximum(rgb[rai].mean(0), 1e-3)
                rgb[rai] = np.clip(rgb[rai] * k, 0, 1)
                bilok = ~rai & (rgb.max(-1) > 0.35) & (e[..., 3] > 0.5)
                if tsil_bil is not None and bilok.sum() > 50:
                    kb = tsil_bil / np.maximum(rgb[bilok].mean(0), 1e-3)
                    rgb[bilok] = np.clip(rgb[bilok] * kb, 0, 1)
                    print("[mpfb] білок → %s (×%s, %d пікс. кадру)"
                          % (np.round(tsil_bil * 255).astype(int),
                             np.round(kb, 2), len(bil)))
                e[..., :3] = rgb
                nova = bpy.data.images.new("oko_kadru_eye", tw, th, alpha=True)
                nova.pixels[:] = e.ravel()
                nova.filepath_raw = os.path.join(
                    os.path.dirname(os.path.abspath(KUDY)), "oko_kadru_eye.png")
                nova.file_format = "PNG"
                os.makedirs(os.path.dirname(nova.filepath_raw), exist_ok=True)
                nova.save()
                n.image = nova
                for m2 in o.data.materials:
                    for n2 in (m2.node_tree.nodes if m2 and m2.node_tree
                               else []):
                        if n2.type == "TEX_IMAGE" and n2.image == t:
                            n2.image = nova
                print("[mpfb] очі → колір кадру %s (райдужка ×%s)"
                      % (np.round(tsil * 255).astype(int), np.round(k, 2)))
                return
    print("[mpfb] ‼ текстуру очей не знайдено — колір очей лишився MakeHuman")


def asset(*chastyny):
    return os.path.join(DANI, *chastyny)


def main():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    h = HumanService.create_human(macro_detail_dict=MAKRO)
    HumanService.add_builtin_rig(h, "game_engine")
    # Накладка брів — поки ні: на кадрі брови намальовані в шкірі, і з
    # проєкцією вони двоїлись (чорна смуга над очима). Окремі брови — разом
    # із зачіскою, коли з текстури обличчя прибиратимуться намальовані.
    for typ, shliakh in (("Eyes", asset("eyes", "high-poly", "high-poly.mhclo")),
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
    if REF:
        OKO_REF[0] = oko_kadru(os.path.abspath(REF[0]), os.path.abspath(REF[1]))
        if OKO_REF[0] is not None:
            farba_ochei(os.path.abspath(REF[0]), os.path.join(os.path.dirname(
                os.path.abspath(REF[1])), "tochky-ref.npy"))
    if PIDBIR:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import mpfb_pidbir
        if KADRY:
            os.makedirs(KADRY, exist_ok=True)
            mpfb_pidbir.NAKLADKA = os.path.join(KADRY, "накладка.png")
        arm0 = next(o for o in bpy.data.objects if o.type == "ARMATURE")
        _, rez = mpfb_pidbir.pidibraty(
            h, arm0, os.path.abspath(PIDBIR[0]),
            os.path.abspath(PIDBIR[1]) if PIDBIR[1] else None,
            oko_y=OKO_REF[0])
        KUT_RUK[0] = float(rez.get("кут рук", 90.0))
        if REF and OKO_REF[0] is not None:
            import numpy as np
            L_ref = np.load(os.path.join(os.path.dirname(os.path.abspath(
                REF[1])), "tochky-ref.npy"))
            rez["обличчя, px"] = mpfb_pidbir.pidibraty_oblychchia(
                h, arm0, None, None, KUT_RUK[0],
                lambda hh_: render_tochky(hh_, os.path.abspath(REF[1])),
                L_ref, OKO_REF[0], None)
        os.makedirs(os.path.dirname(os.path.abspath(KUDY)), exist_ok=True)
        with open(KUDY + ".підбір.json", "w") as f:
            json.dump(rez, f, ensure_ascii=False, indent=1)
        # Скелет — під нову статуру (MPFB перераховує суглоби з сітки).
        HumanService.refit(h)
    for o in list(bpy.data.objects):
        if o.name.startswith("Icosphere"):
            bpy.data.objects.remove(o)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    if REF:
        proektsiia(h, arm, os.path.abspath(REF[0]), os.path.abspath(REF[1]))
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


def proektsiia(h, arm, ref, maska):
    """Колір спереду — з кадру, решта — шкіра MakeHuman під тон кадру.

    Модель стає в позу кадру (T-поза), її вершини — в кадр тим самим
    правилом, що й у підборі (масштаб за зростом, центр — за тулубом).
    Друга розгортка «Проєкція» й «Видимість» — на базовій сітці (порядок
    вершин той самий: маску MPFB на час обчислення вимкнено), тоді
    запікання Cycles у рідну розгортку MakeHuman."""
    import numpy as np
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import mpfb_pidbir as pb_
    pb_.postavyty_ruky(arm, KUT_RUK[0])
    maska_mod = [m for m in h.modifiers if m.type == "MASK"]
    for m in maska_mod:
        m.show_viewport = False
    dg = bpy.context.evaluated_depsgraph_get()
    ev = h.evaluated_get(dg)
    me_e = ev.to_mesh()
    co = np.array([v.co[:] for v in me_e.vertices])
    nrm = np.array([v.normal[:] for v in me_e.vertices])
    ev.to_mesh_clear()
    for m in maska_mod:
        m.show_viewport = True
    me = h.data
    assert len(co) == len(me.vertices), "порядок вершин змінився"
    # Кадр: маска → масштаб і центр тим самим правилом, що в підборі.
    img = bpy.data.images.load(maska)
    w, hh = img.size
    px = np.empty(w * hh * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    mk = px.reshape(hh, w, 4)[..., 0] > 0.5
    ys, xs = np.where(mk)
    y0, y1 = ys.min(), ys.max() + 1
    vys = y1 - y0
    tul = (ys > y1 - 0.45 * vys) & (ys < y1 - 0.30 * vys)
    cx_r = float(np.median(xs[tul]))
    # Модель — лише тіло (без помічників MPFB: беремо вершини з вагою
    # кісток, як їх бачить маска).
    # Лише тіло: група «body» — та, що лишає маска MPFB (помічники одягу й
    # волосся теж мають ваги кісток і спотворили б масштаб).
    vidymi = np.zeros(len(co), bool)
    gi = h.vertex_groups["body"].index
    for v in me.vertices:
        vidymi[v.index] = any(g.group == gi and g.weight > 0.5 for g in v.groups)
    z = co[vidymi, 2]
    z0, z1 = z.min(), z.max()
    x = co[vidymi, 0]
    tulm = (z > z1 - 0.45 * (z1 - z0)) & (z < z1 - 0.30 * (z1 - z0))
    cx_m = float(np.median(x[tulm]))
    k = vys / (z1 - z0)                     # пікселів на метр
    if OKO_REF[0] is not None:
        # Від ступень до очей (кубики `joint-*-eye` у позованій сітці).
        idx = [h.vertex_groups[g].index for g in ("joint-l-eye", "joint-r-eye")]
        oz = float(np.mean([co[v.index, 2] for v in me.vertices
                            if any(gr.group in idx for gr in v.groups)]))
        k = (OKO_REF[0] - y0) / (oz - z0)
    # Глядач спереду (камера на −Y): праворуч у кадрі — +X.
    u = (cx_r + (co[:, 0] - cx_m) * k) / w
    v = (y0 + (co[:, 2] - z0) * k) / hh
    u, v = vyrivniaty_oblychchia(h, ref, maska, u, v, w, hh, cx_r, cx_m,
                                 y0, z0, k)
    f = -nrm[:, 1]
    vuzka = mk.copy()
    for _ in range(5):
        vuzka = vuzka & np.roll(vuzka, 1, 0) & np.roll(vuzka, -1, 0) \
            & np.roll(vuzka, 1, 1) & np.roll(vuzka, -1, 1)
    iu = np.clip((u * w).astype(int), 0, w - 1)
    iv = np.clip((v * hh).astype(int), 0, hh - 1)
    vaga = np.clip(f / 0.15, 0, 1) * vuzka[iv, iu]
    uvp = me.uv_layers.new(name="Проєкція")
    vyd = me.color_attributes.new("Видимість", "FLOAT_COLOR", "CORNER")
    for li, l in enumerate(me.loops):
        i = l.vertex_index
        uvp.data[li].uv = (u[i], v[i])
        vyd.data[li].color = (vaga[i],) * 3 + (1.0,)
    me.uv_layers.active = me.uv_layers[0]
    print("[mpfb] проєкція: видно спереду %.0f%% вершин"
          % (100 * (vaga > 0.5).mean()))
    zapekty(h, ref)
    me.uv_layers.remove(me.uv_layers["Проєкція"])
    for p_ in arm.pose.bones:
        p_.matrix_basis.identity()
    bpy.context.view_layer.update()


def vidobrazhennia(h, maska):
    """Вершини → пікселі кадру (x зліва, y ЗВЕРХУ): масштаб від ступень до
    очей, центр X — за тулубом. Те саме правило, що й у проєкції."""
    import numpy as np
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import mpfb_pidbir as pb_
    co, _ = pb_.vershyny_bez_masky(h)
    img = bpy.data.images.load(maska, check_existing=True)
    w, hh = img.size
    px = np.empty(w * hh * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    mk = px.reshape(hh, w, 4)[..., 0] > 0.5
    ys, xs = np.where(mk)
    y0, y1 = ys.min(), ys.max() + 1
    vys = y1 - y0
    tul = (ys > y1 - 0.45 * vys) & (ys < y1 - 0.30 * vys)
    cx_r = float(np.median(xs[tul]))
    gi = h.vertex_groups["body"].index
    tilo = np.array([any(g.group == gi and g.weight > 0.5 for g in v.groups)
                     for v in h.data.vertices])
    z = co[tilo, 2]
    z0, z1 = z.min(), z.max()
    tulm = (z > z1 - 0.45 * (z1 - z0)) & (z < z1 - 0.30 * (z1 - z0))
    cx_m = float(np.median(co[tilo, 0][tulm]))
    idx = [h.vertex_groups[g].index for g in ("joint-l-eye", "joint-r-eye")]
    oz = float(np.mean([co[v.index, 2] for v in h.data.vertices
                        if any(gr.group in idx for gr in v.groups)]))
    k = (OKO_REF[0] - y0) / (oz - z0)

    def proekt(c):
        return np.stack([cx_r + (c[:, 0] - cx_m) * k,
                         hh - (y0 + (c[:, 2] - z0) * k)], 1)
    return proekt, (w, hh, cx_r, cx_m, y0, z0, k)


def render_tochky(h, maska):
    """Рендер моделі в прив'язці кадру → її 478 точок обличчя (пікселі
    кадру, y зверху) і функція проєкції вершин."""
    import subprocess
    import numpy as np
    proekt, (w, hh, cx_r, cx_m, y0, z0, k) = vidobrazhennia(h, maska)
    sc = bpy.context.scene
    st = sc.render.engine
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "FLAT"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.film_transparent = True
    sc.view_settings.view_transform = "Standard"
    sc.render.resolution_x, sc.render.resolution_y = w, hh
    kam = bpy.data.objects.new("камера-точок", bpy.data.cameras.new("кт"))
    sc.collection.objects.link(kam)
    sc.camera = kam
    kam.data.type = "ORTHO"
    kam.data.ortho_scale = max(w, hh) / k
    kam.location = (cx_m + (0.5 * w - cx_r) / k, -10.0,
                    z0 + (0.5 * hh - y0) / k)
    kam.rotation_euler = (math.pi / 2, 0, 0)
    kam.data.clip_end = 30
    for o in bpy.data.objects:
        if o.type == "ARMATURE":
            o.hide_render = True
    tut = os.path.dirname(maska)
    kadr = os.path.join(tut, "tochky-render.png")
    sc.render.filepath = kadr
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(kam)
    sc.render.engine = st
    # Маска рендеру — з альфи.
    mpng = os.path.join(tut, "tochky-render-maska.png")
    im = bpy.data.images.load(kadr, check_existing=False)
    a = np.empty(im.size[0] * im.size[1] * 4, dtype=np.float32)
    im.pixels.foreach_get(a)
    a = a.reshape(im.size[1], im.size[0], 4)[..., 3]
    m2 = bpy.data.images.new("маска-рендеру", im.size[0], im.size[1])
    rgba = np.zeros((im.size[1], im.size[0], 4), np.float32)
    rgba[..., :3] = (a > 0.5)[..., None]
    rgba[..., 3] = 1
    m2.pixels.foreach_set(rgba.ravel())
    m2.filepath_raw = mpng
    m2.file_format = "PNG"
    m2.save()
    out = os.path.join(tut, "tochky-modeli.npy")
    venv = os.path.expanduser("~/Програми/cv-venv/bin/python")
    korin = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
    r = subprocess.run([venv, os.path.join(korin, "tools", "oblychchia.py"),
                        kadr, mpng, out], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError("точки обличчя моделі: " + r.stdout[-300:])
    return np.load(out), proekt


def vyrivniaty_oblychchia(h, ref, maska, u, v, w, hh, cx_r, cx_m, y0, z0, k):
    """Рендер моделі в прив'язці проєкції → опорні точки обличчя на ньому й
    на кадрі → зсув проєкції обличчя (`tools/oblychchia_warp.py`)."""
    import subprocess
    import numpy as np
    sc = bpy.context.scene
    stari_dvyg = sc.render.engine
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "FLAT"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.film_transparent = True
    sc.view_settings.view_transform = "Standard"
    sc.render.resolution_x, sc.render.resolution_y = w, hh
    kam = bpy.data.objects.new("камера-обличчя", bpy.data.cameras.new("ко"))
    sc.collection.objects.link(kam)
    sc.camera = kam
    kam.data.type = "ORTHO"
    kam.data.ortho_scale = max(w, hh) / k
    x_c = cx_m + (0.5 * w - cx_r) / k
    z_c = z0 + (0.5 * hh - y0) / k
    kam.location = (x_c, -10.0, z_c)
    kam.rotation_euler = (math.pi / 2, 0, 0)
    kam.data.clip_end = 30
    for o in bpy.data.objects:
        if o.type == "ARMATURE":
            o.hide_render = True
    tut = os.path.dirname(os.path.abspath(maska))
    kadr = os.path.join(tut, "obl-render.png")
    sc.render.filepath = kadr
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(kam)
    sc.render.engine = stari_dvyg
    P = np.stack([u * w, (1.0 - v) * hh], 1).astype(np.float32)
    p_in = os.path.join(tut, "obl-in.npy")
    p_out = os.path.join(tut, "obl-out.npy")
    np.save(p_in, P)
    venv = os.path.expanduser("~/Програми/cv-venv/bin/python")
    korin = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
    r = subprocess.run([venv, os.path.join(korin, "tools", "oblychchia_warp.py"),
                        ref, maska, kadr, p_in, p_out],
                       capture_output=True, text=True)
    print((r.stdout.strip().splitlines() or ["‼ " + r.stderr[-300:]])[-1])
    if r.returncode != 0 or not os.path.exists(p_out):
        print("[mpfb] ‼ обличчя не вирівняно — проєкція як є")
        return u, v
    Q = np.load(p_out)
    return Q[:, 0] / w, 1.0 - Q[:, 1] / hh


def zapekty(h, ref):
    import numpy as np
    me = h.data
    mat = me.materials[0]
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    tex_s = next(l.from_node for l in bsdf.inputs["Base Color"].links)
    ref_i = bpy.data.images.load(ref)

    def pikseli(o):
        w, hh = o.size
        a = np.empty(w * hh * 4, dtype=np.float32)
        o.pixels.foreach_get(a)
        return a.reshape(hh, w, 4)
    ps, pr = pikseli(tex_s.image), pikseli(ref_i)
    uv0, uvr = me.uv_layers[0].data, me.uv_layers["Проєкція"].data
    vyd = me.color_attributes["Видимість"].data
    a_, b_ = [], []
    for li in range(0, len(me.loops), 5):
        if vyd[li].color[0] < 0.95:
            continue
        uu, vv = uv0[li].uv
        a_.append(ps[min(ps.shape[0] - 1, int(vv * ps.shape[0])),
                     min(ps.shape[1] - 1, int(uu * ps.shape[1])), :3])
        uu, vv = uvr[li].uv
        b_.append(pr[min(pr.shape[0] - 1, max(0, int(vv * pr.shape[0]))),
                     min(pr.shape[1] - 1, max(0, int(uu * pr.shape[1]))), :3])
    gain = np.clip(np.median(np.array(b_), 0) /
                   np.maximum(np.median(np.array(a_), 0), 1e-3), 0.3, 3.0)
    print("[mpfb] тон шкіри MakeHuman → кадр: ×%s" % np.round(gain, 3))
    uv_a = nodes.new("ShaderNodeUVMap")
    uv_a.uv_map = me.uv_layers[0].name
    links.new(uv_a.outputs["UV"], tex_s.inputs["Vector"])
    mn = nodes.new("ShaderNodeMix")
    mn.data_type, mn.blend_type = "RGBA", "MULTIPLY"
    mn.inputs["Factor"].default_value = 1.0
    links.new(tex_s.outputs["Color"], mn.inputs[6])
    mn.inputs[7].default_value = (*[float(x) for x in gain], 1.0)
    uv_b = nodes.new("ShaderNodeUVMap")
    uv_b.uv_map = "Проєкція"
    tr = nodes.new("ShaderNodeTexImage")
    tr.image = ref_i
    tr.extension = "EXTEND"
    links.new(uv_b.outputs["UV"], tr.inputs["Vector"])
    at = nodes.new("ShaderNodeVertexColor")
    at.layer_name = "Видимість"
    mx = nodes.new("ShaderNodeMix")
    mx.data_type = "RGBA"
    links.new(at.outputs["Color"], mx.inputs["Factor"])
    links.new(mn.outputs[2], mx.inputs[6])
    links.new(tr.outputs["Color"], mx.inputs[7])
    links.new(mx.outputs[2], bsdf.inputs["Base Color"])
    for k_ in ("Metallic",):
        for l in list(bsdf.inputs[k_].links):
            links.remove(l)
        bsdf.inputs[k_].default_value = 0.0
    cil = bpy.data.images.new("аватар-шкіра", 4096, 4096)
    tc = nodes.new("ShaderNodeTexImage")
    tc.image = cil
    nodes.active = tc
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    try:
        pr_ = bpy.context.preferences.addons["cycles"].preferences
        pr_.compute_device_type = "OPTIX"
        pr_.get_devices()
        for d in pr_.devices:
            d.use = d.type == "OPTIX"
        sc.cycles.device = "GPU"
    except Exception as e:
        print("[mpfb] ‼ GPU для запікання: %s" % e)
    sc.cycles.samples = 1
    sc.render.bake.margin = 8
    for o in bpy.context.selected_objects:
        o.select_set(False)
    h.select_set(True)
    bpy.context.view_layer.objects.active = h
    me.uv_layers[0].active = True
    me.uv_layers[0].active_render = True
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"})
    cil.pack()
    for n in (mx, mn, tr, uv_b, at):
        nodes.remove(n)
    links.new(tc.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(uv_a.outputs["UV"], tc.inputs["Vector"])
    print("[mpfb] запечено шкіру 4096²")


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
