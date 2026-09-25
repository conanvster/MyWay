"""Імп із сітки, зробленої за референсом (23.09.2026) — перший гуманоїд
шляхом А `spec/генерація-3d-моделей-монстрів.md`, на заміну процедурному
рескіну людини (`humanoids.py`, SPECIES="імп"), який замовника не
задовольнив (надто примітивний, лише формальний збіг).

Свій, простий скелет (8 кісток: hips/chest/head/arm.L-R/leg.L-R/tail) —
а не переспаджений манекен гравця (`make_races.py`): манекен у T-позі, а
скан — у природній позі з референсу (руки розведені, не горизонтально),
і пряме нав'язування анімацій бібліотеки людини на скан дало б розсинхрон
пози прив'язки з рухами бібліотеки. Власний скелет під ЦЮ сітку — той
самий підхід, що й у вовка/кажана/скорпіона.

Звідки сітка: референс `wiki/img/monstry/імп.png` (камера дуже низько й
близько — кисті на передньому плані величезні) → Kontext (свій промт,
`art/monsters/імп-3d/промт-пози.txt`, «звичайна перспектива, повний
зріст») → Pixal3D → `art/monsters/імп-3d/pixal3d-01.glb`. Сітка вже
дивиться на −Y і стоїть у природній позі — обертання не потрібне, лише
підняти на нуль.

Запуск (з каталогу проєкту):
    blender --background --python tools/blender/make_imp_scan.py -- \\
        art/monsters/імп.blend game/models/own/імп.glb [тека_для_картинок]
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_template as base  # noqa: E402
import make_hare as hare  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SOURCE = os.path.join(ROOT, "art", "monsters", "імп-3d", "pixal3d-01.glb")
FACES = 20000
TEXTURE = 2048

# Заміряно на сирій сітці (лог `landmarks_imp.py`, розділ 7 у
# art/monsters/імп-3d/лог.md): Z-гістограма густини (тіло/роги — окремо,
# роги рідкі) і центроїди рук/ніг по боках X. Мордою вже на −Y (перевірено
# рендером спереду) — лише підняти ступні на нуль (`orient`, без повороту).
BONES = [
    ("hips", (0.0, 0.09, 0.40), (0.0, 0.02, 0.55), None),
    ("chest", (0.0, 0.02, 0.55), (0.02, -0.02, 0.74), "hips"),
    ("head", (0.02, -0.02, 0.74), (0.05, 0.0, 0.90), "chest"),
    ("arm.L", (-0.08, -0.02, 0.72), (-0.233, -0.053, 0.247), "chest"),
    ("arm.R", (0.14, -0.02, 0.72), (0.293, 0.119, 0.278), "chest"),
    ("leg.L", (-0.06, 0.09, 0.40), (-0.106, -0.007, 0.037), "hips"),
    ("leg.R", (0.12, 0.09, 0.40), (0.210, 0.114, 0.032), "hips"),
    ("tail", (0.0, 0.16, 0.40), (-0.317, 0.094, 0.044), "hips"),
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
    """Уже дивиться на −Y (перевірено рендером із чотирьох боків) —
    підняти ступні на Z = 0, без повороту й без перемасштабування (свій
    скелет під цю саме сітку, довільні одиниці — гра підганяє «зріст»)."""
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
    """Вершинам без ваги (кігті, роги — окремі клапті) — 1/d⁴ до двох
    найближчих кісток (той самий трюк, що у вовка/кажана)."""
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
    print("[імп-скан] ваги за відстанню: %d вершин із %d"
          % (fixed, len(mesh.data.vertices)))


def actions(rig):
    """Idle/Walk/Attack/Death — прості обертання іменованих кісток
    (`hare.pose`/`hare.action`), без зсуву стегон (`UP_IN_HIPS` заточено
    під горизонтальну кістку hips вовка/зайця, у імпа вона вертикальна —
    не переноситься)."""
    rest = {}
    hare.action(rig, "Idle", 48, {
        1: rest,
        12: {"tail": ((0, 0, 10), (0, 0, 0)),
             "head": ((3, 0, 0), (0, 0, 0))},
        24: {"tail": ((0, 0, -10), (0, 0, 0))},
        36: {"tail": ((0, 0, 10), (0, 0, 0)),
             "head": ((3, 0, 0), (0, 0, 0))},
        48: rest,
    })
    hare.action(rig, "Walk", 16, {
        1: {"leg.L": ((25, 0, 0), (0, 0, 0)),
            "leg.R": ((-25, 0, 0), (0, 0, 0)),
            "arm.L": ((-15, 0, 0), (0, 0, 0)),
            "arm.R": ((15, 0, 0), (0, 0, 0)),
            "chest": ((0, 0, 6), (0, 0, 0))},
        5: {"leg.L": ((0, 0, 0), (0, 0, 0)),
            "leg.R": ((0, 0, 0), (0, 0, 0)),
            "arm.L": ((0, 0, 0), (0, 0, 0)),
            "arm.R": ((0, 0, 0), (0, 0, 0))},
        9: {"leg.L": ((-25, 0, 0), (0, 0, 0)),
            "leg.R": ((25, 0, 0), (0, 0, 0)),
            "arm.L": ((15, 0, 0), (0, 0, 0)),
            "arm.R": ((-15, 0, 0), (0, 0, 0)),
            "chest": ((0, 0, -6), (0, 0, 0))},
        13: {"leg.L": ((0, 0, 0), (0, 0, 0)),
             "leg.R": ((0, 0, 0), (0, 0, 0)),
             "arm.L": ((0, 0, 0), (0, 0, 0)),
             "arm.R": ((0, 0, 0), (0, 0, 0))},
        16: {"leg.L": ((25, 0, 0), (0, 0, 0)),
             "leg.R": ((-25, 0, 0), (0, 0, 0)),
             "arm.L": ((-15, 0, 0), (0, 0, 0)),
             "arm.R": ((15, 0, 0), (0, 0, 0)),
             "chest": ((0, 0, 6), (0, 0, 0))},
    })
    # Атака: замах пазурами правою рукою (тулуб не крутити — на цьому
    # скелеті chest-обертання ховало голову, спроба-01).
    hare.action(rig, "Attack", 20, {
        1: rest,
        5: {"arm.R": ((-35, 0, -10), (0, 0, 0)),
            "tail": ((0, 0, -12), (0, 0, 0))},
        9: {"arm.R": ((30, 0, 15), (0, 0, 0)),
            "head": ((-5, 0, 0), (0, 0, 0)),
            "tail": ((0, 0, 15), (0, 0, 0))},
        13: {"arm.R": ((10, 0, 5), (0, 0, 0))},
        20: rest,
    })
    # Смерть: падає на спину, кігті обм'якли.
    hare.action(rig, "Death", 30, {
        1: rest,
        30: {"hips": ((-80, 0, 0), (0, 0, 0)),
             "head": ((30, 0, 0), (0, 0, 0)),
             "arm.L": ((20, 0, 0), (0, 0, 0)),
             "arm.R": ((20, 0, 0), (0, 0, 0)),
             "leg.L": ((-15, 0, 0), (0, 0, 0)),
             "leg.R": ((-15, 0, 0), (0, 0, 0)),
             "tail": ((0, 0, 0), (0, 0, 0))},
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
    blend = args[0] if args else "art/monsters/імп.blend"
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
    print("[імп-скан] збережено", blend)
    if glb:
        export(os.path.abspath(glb))
        print("[імп-скан] експорт", glb)


if __name__ == "__main__":
    main()
