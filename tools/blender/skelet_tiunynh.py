"""Тюнінг скелета, поставленого вручну (09.11.2026).

Слово замовника: «я ще не достатньо якісно зробив кістки, чи можеш ти сам
затюнити те що я зробив». Розстановка замовника лишається (які кістки в
якому пальці, де приблизно суглоби); кожен суглоб руки й пальців
центрується в сітці: переріз поперек кістки (тонкий шар уздовж кістки) —
центр перерізу, зсув лише поперек кістки. Плече й основи пальців (у широкій
долоні) не рухаються. Голова дитини = хвіст батька, закрутка зберігається.

    blender -b <skelet-vruchnu2.blend> -P tools/blender/skelet_tiunynh.py -- <вихід.blend>
"""
import sys

import bpy
import numpy as np
from mathutils import Vector
from mathutils.kdtree import KDTree

VYKHID = sys.argv[sys.argv.index("--") + 1]
rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
tilo = next(o for o in bpy.data.objects if o.type == "MESH" and o.name == "Тіло")
CO = np.array([(tilo.matrix_world @ v.co)[:] for v in tilo.data.vertices])
kd = KDTree(len(CO))
for i, c in enumerate(CO):
    kd.insert(c, i)
kd.balance()
PALTSI = ("thumb", "index", "middle", "ring", "pinky")


def log(*a):
    print("[тюнінг]", *a, flush=True)


def tsentr(p, napr, sloi, rad):
    """Центр перерізу сітки площиною через p поперек napr."""
    blyzki = np.array([i for _, i, _ in kd.find_range(Vector(p), rad)])
    if len(blyzki) < 8:
        return None
    Q = CO[blyzki]
    s = np.abs((Q - p) @ napr) < sloi
    if s.sum() < 8:
        return None
    c = Q[s].mean(0)
    return p + (c - p) - napr * ((c - p) @ napr)      # лише поперек кістки


bpy.context.view_layer.objects.active = rig
rig.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
eb = rig.data.edit_bones
mw, mwi = rig.matrix_world, rig.matrix_world.inverted()
W = lambda v: np.array((mw @ v)[:])
for bik in ("l", "r"):
    # суглоби: (кістка, кінець, ширина шару, радіус)
    suhl = [("upperarm_" + bik, "tail", 0.015, 0.09), ("lowerarm_" + bik, "tail", 0.012, 0.07)]
    for p in PALTSI:
        for j in (1, 2, 3):
            suhl.append(("%s_%02d_%s" % (p, j, bik), "tail", 0.004, 0.013))
    stari = {n: W(getattr(eb[n], k)) for n, k, _, _ in suhl}
    zakrutky = {b.name: (b.tail - b.head).normalized().copy() for b in eb if b.name.endswith("_" + bik)}
    z_osi = {b.name: b.z_axis.copy() for b in eb if b.name.endswith("_" + bik)}
    for _ in range(3):
        for n, k, sl, rad in suhl:
            b = eb[n]
            napr = W(b.tail) - W(b.head)
            napr /= np.linalg.norm(napr)
            p = W(getattr(b, k))
            if n.endswith("_03_" + bik):
                # кінчик — центр трохи раніше кінця (у самому кінчику переріз мізерний)
                p = p - napr * 0.004
            c = tsentr(p, napr, sl, rad)
            if c is None:
                continue
            setattr(b, k, mwi @ Vector(c))
            # дитина починається там, де закінчився батько
            for d in b.children:
                d.head = b.tail.copy()
            if n.startswith("lowerarm_"):
                eb["hand_" + bik].head = b.tail.copy()
            if n.startswith("upperarm_"):
                eb["lowerarm_" + bik].head = b.tail.copy()
    for b in eb:
        if b.name in zakrutky:
            q = zakrutky[b.name].rotation_difference((b.tail - b.head).normalized())
            b.align_roll(q @ z_osi[b.name])
    for n, k, _, _ in suhl:
        z = np.linalg.norm(W(getattr(eb[n], k)) - stari[n])
        if z > 0.003:
            log("%s.%s зсунуто на %.1f см" % (n, k, 100 * z))
bpy.ops.object.mode_set(mode="OBJECT")
bpy.ops.wm.save_as_mainfile(filepath=VYKHID)
log("→", VYKHID)
