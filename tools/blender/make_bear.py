"""Ведмідь для гри (П-15) — на тих самих функціях, що й заєць і вовк
(`make_hare.py`, `make_wolf.py`).

Замовник 19.09.2026: «зроби вовка і ведмедя так само як зайця».
Масивний, темно-бурий, з горбом над плечима, круглими вухами й світлішою
мордою. Рухи: Idle — дихає й поводить головою; Walk — перевалюється
(лапи одного боку разом, як ходять ведмеді); Attack — стає дибки,
замах і удар лапою згори; Death — на бік.

Запуск (з каталогу проєкту):
    blender --background --python tools/blender/make_bear.py -- \\
        art/monsters/ведмідь.blend [тека_для_картинок]
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_hare as h  # noqa: E402
import make_template as base  # noqa: E402
from make_wolf import k  # noqa: E402

BONES = [
    ("hips", (0, 0.5, 0.85), (0, 0.0, 0.95), None),
    ("chest", (0, 0.0, 0.95), (0, -0.4, 1.0), "hips"),
    ("head", (0, -0.45, 1.02), (0, -0.76, 0.95), "chest"),
    ("jaw", (0, -0.6, 0.9), (0, -0.79, 0.88), "head"),
    ("ear.L", (0.11, -0.52, 1.13), (0.12, -0.51, 1.22), "head"),
    ("ear.R", (-0.11, -0.52, 1.13), (-0.12, -0.51, 1.22), "head"),
    ("tail", (0, 0.55, 0.9), (0, 0.67, 0.85), "hips"),
    ("front.L", (0.16, -0.32, 0.85), (0.16, -0.35, 0.05), "chest"),
    ("front.R", (-0.16, -0.32, 0.85), (-0.16, -0.35, 0.05), "chest"),
    ("hind.L", (0.16, 0.38, 0.85), (0.16, 0.42, 0.05), "hips"),
    ("hind.R", (-0.16, 0.38, 0.85), (-0.16, 0.42, 0.05), "hips"),
]


def body(rig):
    dark = h.fur("Хутро", (0.08, 0.05, 0.03), "хутро-темне")
    muzzle = h.fur("Морда", (0.3, 0.2, 0.12), "хутро-буре")
    black = base.material("Ніс", (0.01, 0.01, 0.01))
    p = base.part
    parts = [
        p("sphere", "hips", (0, 0.12, 0.92), (0.3, 0.55, 0.33), dark),
        p("sphere", "chest", (0, -0.24, 1.07), (0.25, 0.26, 0.22), dark),
        p("sphere", "chest", (0, -0.34, 0.92), (0.27, 0.25, 0.3), dark),
        p("sphere", "head", (0, -0.58, 1.0), (0.16, 0.17, 0.15), dark),
        p("sphere", "head", (0, -0.74, 0.95), (0.08, 0.1, 0.07), muzzle),
        p("sphere", "head", (0, -0.835, 0.97), (0.032, 0.022, 0.024),
          black),
        p("sphere", "head", (0.075, -0.7, 1.06), (0.016, 0.012, 0.016),
          black),
        p("sphere", "head", (-0.075, -0.7, 1.06), (0.016, 0.012, 0.016),
          black),
        p("sphere", "ear.L", (0.115, -0.52, 1.16), (0.055, 0.03, 0.05),
          dark),
        p("sphere", "ear.R", (-0.115, -0.52, 1.16), (0.055, 0.03, 0.05),
          dark),
        p("sphere", "jaw", (0, -0.72, 0.9), (0.07, 0.09, 0.03), muzzle),
        p("sphere", "tail", (0, 0.63, 0.9), (0.06, 0.06, 0.06), dark),
        p("sphere", "front.L", (0.16, -0.32, 0.72), (0.12, 0.15, 0.24),
          dark),
        p("sphere", "front.R", (-0.16, -0.32, 0.72), (0.12, 0.15, 0.24),
          dark),
        p("cyl", "front.L", (0.16, -0.34, 0.36), (0.09, 0.09, 0.32), dark),
        p("cyl", "front.R", (-0.16, -0.34, 0.36), (0.09, 0.09, 0.32), dark),
        p("sphere", "front.L", (0.16, -0.39, 0.05), (0.1, 0.13, 0.05),
          dark),
        p("sphere", "front.R", (-0.16, -0.39, 0.05), (0.1, 0.13, 0.05),
          dark),
        p("sphere", "hind.L", (0.16, 0.38, 0.72), (0.13, 0.2, 0.25), dark),
        p("sphere", "hind.R", (-0.16, 0.38, 0.72), (0.13, 0.2, 0.25), dark),
        p("cyl", "hind.L", (0.16, 0.42, 0.34), (0.085, 0.085, 0.3), dark),
        p("cyl", "hind.R", (-0.16, 0.42, 0.34), (0.085, 0.085, 0.3), dark),
        p("sphere", "hind.L", (0.16, 0.37, 0.05), (0.1, 0.14, 0.05), dark),
        p("sphere", "hind.R", (-0.16, 0.37, 0.05), (0.1, 0.14, 0.05), dark),
    ]
    return h.join_parts(rig, parts)


def actions(rig):
    h.action(rig, "Idle", 48, {
        1: k(),
        16: k(chest=2, head=(0, 0, 10)),
        32: k(chest=2, head=(0, 0, -10), ear_L=-15),
        48: k(),
    })
    # Перевалюється: обидві ліві лапи вперед, тоді обидві праві; тулуб
    # ледь хилиться з боку на бік. Розставлені лапи коротші по вертикалі
    # — тулуб опускається, щоб лапи не висіли над землею.
    h.action(rig, "Walk", 24, {
        1: k(front_L=-20, hind_L=-20, front_R=18, hind_R=18,
             hips=(0, 3, 0), hips_up=-0.05),
        7: k(hips_up=0.0),
        13: k(front_R=-20, hind_R=-20, front_L=18, hind_L=18,
              hips=(0, -3, 0), hips_up=-0.05),
        19: k(hips_up=0.0),
        24: k(front_L=-20, hind_L=-20, front_R=18, hind_R=18,
              hips=(0, 3, 0), hips_up=-0.05),
    })
    # Дибки, замах правою й удар згори. Задні лапи повертаються назад
    # на кут тулуба, щоб лишитись на землі (як у зайця).
    # Задні лапи кріпляться на 12 см попереду осі, навколо якої тулуб
    # стає дибки, — і з нею підіймаються на 0,12·sin(кут); тулуб
    # опускається рівно на стільки (заміряно: без цього — 9 см у повітрі).
    def rear(angle, **more):
        return k(hips=-angle, hind_L=angle, hind_R=angle,
                 hips_up=-0.12 * math.sin(math.radians(angle)), **more)
    h.action(rig, "Attack", 24, {
        1: k(),
        # Передні лапи теж крутяться з тулубом — «+кут» лишає їх звислими
        # (з «−» стирчали вперед, як у зомбі, — перший рендер).
        6: rear(45, front_L=25, front_R=10, head=25, jaw=15),
        10: rear(50, front_L=30, front_R=-120, head=30, jaw=25),
        14: rear(25, front_L=15, front_R=15, head=10, jaw=0),
        17: rear(5, front_L=5, front_R=5),
        24: k(),
    })
    h.action(rig, "Death", 30, {
        1: k(),
        30: k(hips=(0, 85, 0), hips_up=-0.62, head=20, jaw=15,
              front_L=-20, hind_L=25),
    })
    rig.animation_data.action = bpy.data.actions["Idle"]


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = args[0] if args else "art/monsters/ведмідь.blend"
    base.clear()
    bpy.context.scene.render.fps = 24
    rig = h.armature(BONES)
    body(rig)
    actions(rig)
    if len(args) > 1:
        h.previews(rig, args[1], zoom=2.7)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(out))
    print("[ведмідь] збережено", out)


if __name__ == "__main__":
    main()
