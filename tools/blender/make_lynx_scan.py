"""Рись із сітки, зробленої за референсом (24.09.2026), за шляхом А
`spec/генерація-3d-моделей-монстрів.md`.

Референс `wiki/img/monstry/рись.png` — рись уже стоїть на всіх чотирьох
лапах у профіль/три чверті, крок пози пропущено; Pixal3D прямо з
референсу → `art/monsters/рись-3d/pixal3d-01.glb`.

Орієнтація/вирівнювання — через спільний `scan_quadruped_orient.py`
(самоперевірний розрахунок нахилу: пробує з виключенням підозрілої лапи
й без, лишає варіант з меншим розкидом — розділ А6.2). Скелет — за
`make_hare.BONES` (немає власного процедурного білдера, рись у
спільному `beasts.py` теж на скелеті зайця).

Запуск (з каталогу проєкту):
    blender --background --python tools/blender/make_lynx_scan.py -- \\
        art/monsters/рись.blend game/models/own/рись.glb [тека_для_картинок]
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
SOURCE = os.path.join(ROOT, "art", "monsters", "рись-3d", "pixal3d-01.glb")
HEIGHT = 0.75           # зріст із mobs.json (вид 12)
FACES = 32000
TEXTURE = 2048

# Заміряно `scan_quadruped_orient.py` на орієнтованій-вирівняній чернетці.
BONES = [
    ("hips", (0.03, 0.32, 0.4), (0.05, 0.05, 0.42), None),
    ("chest", (0.05, 0.05, 0.42), (0.05, -0.15, 0.48), "hips"),
    ("head", (0.05, -0.15, 0.48), (0.065, -0.28, 0.58), "chest"),
    ("ear.R", (0.065, -0.28, 0.58), (-0.084, -0.287, 0.75), "head"),
    ("ear.L", (0.065, -0.28, 0.58), (0.213, -0.277, 0.665), "head"),
    ("tail", (0.03, 0.32, 0.35), (0.122, 0.416, 0.203), "hips"),
    ("front.L", (0.107, -0.06, 0.42), (0.107, -0.116, 0.0), "chest"),
    ("front.R", (-0.014, -0.02, 0.42), (-0.014, -0.075, 0.014), "chest"),
    ("hind.L", (0.098, 0.22, 0.4), (0.098, 0.256, 0.01), "hips"),
    ("hind.R", (-0.044, 0.25, 0.4), (-0.044, 0.294, 0.009), "hips"),
]


def simplify(mesh):
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0005)
    bpy.ops.object.mode_set(mode="OBJECT")
    mod = mesh.modifiers.new("Спрощення", "DECIMATE")
    mod.ratio = FACES / len(mesh.data.polygons)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    # Тонкий короткий хвіст рисі після децимації лишав перевернуті
    # нормалі на кінчику — шари хутра на цих вершинах росли не назовні,
    # а вздовж хребта високим "шпилем" (розділ А8, видно лише з хутром,
    # на голій сітці непомітно).
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
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
    """Друга UV: U = голизна. Рожеве (ніс, нутро вух) і темне (очі,
    кігті, чорні кінчики вух) — голе, решта в хутрі. Поріг темного
    послаблено (0.14, як у лисиці — розділ А6.5 не завжди підходить
    буквально для нового виду)."""
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
    print("[рись-скан] голих вершин: %d із %d"
          % (int((bare > 0.5).sum()), len(bare)))


def fix_hips_roll(skeleton):
    """`hips` у зайця/вовка/лисиці лежить точно в площині YZ (X голови
    = X хвоста) — авторолл Blender випадково вирівнює локальний Z
    близько до світового, тож `location.z` у `hare.actions()`
    (UP_IN_HIPS) реально рухає вгору-вниз. У рисі X трохи різний —
    авторолл розвернув локальні осі так, що `location.z` рухав по
    світовому X, а не Z (перевірено виміром зсуву по кожній осі:
    розділ А6.7). Примусово вирівняти локальний Z кістки hips по
    світовому Z, щоб рухи з `make_hare.py` рахували вертикаль
    правильно на будь-якій геометрії."""
    bpy.context.view_layer.objects.active = skeleton
    bpy.ops.object.mode_set(mode="EDIT")
    hips = skeleton.data.edit_bones["hips"]
    hips.align_roll((0, 0, 1))
    bpy.ops.object.mode_set(mode="OBJECT")


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
    print("[рись-скан] ваги за відстанню: %d вершин із %d"
          % (fixed, len(mesh.data.vertices)))


def fix_ground(action_name, deltas):
    """Довгі ноги рисі (розділ А6.6) не пропорційні абсолютним, у метрах,
    зсувам `hips` у `hare.actions()` — на частині кадрів лапи протикають
    землю, на Death кінець падіння висів у повітрі. Тепер, коли
    `fix_hips_roll` вирівняв вісь, `location.z` кістки hips напряму (1:1)
    рухає по світовій вертикалі — можна прицільно зсунути лише названі
    кадри, не чіпаючи `make_hare.py`. `deltas`: {кадр: зсув у метрах}."""
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
    blend = args[0] if args else "art/monsters/рись.blend"
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
    fix_ground("Walk", {5: 0.08, 9: 0.045})
    fix_ground("Attack", {9: 0.34, 16: 0.14})
    fix_ground("Death", {30: -0.32})
    if len(args) > 2:
        hare.previews(skeleton, args[2])
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(blend))
    print("[рись-скан] збережено", blend)
    if glb:
        export(os.path.abspath(glb))
        print("[рись-скан] експорт", glb)


if __name__ == "__main__":
    main()
