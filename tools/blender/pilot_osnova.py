"""Пілот Б (П-281), крок 1 — основа: тіло MPFB у білизні, без волосся й одягу.

Слово замовника 08.11.2026: вдягнена цілком модель (Г) має критичні вади
(рукави в повітрі, пластмасове волосся), тому — шарами, як манекени
Superhero (`game/models/player`): спершу гола основа в білизні, далі
волосся, очі/борода/вуса, одяг і взуття окремо.

У MPFB білизни немає, тож тут вона робиться з самого тіла: грані в смузі
грудей (топ) і на тазі (трусики) копіюються окремою сіткою, відсуваються
вздовж нормалей на кілька міліметрів і стовщуються. Ваги кісток —
скопійовані з тіла, тож білизна рухається разом зі шкірою.

    blender -b -P tools/blender/pilot_b.py -- <тека> --зачіска - --без-рендеру
    blender -b <тека>/pilot.blend -P tools/blender/pilot_osnova.py -- <тека>
        → <тека>/основа.blend (далі pilot_eksport.py — рухи й GLB)
        [--чоловік] [--ікла]

09.11.2026, усі раси (слово замовника: «модель топлес з усіма
налаштуваннями»): `--чоловік` — без верху, низ — короткі боксери до
середини стегна; `--ікла` — орки: два нижні ікла з-за губи (окрема сітка
«Ікла», вага — голова).
"""
import functools
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

print = functools.partial(print, flush=True)
ARGS = sys.argv[sys.argv.index("--") + 1:]
KUDY = os.path.abspath(ARGS[0])
CHOLOVIK = "--чоловік" in ARGS
IKLA = "--ікла" in ARGS

h = bpy.data.objects["Human"]
rig = bpy.data.objects["Human.rig"]
me = h.data

# Форми (цілі MakeHuman) — у сітку: координати сітки = тіло в спокої.
if me.shape_keys:
    bpy.context.view_layer.objects.active = h
    h.shape_key_add(name="змішано", from_mix=True)
    for k in list(me.shape_keys.key_blocks):
        if k.name != "змішано":
            h.shape_key_remove(k)
    h.shape_key_remove(me.shape_keys.key_blocks["змішано"])

gi = {g.name: g.index for g in h.vertex_groups}
body = gi["body"]
co = [v.co.copy() for v in me.vertices]


def w(v, name):
    i = gi.get(name)
    if i is None:
        return 0.0
    return next((g.weight for g in me.vertices[v].groups if g.group == i), 0.0)


v_body = [any(g.group == body and g.weight > 0.5 for g in v.groups)
          for v in me.vertices]

# Орієнтири з самого тіла: соски (матеріал Human.nipple) і промежина.
mi = {m.name: i for i, m in enumerate(me.materials)}
nip = [p.center for p in me.polygons if p.material_index == mi.get("Human.nipple")]
nip_z = sum(c.z for c in nip) / len(nip)
nip_x = sum(abs(c.x) for c in nip) / len(nip)
krok = min(co[i].z for i in range(len(co))
           if v_body[i] and abs(co[i].x) < 0.004 and 0.7 < co[i].z < 1.0
           and co[i].y < 0.05)
print("[основа] соски z %.3f (x ±%.3f), промежина z %.3f" % (nip_z, nip_x, krok))


def ruka(i):
    return max(w(i, "upperarm_l"), w(i, "upperarm_r"),
               w(i, "clavicle_l"), w(i, "clavicle_r"))


def zad(c):
    """0 спереду … 1 ззаду, плавно (перехід боком, без сходинки на краю)."""
    t = min(1.0, max(0.0, (c.y + 0.03) / 0.06))
    return t * t * (3 - 2 * t)


def mizh(a, b, t):
    return a + (b - a) * t


# Значення > 0 — усередині білизни; край — там, де 0 (розріз по ребрах).
def top(i):
    c = co[i]
    k = zad(c)
    # Бандо: від-під грудей до трохи вище сосків; посередині спереду
    # верхній край плавно нижчий (виріз між чашками).
    u = abs(c.x) / nip_x
    vyriz = 0.03 * max(0.0, 1.0 - u * u)
    hi = mizh(nip_z + 0.05 - vyriz, nip_z + 0.025, k)
    lo = mizh(nip_z - 0.075, nip_z - 0.045, k)
    return min(c.z - lo, hi - c.z, (0.4 - ruka(i)) * 0.1)


def boksery(i):
    c = co[i]
    k = zad(c)
    lo = mizh(krok - 0.085, krok - 0.095, k)
    hi = mizh(krok + 0.125, krok + 0.145, k)
    return min(c.z - lo, hi - c.z)


def trusy(i):
    c = co[i]
    ax = abs(c.x)
    k = zad(c)
    # перед: низька посадка, високий виріз на стегнах; зад закриває сідниці
    lo = mizh(krok - 0.012 + 0.55 * ax, krok - 0.045 + 0.30 * ax, k)
    hi = mizh(krok + 0.105 + 0.12 * ax, krok + 0.115 + 0.10 * ax, k)
    return min(c.z - lo, hi - c.z)


def rozriz(bm, f):
    """Лишити частину сітки, де f > 0, розрізавши ребра по f = 0."""
    for e in [e for e in bm.edges
              if f[e.verts[0]] * f[e.verts[1]] < 0]:
        a, b = e.verts
        t = f[a] / (f[a] - f[b])
        _, nv = bmesh.utils.edge_split(e, a, t)
        f[nv] = 0.0
    for face in list(bm.faces):
        nuli = [v for v in face.verts if f[v] == 0.0]
        if len(nuli) == 2 and not any(nuli[1] in e.verts
                                      for e in nuli[0].link_edges
                                      if e in face.edges):
            bmesh.utils.face_split(face, nuli[0], nuli[1])
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if f[v] < 0],
                     context="VERTS")


