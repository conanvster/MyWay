"""Рендер сирої сітки Pixal3D із 4 боків — крок А5 `spec/
генерація-3d-моделей-монстрів.md`, звірка з чеклістом ДО побудови
скелета. Спільний для всіх видів шляху А (гуманоїдів і не тільки).

Запуск (з каталогу проєкту):
    blender --background --python tools/blender/scan_inspect.py -- \\
        art/monsters/<назва>-3d/pixal3d-01.glb art/monsters/<назва>-3d/огляд
"""
import math
import os
import sys

import bpy
from mathutils import Vector


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    glb_path, out_dir = argv[0], argv[1]
    os.makedirs(out_dir, exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb_path)

    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    minv = Vector((1e9, 1e9, 1e9))
    maxv = Vector((-1e9, -1e9, -1e9))
    for o in meshes:
        for c in o.bound_box:
            wc = o.matrix_world @ Vector(c)
            minv.x, minv.y, minv.z = min(minv.x, wc.x), min(minv.y, wc.y), min(minv.z, wc.z)
            maxv.x, maxv.y, maxv.z = max(maxv.x, wc.x), max(maxv.y, wc.y), max(maxv.z, wc.z)
    center = (minv + maxv) / 2
    size = max((maxv - minv).x, (maxv - minv).y, (maxv - minv).z, 0.5)
    dist = size * 2.2

    scene = bpy.context.scene
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    scene.world = bpy.data.worlds.new("W")
    scene.world.color = (0.7, 0.7, 0.7)

    light = bpy.data.objects.new("L", bpy.data.lights.new("L", "SUN"))
    light.data.energy = 3.0
    scene.collection.objects.link(light)
    light.rotation_euler = (math.radians(55), 0, math.radians(35))

    cam_data = bpy.data.cameras.new("C")
    cam = bpy.data.objects.new("C", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam

    views = {
        "1-три_чверті": (dist * 0.7, -dist * 0.7, center.z + size * 0.15),
        "2-збоку": (dist, 0, center.z + size * 0.05),
        "3-спереду": (0, -dist, center.z + size * 0.05),
        "4-ззаду": (0, dist, center.z + size * 0.05),
    }
    for name, (dx, dy, dz) in views.items():
        cam.location = (center.x + dx, center.y + dy, dz)
        direction = center - cam.location
        cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(out_dir, name + ".png")
        bpy.ops.render.render(write_still=True)
        print("[огляд] рендер", name)

    print("[огляд] bbox", tuple(minv), tuple(maxv), "розмір", size)


if __name__ == "__main__":
    main()
