"""Паглін із сітки, зробленої за референсом (23.09.2026) — другий
гуманоїд шляхом А `spec/генерація-3d-моделей-монстрів.md`, за рішенням
П-247 (`spec/DECIDED.md`): свій простий скелет, не манекен гравця
(`make_races.py`) — той самий підхід, що дав бездоганний результат на
імпі. На заміну купленому асету `res://models/monsters/Puglin.glb`.

Звідки сітка: референс `wiki/img/monstry/паглін.png` (камера трохи
низько — передня стопа й кілок на передньому плані завеликі) → Kontext
(свій промт, `art/monsters/паглін-3d/промт-пози.txt`) → Pixal3D →
`art/monsters/паглін-3d/pixal3d-01.glb`. Сітка вже дивиться на −Y —
обертання не потрібне, лише підняти на нуль.

Запуск (з каталогу проєкту):
    blender --background --python tools/blender/make_paglin_scan.py -- \\
        art/monsters/паглін.blend game/models/own/паглін.glb
"""
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_template as base  # noqa: E402
import make_hare as hare  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SOURCE = os.path.join(ROOT, "art", "monsters", "паглін-3d", "pixal3d-01.glb")
FACES = 20000
TEXTURE = 2048

# Заміряно так само, як в імпа: Z-гістограма густини (`landmarks_paglin.py`,
# тимчасовий скрипт) + центроїди рук/ніг по боках. Мордою вже на −Y.
BONES = [
    ("hips", (0.0, 0.08, 0.32), (0.0, 0.0, 0.46), None),
    ("chest", (0.0, 0.0, 0.46), (0.0, -0.02, 0.62), "hips"),
    ("head", (0.0, -0.02, 0.62), (-0.02, -0.03, 0.72), "chest"),
    ("arm.L", (-0.1, -0.02, 0.55), (-0.2815, -0.0383, 0.4613), "chest"),
    ("arm.R", (0.15, -0.02, 0.55), (0.2871, -0.0668, 0.3119), "chest"),
    ("leg.L", (-0.08, 0.08, 0.32), (-0.1648, 0.0868, 0.0245), "hips"),
    ("leg.R", (0.12, 0.08, 0.32), (0.2015, -0.1012, 0.0278), "hips"),
    ("tail", (0.0, 0.15, 0.30), (0.0, 0.26, 0.18), "hips"),
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
    zs = [v.co.z for v in mesh.data.vertices]
    mesh.data.transform(Matrix.Translation((0, 0, -min(zs))))


def simplify(mesh):
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0005)
    bpy.ops.object.mode_set(mode="OBJECT")
    mod = mesh.modifiers.new("Спрощення", "DECIMATE")
    mod.ratio = min(1.0, FACES / len(mesh.data.polygons))
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.ops.object.shade_smooth()


def shrink_textures(mesh):
    for node in mesh.data.materials[0].node_tree.nodes:
        if node.type == "TEX_IMAGE" and node.image.size[0] > TEXTURE:
            node.image.scale(TEXTURE, TEXTURE)


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
    print("[паглін-скан] ваги за відстанню: %d вершин із %d"
          % (fixed, len(mesh.data.vertices)))


def actions(rig):
    """Idle — присідає й підстрибує; Walk — перевалюється; Attack —
    тицяє кілком уперед правою рукою; Death — падає на спину (бестіарій:
    «Падає на спину, лапи підібгані»)."""
    rest = {}
    hare.action(rig, "Idle", 32, {
        1: rest,
        8: {"leg.L": ((-8, 0, 0), (0, 0, 0)),
            "leg.R": ((-8, 0, 0), (0, 0, 0)),
            "hips": ((-5, 0, 0), (0, 0, 0))},
        16: rest,
        24: {"leg.L": ((-8, 0, 0), (0, 0, 0)),
             "leg.R": ((-8, 0, 0), (0, 0, 0)),
             "hips": ((-5, 0, 0), (0, 0, 0))},
        32: rest,
    })
    hare.action(rig, "Walk", 18, {
        1: {"leg.L": ((18, 0, 0), (0, 0, 0)),
            "leg.R": ((-18, 0, 0), (0, 0, 0)),
            "chest": ((0, 0, 5), (0, 0, 0))},
        5: rest,
        9: {"leg.L": ((-18, 0, 0), (0, 0, 0)),
            "leg.R": ((18, 0, 0), (0, 0, 0)),
            "chest": ((0, 0, -5), (0, 0, 0))},
        14: rest,
        18: {"leg.L": ((18, 0, 0), (0, 0, 0)),
             "leg.R": ((-18, 0, 0), (0, 0, 0)),
             "chest": ((0, 0, 5), (0, 0, 0))},
    })
    # arm.L тримає кілок (виміряно на сітці: «grip» на негативному X) —
    # атакувати саме нею, не порожньою arm.R.
    hare.action(rig, "Attack", 16, {
        1: rest,
        4: {"arm.L": ((-25, 0, 0), (0, 0, 0)), "chest": ((-8, 0, 0), (0, 0, 0))},
        8: {"arm.L": ((45, 0, 0), (0, -0.1, 0)), "chest": ((8, 0, 0), (0, 0, 0)),
            "head": ((-5, 0, 0), (0, 0, 0))},
        12: {"arm.L": ((10, 0, 0), (0, -0.02, 0))},
        16: rest,
    })
    hare.action(rig, "Death", 26, {
        1: rest,
        26: {"hips": ((-85, 0, 0), (0, 0, 0)),
             "head": ((25, 0, 0), (0, 0, 0)),
             "arm.L": ((15, 0, 0), (0, 0, 0)),
             "arm.R": ((15, 0, 0), (0, 0, 0)),
             "leg.L": ((-20, 0, 0), (0, 0, 0)),
             "leg.R": ((-20, 0, 0), (0, 0, 0))},
    })
    rig.animation_data.action = bpy.data.actions["Idle"]


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
    blend = args[0] if args else "art/monsters/паглін.blend"
    glb = args[1] if len(args) > 1 else ""
    base.clear()
    bpy.context.scene.render.fps = 24
    mesh = load_mesh()
    orient(mesh)
    simplify(mesh)
    shrink_textures(mesh)
    mesh.name = "Тіло"
    if os.environ.get("ONLY_ORIENT"):
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(blend))
        return
    skeleton = rig(mesh)
    actions(skeleton)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(blend))
    print("[паглін-скан] збережено", blend)
    if glb:
        export(os.path.abspath(glb))
        print("[паглін-скан] експорт", glb)


if __name__ == "__main__":
    main()
