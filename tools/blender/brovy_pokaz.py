"""Показ двох способів брів на одному обличчі (19.11.2026, план 15.11 крок 4 — розвилка;
слово замовника: «так - покажи обидва способи брів»).

Моделі «з нуля» мають брови, запечені в текстуру голови. Два способи дати вибір брів:
  (а) сітки-картки як у людини-жінки (MPFB): запечені брови затерти в текстурі, поверх —
      смужка-сітка над шкірою з текстурою брів MPFB (CC0) і прозорістю;
  (б) лише текстура: запечені брови перефарбувати, або затерти й намалювати нову форму
      (той самий малюнок MPFB, але пласко в шкірі).

Затирання й малювання — у кадрі спереду (як у maski_z_nulia.py), кадр проєктується на перед
голови в матеріалі. Рендер Cycles на CPU, спереду й на три чверті.

    blender -b --factory-startup -P tools/blender/brovy_pokaz.py -- <модель.glb> <точки.npy> <тека>
"""
import os
import sys

import bpy
import cv2
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

A = sys.argv[sys.argv.index("--") + 1:]
MODEL, TOCHKY, TEKA = os.path.abspath(A[0]), os.path.abspath(A[1]), os.path.abspath(A[2])
os.makedirs(TEKA, exist_ok=True)
MPFB = os.path.expanduser("~/.config/blender/5.2/extensions/.user/blender_org/mpfb/data/eyebrows")
KADR = 1024
S = 0.30


def log(*a):
    print("[брови]", *a, flush=True)


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=MODEL)
sc = bpy.context.scene
tilo = next(o for o in sc.objects if o.type == "MESH"
            and any(m and m.name == "шкіра-голова" for m in o.data.materials))
for o in sc.objects:
    if o.type == "MESH":
        for m in list(o.modifiers):
            if m.type == "ARMATURE":
                o.modifiers.remove(m)
        # лише тіло: волосся, бороди, білизна — геть із кадру
        if o is not tilo:
            o.hide_render = True
            log("сховано", o.name)
if tilo.data.shape_keys:
    for k in tilo.data.shape_keys.key_blocks:
        k.value = 0.0
me = tilo.data
mw = tilo.matrix_world
hi = next(i for i, m in enumerate(me.materials) if m and m.name == "шкіра-голова")
V = np.array([mw @ v.co for v in me.vertices])
hol_v = np.zeros(len(V), bool)
for p in me.polygons:
    if p.material_index == hi:
        hol_v[list(p.vertices)] = True
H = V[hol_v]
top = float(H[:, 2].max())
cz = top - 0.13
cx = float(np.median(H[:, 0]))
ymin = float(H[:, 1].min())

# ── кадр спереду: колір текстури як є (Standard — без AgX, щоб колір у кадрі = альбедо) ──
sc.view_settings.view_transform = "Standard"
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.light = "FLAT"
sc.display.shading.color_type = "TEXTURE"
sc.display.shading.background_type = "VIEWPORT"
sc.display.shading.background_color = (0.5, 0.5, 0.5)
sc.render.resolution_x = sc.render.resolution_y = KADR
cam = bpy.data.objects.new("кадр", bpy.data.cameras.new("кадр"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.type = "ORTHO"
cam.data.ortho_scale = S
cam.location = Vector((cx, ymin - 1.0, cz))
cam.rotation_euler = (1.5707963, 0, 0)
kadr_f = os.path.join(TEKA, "кадр.png")
sc.render.filepath = kadr_f
bpy.ops.render.render(write_still=True)
kadr = cv2.imread(kadr_f)

F = np.load(TOCHKY)
# брови MediaPipe, від середини обличчя назовні: верх і низ; сторона +1 — праворуч у кадрі
BROVY = {+1: ([336, 296, 334, 293, 300], [285, 295, 282, 283, 276]),
         -1: ([107, 66, 105, 63, 70], [55, 65, 52, 53, 46])}

# ── маска запечених брів і затирання ────────────────────────────────
maska = np.zeros((KADR, KADR), np.uint8)
for verh, nyz in BROVY.values():
    poly = np.concatenate([F[verh], F[nyz][::-1]]).astype(np.int32)
    cv2.fillPoly(maska, [poly], 255)
maska = cv2.dilate(maska, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (27, 31)))
chyste = cv2.inpaint(kadr, maska, 15, cv2.INPAINT_TELEA)
cv2.imwrite(os.path.join(TEKA, "затерте.png"), chyste)
# м'яка межа області, яку кадр підміняє в текстурі
zona = cv2.dilate(maska, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (41, 41)))
zona = cv2.GaussianBlur(zona, (0, 0), 6)


