"""Пілот Б (П-281), крок 4 — одяг і взуття людини MPFB, три способи.

Слово замовника 08.11.2026: «переходь до кроку 4 — одяг і взуття» (план
пошаровий: основа → волосся → риси → одяг і взуття). Як у кроці 3 —
один комплект трьома способами, щоб вибрати якісніший; обраним потім
шиються решта типів (легка / важка / магічна, `data/items.json`).

Комплект — легкий: куртка, штани, черевики. Сітки мають імена, які вже
знає гра (`skinned_model.gd`, `PIECES`): `Одяг-Сорочка`, `Одяг-Штани`
(комірка «тіло»), `Одяг-Чоботи` («взуття»). Колір і матеріал дає річ
(`вигляд` у items.json), у моделі — лише крій.

Способи (`--спосіб`):
  А — як у манекенах гри (`make_races.py`): шматки шкіри, відсунуті
      назовні, стопа — опукла оболонка. Що зараз у грі в усіх рас.
  Б — готовий одяг MPFB (.mhclo): справжній крій зі складками й
      розгорткою, підганяється під тіло MPFB точно; сучасний (блуза,
      джинси, черевики) — у грі його перефарбовує річ.
  В — свій крій для гри: куртка з полами до середини стегна, комір і
      манжети, вільні штани, високі черевики з халявою й підошвою;
      поли й рукави провисають під симуляцією тканини (складки).

Тіло під річчю ховається (інакше шкіра пролазить крізь одяг на русі):
атрибут вершин тіла `під_одяг` (R — під сорочкою, G — штанами, B —
взуттям; промінь з тіла по нормалі влучає в річ), гра відкидає ці
місця, коли річ вдягнена (`avatar_skin.gdshader`, `hide_under`).

    blender -b <риси.blend> -P tools/blender/pilot_odiah.py -- <вихід.blend> --спосіб А|Б|В
"""
import functools
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector, kdtree
from mathutils.bvhtree import BVHTree

TUT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TUT)
print = functools.partial(print, flush=True)
ARGS = sys.argv[sys.argv.index("--") + 1:]
VYKHID = os.path.abspath(ARGS[0])
SPOSIB = ARGS[ARGS.index("--спосіб") + 1]

h = bpy.data.objects["Human"]
rig = bpy.data.objects["Human.rig"]
for pb in rig.pose.bones:
    pb.matrix_basis.identity()
if h.data.shape_keys:
    for k in h.data.shape_keys.key_blocks:
        k.value = 0.0
bpy.context.view_layer.update()

KANAL = {"Сорочка": 0, "Штани": 1, "Чоботи": 2, "Рукавиці": 3}
# деталі `Одяг-<комірка>-<тип>-<деталь>` — канал за кінцем імені
KANAL_DETALI = {"сорочка": 0, "штани": 1, "чоботи": 2, "поножі": 2, "наручі": 3,
                "рукавички": 3}
KOLIR = {"Сорочка": (0.42, 0.30, 0.18), "Штани": (0.22, 0.17, 0.12),
         "Чоботи": (0.12, 0.08, 0.05), "Пасок": (0.1, 0.065, 0.04)}


def tilo_bez_kliuchiv(imia="тимчасове-тіло"):
    """Копія тіла без форм-ключів (риси обличчя одягу не потрібні)."""
    o = h.copy()
    o.data = h.data.copy()
    o.name = imia
    bpy.context.scene.collection.objects.link(o)
    if o.data.shape_keys:
        o.shape_key_clear()
    return o


def vazhy_vid_tila(o, rozmyty=0):
    """Ваги кісток кожній вершині — від найближчої вершини шкіри
    (`rozmyty` — скільки разів згладити по сусідах: поли не рвуться)."""
    sk = h.data
    tree = kdtree.KDTree(len(sk.vertices))
    for v in sk.vertices:
        tree.insert(v.co, v.index)
    tree.balance()
    names = {g.index: g.name for g in h.vertex_groups}
    kosti = {n for n in names.values() if n in rig.data.bones}
    for g in list(o.vertex_groups):
        o.vertex_groups.remove(g)
    nv = len(o.data.vertices)
    vazhi = {}
    for v in o.data.vertices:
        _, at, _ = tree.find(o.matrix_world @ v.co)
        for g in sk.vertices[at].groups:
            n = names[g.group]
            if n in kosti and g.weight > 0.001:
                vazhi.setdefault(n, np.zeros(nv))[v.index] = g.weight
    if rozmyty:
        sus = [[] for _ in range(nv)]
        for e in o.data.edges:
            a, b = e.vertices
            sus[a].append(b)
            sus[b].append(a)
        for _ in range(rozmyty):
            for n, w in vazhi.items():
                vazhi[n] = np.array([(w[i] + sum(w[j] for j in sus[i])) / (1 + len(sus[i]))
                                     for i in range(nv)])
    suma = sum(vazhi.values())
    for n, w in vazhi.items():
        g = o.vertex_groups.new(name=n)
        w = w / np.maximum(suma, 1e-6)
        for i in np.where(w > 0.002)[0]:
            g.add([int(i)], float(w[i]), "REPLACE")
    if not any(m.type == "ARMATURE" for m in o.modifiers):
        md = o.modifiers.new("Armature", "ARMATURE")
        md.object = rig
    o.parent = rig


def material(imia, rgb, rough=0.85):
    import make_races as mr
    return mr.material(imia, rgb, rough)


# ── А: як у манекенах гри ───────────────────────────────────────────────
def sposib_a():
    import make_races as mr
    # межі — під тіло MPFB (1,74 м; кульшовий суглоб 0,91, коліно 0,50,
    # кісточка 0,07); решта — як у манекенах
    mr.CLOTHES = {k: v for k, v in mr.CLOTHES.items()
                  if k in ("Сорочка", "Штани", "Чоботи", "Пасок")}
    keep, gap, rgb, rough, _ = mr.CLOTHES["Сорочка"]
    mr.CLOTHES["Сорочка"] = (keep, gap, rgb, rough, lambda p: p.z >= 0.90)
    mr.FOOT_TOP = 0.09
    # у тіла MPFB, крім кісток, групи `body`, `Left`, `joint-…` — найбільша
    # вага має бути серед кісток
    kosti = set(rig.data.bones.keys())

    def dominant(obj):
        names = {g.index: g.name for g in obj.vertex_groups}
        out = {}
        for v in obj.data.vertices:
            gs = [g for g in v.groups if names.get(g.group) in kosti]
            if gs:
                out[v.index] = names[max(gs, key=lambda x: x.weight).group]
        return out
    mr.dominant = dominant
    tmp = tilo_bez_kliuchiv()
    rechi = mr.clothes(tmp)
    bpy.data.objects.remove(tmp)
    for o in rechi:
        if o.data.shape_keys:
            o.shape_key_clear()
        o.parent = rig
    return rechi


# ── Б: готовий одяг MPFB ────────────────────────────────────────────────
# .mhclo прив'язаний до номерів вершин повного тіла MPFB (з помічниками),
# а в `риси.blend` помічники вже вирізано — тому заготовка окремим
# проходом на `зачіски.blend` (`--спосіб Б-заготовка`), а тут лише
# переноситься. Річ -> (актив MPFB, який шматок: «верх»/«низ»/«усе»).
MPFB_RECHI = {"Сорочка": ("female_elegantsuit01", "верх"),
              "Штани": ("female_casualsuit01", "низ"),
              "Чоботи": ("shoes03", "черевик")}


