"""Звірі бестіарію (spec/monsters.md, лінія 1) — одним будівником.

Замовник 19.09.2026: «поїхали, починай зі звірів». Заєць, вовк і ведмідь
робились кожен своїм скриптом із числами руками; звірів у лінії десяток,
тож тут вид — набір чисел (`SPECIES`): довжина, висота, голова, вуха,
хвіст, хутро й додатки (роги, ікла, шипи, пластини, зайві очі), стиль
атаки. З нього будуються скелет, тіло й рухи на тих самих функціях, що й
заєць (`make_hare.py`).

Що перевіряється само, при кожній збірці (`check_paws`): висота лап над
землею в кожному ключовому кадрі. Звір, що висить у ходьбі чи провалює
лапу в атаці, друкує «‼» — так спіймано три вади вовка й ведмедя
19.09.2026, тепер без ручних замірів.

Запуск (з каталогу проєкту):
    blender --background --python tools/blender/beasts.py -- \\
        <вид> art/monsters/<вид>.blend [тека_для_картинок]
    blender --background --python tools/blender/beasts.py -- --список
"""
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_hare as h  # noqa: E402
import make_template as base  # noqa: E402
from make_wolf import k  # noqa: E402

# Вид: L — довжина тулуба, H — висота в холці, W — півширина тулуба (м).
# Решта — що є на тілі; не назване — немає.
SPECIES = {
    "лисиця": dict(L=0.55, H=0.36, W=0.1, head=0.075, snout=0.1,
                   ears=("гострі", 0.07), tail=("пухнастий", 0.36),
                   fur="хутро-руде", belly="хутро-світле", attack="стрибок",
                   eyes=(0.9, 0.6, 0.1)),
    "рись": dict(L=0.62, H=0.5, W=0.13, head=0.09, snout=0.04,
                 ears=("китиці", 0.07), tail=("короткий", 0.09),
                 fur="хутро-рисяче", belly="хутро-світле", attack="стрибок",
                 eyes=(0.8, 0.75, 0.2), legs=1.15),
    "олень": dict(L=0.95, H=1.05, W=0.16, neck=0.32, head=0.1, snout=0.15,
                  ears=("довгі", 0.1), tail=("короткий", 0.07),
                  fur="хутро-оленяче", belly="хутро-світле", hooves=True,
                  antlers=0.55, attack="таран", eyes=(0.05, 0.04, 0.03),
                  legs=0.8),
    "вовк-сіромаха": dict(L=0.85, H=0.84, W=0.19, head=0.11, snout=0.17,
                          ears=("гострі", 0.09), tail=("пухнастий", 0.42),
                          fur="хутро-сиве", belly="хутро-світле", mane=0.2,
                          attack="укус", eyes=(0.9, 0.7, 0.15), body=0.22),
    "печерний ведмідь": dict(L=1.6, H=1.08, W=0.38, head=0.19, snout=0.11,
                             ears=("круглі", 0.06), tail=("короткий", 0.07),
                             fur="хутро-сіре", belly="хутро-сіре", hump=0.28,
                             attack="лапа", eyes=(0.02, 0.02, 0.02),
                             legs=1.3, body=0.31),
    "вовк-мутант": dict(L=0.9, H=0.88, W=0.2, head=0.12, snout=0.18,
                        ears=("гострі", 0.1), tail=("пухнастий", 0.42),
                        tails=2, fur="хутро-темне", belly="хутро-сіре",
                        spikes=7, attack="укус", eyes=(1.0, 0.08, 0.05),
                        glow=True, body=0.23),
    "кабан": dict(L=0.78, H=0.62, W=0.22, head=0.14, snout=0.16,
                  ears=("гострі", 0.06), tail=("тонкий", 0.14),
                  fur="щетина", belly="щетина", hooves=True, tusks=2,
                  bristle=9, attack="таран", eyes=(0.05, 0.03, 0.02),
                  legs=1.2, body=0.34),
    "кабан-мутант": dict(L=0.92, H=0.76, W=0.27, head=0.17, snout=0.18,
                         ears=("гострі", 0.07), tail=("тонкий", 0.16),
                         fur="щетина", belly="хутро-темне", hooves=True,
                         tusks=4, plates=5, attack="таран",
                         eyes=(1.0, 0.1, 0.05), glow=True, legs=1.25,
                         body=0.36),
    "ведмідь-мутант": dict(L=1.7, H=1.18, W=0.42, head=0.2, snout=0.12,
                           ears=("круглі", 0.065), tail=("короткий", 0.08),
                           fur="хутро-темне", belly="хутро-темне", hump=0.3,
                           spikes=9, extra_eyes=2, attack="лапа",
                           eyes=(1.0, 0.1, 0.05), glow=True, legs=1.3,
                           body=0.31),
    # Химера — масивна, темна, вовча паща з іклами, роги й бивні; на
    # першому огляді була надто схожа на оленя.
    "химера": dict(L=1.2, H=1.2, W=0.3, neck=0.24, head=0.15, snout=0.24,
                   ears=("гострі", 0.1), tail=("пухнастий", 0.55),
                   fur="хутро-темне", belly="хутро-буре", hooves=True,
                   antlers=0.7, horns=0.5, mane=0.32, tusks=2, spikes=5,
                   attack="таран", eyes=(1.0, 0.5, 0.05), glow=True,
                   legs=1.1, body=0.27),
}

