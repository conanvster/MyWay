"""Лук скелета-лучника — окрема річ у руці (25.09.2026).

Kontext у спокійній стійці лук губив (поза s22 без лука), замовник обрав
«тіло з s22 + лук окремою річчю». Проста геометрія за референсом
`wiki/img/monstry/скелет-лучник.png`: темне дерево, рекурсивні кінці,
світліша обмотка руків'я, тятива.

    blender -b -P tools/blender/make_bow.py -- <довжина> [вихід.glb]

Довжина — в одиницях файла звіра (лук успадковує масштаб кістяка).
Рукоять — у початку координат; плечі — уздовж Z Blender (у glTF це +Y),
вигин — у −Y Blender (у glTF +Z), тятива — з боку +Y.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
LENGTH = float(args[0]) if args else 1.0
OUT = args[1] if len(args) > 1 else os.path.join(ROOT, "game", "models", "own", "речі", "лук-скелета.glb")

WOOD = (0.16, 0.08, 0.04, 1)
GRIP = (0.30, 0.20, 0.12, 1)
STRING = (0.75, 0.70, 0.60, 1)


def material(name, color, rough=0.7):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = rough
    return m


def tube(name, points, radius, mat, taper=None):
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = radius
    cu.bevel_resolution = 3
    cu.use_fill_caps = True
    sp = cu.splines.new("POLY")
    sp.points.add(len(points) - 1)
    for i, p in enumerate(points):
        sp.points[i].co = (p.x, p.y, p.z, 1)
        sp.points[i].radius = taper(i / (len(points) - 1)) if taper else 1.0
    ob = bpy.data.objects.new(name, cu)
    bpy.context.collection.objects.link(ob)
    ob.data.materials.append(mat)
    return ob


def limb_point(t):
    """t від −1 (нижній кінець) до 1 (верхній). Плече вигнуте від тятиви
    (−Y), а останні 15% загинаються назад (+Y) — рекурсивні кінці."""
    z = t * LENGTH / 2
    a = abs(t)
    y = -0.10 * LENGTH * math.sin(a * math.pi / 2) ** 1.4
    if a > 0.85:
        y += 0.35 * LENGTH * (a - 0.85) ** 1.5 * 6
    return Vector((0, y, z))


bpy.ops.wm.read_factory_settings(use_empty=True)
wood, grip, string = material("Лук-дерево", WOOD), material("Лук-руків'я", GRIP, 0.9), \
    material("Лук-тятива", STRING, 0.5)
n = 60
pts = [limb_point(-1 + 2 * i / n) for i in range(n + 1)]
r = 0.018 * LENGTH
parts = [tube("Лук", pts, r, wood, taper=lambda u: 0.45 + 0.55 * math.sin(u * math.pi))]
parts.append(tube("Руків'я", [limb_point(t) for t in (-0.09, -0.03, 0.03, 0.09)],
                  r * 1.35, grip))
top, bottom = pts[-1], pts[0]
parts.append(tube("Тятива", [bottom, top], 0.0025 * LENGTH, string))

for ob in parts:
    ob.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.convert(target="MESH")
bpy.ops.object.join()
bow = bpy.context.active_object
bow.name = "Лук"
os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True)
print("[лук] %s, довжина %.3f, вершин %d" % (OUT, LENGTH, len(bow.data.vertices)))
