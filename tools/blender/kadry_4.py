# Чотири кадри моделі (спереду, ззаду, зліва, справа) в однаковому кадрі (24.11.2026, П-288,
# спосіб Б порівняння: 3D з кількох видів, Hunyuan3D-2mv). Ортографічна камера, той самий
# масштаб і середина для всіх боків, маківка на 0,035 висоти кадру, підошви на 0,965 —
# як у референсах «з нуля», тож висоту зони рахує та сама формула z = зріст·(0,965 − y)/0,93.
#   blender -b -P tools/blender/kadry_4.py -- <модель.glb|.blend> <тека> [--розмір 1024]
import math
import os
import sys

import bpy
from mathutils import Vector

A = sys.argv[sys.argv.index("--") + 1:]
SHLIAKH, TEKA = A[0], A[1]
R = int(A[A.index("--розмір") + 1]) if "--розмір" in A else 1024
os.makedirs(TEKA, exist_ok=True)
if SHLIAKH.endswith(".glb"):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(SHLIAKH))
else:
    bpy.ops.wm.open_mainfile(filepath=os.path.abspath(SHLIAKH))
sc = bpy.context.scene
for o in bpy.data.objects:
    if o.type == "MESH" and o.name.startswith(("Волосся", "Борода", "Одяг-", "Брови-", "Вії-")):
        o.hide_render = True
    if o.type == "LIGHT":
        o.hide_render = True
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
P = []
for o in bpy.data.objects:
    if o.type == "MESH" and not o.hide_render:
        ev = o.evaluated_get(dg)
        P += [ev.matrix_world @ v.co for v in ev.data.vertices]
zmin, zmax = min(p.z for p in P), max(p.z for p in P)
cx = (min(p.x for p in P) + max(p.x for p in P)) / 2
cy = (min(p.y for p in P) + max(p.y for p in P)) / 2
H = zmax - zmin
cam = bpy.data.objects.new("tmp-кадр", bpy.data.cameras.new("tmp-кадр"))
sc.collection.objects.link(cam)
cam.data.type = "ORTHO"
cam.data.ortho_scale = H / 0.93
sc.camera = cam
sc.render.engine = "BLENDER_EEVEE"
sc.render.resolution_x = sc.render.resolution_y = R
sc.render.film_transparent = False
if sc.world is None:
    sc.world = bpy.data.worlds.new("світ")
sc.world.use_nodes = True
bg = sc.world.node_tree.nodes.get("Background")
bg.inputs[0].default_value = (0.78, 0.78, 0.8, 1)
bg.inputs[1].default_value = 1.0
lt = bpy.data.objects.new("tmp-світло", bpy.data.lights.new("tmp-світло", "SUN"))
lt.data.energy = 2.5
lt.data.angle = 0.6
sc.collection.objects.link(lt)
# спереду — з −Y (модель дивиться на −Y Blender)
for nazva, kut in (("спереду", 0), ("ззаду", 180), ("зліва", 90), ("справа", -90)):
    a = math.radians(kut)
    d = Vector((math.sin(a), -math.cos(a), 0))
    cam.location = Vector((cx, cy, zmin + H / 2)) + d * 6
    cam.rotation_euler = (math.pi / 2, 0, a)
    lt.rotation_euler = (0.9, 0, a + 0.3)
    sc.render.filepath = os.path.join(TEKA, nazva + ".png")
    bpy.ops.render.render(write_still=True)
print("[кадри] зріст %.3f м, низ %.3f → %s" % (H, zmin, TEKA))
