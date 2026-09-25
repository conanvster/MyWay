"""Зомбі із сітки, зробленої за референсом — третій гуманоїд шляхом А
`spec/генерація-3d-моделей-монстрів.md`, за рішенням П-247
(`spec/DECIDED.md`): свій простий скелет, не манекен гравця. На заміну
процедурному рескіну людини (`humanoids.py`,
`res://models/own/humanoids/зомбі.gltf`).

Звідки сітка: референс `wiki/img/monstry/зомбі.png` — уже майже строго
анфас, звичайна перспектива, руки розведені в боки (вигідно відокремлені
від тіла) → крок пози (Kontext) пропущено, Pixal3D прямо з референсу →
`art/monsters/зомбі-3d/pixal3d-01.glb`.

Запуск (з каталогу проєкту):
    blender --background --python tools/blender/make_zombie_scan.py -- \\
        art/monsters/зомбі.blend game/models/own/зомбі.glb
"""
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_template as base  # noqa: E402
import make_hare as hare  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SOURCE = os.path.join(ROOT, "art", "monsters", "зомбі-3d", "pixal3d-01.glb")
FACES = 20000
TEXTURE = 2048

# Заміряно так само, як в імпа/паглін: Z-гістограма густини +
# центроїди рук/ніг по боках (`landmarks_zombie.py`). Мордою вже на −Y.
BONES = [
    ("hips", (0.0, 0.02, 0.28), (0.0, 0.0, 0.46), None),
    ("chest", (0.0, 0.0, 0.46), (0.0, 0.0, 0.62), "hips"),
    ("head", (0.0, 0.0, 0.62), (0.03, 0.0, 0.82), "chest"),
    ("arm.L", (-0.12, 0.0, 0.60), (-0.2459, -0.0135, 0.5161), "chest"),
    ("arm.R", (0.14, 0.0, 0.60), (0.2144, 0.1383, 0.4914), "chest"),
    ("leg.L", (-0.08, 0.02, 0.28), (-0.1439, -0.0552, 0.0175), "hips"),
    ("leg.R", (0.08, 0.02, 0.28), (0.1426, -0.0564, 0.0155), "hips"),
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
    print("[зомбі-скан] ваги за відстанню: %d вершин із %d"
          % (fixed, len(mesh.data.vertices)))


def actions(rig):
    """Idle — похитується, голова звішена; Walk — дуже повільна ходьба;
    Attack — піднімає руки й падає вперед; Death — складається на
    місці (бестіарій — тактика/анімації)."""
    rest = {}
    hare.action(rig, "Idle", 40, {
        1: rest,
        10: {"chest": ((0, 0, 4), (0, 0, 0)), "head": ((10, 0, 0), (0, 0, 0))},
        20: {"chest": ((0, 0, 0), (0, 0, 0)), "head": ((10, 0, 0), (0, 0, 0))},
        30: {"chest": ((0, 0, -4), (0, 0, 0)), "head": ((10, 0, 0), (0, 0, 0))},
        40: rest,
    })
    hare.action(rig, "Walk", 24, {
        1: {"leg.L": ((10, 0, 0), (0, 0, 0)), "leg.R": ((-6, 0, 0), (0, 0, 0)),
            "hips": ((0, 0, 3), (0, 0, 0))},
        7: rest,
        13: {"leg.L": ((-6, 0, 0), (0, 0, 0)), "leg.R": ((10, 0, 0), (0, 0, 0)),
             "hips": ((0, 0, -3), (0, 0, 0))},
        19: rest,
        24: {"leg.L": ((10, 0, 0), (0, 0, 0)), "leg.R": ((-6, 0, 0), (0, 0, 0)),
             "hips": ((0, 0, 3), (0, 0, 0))},
    })
    # Піднімає руки й падає вперед. Ліва й права кістки рук мають різний
    # природний roll (asymmetric виміряні позиції) — той самий кут дає
    # різний візуальний результат, підібрано окремо для кожної руки.
    hare.action(rig, "Attack", 22, {
        1: rest,
        6: {"arm.L": ((35, 0, 0), (0, 0, 0)), "arm.R": ((-25, 0, 0), (0, 0, 0)),
            "head": ((-10, 0, 0), (0, 0, 0))},
        12: {"arm.L": ((35, 0, 0), (0, 0, 0)), "arm.R": ((-25, 0, 0), (0, 0, 0)),
             "hips": ((25, 0, 0), (0, 0.1, 0)), "chest": ((15, 0, 0), (0, 0, 0)),
             "head": ((-15, 0, 0), (0, 0, 0))},
        17: {"arm.L": ((12, 0, 0), (0, 0, 0)), "arm.R": ((-8, 0, 0), (0, 0, 0)),
             "hips": ((5, 0, 0), (0, 0.02, 0))},
        22: rest,
    })
    hare.action(rig, "Death", 24, {
        1: rest,
        24: {"hips": ((55, 0, 0), (0, -0.05, -0.1)),
             "chest": ((30, 0, 0), (0, 0, 0)),
             "head": ((20, 0, 0), (0, 0, 0)),
             "arm.L": ((10, 0, 0), (0, 0, 0)),
             "arm.R": ((10, 0, 0), (0, 0, 0)),
             "leg.L": ((-25, 0, 0), (0, 0, 0)),
             "leg.R": ((-25, 0, 0), (0, 0, 0))},
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
    blend = args[0] if args else "art/monsters/зомбі.blend"
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
    print("[зомбі-скан] збережено", blend)
    if glb:
        export(os.path.abspath(glb))
        print("[зомбі-скан] експорт", glb)


if __name__ == "__main__":
    main()
