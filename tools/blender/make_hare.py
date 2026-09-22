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

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

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


def armature(bones=None):
    """Скелет з переліку (ім'я, голова, хвіст, батько). Спільний для
    чотирилапих: вовк і ведмідь беруть звідси все, крім форми."""
    bones = bones or BONES
    data = bpy.data.armatures.new("Скелет")
    rig = bpy.data.objects.new("Скелет", data)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for name, head, tail, parent in bones:
        bone = data.edit_bones.new(name)
        bone.head = head
        bone.tail = tail
        if parent:
            bone.parent = data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


def join_parts(rig, parts):
    """Гладко затінити, з'єднати в одне тіло й прив'язати до скелета."""
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


def fur(name, rgb, picture):
    """Матеріал хутра з картинок `fur_texture.py`."""
    tex = os.path.join(ROOT, "art", "monsters", "textures")
    return base.material(name, rgb, os.path.join(tex, picture + ".png"),
                         os.path.join(tex, "хутро-нормаль.png"))


def body(rig):
    tex = os.path.join(ROOT, "art", "monsters", "textures")
    bump = os.path.join(tex, "хутро-нормаль.png")
    # Палеве, як на референсі (wiki/img/monstry/заєць.png) і моб #b08050.
    fur = base.material("Хутро", (0.62, 0.49, 0.34),
                        os.path.join(tex, "хутро-рисяче.png"), bump,
                        normal_strength=2.5)
    light = base.material("Світле", (0.8, 0.76, 0.7),
                          os.path.join(tex, "хутро-світле.png"), bump,
                          normal_strength=2.5)
    pink = base.material("Рожеве", (0.85, 0.45, 0.35))
    dark = base.material("Очі", (0.01, 0.01, 0.01))
    nose = base.material("Ніс", (0.15, 0.08, 0.05))
    tips = base.material("Кінчики", (0.05, 0.04, 0.035))
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
        # Голова трохи видовжена, писок уперед — як на референсі.
        p("sphere", "head", (0, -0.225, 0.35), (0.067, 0.105, 0.074), fur),
        p("sphere", "head", (0, -0.29, 0.332), (0.043, 0.045, 0.035), light),
        # Очі великі, по боках голови, у світлому обідку.
        p("sphere", "head", (0.05, -0.255, 0.372), (0.024, 0.024, 0.026),
          light),
        p("sphere", "head", (-0.05, -0.255, 0.372), (0.024, 0.024, 0.026),
          light),
        p("sphere", "head", (0.056, -0.258, 0.374), (0.02, 0.019, 0.021),
          dark),
        p("sphere", "head", (-0.056, -0.258, 0.374), (0.02, 0.019, 0.021),
          dark),
        p("sphere", "head", (0, -0.33, 0.345), (0.013, 0.01, 0.01), nose),
        # Вуха — широкі «ложки» з чорними кінчиками.
        p("sphere", "ear.L", (0.04, -0.165, 0.535), (0.034, 0.012, 0.13),
          fur, tilt),
        p("sphere", "ear.R", (-0.04, -0.165, 0.535), (0.034, 0.012, 0.13),
          fur, tilt),
        p("sphere", "ear.L", (0.04, -0.176, 0.53), (0.024, 0.004, 0.1),
          pink, tilt),
        p("sphere", "ear.R", (-0.04, -0.176, 0.53), (0.024, 0.004, 0.1),
          pink, tilt),
        p("sphere", "ear.L", (0.04, -0.134, 0.63), (0.024, 0.0135, 0.037),
          tips, tilt),
        p("sphere", "ear.R", (-0.04, -0.134, 0.63), (0.024, 0.0135, 0.037),
          tips, tilt),
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


## Власна вісь Z кістки тулуба дивиться ВНИЗ (заміряно: (0, −0,2, −0,98)),
## тож «підняти» в її осях — це мінус. Рухи нижче пишуть зсув тулуба
## по-людськи — «вгору» додатне, — а тут він перекладається.
UP_IN_HIPS = -1.0


def pose(rig, frame, bone, rot=(0, 0, 0), loc=(0, 0, 0)):
    b = rig.pose.bones[bone]
    b.rotation_mode = "XYZ"
    b.rotation_euler = [math.radians(a) for a in rot]
    if bone == "hips":
        loc = (loc[0], loc[1], loc[2] * UP_IN_HIPS)
    b.location = loc
    b.keyframe_insert("rotation_euler", frame=frame)
    b.keyframe_insert("location", frame=frame)


