"""Ельфійка на скелеті Mixamo з вибраними рухами → .glb для гри (12.10.2026).

Слово замовника: «бачу, що на превʼю рухи з Mixamo виглядають краще наших
43 рухів, тож будуй ельфійку на 10 вибраних рухах». Скелет — авто-скелет
Mixamo (сітку `elf_osnova.py` завантажено в Mixamo), рухи — експорт
Mixamo на цьому ж персонажі (60 fps), тож перенос рухів не потрібен.

  1. `основа.blend` — наша сітка з текстурою 4096 (метри, ступні на нулі);
  2. FBX «зі шкірою» від Mixamo — скелет і ваги; Mixamo читає наш OBJ у
     сантиметрах, тож усе в ньому в 100 разів менше — масштаб за зростом;
  3. ваги — з сітки Mixamo на нашу (Data Transfer, найближча грань),
     сітки Mixamo геть; на нашій — модифікатор Armature;
  4. рухи — з решти FBX: дія переходить на основний скелет (ті самі
     кістки й поза спокою); у ході/бігу/стрибку — без зсуву вперед
     (позицію в грі веде сервер);
  5. експорт .glb з усіма діями.

    blender -b --factory-startup -P tools/blender/mixamo_zbirka.py -- \\
        <основа.blend> <вихід.glb> <зі_шкірою.fbx> <рух.fbx>... [--волосся]

`--зачіска <волосся.blend>` (з `mpfb_volossia.py`) — замість сканової пластини
зачіска MakeHuman на тих самих ланцюжках (ланцюжки від потилиці, 1,58 м).
`--волосся` — пластину волосся зі спини окремою сіткою на трьох ланцюжках
кісток `hair_{L,C,R}_{1..4}` під головою (для `SpringBoneSimulator3D`).

Назва дії — друге поле імені файлу (`elf808v2__02_khoda__walking.fbx` →
`02_khoda`) і переклад у RUKHY.
"""
import os
import sys

import bpy
from mathutils import Vector

a = sys.argv[sys.argv.index("--") + 1:]
VOLOSSIA = "--волосся" in a
a = [x for x in a if x != "--волосся"]
# `--зачіска` можна кілька разів (12.10.2026, вибір зачіски в грі): кожна —
# окрема сітка «Волосся-<стиль>» на тих самих пружних кістках; перша —
# видима за замовчуванням і задає кістки.
ZACHISKY = []
while "--зачіска" in a:
    i_ = a.index("--зачіска")
    ZACHISKY.append(a[i_ + 1])
    del a[i_:i_ + 2]
    VOLOSSIA = True
ZACHISKA = ZACHISKY[0] if ZACHISKY else None
# `--маски <png>` — маски рис обличчя (`avatar_build.py`) поруч із виходом
# як `<вихід>_маски.png` (колір очей, губ, шкіри, скальпу в грі).
MASKY = None
if "--маски" in a:
    i_ = a.index("--маски")
    MASKY = a[i_ + 1]
    del a[i_:i_ + 2]
OSNOVA, VYKHID, SHKIRA, RUKHY_F = a[0], a[1], a[2], a[3:]
RUKHY = {"01_spokii": "Idle", "02_khoda": "Walk", "03_bih": "Run",
         "04_strybok": "Jump", "05_udar_mechem": "Sword_Slash",
         "06_blok": "Block", "07_postril_z_luka": "Bow_Shot",
         "08_zaklynannia": "Cast", "09_otrymannia_udaru": "Hit",
         "10_smert": "Death"}
NA_MISCI = {"Walk", "Run", "Jump"}


def fcurves_of(action):
    """Криві дії і в старому API, і в шаруватому Blender 5
    (як `avatar_build.fcurves_of`)."""
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


def nazva(f):
    k = os.path.basename(f).split("__")[1]
    return RUKHY.get(k, k)


