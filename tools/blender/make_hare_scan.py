"""Заєць із сітки, зробленої за референсом (23.09.2026) — на заміну
зайцеві з куль і циліндрів (`make_hare.py`).

Слово замовника 23.09.2026: «дуже слабка початкова 3D модель, вона дуже
примітивна і має тільки формальні збіги з референсом, навіть хутро не
промальовується». Звідки сітка:

  1. референс `wiki/img/monstry/заєць.png` (заєць у стрибку) → FLUX
     Kontext переставив того самого зайця в спокійну позу на чотирьох
     лапах на сірому тлі (`art/monsters/заєць-3d/поза-s44.png`, вибір
     замовника — варіант 4 з чотирьох);
  2. з неї Pixal3D (ComfyUI, шаблон `3d_pixal3d_trellis2_image_to_model`)
     — сітка з текстурою, `art/monsters/заєць-3d/pixal3d-02.glb`.

Тут: розвернути мордою на −Y і поставити лапами на нуль, спростити до
ігрової кількості граней, зменшити текстури, посадити на скелет зайця
(ті самі імена й напрямки кісток, що в `make_hare.py`, тож і рухи звідти
ж) з автоматичними вагами. Ще пишемо маску ворсу: друга UV-розгортка,
U = «голизна» (0 — хутро, 1 — голо: очі, ніс, кігті, нутро вух). Її
читає `game/scripts/fur_shell.gdshader`; кольори вершин для цього не
годяться — Godot множить на них колір моделі.

Запуск (з каталогу проєкту):
    blender --background --python tools/blender/make_hare_scan.py -- \\
        art/monsters/заєць.blend game/models/own/заєць.glb [тека_для_картинок]
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
SOURCE = os.path.join(ROOT, "art", "monsters", "заєць-3d", "pixal3d-02.glb")
HEIGHT = 0.67          # до кінчиків вух, як у зайця з `make_hare.py`
FACES = 20000
TEXTURE = 2048

# Кістки під цю сітку: заміряно на ортографічних видах збоку й спереду
# (сітка вже розвернута й поставлена на нуль). Імена й напрямки — як у
# `make_hare.BONES`, інакше рухи звідти крутили б не те.
BONES = [
    ("hips", (0, 0.22, 0.3), (0, 0.0, 0.33), None),
    ("chest", (0, 0.0, 0.33), (0, -0.15, 0.35), "hips"),
    ("head", (0, -0.16, 0.37), (0, -0.28, 0.43), "chest"),
    ("ear.L", (0.035, -0.16, 0.5), (0.08, -0.12, 0.65), "head"),
    ("ear.R", (-0.025, -0.17, 0.5), (-0.07, -0.15, 0.65), "head"),
    ("tail", (0, 0.27, 0.24), (0, 0.31, 0.22), "hips"),
    ("front.L", (0.06, -0.12, 0.28), (0.06, -0.19, 0.03), "chest"),
    ("front.R", (-0.06, -0.12, 0.28), (-0.06, -0.19, 0.03), "chest"),
    ("hind.L", (0.09, 0.12, 0.26), (0.09, 0.2, 0.02), "hips"),
    ("hind.R", (-0.09, 0.12, 0.26), (-0.09, 0.2, 0.02), "hips"),
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
    print("[заєць-скан] голих вершин: %d із %d"
          % (int((bare > 0.5).sum()), len(bare)))


def rig(mesh):
    skeleton = hare.armature(BONES)
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
    print("[заєць-скан] ваги за відстанню: %d вершин із %d"
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
    blend = args[0] if args else "art/monsters/заєць.blend"
    glb = args[1] if len(args) > 1 else ""
    base.clear()
    bpy.context.scene.render.fps = 24
    mesh = load_mesh()
    orient(mesh)
    simplify(mesh)
    shrink_textures(mesh)
    fur_mask(mesh)
    mesh.name = "Тіло"
    skeleton = rig(mesh)
    hare.actions(skeleton)
    if len(args) > 2:
        hare.previews(skeleton, args[2])
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(blend))
    print("[заєць-скан] збережено", blend)
    if glb:
        export(os.path.abspath(glb))
        print("[заєць-скан] експорт", glb)


if __name__ == "__main__":
    main()
