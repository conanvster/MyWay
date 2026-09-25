"""Квадратний рендер 1024×1024 для вікі (`wiki/img/monstry/<назва>-
модель.png`) зі збудованого `.blend` — темна печера + вогник, як на
референс-арті. Крок 8.1 `spec/генерація-3d-моделей-монстрів.md`.

**Параметри світла й відстані підбирати щоразу заново** (зауважено на
паглін 23.09.2026: значення, що добре лягли на імпа, дали жовтий
пересвіт на іншій шкірі) — `--fire`/`--sun`/`--dist` не мають типового
«правильного» числа для всіх видів, дивитись результат і коригувати.

Запуск (з каталогу проєкту):
    blender --background --python tools/blender/scan_wiki_render.py -- \\
        art/monsters/<назва>.blend wiki/img/monstry/<назва>-модель.png \\
        [--dist 1.15] [--fire 4] [--sun 3.2] [--action Idle:1]
"""
import math
import os
import sys

import bpy
from mathutils import Vector


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    blend_path, out_path = argv[0], argv[1]
    dist_mult, fire_e, sun_e, action_spec = 1.15, 4.0, 3.2, "Idle:1"
    i = 2
    while i < len(argv):
        if argv[i] == "--dist":
            dist_mult = float(argv[i + 1]); i += 2
        elif argv[i] == "--fire":
            fire_e = float(argv[i + 1]); i += 2
        elif argv[i] == "--sun":
            sun_e = float(argv[i + 1]); i += 2
        elif argv[i] == "--action":
            action_spec = argv[i + 1]; i += 2
        else:
            i += 1
    act_name, act_frame = action_spec.split(":")

    bpy.ops.wm.open_mainfile(filepath=blend_path)
    rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    mesh = next(o for o in bpy.data.objects if o.type == "MESH")
    act = bpy.data.actions.get(act_name)
    if act:
        rig.animation_data.action = act
        if act.slots:
            rig.animation_data.action_slot = act.slots[0]
    bpy.context.scene.frame_set(int(act_frame) if act_frame != "last" else int(act.frame_range[1]))

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("W")
    scene.world = world
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.012, 0.02, 0.026, 1.0)

    sun = bpy.data.objects.new("Сонце", bpy.data.lights.new("Сонце", "SUN"))
    sun.rotation_euler = (math.radians(50), 0, math.radians(-30))
    sun.data.energy = sun_e
    sun.data.color = (0.65, 0.72, 0.85)
    scene.collection.objects.link(sun)

    fire = bpy.data.objects.new("Вогонь", bpy.data.lights.new("Вогонь", "POINT"))
    fire.data.energy = fire_e
    fire.data.color = (1.0, 0.45, 0.12)
    fire.location = (0.35, -0.3, 0.05)
    scene.collection.objects.link(fire)

    minv = Vector((1e9, 1e9, 1e9))
    maxv = Vector((-1e9, -1e9, -1e9))
    depsgraph = bpy.context.evaluated_depsgraph_get()
    eval_mesh = mesh.evaluated_get(depsgraph)
    for v in eval_mesh.data.vertices:
        wc = eval_mesh.matrix_world @ v.co
        minv.x, minv.y, minv.z = min(minv.x, wc.x), min(minv.y, wc.y), min(minv.z, wc.z)
        maxv.x, maxv.y, maxv.z = max(maxv.x, wc.x), max(maxv.y, wc.y), max(maxv.z, wc.z)
    center = (minv + maxv) / 2
    size = max((maxv - minv).x, (maxv - minv).y, (maxv - minv).z)

    cam_data = bpy.data.cameras.new("C")
    cam = bpy.data.objects.new("C", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.data.lens = 45
    cam.location = (center.x + size * dist_mult, center.y - size * dist_mult * 1.4,
                     center.z + size * 0.1)
    direction = center - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()

    if "--авто" in argv:
        auto_light(scene, cam, center, size, [sun], albedo_lum(mesh))
    scene.render.filepath = out_path
    bpy.ops.render.render(write_still=True)
    print("[вікі-рендер]", out_path, "bbox", tuple(minv), tuple(maxv))


def _probe(scene, path):
    """Пробний кадр 256² з прозорим тлом → (середня світлість звіра,
    частка кадру, яку він займає по більшій стороні)."""
    import numpy as np
    r = scene.render
    keep = (r.resolution_x, r.resolution_y, r.film_transparent, r.filepath)
    r.resolution_x = r.resolution_y = 256
    r.film_transparent = True
    r.filepath = path
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(path)
    px = np.array(img.pixels[:], dtype=np.float32).reshape(256, 256, 4)
    bpy.data.images.remove(img)
    r.resolution_x, r.resolution_y, r.film_transparent, r.filepath = keep
    m = px[:, :, 3] > 0.5
    if not m.any():
        return 0.0, 0.0, 0.0
    lum = (0.2126 * px[:, :, 0] + 0.7152 * px[:, :, 1] + 0.0722 * px[:, :, 2])[m]
    ys, xs = np.nonzero(m)
    fill = max(ys.max() - ys.min(), xs.max() - xs.min()) / 256.0
    return float(np.median(lum)), float(fill), float(np.percentile(lum, 95))


def albedo_lum(mesh):
    """Медіанна світлість власної текстури звіра (без чорних полів
    атласу). Ціль експозиції — від неї: сірий вовк 24.09.2026 з однією
    ціллю на всіх (0.38) вийшов білим."""
    import numpy as np
    for node in mesh.data.materials[0].node_tree.nodes:
        if node.type == "TEX_IMAGE" and node.image and node.image.size[0]:
            w, h = node.image.size
            px = np.array(node.image.pixels[:], dtype=np.float32).reshape(-1, 4)[:: 7]
            lum = 0.2126 * px[:, 0] + 0.7152 * px[:, 1] + 0.0722 * px[:, 2]
            lum = lum[lum > 0.03]
            if len(lum):
                return float(np.median(lum))
    return 0.35


def auto_light(scene, cam, center, size, lights, albedo=0.35):
    """Три точки замість ручного підбору `--fire/--sun/--dist` під кожну
    шкіру (олень 24.09.2026 — три спроби, поки не став видним):
    ключове (наявне сонце), м'яке заповнення з протилежного боку, контур
    ззаду-згори. Далі пробний кадр: камера — щоб звір займав ~78% кадру,
    сила ключового/заповнення/контуру — щоб медіанна світлість звіра була
    трохи вищою за світлість його текстури (`albedo_lum`); вогник
    (теплий акцент) не підсилюється — інакше світле черево ставало
    помаранчевим."""
    import os
    import tempfile
    fill = bpy.data.objects.new("Заповнення", bpy.data.lights.new("Заповнення", "AREA"))
    # Заповнення сильне відносно сонця: у сірого вовка з білою гривою
    # сонце вибілювало гриву, а бік лишався в тіні (0.14 при гриві 0.76).
    fill.data.energy = 180.0 * size * size
    fill.data.size = size * 2
    fill.data.color = (0.75, 0.82, 1.0)
    fill.location = (center.x - size * 1.6, center.y - size * 1.2, center.z + size * 0.4)
    fill.rotation_euler = (center - fill.location).to_track_quat("-Z", "Y").to_euler()
    rim = bpy.data.objects.new("Контур", bpy.data.lights.new("Контур", "AREA"))
    rim.data.energy = 60.0 * size * size
    for o in lights:
        o.data.energy *= 0.5
    rim.data.size = size
    rim.location = (center.x + size * 0.4, center.y + size * 1.8, center.z + size * 1.4)
    rim.rotation_euler = (center - rim.location).to_track_quat("-Z", "Y").to_euler()
    for o in (fill, rim):
        scene.collection.objects.link(o)
    lights = lights + [fill, rim]
    # Ціль — трохи ТЕМНІШЕ за власну текстуру: Pixal3D запікає світло в
    # текстуру, і «рівна» ціль (×1.15) білила сірого вовка. Низ 0.18 — щоб темний звір не губився в печері.
    target = min(0.40, max(0.18, albedo * 0.85))
    print("[вікі-рендер] авто: світлість текстури %.2f → ціль %.2f" % (albedo, target))
    tmp = os.path.join(tempfile.gettempdir(), "вікі-проба.png")
    for _ in range(4):
        lum, frac, hi = _probe(scene, tmp)
        if frac > 0:
            d = cam.location - center
            cam.location = center + d * (frac / 0.78)
        if lum > 0:
            # Піксель ≈ енергія^(1/2.2) (гамма sRGB) — корекція в степені.
            k = max(0.1, min(10.0, (target / lum) ** 2.2))
            # Світлі ділянки (сива грива, біле черево) не вище 0.8 —
            # інакше «білий» вовк при правильній середній.
            if hi > 0:
                k = min(k, (0.8 / hi) ** 2.2)
            for o in lights:
                o.data.energy *= k
        print("[вікі-рендер] авто: світлість %.2f (світлі %.2f), кадр %.0f%%" % (lum, hi, frac * 100))
        if (abs(lum - target) < 0.03 or hi > 0.76) and hi <= 0.84 and abs(frac - 0.78) < 0.05:
            break


if __name__ == "__main__":
    main()