def viddilyty_volossia(tilo):
    """Пластина волосся зі спини — окремою сіткою (12.10.2026).

    Скан — подвійна оболонка ~5 мм. Промінь ззаду наперед крізь (x, z):
    з волоссям три пари стінок (волосся, спина, груди), без нього дві;
    волосся — перша пара до першого проміжку > 2,5 см. Колір не годиться:
    бліда шкіра ельфійки майже біла."""
    import collections
    import bmesh
    import numpy as np
    from mathutils.bvhtree import BVHTree
    me = tilo.data
    mw = tilo.matrix_world
    co = np.array([(mw @ v.co)[:] for v in me.vertices])
    nv = len(co)
    dg = bpy.context.evaluated_depsgraph_get()
    tree = BVHTree.FromObject(tilo, dg)   # у координатах об'єкта
    inv = mw.inverted()

    def shary(x, z):
        ys = []
        p = inv @ Vector((x, 2.0, z))
        d = (inv.to_3x3() @ Vector((0, -1, 0))).normalized()
        for _ in range(12):
            hit = tree.ray_cast(p, d, 6.0)
            if hit[0] is None:
                break
            ys.append((mw @ hit[0]).y)
            p = hit[0] + d * 0.0005
        return ys

    oblast = (co[:, 1] > 0.0) & (co[:, 2] > 0.98) & (co[:, 2] < 1.58) \
        & (np.abs(co[:, 0]) < 0.3)
    vybir = np.zeros(nv, bool)
    kesh = {}
    for i in np.where(oblast)[0]:
        kl = (round(co[i, 0], 3), round(co[i, 2], 3))
        if kl not in kesh:
            ys = shary(co[i, 0], co[i, 2])
            gr = None
            # 4: пластина (2 боки) + спина й груди (одна стінка після
            # `--одна-оболонка`); подвійна давала 6
            if len(ys) >= 4:
                for k in range(len(ys) - 1):
                    if ys[k] - ys[k + 1] > 0.025:
                        gr = (ys[k] + ys[k + 1]) / 2
                        break
            kesh[kl] = gr
        if kesh[kl] is not None and co[i, 1] > kesh[kl]:
            vybir[i] = True
    sus = [[] for _ in range(nv)]
    for e in me.edges:
        a_, b_ = e.vertices
        sus[a_].append(b_)
        sus[b_].append(a_)
    mitka = np.full(nv, -1)
    rozmir = []
    for s0 in np.where(vybir)[0]:
        if mitka[s0] >= 0:
            continue
        q = collections.deque([s0])
        mitka[s0] = len(rozmir)
        n = 0
        while q:
            i = q.popleft()
            n += 1
            for j in sus[i]:
                if vybir[j] and mitka[j] < 0:
                    mitka[j] = mitka[s0]
                    q.append(j)
        rozmir.append(n)
    vybir = np.isin(mitka, [k for k, n in enumerate(rozmir) if n >= 200])
    bm = bmesh.new()
    bm.from_mesh(me)
    for f in bm.faces:
        f.select = all(vybir[v.index] for v in f.verts)
    bm.to_mesh(me)
    bm.free()
    bpy.ops.object.select_all(action="DESELECT")
    tilo.select_set(True)
    bpy.context.view_layer.objects.active = tilo
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.separate(type="SELECTED")
    bpy.ops.object.mode_set(mode="OBJECT")
    vol = next(o for o in bpy.context.selected_objects if o is not tilo)
    vol.name = "Волосся"
    print("[волосся] вершин %d (з %d кандидатів), тіло %d"
          % (len(vol.data.vertices), int(oblast.sum()), len(tilo.data.vertices)))
    return vol


GEOM_KISTOK = {}


