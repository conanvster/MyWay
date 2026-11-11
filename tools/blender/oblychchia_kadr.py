"""Обличчя моделі генератора: кадр спереду → (FLUX) → назад у текстуру (П-285, 11.11.2026).

Модель генератора (Pixal3D) лишається як є — форма, одяг, борода. Слабке місце — розмита
текстура обличчя. Тут: ортографічний кадр голови спереду (лише колір текстури, без світла),
його перемальовує FLUX (`tools/comfyui/oblychchia_flux.py`), і цей самий скрипт кладе
перемальоване назад у розгортку — лише там, де поверхня дивиться в камеру й нічим не
затулена; боки й потилиця лишаються старі.

    blender -b <модель.blend> -P tools/blender/oblychchia_kadr.py -- кадр <тека>
    blender -b <модель.blend> -P tools/blender/oblychchia_kadr.py -- назад <тека> <вихід.blend> \
        [--кадр <перемальований.png>] [--сила 1.0]

<тека>/кадр.png — вхід для FLUX, <тека>/камера.json — рамка кадру.
"""
import json
import os
import sys

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ARGS = sys.argv[sys.argv.index("--") + 1:]
DIIA, TEKA = ARGS[0], os.path.abspath(ARGS[1])
os.makedirs(TEKA, exist_ok=True)
ROZMIR = 1024


def arg(k, typ, d):
    return typ(ARGS[ARGS.index(k) + 1]) if k in ARGS else d


def log(*a):
    print("[обличчя]", *a)
    sys.stdout.flush()


tilo = bpy.data.objects["Тіло"]
me = tilo.data
mw = tilo.matrix_world
mat = me.materials[0]
nt = mat.node_tree
bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
tex = bsdf.inputs["Base Color"].links[0].from_node
assert tex.type == "TEX_IMAGE"

# спокійна поза (T), без рухів
for o in bpy.data.objects:
    if o.type == "ARMATURE":
        o.data.pose_position = "REST"
bpy.context.view_layer.update()

V = np.array([(mw @ v.co)[:] for v in me.vertices])
VN = np.array([(mw.to_3x3() @ v.normal).normalized()[:] for v in me.vertices])
gi = tilo.vertex_groups["head"].index
wh = np.zeros(len(me.vertices))
for v in me.vertices:
    for g in v.groups:
        if g.group == gi:
            wh[v.index] = g.weight
hol = wh > 0.5
lo, hi = V[hol].min(0), V[hol].max(0)

if DIIA == "кадр":
    # рамка: голова з вухами й бородою, квадрат
    cx = 0.0
    S = max(hi[0] - lo[0], hi[2] - lo[2]) * 1.12
    cz = (hi[2] + lo[2]) / 2
    ymin = V[:, 1].min()
    json.dump({"cx": cx, "cz": cz, "S": S}, open(os.path.join(TEKA, "камера.json"), "w"))
    cam = bpy.data.objects.new("кам", bpy.data.cameras.new("кам"))
    bpy.context.scene.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = S
    cam.location = (cx, ymin - 2.0, cz)
    cam.rotation_euler = (np.pi / 2, 0, 0)
    cam.data.clip_end = 20
    sc = bpy.context.scene
    sc.camera = cam
    # лише колір текстури
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(tex.outputs[0], em.inputs[0])
    out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    nt.links.new(em.outputs[0], out.inputs[0])
    for o in bpy.data.objects:
        if o.type == "MESH" and o != tilo:
            o.hide_render = True
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = sc.render.resolution_y = ROZMIR
    sc.render.film_transparent = False
    sc.view_settings.view_transform = "Standard"
    w = sc.world or bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.05, 0.055, 1)
    sc.render.filepath = os.path.join(TEKA, "кадр.png")
    bpy.ops.render.render(write_still=True)
    log("→", sc.render.filepath, "рамка %.3f м" % S)
    sys.exit(0)

# ── назад у розгортку ────────────────────────────────────────────────
VYHID = os.path.abspath(ARGS[2])
KADR = os.path.abspath(arg("--кадр", str, os.path.join(TEKA, "flux.png")))
SYLA = arg("--сила", float, 1.0)
k = json.load(open(os.path.join(TEKA, "камера.json")))
cx, cz, S = k["cx"], k["cz"], k["S"]

