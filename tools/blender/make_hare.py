"""Заєць для гри (П-15) — чотирилапий, скелет на 11 кісток, рухи Idle,
Walk (стрибок), Attack (стає дибки й «боксує», як зайці навесні),
Death.

Замовник 19.09.2026: «відкрий заготовку в Blender — спробуй намалювати
зайця». Тіло — ті самі прості фігури на кістках, що й у заготовці
(`make_template.py`), тож форму можна доліплювати руками, і рухи не
зламаються. Перед — на −Y, ноги на нулі.

Запуск (з каталогу проєкту):
    blender --background --python tools/blender/make_hare.py -- \\
        art/monsters/заєць.blend [тека_для_картинок]
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_template as base  # noqa: E402

BONES = [
    ("hips", (0, 0.13, 0.23), (0, -0.02, 0.26), None),
    ("chest", (0, -0.02, 0.26), (0, -0.15, 0.28), "hips"),
    ("head", (0, -0.16, 0.3), (0, -0.27, 0.37), "chest"),
    ("ear.L", (0.03, -0.19, 0.42), (0.05, -0.13, 0.63), "head"),
    ("ear.R", (-0.03, -0.19, 0.42), (-0.05, -0.13, 0.63), "head"),
    ("tail", (0, 0.17, 0.24), (0, 0.22, 0.27), "hips"),
    ("front.L", (0.05, -0.13, 0.2), (0.05, -0.15, 0.01), "chest"),
    ("front.R", (-0.05, -0.13, 0.2), (-0.05, -0.15, 0.01), "chest"),
    ("hind.L", (0.08, 0.09, 0.22), (0.08, 0.04, 0.01), "hips"),
    ("hind.R", (-0.08, 0.09, 0.22), (-0.08, 0.04, 0.01), "hips"),
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
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


def body(rig):
    fur = base.material("Хутро", (0.34, 0.2, 0.1))
    light = base.material("Світле", (0.8, 0.76, 0.7))
    pink = base.material("Рожеве", (0.75, 0.35, 0.35))
    dark = base.material("Очі", (0.01, 0.01, 0.01))
    p = base.part
    tilt = (math.radians(-18), 0, 0)
    parts = [
        p("sphere", "hips", (0, 0.03, 0.24), (0.12, 0.19, 0.12), fur),
        p("sphere", "hips", (0, -0.01, 0.18), (0.09, 0.14, 0.07), light),
        p("sphere", "chest", (0, -0.12, 0.26), (0.09, 0.09, 0.1), fur),
        p("sphere", "hind.L", (0.08, 0.09, 0.2), (0.055, 0.09, 0.09), fur),
        p("sphere", "hind.R", (-0.08, 0.09, 0.2), (0.055, 0.09, 0.09), fur),
        # Гомілка: від стегна до стопи, інакше стопа висить окремо.
        p("cyl", "hind.L", (0.08, 0.055, 0.075), (0.024, 0.024, 0.065), fur,
          (math.radians(-25), 0, 0)),
        p("cyl", "hind.R", (-0.08, 0.055, 0.075), (0.024, 0.024, 0.065),
          fur, (math.radians(-25), 0, 0)),
        p("sphere", "hind.L", (0.08, 0.01, 0.02), (0.03, 0.085, 0.02), fur),
        p("sphere", "hind.R", (-0.08, 0.01, 0.02), (0.03, 0.085, 0.02), fur),
        p("cyl", "front.L", (0.05, -0.14, 0.1), (0.022, 0.022, 0.1), fur),
        p("cyl", "front.R", (-0.05, -0.14, 0.1), (0.022, 0.022, 0.1), fur),
        p("sphere", "front.L", (0.05, -0.16, 0.015), (0.025, 0.035, 0.018),
          fur),
        p("sphere", "front.R", (-0.05, -0.16, 0.015), (0.025, 0.035, 0.018),
          fur),
        p("sphere", "head", (0, -0.22, 0.35), (0.07, 0.095, 0.075), fur),
        p("sphere", "head", (0, -0.28, 0.33), (0.045, 0.04, 0.035), light),
        p("sphere", "head", (0.045, -0.265, 0.375), (0.016, 0.014, 0.018),
          dark),
        p("sphere", "head", (-0.045, -0.265, 0.375), (0.016, 0.014, 0.018),
          dark),
        p("sphere", "head", (0, -0.315, 0.345), (0.013, 0.01, 0.01), pink),
        p("sphere", "ear.L", (0.04, -0.165, 0.52), (0.024, 0.012, 0.11),
          fur, tilt),
        p("sphere", "ear.R", (-0.04, -0.165, 0.52), (0.024, 0.012, 0.11),
          fur, tilt),
        p("sphere", "ear.L", (0.04, -0.176, 0.52), (0.015, 0.004, 0.085),
          pink, tilt),
        p("sphere", "ear.R", (-0.04, -0.176, 0.52), (0.015, 0.004, 0.085),
          pink, tilt),
        p("sphere", "tail", (0, 0.21, 0.26), (0.04, 0.04, 0.04), light),
    ]
    for obj in parts:
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.shade_smooth()
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


def pose(rig, frame, bone, rot=(0, 0, 0), loc=(0, 0, 0)):
    b = rig.pose.bones[bone]
    b.rotation_mode = "XYZ"
    b.rotation_euler = [math.radians(a) for a in rot]
    b.location = loc
    b.keyframe_insert("rotation_euler", frame=frame)
    b.keyframe_insert("location", frame=frame)


def action(rig, name, frames, keys):
    """keys: {кадр: {кістка: (обертання°, зсув)}}; не названа кістка в
    ключовому кадрі стоїть рівно."""
    rig.animation_data_create()
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    rig.animation_data.action = act
    for frame, bones in keys.items():
        for bone in rig.pose.bones:
            rot, loc = bones.get(bone.name, ((0, 0, 0), (0, 0, 0)))
            pose(rig, frame, bone.name, rot, loc)
    act.frame_range = (1, frames)
    return act


def actions(rig):
    rest = {}
    # Idle, 48 кадрів: вуха смикаються по черзі, голова ледь киває.
    action(rig, "Idle", 48, {
        1: rest,
        8: {"ear.L": ((-18, 0, 0), (0, 0, 0))},
        14: rest,
        26: {"ear.R": ((-18, 0, 0), (0, 0, 0)),
             "head": ((6, 0, 0), (0, 0, 0))},
        34: {"head": ((6, 0, 0), (0, 0, 0))},
        48: rest,
    })
    # Walk — стрибок, 16 кадрів: присів → відштовхнувся задніми →
    # летить із витягнутими передніми → приземлився.
    action(rig, "Walk", 16, {
        1: {"hips": ((0, 0, 0), (0, 0, -0.03)),
            "hind.L": ((-25, 0, 0), (0, 0, 0)),
            "hind.R": ((-25, 0, 0), (0, 0, 0)),
            "front.L": ((20, 0, 0), (0, 0, 0)),
            "front.R": ((20, 0, 0), (0, 0, 0))},
        5: {"hips": ((-10, 0, 0), (0, 0, 0.05)),
            "hind.L": ((45, 0, 0), (0, 0, 0)),
            "hind.R": ((45, 0, 0), (0, 0, 0)),
            "front.L": ((-30, 0, 0), (0, 0, 0)),
            "front.R": ((-30, 0, 0), (0, 0, 0)),
            "ear.L": ((20, 0, 0), (0, 0, 0)),
            "ear.R": ((20, 0, 0), (0, 0, 0))},
        9: {"hips": ((5, 0, 0), (0, 0, 0.09)),
            "hind.L": ((35, 0, 0), (0, 0, 0)),
            "hind.R": ((35, 0, 0), (0, 0, 0)),
            "front.L": ((-50, 0, 0), (0, 0, 0)),
            "front.R": ((-50, 0, 0), (0, 0, 0)),
            "ear.L": ((30, 0, 0), (0, 0, 0)),
            "ear.R": ((30, 0, 0), (0, 0, 0))},
        13: {"hips": ((8, 0, 0), (0, 0, 0.02)),
             "hind.L": ((-10, 0, 0), (0, 0, 0)),
             "hind.R": ((-10, 0, 0), (0, 0, 0)),
             "front.L": ((10, 0, 0), (0, 0, 0)),
             "front.R": ((10, 0, 0), (0, 0, 0))},
        16: {"hips": ((0, 0, 0), (0, 0, -0.03)),
             "hind.L": ((-25, 0, 0), (0, 0, 0)),
             "hind.R": ((-25, 0, 0), (0, 0, 0)),
             "front.L": ((20, 0, 0), (0, 0, 0)),
             "front.R": ((20, 0, 0), (0, 0, 0))},
    })
    # Attack, 16 кадрів: дибки — і лівою-правою, як зайці боксують.
    # Кістка тулуба дивиться на −Y: «+» по X опускає морду (видно на
    # рендері), тож дибки — «−».
    up = ((-45, 0, 0), (0, 0, 0))
    # Задні лапи крутяться разом із тулубом — повертаємо їх назад на
    # той самий кут, щоб стояли на землі.
    stand = ((45, 0, 0), (0, 0, 0))
    boxing = {"hips": up, "hind.L": stand, "hind.R": stand,
              "head": ((25, 0, 0), (0, 0, 0))}
    action(rig, "Attack", 16, {
        1: rest,
        5: {**boxing, "front.L": ((-70, 0, 0), (0, 0, 0)),
            "front.R": ((-40, 0, 0), (0, 0, 0))},
        9: {**boxing, "front.L": ((-30, 0, 0), (0, 0, 0)),
            "front.R": ((-95, 0, 0), (0, 0, 0))},
        12: {**boxing, "front.L": ((-95, 0, 0), (0, 0, 0)),
             "front.R": ((-30, 0, 0), (0, 0, 0))},
        16: rest,
    })
    # Death, 30 кадрів: завалюється на бік, лапи обм'якли.
    action(rig, "Death", 30, {
        1: rest,
        30: {"hips": ((0, 85, 0), (0, 0, -0.06)),
             "head": ((20, 0, 0), (0, 0, 0)),
             "ear.L": ((25, 0, 0), (0, 0, 0)),
             "ear.R": ((25, 0, 0), (0, 0, 0)),
             "front.L": ((-25, 0, 0), (0, 0, 0)),
             "hind.L": ((30, 0, 0), (0, 0, 0))},
    })
    rig.animation_data.action = bpy.data.actions["Idle"]


def previews(rig, folder):
    """Кадри для перевірки оком: спокій, стрибок, бокс, смерть."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.light = "STUDIO"
    scene.render.resolution_x = 480
    scene.render.resolution_y = 360
    cam_data = bpy.data.cameras.new("Камера")
    cam = bpy.data.objects.new("Камера", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.location = (1.2, -1.35, 0.62)
    cam.rotation_euler = (math.radians(76), 0, math.radians(42))
    cam_data.lens = 50
    shots = [("Idle", 1), ("Walk", 1), ("Walk", 5), ("Walk", 9),
             ("Attack", 9), ("Death", 30)]
    for name, frame in shots:
        rig.animation_data.action = bpy.data.actions[name]
        scene.frame_set(frame)
        scene.render.filepath = os.path.join(folder, "%s-%02d.png"
                                             % (name, frame))
        bpy.ops.render.render(write_still=True)
    rig.animation_data.action = bpy.data.actions["Idle"]
    scene.frame_set(1)
    bpy.data.objects.remove(cam)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = args[0] if args else "art/monsters/заєць.blend"
    base.clear()
    bpy.context.scene.render.fps = 24
    rig = armature()
    body(rig)
    actions(rig)
    if len(args) > 1:
        previews(rig, args[1])
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(out))
    print("[заєць] збережено", out)


if __name__ == "__main__":
    main()
