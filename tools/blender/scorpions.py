"""Скорпіони бестіарію (spec/monsters.md, конвеєр «С») — скорпіон, чорний
скорпіон, скорпіон-імператор.

Замовник 19.09.2026: «зроби наступні монстри що залишились». Скелет —
тулуб, дві клешні (плече + клішня), вісім ніг, хвіст-ланцюг дугою над
спиною з жалом. Рухи: ходьба трійками ніг, удар хвостом уперед над
головою з клацанням клешнями, перекид на спину.

Перевіряється само (`check_legs`): кінці ніг у спокої й ході на землі.

Запуск (з каталогу проєкту):
    blender --background --python tools/blender/scorpions.py -- \\
        <вид> [тека_для_картинок]
"""
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_hare as h  # noqa: E402
import make_template as base  # noqa: E402
from humanoids import solid  # noqa: E402

OUT = os.path.join(h.ROOT, "art", "monsters")

# L — довжина тулуба (м); колір панцира; claws — розмір клешень.
SPECIES = {
    "скорпіон": dict(L=0.32, shell=(0.62, 0.34, 0.12), claws=1.0,
                     eyes=(0.1, 0.05, 0.02)),
    "чорний скорпіон": dict(L=0.55, shell=(0.08, 0.08, 0.09), claws=1.1,
                            eyes=(1.0, 0.2, 0.05), glow=True),
    "скорпіон-імператор": dict(L=1.1, shell=(0.12, 0.14, 0.22), claws=1.4,
                               plates=True, eyes=(1.0, 0.1, 0.05),
                               glow=True),
}

LEGS = [(side, n) for side in ("L", "R") for n in range(4)]


def geometry(s):
    L = s["L"]
    h_body = L * 0.32
    w = L * 0.22
    bones = [("body", (0, L * 0.45, h_body), (0, -L * 0.45, h_body), None)]
    for side, n in LEGS:
        sign = 1 if side == "L" else -1
        y = -L * 0.25 + n * L * 0.18
        bones.append(("leg.%s%d" % (side, n), (sign * w, y, h_body),
                      (sign * (w + L * 0.45), y + L * 0.05 * (n - 1.5),
                       L * 0.02), "body"))
    for side in ("L", "R"):
        sign = 1 if side == "L" else -1
        bones.append(("arm.%s" % side, (sign * w * 0.7, -L * 0.45, h_body),
                      (sign * L * 0.35, -L * 0.75, h_body), "body"))
        bones.append(("claw.%s" % side, (sign * L * 0.35, -L * 0.75,
                                         h_body),
                      (sign * L * 0.3, -L * 1.05, h_body), "arm.%s" % side))
    # Хвіст дугою вгору й уперед над спиною.
    prev = "body"
    pts = []
    for i in range(6):
        a = math.radians(-10 + i * 38)
        pts.append(Vector((0, L * 0.45 + math.cos(a) * L * 0.45 - L * 0.05 * i,
                           h_body + math.sin(a) * L * 0.55 + i * L * 0.05)))
    for i in range(5):
        bones.append(("tail%d" % i, tuple(pts[i]), tuple(pts[i + 1]), prev))
        prev = "tail%d" % i
    return dict(L=L, h=h_body, w=w, bones=bones, tail=pts)


def body(rig, s, g):
    p = base.part
    shell = solid("Панцир", s["shell"], 0.35)
    belly = solid("Черево", tuple(c * 0.7 + 0.1 for c in s["shell"]), 0.6)
    eye = solid("Очі", s["eyes"], 0.3, glow=5.0 if s.get("glow") else 0.5)
    sting = solid("Жало", (0.85, 0.75, 0.4), 0.3)
    L, hb, w = g["L"], g["h"], g["w"]
    k = s["claws"]
    parts = []
    for i in range(4):  # сегменти тулуба
        y = -L * 0.3 + i * L * 0.22
        parts.append(p("sphere", "body", (0, y, hb),
                       (w * (1.1 - i * 0.08), L * 0.16, hb * 0.55), shell))
        parts.append(p("sphere", "body", (0, y, hb - hb * 0.25),
                       (w * 0.9, L * 0.15, hb * 0.35), belly))
    for sign in (1, -1):
        parts.append(p("sphere", "body", (sign * w * 0.3, -L * 0.42,
                                          hb + hb * 0.4),
                       (L * 0.03,) * 3, eye))
    for side, n in LEGS:
        b = rig.data.bones["leg.%s%d" % (side, n)]
        a, t = b.head_local, b.tail_local
        knee = a.lerp(t, 0.4) + Vector((0, 0, L * 0.12))
        parts.append(rod(a, knee, L * 0.025, shell, b.name))
        parts.append(rod(knee, t, L * 0.02, shell, b.name))
    for side in ("L", "R"):
        arm = rig.data.bones["arm.%s" % side]
        claw = rig.data.bones["claw.%s" % side]
        parts.append(rod(arm.head_local, arm.tail_local, L * 0.04 * k,
                         shell, arm.name))
        c = claw.head_local.lerp(claw.tail_local, 0.45)
        parts.append(p("sphere", claw.name, tuple(c),
                       (L * 0.1 * k, L * 0.16 * k, L * 0.07 * k), shell))
        for off in (1, -1):
            tip = claw.tail_local + Vector((off * L * 0.035 * k, -L * 0.04,
                                            0))
            parts.append(rod(c, tip, L * 0.03 * k, shell, claw.name))
    pts = g["tail"]
    # Сегменти хвоста — товсті циліндри між суглобами й кулі в суглобах:
    # самі кулі розсипались на окремі цятки (перший огляд).
    for i in range(5):
        r = L * (0.075 - i * 0.009)
        parts.append(rod(pts[i], pts[i + 1], r, shell, "tail%d" % i))
        parts.append(p("sphere", "tail%d" % i, tuple(pts[i + 1]),
                       (r * 1.15,) * 3, shell))
    tip = pts[5]
    parts.append(p("sphere", "tail4", tuple(tip), (L * 0.07,) * 3, sting))
    parts.append(rod(tip, tip + Vector((0, -L * 0.12, -L * 0.06)),
                     L * 0.02, sting, "tail4"))
    if s.get("plates"):
        for i in range(4):
            y = -L * 0.3 + i * L * 0.22
            parts.append(p("sphere", "body", (0, y, hb + hb * 0.45),
                           (w * 0.8, L * 0.12, hb * 0.18),
                           solid("Пластина", (0.3, 0.3, 0.35), 0.3)))
    return h.join_parts(rig, parts)


