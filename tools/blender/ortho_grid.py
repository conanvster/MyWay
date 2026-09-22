"""Ортографічні види моделі з координатною сіткою — щоб розставити кістки
під нову сітку (`spec/генерація-3d-моделей-монстрів.md`, крок А6).

Сітка вже має бути розвернута мордою на −Y і стояти лапами на нулі
(тобто брати .blend, який зберіг білдер, або сирий .glb після `orient`).
Три кадри 900×900; у кадрі `масштаб` метрів (типово 0,9 — тоді 1 піксель = 1 мм):

  * `<основа>-збоку.png`  — камера з +X: праворуч +Y (хвіст), угору +Z;
  * `<основа>-спереду.png` — камера з −Y: праворуч +X (ліва лапа звіра), угору +Z;
  * `<основа>-згори.png`  — камера з +Z: праворуч +X, угору +Y.

Лінії прив'язані до справжніх координат світу: нульові — червоні, кожні
10 см — темно-сині, проміжні 5 см — блідо-сині. Підписів немає (текст
пікселями не малюємо) — відлік від червоних нулів: земля (Z = 0) на видах
збоку й спереду, вісь тулуба (X = 0) спереду й згори, Y = 0 збоку.

Запуск:
    blender --background <модель.blend> --python tools/blender/ortho_grid.py -- <основа> [масштаб]
"""
import os
import sys

import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if not args:
    sys.exit("‼ куди писати кадри? — після «--» дай основу імені")
stem = args[0]
span = float(args[1]) if len(args) > 1 else 0.9      # метрів у кадрі
SIZE = 900
STEP = 0.05

meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
zs = [(o.matrix_world @ Vector(c)).z for o in meshes for c in o.bound_box]
mid_z = (min(zs) + max(zs)) / 2

scene = bpy.context.scene
scene.render.resolution_x = scene.render.resolution_y = SIZE
cam = bpy.data.objects.new("Орто", bpy.data.cameras.new("Орто"))
scene.collection.objects.link(cam)
scene.camera = cam
cam.data.type = "ORTHO"
cam.data.ortho_scale = span
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.color_type = "TEXTURE"
scene.display.shading.light = "FLAT"
world = bpy.data.worlds.new("Тло")
world.color = (1, 1, 1)
scene.world = world

# (ім'я, де камера, куди дивиться, що по горизонталі, центр по вертикалі)
views = [
    ("збоку", (2, 0, mid_z), Vector((-1, 0, 0)), "Y", mid_z),
    ("спереду", (0, -2, mid_z), Vector((0, 1, 0)), "X", mid_z),
    ("згори", (0, 0, 3), Vector((0, 0, -1)), "X", 0.0),
]
shots = []
for name, at, look, _, _ in views:
    cam.location = at
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = look.to_track_quat("-Z", "Y")
    path = os.path.abspath("%s-%s.png" % (stem, name))
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    shots.append(path)

# Сітку домальовуємо поверх готових кадрів пікселями Blender — без PIL,
# бо Python Blender його не має.
per_m = SIZE / span


def tone(value):
    """Нуль — червоний, кожні 10 см — темніший, решта (5 см) — блідий."""
    k = round(value / STEP)
    if k == 0:
        return (0.85, 0.0, 0.0)
    return (0.35, 0.35, 0.8) if k % 2 == 0 else (0.72, 0.72, 1.0)


for (name, _, _, h_axis, v_mid), path in zip(views, shots):
    img = bpy.data.images.load(path)
    w, h = img.size
    px = list(img.pixels[:])            # рядки знизу вгору
    n = int(span / STEP) + 2
    for i in range(-n, n + 1):
        value = i * STEP
        colour = tone(value)
        x = int(round(w / 2 + value * per_m))           # горизонталь: центр = 0
        if 0 <= x < w:
            for y in range(h):
                k = (y * w + x) * 4
                px[k:k + 3] = colour
        y = int(round(h / 2 + (value - v_mid) * per_m))  # вертикаль: справжня Z/Y
        if 0 <= y < h:
            for x in range(w):
                k = (y * w + x) * 4
                px[k:k + 3] = colour
    img.pixels[:] = px
    img.save()
    print("[орто] %s · по горизонталі %s, лінії через %.0f см"
          % (path, h_axis, STEP * 100))