WARN = []


def emissive(name, rgb, strength):
    mat = base.material(name, rgb)
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Emission Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Emission Strength"].default_value = strength
    return mat


def geometry(s):
    """Точки скелета з чисел виду. Перед — −Y, земля — Z = 0."""
    L, H, W = s["L"], s["H"], s["W"]
    rear, front = L * 0.5, -L * 0.5
    neck = s.get("neck", 0.0)
    head_r = s["head"]
    hz = H * 1.08 + neck
    hy = front * 0.95 - neck * 0.35
    paw = max(0.02, H * 0.035)
    g = dict(L=L, H=H, W=W, rear=rear, front=front, hz=hz, hy=hy, paw=paw,
             head_r=head_r, snout=s["snout"])
    g["bones"] = [
        ("hips", (0, rear * 0.9, H * 0.93), (0, 0.0, H * 0.96), None),
        ("chest", (0, 0.0, H * 0.96), (0, front * 0.8, H * 1.0), "hips"),
        ("head", (0, hy + head_r * 0.6, hz), (0, hy - head_r - s["snout"],
                                               hz - head_r * 0.2), "chest"),
        ("jaw", (0, hy - head_r * 0.2, hz - head_r * 0.55),
         (0, hy - head_r - s["snout"] * 0.9, hz - head_r * 0.6), "head"),
        ("ear.L", (head_r * 0.55, hy, hz + head_r * 0.7),
         (head_r * 0.65, hy + 0.01, hz + head_r * 0.7 + s["ears"][1]),
         "head"),
        ("ear.R", (-head_r * 0.55, hy, hz + head_r * 0.7),
         (-head_r * 0.65, hy + 0.01, hz + head_r * 0.7 + s["ears"][1]),
         "head"),
        ("tail", (0, rear, H * 0.95),
         (0, rear + s["tail"][1] * 0.8, H * 0.95 - s["tail"][1] * 0.55),
         "hips"),
        ("front.L", (W * 0.7, front * 0.62, H * 0.86),
         (W * 0.7, front * 0.66, paw), "chest"),
        ("front.R", (-W * 0.7, front * 0.62, H * 0.86),
         (-W * 0.7, front * 0.66, paw), "chest"),
        ("hind.L", (W * 0.7, rear * 0.7, H * 0.86),
         (W * 0.7, rear * 0.78, paw), "hips"),
        ("hind.R", (-W * 0.7, rear * 0.7, H * 0.86),
         (-W * 0.7, rear * 0.78, paw), "hips"),
    ]
    g["leg"] = H * 0.86 - paw
    return g