def curves(act):
    """Криві анімації дії. У Blender 5 дії шаруваті (шари → смуги →
    канали), `act.fcurves` є лише в старих; беремо, що є."""
    if hasattr(act, "fcurves"):
        try:
            return list(act.fcurves)
        except (AttributeError, RuntimeError):
            pass
    out = []
    for layer in getattr(act, "layers", []):
        for strip in layer.strips:
            for bag in getattr(strip, "channelbags", []):
                out.extend(bag.fcurves)
    return out


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
        1: {"hips": ((0, 0, 0), (0, 0, -0.012)),
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
        16: {"hips": ((0, 0, 0), (0, 0, -0.012)),
             "hind.L": ((-25, 0, 0), (0, 0, 0)),
             "hind.R": ((-25, 0, 0), (0, 0, 0)),
             "front.L": ((20, 0, 0), (0, 0, 0)),
             "front.R": ((20, 0, 0), (0, 0, 0))},
    })
    # Attack, 20 кадрів (слово замовника 19.09.2026: «коли атакує —
    # повинен бити лапами в стрибку і відскакувати назад»): присів →
    # стрибок уперед і вгору → у повітрі лівою-правою → приземлився →
    # відскок назад. Кістка тулуба дивиться на −Y: зсув по її Y — уперед,
    # «−» по X — морда вгору (перевірено рендером збоку).
    def at(pitch, up, ahead, **more):
        keys = {"hips": ((pitch, 0, 0), (0, ahead, up))}
        for bone, angle in more.items():
            keys[bone.replace("_", ".")] = ((angle, 0, 0), (0, 0, 0))
        return keys
    action(rig, "Attack", 20, {
        1: rest,
        4: at(6, -0.012, 0.0, hind_L=-25, hind_R=-25, front_L=20,
              front_R=20),
        7: at(-30, 0.12, 0.1, hind_L=45, hind_R=45, front_L=-100,
              front_R=-40, head=20, ear_L=30, ear_R=30),
        9: at(-32, 0.14, 0.14, hind_L=40, hind_R=40, front_L=-35,
              front_R=-105, head=22, ear_L=35, ear_R=35),
        11: at(-28, 0.11, 0.16, hind_L=35, hind_R=35, front_L=-105,
               front_R=-35, head=20, ear_L=30, ear_R=30),
        13: at(8, 0.0, 0.14, hind_L=-20, hind_R=-20, front_L=15,
               front_R=15),
        16: at(-12, 0.07, 0.02, hind_L=30, hind_R=30, front_L=-20,
               front_R=-20, ear_L=25, ear_R=25),
        20: rest,
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


def previews(rig, folder, zoom=1.0):
    """Кадри для перевірки оком: 3/4 для вигляду, збоку — для руху, і
    зблизька в EEVEE — чи хутро не блищить. `zoom` — у скільки разів
    звір більший за зайця: камери відсуваються в стільки ж."""
    scene = bpy.context.scene
    scene.render.resolution_x = 480
    scene.render.resolution_y = 360
    cam_data = bpy.data.cameras.new("Камера")
    cam = bpy.data.objects.new("Камера", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam_data.lens = 50
    views = {
        "три-чверті": ((1.2, -1.35, 0.62), (76, 0, 42)),
        "збоку": ((2.0, -0.1, 0.35), (86, 0, 90)),
        "зблизька": ((0.55, -0.7, 0.45), (72, 0, 38)),
    }
    shots = [("Idle", 1, "три-чверті"), ("Walk", 9, "три-чверті"), ("Death", 30, "три-чверті"),
             ("Attack", 4, "збоку"), ("Attack", 9, "збоку"),
             ("Attack", 13, "збоку"), ("Attack", 16, "збоку"),
             ("Idle", 1, "зблизька")]
    sun = bpy.data.objects.new("Сонце", bpy.data.lights.new("Сонце", "SUN"))
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    sun.data.energy = 3.0
    scene.collection.objects.link(sun)
    world = bpy.data.worlds.new("Небо")
    world.color = (0.4, 0.45, 0.5)
    scene.world = world
    for name, frame, view in shots:
        at, rot = views[view]
        cam.location = [c * zoom for c in at]
        cam.rotation_euler = [math.radians(a) for a in rot]
        if view == "зблизька":
            scene.render.engine = "BLENDER_EEVEE"
        else:
            scene.render.engine = "BLENDER_WORKBENCH"
            scene.display.shading.color_type = "TEXTURE"
            scene.display.shading.light = "STUDIO"
        rig.animation_data.action = bpy.data.actions[name]
        scene.frame_set(frame)
        scene.render.filepath = os.path.join(folder, "%s-%02d-%s.png"
                                             % (name, frame, view))
        bpy.ops.render.render(write_still=True)
    rig.animation_data.action = bpy.data.actions["Idle"]
    scene.frame_set(1)
    for obj in (cam, sun):
        bpy.data.objects.remove(obj)


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
