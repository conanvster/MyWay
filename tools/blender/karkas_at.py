# Каркас для аркуша-референсу монстра (25.11.2026): модель-шаблон у А- і Т-позі з чотирьох
# боків (0°, 45°, 90°, 180°) під рівним світлом — лише світло світу, без сонць і тіней.
# Ортографічна камера, той самий масштаб і середина для всіх кадрів, маківка на 0,035 висоти
# кадру, підошви на 0,965 (як kadry_4.py). Кадри — перша картинка для Qwen-Edit.
#   blender -b -P tools/blender/karkas_at.py -- <модель.glb|.blend> <тека> [--розмір 1024] [--лише-А]
# Вихід: <тека>/<поза>-<кут>.png (А-0, А-45, А-90, А-180, Т-0 …) і зріст.txt.
import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

A = sys.argv[sys.argv.index("--") + 1:]
SHLIAKH, TEKA = A[0], A[1]
R = int(A[A.index("--розмір") + 1]) if "--розмір" in A else 1024
os.makedirs(TEKA, exist_ok=True)
if SHLIAKH.endswith(".blend"):
    bpy.ops.wm.open_mainfile(filepath=os.path.abspath(SHLIAKH))
else:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(SHLIAKH))
sc = bpy.context.scene
for o in bpy.data.objects:
    if o.type == "LIGHT" or (o.type == "MESH" and o.name.startswith("Icosphere")):
        o.hide_render = True
rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
rig.animation_data_clear()
for o in bpy.data.objects:
    if o.animation_data:
        o.animation_data_clear()
# кути руки від вертикалі донизу: А — 45° (або поза скульптури, якщо є), Т — 90°
POZY = {"А": 45, "Т": 90}
if "поза_основи" in rig:
    POZA_SKULPTU = {k: [list(r) for r in v] for k, v in json.loads(rig["поза_основи"]).items()}
    POZY["А"] = "скульпт"


# ланцюжки руки: скелет гри (upperarm_l → lowerarm_l) або автоскелет шаблону (arm.L → arm.L.2)
LANTSIUHY = [("upperarm_l", "lowerarm_l"), ("upperarm_r", "lowerarm_r"),
             ("arm.L", "arm.L.2"), ("arm.R", "arm.R.2")]


def vyrivniaty(pb, tsil):
    mw = rig.matrix_world
    dir_svit = ((mw @ pb.tail) - (mw @ pb.head)).normalized()
    q = dir_svit.rotation_difference(tsil)
    m = mw.to_3x3() @ pb.matrix.to_3x3()
    d = (m.inverted() @ q.to_matrix() @ m).to_quaternion()
    pb.rotation_mode = "QUATERNION"
    pb.rotation_quaternion = pb.rotation_quaternion @ d
    bpy.context.view_layer.update()


def postav(kut):
    for pb in rig.pose.bones:
        pb.matrix_basis.identity()
    bpy.context.view_layer.update()
    if kut == "скульпт":
        # А-поза = поза скульптури тіло-4 (`art/сет-еталон-людина-2026-11-21/тіло-4`, руки
        # опущені трохи вбік) — слово замовника 25.11.2026; записана `rig_sitky.py`
        for pb in rig.pose.bones:
            pb.matrix_basis = Matrix(POZA_SKULPTU.get(pb.name, Matrix.Identity(4)))
        bpy.context.view_layer.update()
        return
    seredyna = rig.matrix_world.translation.x
    for plече, likot in LANTSIUHY:
        pb = rig.pose.bones.get(plече)
        if pb is None:
            continue
        # бік — за фактичним положенням кисті, а не за назвою
        storona = 1 if (rig.matrix_world @ pb.tail).x > seredyna else -1
        a = math.radians(kut)
        tsil = Vector((storona * math.sin(a), 0, -math.cos(a)))
        vyrivniaty(pb, tsil)
        p2 = rig.pose.bones.get(likot)
        if p2:
            vyrivniaty(p2, tsil)  # рука пряма в лікті


def mezhi():
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    P = []
    for o in bpy.data.objects:
        if o.type == "MESH" and not o.hide_render:
            ev = o.evaluated_get(dg)
            P += [ev.matrix_world @ v.co for v in ev.to_mesh().vertices]
            ev.to_mesh_clear()
    return P


cam = bpy.data.objects.new("tmp-кадр", bpy.data.cameras.new("tmp-кадр"))
sc.collection.objects.link(cam)
cam.data.type = "ORTHO"
sc.camera = cam
sc.render.engine = "BLENDER_EEVEE"
sc.render.resolution_x = sc.render.resolution_y = R
sc.render.film_transparent = False
sc.view_settings.view_transform = "Standard"
if sc.world is None:
    sc.world = bpy.data.worlds.new("світ")
sc.world.use_nodes = True
bg = sc.world.node_tree.nodes.get("Background")
bg.inputs[0].default_value = (0.78, 0.78, 0.8, 1)
bg.inputs[1].default_value = 1.0   # сіре тло, як у тіло-4

# масштаб кадру — за Т-позою (найширша), щоб А і Т були одного масштабу
postav(POZY["Т"])
P = mezhi()
zmin, zmax = min(p.z for p in P), max(p.z for p in P)
H = zmax - zmin
shyr = max(max(abs(p.x) for p in P), max(abs(p.y) for p in P)) * 2
cx = (min(p.x for p in P) + max(p.x for p in P)) / 2
cy = (min(p.y for p in P) + max(p.y for p in P)) / 2
cam.data.ortho_scale = max(H / 0.93, shyr * 1.08)
for poza, kut_ruky in POZY.items():
    if "--лише-А" in A and poza != "А":
        continue   # Т у каркасі аркуша — фото, не рендер (_аркуш-каркас/ЗВІДКИ.txt)
    postav(kut_ruky)
    for kut in (0, 45, 90, 180):
        a = math.radians(kut)
        d = Vector((math.sin(a), -math.cos(a), 0))
        cam.location = Vector((cx, cy, zmin + H / 2)) + d * 8
        cam.rotation_euler = (math.pi / 2, 0, a)
        sc.render.filepath = os.path.join(TEKA, "%s-%d.png" % (poza, kut))
        bpy.ops.render.render(write_still=True)
open(os.path.join(TEKA, "зріст.txt"), "w").write("%.4f %.4f %.4f\n" % (H, zmin, cam.data.ortho_scale))
print("[каркас] зріст %.3f м → %s" % (H, TEKA))