# ── малюнок брів MPFB: прямокутник текстури на брову кадру ───────────
def mpfb(nazva):
    """Текстура (BGRA) і для кожної сторони: (u_всередині, u_назовні, v_низ, v_верх)."""
    tex = cv2.imread(os.path.join(MPFB, nazva, nazva + ".png"), cv2.IMREAD_UNCHANGED)
    v, vt, vi = [], [], {}
    for l in open(os.path.join(MPFB, nazva, nazva + ".obj")):
        p = l.split()
        if not p:
            continue
        if p[0] == "v":
            v.append([float(x) for x in p[1:4]])
        elif p[0] == "vt":
            vt.append([float(x) for x in p[1:3]])
        elif p[0] == "f":
            for q in p[1:]:
                a, b = q.split("/")[:2]
                vi[int(b) - 1] = int(a) - 1
    v, vt = np.array(v), np.array(vt)
    st = {}
    for s in (+1, -1):
        ks = [k for k in vi if v[vi[k], 0] * s > 0]
        uv = vt[ks]
        xs = np.abs(v[[vi[k] for k in ks], 0])
        u_in, u_out = uv[xs.argmin(), 0], uv[xs.argmax(), 0]
        st[s] = (u_in, u_out, uv[:, 1].min(), uv[:, 1].max())
    return tex, st


def priamokutnyk(s, st, dovzh=1.18, zsuv=0.0, tovshch=1.5):
    """Кути в кадрі: початок, вектор уздовж, вектор угору (пікселі), і uv-кути."""
    verh, nyz = BROVY[s]
    seredyna = (F[verh] + F[nyz]) / 2
    p_in, p_out = seredyna[0], seredyna[-1]
    vzd = (p_out - p_in) * dovzh
    p0 = p_in - (p_out - p_in) * (dovzh - 1) / 2
    u_in, u_out, v_lo, v_hi = st
    L = np.linalg.norm(vzd)
    h = L * (v_hi - v_lo) / abs(u_out - u_in) * tovshch
    vgoru = np.array([vzd[1], -vzd[0]]) / L * h          # перпендикуляр угору в кадрі (y вниз)
    if vgoru[1] > 0:
        vgoru = -vgoru
    # центр прямокутника — по висоті трохи вище середини брови (дуга малюнка вгорі)
    c = seredyna.mean(0) + vgoru * zsuv
    p0 = c - vzd / 2 - vgoru / 2
    return p0, vzd, vgoru


def namaliuvaty(osnova, nazva, kolir, zsuv=0.0):
    """Брови MPFB пласко в кадр (спосіб б) — перенесення текстури афінним перетворенням."""
    tex, st = mpfb(nazva)
    out = osnova.astype(np.float32)
    T = tex.shape[0]
    for s in (+1, -1):
        p0, vzd, vgoru = priamokutnyk(s, st[s], zsuv=zsuv)
        u_in, u_out, v_lo, v_hi = st[s]
        src = np.float32([[u_in * T, (1 - v_lo) * T], [u_out * T, (1 - v_lo) * T],
                          [u_in * T, (1 - v_hi) * T]])
        dst = np.float32([p0, p0 + vzd, p0 + vgoru])
        M = cv2.getAffineTransform(src, dst)
        w = cv2.warpAffine(tex, M, (KADR, KADR), flags=cv2.INTER_LINEAR,
                           borderMode=cv2.BORDER_CONSTANT, borderValue=(0, 0, 0, 0)).astype(np.float32)
        a = w[..., 3:] / 255.0
        lum = w[..., :3].mean(2, keepdims=True) / 255.0
        bgr = np.array(kolir[::-1], np.float32) * 255 * (0.55 + 0.9 * lum)
        out = out * (1 - a * 0.92) + bgr * a * 0.92
    return np.clip(out, 0, 255).astype(np.uint8)


def perefarbuvaty(kolir, sila=1.0):
    """Спосіб б без зміни форми: темнота брови відносно затертої шкіри → новий колір."""
    k = kadr.astype(np.float32)
    c = chyste.astype(np.float32)
    d = np.clip(1 - k.mean(2) / np.maximum(c.mean(2), 1), 0, 1)[..., None] * (maska[..., None] > 0)
    d = np.clip(d * 1.3, 0, 1) * sila
    # фактура волосинок лишається: яскравість брови відносно її середньої
    lum = k.mean(2, keepdims=True)
    sered = max(float(lum[maska > 0].mean()), 1)
    bgr = np.array(kolir[::-1], np.float32) * 255 * np.clip(0.35 + 0.65 * lum / sered, 0, 2)
    return np.clip(c * (1 - d) + bgr * d, 0, 255).astype(np.uint8)


