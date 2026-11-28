# Каркас аркуша-референсу НЕгуманоїда (27.11.2026, слово замовника «давай почнемо робити по
# типам»): модель-зразок типу (вовк-сіромаха, рись, скорпіон… — те, що копіюють види П-248)
# у природній стійці (поза спокою скелета, без анімації), однаково сіра, рівне світло світу
# без сонць і тіней, з чотирьох боків (0° спереду, 45°, 90° збоку, 180° ззаду) і згори.
# Орто-камера, однаковий масштаб і середина для всіх бічних кадрів (як karkas_at.py).
# Рендер — Cycles на процесорі (відеокарта не потрібна).
#   blender -b -P tools/blender/karkas_zvir.py -- <модель.glb|.fbx> <тека> [--розмір 1024]
#        [--поворот <градуси>]   (якщо модель після імпорту дивиться не на камеру 0°)
# Вихід: <тека>/{0,45,90,180,згори}.png і розміри.txt (довжина, ширина, висота, м).
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

A = sys.argv[sys.argv.index("--") + 1:]
SHLIAKH, TEKA = A[0], A[1]
R = int(A[A.index("--розмір") + 1]) if "--розмір" in A else 1024
POVOROT = float(A[A.index("--поворот") + 1]) if "--поворот" in A else 0.0
os.makedirs(TEKA, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
if SHLIAKH.lower().endswith(".fbx"):
    bpy.ops.import_scene.fbx(filepath=os.path.abspath(SHLIAKH))
else:
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(SHLIAKH))
sc = bpy.context.scene
for o in list(bpy.data.objects):
    if o.animation_data:
        o.animation_data_clear()
    if o.type == "ARMATURE":
        for pb in o.pose.bones:
            pb.matrix_basis.identity()
    if o.type in ("LIGHT", "CAMERA") or (o.type == "MESH" and o.name.startswith("Icosphere")):
        bpy.data.objects.remove(o)   # Icosphere — службова куля-мітка в моделях гри

# однаково сірий матеріал — лише зразок форми й пози, без кольорів зразка
sire = bpy.data.materials.new("каркас-сірий")
sire.use_nodes = True
bsdf = sire.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.55, 0.55, 0.57, 1)
bsdf.inputs["Roughness"].default_value = 0.8
for o in bpy.data.objects:
    if o.type == "MESH":
        o.data.materials.clear()
        o.data.materials.append(sire)

# поворот усієї моделі навколо вертикалі (щоб морда дивилась на камеру 0°, тобто в −Y)
koreni = [o for o in bpy.data.objects if o.parent is None]
for o in koreni:
    o.matrix_world = Matrix.Rotation(math.radians(POVOROT), 4, "Z") @ o.matrix_world
bpy.context.view_layer.update()

dg = bpy.context.evaluated_depsgraph_get()
P = []
for o in bpy.data.objects:
    if o.type == "MESH" and not o.hide_render:
        ev = o.evaluated_get(dg)
        P += [ev.matrix_world @ v.co for v in ev.to_mesh().vertices]
        ev.to_mesh_clear()
xs, ys, zs = [p.x for p in P], [p.y for p in P], [p.z for p in P]
zmin, zmax = min(zs), max(zs)
H = zmax - zmin
cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
dx, dy = max(xs) - min(xs), max(ys) - min(ys)
# найбільший горизонтальний розмах за будь-якого кута — діагональ рамки
shyr = math.hypot(dx, dy)

cam = bpy.data.objects.new("tmp-кадр", bpy.data.cameras.new("tmp-кадр"))
sc.collection.objects.link(cam)
cam.data.type = "ORTHO"
cam.data.clip_end = 1000
sc.camera = cam
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = 48
sc.cycles.use_denoising = True
sc.render.resolution_x = sc.render.resolution_y = R
sc.render.film_transparent = False
sc.view_settings.view_transform = "Standard"
sc.world = bpy.data.worlds.new("світ")
sc.world.use_nodes = True
bg = sc.world.node_tree.nodes.get("Background")
bg.inputs[0].default_value = (0.78, 0.78, 0.8, 1)
bg.inputs[1].default_value = 1.0

masshtab = max(H, shyr) * 1.12
cam.data.ortho_scale = masshtab
vidstan = max(H, shyr) * 4 + 5
for kut in (0, 45, 90, 180):
    a = math.radians(kut)
    d = Vector((math.sin(a), -math.cos(a), 0))
    cam.location = Vector((cx, cy, zmin + H / 2)) + d * vidstan
    cam.rotation_euler = (math.pi / 2, 0, a)
    sc.render.filepath = os.path.join(TEKA, "%d.png" % kut)
    bpy.ops.render.render(write_still=True)
# згори: голова догори кадру
cam.location = Vector((cx, cy, zmax + vidstan))
cam.rotation_euler = (0, 0, math.pi)
sc.render.filepath = os.path.join(TEKA, "згори.png")
bpy.ops.render.render(write_still=True)
open(os.path.join(TEKA, "розміри.txt"), "w").write(
    "довжина(Y) %.4f ширина(X) %.4f висота %.4f масштаб %.4f\n" % (dy, dx, H, masshtab))
print("[каркас-звір] %.3f × %.3f × %.3f м → %s" % (dy, dx, H, TEKA))