def rod(a, b, radius, mat, bone):
    """Циліндр від a до b на кістці `bone`."""
    length = (b - a).length
    bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=radius,
                                        depth=length)
    obj = bpy.context.active_object
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = (b - a).normalized().to_track_quat("Z", "Y")
    obj.location = (a + b) * 0.5
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    obj.data.materials.append(mat)
    return obj


def legs_key(phase):
    """Трійки ніг: L0, R1, L2, R3 разом, решта навпаки. Нога крутиться
    навколо своєї осі Z — крок уперед-назад."""
    out = {}
    for side, n in LEGS:
        group = (n + (0 if side == "L" else 1)) % 2
        a = 18 * (1 if (group == 0) == phase else -1)
        out["leg.%s%d" % (side, n)] = ((0, 0, a), (0, 0, 0))
    return out


def actions(rig, s):
    rest = {}

    def with_(base_k, **more):
        k = dict(base_k)
        for name, rot in more.items():
            k[name.replace("_", ".")] = (rot, (0, 0, 0))
        return k

    h.action(rig, "Idle", 48, {
        1: rest,
        12: with_(rest, tail4=(8, 0, 0), claw_L=(0, 0, 10)),
        24: with_(rest, tail3=(-6, 0, 0), claw_R=(0, 0, -10)),
        48: rest,
    })
    # Нога крокує навколо своєї осі, що йде вбік і вниз, — кінець
    # опускається на ~7,5 % довжини тулуба (заміряно `check_legs`: −2,4…
    # −8 см). Тулуб на стільки ж угору. Вісь Z цієї кістки (строго
    # горизонтальної) дивиться ВГОРУ — не вниз, як у нахиленого тулуба
    # зайця: з мінусом похибка подвоїлась.
    lift = (0, 0, 0.074 * s["L"])

    def walk(phase):
        k = legs_key(phase)
        k["body"] = ((0, 0, 0), lift)
        return k
    h.action(rig, "Walk", 16, {1: walk(True), 9: walk(False),
                               16: walk(True)})
    h.action(rig, "Attack", 18, {
        1: rest,
        6: with_(rest, tail0=(-15, 0, 0), tail1=(-15, 0, 0),
                 tail2=(-10, 0, 0), arm_L=(0, 0, 20), arm_R=(0, 0, -20)),
        10: with_(rest, tail0=(20, 0, 0), tail1=(25, 0, 0), tail2=(25, 0, 0),
                  tail3=(20, 0, 0), claw_L=(0, 0, -15), claw_R=(0, 0, 15)),
        18: rest,
    })
    h.action(rig, "Death", 30, {
        1: rest,
        30: {"body": ((0, 175, 0), (0, 0, 0))},
    })
    rig.animation_data.action = bpy.data.actions["Idle"]


WARN = []


def check_legs(rig, g):
    scene = bpy.context.scene
    tips = ["leg.%s%d" % (side, n) for side, n in LEGS]
    report = []
    for name in ("Idle", "Walk"):
        act = bpy.data.actions[name]
        rig.animation_data.action = act
        lows = []
        for f in sorted({int(kp.co.x) for fc in h.curves(act)
                         for kp in fc.keyframe_points}):
            scene.frame_set(f)
            low = min((rig.matrix_world @ rig.pose.bones[b].tail).z
                      for b in tips) - g["L"] * 0.02
            lows.append(low)
            if abs(low) > 0.025:
                WARN.append("%s кадр %d: кінці ніг %+.3f м" % (name, f, low))
        report.append("%s %+.3f…%+.3f" % (name, min(lows), max(lows)))
    rig.animation_data.action = bpy.data.actions["Idle"]
    scene.frame_set(1)
    return ", ".join(report)


def build(name, shots=None):
    s = SPECIES[name]
    base.clear()
    bpy.context.scene.render.fps = 24
    g = geometry(s)
    rig = h.armature(g["bones"])
    body(rig, s, g)
    actions(rig, s)
    legs = check_legs(rig, g)
    if shots:
        h.previews(rig, shots, zoom=max(1.0, s["L"] * 2.2 / 0.6))
    out = os.path.join(OUT, name + ".blend")
    bpy.ops.wm.save_as_mainfile(filepath=out)
    print("[скорпіон] %s → %s · ноги: %s" % (name, out, legs))
    for line in WARN:
        print("[скорпіон] ‼ %s: %s" % (name, line))


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if not args or args[0] == "--список":
        print("[скорпіон] види: " + ", ".join(SPECIES))
        return
    build(args[0], args[1] if len(args) > 1 else None)


if __name__ == "__main__":
    main()
