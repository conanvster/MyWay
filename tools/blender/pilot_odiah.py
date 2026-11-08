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
KANAL_DETALI = {"сорочка": 0, "штани": 1, "чоботи": 2, "наручі": 3}
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
    """Дерево променів по шкірі, де головна кістка — з `kosti`."""
    dom = dominanta(h)
    mw = h.matrix_world
    verts = [mw @ v.co for v in h.data.vertices]
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


def obolonka(imia, promin, nt, nth, kosti, zazor, povne=False, zhlad=8,
             tovsh=0.004, valyk=0.003, vahy=None):
    """Тверда оболонка: сітка (t ∈ 0…1) × (кут θ); `promin(t, θ)` → (початок,
    напрям) усередині тіла; промінь влучає в шкіру області `kosti`, радіус —
    обгортка (згладжена, ніде не нижче шкіри) + `zazor(t, θ)`. Товщина
    `tovsh`, край — валик назовні. `vahy(p)` → {кістка: вага}."""
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
            hit = bvh.ray_cast(o, d, 0.5)
            if hit[0] is not None:
                r[i, j] = hit[3]
    # промахи — середнє ряду (або 0: верхівка шолома над тім'ям)
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
    co = org + dr * r[..., None]
    me = bpy.data.meshes.new(imia)
    faces = []
    nj = nth if povne else nth - 1
    for i in range(nt - 1):
        for j in range(nj):
            j2 = (j + 1) % nth
            faces.append((i * nth + j, i * nth + j2, (i + 1) * nth + j2, (i + 1) * nth + j))
    me.from_pydata(co.reshape(-1, 3).tolist(), [], faces)
    o = bpy.data.objects.new(imia, me)
    bpy.context.scene.collection.objects.link(o)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    # нормалі назовні — від осі
    c0 = Vector(org.reshape(-1, 3).mean(0))
    if sum((p.center - c0).dot(p.normal) for p in me.polygons) < 0:
        for p in me.polygons:
            p.flip()
    sd = o.modifiers.new("товщина", "SOLIDIFY")
    sd.thickness = tovsh
    sd.offset = 1.0
    sd.use_even_offset = True
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


def vzdovzh(n, bik, t0, t1, th0, th1):
    """Промінь навколо кістки `n`: t — від t0 до t1 її довжини, θ (градуси;
    0 — уперед, 90 — назовні)."""
    a, b = kistka(n)
    u, v, w = ramka(b - a, bik)

    def f(t, th):
        tt = t0 + (t1 - t0) * t
        k = np.radians(th0 + (th1 - th0) * th)
        return a + (b - a) * tt, v * np.cos(k) + w * np.sin(k)
    return f