def kistky_volossia(arm, vol, verkh=None, svii_material=False):
    """Три ланцюжки по 4 кістки вздовж пластини (ліво, центр, право) під
    `mixamorig:Head`; ваги — плавно між ланцюжками й ланками; верхні 3 см
    — частково голова. Друга й далі зачіска — лише ваги на ті самі кістки."""
    import numpy as np
    co = np.array([(vol.matrix_world @ v.co)[:] for v in vol.data.vertices])
    LANKY = 4
    if GEOM_KISTOK:
        xs, zs, z_t, z_b = (GEOM_KISTOK[k_] for k_ in ("xs", "zs", "z_t", "z_b"))
        vazhi_volossia(vol, co, xs, zs, z_t, z_b, LANKY,
                       ["hair_%s_%d" % (c, k + 1) for c in "LCR" for k in range(LANKY)])
        return
    z_t, z_b = co[:, 2].max() - 0.01, co[:, 2].min() + 0.02
    if verkh is not None:          # зачіска з маківкою: ланцюжки від потилиці
        z_t = min(z_t, verkh)
    x_l, x_r = np.percentile(co[:, 0], 8), np.percentile(co[:, 0], 92)
    xs = [x_l * 0.6, 0.0, x_r * 0.6]
    zs = np.linspace(z_t, z_b, LANKY + 1)
    GEOM_KISTOK.update(xs=xs, zs=zs, z_t=z_t, z_b=z_b)

    def y_v(x, z):
        # лише пасма позаду (бокові пасма на грудях тягли ланцюжок уперед)
        m = (np.abs(co[:, 0] - x) < 0.04) & (np.abs(co[:, 2] - z) < 0.04) \
            & (co[:, 1] > 0.0)
        return float(np.median(co[m, 1])) if m.any() else float(np.median(co[:, 1]))

    inv = arm.matrix_world.inverted()
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.data.edit_bones
    holova = eb["mixamorig:Head"]
    imena = []
    for c, x in zip("LCR", xs):
        bat = holova
        for k in range(LANKY):
            b = eb.new("hair_%s_%d" % (c, k + 1))
            b.head = inv @ Vector((x, y_v(x, zs[k]), zs[k]))
            b.tail = inv @ Vector((x, y_v(x, zs[k + 1]), zs[k + 1]))
            b.parent = bat
            b.use_connect = k > 0
            bat = b
            imena.append(b.name)
    bpy.ops.object.mode_set(mode="OBJECT")
    vazhi_volossia(vol, co, xs, zs, z_t, z_b, LANKY, imena)
    if svii_material:
        print("[волосся] кістки:", ", ".join(imena), "; z %.2f…%.2f" % (z_b, z_t))
        return
    mat = bpy.data.materials.new("Волосся")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (0.86, 0.85, 0.82, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.55
    vol.data.materials.clear()
    vol.data.materials.append(mat)
    print("[волосся] кістки:", ", ".join(imena), "; z %.2f…%.2f" % (z_b, z_t))


def vazhi_volossia(vol, co, xs, zs, z_t, z_b, LANKY, imena):
    for g in list(vol.vertex_groups):
        vol.vertex_groups.remove(g)
    grupy = {n: vol.vertex_groups.new(name=n) for n in imena}
    gh = vol.vertex_groups.new(name="mixamorig:Head")
    for i, p in enumerate(co):
        x, z = p[0], p[2]
        # між ланцюжками
        if x <= xs[0]:
            ch = [(0, 1.0)]
        elif x >= xs[2]:
            ch = [(2, 1.0)]
        else:
            j = 0 if x < xs[1] else 1
            f = (x - xs[j]) / (xs[j + 1] - xs[j])
            ch = [(j, 1 - f), (j + 1, f)]
        t = min(max((z_t - z) / (z_t - z_b), 0.0), 0.999) * LANKY
        k = int(t)
        fk = t - k
        holova_w = 1.0 if z >= z_t else (
            max(0.0, 1.0 - (z_t - z) / 0.03) if z > z_t - 0.03 else 0.0)
        for c_i, wc in ch:
            c = "LCR"[c_i]
            w_tut = wc * (1 - holova_w)
            grupy["hair_%s_%d" % (c, k + 1)].add([i], w_tut * (1 - 0.5 * fk), "ADD")
            if k + 1 < LANKY:
                grupy["hair_%s_%d" % (c, k + 2)].add([i], w_tut * 0.5 * fk, "ADD")
        if holova_w > 0:
            gh.add([i], holova_w, "ADD")


def mezhi(obs):
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in obs:
        e = o.evaluated_get(dg)
        me = e.to_mesh()
        pts += [e.matrix_world @ v.co for v in me.vertices]
        e.to_mesh_clear()
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


bpy.ops.wm.open_mainfile(filepath=OSNOVA)
nashi = [o for o in bpy.context.scene.objects if o.type == "MESH"]
lo_n, hi_n = mezhi(nashi)

# 2. Скелет і ваги Mixamo.
pered_imp = set(bpy.data.objects)
bpy.ops.import_scene.fbx(filepath=SHKIRA)
# Різниця «до/після», не виділення: кулька-мітка з Mixamo («Icosphere»)
# лишалась невиділеною, не видалялась і ламала зріст у грі (12.10.2026).
nove = [o for o in bpy.data.objects if o not in pered_imp]
arm = next(o for o in nove if o.type == "ARMATURE")
mx_ms = [o for o in nove if o.type == "MESH"]
# Тіло — найбільша сітка; поруч можуть бути мітки перевірки орієнтації
# (пластина спереду, кулька біля лівого стегна) — у габарит їх не брати.
tilo_mx = max(mx_ms, key=lambda o: len(o.data.vertices))
# Заміри й вирівнювання — у позі спокою (T-поза), не в кадрі руху.
arm.data.pose_position = "REST"
bpy.context.view_layer.update()
lo_m, hi_m = mezhi([tilo_mx])
k = (hi_n.z - lo_n.z) / (hi_m.z - lo_m.z)
arm.scale = arm.scale * k
bpy.context.view_layer.update()
lo_m, hi_m = mezhi([tilo_mx])
zsuv = Vector(((lo_n.x + hi_n.x - lo_m.x - hi_m.x) / 2,
               (lo_n.y + hi_n.y - lo_m.y - hi_m.y) / 2, lo_n.z - lo_m.z))
arm.location = arm.location + zsuv
bpy.context.view_layer.update()
lo_m, hi_m = mezhi([tilo_mx])


def vidstan():
    """Середня відстань від вершин сітки Mixamo до нашої (вибірка)."""
    from mathutils.bvhtree import BVHTree
    dg = bpy.context.evaluated_depsgraph_get()
    nash = max(nashi, key=lambda o: len(o.data.vertices))
    tree = BVHTree.FromObject(nash.evaluated_get(dg), dg)
    inv = nash.matrix_world.inverted()
    m_ = tilo_mx
    e = m_.evaluated_get(dg)
    me = e.to_mesh()
    krok = max(1, len(me.vertices) // 3000)
    s, n = 0.0, 0
    for i in range(0, len(me.vertices), krok):
        hit = tree.find_nearest(inv @ (e.matrix_world @ me.vertices[i].co))
        if hit[0] is not None:
            s += hit[3]
            n += 1
    e.to_mesh_clear()
    return s / max(n, 1)


# Розворот (12.10.2026: «переплутали модель задом наперед»): OBJ для
# Mixamo могли віддати обличчям в інший бік — беремо положення, де сітки
# збігаються.
import math
d0 = vidstan()
tsentr = Vector(((lo_n.x + hi_n.x) / 2, (lo_n.y + hi_n.y) / 2, 0))
from mathutils import Matrix
pov = Matrix.Translation(tsentr) @ Matrix.Rotation(math.pi, 4, "Z") \
    @ Matrix.Translation(-tsentr)
arm.matrix_world = pov @ arm.matrix_world
bpy.context.view_layer.update()
d180 = vidstan()
if d180 >= d0:
    arm.matrix_world = pov.inverted() @ arm.matrix_world
    bpy.context.view_layer.update()
print("[mixamo] розбіжність сіток: як є %.4f м, повернуто %.4f м → %s"
      % (d0, d180, "повернуто" if d180 < d0 else "як є"))
lo_m, hi_m = mezhi([tilo_mx])
print("[mixamo] масштаб ×%.2f; габарит Mixamo %s…%s, наш %s…%s"
      % (k, tuple(round(v, 3) for v in lo_m), tuple(round(v, 3) for v in hi_m),
         tuple(round(v, 3) for v in lo_n), tuple(round(v, 3) for v in hi_n)))
bud = arm.animation_data.action if arm.animation_data else None

# 3. Ваги на наші сітки. Поза спокою (без дії), щоб форми збіглись.
if arm.animation_data:
    arm.animation_data.action = None
for b in arm.pose.bones:
    b.location = (0, 0, 0)
    b.rotation_quaternion = (1, 0, 0, 0)
    b.rotation_euler = (0, 0, 0)
    b.scale = (1, 1, 1)
bpy.context.view_layer.update()
dzherelo = tilo_mx
for o in nashi:
    # Форм-ключі (риси обличчя, `elf_rysy.py`) — на час переносу ваг геть:
    # модифікатор не застосовується до сітки з ключами. Вершини ті самі,
    # тож ключі вертаються як були.
    kliuchi = []
    if o.data.shape_keys:
        import numpy as _np
        for kb in o.data.shape_keys.key_blocks:
            c_ = _np.empty(len(o.data.vertices) * 3, dtype=_np.float32)
            kb.data.foreach_get("co", c_)
            kliuchi.append((kb.name, c_))
        o.shape_key_clear()
    for g in list(o.vertex_groups):
        o.vertex_groups.remove(g)
    for g in dzherelo.vertex_groups:
        o.vertex_groups.new(name=g.name)
    dt = o.modifiers.new("ваги", "DATA_TRANSFER")
    dt.object = dzherelo
    dt.use_vert_data = True
    dt.data_types_verts = {"VGROUP_WEIGHTS"}
    dt.vert_mapping = "POLYINTERP_NEAREST"
    dt.layers_vgroup_select_src = "ALL"
    dt.layers_vgroup_select_dst = "NAME"
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.datalayout_transfer(modifier=dt.name)
    bpy.ops.object.modifier_apply(modifier=dt.name)
    for imia_k, c_ in kliuchi:
        kb = o.shape_key_add(name=imia_k, from_mix=False)
        kb.data.foreach_set("co", c_)
    if kliuchi:
        print("[mixamo] %s: форм-ключів %d" % (o.name, len(kliuchi) - 1))
    mw = o.matrix_world.copy()
    o.parent = arm
    o.matrix_parent_inverse = arm.matrix_world.inverted()
    o.matrix_world = mw
    am = o.modifiers.new("Armature", "ARMATURE")
    am.object = arm
    porozhni = sum(1 for v in o.data.vertices if not v.groups)
    print("[mixamo] %s: вершин %d, без ваги %d" % (o.name, len(o.data.vertices),
                                                    porozhni))
for o in mx_ms:
    bpy.data.objects.remove(o)
if VOLOSSIA:
    tilo_n = max(nashi, key=lambda o: len(o.data.vertices))
    vol = viddilyty_volossia(tilo_n)
    if ZACHISKY:
        # сканова пластина геть — на голову зачіски (`volossia_pasma.py`)
        bpy.data.objects.remove(vol)
        for n_, shliakh in enumerate(ZACHISKY):
            with bpy.data.libraries.load(shliakh) as (src_, dst_):
                dst_.objects = [n for n in src_.objects if n.startswith("Волосся")]
            for vol in dst_.objects:
                bpy.context.scene.collection.objects.link(vol)
                mw = vol.matrix_world.copy()
                vol.parent = arm
                vol.matrix_parent_inverse = arm.matrix_world.inverted()
                vol.matrix_world = mw
                am = vol.modifiers.new("Armature", "ARMATURE")
                am.object = arm
                nashi.append(vol)
                kistky_volossia(arm, vol, verkh=1.58, svii_material=True)
                print("[волосся] зачіска %s: вершин %d" % (vol.name, len(vol.data.vertices)))
    else:
        nashi.append(vol)
        kistky_volossia(arm, vol)
arm.data.pose_position = "POSE"

# 4. Дії.
dii = []
if bud:
    bud.name = nazva(SHKIRA)
    dii.append(bud)
for f in RUKHY_F:
    pered = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=f)
    novi = [o for o in bpy.data.objects if o not in pered]
    a2 = next(o for o in novi if o.type == "ARMATURE")
    d = a2.animation_data.action
    d.name = nazva(f)
    dii.append(d)
    for o in novi:
        bpy.data.objects.remove(o)

# Без зсуву вперед: у кістки Hips канал положення, що найбільше
# «пливе» від першого кадру до останнього, стає сталим.
for d in dii:
    d.use_fake_user = True
    if d.name not in NA_MISCI:
        continue
    fcs = [fc for fc in fcurves_of(d)
           if fc.data_path == 'pose.bones["mixamorig:Hips"].location']
    for fc in fcs:
        ks = fc.keyframe_points
        dryf = abs(ks[-1].co.y - ks[0].co.y)
        roz = max(k_.co.y for k_ in ks) - min(k_.co.y for k_ in ks)
        if roz > 0 and dryf > 0.5 * roz:
            v0 = ks[0].co.y
            for k_ in ks:
                k_.co.y = v0
                k_.handle_left.y = k_.handle_right.y = v0
            print("[mixamo] %s: Hips[%d] на місці (дрейф %.1f)"
                  % (d.name, fc.array_index, dryf))

# Зайве геть: лишаються наш скелет і наші сітки.
for o in list(bpy.data.objects):
    if o is not arm and o not in nashi:
        print("[mixamo] прибрано зайве:", o.name)
        bpy.data.objects.remove(o)

# Поворот (FBX: X +90°) і масштаб — у сам скелет: інакше в .glb вузол
# Armature повернутий, і `SkinnedModel._fit` міряв «зріст» по товщині тіла
# (0,29 м) — модель у грі роздувалась у 6 разів (12.10.2026).
arm.animation_data_create()
arm.animation_data.action = None
bpy.ops.object.select_all(action="DESELECT")
arm.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
print("[mixamo] скелет: поворот і масштаб застосовано", tuple(arm.rotation_euler),
      tuple(arm.scale))

# 5. Кожна дія — смугою NLA, щоб експорт узяв усі.
arm.animation_data_create()
arm.animation_data.action = None
for d in dii:
    tr = arm.animation_data.nla_tracks.new()
    tr.name = d.name
    tr.strips.new(d.name, int(d.frame_range[0]), d)
print("[mixamo] дії:", [d.name for d in dii])
os.makedirs(os.path.dirname(os.path.abspath(VYKHID)), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=VYKHID, export_format="GLB",
                          export_animations=True,
                          export_animation_mode="NLA_TRACKS",
                          export_skins=True, export_yup=True)
print("[mixamo] →", VYKHID)
if MASKY:
    import shutil
    kudy_m = os.path.splitext(os.path.abspath(VYKHID))[0] + "_маски.png"
    shutil.copy(MASKY, kudy_m)
    print("[mixamo] маски →", kudy_m)