def zrobyty(name, test, vidstup, tovshch, kolir):
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    f = {v: (test(v.index) if v_body[v.index] else -1.0) for v in bm.verts}
    rozriz(bm, f)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces],
                     context="VERTS")
    # Дрібні острівці (окремі грані на межі) — геть.
    bm.verts.ensure_lookup_table()
    bachyv, ostrovy = set(), []
    for f in bm.faces:
        if f in bachyv:
            continue
        stos, o_ = [f], []
        bachyv.add(f)
        while stos:
            g = stos.pop()
            o_.append(g)
            for e in g.edges:
                for n in e.link_faces:
                    if n not in bachyv:
                        bachyv.add(n)
                        stos.append(n)
        ostrovy.append(o_)
    dribni = [f for o_ in ostrovy if len(o_) < 40 for f in o_]
    bmesh.ops.delete(bm, geom=dribni, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces],
                     context="VERTS")
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * vidstup
    nova = bpy.data.meshes.new(name)
    bm.to_mesh(nova)
    bm.free()
    nova.materials.clear()
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*kolir, 1)
    b.inputs["Roughness"].default_value = 0.55
    nova.materials.append(m)
    for p in nova.polygons:
        p.material_index = 0
        p.use_smooth = True
    o = bpy.data.objects.new(name, nova)
    bpy.context.scene.collection.objects.link(o)
    o.parent = rig
    # Ваги: bmesh зберіг deform-шар, імена груп — як у тіла.
    for g in h.vertex_groups:
        o.vertex_groups.new(name=g.name)
    for g in list(o.vertex_groups):
        if not (g.name in rig.data.bones):
            o.vertex_groups.remove(g)
    mo = o.modifiers.new("Armature", "ARMATURE")
    mo.object = rig
    so = o.modifiers.new("Товщина", "SOLIDIFY")
    so.thickness = tovshch
    so.offset = 1.0
    sm = o.modifiers.new("Гладко", "SUBSURF")
    sm.levels = sm.render_levels = 1
    print("[основа] %s: %d граней" % (name, len(nova.polygons)))
    return o


if CHOLOVIK:
    zrobyty("білизна-низ", boksery, 0.0035, 0.0025, (0.055, 0.055, 0.06))
else:
    zrobyty("білизна-верх", top, 0.0035, 0.0025, (0.055, 0.055, 0.06))
    zrobyty("білизна-низ", trusy, 0.0025, 0.0025, (0.055, 0.055, 0.06))


def ikla():
    """Два нижні ікла біля кутиків рота: від-під нижньої губи вгору,
    трохи назовні й уперед, злегка вигнуті."""
    gr = gi.get("lips")
    guby = [co[v.index] for v in me.vertices
            if gr is not None and any(g.group == gr and g.weight > 0.5 for g in v.groups)]
    if not guby:
        print("[основа] ‼ групи губ немає — ікла не ставлю")
        return
    x_k = max(abs(c.x) for c in guby)
    z_n = min(c.z for c in guby)
    y_p = min(c.y for c in guby)
    bm = bmesh.new()
    for zn in (-1, 1):
        baza = Vector((zn * x_k * 0.72, y_p + 0.010, z_n - 0.004))
        os_ = Vector((zn * 0.25, -0.30, 1.0)).normalized()
        sehm, kil = 6, 10
        kiltsia = []
        for i in range(sehm + 1):
            t = i / sehm
            r = 0.0052 * (1 - t) ** 0.8 + 0.0004
            tsentr = baza + os_ * (0.026 * t) + Vector((zn * 0.003, -0.004, 0)) * t * t
            u = os_.cross(Vector((1, 0, 0))).normalized()
            v = os_.cross(u).normalized()
            kiltsia.append([bm.verts.new(tsentr + (u * math.cos(a) + v * math.sin(a)) * r)
                            for a in [2 * math.pi * j / kil for j in range(kil)]])
        for a_, b_ in zip(kiltsia, kiltsia[1:]):
            for j in range(kil):
                bm.faces.new((a_[j], a_[(j + 1) % kil], b_[(j + 1) % kil], b_[j]))
        bm.faces.new(list(reversed(kiltsia[0])))
        bm.faces.new(kiltsia[-1])
    nova = bpy.data.meshes.new("Ікла")
    bm.to_mesh(nova)
    bm.free()
    m = bpy.data.materials.new("Ікла")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.78, 0.72, 0.58, 1)
    b.inputs["Roughness"].default_value = 0.4
    nova.materials.append(m)
    for p in nova.polygons:
        p.use_smooth = True
    o = bpy.data.objects.new("Ікла", nova)
    bpy.context.scene.collection.objects.link(o)
    o.parent = rig
    o.vertex_groups.new(name="head").add(list(range(len(nova.vertices))), 1.0, "REPLACE")
    o.modifiers.new("Armature", "ARMATURE").object = rig
    print("[основа] ікла: кутики рота x ±%.3f, низ губи z %.3f" % (x_k, z_n))


if IKLA:
    ikla()
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(KUDY, "основа.blend"))
print("[основа] →", os.path.join(KUDY, "основа.blend"))
