"""Вовк для гри (П-15) — на тих самих функціях, що й заєць
(`make_hare.py`): скелет, рухи, хутро, картинки для перевірки.

Замовник 19.09.2026: «зроби вовка і ведмедя так само як зайця».
Сірий, з пащею, що відкривається (кістка `jaw`). Рухи: Idle — дихає,
хвіст хитається, вуха смикаються; Walk — рисся (діагональні лапи
разом); Attack — випад і укус; Death — на бік.

Запуск (з каталогу проєкту):
    blender --background --python tools/blender/make_wolf.py -- \\
        art/monsters/вовк.blend [тека_для_картинок]
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_hare as h  # noqa: E402
import make_template as base  # noqa: E402

BONES = [
    ("hips", (0, 0.36, 0.7), (0, 0.0, 0.72), None),
    ("chest", (0, 0.0, 0.72), (0, -0.3, 0.76), "hips"),
    ("head", (0, -0.33, 0.84), (0, -0.62, 0.8), "chest"),
    ("jaw", (0, -0.44, 0.76), (0, -0.63, 0.74), "head"),
    ("ear.L", (0.055, -0.37, 0.93), (0.065, -0.35, 1.04), "head"),
    ("ear.R", (-0.055, -0.37, 0.93), (-0.065, -0.35, 1.04), "head"),
    ("tail", (0, 0.4, 0.72), (0, 0.76, 0.52), "hips"),
    ("front.L", (0.1, -0.24, 0.64), (0.1, -0.26, 0.03), "chest"),
    ("front.R", (-0.1, -0.24, 0.64), (-0.1, -0.26, 0.03), "chest"),
    ("hind.L", (0.1, 0.3, 0.64), (0.1, 0.34, 0.03), "hips"),
    ("hind.R", (-0.1, 0.3, 0.64), (-0.1, 0.34, 0.03), "hips"),
]


def body(rig):
    grey = h.fur("Хутро", (0.3, 0.29, 0.27), "хутро-сіре")
    light = h.fur("Світле", (0.7, 0.68, 0.64), "хутро-світле")
    dark = base.material("Ніс", (0.02, 0.02, 0.02))
    eye = base.material("Очі", (0.8, 0.55, 0.1))
    p = base.part
    parts = [
        p("sphere", "hips", (0, 0.08, 0.72), (0.16, 0.4, 0.18), grey),
        p("sphere", "hips", (0, 0.02, 0.62), (0.12, 0.3, 0.09), light),
        p("sphere", "chest", (0, -0.2, 0.75), (0.17, 0.2, 0.21), grey),
        # Грива на шиї — вовк важчий спереду.
        p("sphere", "chest", (0, -0.32, 0.8), (0.15, 0.14, 0.17), grey),
        p("sphere", "head", (0, -0.42, 0.86), (0.1, 0.12, 0.09), grey),
        p("sphere", "head", (0, -0.56, 0.82), (0.055, 0.12, 0.045), grey),
        p("sphere", "head", (0, -0.675, 0.83), (0.022, 0.018, 0.018), dark),
        p("sphere", "head", (0.048, -0.5, 0.89), (0.016, 0.012, 0.013), eye),
        p("sphere", "head", (-0.048, -0.5, 0.89), (0.016, 0.012, 0.013),
          eye),
        p("sphere", "jaw", (0, -0.55, 0.765), (0.045, 0.1, 0.022), light),
        p("cone", "ear.L", (0.058, -0.37, 0.98), (0.04, 0.016, 0.06), grey),
        p("cone", "ear.R", (-0.058, -0.37, 0.98), (0.04, 0.016, 0.06), grey),
        p("sphere", "tail", (0, 0.6, 0.62), (0.05, 0.2, 0.055), grey,
          (math.radians(-35), 0, 0)),
        # Плече — щоб передня лапа виростала з тіла, а не стирчала паличкою.
        p("sphere", "front.L", (0.1, -0.24, 0.55), (0.07, 0.1, 0.15), grey),
        p("sphere", "front.R", (-0.1, -0.24, 0.55), (0.07, 0.1, 0.15), grey),
        p("cyl", "front.L", (0.1, -0.25, 0.3), (0.05, 0.05, 0.27), grey),
        p("cyl", "front.R", (-0.1, -0.25, 0.3), (0.05, 0.05, 0.27), grey),
        p("sphere", "front.L", (0.1, -0.28, 0.03), (0.045, 0.065, 0.03),
          grey),
        p("sphere", "front.R", (-0.1, -0.28, 0.03), (0.045, 0.065, 0.03),
          grey),
        p("sphere", "hind.L", (0.1, 0.3, 0.55), (0.07, 0.13, 0.15), grey),
        p("sphere", "hind.R", (-0.1, 0.3, 0.55), (0.07, 0.13, 0.15), grey),
        p("cyl", "hind.L", (0.1, 0.34, 0.24), (0.046, 0.046, 0.24), grey,
          (math.radians(-8), 0, 0)),
        p("cyl", "hind.R", (-0.1, 0.34, 0.24), (0.046, 0.046, 0.24), grey,
          (math.radians(-8), 0, 0)),
        p("sphere", "hind.L", (0.1, 0.33, 0.03), (0.045, 0.07, 0.03), grey),
        p("sphere", "hind.R", (-0.1, 0.33, 0.03), (0.045, 0.07, 0.03), grey),
    ]
    return h.join_parts(rig, parts)


def k(**bones):
    """Ключовий кадр: кістка=кут по X (°), або кістка=(x, y, z) кути,
    hips_up/hips_ahead — зсув тулуба «по-людськи» (`make_hare.pose`)."""
    up = bones.pop("hips_up", 0.0)
    ahead = bones.pop("hips_ahead", 0.0)
    out = {}
    for name, angle in bones.items():
        rot = angle if isinstance(angle, tuple) else (angle, 0, 0)
        out[name.replace("_", ".")] = (rot, (0, 0, 0))
    hips_rot = out.get("hips", ((0, 0, 0), (0, 0, 0)))[0]
    out["hips"] = (hips_rot, (0, ahead, up))
    return out


def actions(rig):
    h.action(rig, "Idle", 48, {
        1: k(),
        12: k(tail=(0, 0, 12), chest=2),
        24: k(tail=(0, 0, -12), ear_L=-15, head=4),
        36: k(tail=(0, 0, 12), chest=2),
        48: k(),
    })
    # Рисся: ліва передня з правою задньою, тоді навпаки. Коли лапи
    # розставлені на 25°, по вертикалі вони коротші на ~5 см — тулуб
    # опускається, інакше вовк біг би над землею (заміряно 19.09.2026).
    h.action(rig, "Walk", 20, {
        1: k(front_L=-25, hind_R=-25, front_R=20, hind_L=20, hips_up=-0.045),
        6: k(hips_up=0.0, tail=(0, 0, 6)),
        11: k(front_L=20, hind_L=-25, front_R=-25, hind_R=20,
              hips_up=-0.045),
        16: k(hips_up=0.0, tail=(0, 0, -6)),
        20: k(front_L=-25, hind_R=-25, front_R=20, hind_L=20,
              hips_up=-0.045),
    })
    # Випад з укусом: присів → кинувся вперед із роззявленою пащею →
    # клацнув → назад.
    h.action(rig, "Attack", 18, {
        1: k(),
        4: k(hind_L=-12, hind_R=-12, head=-10),
        8: k(hips=-8, hips_up=0.04, hips_ahead=0.2, front_L=-35,
             front_R=-35, hind_L=30, hind_R=30, head=12, jaw=28,
             ear_L=25, ear_R=25),
        10: k(hips_ahead=0.22, hips_up=0.02, front_L=-20, front_R=-20,
              hind_L=20, hind_R=20, head=18, jaw=0, ear_L=25, ear_R=25),
        14: k(hips_ahead=0.08, head=5),
        18: k(),
    })
    h.action(rig, "Death", 30, {
        1: k(),
        30: k(hips=(0, 85, 0), hips_up=-0.52, head=15, jaw=15,
              front_L=-20, hind_L=25, tail=(0, 0, 20)),
    })
    rig.animation_data.action = bpy.data.actions["Idle"]


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = args[0] if args else "art/monsters/вовк.blend"
    base.clear()
    bpy.context.scene.render.fps = 24
    rig = h.armature(BONES)
    body(rig)
    actions(rig)
    if len(args) > 1:
        h.previews(rig, args[1], zoom=1.9)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(out))
    print("[вовк] збережено", out)


if __name__ == "__main__":
    main()
