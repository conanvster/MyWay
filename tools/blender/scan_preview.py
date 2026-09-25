"""Рендер ключових кадрів Idle/Walk/Attack/Death зі збудованого `.blend`
— перевірка деформації скіна ПЕРЕД експортом (крок А6.8 `spec/
генерація-3d-моделей-монстрів.md`): чи не рветься сітка, чи рука з
кулаком не заходить повз голову, чи Death не проваливсь під землю.

Запуск (з каталогу проєкту):
    blender --background --python tools/blender/scan_preview.py -- \\
        art/monsters/<назва>.blend art/monsters/<назва>-3d/рухи \\
        Idle:1 Walk:5 Walk:9 Attack:9 Death:last
"""
import math
import os
import sys

import bpy
from mathutils import Vector


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    blend_path, out_dir = argv[0], argv[1]
    shot_args = argv[2:] or ["Idle:1", "Walk:9", "Attack:9", "Death:last"]
    os.makedirs(out_dir, exist_ok=True)

    bpy.ops.wm.open_mainfile(filepath=blend_path)
    rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    mesh = next(o for o in bpy.data.objects if o.type == "MESH")

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    world = bpy.data.worlds.new("W")
    world.color = (0.6, 0.6, 0.6)
    scene.world = world
    light = bpy.data.objects.new("L", bpy.data.lights.new("L", "SUN"))
    light.data.energy = 3.0
    light.rotation_euler = (math.radians(55), 0, math.radians(35))
    scene.collection.objects.link(light)

    minv = Vector((1e9, 1e9, 1e9))
    maxv = Vector((-1e9, -1e9, -1e9))
    for c in mesh.bound_box:
        wc = mesh.matrix_world @ Vector(c)
        minv.x, minv.y, minv.z = min(minv.x, wc.x), min(minv.y, wc.y), min(minv.z, wc.z)
        maxv.x, maxv.y, maxv.z = max(maxv.x, wc.x), max(maxv.y, wc.y), max(maxv.z, wc.z)
    center = (minv + maxv) / 2
    size = max((maxv - minv).x, (maxv - minv).y, (maxv - minv).z, 0.5)
    dist = size * 2.3

    cam_data = bpy.data.cameras.new("C")
    cam = bpy.data.objects.new("C", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.location = (center.x + dist * 0.7, center.y - dist * 0.7, center.z + size * 0.15)
    direction = center - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()

    for shot in shot_args:
        name, frame_s = shot.split(":")
        act = bpy.data.actions.get(name)
        if act is None:
            print("[рухи] немає дії", name)
            continue
        rig.animation_data.action = act
        if act.slots:
            rig.animation_data.action_slot = act.slots[0]
        frame = int(act.frame_range[1]) if frame_s == "last" else int(frame_s)
        scene.frame_set(frame)
        scene.render.filepath = os.path.join(out_dir, "%s-%d.png" % (name, frame))
        bpy.ops.render.render(write_still=True)
        print("[рухи] рендер", name, frame)


if __name__ == "__main__":
    main()