def shmatky(o):
    """Зв'язні шматки сітки: [(середня висота, {індекси вершин})]."""
    me = o.data
    sus = [[] for _ in me.vertices]
    for e in me.edges:
        a, b = e.vertices
        sus[a].append(b)
        sus[b].append(a)
    bachyv = np.zeros(len(me.vertices), bool)
    out = []
    for s in range(len(me.vertices)):
        if bachyv[s]:
            continue
        st, comp = [s], set()
        bachyv[s] = True
        while st:
            x = st.pop()
            comp.add(x)
            for y in sus[x]:
                if not bachyv[y]:
                    bachyv[y] = True
                    st.append(y)
        out.append((float(np.mean([me.vertices[i].co.z for i in comp])), comp))
    return out


def sposib_b_zahotovka():
    from bl_ext.blender_org.mpfb.services.humanservice import HumanService
    from bl_ext.blender_org.mpfb.services.locationservice import LocationService
    dani = LocationService.get_user_data()
    rechi = []
    for rich, (aktyv, shmatok) in MPFB_RECHI.items():
        HumanService.add_mhclo_asset(os.path.join(dani, "clothes", aktyv, aktyv + ".mhclo"),
                                     h, asset_type="Clothes", material_type="MAKESKIN")
        o = next(x for x in bpy.data.objects if x.name.endswith("." + aktyv))
        if shmatok != "усе":
            sh = sorted(shmatky(o), key=lambda t: t[0])
            if shmatok == "черевик":
                # халява (шматки вище 15 см) пролазить крізь штанину
                lyshyty = set().union(*(c for _, c in sh if max(
                    o.data.vertices[i].co.z for i in c) <= 0.15))
            else:
                lyshyty = sh[-1][1] if shmatok == "верх" else sh[0][1]
            bm = bmesh.new()
            bm.from_mesh(o.data)
            bm.verts.ensure_lookup_table()
            bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.index not in lyshyty],
                             context="VERTS")
            bm.to_mesh(o.data)
            bm.free()
        o.name = "Одяг-" + rich
        rechi.append(o)
    # маски MPFB «Delete.*» на тілі тут не потрібні — тіло ховає гра
    keep = {o.name for o in rechi} | {rig.name}
    for o in list(bpy.data.objects):
        if o.name not in keep:
            bpy.data.objects.remove(o)
    return rechi


def sposib_b():
    zahotovka = os.path.join(os.path.dirname(VYKHID), "заготовка-Б.blend")
    with bpy.data.libraries.load(zahotovka) as (src, dst):
        dst.objects = [n for n in src.objects if n.startswith("Одяг-")]
    rechi = []
    for o in dst.objects:
        bpy.context.scene.collection.objects.link(o)
        o.parent = rig
        for md in o.modifiers:
            if md.type == "ARMATURE":
                md.object = rig
        rechi.append(o)
    return rechi


# ── В: свій крій ─────────────────────────────────────────────────────────
KOSTI = set(rig.data.bones.keys())


def dominanta(o):
    names = {g.index: g.name for g in o.vertex_groups}
    out = {}
    for v in o.data.vertices:
        gs = [g for g in v.groups if names.get(g.group) in KOSTI]
        if gs:
            out[v.index] = names[max(gs, key=lambda x: x.weight).group]
    return out


def shmatok_tila(imia, kosti, de, vidstup, zhladyty=0):
    """Копія шматка шкіри: вершини з головною кісткою з `kosti`, де `de(p)`;
    відсунута по нормалі на `vidstup(p)` м."""
    o = tilo_bez_kliuchiv(imia)
    dom = dominanta(o)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if dom.get(v.index, "") not in kosti
                               or not de(v.co)], context="VERTS")
    if zhladyty:
        # тканина не облягає кожну западину: згладити, межу не чіпати
        vnutr = [v for v in bm.verts if not v.is_boundary]
        for _ in range(zhladyty):
            bmesh.ops.smooth_vert(bm, verts=vnutr, factor=0.5,
                                  use_axis_x=True, use_axis_y=True, use_axis_z=True)
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * vidstup(v.co)
    bm.to_mesh(o.data)
    bm.free()
    for g in list(o.vertex_groups):
        if g.name not in KOSTI:
            o.vertex_groups.remove(g)
    o.data.materials.clear()
    return o