# ── матеріал голови: кадр поверх текстури на передній частині ───────
mat = me.materials[hi]
nt = mat.node_tree
bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
lnk = bsdf.inputs["Base Color"].links
stare = lnk[0].from_socket if lnk else None
geo = nt.nodes.new("ShaderNodeNewGeometry")
sep = nt.nodes.new("ShaderNodeSeparateXYZ")
nt.links.new(geo.outputs["Position"], sep.inputs[0])


def matem(op, a, b):
    n = nt.nodes.new("ShaderNodeMath")
    n.operation = op
    for i, x in enumerate((a, b)):
        if isinstance(x, (int, float)):
            n.inputs[i].default_value = x
        else:
            nt.links.new(x, n.inputs[i])
    return n.outputs[0]


u = matem("ADD", matem("DIVIDE", matem("SUBTRACT", sep.outputs[0], cx), S), 0.5)
v = matem("ADD", matem("DIVIDE", matem("SUBTRACT", sep.outputs[2], cz), S), 0.5)
comb = nt.nodes.new("ShaderNodeCombineXYZ")
nt.links.new(u, comb.inputs[0])
nt.links.new(v, comb.inputs[1])
img_k = nt.nodes.new("ShaderNodeTexImage")
img_k.extension = "CLIP"
img_m = nt.nodes.new("ShaderNodeTexImage")
img_m.extension = "CLIP"
nt.links.new(comb.outputs[0], img_k.inputs[0])
nt.links.new(comb.outputs[0], img_m.inputs[0])
sepn = nt.nodes.new("ShaderNodeSeparateXYZ")
nt.links.new(geo.outputs["Normal"], sepn.inputs[0])
pered = matem("MULTIPLY", matem("SUBTRACT", matem("MULTIPLY", sepn.outputs[1], -1.0), 0.35), 4.0)
pered.node.use_clamp = True
fak = matem("MULTIPLY", pered, img_m.outputs["Color"])
mix = nt.nodes.new("ShaderNodeMix")
mix.data_type = "RGBA"
nt.links.new(fak, mix.inputs["Factor"])
if stare is not None:
    nt.links.new(stare, mix.inputs["A"])
nt.links.new(img_k.outputs["Color"], mix.inputs["B"])
nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
cv2.imwrite(os.path.join(TEKA, "зона.png"), zona)
img_m.image = bpy.data.images.load(os.path.join(TEKA, "зона.png"))
img_m.image.colorspace_settings.name = "Non-Color"


# ── картки (спосіб а): смужка-сітка над шкірою ───────────────────────
dg = bpy.context.evaluated_depsgraph_get()
bvh = BVHTree.FromObject(tilo, dg)


def u_svit(px):
    return cx + (px[0] / KADR - 0.5) * S, cz - (px[1] / KADR - 0.5) * S


def kartky(nazva, kolir, zsuv=0.0, vidstup=0.0012):
    tex, st = mpfb(nazva)
    ob = []
    teks = bpy.data.images.load(os.path.join(MPFB, nazva, nazva + ".png"), check_existing=True)
    m = bpy.data.materials.new("брови-" + nazva)
    m.use_nodes = True
    t = m.node_tree
    b = t.nodes["Principled BSDF"]
    ti = t.nodes.new("ShaderNodeTexImage")
    ti.image = teks
    # як у грі (avatar_hair): колір волосся × яскравість малюнка
    rgb = t.nodes.new("ShaderNodeRGB")
    rgb.outputs[0].default_value = (*kolir, 1)
    mul = t.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    t.links.new(rgb.outputs[0], mul.inputs["A"])
    t.links.new(ti.outputs["Color"], mul.inputs["B"])
    # малюнок MPFB темний — нормувати до середньої яскравості волосинок, щоб колір був кольором
    a_ = tex[..., 3] > 128
    sered = float(tex[..., :3][a_].mean()) / 255 if a_.any() else 0.3
    sk = t.nodes.new("ShaderNodeVectorMath")
    sk.operation = "SCALE"
    sered = sered ** 2.2                                   # текстура в sRGB, множення — в лінійному
    sk.inputs["Scale"].default_value = min(1.0 / max(sered, 0.01), 25.0) * 0.8
    t.links.new(mul.outputs["Result"], sk.inputs[0])
    t.links.new(sk.outputs[0], b.inputs["Base Color"])
    t.links.new(ti.outputs["Alpha"], b.inputs["Alpha"])
    b.inputs["Roughness"].default_value = 0.7
    NU, NV = 24, 6
    for s in (+1, -1):
        p0, vzd, vgoru = priamokutnyk(s, st[s], zsuv=zsuv)
        u_in, u_out, v_lo, v_hi = st[s]
        verts, uvs = [], []
        for j in range(NV + 1):
            for i in range(NU + 1):
                a_, b_ = i / NU, j / NV
                px = p0 + vzd * a_ + vgoru * b_
                x, z = u_svit(px)
                hit = bvh.ray_cast(Vector((x, ymin - 0.5, z)), Vector((0, 1, 0)))
                if hit[0] is None:
                    co = Vector((x, ymin, z))
                else:
                    n = hit[1]
                    co = hit[0] + n * vidstup
                verts.append(co)
                uvs.append((u_in + (u_out - u_in) * a_, v_lo + (v_hi - v_lo) * b_))
        faces = [(j * (NU + 1) + i, j * (NU + 1) + i + 1, (j + 1) * (NU + 1) + i + 1, (j + 1) * (NU + 1) + i)
                 for j in range(NV) for i in range(NU)]
        mm = bpy.data.meshes.new("Брови")
        mm.from_pydata([tuple(c) for c in verts], [], faces)
        uvl = mm.uv_layers.new()
        for p in mm.polygons:
            for li in p.loop_indices:
                uvl.data[li].uv = uvs[mm.loops[li].vertex_index]
        mm.materials.append(m)
        o = bpy.data.objects.new("Брови-%s-%d" % (nazva, s), mm)
        sc.collection.objects.link(o)
        ob.append(o)
    return ob


