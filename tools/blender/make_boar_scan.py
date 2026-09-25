"""Кабан із сітки, зробленої за референсом (24.09.2026), за шляхом А
`spec/генерація-3d-моделей-монстрів.md`.

Референс `wiki/img/monstry/кабан.png` — камера дуже близько й низько,
ікла величезні на передньому плані (як скорпіон) — крок пози (Kontext,
`--хто "wild boar"`) відсунув камеру, обрано варіант s11 з чотирьох.
Pixal3D з пози → `art/monsters/кабан-3d/pixal3d-01.glb`.

Орієнтація/вирівнювання — `scan_quadruped_orient.py` (самоперевірний
нахил). Скелет — `make_hare.BONES` (немає власного процедурного
білдера — кабан у спільному `beasts.py` на скелеті зайця). `fix_hips_roll`
— обов'язково для будь-якого нового виду на цьому скелеті (розділ А6.7
`лог.md` рисі): авторолл `hips` інакше може розвернути локальні осі, і
`location.z` у `hare.actions()` рухатиме не по вертикалі.

Запуск (з каталогу проєкту):
    blender --background --python tools/blender/make_boar_scan.py -- \\
        art/monsters/кабан.blend game/models/own/кабан.glb [тека_для_картинок]
"""
import os
import sys

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_template as base  # noqa: E402
import make_hare as hare  # noqa: E402
import scan_quadruped_orient as sqo  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SOURCE = os.path.join(ROOT, "art", "monsters", "кабан-3d", "pixal3d-01.glb")
HEIGHT = 1.0             # зріст із mobs.json (вид 3)
FACES = 80000
TEXTURE = 2048

# Заміряно `scan_quadruped_orient.py` на орієнтованій-вирівняній
# чернетці (тангаж 3.5°, крен -1.7° — сирий нахил малий, лапи всі
# ~0-0.003 м, без викидів).
BONES = [
    ("hips", (-0.02, 0.45, 0.45), (0.0, 0.0, 0.5), None),
    ("chest", (0.0, 0.0, 0.5), (0.0, -0.05, 0.55), "hips"),
    ("head", (0.0, -0.05, 0.55), (0.0, -0.03, 0.88), "chest"),
    ("ear.R", (0.0, -0.03, 0.88), (-0.065, -0.042, 1.0), "head"),
    ("ear.L", (0.0, -0.03, 0.88), (0.053, 0.006, 0.969), "head"),
    ("tail", (-0.02, 0.45, 0.45), (-0.008, 0.627, 0.621), "hips"),
    ("front.L", (0.082, -0.1, 0.5), (0.082, -0.187, 0.0), "chest"),
    ("front.R", (-0.171, -0.09, 0.5), (-0.171, -0.175, 0.003), "chest"),
    ("hind.L", (0.055, 0.35, 0.45), (0.055, 0.435, 0.002), "hips"),
    ("hind.R", (-0.092, 0.35, 0.45), (-0.092, 0.428, 0.001), "hips"),
]


def fix_hips_roll(skeleton):
    """Розділ А6.7 лог.md рисі — обов'язково для кожного нового виду на
    скелеті зайця/вовка: авторолл `hips` інакше може відв'язати
    `location.z` від світової вертикалі."""
    bpy.context.view_layer.objects.active = skeleton
    bpy.ops.object.mode_set(mode="EDIT")
    skeleton.data.edit_bones["hips"].align_roll((0, 0, 1))
    bpy.ops.object.mode_set(mode="OBJECT")


def simplify(mesh):
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0005)
    bpy.ops.object.mode_set(mode="OBJECT")
    mod = mesh.modifiers.new("Спрощення", "DECIMATE")
    mod.ratio = FACES / len(mesh.data.polygons)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.ops.object.shade_smooth()


def base_colour(mesh):
    mat = mesh.data.materials[0]
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    return bsdf.inputs["Base Color"].links[0].from_node.image


def shrink_textures(mesh):
    for node in mesh.data.materials[0].node_tree.nodes:
        if node.type == "TEX_IMAGE" and node.image.size[0] > TEXTURE:
            node.image.scale(TEXTURE, TEXTURE)