def sposib_vazhka():
    TULUB = {"pelvis", "spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r", "neck_01"}
    rechi = []
    # ── підклад: стьобанка до стегон з рукавами до ліктя, широкі штани ──
    sorochka = shmatok_tila(
        "Одяг-тіло-важка-підклад-сорочка",
        TULUB | {"upperarm_l", "upperarm_r"},
        lambda p: p.z >= 0.88 and (p.z <= 1.45 or abs(p.x) > 0.10)
        and not (abs(p.x) > 0.27 and p.z < 1.26),
        lambda p: 0.017, zhladyty=20)
    vazhy_vid_tila(sorochka, rozmyty=1)

    def shyr(p):        # штани: вузько в поясі, найширше під коліном, заправлені
        z = p.z
        if z > 0.65:
            return 0.014 + 0.016 * (0.92 - min(z, 0.92)) / 0.27
        if z > 0.40:
            return 0.030
        return 0.014 + 0.016 * max(0.0, (z - 0.30) / 0.10)
    shtany = shmatok_tila("Одяг-тіло-важка-підклад-штани",
                          {"pelvis", "spine_01", "thigh_l", "thigh_r", "calf_l", "calf_r"},
                          lambda p: 0.26 <= p.z <= 0.99, shyr, zhladyty=3)
    vazhy_vid_tila(shtany, rozmyty=1)
    rechi += [sorochka, shtany]

    # ── нагрудник: від пояса до ключиць, по боках — пройми для рук ──
    vis = Vector((0, -0.01, 0))

    def tulub(zb, zt, th0=0.0, th1=360.0, proima=0.0):
        def f(t, th):
            k = np.radians(th0 + (th1 - th0) * th)
            verkh = zt - proima * np.sin(k) ** 2       # нижче на боках
            return Vector((vis.x, vis.y, zb + (verkh - zb) * t)), \
                Vector((np.sin(k), -np.cos(k), 0))
        return f
    nahrudnyk = obolonka("Одяг-тіло-важка-нагрудник", tulub(1.13, 1.40, proima=0.12), 14, 64,
                         TULUB, lambda t, th: 0.026, povne=True, zhlad=14, tovsh=0.005,
                         valyk=0.004, vahy=lambda p: {"spine_03": 1.0} if p.z > 1.20 else
                         {"spine_03": 0.6, "spine_02": 0.4})
    rechi.append(nahrudnyk)
    # пластини на животі: три смуги внахльост, кожна трохи ширша за верхню
    plast = []
    for i, (zb, zt, kist) in enumerate([(1.075, 1.140, "spine_02"), (1.025, 1.090, "spine_01"),
                                         (0.975, 1.040, "spine_01")]):
        plast.append(obolonka("смуга%d" % i, tulub(zb, zt), 5, 64, TULUB,
                              (lambda d: lambda t, th: d)(0.030 + 0.005 * i), povne=True,
                              zhlad=14, tovsh=0.004, valyk=0.003, vahy=tverda(kist)))
    # пояс під пластинами
    plast.append(obolonka("пояс", tulub(0.92, 0.985), 5, 64, TULUB, lambda t, th: 0.040,
                          povne=True, zhlad=14, tovsh=0.006, valyk=0.002,
                          vahy=tverda("pelvis")))
    rechi.append(z_iednaty("Одяг-тіло-важка-пластини", plast))

    # ── наплічники: по три пластини на плече, верхня накриває плече ──
    napl = []
    for bik in ("l", "r"):
        for i, (t0, t1, zz) in enumerate([(-0.18, 0.12, 0.030), (0.06, 0.30, 0.040),
                                          (0.24, 0.48, 0.050)]):
            napl.append(obolonka(
                "напл%s%d" % (bik, i), vzdovzh("upperarm_" + bik, bik, t0, t1, -35, 215), 6, 28,
                {"upperarm_" + bik, "clavicle_" + bik, "spine_03"},
                (lambda zz: lambda t, th: zz)(zz), zhlad=10, tovsh=0.005, valyk=0.004,
                vahy=tverda("upperarm_" + bik)))
    rechi.append(z_iednaty("Одяг-тіло-важка-наплічники", napl))

    # ── набедреники: спереду й збоку на кожному стегні, звисають з пояса ──
    nab = []
    for bik in ("l", "r"):
        for i, (th0, th1) in enumerate([(-70, 8), (18, 100)]):
            def vh(p, bik=bik):
                a, b = kistka("thigh_" + bik)
                t = float(np.clip((a.z - p.z) / (a.z - b.z) / 0.4, 0, 1))
                return {"pelvis": 1 - 0.6 * t, "thigh_" + bik: 0.6 * t}
            nab.append(obolonka(
                "наб%s%d" % (bik, i), vzdovzh("thigh_" + bik, bik, 0.0, 0.36, th0, th1), 7, 14,
                {"thigh_" + bik, "pelvis"}, lambda t, th: 0.040 + 0.025 * t, zhlad=8,
                tovsh=0.004, valyk=0.003, vahy=vh))
    rechi.append(z_iednaty("Одяг-тіло-важка-набедреники", nab))

    # ── наручі: передпліччя від ліктя до зап'ястя, ширше до зап'ястя ──
    nar = []
    for bik in ("l", "r"):
        nar.append(obolonka("нар" + bik, vzdovzh("lowerarm_" + bik, bik, 0.30, 0.95, 0, 360), 8, 32,
                            {"lowerarm_" + bik}, lambda t, th: 0.010 + 0.010 * t, povne=True,
                            zhlad=8, tovsh=0.004, valyk=0.003, vahy=tverda("lowerarm_" + bik)))
    rechi.append(z_iednaty("Одяг-рукавиці-важка-наручі", nar))

    # ── чоботи: стопа й гомілка до 28 см, шире вгорі ──
    import make_races as mr
    choboty = shmatok_tila("Одяг-взуття-важка-чоботи",
                           {"calf_l", "calf_r", "foot_l", "foot_r", "ball_l", "ball_r"},
                           lambda p: 0.09 <= p.z <= 0.28,
                           lambda p: 0.012 + 0.012 * float(np.clip((p.z - 0.12) / 0.16, 0, 1)))
    tmp = tilo_bez_kliuchiv()
    for g in list(tmp.vertex_groups):
        if g.name not in KOSTI:
            tmp.vertex_groups.remove(g)
    mr.FOOT_TOP = 0.10
    stopy = mr._boot_feet(tmp, 0.012)
    bpy.data.objects.remove(tmp)
    choboty = z_iednaty("Одяг-взуття-важка-чоботи", [choboty] + list(stopy))
    vazhy_vid_tila(choboty, rozmyty=1)
    rechi.append(choboty)
    # поножі й наколінники
    pon = []
    for bik in ("l", "r"):
        pon.append(obolonka("пон" + bik, vzdovzh("calf_" + bik, bik, 0.08, 0.72, -115, 115), 10, 28,
                            {"calf_" + bik}, lambda t, th: 0.044 - 0.016 * t, zhlad=10,
                            tovsh=0.005, valyk=0.004, vahy=tverda("calf_" + bik)))
        pon.append(obolonka("кол" + bik, vzdovzh("calf_" + bik, bik, -0.12, 0.10, -80, 80), 6, 16,
                            {"calf_" + bik, "thigh_" + bik}, lambda t, th: 0.052, zhlad=8,
                            tovsh=0.005, valyk=0.004, vahy=tverda("calf_" + bik)))
    rechi.append(z_iednaty("Одяг-взуття-важка-поножі", pon))

    # ── шолом: купол, нащічники й захист потилиці, обличчя відкрите ──
    C = Vector((0, -0.025, 1.625))

    def sfera(t, th):
        k = np.radians(th * 360 - 180)                  # 0 — потилиця, ±180 — обличчя
        lytse = abs(abs(np.degrees(k)) - 180) < 52
        nyz = 14 if lytse else -38
        f = np.radians(nyz + (86 - nyz) * t)
        hor = Vector((np.sin(k), np.cos(k), 0))         # k=0 → +Y (потилиця)
        return C, hor * np.cos(f) + Vector((0, 0, 1)) * np.sin(f)
    sholom = obolonka("Одяг-голова-важка-шолом", sfera, 14, 56, {"head", "neck_01"},
                      lambda t, th: 0.030, povne=True, zhlad=10, tovsh=0.005, valyk=0.004,
                      vahy=tverda("head"))
    # гребінь від потилиці через тім'я до чола й наносник
    def hreb(t, th):
        a = np.radians(-30 + 218 * t)                   # 0 — потилиця, 90 — тім'я, 180 — чоло
        lat = np.radians(-7 + 14 * th)
        base = Vector((0, np.cos(a), np.sin(a)))
        return C, base * np.cos(lat) + Vector((1, 0, 0)) * np.sin(lat)
    hreben = obolonka("гребінь", hreb, 40, 5, {"head", "neck_01"},
                      lambda t, th: 0.036 + (0.008 if 0.1 < t < 0.75 else 0.0) * np.sin(np.pi * th),
                      zhlad=6, tovsh=0.005, valyk=0.002, vahy=tverda("head"))
    # бровка: обідок над чолом і довкола купола
    def obid(t, th):
        k = np.radians(th * 360 - 180)
        lytse = abs(abs(np.degrees(k)) - 180) < 52
        f = np.radians((14 if lytse else -38) + 6 * t)
        hor = Vector((np.sin(k), np.cos(k), 0))
        return C, hor * np.cos(f) + Vector((0, 0, 1)) * np.sin(f)
    obidok = obolonka("обідок", obid, 3, 56, {"head", "neck_01"}, lambda t, th: 0.040,
                      povne=True, zhlad=10, tovsh=0.006, valyk=0.0, vahy=tverda("head"))
    sholom = z_iednaty("Одяг-голова-важка-шолом", [sholom, hreben, obidok])
    rechi.append(sholom)

    for o in rechi:
        for pl in o.data.polygons:
            pl.use_smooth = True
        o.data.materials.clear()
    for o in rechi:
        if os.environ.get("BEZ_AO"):
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