# ── сцена рендеру ───────────────────────────────────────────────────
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = 48
sc.cycles.use_denoising = True
sc.view_settings.view_transform = "Standard"
sc.render.resolution_x = sc.render.resolution_y = 640
w = bpy.data.worlds.new("світ")
w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.42, 0.42, 0.44, 1)
w.node_tree.nodes["Background"].inputs[1].default_value = 0.9
sc.world = w
sun = bpy.data.objects.new("сонце", bpy.data.lights.new("сонце", "SUN"))
sun.data.energy = 3.0
sun.rotation_euler = (0.9, 0.25, -0.35)
sc.collection.objects.link(sun)
cam2 = bpy.data.objects.new("фото", bpy.data.cameras.new("фото"))
sc.collection.objects.link(cam2)
cam2.data.lens = 85
sc.camera = cam2
_bz = float(np.mean([u_svit(F[i])[1] for v_ in BROVY.values() for i in v_[0] + v_[1]]))
tsentr = Vector((cx, float(np.median(H[:, 1])), _bz - 0.012))   # брови й очі
VYDY = {"спереду": (0.0, 0.42), "три-чверті": (0.7, 0.42)}


def znimok(nazva):
    for vyd, (kut, dal) in VYDY.items():
        d = Vector((np.sin(kut), -np.cos(kut), 0.03)) * dal
        cam2.location = tsentr + d
        cam2.rotation_euler = (tsentr - cam2.location).to_track_quat("-Z", "Y").to_euler()
        cam2.data.lens = 105
        sc.render.filepath = os.path.join(TEKA, "%s-%s.png" % (nazva, vyd))
        bpy.ops.render.render(write_still=True)
    log("знімок", nazva)


def kadr_u_material(img_bgr, nazva):
    f = os.path.join(TEKA, "кадр-%s.png" % nazva)
    cv2.imwrite(f, img_bgr)
    img_k.image = bpy.data.images.load(f)


TEMNI, SVITLI, CHORNI = (0.16, 0.10, 0.06), (0.62, 0.48, 0.30), (0.05, 0.04, 0.035)
# 0 — як є
img_m.image = None
mix.inputs["Factor"].default_value = 0
nt.links.remove(fak.links[0])
znimok("0-як-є")
nt.links.new(fak, mix.inputs["Factor"])
img_m.image = bpy.data.images.load(os.path.join(TEKA, "зона.png"))
img_m.image.colorspace_settings.name = "Non-Color"
# б — лише текстура
kadr_u_material(perefarbuvaty(SVITLI), "б1")
znimok("б1-перефарбовані-світлі")
kadr_u_material(namaliuvaty(chyste, "eyebrow006", TEMNI), "б2")
znimok("б2-нова-форма-тонкі")
kadr_u_material(namaliuvaty(chyste, "eyebrow002", CHORNI), "б3")
znimok("б3-нова-форма-густі")
# а — картки поверх затертих
kadr_u_material(chyste, "а")
for nazva, kolir, mitka in (("eyebrow010", TEMNI, "а1-картки-природні"),
                            ("eyebrow002", SVITLI, "а2-картки-густі-світлі")):
    ob = kartky(nazva, kolir)
    znimok(mitka)
    for o in ob:
        bpy.data.objects.remove(o)
log("готово", TEKA)