def fur_mask(mesh):
    """Друга UV: U = голизна. Рожеве (п'ятачок, нутро вух) і темне
    (очі, ікла, кігті) — голе, решта в щетині."""
    image = base_colour(mesh)
    w, h = image.size
    px = np.array(image.pixels[:], dtype=np.float32).reshape(h, w, 4)
    me = mesh.data
    uv = me.uv_layers[0].data
    bare = np.zeros(len(me.vertices), dtype=np.float32)
    seen = np.zeros(len(me.vertices), dtype=np.int32)
    for loop in me.loops:
        u, v = uv[loop.index].uv
        x = min(w - 1, max(0, int(u * w)))
        y = min(h - 1, max(0, int(v * h)))
        r, g, b, _ = px[y, x]
        light = 0.3 * r + 0.59 * g + 0.11 * b
        pink = r > 0.3 and r > 1.45 * g and b > 0.85 * g
        dark = light < 0.14
        bare[loop.vertex_index] += 1.0 if (pink or dark) else 0.0
        seen[loop.vertex_index] += 1
    bare = bare / np.maximum(seen, 1)
    mask = me.uv_layers.new(name="Голизна")
    for loop in me.loops:
        mask.data[loop.index].uv = (float(bare[loop.vertex_index]), 0.0)
    me.uv_layers.active_index = 0
    print("[кабан-скан] голих вершин: %d із %d"
          % (int((bare > 0.5).sum()), len(bare)))


def rig(mesh):
    skeleton = hare.armature(BONES)
    fix_hips_roll(skeleton)
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    skeleton.select_set(True)
    bpy.context.view_layer.objects.active = skeleton
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    by_distance(mesh, skeleton)
    return skeleton


def by_distance(mesh, skeleton):
    bones = [(b.name, Vector(b.head_local), Vector(b.tail_local))
             for b in skeleton.data.bones]
    groups = {name: mesh.vertex_groups.get(name)
              or mesh.vertex_groups.new(name=name) for name, _, _ in bones}
    fixed = 0
    for v in mesh.data.vertices:
        if sum(e.weight for e in v.groups) > 0.01:
            continue
        near = []
        for name, a, b in bones:
            ab = b - a
            t = max(0.0, min(1.0, (v.co - a).dot(ab) / ab.length_squared))
            d = (v.co - (a + ab * t)).length
            near.append((d, name))
        near.sort()
        weights = [(1.0 / max(d, 0.005) ** 4, n) for d, n in near[:2]]
        total = sum(w for w, _ in weights)
        for w, n in weights:
            groups[n].add([v.index], w / total, "REPLACE")
        fixed += 1
    print("[кабан-скан] ваги за відстанню: %d вершин із %d"
          % (fixed, len(mesh.data.vertices)))


def fix_ground(action_name, deltas):
    """Короткі товсті ноги кабана (за описом моделі) не пропорційні
    абсолютним, у метрах, зсувам `hips` у `hare.actions()` — розділ
    А6.8 лог.md рисі. `location.z` кістки hips після `fix_hips_roll`
    рухає по світовій вертикалі 1:1, тож зсув можна порахувати прямо з
    виміряної нестачі/надлишку висоти."""
    act = bpy.data.actions[action_name]
    for fcu in hare.curves(act):
        if fcu.data_path == 'pose.bones["hips"].location' and fcu.array_index == 2:
            for kp in fcu.keyframe_points:
                d = deltas.get(round(kp.co.x))
                if d:
                    kp.co.y += d
                    kp.handle_left.y += d
                    kp.handle_right.y += d
            fcu.update()


def export(out):
    bpy.ops.export_scene.gltf(
        filepath=out, export_format="GLB", export_yup=True,
        export_apply=True, export_animations=True,
        export_animation_mode="ACTIONS", export_force_sampling=True,
        export_def_bones=False, export_skins=True,
        export_texcoords=True, export_image_format="JPEG",
        export_jpeg_quality=90)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    blend = args[0] if args else "art/monsters/кабан.blend"
    glb = args[1] if len(args) > 1 else ""
    base.clear()
    bpy.context.scene.render.fps = 24
    mesh = sqo.load_mesh(SOURCE)
    sqo.orient(mesh, HEIGHT)
    sqo.level(mesh, HEIGHT)
    simplify(mesh)
    shrink_textures(mesh)
    fur_mask(mesh)
    mesh.name = "Тіло"
    if os.environ.get("ONLY_ORIENT"):
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(blend))
        return
    skeleton = rig(mesh)
    hare.actions(skeleton)
    fix_ground("Walk", {5: 0.11, 9: 0.03})
    fix_ground("Attack", {9: 0.43, 16: 0.18})
    fix_ground("Death", {30: -0.30})
    if len(args) > 2:
        hare.previews(skeleton, args[2])
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(blend))
    print("[кабан-скан] збережено", blend)
    if glb:
        export(os.path.abspath(glb))
        print("[кабан-скан] експорт", glb)


if __name__ == "__main__":
    main()