def vytiahnuty_kraj(o, vybraty, kroky):
    """Край сітки (межові ребра, де `vybraty(середина ребра)`) — витягнути
    кільцями: `kroky` — [(зсув як функція (точка краю, напрям назовні) -> Vector)].
    Повертає індекси нових вершин по кільцях."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    kraj = [e for e in bm.edges if e.is_boundary
            and vybraty((e.verts[0].co + e.verts[1].co) / 2)]
    vershyny = {v for e in kraj for v in e.verts}
    pochatok = {v: v.co.copy() for v in vershyny}
    kiltsia = []
    for f in kroky:
        r = bmesh.ops.extrude_edge_only(bm, edges=kraj)
        novi = [g for g in r["geom"] if isinstance(g, bmesh.types.BMVert)]
        kraj = [g for g in r["geom"] if isinstance(g, bmesh.types.BMEdge)
                and all(v in novi for v in g.verts)]
        # нова вершина пам'ятає, з якої вершини краю виросла
        for v in novi:
            src = min(pochatok, key=lambda s: (s.co - v.co).length)
            p0 = pochatok[src]
            v.co = p0 + f(p0)
            pochatok[v] = p0
        for s in [s for s in list(pochatok) if s not in novi and s.is_valid and s in vershyny]:
            pass
        vershyny = set(novi)
        pochatok = {v: pochatok[v] for v in novi}
        kiltsia.append(novi)
    bm.verts.index_update()
    idx = [[v.index for v in k] for k in kiltsia]
    bm.to_mesh(o.data)
    bm.free()
    return idx


def nazovni_xy(p, tsentr_y=0.0):
    d = Vector((p.x, p.y - tsentr_y, 0.0))
    return d.normalized() if d.length > 1e-6 else Vector((0, -1, 0))


def zadaty_vahy(o, vazhi):
    """vazhi: {кістка: np.array по вершинах} — замість наявних."""
    for g in list(o.vertex_groups):
        o.vertex_groups.remove(g)
    suma = sum(vazhi.values())
    for n, w in vazhi.items():
        g = o.vertex_groups.new(name=n)
        w = w / np.maximum(suma, 1e-6)
        for i in np.where(w > 0.002)[0]:
            g.add([int(i)], float(w[i]), "REPLACE")


def tkanyna(o, pryshpyl, kadriv=36):
    """Провисання під вагою з тілом як перешкодою (симуляція тканини на
    процесорі): `pryshpyl` — вага пришпилення по вершинах (1 — не рухати)."""
    pg = o.vertex_groups.new(name="пришпилити")
    for i, w in enumerate(pryshpyl):
        pg.add([i], float(w), "REPLACE")
    tilo = tilo_bez_kliuchiv("перешкода")
    tilo.modifiers.clear()
    col = tilo.modifiers.new("Collision", "COLLISION")
    tilo.collision.thickness_outer = 0.004
    zberehty = [md for md in o.modifiers]
    for md in zberehty:
        md.show_viewport = False
    cl = o.modifiers.new("Тканина", "CLOTH")
    s = cl.settings
    s.quality = 8
    s.mass = 0.2
    s.tension_stiffness = 12
    s.compression_stiffness = 12
    s.bending_stiffness = 0.4
    s.vertex_group_mass = "пришпилити"
    cl.collision_settings.use_collision = True
    cl.collision_settings.distance_min = 0.004
    sc = bpy.context.scene
    cl.point_cache.frame_start = 1
    cl.point_cache.frame_end = kadriv
    for f in range(1, kadriv + 1):
        sc.frame_set(f)
    dg = bpy.context.evaluated_depsgraph_get()
    ev = o.evaluated_get(dg)
    co = np.array([v.co[:] for v in ev.data.vertices])
    o.modifiers.remove(cl)
    for md in zberehty:
        md.show_viewport = True
    o.data.vertices.foreach_set("co", co.ravel())
    o.vertex_groups.remove(pg)
    bpy.data.objects.remove(tilo)
    sc.frame_set(1)
    del col


def zapekty_ao(o, rozmir=1024):
    """Нова розгортка й запечена світлотінь (AO) — власна картинка речі."""
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    while o.data.uv_layers:
        o.data.uv_layers.remove(o.data.uv_layers[0])
    o.data.uv_layers.new(name="UVMap")
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.01)
    bpy.ops.object.mode_set(mode="OBJECT")
    img = bpy.data.images.new(o.name + "-ao", rozmir, rozmir, alpha=True)
    img.pixels.foreach_set(np.zeros(rozmir * rozmir * 4, np.float32))   # тло прозоре
    mat = bpy.data.materials.new(o.name)
    mat.use_nodes = True
    nt = mat.node_tree
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.links.new(tex.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
    nt.nodes.active = tex
    o.data.materials.clear()
    o.data.materials.append(mat)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 48
    sc.render.bake.margin = 8
    sc.render.bake.use_clear = False     # інакше тло стає непрозорим чорним
    sc.world = sc.world or bpy.data.worlds.new("світ")
    sc.world.light_settings.distance = 0.25
    # затуляє лише тіло й інший одяг (не зачіски, брови тощо)
    skhovani = [x for x in bpy.data.objects if x.type == "MESH" and not x.hide_render
                and x != h and not x.name.startswith("Одяг-")]
    for x in skhovani:
        x.hide_render = True
    bpy.ops.object.bake(type="AO")
    for x in skhovani:
        x.hide_render = False
    # світлотінь м'якша: 0,35…1 (інакше складки чорні)
    px = np.array(img.pixels[:]).reshape(-1, 4)
    ye = px[:, 3] > 0                   # лише запечене, тло лишається прозорим
    px[ye, :3] = 0.35 + 0.65 * px[ye, :3]
    img.pixels.foreach_set(px.astype(np.float32).ravel())
    img.filepath_raw = os.path.join(os.path.dirname(VYKHID), o.name + "-ao.png")
    img.file_format = "PNG"
    img.save()


def sposib_v():
    nizh = {"thigh_l", "thigh_r", "calf_l", "calf_r"}
    # ── куртка: тулуб і руки до зап'ястя, поли, комір, манжети ──
    tulub = {"pelvis", "spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r",
             "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r", "neck_01"}
    kurtka = shmatok_tila("Одяг-Сорочка", tulub,
                          lambda p: p.z >= 0.90 and (p.z <= 1.44 or abs(p.x) > 0.09),
                          lambda p: 0.013, zhladyty=18)
    # поли: від краю на стегнах — 6 кілець донизу до середини стегна,
    # розходяться назовні (одна труба на обидві ноги, як у туніки)
    DOVZH, ROZKHID = 0.30, 0.07
    nv_bez_pol = len(kurtka.data.vertices)
    kiltsia = vytiahnuty_kraj(
        kurtka, lambda m: m.z < 0.95 and abs(m.x) < 0.25,
        [(lambda t: (lambda p0: Vector((0, 0, -DOVZH * t)) + nazovni_xy(p0, 0.0) * ROZKHID * t))(
            (i + 1) / 6) for i in range(6)])
    # поли дрібніше (двічі ділити ребра): інакше тканині ні з чого складатися
    for _ in range(2):
        bm = bmesh.new()
        bm.from_mesh(kurtka.data)
        bm.verts.ensure_lookup_table()
        polovi = [f for f in bm.faces if any(v.index >= nv_bez_pol for v in f.verts)]
        rebra = list({e for f in polovi for e in f.edges})
        bmesh.ops.subdivide_edges(bm, edges=rebra, cuts=1, use_grid_fill=True)
        bm.to_mesh(kurtka.data)
        bm.free()
        nv_bez_pol = min(nv_bez_pol, len(kurtka.data.vertices))
    # комір: край на шиї — 2 кільця вгору й трохи назовні
    vytiahnuty_kraj(kurtka, lambda m: m.z > 1.40 and abs(m.x) < 0.09,
                    [lambda p0: Vector((0, 0, 0.012)) + nazovni_xy(p0, 0.0) * 0.004,
                     lambda p0: Vector((0, 0, 0.026)) + nazovni_xy(p0, 0.0) * 0.010])
    # манжети: передпліччя біля зап'ястя — ширше від осі руки
    for bik in ("l", "r"):
        b = rig.data.bones["lowerarm_" + bik]
        a, z = b.head_local, b.tail_local
        os_ = (z - a).normalized()
        for v in kurtka.data.vertices:
            t = (v.co - a).dot(os_) / (z - a).length
            if t > 0.55 and (v.co - a).cross(os_).length < 0.09:
                rad = (v.co - a) - os_ * (v.co - a).dot(os_)
                v.co += rad.normalized() * 0.018 * min(1.0, (t - 0.55) / 0.4)
    # підрозділити поли (для складок)
    nv0 = len(kurtka.data.vertices)
    # ваги: тулуб і руки — від шкіри; поли — таз, донизу дедалі більше стегно
    vazhy_vid_tila(kurtka, rozmyty=1)
    hem_z0 = 0.93
    co = np.array([v.co[:] for v in kurtka.data.vertices])
    t = np.clip((hem_z0 - co[:, 2]) / DOVZH, 0, 1)
    s = np.clip((co[:, 0] + 0.04) / 0.08, 0, 1)        # +x — ліва нога
    names = [g.name for g in kurtka.vertex_groups]
    stari = {n: np.array([next((g.weight for g in v.groups if g.group == kurtka.vertex_groups[n].index), 0.0)
                          for v in kurtka.data.vertices]) for n in names}
    poly = t > 0
    nove = {n: np.where(poly, 0.0, w) for n, w in stari.items()}
    for n in ("pelvis", "thigh_l", "thigh_r"):
        nove.setdefault(n, np.zeros(len(co)))
    nove["pelvis"] = np.where(poly, 1 - 0.5 * t, nove["pelvis"])
    nove["thigh_l"] = np.where(poly, 0.5 * t * s, nove["thigh_l"])
    nove["thigh_r"] = np.where(poly, 0.5 * t * (1 - s), nove["thigh_r"])
    zadaty_vahy(kurtka, nove)
    tkanyna(kurtka, 1.0 - np.clip(t * 1.6, 0, 0.92))
    print("[одяг] куртка: вершин %d (поли %d)" % (len(co), int(poly.sum())), nv0)

    # ── штани: вільні, до халяви чобіт ──
    shtany = shmatok_tila("Одяг-Штани", {"pelvis", "spine_01"} | nizh,
                          lambda p: 0.30 <= p.z <= 0.99,
                          lambda p: 0.007 + 0.004 * float(np.clip((p.z - 0.35) / 0.25, 0, 1)),
                          zhladyty=3)
    vazhy_vid_tila(shtany, rozmyty=1)

    # ── черевики: високі, з вивернутою халявою; стопа — оболонка ──
    import make_races as mr
    choboty = shmatok_tila("Одяг-Чоботи", {"calf_l", "calf_r", "foot_l", "foot_r", "ball_l", "ball_r"},
                           lambda p: 0.09 <= p.z <= 0.42, lambda p: 0.010)
    vytiahnuty_kraj(choboty, lambda m: m.z > 0.40,
                    [lambda p0: Vector((0, 0, 0.008)) + nazovni_xy(p0, p0.y) * 0.0,
                     lambda p0: Vector((0, 0, 0.010)) + (p0 - Vector((0.15 if p0.x > 0 else -0.15, p0.y, p0.z))).normalized() * 0.012,
                     lambda p0: Vector((0, 0, -0.025)) + (p0 - Vector((0.15 if p0.x > 0 else -0.15, p0.y, p0.z))).normalized() * 0.016])
    tmp = tilo_bez_kliuchiv()
    for g in list(tmp.vertex_groups):
        if g.name not in KOSTI:
            tmp.vertex_groups.remove(g)
    mr.FOOT_TOP = 0.10
    stopy = mr._boot_feet(tmp, 0.010)
    bpy.data.objects.remove(tmp)
    bpy.ops.object.select_all(action="DESELECT")
    for ob in stopy:
        ob.select_set(True)
    choboty.select_set(True)
    bpy.context.view_layer.objects.active = choboty
    bpy.ops.object.join()
    vazhy_vid_tila(choboty, rozmyty=1)

    rechi = [kurtka, shtany, choboty]
    for o in rechi:
        for p in o.data.polygons:
            p.use_smooth = True
        zapekty_ao(o)
    return rechi


# ── Важка: два шари — тканина й об'ємні пластини ─────────────────────────
# Слово замовника 08.11.2026: одяг «не буде прилягати до тіла а буде трохи
# обемнішим хоч і повторюватиме тіло … важкої броні, взуття … очікую обемну
# структуру а десь будуть проглядати частини тіла». Тканина (стьобанка,
# широкі штани) — шкіра, відсунута на 1,5–3 см і згладжена; пластини —
# окремі тверді оболонки навколо осі (кістки чи тулуба) з товщиною й
# валиком по краю, кожна на одній кістці (на русі не тягнуться, а
# повертаються цілими), між ними проміжки — видно тканину й тіло.
# Імена: `Одяг-<комірка>-<тип>-<деталь>` (`skinned_model.gd`, `wear`);
# `підклад-…` — тканина під бронею (у грі темніший тон речі).
def oblast_bvh(kosti):
    """Дерево променів по шкірі, де головна кістка — з `kosti` (або, якщо
    `kosti` — число, вище за цю висоту: голова з обличчям)."""
    dom = dominanta(h)
    mw = h.matrix_world
    verts = [mw @ v.co for v in h.data.vertices]
    if isinstance(kosti, float):
        polys = [tuple(p.vertices) for p in h.data.polygons
                 if all(verts[i].z > kosti for i in p.vertices)]
    else:
        polys = [tuple(p.vertices) for p in h.data.polygons
                 if all(dom.get(i, "") in kosti for i in p.vertices)]
    return BVHTree.FromPolygons(verts, polys)


def ramka(u, bik):
    """Ортонормована рамка навколо осі `u`: v — уперед (−Y), w — назовні
    (для бік «l» +X, «r» −X, «» — +X)."""
    u = u.normalized()
    v = Vector((0, -1, 0)) - u * Vector((0, -1, 0)).dot(u)
    if v.length < 1e-4:
        v = Vector((0, 0, 1)) - u * u.z
    v.normalize()
    w = u.cross(v)
    znak = -1 if bik == "r" else 1
    if w.x * znak < 0 or (abs(w.x) < 1e-6 and w.z < 0):
        w = -w
    return u, v, w


# сітки оболонок: ім'я → (промінь, T, TH, радіус зовні, повне, ваги) —
# накладки й заклепки сідають на поверхню батька
GRATKY = {}


def sitka(imia, co, faces, tovsh, vahy, tsentr, faska=True):
    """Сітка з точок і граней → тверда деталь: товщина назовні, фаска,
    ваги `vahy(p)`."""
    me = bpy.data.meshes.new(imia)
    me.from_pydata([tuple(map(float, p)) for p in co], [], faces)
    o = bpy.data.objects.new(imia, me)
    bpy.context.scene.collection.objects.link(o)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    if sum((p.center - tsentr).dot(p.normal) for p in me.polygons) < 0:
        for p in me.polygons:
            p.flip()
    sd = o.modifiers.new("товщина", "SOLIDIFY")
    sd.thickness = tovsh
    sd.offset = 1.0
    sd.use_even_offset = True
    if faska:
        bv = o.modifiers.new("фаска", "BEVEL")
        bv.width = min(0.0015, tovsh * 0.4)
        bv.segments = 2
        bv.limit_method = "ANGLE"
        bv.harden_normals = False
    dg = bpy.context.evaluated_depsgraph_get()
    novyi = bpy.data.meshes.new_from_object(o.evaluated_get(dg))
    o.modifiers.clear()
    o.data = novyi
    for p in o.data.polygons:
        p.use_smooth = True
    if vahy is not None:
        nv = len(o.data.vertices)
        w = {}
        for v in o.data.vertices:
            for k, x in vahy(v.co).items():
                w.setdefault(k, np.zeros(nv))[v.index] = x
        zadaty_vahy(o, w)
        md = o.modifiers.new("Armature", "ARMATURE")
        md.object = rig
        o.parent = rig
    return o


def obolonka(imia, promin, nt, nth, kosti, zazor, povne=False, zhlad=8,
             tovsh=0.004, valyk=0.003, vahy=None, dirka=None, masht=None, zzovni=False):
    """Тверда оболонка: сітка (t ∈ 0…1) × (кут θ); `promin(t, θ)` → (початок,
    напрям) усередині тіла; промінь влучає в шкіру області `kosti`, радіус —
    обгортка (згладжена, ніде не нижче шкіри) + `zazor(t, θ)`. Товщина
    `tovsh`, край — валик назовні. `vahy(p)` → {кістка: вага}. `dirka(t, θ)`
    — де грані нема (проріз для очей). Ряд без жодного влучання — радіус 0
    (верхівка шолома). `masht(t)` — множник радіуса (гострий ніс, кругла
    п'ята сабатона: 0 — точка на осі). `zzovni` — промінь іде ззовні до осі:
    влучає в зовнішню шкіру, а не в порожнини (рот, щілини між пальцями)."""
    bvh = oblast_bvh(kosti)
    T = np.linspace(0, 1, nt)
    TH = np.linspace(0, 1, nth, endpoint=not povne)
    org = np.zeros((nt, nth, 3))
    dr = np.zeros((nt, nth, 3))
    r = np.full((nt, nth), np.nan)
    for i, t in enumerate(T):
        for j, th in enumerate(TH):
            o, d = promin(t, th)
            d = d.normalized()
            org[i, j], dr[i, j] = o, d
            if zzovni:
                hit = bvh.ray_cast(o + d * 0.35, -d, 0.35)
                if hit[0] is not None:
                    r[i, j] = 0.35 - hit[3]
                continue
            hit = bvh.ray_cast(o, d, 0.5)
            if hit[0] is not None:
                r[i, j] = hit[3]
    for i in range(nt):
        ok = ~np.isnan(r[i])
        r[i, ~ok] = r[i, ok].mean() if ok.any() else 0.0
    syre = r.copy()
    for _ in range(zhlad):
        p = np.pad(r, ((1, 1), (0, 0)), mode="edge")
        if povne:
            p = np.concatenate([p[:, -1:], p, p[:, :1]], axis=1)
        else:
            p = np.pad(p, ((0, 0), (1, 1)), mode="edge")
        hl = (p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:] + 2 * p[1:-1, 1:-1]) / 6
        r = np.maximum(hl, syre)
    z = np.array([[zazor(t, th) for th in TH] for t in T])
    r = r + z
    if valyk:
        r[0] += valyk
        r[-1] += valyk
        if not povne:
            r[:, 0] += valyk
            r[:, -1] += valyk
    if masht is not None:
        r = r * np.array([masht(t) for t in T])[:, None]
    co = org + dr * r[..., None]
    faces = []
    nj = nth if povne else nth - 1
    for i in range(nt - 1):
        for j in range(nj):
            if dirka is not None:
                tc = (T[i] + T[i + 1]) / 2
                thc = (TH[j] + (TH[(j + 1) % nth] if j + 1 < nth else 1.0)) / 2
                if dirka(tc, thc):
                    continue
            j2 = (j + 1) % nth
            faces.append((i * nth + j, i * nth + j2, (i + 1) * nth + j2, (i + 1) * nth + j))
    GRATKY[imia] = (promin, T, TH, r + tovsh, povne, vahy)
    return sitka(imia, co.reshape(-1, 3), faces, tovsh, vahy,
                 Vector(org.reshape(-1, 3).mean(0)))


def na_batku(batko, t, th, dod=0.0):
    """Точка на зовнішній поверхні оболонки `batko` у (t, θ) і напрям назовні."""
    promin, T, TH, R, povne, _ = GRATKY[batko]
    nt, nth = R.shape
    fi = float(np.clip(t, 0, 1)) * (nt - 1)
    i0 = min(int(fi), nt - 2)
    a = fi - i0
    if povne:
        fj = (th % 1.0) * nth
        j0 = int(fj) % nth
        j1 = (j0 + 1) % nth
    else:
        fj = float(np.clip(th, 0, 1)) * (nth - 1)
        j0 = min(int(fj), nth - 2)
        j1 = j0 + 1
    b = fj - int(fj)
    rr = ((1 - a) * ((1 - b) * R[i0, j0] + b * R[i0, j1])
          + a * ((1 - b) * R[i0 + 1, j0] + b * R[i0 + 1, j1]))
    o, d = promin(t, th)
    d = d.normalized()
    return o + d * (rr + dod), d


def nakladka(batko, imia, mapa, ns, nu, dod=0.0008, tovsh=0.0022):
    """Смуга на поверхні батька: `mapa(s, u)` → (t, θ) батька, s, u ∈ 0…1.
    Латунні обідки, ребра, хрест на грудях. Ваги — батькові."""
    co = []
    for s in np.linspace(0, 1, ns):
        for u in np.linspace(0, 1, nu):
            co.append(na_batku(batko, *mapa(s, u), dod)[0])
    faces = [(i * nu + j, i * nu + j + 1, (i + 1) * nu + j + 1, (i + 1) * nu + j)
             for i in range(ns - 1) for j in range(nu - 1)]
    promin = GRATKY[batko][0]
    tsentr = promin(0.5, 0.5)[0]
    return sitka(imia, co, faces, tovsh, GRATKY[batko][5], tsentr)


def obidok(batko, imia, t0, t1, th0=0.0, th1=1.0, ns=None, nu=3, **kw):
    """Смуга вздовж батька: t ∈ [t0, t1], θ ∈ [th0, th1]."""
    nth = len(GRATKY[batko][2])
    ns = ns or max(4, int(abs(th1 - th0) * nth * 2) + 1)
    return nakladka(batko, imia, lambda s, u: (t0 + (t1 - t0) * u, th0 + (th1 - th0) * s),
                    ns, nu, **kw)


def zaklepky(batko, imia, tochky, r=0.0045, splask=0.45):
    """Заклепки (сплюснуті півкулі) на поверхні батька в точках (t, θ)."""
    bm = bmesh.new()
    for t, th in tochky:
        p, d = na_batku(batko, t, th, r * splask * 0.3)
        g = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=r)
        vs = g["verts"]
        q = Vector((0, 0, 1)).rotation_difference(d)
        for v in vs:
            v.co.z *= splask
            v.co = q @ v.co + p
    me = bpy.data.meshes.new(imia)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(imia, me)
    bpy.context.scene.collection.objects.link(o)
    for pl in me.polygons:
        pl.use_smooth = True
    vahy = GRATKY[batko][5]
    if vahy is not None:
        nv = len(me.vertices)
        w = {}
        for v in me.vertices:
            for k, x in vahy(v.co).items():
                w.setdefault(k, np.zeros(nv))[v.index] = x
        zadaty_vahy(o, w)
        md = o.modifiers.new("Armature", "ARMATURE")
        md.object = rig
        o.parent = rig
    return o


def z_iednaty(imia, chastyny):
    bpy.ops.object.select_all(action="DESELECT")
    for x in chastyny:
        x.select_set(True)
    bpy.context.view_layer.objects.active = chastyny[0]
    if len(chastyny) > 1:
        bpy.ops.object.join()
    o = chastyny[0]
    o.name = imia
    o.data.name = imia
    return o


def tverda(kist):
    return lambda p: {kist: 1.0}


def kistka(n):
    b = rig.data.bones[n]
    return b.head_local.copy(), b.tail_local.copy()


def vzdovzh(n, bik, t0, t1, th0, th1, a=None, b=None):
    """Промінь навколо кістки `n` (або відрізка a→b): t — від t0 до t1 її
    довжини (t0, t1 можуть бути функціями кута в градусах), θ (градуси;
    0 — уперед, 90 — назовні)."""
    if a is None:
        a, b = kistka(n)
    u, v, w = ramka(b - a, bik)

    def f(t, th):
        kg = th0 + (th1 - th0) * th
        lo = t0(kg) if callable(t0) else t0
        hi = t1(kg) if callable(t1) else t1
        k = np.radians(kg)
        return a + (b - a) * (lo + (hi - lo) * t), v * np.cos(k) + w * np.sin(k)
    return f


def kut(th, th0, th1):
    """θ сітки (0…1) → градуси."""
    return th0 + (th1 - th0) * th


def horb(x, shyr):
    """Плавний горб висотою 1 і півшириною `shyr` (ребро по центру)."""
    return float(np.exp(-(x / shyr) ** 2))


def sposib_vazhka():
    """Важка броня, сталевий сет (грейд C) за референсом
    `art/пілот-б-2026-11-07/одяг/v3/r/сталевий-референс.jpg` (значки гри).
    Сітки: пластини (колір речі), `-оздоба` (латунь), `-підклад-` (стьобанка,
    кольчуга), `-шкіра-` (пояс, рукавички), `-тканина-` (шарф)."""
    TULUB = {"pelvis", "spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r", "neck_01"}
    rechi = []
    ozdoba = {"тіло": [], "рукавиці": [], "взуття": [], "голова": []}

    # ── підклад: кольчуга-стьобанка до стегон, рукави до зап'ястя ──
    sorochka = shmatok_tila(
        "Одяг-тіло-важка-підклад-сорочка",
        TULUB | {"upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r"},
        lambda p: p.z >= 0.88 and (p.z <= 1.45 or abs(p.x) > 0.10),
        lambda p: 0.017 if abs(p.x) < 0.28 else 0.022, zhladyty=20)
    vazhy_vid_tila(sorochka, rozmyty=1)

    def shyr(p):        # штани: вузько в поясі, найширше під коліном, заправлені
        z = p.z
        if z > 0.65:
            return 0.014 + 0.016 * (0.92 - min(z, 0.92)) / 0.27
        if z > 0.55:
            return 0.030
        return 0.008 + 0.022 * max(0.0, (z - 0.45) / 0.10)
    shtany = shmatok_tila("Одяг-тіло-важка-підклад-штани",
                          {"pelvis", "spine_01", "thigh_l", "thigh_r", "calf_l", "calf_r"},
                          lambda p: 0.30 <= p.z <= 0.99, shyr, zhladyty=3)
    vazhy_vid_tila(shtany, rozmyty=1)
    rechi += [sorochka, shtany]
    # кольчужний комір-стійка на шиї
    ka, kb = kistka("neck_01")
    komir = obolonka("Одяг-тіло-важка-підклад-комір",
                     vzdovzh("neck_01", "", -0.15, 0.75, 0, 360), 8, 40,
                     {"neck_01", "spine_03", "head", "clavicle_l", "clavicle_r"},
                     lambda t, th: 0.010 + 0.012 * (1 - t), povne=True, zhlad=10,
                     tovsh=0.004, valyk=0.003,
                     vahy=lambda p: {"neck_01": float(np.clip((p.z - ka.z) / 0.06, 0.2, 1)),
                                     "spine_03": 1 - float(np.clip((p.z - ka.z) / 0.06, 0.2, 1))})
    rechi.append(komir)

    # ── нагрудник: опуклий, ребро посередині, пройми для рук ──
    vis = Vector((0, -0.01, 0))

    def tulub(zb, zt, th0=0.0, th1=360.0, proima=0.0):
        def f(t, th):
            k = np.radians(th0 + (th1 - th0) * th)
            verkh = zt - proima * np.sin(k) ** 2       # нижче на боках
            return Vector((vis.x, vis.y, zb + (verkh - zb) * t)), \
                Vector((np.sin(k), -np.cos(k), 0))
        return f

    def dkut(th):       # кут від переду, −180…180
        return (th * 360 + 180) % 360 - 180
    NG = "Одяг-тіло-важка-нагрудник"
    nahrudnyk = obolonka(NG, tulub(1.13, 1.40, proima=0.12), 16, 72, TULUB,
                         lambda t, th: 0.026 + 0.007 * horb(dkut(th), 7) * (0.4 + 0.6 * t),
                         povne=True, zhlad=14, tovsh=0.005, valyk=0.004,
                         vahy=lambda p: {"spine_03": 1.0} if p.z > 1.20 else
                         {"spine_03": 0.6, "spine_02": 0.4})
    rechi.append(nahrudnyk)
    o_t = ozdoba["тіло"]
    o_t.append(obidok(NG, "ног1", 0.0, 0.07))
    o_t.append(obidok(NG, "ног2", 0.93, 1.0))
    # латунний хрест на грудях
    o_t.append(nakladka(NG, "хрест1", lambda s, u: (0.50 + 0.30 * s, (-1.4 + 2.8 * u) / 360),
                        8, 3, dod=0.0015, tovsh=0.003))
    o_t.append(nakladka(NG, "хрест2", lambda s, u: (0.66 + 0.06 * u, (-6 + 12 * s) / 360),
                        8, 3, dod=0.0015, tovsh=0.003))
    o_t.append(zaklepky(NG, "хрест3", [(0.69, 0.0)], r=0.006, splask=0.5))

    # пластини на животі: три смуги внахльост, кожна трохи ширша за верхню
    plast = []
    for i, (zb, zt, kist) in enumerate([(1.075, 1.140, "spine_02"), (1.025, 1.090, "spine_01"),
                                         (0.975, 1.040, "spine_01")]):
        im = "смуга%d" % i
        plast.append(obolonka(im, tulub(zb, zt), 5, 72, TULUB,
                              (lambda d: lambda t, th: d)(0.030 + 0.005 * i), povne=True,
                              zhlad=14, tovsh=0.004, valyk=0.003, vahy=tverda(kist)))
        o_t.append(obidok(im, im + "о", 0.0, 0.22, nu=2))
    rechi.append(z_iednaty("Одяг-тіло-важка-пластини", plast))
    # шкіряний пояс із латунними пряжками
    poyas = obolonka("Одяг-тіло-важка-шкіра-пояс", tulub(0.925, 0.985), 5, 72, TULUB,
                     lambda t, th: 0.044, povne=True, zhlad=14, tovsh=0.005, valyk=0.0,
                     vahy=tverda("pelvis"))
    rechi.append(poyas)
    o_t.append(nakladka("Одяг-тіло-важка-шкіра-пояс", "пряжка",
                        lambda s, u: (0.1 + 0.8 * u, (-3.5 + 7 * s) / 360), 4, 4,
                        dod=0.001, tovsh=0.004))
    o_t.append(zaklepky("Одяг-тіло-важка-шкіра-пояс", "пряжки",
                        [(0.5, a / 360) for a in (-60, -30, 30, 60, 150, 180, 210)],
                        r=0.006, splask=0.5))

    # червоний шарф навскіс: з лівого плеча через груди до правого боку
    def sharf(s, u):
        t = 0.97 - 0.97 * s
        a = 38 - 80 * s + (-6 + 12 * u)
        return t, a / 360
    rechi.append(nakladka(NG, "Одяг-тіло-важка-тканина-шарф", sharf, 18, 4,
                          dod=0.0025, tovsh=0.004))

    # ── наплічники: чаша на плечі зі спіраллю-заклепкою, під нею 3 смуги ──
    napl = []
    for bik in ("l", "r"):
        zn = 1 if bik == "l" else -1
        a, b = kistka("upperarm_" + bik)
        os_ = (Vector((zn * 0.45, 0, 1.0))).normalized()
        u_, v_, w_ = ramka(os_, bik)
        tsentr = a + Vector((-zn * 0.012, 0, -0.03))

        def chasha(t, th, tsentr=tsentr, os_=os_, v_=v_, w_=w_):
            f = np.radians(70 * t)
            k = np.radians(th * 360)
            return tsentr, os_ * np.cos(f) + (v_ * np.cos(k) + w_ * np.sin(k)) * np.sin(f)
        im = "чаша" + bik
        napl.append(obolonka(im, chasha, 12, 40,
                             {"upperarm_" + bik, "clavicle_" + bik, "spine_03"},
                             lambda t, th: 0.030 + 0.008 * t, povne=True, zhlad=10,
                             tovsh=0.005, valyk=0.004, vahy=tverda("upperarm_" + bik)))
        o_t.append(obidok(im, im + "о", 0.90, 1.0, nu=2))
        o_t.append(zaklepky(im, im + "д", [(0.42, 0.25)], r=0.020, splask=0.18))
        o_t.append(zaklepky(im, im + "з", [(0.42, 0.25)], r=0.007, splask=0.9))
        for i, (t0, t1, zz, roz) in enumerate([(0.10, 0.32, 0.034, 0.0), (0.26, 0.46, 0.042, 0.0),
                                               (0.40, 0.60, 0.048, 0.030)]):
            im = "напл%s%d" % (bik, i)
            napl.append(obolonka(
                im, vzdovzh("upperarm_" + bik, bik, t0, t1, -40, 220), 6, 28,
                {"upperarm_" + bik, "clavicle_" + bik, "spine_03"},
                (lambda zz, roz: lambda t, th: zz + roz * t * t)(zz, roz), zhlad=10,
                tovsh=0.0045, valyk=0.003, vahy=tverda("upperarm_" + bik)))
            o_t.append(obidok(im, im + "о", 0.80, 1.0, nu=2))
    rechi.append(z_iednaty("Одяг-тіло-важка-наплічники", napl))

    # ── набедреники: дві великі спереду, менші з боків, заклепки по кутах ──
    nab = []
    for bik in ("l", "r"):
        for i, (th0, th1, t1) in enumerate([(-62, 12, 0.40), (20, 92, 0.30)]):
            def vh(p, bik=bik):
                a, b = kistka("thigh_" + bik)
                t = float(np.clip((a.z - p.z) / (a.z - b.z) / 0.4, 0, 1))
                return {"pelvis": 1 - 0.6 * t, "thigh_" + bik: 0.6 * t}
            im = "наб%s%d" % (bik, i)
            nab.append(obolonka(
                im, vzdovzh("thigh_" + bik, bik, -0.02, t1, th0, th1), 8, 16,
                {"thigh_" + bik, "pelvis"}, lambda t, th: 0.042 + 0.026 * t, zhlad=8,
                tovsh=0.0045, valyk=0.003, vahy=vh))
            o_t.append(obidok(im, im + "о", 0.88, 1.0, nu=2))
            o_t.append(zaklepky(im, im + "з", [(0.12, 0.12), (0.12, 0.88), (0.80, 0.12),
                                               (0.80, 0.88)]))
    rechi.append(z_iednaty("Одяг-тіло-важка-набедреники", nab))

    # ── рукавиці: розтруб до половини ліктя, пластина на кисті, рукавички ──
    nar = []
    o_r = ozdoba["рукавиці"]
    for bik in ("l", "r"):
        im = "нар" + bik
        nar.append(obolonka(im, vzdovzh("lowerarm_" + bik, bik, 0.22, 1.0, 0, 360), 10, 32,
                            {"lowerarm_" + bik, "hand_" + bik},
                            lambda t, th: 0.008 + 0.026 * (1 - t) ** 2, povne=True,
                            zhlad=8, tovsh=0.004, valyk=0.004, vahy=tverda("lowerarm_" + bik)))
        o_r.append(obidok(im, im + "о1", 0.0, 0.07, nu=2, tovsh=0.003))
        o_r.append(obidok(im, im + "о2", 0.86, 0.95, nu=2, tovsh=0.003))
        # пластина на тильному боці: вісь від зап'ястя до середнього пальця
        ha = kistka("hand_" + bik)[0]
        hb = kistka("middle_01_" + bik)[0]
        poper = kistka("pinky_01_" + bik)[0] - kistka("index_01_" + bik)[0]
        tyl = (hb - ha).cross(poper).normalized()
        if tyl.x * (1 if bik == "l" else -1) + tyl.z < 0:
            tyl = -tyl
        os_ = (hb - ha).normalized()
        bok = os_.cross(tyl).normalized()

        def kyst(t, th, ha=ha, hb=hb, tyl=tyl, bok=bok):
            k = np.radians(-60 + 120 * th)
            return ha + (hb - ha) * (-0.05 + 1.0 * t), tyl * np.cos(k) + bok * np.sin(k)
        im = "кисть" + bik
        nar.append(obolonka(im, kyst, 8, 12, {"hand_" + bik}, lambda t, th: 0.006,
                            zhlad=6, tovsh=0.0035, valyk=0.002, vahy=tverda("hand_" + bik)))
        o_r.append(zaklepky(im, im + "з", [(0.5, 0.5)], r=0.007, splask=0.5))
    rechi.append(z_iednaty("Одяг-рукавиці-важка-наручі", nar))
    PALTSI = {n for n in KOSTI if n.split("_")[0] in ("hand", "index", "middle", "ring",
                                                       "pinky", "thumb")}
    rukavychky = shmatok_tila("Одяг-рукавиці-важка-шкіра-рукавички", PALTSI,
                              lambda p: True, lambda p: 0.0035)
    vazhy_vid_tila(rukavychky)
    rechi.append(rukavychky)
    # латунні наконечники пальців
    kinchyky = []
    for bik in ("l", "r"):
        for n in ("thumb", "index", "middle", "ring", "pinky"):
            a, b = kistka("%s_03_%s" % (n, bik))
            bm = bmesh.new()
            bmesh.ops.create_cone(bm, cap_ends=True, segments=10, radius1=0.0075,
                                  radius2=0.0015, depth=0.016)
            q = Vector((0, 0, 1)).rotation_difference((b - a).normalized())
            for v in bm.verts:
                v.co = q @ v.co + a + (b - a) * 0.75
            me = bpy.data.meshes.new("кінчик")
            bm.to_mesh(me)
            bm.free()
            o = bpy.data.objects.new("кінчик", me)
            bpy.context.scene.collection.objects.link(o)
            zadaty_vahy(o, {"%s_03_%s" % (n, bik): np.ones(len(me.vertices))})
            o.modifiers.new("Armature", "ARMATURE").object = rig
            o.parent = rig
            kinchyky.append(o)
    o_r += kinchyky

    # ── поножі: навколо гомілки, спереду гострий виступ над коліном ──
    pon = []
    o_v = ozdoba["взуття"]
    for bik in ("l", "r"):
        a, b = kistka("calf_" + bik)

        def verkh(kg):
            return 0.07 - 0.17 * max(0.0, np.cos(np.radians(kg))) ** 6
        im = "пон" + bik
        pon.append(obolonka(im, vzdovzh("calf_" + bik, bik, verkh, 0.95, -180, 180), 18, 40,
                            {"calf_" + bik, "thigh_" + bik},
                            lambda t, th: 0.018 + 0.012 * (1 - t) ** 2 + 0.006 * horb(kut(th, -180, 180), 9),
                            povne=True, zhlad=10, tovsh=0.0045, valyk=0.004,
                            vahy=tverda("calf_" + bik)))
        o_v.append(obidok(im, im + "о", 0.0, 0.06, nu=2))
        # латунне ребро спереду і роздвоєння вгорі
        o_v.append(nakladka(im, im + "р", lambda s, u: (0.10 + 0.55 * s,
                                                        0.5 + (-2 + 4 * u) / 360), 12, 3,
                            dod=0.001, tovsh=0.003))
        for zn in (-1, 1):
            o_v.append(nakladka(im, im + "в%d" % zn,
                                lambda s, u, zn=zn: (0.10 + 0.16 * s,
                                                     0.5 + zn * (2 + 22 * s ** 1.5 + 3 * u) / 360),
                                10, 3, dod=0.001, tovsh=0.003))
    rechi.append(z_iednaty("Одяг-взуття-важка-поножі", pon))

    # ── сабатони: оболонка навколо осі п'ята → носок, ніс загострений ──
    sab = []
    for bik in ("l", "r"):
        fa = kistka("foot_" + bik)[0]
        bt = kistka("ball_" + bik)[1]
        A = Vector((fa.x, fa.y + 0.080, 0.060))
        B = Vector((bt.x + (0.004 if bik == "l" else -0.004), bt.y - 0.040, 0.026))

        def zz(t, th):
            k = np.radians(kut(th, 0, 360))
            vnyz = (1 - np.cos(k)) / 2                    # 0 — догори, 1 — донизу
            return 0.016 - 0.012 * vnyz

        def kintsi(t):      # п'ята кругла, ніс гострий
            if t < 0.10:
                return float(np.sqrt(max(0.0, 1 - ((0.10 - t) / 0.10) ** 2)))
            return 1 - 0.8 * float(np.clip((t - 0.78) / 0.22, 0, 1)) ** 1.6
        im = "саб" + bik
        sab.append(obolonka(im, vzdovzh("", bik, 0.0, 1.0, 0, 360, a=A, b=B), 18, 32,
                            {"foot_" + bik, "ball_" + bik}, zz, povne=True, zhlad=6,
                            tovsh=0.004, valyk=0.0, masht=kintsi, zzovni=True,
                            vahy=lambda p, bik=bik, fa=fa: {"foot_" + bik: 1.0}
                            if p.y > fa.y - 0.10 else {"ball_" + bik: 1.0}))
        o_v.append(nakladka(im, im + "н", lambda s, u: (0.55 + 0.35 * s,
                                                        (-2.5 + 5 * u) / 360), 8, 3,
                            dod=0.001, tovsh=0.003))
    rechi.append(z_iednaty("Одяг-взуття-важка-чоботи", sab))

    # ── шолом: закритий, проріз для очей, хвіст над потилицею ──
    C = Vector((0, -0.025, 1.625))
    F0, F1 = -42.0, 88.0

    def sfera(t, th):
        k = np.radians(th * 360 - 180)                  # 0 — потилиця, ±180 — обличчя
        f = np.radians(F0 + (F1 - F0) * t)
        hor = Vector((np.sin(k), np.cos(k), 0))         # k=0 → +Y (потилиця)
        return C, hor * np.cos(f) + Vector((0, 0, 1)) * np.sin(f)

    def lyk(th):        # кут від обличчя, 0…180
        return abs(abs(th * 360 - 180) - 180)
    PRORIZ = (17.0, 25.5, 58.0)                         # φ від, φ до, півширина

    def proriz(t, th):
        f = F0 + (F1 - F0) * t
        return PRORIZ[0] < f < PRORIZ[1] and lyk(th) < PRORIZ[2]

    def zz_sh(t, th):
        f = F0 + (F1 - F0) * t
        k = th * 360 - 180
        hvist = 0.030 * max(0.0, 1 - (f - F0) / 22) ** 2 * horb(k, 55)   # потилиця
        hreb = 0.005 * horb(np.degrees(np.arcsin(np.sin(np.radians(k)))), 5) * \
            float(np.clip((f - 10) / 25, 0, 1)) * float(np.clip((76 - f) / 16, 0, 1))
        zabralo = 0.006 * horb(lyk(th), 40) * float(f < PRORIZ[1] + 4)
        return 0.028 + hvist + hreb + zabralo
    SH = "Одяг-голова-важка-шолом"
    sholom = obolonka(SH, sfera, 30, 72, 1.50, zz_sh, povne=True, zhlad=10,
                      tovsh=0.005, valyk=0.004, vahy=tverda("head"), dirka=proriz, zzovni=True)
    rechi.append(sholom)
    o_h = ozdoba["голова"]
    o_h.append(obidok(SH, "шо1", 0.0, 0.035, nu=2))
    tp = lambda f: (f - F0) / (F1 - F0)
    for f0, f1 in ((PRORIZ[0] - 3.5, PRORIZ[0]), (PRORIZ[1], PRORIZ[1] + 3.5)):
        o_h.append(nakladka(SH, "шп%d" % f0, lambda s, u, f0=f0, f1=f1:
                            (tp(f0 + (f1 - f0) * u), ((PRORIZ[2] + 3) * (2 * s - 1)) / 360 % 1.0),
                            30, 2, dod=0.0006, tovsh=0.0025))
    o_h.append(zaklepky(SH, "шз", [(tp(21), (zn * 66) / 360 % 1.0) for zn in (-1, 1)] +
                        [(tp(3), (zn * 66) / 360 % 1.0) for zn in (-1, 1)], r=0.0055))

    nazvy = {"тіло": "Одяг-тіло-важка-оздоба", "рукавиці": "Одяг-рукавиці-важка-оздоба",
             "взуття": "Одяг-взуття-важка-оздоба", "голова": "Одяг-голова-важка-оздоба"}
    for sl, chastyny in ozdoba.items():
        if chastyny:
            rechi.append(z_iednaty(nazvy[sl], chastyny))

    for o in rechi:
        for pl in o.data.polygons:
            pl.use_smooth = True
        o.data.materials.clear()
    for o in rechi:
        if os.environ.get("BEZ_AO") or o.name.endswith("-оздоба"):
            continue
        zapekty_ao(o, 1024 if "підклад" in o.name or "нагрудник" in o.name else 512)
    return rechi


SPOSOBY = {"А": sposib_a, "Б": sposib_b, "Б-заготовка": sposib_b_zahotovka, "В": sposib_v,
           "важка": sposib_vazhka}


# ── Тіло під річчю ───────────────────────────────────────────────────────
def pid_odiahom(rechi, dalno):
    dg = bpy.context.evaluated_depsgraph_get()
    dereva = []
    for o in rechi:
        k = next((v for n, v in KANAL.items() if o.name == "Одяг-" + n), None)
        if k is None:
            k = next((v for n, v in KANAL_DETALI.items() if o.name.endswith("-" + n)), None)
        if k is None:
            continue
        ev = o.evaluated_get(dg)
        m = ev.to_mesh()
        mw = o.matrix_world
        verts = [mw @ v.co for v in m.vertices]
        polys = [tuple(p.vertices) for p in m.polygons]
        ev.to_mesh_clear()
        dereva.append((k, BVHTree.FromPolygons(verts, polys)))
    me = h.data
    nv = len(me.vertices)
    pid = np.zeros((nv, 4), bool)
    mw = h.matrix_world
    for v in me.vertices:
        p = mw @ v.co
        n = (mw.to_3x3() @ v.normal).normalized()
        for k, t in dereva:
            hit = t.ray_cast(p + n * 0.0005, n, dalno)
            if hit[0] is not None:
                pid[v.index, k] = True
            # річ упритул (одяг MPFB облягає, місцями й нижче шкіри) —
            # промінь по нормалі її не бачить, а шкіра на русі пролазить
            elif t.find_nearest(p, 0.012)[0] is not None:
                pid[v.index, k] = True
    # м'який край: крайнє кільце лишається видимим (під краєм речі не дірка)
    sus = [[] for _ in range(nv)]
    for e in me.edges:
        a, b = e.vertices
        sus[a].append(b)
        sus[b].append(a)
    zviz = pid.copy()
    for i in range(nv):
        for j in sus[i]:
            zviz[i] &= pid[j]
    a = me.color_attributes.get("під_одяг") or me.color_attributes.new(
        "під_одяг", "FLOAT_COLOR", "POINT")
    a.data.foreach_set("color", zviz.astype(np.float32).ravel())
    print("[одяг] під річчю вершин тіла:", {n: int(zviz[:, k].sum()) for n, k in KANAL.items()})


rechi = SPOSOBY[SPOSIB]()
if SPOSIB == "Б-заготовка":
    bpy.ops.wm.save_as_mainfile(filepath=VYKHID)
    print("[одяг] заготовка →", VYKHID, [o.name for o in rechi])
    sys.exit(0)
for o in rechi:
    print("[одяг] %s: вершин %d, модифікатори %s" % (
        o.name, len(o.data.vertices), [m.type for m in o.modifiers]))
pid_odiahom(rechi, {"А": 0.03, "Б": 0.05, "В": 0.09, "важка": 0.09}[SPOSIB])
bpy.ops.wm.save_as_mainfile(filepath=VYKHID)
print("[одяг] →", VYKHID)