def body(rig, s, g):
    p = base.part
    fur = h.fur("Хутро", (0.3, 0.2, 0.12), s["fur"])
    belly = h.fur("Черево", (0.6, 0.55, 0.5), s["belly"])
    dark = base.material("Ніс", (0.02, 0.02, 0.02))
    eye_rgb = s.get("eyes", (0.05, 0.04, 0.03))
    eye = emissive("Очі", eye_rgb, 4.0) if s.get("glow") \
        else base.material("Очі", eye_rgb)
    bone = base.material("Кістка", (0.82, 0.78, 0.66))
    horn = base.material("Ріг", (0.3, 0.24, 0.17))
    hoof = base.material("Копито", (0.08, 0.07, 0.06))
    plate = base.material("Пластина", (0.2, 0.2, 0.22))
    L, H, W, rear, front = g["L"], g["H"], g["W"], g["rear"], g["front"]
    hy, hz, hr, sn = g["hy"], g["hz"], g["head_r"], g["snout"]
    # Товщина тулуба частками висоти: кабан і ведмідь присадкуваті, на
    # тонкому тулубі вони стояли, як на ходулях (перший огляд).
    rz = H * s.get("body", 0.2)
    legw = W * 0.28 * s.get("legs", 1.0)
    parts = [
        p("sphere", "hips", (0, rear * 0.35, H * 0.93), (W, L * 0.42, rz),
          fur),
        p("sphere", "hips", (0, 0.0, H * 0.93 - rz * 0.5),
          (W * 0.75, L * 0.42, rz * 0.5), belly),
        p("sphere", "chest", (0, front * 0.5, H * 0.97),
          (W * 1.05, L * 0.28, rz * 1.12), fur),
        # Шия від грудей до голови.
        p("sphere", "chest", (0, (front * 0.75 + hy) * 0.5,
                              (H * 1.0 + hz) * 0.5),
          (W * 0.6, max(0.08, abs(front * 0.75 - hy) * 0.6),
           max(rz * 0.7, (hz - H) * 0.6)), fur),
        p("sphere", "head", (0, hy, hz), (hr, hr * 1.15, hr * 0.9), fur),
        p("sphere", "head", (0, hy - hr * 0.7 - sn * 0.45, hz - hr * 0.25),
          (hr * 0.55, sn * 0.6 + hr * 0.3, hr * 0.45), fur),
        p("sphere", "head", (0, hy - hr * 0.95 - sn, hz - hr * 0.2),
          (hr * 0.22, hr * 0.15, hr * 0.17), dark),
        p("sphere", "jaw", (0, hy - hr * 0.6 - sn * 0.4, hz - hr * 0.6),
          (hr * 0.45, sn * 0.55 + hr * 0.25, hr * 0.2), belly),
    ]
    for sign in (1, -1):
        parts.append(p("sphere", "head",
                       (sign * hr * 0.55, hy - hr * 0.65, hz + hr * 0.3),
                       (hr * 0.16, hr * 0.1, hr * 0.14), eye))
    for n in range(s.get("extra_eyes", 0)):
        for sign in (1, -1):
            parts.append(p("sphere", "head",
                           (sign * hr * 0.4, hy - hr * 0.8,
                            hz + hr * (0.6 + 0.25 * n)),
                           (hr * 0.1, hr * 0.07, hr * 0.09), eye))
    # Вуха.
    kind, size = s["ears"]
    for sign, bone_name in ((1, "ear.L"), (-1, "ear.R")):
        at = (sign * hr * 0.6, hy + 0.005, hz + hr * 0.7 + size * 0.45)
        if kind == "круглі":
            parts.append(p("sphere", bone_name,
                           (at[0], at[1], hz + hr * 0.75),
                           (size, size * 0.5, size), fur))
        elif kind == "довгі":
            parts.append(p("sphere", bone_name, at,
                           (size * 0.35, size * 0.12, size * 0.6), fur,
                           (0, math.radians(sign * -40), 0)))
        else:
            parts.append(p("cone", bone_name, at,
                           (size * 0.55, size * 0.22, size * 0.55), fur))
            if kind == "китиці":
                parts.append(p("cone", bone_name,
                               (at[0], at[1], at[2] + size * 0.75),
                               (size * 0.08, size * 0.06, size * 0.35),
                               dark))
    # Хвіст (або два).
    kind, size = s["tail"]
    tail_at = (0, rear + size * 0.45, H * 0.95 - size * 0.3)
    for n in range(s.get("tails", 1)):
        off = (n - (s.get("tails", 1) - 1) * 0.5) * W * 0.5
        at = (tail_at[0] + off, tail_at[1], tail_at[2])
        tilt = (math.radians(-35), 0, 0)
        if kind == "пухнастий":
            parts.append(p("sphere", "tail", at,
                           (size * 0.2, size * 0.55, size * 0.2), fur, tilt))
            parts.append(p("sphere", "tail",
                           (at[0], at[1] + size * 0.4, at[2] - size * 0.28),
                           (size * 0.12, size * 0.2, size * 0.12), belly,
                           tilt))
        elif kind == "тонкий":
            parts.append(p("cyl", "tail", at,
                           (size * 0.06, size * 0.06, size * 0.45), fur,
                           (math.radians(-55), 0, 0)))
        else:
            parts.append(p("sphere", "tail", (0, rear + size * 0.2,
                                              H * 0.98),
                           (size * 0.6, size * 0.5, size * 0.6), belly))
    # Лапи: плече/стегно, гомілка, лапа чи копито.
    for side, sign in (("L", 1), ("R", -1)):
        x = W * 0.7 * sign
        for leg, y0 in (("front", front * 0.64), ("hind", rear * 0.74)):
            b = "%s.%s" % (leg, side)
            top = H * 0.72 if leg == "front" else H * 0.7
            parts.append(p("sphere", b, (x, y0, top),
                           (legw * 1.5, legw * 2.0 if leg == "hind"
                            else legw * 1.6, H * 0.2), fur))
            parts.append(p("cyl", b, (x, y0 + (0.02 if leg == "hind" else 0),
                                      H * 0.33),
                           (legw, legw, H * 0.3), fur))
            if s.get("hooves"):
                parts.append(p("cyl", b, (x, y0, g["paw"] + 0.012),
                               (legw * 1.05, legw * 1.1, 0.03), hoof))
            else:
                parts.append(p("sphere", b, (x, y0 - legw * 0.5, g["paw"]),
                               (legw * 1.2, legw * 1.7, g["paw"]), fur))
    # Додатки.
    if s.get("mane"):
        m = s["mane"]
        parts.append(p("sphere", "chest", (0, front * 0.7, H * 1.05),
                       (W * 1.1, m, m * 1.1), fur))
    if s.get("hump"):
        parts.append(p("sphere", "chest", (0, front * 0.35, H * 1.12),
                       (W * 0.85, s["hump"], H * 0.16), fur))
    if s.get("antlers"):
        parts += antlers(s["antlers"], hy, hz, hr, horn)
    if s.get("horns"):
        for sign in (1, -1):
            parts.append(p("cone", "head",
                           (sign * hr * 0.7, hy + hr * 0.2, hz + hr * 0.6),
                           (hr * 0.3, hr * 0.3, s["horns"] * 0.5), bone,
                           (math.radians(30), math.radians(sign * 35), 0)))
    for n in range(s.get("tusks", 0)):
        sign = 1 if n % 2 == 0 else -1
        row = n // 2
        parts.append(p("cone", "jaw",
                       (sign * hr * (0.45 + 0.12 * row),
                        hy - hr * 0.7 - sn * (0.55 - 0.2 * row),
                        hz - hr * 0.45),
                       (hr * 0.1, hr * 0.1, hr * 0.45), bone,
                       (math.radians(-20), math.radians(sign * 25), 0)))
    spikes = s.get("spikes", 0)
    for n in range(spikes):
        t = n / max(1, spikes - 1)
        y = front * 0.6 + (rear * 0.8 - front * 0.6) * t
        tall = H * 0.22 * (1.0 - abs(t - 0.4))
        on = "chest" if y < 0 else "hips"
        parts.append(p("cone", on, (0, y, H * 0.93 + rz * 0.95 + tall * 0.4),
                       (W * 0.12, W * 0.18, tall), bone,
                       (math.radians(25), 0, 0)))
    for n in range(s.get("bristle", 0)):
        t = n / max(1, s["bristle"] - 1)
        y = front * 0.6 + (rear * 0.7 - front * 0.6) * t
        on = "chest" if y < 0 else "hips"
        parts.append(p("cone", on, (0, y, H * 0.93 + rz * 0.95),
                       (W * 0.06, W * 0.12, H * 0.08), dark,
                       (math.radians(20), 0, 0)))
    for n in range(s.get("plates", 0)):
        t = n / max(1, s["plates"] - 1)
        y = front * 0.55 + (rear * 0.7 - front * 0.55) * t
        on = "chest" if y < 0 else "hips"
        parts.append(p("sphere", on, (0, y, H * 0.93 + rz * 0.75),
                       (W * 0.85, L * 0.1, rz * 0.35), plate))
    return h.join_parts(rig, parts)


