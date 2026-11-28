"""Чисте обличчя на ігрову сітку NPC (28.11.2026, слово замовника: «спробуй накласти зображення
облича чистіше для усих»). Відновлене обличчя (`tools/comfyui/npc_oblychchia.py`: виріз голови з
Т-0, 1024²) проєктується спереду на голову — та сама рамка «сітка ↔ кадр», що в `proektsiia_4.py`
(межі сітки ↔ межі постаті + уточнення масштабу й зсуву за IoU силуету), — і запікається в
текстуру моделі з м'яким краєм: вага = (дивиться вперед) × (всередині еліпса вирізу).

    blender -b -P tools/blender/npc_oblychchia.py -- <hra.glb> <вихід.glb> <Т-0.png> <обличчя.png> \
        x0 y0 x1 y1
"""
import sys

import bpy
import numpy as np

A = sys.argv[sys.argv.index("--") + 1:]
VHID, VYHID, T0, OBL = A[:4]
CX0, CY0, CX1, CY1 = [float(x) for x in A[4:8]]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=VHID)
ob = next(o for o in bpy.context.scene.objects if o.type == "MESH")
bpy.context.view_layer.objects.active = ob
ob.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
me = ob.data
P = np.array([v.co[:] for v in me.vertices])
N = np.array([v.normal[:] for v in me.vertices])
lo, hi = P.min(0), P.max(0)

# кадр Т-0: маска постаті й межі (як zchytaty у proektsiia_4.py)
img = bpy.data.images.load(T0)
w, h = img.size
a = np.array(img.pixels[:]).reshape(h, w, 4)[::-1, :, :3]
tlo = np.median(np.concatenate([a[:6].reshape(-1, 3), a[:, :6].reshape(-1, 3), a[:, -6:].reshape(-1, 3)]), 0)
kil = np.concatenate([a[int(h * 0.1):int(h * 0.9), int(w * 0.12)].reshape(-1, 3),
                      a[int(h * 0.1):int(h * 0.9), int(w * 0.88)].reshape(-1, 3)])
tlo2 = np.median(kil, 0)
maska = (np.abs(a - tlo).sum(2) > 0.09) & (np.abs(a - tlo2).sum(2) > 0.09)
ys, xs = np.nonzero(maska)
x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
# спереду: камера з −Y, праве кадру = +X
px = x0 + (P[:, 0] - lo[0]) / max(hi[0] - lo[0], 1e-6) * (x1 - x0)
py = y0 + (hi[2] - P[:, 2]) / max(hi[2] - lo[2], 1e-6) * (y1 - y0)
K = 160.0 / max(w, h)
mk = np.zeros((int(h * K) + 2, int(w * K) + 2), bool)
mk[(ys * K).astype(int), (xs * K).astype(int)] = True
cxp, cyp = px.mean(), py.mean()


def iou(s_, ox, oy):
    qx = ((cxp + (px - cxp) * s_ + ox) * K).astype(int)
    qy = ((cyp + (py - cyp) * s_ + oy) * K).astype(int)
    ok = (qx >= 0) & (qy >= 0) & (qx < mk.shape[1]) & (qy < mk.shape[0])
    sil = np.zeros_like(mk)
    sil[qy[ok], qx[ok]] = True
    return (sil & mk).sum() / max((sil | mk).sum(), 1)


naikr = (iou(1.0, 0, 0), 1.0, 0.0, 0.0)
for s_ in np.linspace(0.85, 1.15, 13):
    for ox in np.linspace(-0.08 * w, 0.08 * w, 13):
        for oy in np.linspace(-0.08 * h, 0.08 * h, 13):
            v_ = iou(s_, ox, oy)
            if v_ > naikr[0]:
                naikr = (v_, s_, ox, oy)
_, s_, ox, oy = naikr
px = cxp + (px - cxp) * s_ + ox
py = cyp + (py - cyp) * s_ + oy
print("[обличчя] рамка: масштаб %.3f, зсув %+.0f %+.0f px, IoU %.3f" % (s_, ox, oy, naikr[0]), flush=True)

# координати у вирізі (v — знизу вгору, як UV) і вага
u2 = (px - CX0) / (CX1 - CX0)
v2 = 1.0 - (py - CY0) / (CY1 - CY0)
r = np.sqrt(((u2 - 0.5) / 0.5) ** 2 + ((v2 - 0.5) / 0.5) ** 2)
vaha = np.clip((-N[:, 1] - 0.2) / 0.35, 0, 1) * np.clip((0.92 - r) / 0.22, 0, 1)
print("[обличчя] вершин з вагою > 0,5: %d" % int((vaha > 0.5).sum()), flush=True)

uv_main = me.uv_layers[0].name
uvo = me.uv_layers.new(name="UVo")
lv = np.zeros(len(me.loops), int)
me.loops.foreach_get("vertex_index", lv)
uvo.data.foreach_set("uv", np.stack([u2[lv], v2[lv]], 1).ravel())
at = me.color_attributes.new("vaha_obl", "FLOAT_COLOR", "POINT")
at.data.foreach_set("color", np.repeat(vaha, 4).astype(np.float32))

mat = me.materials[0]
nt = mat.node_tree
staryi = next(n for n in nt.nodes if n.type == "TEX_IMAGE")
TEX = staryi.image.size[0]
staryi_img = staryi.image
# окремий матеріал для запікання: мішанка → випромінювання
bm_ = bpy.data.materials.new("bake")
bm_.use_nodes = True
t = bm_.node_tree
t.nodes.clear()
uvA = t.nodes.new("ShaderNodeUVMap"); uvA.uv_map = uv_main
uvB = t.nodes.new("ShaderNodeUVMap"); uvB.uv_map = "UVo"
tA = t.nodes.new("ShaderNodeTexImage"); tA.image = staryi_img
tB = t.nodes.new("ShaderNodeTexImage"); tB.image = bpy.data.images.load(OBL); tB.extension = "EXTEND"
atr = t.nodes.new("ShaderNodeAttribute"); atr.attribute_name = "vaha_obl"
mix = t.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"
em = t.nodes.new("ShaderNodeEmission")
outn = t.nodes.new("ShaderNodeOutputMaterial")
t.links.new(uvA.outputs["UV"], tA.inputs["Vector"])
t.links.new(uvB.outputs["UV"], tB.inputs["Vector"])
t.links.new(atr.outputs["Fac"], mix.inputs["Factor"])
t.links.new(tA.outputs["Color"], mix.inputs[6])
t.links.new(tB.outputs["Color"], mix.inputs[7])
t.links.new(mix.outputs[2], em.inputs["Color"])
t.links.new(em.outputs["Emission"], outn.inputs["Surface"])
nove = bpy.data.images.new("npc-kolir-obl", TEX, TEX)
ciL = t.nodes.new("ShaderNodeTexImage"); ciL.image = nove
t.nodes.active = ciL
me.materials[0] = bm_
me.uv_layers.active = me.uv_layers[uv_main]
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = 1
sc.render.bake.use_selected_to_active = False
sc.render.bake.margin = 6
bpy.ops.object.bake(type="EMIT")
import os
nove.filepath_raw = os.path.splitext(VYHID)[0] + "-колір.png"
nove.file_format = "PNG"
nove.save()
# назад: звичайний матеріал з новою текстурою; допоміжне — геть
staryi.image = nove
me.materials[0] = mat
me.uv_layers.remove(me.uv_layers["UVo"])
me.color_attributes.remove(me.color_attributes["vaha_obl"])
bpy.ops.export_scene.gltf(filepath=VYHID, export_format="GLB")
print("[обличчя] →", VYHID, flush=True)
