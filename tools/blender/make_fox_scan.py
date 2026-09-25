"""Лисиця із сітки, зробленої за референсом (24.09.2026), за шляхом А
`spec/генерація-3d-моделей-монстрів.md`.

Звідки сітка: референс `wiki/img/monstry/лисиця.png` — лисиця вже стоїть
на всіх чотирьох лапах у три чверті, тож крок пози (Kontext) пропущено,
як у вовка; Pixal3D (ComfyUI) прямо з референсу →
`art/monsters/лисиця-3d/pixal3d-01.glb`.

Свого процедурного білдера в лисиці нема (вона в спільному `beasts.py`,
на скелеті зайця, без щелепи) — тож імена й напрямки кісток і рухи беремо
з `make_hare.py` (розділ 3 таблиці: «інакше make_hare.py»), а вирівнювання
нахилу (`level`) — як у вовка, бо сітка теж прямо з референсу, без
проміжного кроку пози Kontext.

Запуск (з каталогу проєкту):
    blender --background --python tools/blender/make_fox_scan.py -- \\
        art/monsters/лисиця.blend game/models/own/лисиця.glb [тека_для_картинок]
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

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SOURCE = os.path.join(ROOT, "art", "monsters", "лисиця-3d", "pixal3d-01.glb")
HEIGHT = 0.6            # зріст із mobs.json (вид 11)
FACES = 20000
TEXTURE = 2048

# Заміряно числом на орієнтованій-вирівняній чернетці (ONLY_ORIENT):
# Z/Y-смуги для голови/шиї/стегон/хвоста, крайні точки для лап і вух.
# Ліва сторона (передня ліва лапа, ліве вухо) — дальня від камери на
# референсі, слабша й асиметрична (та сама природа, що в асиметричної
# голови вовка) — координати не дзеркалити, брати заміряні.
BONES = [
    ("hips", (0.0, 0.13, 0.28), (0.0, 0.0, 0.30), None),
    ("chest", (0.0, 0.0, 0.30), (-0.03, -0.19, 0.34), "hips"),
    ("head", (-0.03, -0.19, 0.34), (-0.05, -0.26, 0.55), "chest"),
    ("ear.R", (-0.05, -0.26, 0.55), (-0.22, -0.253, 0.6), "head"),
    ("ear.L", (-0.05, -0.26, 0.55), (-0.015, -0.259, 0.505), "head"),
    ("tail", (0.02, 0.14, 0.26), (-0.1, 0.423, 0.258), "hips"),
    ("front.L", (0.017, -0.05, 0.28), (0.017, -0.12, 0.061), "chest"),
    ("front.R", (-0.11, -0.06, 0.28), (-0.11, -0.146, 0.0), "chest"),
    ("hind.L", (0.023, 0.12, 0.28), (0.023, 0.047, 0.011), "hips"),
    ("hind.R", (-0.091, 0.12, 0.28), (-0.091, 0.046, 0.007), "hips"),
]


def load_mesh():
    bpy.ops.import_scene.gltf(filepath=SOURCE)
    mesh = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
    for other in list(bpy.context.scene.objects):
        if other is not mesh:
            bpy.data.objects.remove(other)
    bpy.context.view_layer.objects.active = mesh
    mesh.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return mesh


def orient(mesh):
    """Мордою на −Y, лапами на нуль, заввишки HEIGHT. Куди дивиться
    голова — за головною віссю тулуба (точки нижче основи вух) і тим,
    з якого її кінця стирчать вуха."""
    vs = [v.co.copy() for v in mesh.data.vertices]
    top = max(vs, key=lambda v: v.z)
    body = [v for v in vs if v.z < top.z - 0.35]
    cx = sum(v.x for v in body) / len(body)
    cy = sum(v.y for v in body) / len(body)
    sxx = sum((v.x - cx) ** 2 for v in body)
    syy = sum((v.y - cy) ** 2 for v in body)
    sxy = sum((v.x - cx) * (v.y - cy) for v in body)
    angle = 0.5 * math.atan2(2 * sxy, sxx - syy)
    axis = Vector((math.cos(angle), math.sin(angle)))
    if (top.xy - Vector((cx, cy))).dot(axis) < 0:
        axis = -axis
    yaw = math.atan2(axis.y, axis.x)
    mesh.data.transform(Matrix.Translation((-cx, -cy, 0)))
    mesh.data.transform(Matrix.Rotation(-math.pi / 2 - yaw, 4, "Z"))
    zs = [v.co.z for v in mesh.data.vertices]
    scale = HEIGHT / (max(zs) - min(zs))
    mesh.data.transform(Matrix.Scale(scale, 4)
                        @ Matrix.Translation((0, 0, -min(zs))))


def level(mesh):
    """Pixal3D переносить перспективу арту — нахилити так, щоб чотири
    лапи (квадранти навколо центру, без смуги хвоста) лягли на одну
    площину, тоді знов на нуль і в HEIGHT.

    Передня права лапа на референсі частково затінена іншою ногою —
    Pixal3D її не добудовує до землі (лишається ~0.1-0.15 м у повітрі
    в СИРІЙ сітці, підтверджено на двох сідах, отже не шум генератора).
    Замість патчити сітку вручну — виключити цю лапу з розрахунку
    нахилу й рахувати по трьох надійних (розділ А5 методу)."""
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
    zs = {names[k]: p.z for k, p in feet.items()}
    med = sorted(zs.values())[1:3]
    med_val = sum(med) / 2
    bad = max(zs, key=lambda n: abs(zs[n] - med_val))
    exclude = abs(zs[bad] - med_val) > 0.05

    def avg(pts, pt_names):
        if exclude:
            pts = [p for p, n in zip(pts, pt_names) if n != bad]
        return sum(pts, Vector()) / len(pts)

    front_pts = [feet[(False, False)], feet[(True, False)]]
    hind_pts = [feet[(False, True)], feet[(True, True)]]
    right_pts = [feet[(False, False)], feet[(False, True)]]
    left_pts = [feet[(True, False)], feet[(True, True)]]
    if exclude:
        print("[лисиця-скан] лапа %s не торкається землі в сирій сітці "
              "(z=%.3f, інші ~%.3f) — виключено з розрахунку нахилу"
              % (bad, zs[bad], med_val))

    f = avg(front_pts, ["перед-права", "перед-ліва"])
    b = avg(hind_pts, ["зад-права", "зад-ліва"])
    pitch = math.atan2(f.z - b.z, b.y - f.y)
    r = avg(right_pts, ["перед-права", "зад-права"])
    l = avg(left_pts, ["перед-ліва", "зад-ліва"])
    roll = math.atan2(l.z - r.z, l.x - r.x)
    mesh.data.transform(Matrix.Rotation(pitch, 4, "X"))
    mesh.data.transform(Matrix.Rotation(roll, 4, "Y"))
    print("[лисиця-скан] вирівняно: тангаж %.1f°, крен %.1f°"
          % (math.degrees(pitch), math.degrees(roll)))
    zs = [v.co.z for v in mesh.data.vertices]
    scale = HEIGHT / (max(zs) - min(zs))
    mesh.data.transform(Matrix.Scale(scale, 4)
                        @ Matrix.Translation((0, 0, -min(zs))))
    ys = [v.co.y for v in mesh.data.vertices]
    shift = (max(ys) + min(ys)) / 2
    mesh.data.transform(Matrix.Translation((0, -shift, 0)))
    print("[лисиця-скан] зсув уздовж тулуба: %.3f м" % shift)
    return shift


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
    """Друга UV: U = голизна. Рожеве (нутро вух, ніс) і майже чорне
    (очі, кігті) — голе, решта в хутрі."""
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
    print("[лисиця-скан] голих вершин: %d із %d"
          % (int((bare > 0.5).sum()), len(bare)))


def rig(mesh, shift):
    # BONES заміряно прямо на чернетці ONLY_ORIENT, яка вже пройшла
    # level() (зсув застосований) — той самий стан, що й mesh тут,
    # тож координати передаються як є, без повторного зсуву.
    skeleton = hare.armature(BONES)
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
    print("[лисиця-скан] ваги за відстанню: %d вершин із %d"
          % (fixed, len(mesh.data.vertices)))


def fix_walk_ground(skeleton):
    """`hare.actions` перенесено з інших пропорцій ноги — на кадрах 1,
    13, 16 «Walk» лапи протикали землю на 2.7-3.3 см (перевірено
    найнижчою вершиною в ключових кадрах, розділ А6.8). Підняти стегно
    трохи вище саме в цих кадрах, не чіпаючи спільний `make_hare.py`."""
    act = bpy.data.actions["Walk"]
    for fcu in hare.curves(act):
        if fcu.data_path == 'pose.bones["hips"].location' and fcu.array_index == 2:
            for kp in fcu.keyframe_points:
                if round(kp.co.x) in (1, 13, 16):
                    kp.co.y -= 0.04
                    kp.handle_left.y -= 0.04
                    kp.handle_right.y -= 0.04
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
    blend = args[0] if args else "art/monsters/лисиця.blend"
    glb = args[1] if len(args) > 1 else ""
    base.clear()
    bpy.context.scene.render.fps = 24
    mesh = load_mesh()
    orient(mesh)
    shift = level(mesh)
    simplify(mesh)
    shrink_textures(mesh)
    fur_mask(mesh)
    mesh.name = "Тіло"
    if os.environ.get("ONLY_ORIENT"):
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(blend))
        return
    skeleton = rig(mesh, shift)
    hare.actions(skeleton)
    fix_walk_ground(skeleton)
    if len(args) > 2:
        hare.previews(skeleton, args[2])
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(blend))
    print("[лисиця-скан] збережено", blend)
    if glb:
        export(os.path.abspath(glb))
        print("[лисиця-скан] експорт", glb)


if __name__ == "__main__":
    main()
