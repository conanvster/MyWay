"""Олень-рогач із сітки, зробленої за референсом (24.09.2026), за
шляхом А `spec/генерація-3d-моделей-монстрів.md`.

Референс `wiki/img/monstry/олень-рогач.png` — олень іде, одна нога
піднята; крок пози (Kontext, `--хто "red deer stag with large
antlers"`) не прибрав ходу повністю (усі 4 варіанти лишили підняту
ногу) — обрано s33, найчистіший. Pixal3D з пози →
`art/monsters/олень-3d/pixal3d-01.glb`.

**Свій розрахунок нахилу, не `scan_quadruped_orient.level()`**: у позі
з ходою одразу ДВІ лапи з одного боку (перед-права, зад-права) висіли
в повітрі (0.5-0.55 м) — стандартний алгоритм розрахований на ОДНУ
погану лапу й із двома дає крен -20°, звіра підвішеним. З лівого боку
обидві лапи надійні (~0-0.03 м) — тангаж рахуємо з них (перед vs зад,
той самий бік), крен не рахуємо (нема надійної пари лівого/правого) —
лишаємо як є, а не вгадуємо. Ліва сторона тому й надійна, що на позі
кроку саме вона на землі.

Скелет — `make_hare.BONES`. `fix_hips_roll` — обов'язково (розділ А6.7
лог.md рисі).

Запуск (з каталогу проєкту):
    blender --background --python tools/blender/make_deer_scan.py -- \\
        art/monsters/олень.blend game/models/own/олень.glb [тека_для_картинок]
"""
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_template as base  # noqa: E402
import make_hare as hare  # noqa: E402
import scan_quadruped_orient as sqo  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SOURCE = os.path.join(ROOT, "art", "monsters", "олень-3d", "pixal3d-01.glb")
HEIGHT = 1.9             # зріст із mobs.json (вид 13), до кінчиків рогів
FACES = 40000            # роги тонкі й розгалужені — типові 20-30 тис. ріжуть відростки
TEXTURE = 2048


def level_left_side(mesh, height):
    """Див. докстрінг файлу: тангаж з лівої (надійної) пари лап, крен
    не чіпати."""
    vs = [v.co for v in mesh.data.vertices]
    cx = sum(v.x for v in vs) / len(vs)
    cy = sum(v.y for v in vs) / len(vs)
    feet = {}
    for v in vs:
        if abs(v.x - cx) < 0.03:
            continue
        key = (v.x > cx, v.y > cy)
        if key not in feet or v.z < feet[key].z:
            feet[key] = v.copy()
    names = {(False, False): "перед-права", (True, False): "перед-ліва",
             (False, True): "зад-права", (True, True): "зад-ліва"}
    for k, p in feet.items():
        print("[олень-скан] %s z=%.3f" % (names[k], p.z))

    front_l = feet[(True, False)]
    hind_l = feet[(True, True)]
    pitch = math.atan2(front_l.z - hind_l.z, hind_l.y - front_l.y)
    mesh.data.transform(Matrix.Rotation(pitch, 4, "X"))
    print("[олень-скан] тангаж з лівої пари: %.1f° (крен не рахувався)"
          % math.degrees(pitch))
    zs = [v.co.z for v in mesh.data.vertices]
    scale = height / (max(zs) - min(zs))
    mesh.data.transform(Matrix.Scale(scale, 4)
                        @ Matrix.Translation((0, 0, -min(zs))))
    ys = [v.co.y for v in mesh.data.vertices]
    shift = (max(ys) + min(ys)) / 2
    mesh.data.transform(Matrix.Translation((0, -shift, 0)))
    print("[олень-скан] зсув уздовж тулуба: %.3f м" % shift)
    return shift


def fix_hips_roll(skeleton):
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
    print("[олень-скан] голих вершин: %d із %d"
          % (int((bare > 0.5).sum()), len(bare)))


# Заміряно числом на орієнтованій чернетці (ONLY_ORIENT=1). Передня
# права нога піднята (частина пози ходи, не вада) — z=0.141.
BONES = [
    ("hips", (0.02, 0.55, 0.72), (0.02, 0.1, 0.75), None),
    ("chest", (0.02, 0.1, 0.75), (0.02, -0.32, 0.86), "hips"),
    ("head", (0.02, -0.32, 0.86), (0.03, -0.45, 0.85), "chest"),
    ("ear.R", (0.03, -0.4, 0.9), (-0.08, -0.38, 0.98), "head"),
    ("ear.L", (0.03, -0.4, 0.9), (0.1, -0.38, 0.98), "head"),
    ("tail", (0.02, 0.55, 0.72), (0.071, 0.75, 0.475), "hips"),
    ("front.L", (0.079, -0.1, 0.75), (0.079, -0.238, 0.0), "chest"),
    ("front.R", (-0.1, -0.05, 0.75), (-0.1, -0.184, 0.141), "chest"),
    ("hind.L", (0.081, 0.45, 0.72), (0.081, 0.598, 0.0), "hips"),
    ("hind.R", (-0.167, 0.4, 0.72), (-0.167, 0.23, 0.008), "hips"),
]


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
    print("[олень-скан] ваги за відстанню: %d вершин із %d"
          % (fixed, len(mesh.data.vertices)))


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
    blend = args[0] if args else "art/monsters/олень.blend"
    glb = args[1] if len(args) > 1 else ""
    base.clear()
    bpy.context.scene.render.fps = 24
    mesh = sqo.load_mesh(SOURCE)
    sqo.orient(mesh, HEIGHT)
    level_left_side(mesh, HEIGHT)
    simplify(mesh)
    shrink_textures(mesh)
    fur_mask(mesh)
    mesh.name = "Тіло"
    if os.environ.get("ONLY_ORIENT"):
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(blend))
        return
    skeleton = rig(mesh)
    hare.actions(skeleton)
    if len(args) > 2:
        hare.previews(skeleton, args[2], zoom=1.6)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(blend))
    print("[олень-скан] збережено", blend)
    if glb:
        export(os.path.abspath(glb))
        print("[олень-скан] експорт", glb)


if __name__ == "__main__":
    main()