def antlers(size, hy, hz, hr, mat):
    """Роги оленя: дві гілки назад і вгору з трьома відростками."""
    p = base.part
    out = []
    for sign in (1, -1):
        root = Vector((sign * hr * 0.5, hy + hr * 0.1, hz + hr * 0.7))
        tip = root + Vector((sign * size * 0.45, size * 0.35, size * 0.85))
        out.append(beam(root, tip, hr * 0.12, mat))
        for t, off in ((0.35, (0, -0.25, 0.35)), (0.6, (sign * 0.3, -0.1,
                                                          0.3)),
                       (0.85, (sign * 0.1, 0.3, 0.25))):
            at = root.lerp(tip, t)
            out.append(beam(at, at + Vector(off) * size, hr * 0.07, mat))
    return out


def beam(a, b, radius, mat):
    """Циліндр від точки a до b — на кістці голови."""
    length = (b - a).length
    bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=radius,
                                        depth=length)
    obj = bpy.context.active_object
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = (b - a).normalized().to_track_quat("Z", "Y")
    obj.location = (a + b) * 0.5
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    group = obj.vertex_groups.new(name="head")
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    obj.data.materials.append(mat)
    return obj


def actions(rig, s, g):
    leg = g["leg"]
    # Розставлена на кут лапа по вертикалі коротша на leg·(1 − cos) —
    # на стільки ж опускається тулуб, щоб лапи не висіли над землею.
    def drop(angle):
        return -leg * (1.0 - math.cos(math.radians(angle)))

    h.action(rig, "Idle", 48, {
        1: k(),
        12: k(tail=(0, 0, 10), chest=2),
        24: k(tail=(0, 0, -10), ear_L=-15, head=4),
        36: k(tail=(0, 0, 10), chest=2),
        48: k(),
    })
    a = 24 if leg < 0.6 else 20
    frames = 20 if g["H"] < 0.9 else 24
    half = frames // 2
    h.action(rig, "Walk", frames, {
        1: k(front_L=-a, hind_R=-a, front_R=a, hind_L=a, hips_up=drop(a)),
        half // 2 + 1: k(),
        half + 1: k(front_L=a, hind_L=-a, front_R=-a, hind_R=a,
                    hips_up=drop(a)),
        half + half // 2 + 1: k(),
        frames: k(front_L=-a, hind_R=-a, front_R=a, hind_L=a,
                  hips_up=drop(a)),
    })
    style = s["attack"]
    if style == "укус":
        h.action(rig, "Attack", 18, {
            1: k(),
            4: k(hind_L=-12, hind_R=-12, head=-10),
            8: k(hips=-8, hips_up=0.04, hips_ahead=g["L"] * 0.22,
                 front_L=-35, front_R=-35, hind_L=30, hind_R=30, head=12,
                 jaw=28),
            10: k(hips_ahead=g["L"] * 0.24, hips_up=0.02, front_L=-20,
                  front_R=-20, hind_L=20, hind_R=20, head=18, jaw=0),
            14: k(hips_ahead=g["L"] * 0.08, head=5),
            18: k(),
        })
    elif style == "стрибок":
        up = g["H"] * 0.45
        h.action(rig, "Attack", 18, {
            1: k(),
            4: k(front_L=15, front_R=15, hind_L=-20, hind_R=-20,
                 hips_up=drop(20)),
            8: k(hips=-15, hips_up=up, hips_ahead=g["L"] * 0.5, front_L=-60,
                 front_R=-60, hind_L=40, hind_R=40, jaw=25),
            11: k(hips=5, hips_up=up * 0.3, hips_ahead=g["L"] * 0.7,
                  front_L=-20, front_R=-20, hind_L=20, hind_R=20),
            14: k(hips_ahead=g["L"] * 0.55, front_L=10, front_R=10),
            18: k(),
        })
    elif style == "таран":
        h.action(rig, "Attack", 20, {
            1: k(),
            # Голову вниз — роги й ікла вперед. Тулуб НЕ нахиляти: нахил
            # мордою донизу опускає передок разом із лапами під землю
            # (спіймано `check_paws`: −6…−9 см).
            # Тулуб опускається під НАЙМЕНШ розставлену лапу: під
            # найбільш розставлену — решта йде під землю (олень, химера:
            # −3 см, `check_paws`).
            5: k(head=18, hind_L=-12, hind_R=-12, hips_ahead=-0.05),
            10: k(head=25, hips_ahead=g["L"] * 0.45, front_L=-25,
                  front_R=15, hind_L=25, hind_R=-15, hips_up=drop(15)),
            12: k(hips=-10, head=-20, hips_ahead=g["L"] * 0.5,
                  hips_up=drop(10)),
            16: k(hips_ahead=g["L"] * 0.2),
            20: k(),
        })
    else:  # «лапа» — дибки й удар згори, як ведмідь
        def rear_up(angle, **more):
            return k(hips=-angle, hind_L=angle, hind_R=angle,
                     hips_up=-(g["rear"] * 0.9 - g["rear"] * 0.7)
                     * math.sin(math.radians(angle)), **more)
        h.action(rig, "Attack", 24, {
            1: k(),
            6: rear_up(45, front_L=25, front_R=10, head=25, jaw=15),
            10: rear_up(50, front_L=30, front_R=-120, head=30, jaw=25),
            14: rear_up(25, front_L=15, front_R=15, head=10),
            17: rear_up(5, front_L=5, front_R=5),
            24: k(),
        })
    lie = -(g["H"] * 0.93 - g["W"] * 0.9)
    h.action(rig, "Death", 30, {
        1: k(),
        30: k(hips=(0, 85, 0), hips_up=lie, head=15, jaw=15, front_L=-20,
              hind_L=25, tail=(0, 0, 20)),
    })
    rig.animation_data.action = bpy.data.actions["Idle"]


