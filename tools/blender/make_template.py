"""Заготовка монстра для Blender: тіло, скелет, чотири названі рухи.

Замовник 19.09.2026: «у нас недостатньо моделей монстрів — хочу спробувати
намалювати» — малює сам. Заготовка знімає з нього все, що не малювання:
скелет уже прив'язаний, рухи Idle/Walk/Attack/Death уже названі так, як
їх шукає гра (`skinned_model.gd`), а перед моделі — там, де його чекає
Blender (дивиться на −Y, «Front» на Numpad 1).

Тіло зібране з простих фігур, кожна намертво прив'язана до своєї
кістки (група вершин з вагою 1). Тож можна міняти форму як завгодно —
ліпити, додавати, фарбувати — і рухи лишаються робочими.

Запуск (з каталогу проєкту):
    blender --background --python tools/blender/make_template.py -- \\
        art/monsters/заготовка.blend
"""
import math
import sys

import bpy


def out_path():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return args[0] if args else "art/monsters/заготовка.blend"


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, rgb):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.7
    # Колір і для вікна Blender (режим Solid), не лише для рендера й гри.
    mat.diffuse_color = (*rgb, 1.0)
    return mat


# Кістки: ім'я, голова, хвіст, батько. Метри, вгору — Z, перед — −Y.
BONES = [
    ("hips", (0, 0, 0.85), (0, 0, 1.05), None),
    ("spine", (0, 0, 1.05), (0, 0, 1.4), "hips"),
    ("head", (0, 0, 1.4), (0, 0, 1.75), "spine"),
    ("arm.L", (0.26, 0, 1.35), (0.5, 0, 0.9), "spine"),
    ("arm.R", (-0.26, 0, 1.35), (-0.5, 0, 0.9), "spine"),
    ("leg.L", (0.13, 0, 0.85), (0.13, 0, 0.05), "hips"),
    ("leg.R", (-0.13, 0, 0.85), (-0.13, 0, 0.05), "hips"),
]


def armature():
    data = bpy.data.armatures.new("Скелет")
    rig = bpy.data.objects.new("Скелет", data)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for name, head, tail, parent in BONES:
        bone = data.edit_bones.new(name)
        bone.head = head
        bone.tail = tail
        if parent:
            bone.parent = data.edit_bones[parent]
            bone.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


def part(kind, bone, at, size, mat, rotate=(0, 0, 0)):
    """Одна фігура тіла, уся — на одній кістці."""
    if kind == "sphere":
        bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=10,
                                             location=at, rotation=rotate)
    elif kind == "cone":
        bpy.ops.mesh.primitive_cone_add(vertices=10, location=at,
                                        rotation=rotate, radius2=0.25)
    else:
        bpy.ops.mesh.primitive_cylinder_add(vertices=12, location=at,
                                            rotation=rotate)
    obj = bpy.context.active_object
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    obj.data.materials.append(mat)
    return obj


def body(rig):
    skin = material("Шкіра", (0.36, 0.5, 0.28))
    eye = material("Очі", (0.95, 0.8, 0.15))
    parts = [
        part("sphere", "hips", (0, 0, 0.95), (0.24, 0.2, 0.18), skin),
        part("sphere", "spine", (0, 0, 1.22), (0.28, 0.22, 0.26), skin),
        part("sphere", "head", (0, 0, 1.55), (0.19, 0.19, 0.2), skin),
        # Очі й ніс — спереду, на −Y: по них видно, куди дивиться.
        part("sphere", "head", (0.07, -0.17, 1.6), (0.04, 0.03, 0.04), eye),
        part("sphere", "head", (-0.07, -0.17, 1.6), (0.04, 0.03, 0.04), eye),
        part("sphere", "head", (0, -0.2, 1.52), (0.05, 0.07, 0.05), skin),
        part("cyl", "arm.L", (0.38, 0, 1.12), (0.06, 0.06, 0.26), skin,
             (0, math.radians(-28), 0)),
        part("cyl", "arm.R", (-0.38, 0, 1.12), (0.06, 0.06, 0.26), skin,
             (0, math.radians(28), 0)),
        part("cyl", "leg.L", (0.13, 0, 0.45), (0.08, 0.08, 0.42), skin),
        part("cyl", "leg.R", (-0.13, 0, 0.45), (0.08, 0.08, 0.42), skin),
    ]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    mesh = bpy.context.active_object
    mesh.name = "Тіло"
    mesh.parent = rig
    mod = mesh.modifiers.new("Скелет", "ARMATURE")
    mod.object = rig
    return mesh


def key(rig, frame, bone, angle_deg, axis="X", lift=None):
    pose = rig.pose.bones[bone]
    pose.rotation_mode = "XYZ"
    euler = [0.0, 0.0, 0.0]
    euler["XYZ".index(axis)] = math.radians(angle_deg)
    pose.rotation_euler = euler
    pose.keyframe_insert("rotation_euler", frame=frame)
    if lift is not None:
        pose.location = (0.0, lift, 0.0)
        pose.keyframe_insert("location", frame=frame)


def action(rig, name, frames, poses):
    """poses: {кадр: [(кістка, кут, вісь[, підйом])...]}."""
    rig.animation_data_create()
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    rig.animation_data.action = act
    for bone in rig.pose.bones:
        bone.rotation_mode = "XYZ"
        bone.rotation_euler = (0, 0, 0)
        bone.location = (0, 0, 0)
    for frame, keys in poses.items():
        for one in keys:
            key(rig, frame, *one)
    act.frame_range = (1, frames)
    return act


def actions(rig):
    # Idle: дихає — тулуб і голова ледь хитаються; 48 кадрів = 2 с.
    action(rig, "Idle", 48, {
        1: [("spine", 0), ("head", 0)],
        24: [("spine", 4), ("head", -4)],
        48: [("spine", 0), ("head", 0)],
    })
    # Walk: ноги й руки навперемін; 24 кадри = 1 с на два кроки.
    action(rig, "Walk", 24, {
        1: [("leg.L", 30), ("leg.R", -30), ("arm.L", -25), ("arm.R", 25)],
        12: [("leg.L", -30), ("leg.R", 30), ("arm.L", 25), ("arm.R", -25)],
        24: [("leg.L", 30), ("leg.R", -30), ("arm.L", -25), ("arm.R", 25)],
    })
    # Attack: замах правою і удар уперед; 20 кадрів.
    action(rig, "Attack", 20, {
        1: [("arm.R", 0), ("spine", 0)],
        8: [("arm.R", 110), ("spine", 12)],
        13: [("arm.R", -60), ("spine", -18)],
        20: [("arm.R", 0), ("spine", 0)],
    })
    # Death: валиться вперед; 30 кадрів, не в петлі.
    action(rig, "Death", 30, {
        1: [("hips", 0, "X", 0.0)],
        30: [("hips", -85, "X", 0.0)],
    })
    rig.animation_data.action = bpy.data.actions["Idle"]


def main():
    clear()
    scene = bpy.context.scene
    scene.render.fps = 24
    rig = armature()
    body(rig)
    actions(rig)
    path = out_path()
    bpy.ops.wm.save_as_mainfile(filepath=bpy.path.abspath("//") + path
                                if not path.startswith("/") else path)
    print("[заготовка] збережено", path)


if __name__ == "__main__":
    main()
