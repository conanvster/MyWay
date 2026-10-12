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
        <основа.blend> <вихід.glb> <зі_шкірою.fbx> <рух.fbx>...

Назва дії — друге поле імені файлу (`elf808v2__02_khoda__walking.fbx` →
`02_khoda`) і переклад у RUKHY.
"""
import os
import sys

import bpy
from mathutils import Vector

a = sys.argv[sys.argv.index("--") + 1:]
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