def check_paws(rig, g):
    """Висота лап у кожному ключовому кадрі. Стоїть і йде — найнижча лапа
    на землі (±2,5 см); атака — не нижче землі. Друкує, що не так."""
    scene = bpy.context.scene
    paws = ("front.L", "front.R", "hind.L", "hind.R")
    rest = g["paw"]
    report = []
    for name in ("Idle", "Walk", "Attack"):
        act = bpy.data.actions[name]
        rig.animation_data.action = act
        frames = sorted({int(kp.co.x) for fc in h.curves(act)
                         for kp in fc.keyframe_points})
        worst = []
        for f in frames:
            scene.frame_set(f)
            low = min((rig.matrix_world @ rig.pose.bones[b].tail).z
                      for b in paws) - rest
            worst.append(low)
            if low < -0.025 or (name != "Attack" and low > 0.025):
                WARN.append("%s кадр %d: найнижча лапа %+.3f м" %
                            (name, f, low))
        report.append("%s %+.3f…%+.3f" % (name, min(worst), max(worst)))
    rig.animation_data.action = bpy.data.actions["Idle"]
    scene.frame_set(1)
    return ", ".join(report)


def build(name, out, shots=None):
    s = SPECIES[name]
    base.clear()
    bpy.context.scene.render.fps = 24
    g = geometry(s)
    rig = h.armature(g["bones"])
    body(rig, s, g)
    actions(rig, s, g)
    paws = check_paws(rig, g)
    if shots:
        size = max(g["L"] * 1.3, g["H"] + g["head_r"] * 2 + s.get("neck", 0)
                   + s.get("antlers", 0))
        h.previews(rig, shots, zoom=max(1.0, size / 0.6))
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(out))
    print("[звір] %s → %s · лапи: %s" % (name, out, paws))
    for line in WARN:
        print("[звір] ‼ %s: %s" % (name, line))


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if not args or args[0] == "--список":
        print("[звір] види: " + ", ".join(SPECIES))
        return
    build(args[0], args[1] if len(args) > 1 else
          "art/monsters/%s.blend" % args[0],
          args[2] if len(args) > 2 else None)


if __name__ == "__main__":
    main()
