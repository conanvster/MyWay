"""Вовк із сітки, зробленої за референсом (23.09.2026) — на заміну вовкові
з куль і циліндрів (`make_wolf.py`), за шляхом А
`spec/генерація-3d-моделей-монстрів.md`.

Звідки сітка: референс `wiki/img/monstry/вовк.png` — вовк уже стоїть на
всіх чотирьох лапах у три чверті, тож крок пози (Kontext) пропущено;
Pixal3D (ComfyUI) прямо з референсу → `art/monsters/вовк-3d/pixal3d-01.glb`.

Тут те саме, що в `make_hare_scan.py`: розвернути мордою на −Y, лапами
на нуль, спростити, зменшити текстури, маска ворсу в другій UV, скелет з
іменами й напрямками `make_wolf.BONES` (з щелепою `jaw`) і рухи з
`make_wolf.actions()`.

Запуск (з каталогу проєкту):
    blender --background --python tools/blender/make_wolf_scan.py -- \\
        art/monsters/вовк.blend game/models/own/вовк.glb [тека_для_картинок]
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
import make_wolf as wolf  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SOURCE = os.path.join(ROOT, "art", "monsters", "вовк-3d", "pixal3d-01.glb")
HEIGHT = 1.04          # до кінчиків вух, як у вовка з `make_wolf.py`
FACES = 20000
TEXTURE = 2048

# Кістки під цю сітку: заміряно на ортографічних видах (2 м у кадрі) і
# центрами вершин лап по висоті (сітка вже розвернута, вирівняна й на
# нулі). Імена й напрямки — як у `make_wolf.BONES`, інакше рухи звідти
# крутили б не те. Голова на референсі повернута до глядача — тому вона
# й ліві/праві лапи не симетричні відносно X = 0.
BONES = [
    ("hips", (-0.04, 0.35, 0.78), (-0.04, 0.0, 0.8), None),
    ("chest", (-0.04, 0.0, 0.8), (-0.05, -0.4, 0.82), "hips"),
    ("head", (-0.07, -0.62, 0.7), (-0.137, -0.86, 0.56), "chest"),
    ("jaw", (-0.1, -0.74, 0.54), (-0.13, -0.86, 0.5), "head"),
    ("ear.L", (-0.01, -0.78, 0.76), (0.0, -0.78, 0.86), "head"),
    ("ear.R", (-0.2, -0.76, 0.76), (-0.22, -0.76, 0.86), "head"),
    ("tail", (-0.07, 0.42, 0.8), (-0.1, 0.52, 0.15), "hips"),
    ("front.L", (0.055, -0.33, 0.68), (0.058, -0.38, 0.03), "chest"),
    ("front.R", (-0.145, -0.32, 0.68), (-0.18, -0.34, 0.03), "chest"),
    ("hind.L", (0.07, 0.15, 0.68), (0.09, 0.17, 0.03), "hips"),
    ("hind.R", (-0.13, 0.15, 0.68), (-0.113, 0.19, 0.03), "hips"),
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
    """Pixal3D ставить вовка з нахилом (перспектива арту): після `orient`
    передні лапи висіли ~8 см над землею. Нахилити й покрутити так, щоб
    найнижчі точки чотирьох лап (квадранти навколо центру, без смуги
    хвоста посередині) лягли на одну площину, тоді знов на нуль і в
    HEIGHT."""
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
    front = [feet[(s, False)] for s in (False, True)]
    hind = [feet[(s, True)] for s in (False, True)]
    right = [feet[(False, b)] for b in (False, True)]
    left = [feet[(True, b)] for b in (False, True)]

    def mid(pair):
        return sum(pair, Vector()) / 2

    f, b = mid(front), mid(hind)
    pitch = math.atan2(f.z - b.z, b.y - f.y)
    r, l = mid(right), mid(left)
    roll = math.atan2(l.z - r.z, l.x - r.x)
    mesh.data.transform(Matrix.Rotation(pitch, 4, "X"))
    mesh.data.transform(Matrix.Rotation(roll, 4, "Y"))
    print("[вовк-скан] вирівняно: тангаж %.1f°, крен %.1f°"
          % (math.degrees(pitch), math.degrees(roll)))
    zs = [v.co.z for v in mesh.data.vertices]
    scale = HEIGHT / (max(zs) - min(zs))
    mesh.data.transform(Matrix.Scale(scale, 4)
                        @ Matrix.Translation((0, 0, -min(zs))))
    # Центр — посередині габариту від носа до хвоста, а не в центрі
    # тулуба: морда в вовка довга, і `fur_look` (камера на початок
    # координат) обрізав її краєм кадру.
    ys = [v.co.y for v in mesh.data.vertices]
    shift = (max(ys) + min(ys)) / 2
    mesh.data.transform(Matrix.Translation((0, -shift, 0)))
    print("[вовк-скан] зсув уздовж тулуба: %.3f м" % shift)
    return shift


def simplify(mesh):
    # Генератор розрізає сітку по швах UV на острівці — зварити вершини
    # (UV від цього не страждають, вони в кутах граней). Без цього і
    # спрощення рве шви, і ваги «теплом» не знаходять розв'язку.
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0005)
    bpy.ops.object.mode_set(mode="OBJECT")
    mod = mesh.modifiers.new("Спрощення", "DECIMATE")
    mod.ratio = FACES / len(mesh.data.polygons)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    # Шви між клаптями UV після спрощення рвуть нормалі — згладити.
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
    """Друга UV: U = голизна. Колір під вершиною з текстури: рожеве
    (нутро вух, ніс) і майже чорне (очі, кігті) — голе, решта в хутрі."""
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
        # Рожеве від бурого — за синім: у рожевого він ~ як зелений,
        # у бурої шерсті помітно менший.
        pink = r > 0.3 and r > 1.45 * g and b > 0.85 * g
        dark = light < 0.06
        bare[loop.vertex_index] += 1.0 if (pink or dark) else 0.0
        seen[loop.vertex_index] += 1
    bare = bare / np.maximum(seen, 1)
    mask = me.uv_layers.new(name="Голизна")
    for loop in me.loops:
        mask.data[loop.index].uv = (float(bare[loop.vertex_index]), 0.0)
    me.uv_layers.active_index = 0
    print("[вовк-скан] голих вершин: %d із %d"
          % (int((bare > 0.5).sum()), len(bare)))


def rig(mesh, shift):
    """BONES заміряно до центрування (`level`) — зсунути так само."""
    moved = [(name, (h[0], h[1] - shift, h[2]), (t[0], t[1] - shift, t[2]),
              parent) for name, h, t, parent in BONES]
    skeleton = hare.armature(moved)
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    skeleton.select_set(True)
    bpy.context.view_layer.objects.active = skeleton
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    by_distance(mesh, skeleton)
    return skeleton


def by_distance(mesh, skeleton):
    """Вершинам, яким «тепло» не дало ваги (окремі клапті: вуса, кігті),
    — ваги за відстанню до кісток: 1/d⁴, дві найближчі кістки."""
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
    print("[вовк-скан] ваги за відстанню: %d вершин із %d"
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
    blend = args[0] if args else "art/monsters/вовк.blend"
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
        # Для розстановки кісток: лише розвернута сітка, без скелета.
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(blend))
        return
    skeleton = rig(mesh, shift)
    wolf.actions(skeleton)
    if len(args) > 2:
        hare.previews(skeleton, args[2], zoom=1.9)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(blend))
    print("[вовк-скан] збережено", blend)
    if glb:
        export(os.path.abspath(glb))
        print("[вовк-скан] експорт", glb)


if __name__ == "__main__":
    main()
