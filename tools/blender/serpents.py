"""Змії бестіарію (spec/monsters.md, конвеєр «З») — пустельна змія, кобра,
удав, василіск.

Замовник 19.09.2026: «зроби наступні монстри що залишились». Скелет —
ланцюг сегментів хребта від голови до хвоста; тіло — кулі вздовж
сегментів, що звужуються до хвоста; рухи — хвиля по сегментах (хода),
кидок із піднятою головою (атака), перекид черевом догори (смерть).

Перевіряється само (`check_ground`): у спокої й ході найнижча точка
тіла на землі (±2,5 см) — змія не висить і не йде під землю.

Запуск (з каталогу проєкту):
    blender --background --python tools/blender/serpents.py -- \\
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

TEX = os.path.join(h.ROOT, "art", "monsters", "textures")
OUT = os.path.join(h.ROOT, "art", "monsters")

# length — довжина тіла, r — найбільший радіус (м), segs — сегментів.
SPECIES = {
    "пустельна змія": dict(length=1.6, r=0.045, segs=10,
                           skin="луска-піщана", belly=(0.85, 0.78, 0.6),
                           eyes=(0.9, 0.7, 0.1)),
    "кобра": dict(length=2.0, r=0.06, segs=10, skin="луска-темна",
                  belly=(0.75, 0.68, 0.5), hood=True, raised=3,
                  eyes=(0.95, 0.6, 0.1)),
    "удав": dict(length=4.5, r=0.16, segs=14, skin="луска-зелена",
                 belly=(0.7, 0.66, 0.5), eyes=(0.8, 0.8, 0.2)),
    "василіск": dict(length=4.2, r=0.22, segs=12, skin="луска-темна",
                     belly=(0.4, 0.36, 0.3), crest=True, legs=True,
                     eyes=(1.0, 0.3, 0.05), glow=True),
}


def spine_z(s):
    """Хребет — на висоті найтовшого місця: інакше середина тіла йде під
    землю (перша збірка: удав −5 см, василіск −9,5 см)."""
    return max(radius(s, t / 50.0) for t in range(51))


def seg(s, j):
    """Сегмент на місці j від голови (0 — біля голови). Корінь ланцюга —
    кінчик хвоста: коли корінь був шиєю, піднята голова кобри крутила
    за собою все тіло, і хвіст ішов на 1,4 м під землю."""
    return "seg%d" % (s["segs"] - 1 - j)


def bones_for(s):
    n, L = s["segs"], s["length"]
    z = spine_z(s)
    step = L / n
    out = []
    for i in range(n):
        # seg0 — хвіст, далі до голови; кістки дивляться вперед (−Y).
        y0 = L - i * step
        out.append(("seg%d" % i, (0, y0, z), (0, y0 - step, z),
                    None if i == 0 else "seg%d" % (i - 1)))
    hl = s["r"] * 3.2
    out.append(("head", (0, 0, z), (0, -hl, z), "seg%d" % (n - 1)))
    out.append(("jaw", (0, -hl * 0.3, z - s["r"] * 0.3), (0, -hl,
                                                          z - s["r"] * 0.4),
                "head"))
    return out


def radius(s, t):
    """Товщина вздовж тіла: t = 0 біля голови, 1 — кінчик хвоста."""
    return s["r"] * (0.75 + 0.5 * math.sin(min(1.0, t * 1.3 + 0.15)
                                              * math.pi * 0.9)) \
        * (1.0 - 0.85 * max(0.0, t - 0.6) / 0.4)


def body(rig, s):
    p = base.part
    scale_mat = h.fur("Луска", (0.3, 0.3, 0.2), s["skin"])
    belly = solid("Черево", s["belly"], 0.7)
    eye = solid("Очі", s["eyes"], 0.3, glow=5.0 if s.get("glow") else 1.0)
    dark = solid("Ніс", (0.02, 0.02, 0.02), 0.5)
    bone = solid("Гребінь", (0.8, 0.75, 0.62), 0.5)
    n, L, r = s["segs"], s["length"], s["r"]
    z = spine_z(s)
    step = L / n
    parts = []
    for j in range(n):
        t = (j + 0.5) / n
        rr = radius(s, t)
        at = (0, (j + 0.5) * step, z)
        # Кулі налягають удвічі: на 0,75 кроку тіло читалось намистом.
        parts.append(p("sphere", seg(s, j), at, (rr, step * 1.05, rr),
                       scale_mat))
        parts.append(p("sphere", seg(s, j), (0, at[1], z - rr * 0.4),
                       (rr * 0.8, step * 1.0, rr * 0.6), belly))
    hl = r * 3.2
    r = z  # голова — на висоті хребта
    parts += [
        p("sphere", "head", (0, -hl * 0.45, r * 1.02), (r * 1.1, hl * 0.6,
                                                        r * 0.75), scale_mat),
        p("sphere", "jaw", (0, -hl * 0.55, r * 0.72), (r * 0.9, hl * 0.5,
                                                       r * 0.35), belly),
        p("sphere", "head", (0, -hl * 0.95, r * 1.0), (r * 0.18, r * 0.12,
                                                       r * 0.12), dark),
    ]
    for sign in (1, -1):
        parts.append(p("sphere", "head", (sign * r * 0.75, -hl * 0.55,
                                          r * 1.35),
                       (r * 0.2, r * 0.16, r * 0.18), eye))
    if s.get("hood"):
        parts.append(p("sphere", seg(s, 0), (0, step * 0.6, r * 1.1),
                       (r * 2.6, step * 0.6, r * 1.6), scale_mat))
    if s.get("crest"):
        for i in range(n // 2):
            on = "head" if i == 0 else seg(s, i - 1)
            y = -hl * 0.3 if i == 0 else (i - 0.5) * step
            parts.append(p("cone", on, (0, y, r * 2.0), (r * 0.25, r * 0.4,
                                                         r * 1.4), bone,
                           (math.radians(25), 0, 0)))
    if s.get("legs"):
        # Короткі лапи — від боку тіла рівно до землі.
        for j, y in ((1, 1.5), (4, 4.5)):
            for sign in (1, -1):
                parts.append(p("cyl", seg(s, j), (sign * r * 1.1, y * step,
                                                  r * 0.5),
                               # циліндр рушія заввишки 2 — половина
                               (r * 0.18, r * 0.18, r * 0.5), scale_mat,
                               (0, math.radians(sign * 25), 0)))
    return h.join_parts(rig, parts)


def keys(n, fn):
    """Ключовий кадр: {кістка: (обертання°, зсув)}; fn — за місцем від
    голови (0 — біля голови)."""
    out = {}
    for j in range(n):
        out["seg%d" % (n - 1 - j)] = fn(j)
    return out


def actions(rig, s):
    n = s["segs"]
    raised = s.get("raised", 0)

    def lift(i):
        # Кобра тримає передок піднятим (кут на сегмент).
        # Знак заміряно `check_ground`: з «−» голова кобри йшла на 44 см
        # під землю — у цих кісток «вгору» це «+».
        return 18.0 if i < raised else 0.0

    def wave(frame, frames, amp, extra=None):
        def fn(i):
            a = amp * math.sin(2 * math.pi * frame / frames + i * 0.7)
            return ((lift(i), 0, a), (0, 0, 0))
        k = keys(n, fn)
        if extra:
            k.update(extra)
        return k

    h.action(rig, "Idle", 48, {f: wave(f, 48, 4) for f in (1, 13, 25, 37,
                                                            48)})
    h.action(rig, "Walk", 24, {f: wave(f, 24, 12) for f in (1, 7, 13, 19,
                                                             24)})

    def strike(pitch, ahead, jaw):
        def fn(i):
            lean = pitch if i < 3 else 0.0
            # Лише нахил: зсув передньої кістки відривав голову від тіла.
            return ((lift(i) + lean, 0, 0), (0, 0, 0))
        k = keys(n, fn)
        k["jaw"] = ((jaw, 0, 0), (0, 0, 0))
        return k
    step = s["length"] / n
    h.action(rig, "Attack", 18, {
        1: keys(n, lambda i: ((lift(i), 0, 0), (0, 0, 0))),
        # «+» — голова вгору (див. `lift`): замах угору, кидок униз-уперед.
        5: strike(22, -step * 0.8, 10),
        9: strike(-8, step * 1.6, 35),
        12: strike(-4, step * 1.2, 0),
        18: keys(n, lambda i: ((lift(i), 0, 0), (0, 0, 0))),
    })
    h.action(rig, "Death", 30, {
        1: keys(n, lambda i: ((lift(i), 0, 0), (0, 0, 0))),
        # Корінь — хвіст: перекид кореня перевертає все тіло.
        30: keys(n, lambda i: ((0, 170 if i == n - 1 else 0, 0),
                               (0, 0, 0))),
    })
    rig.animation_data.action = bpy.data.actions["Idle"]


WARN = []


def check_ground(rig, s):
    scene = bpy.context.scene
    mesh = next(o for o in bpy.data.objects if o.type == "MESH")
    report = []
    for name in ("Idle", "Walk"):
        act = bpy.data.actions[name]
        rig.animation_data.action = act
        lows = []
        for f in sorted({int(kp.co.x) for fc in h.curves(act)
                         for kp in fc.keyframe_points}):
            scene.frame_set(f)
            dg = bpy.context.evaluated_depsgraph_get()
            ev = mesh.evaluated_get(dg)
            low = min((ev.matrix_world @ v.co).z for v in ev.data.vertices)
            lows.append(low)
            if abs(low) > 0.025:
                WARN.append("%s кадр %d: найнижча точка %+.3f м"
                            % (name, f, low))
        report.append("%s %+.3f…%+.3f" % (name, min(lows), max(lows)))
    rig.animation_data.action = bpy.data.actions["Idle"]
    scene.frame_set(1)
    return ", ".join(report)


def build(name, shots=None):
    s = SPECIES[name]
    base.clear()
    bpy.context.scene.render.fps = 24
    rig = h.armature(bones_for(s))
    body(rig, s)
    actions(rig, s)
    ground = check_ground(rig, s)
    if shots:
        h.previews(rig, shots, zoom=max(1.0, s["length"] / 0.9))
    out = os.path.join(OUT, name + ".blend")
    bpy.ops.wm.save_as_mainfile(filepath=out)
    print("[змія] %s → %s · земля: %s" % (name, out, ground))
    for line in WARN:
        print("[змія] ‼ %s: %s" % (name, line))


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if not args or args[0] == "--список":
        print("[змія] види: " + ", ".join(SPECIES))
        return
    build(args[0], args[1] if len(args) > 1 else None)


if __name__ == "__main__":
    main()