me.calc_loop_triangles()
T = [tuple(t.vertices) for t in me.loop_triangles]
bvh = BVHTree.FromPolygons([tuple(v) for v in V], T)
u = (V[:, 0] - cx) / S + 0.5
w_ = (V[:, 2] - cz) / S + 0.5
lyce = np.clip(-VN[:, 1], 0, 1)                       # камера дивиться вздовж +Y
vaga = np.clip((lyce - 0.3) / 0.4, 0, 1)
vaga = vaga * vaga * (3 - 2 * vaga)
kray = np.minimum.reduce([u, 1 - u, w_, 1 - w_])       # до краю кадру
vaga *= np.clip(kray / 0.06, 0, 1)
vaga[wh < 0.3] = 0
napr = Vector((0, -1, 0))
for i in np.nonzero(vaga > 0)[0]:
    p = Vector(V[i]) + Vector(VN[i]) * 0.002
    if bvh.ray_cast(p, napr, 3.0)[0] is not None:
        vaga[i] = 0
# згладити межу
sus = [[] for _ in me.vertices]
for e in me.edges:
    a, b = e.vertices
    sus[a].append(b)
    sus[b].append(a)
for _ in range(6):
    nv = vaga.copy()
    for i in np.nonzero(wh > 0.2)[0]:
        if sus[i]:
            nv[i] = min(vaga[i], 0.5 * vaga[i] + 0.5 * vaga[sus[i]].mean())
    vaga = nv
vaga *= SYLA
log("вершин під перемальоване: %d (вага > 0,5: %d)" % ((vaga > 0.01).sum(), (vaga > 0.5).sum()))

uv2 = me.uv_layers.new(name="кадр")
for l in me.loops:
    uv2.data[l.index].uv = (u[l.vertex_index], w_[l.vertex_index])
ca = me.color_attributes.new("вага", "FLOAT_COLOR", "POINT")
for i, v in enumerate(vaga):
    ca.data[i].color = (v, v, v, 1)

img_k = bpy.data.images.load(KADR)
stare = tex.image
N = stare.size[0]
nove = bpy.data.images.new("шкіра-обличчя", N, N, alpha=False)
tk = nt.nodes.new("ShaderNodeTexImage")
tk.image = img_k
tk.extension = "EXTEND"
um = nt.nodes.new("ShaderNodeUVMap")
um.uv_map = "кадр"
nt.links.new(um.outputs[0], tk.inputs[0])
va = nt.nodes.new("ShaderNodeVertexColor")
va.layer_name = "вага"
mx = nt.nodes.new("ShaderNodeMixRGB")
nt.links.new(va.outputs[0], mx.inputs[0])
nt.links.new(tex.outputs[0], mx.inputs[1])
nt.links.new(tk.outputs[0], mx.inputs[2])
em = nt.nodes.new("ShaderNodeEmission")
nt.links.new(mx.outputs[0], em.inputs[0])
out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
stary_vyhid = out.inputs[0].links[0].from_socket
nt.links.new(em.outputs[0], out.inputs[0])
tn = nt.nodes.new("ShaderNodeTexImage")
tn.image = nove
nt.nodes.active = tn

sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.samples = 1
sc.cycles.device = "CPU"
sc.view_settings.view_transform = "Standard"
bpy.ops.object.select_all(action="DESELECT")
tilo.select_set(True)
bpy.context.view_layer.objects.active = tilo
me.uv_layers.active = me.uv_layers[0]
sc.render.bake.margin = 6
bpy.ops.object.bake(type="EMIT")
shliakh = os.path.splitext(VYHID)[0] + "_шкіра.png"
nove.filepath_raw = shliakh
nove.file_format = "PNG"
nove.save()
log("→", shliakh)

# матеріал назад, із новою текстурою
nt.links.new(stary_vyhid, out.inputs[0])
tex.image = nove
nove.pack()
for n in (tk, um, va, mx, em, tn):
    nt.nodes.remove(n)
me.uv_layers.remove(me.uv_layers["кадр"])
me.color_attributes.remove(me.color_attributes["вага"])
bpy.ops.wm.save_as_mainfile(filepath=VYHID)
log("→", VYHID)
