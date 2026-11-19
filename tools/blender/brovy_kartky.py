"""Брови й вії сітками-картками для моделей «з нуля» (19.11.2026, план 15.11 крок 4; замовник
вибрав спосіб (а) після показу `brovy_pokaz.py`: «роби а»).

Як у людини-жінки (MPFB, `pilot_rysy.py`): окремі сітки `Брови-<n>-<назва>` (4) і
`Вії-<n>-<назва>` (3), гра показує одну з набору (`skinned_model.gd`, PART_SETS).
  1. запечені брови затерти в текстурі голови: кадр спереду (як у maski_z_nulia.py) →
     cv2.inpaint у межах брів за точками MediaPipe → запікання проєкції в розгортку
     (лише перед голови, м'який край);
  2. брови — прямокутник текстури MPFB (CC0) на брову кадру, сітка 24×6 на шкірі з відступом;
  3. вії — сітка вій MPFB (5×13 на повіку): корінь уздовж краю повіки за точками, решта —
     зсуви від кореня з MPFB у масштабі ширини повіки;
  4. ваги кісток і форми-риси — з найближчих вершин голови (картки йдуть за рисами).

Текстура брів знебарвлена (сірі волосинки) — колір дає гра (колір волосся).

    blender -b --factory-startup -P tools/blender/brovy_kartky.py -- <7-риси/модель.blend> <точки.npy> <вихід.blend>
"""
import os
import sys

import bmesh
import bpy
import cv2
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

A = sys.argv[sys.argv.index("--") + 1:]
DZHERELO, TOCHKY, VYHID = (os.path.abspath(x) for x in A[:3])
TEKA = os.path.join(os.path.dirname(VYHID), os.path.splitext(os.path.basename(VYHID))[0])
os.makedirs(TEKA, exist_ok=True)
MPFB = os.path.expanduser("~/.config/blender/5.2/extensions/.user/blender_org/mpfb/data")
KADR, S = 1024, 0.30
BROVY_NABIR = [("1-дугою", "eyebrow010"), ("2-тонкі", "eyebrow006"), ("3-прямі", "eyebrow001"),
               ("4-густі", "eyebrow008")]
VII_NABIR = [("1-природні", "eyelashes01"), ("2-довгі", "eyelashes02"), ("3-пишні", "eyelashes03")]


def log(*a):
    print("[брови]", *a, flush=True)


bpy.ops.wm.open_mainfile(filepath=DZHERELO)
sc = bpy.context.scene


def _holova_hranei(o):
    ii = [i for i, m in enumerate(o.data.materials) if m and m.name == "шкіра-голова"]
    return sum(1 for p in o.data.polygons if p.material_index in ii) if ii else 0


# тіло — сітка з найбільшою кількістю граней голови (в орка v1 одяг теж має шкіру голови)
tilo = max((o for o in sc.objects if o.type == "MESH" and not o.name.startswith(("Брови-", "Вії-"))),
           key=_holova_hranei)
log("тіло:", tilo.name)
for o in list(sc.objects):
    if o.name.startswith(("Брови-", "Вії-")):
        bpy.data.objects.remove(o)
me = tilo.data
mw = tilo.matrix_world.copy()
mwi = mw.inverted()
HI = {i for i, m in enumerate(me.materials) if m and m.name == "шкіра-голова"}   # в орка v1 — кілька слотів
hi = min(HI)
V = np.array([mw @ v.co for v in me.vertices])
hol_v = np.zeros(len(V), bool)
hol_f = []
for p in me.polygons:
    if p.material_index in HI:
        hol_v[list(p.vertices)] = True
        hol_f.append(list(p.vertices))
H = V[hol_v]
top = float(H[:, 2].max())
cz = top - 0.13
cx = float(np.median(H[:, 0]))
ymin = float(H[:, 1].min())
bvh = BVHTree.FromPolygons([Vector(v) for v in V], hol_f)
F = np.load(TOCHKY)


def u_svit(px):
    return cx + (px[0] / KADR - 0.5) * S, cz - (px[1] / KADR - 0.5) * S


def na_shkiru(px):
    """Точка кадру → точка й нормаль на голові (промінь з камери вздовж +Y)."""
    x, z = u_svit(px)
    hit = bvh.ray_cast(Vector((x, ymin - 0.5, z)), Vector((0, 1, 0)))
    if hit[0] is None:
        return None, None
    n = hit[1]
    if n.y > 0:
        n = -n
    return hit[0], n


# ── 1. кадр спереду й затирання брів ────────────────────────────────
skhovani = []
for o in sc.objects:
    if o.type == "MESH" and o is not tilo and not o.hide_render:
        o.hide_render = True
        skhovani.append(o)
sc.view_settings.view_transform = "Standard"
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.light = "FLAT"
sc.display.shading.color_type = "TEXTURE"
sc.display.shading.background_type = "VIEWPORT"
sc.display.shading.background_color = (0.5, 0.5, 0.5)
sc.render.resolution_x = sc.render.resolution_y = KADR
sc.render.resolution_percentage = 100
cam = bpy.data.objects.new("кадр-брів", bpy.data.cameras.new("кадр-брів"))
sc.collection.objects.link(cam)
stara_kamera = sc.camera
sc.camera = cam
cam.data.type = "ORTHO"
cam.data.ortho_scale = S
cam.location = Vector((cx, ymin - 1.0, cz))
cam.rotation_euler = (1.5707963, 0, 0)
kadr_f = os.path.join(TEKA, "кадр.png")
sc.render.filepath = kadr_f
bpy.ops.render.render(write_still=True)
kadr = cv2.imread(kadr_f)

BROVY = {+1: ([336, 296, 334, 293, 300], [285, 295, 282, 283, 276]),
         -1: ([107, 66, 105, 63, 70], [55, 65, 52, 53, 46])}
maska = np.zeros((KADR, KADR), np.uint8)
for verh, nyz in BROVY.values():
    cv2.fillPoly(maska, [np.concatenate([F[verh], F[nyz][::-1]]).astype(np.int32)], 255)
maska = cv2.dilate(maska, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (27, 31)))
# затирання: шкіра чола над бровою, зсунута вниз на висоту брови (cv2.inpaint тягнув колір і з
# нижнього краю — темної складки повіки, і низ брови лишався темним)
chyste = kadr.copy()
n_, mitky = cv2.connectedComponents(maska)
for c in range(1, n_):
    m_c = (mitky == c).astype(np.uint8) * 255
    ys = np.where(m_c.any(1))[0]
    dy = int(ys.max() - ys.min()) + 6
    zsunute = np.roll(kadr, dy, axis=0)
    # рівень кольору: латка з-над брови може бути світлішою чи темнішою за шкіру довкола
    kiltse = cv2.dilate(m_c, np.ones((15, 15), np.uint8)) & ~m_c
    kiltse[ys.max() - 4:] = 0                              # без повіки знизу
    if kiltse.any():
        zsuv = kadr[kiltse > 0].mean(0) - zsunute[m_c > 0].mean(0)
        zsunute = np.clip(zsunute.astype(np.float32) + zsuv * 0.6, 0, 255).astype(np.uint8)
    m_f = cv2.GaussianBlur(m_c, (0, 0), 3).astype(np.float32)[..., None] / 255
    chyste = (chyste * (1 - m_f) + zsunute * m_f).astype(np.uint8)
zona = cv2.GaussianBlur(cv2.dilate(maska, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (41, 41))),
                        (0, 0), 6)
cv2.imwrite(os.path.join(TEKA, "затерте.png"), chyste)
cv2.imwrite(os.path.join(TEKA, "зона.png"), zona)

# запікання проєкції в розгортку: копія голови без решти тіла
mat_h = me.materials[hi]
tex_node = next(n for n in mat_h.node_tree.nodes if n.type == "TEX_IMAGE"
                and any(l.to_socket.name == "Base Color" for l in n.outputs["Color"].links))
img_h = tex_node.image
W_, H_ = img_h.size
kopiia = tilo.copy()
kopiia.data = me.copy()
sc.collection.objects.link(kopiia)
kopiia.shape_key_clear()
# орк v1 (сет броні): тіло приховане у вікні — бейк не бачить прихованих
kopiia.hide_viewport = kopiia.hide_render = False
kopiia.hide_set(False)
for m in list(kopiia.modifiers):
    kopiia.modifiers.remove(m)
bm = bmesh.new()
bm.from_mesh(kopiia.data)
bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index not in HI], context="FACES")
bm.to_mesh(kopiia.data)
bm.free()
kopiia.data.materials.clear()
mb = bpy.data.materials.new("запікання-брів")
kopiia.data.materials.append(mb)
for p in kopiia.data.polygons:
    p.material_index = 0
nt = mb.node_tree
for n in list(nt.nodes):
    nt.nodes.remove(n)
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


uu = matem("ADD", matem("DIVIDE", matem("SUBTRACT", sep.outputs[0], cx), S), 0.5)
vv = matem("ADD", matem("DIVIDE", matem("SUBTRACT", sep.outputs[2], cz), S), 0.5)
comb = nt.nodes.new("ShaderNodeCombineXYZ")
nt.links.new(uu, comb.inputs[0])
nt.links.new(vv, comb.inputs[1])
pk = nt.nodes.new("ShaderNodeTexImage")
pk.extension = "CLIP"
nt.links.new(comb.outputs[0], pk.inputs[0])
sepn = nt.nodes.new("ShaderNodeSeparateXYZ")
nt.links.new(geo.outputs["Normal"], sepn.inputs[0])
pered = matem("MULTIPLY", matem("SUBTRACT", matem("MULTIPLY", sepn.outputs[1], -1.0), 0.35), 4.0)
pered.node.use_clamp = True
emis = nt.nodes.new("ShaderNodeEmission")
out = nt.nodes.new("ShaderNodeOutputMaterial")
nt.links.new(emis.outputs[0], out.inputs[0])
ROZ = min(W_, 2048)
tsil = nt.nodes.new("ShaderNodeTexImage")
nt.nodes.active = tsil
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = 1
sc.render.bake.margin = 16
log("налаштування бейку у файлі: з вибраних на активний %s, ціль %s" % (sc.render.bake.use_selected_to_active, sc.render.bake.target))
sc.render.bake.use_selected_to_active = False      # орк v1: файл сету броні — бейк одяг→тіло
sc.render.bake.target = "IMAGE_TEXTURES"
for o in sc.objects:
    o.select_set(False)
kopiia.select_set(True)
bpy.context.view_layer.objects.active = kopiia


def zapekty(dzherelo_px, nemaie_koloru):
    """Запекти зображення кадру (BGR) як випромінення → масив RGB 0..1 у розгортці."""
    f = os.path.join(TEKA, "проєкція.png")
    cv2.imwrite(f, dzherelo_px)
    pk.image = bpy.data.images.load(f, check_existing=False)
    pk.image.colorspace_settings.name = "Non-Color" if nemaie_koloru else "sRGB"
    ciil = bpy.data.images.new("ціль", ROZ, ROZ, float_buffer=True)
    ciil.colorspace_settings.name = "Non-Color"
    tsil.image = ciil
    if nemaie_koloru:
        nt.links.new(matem("MULTIPLY", pered, pk.outputs["Color"]), emis.inputs["Color"])
    else:
        nt.links.new(pk.outputs["Color"], emis.inputs["Color"])
    bpy.ops.object.bake(type="EMIT", margin=16)
    a = np.empty(ROZ * ROZ * 4, np.float32)
    ciil.pixels.foreach_get(a)
    return a.reshape(ROZ, ROZ, 4)[..., :3]


m_uv = zapekty(zona, True)[..., 0]
k_uv = zapekty(chyste, False)            # лінійне (зображення sRGB → випромінення)
if ROZ != W_:
    m_uv = cv2.resize(m_uv, (W_, H_), interpolation=cv2.INTER_LINEAR)
    k_uv = cv2.resize(k_uv, (W_, H_), interpolation=cv2.INTER_LINEAR)
px = np.empty(W_ * H_ * 4, np.float32)
img_h.pixels.foreach_get(px)
px = px.reshape(H_, W_, 4)
k_srgb = np.where(k_uv <= 0.0031308, k_uv * 12.92, 1.055 * np.power(np.clip(k_uv, 0, None), 1 / 2.4) - 0.055)
m3 = np.clip(m_uv, 0, 1)[..., None]
px[..., :3] = px[..., :3] * (1 - m3) + np.clip(k_srgb, 0, 1) * m3
# нова картинка з файла: pack() на вже вбудованій лишав стару копію, і в GLB ішли старі брови
tymch = bpy.data.images.new("тимч", W_, H_, alpha=True)
tymch.pixels.foreach_set(px.ravel())
nova = os.path.join(TEKA, os.path.basename(img_h.name).removesuffix("-без-брів") + "-без-брів.png")
tymch.filepath_raw = nova
tymch.file_format = "PNG"
tymch.save()
bpy.data.images.remove(tymch)
img_nova = bpy.data.images.load(nova, check_existing=False)
img_nova.name = os.path.basename(img_h.name).removesuffix("-без-брів") + "-без-брів"
img_nova.colorspace_settings.name = img_h.colorspace_settings.name
img_nova.pack()
tex_node.image = img_nova
log("брови затерто в текстурі: %d текселів" % int((m_uv > 0.05).sum()))
bpy.data.objects.remove(kopiia)
sc.camera = stara_kamera
bpy.data.objects.remove(cam)
for o in skhovani:
    o.hide_render = False

# ── прив'язка карток: ваги кісток і форми-риси з найближчих вершин голови ──
idx_h = np.where(hol_v)[0]
kd = KDTree(len(idx_h))
for j, i in enumerate(idx_h):
    kd.insert(Vector(V[i]), j)
kd.balance()
grupy = {g.index: g.name for g in tilo.vertex_groups}
kliuchi = me.shape_keys.key_blocks if me.shape_keys else []
baza = np.array([v.co for v in me.vertices]) if kliuchi else None
delty = {}
for k in kliuchi:
    if k.name == "Basis" or k == me.shape_keys.reference_key:
        continue
    co = np.empty(len(me.vertices) * 3, np.float32)
    k.data.foreach_get("co", co)
    delty[k.name] = co.reshape(-1, 3) - baza
arm_mod = next((m for m in tilo.modifiers if m.type == "ARMATURE"), None)


def obiekt(nazva, verts_w, faces, uvs, mat):
    loc = [tuple(mwi @ Vector(v)) for v in verts_w]
    mm = bpy.data.meshes.new(nazva)
    mm.from_pydata(loc, [], faces)
    uvl = mm.uv_layers.new(name="UVMap")
    for p in mm.polygons:
        for li in p.loop_indices:
            uvl.data[li].uv = uvs[mm.loops[li].vertex_index]
    mm.materials.append(mat)
    o = bpy.data.objects.new(nazva, mm)
    for c in tilo.users_collection:
        c.objects.link(o)
    o.parent = tilo.parent
    o.parent_type = tilo.parent_type
    o.matrix_parent_inverse = tilo.matrix_parent_inverse.copy()
    o.matrix_world = mw
    # ваги й форми: середнє за 4 найближчими вершинами голови (обернено до відстані)
    vg = {}
    sum_d = {k: np.zeros((len(loc), 3)) for k in delty}
    for vi, w in enumerate(verts_w):
        sus = kd.find_n(Vector(w), 4)
        ww = np.array([1.0 / max(d, 1e-5) for _, _, d in sus])
        ww /= ww.sum()
        for (co_, j, d), wj in zip(sus, ww):
            i = idx_h[j]
            for g in me.vertices[i].groups:
                vg.setdefault(grupy[g.group], {}).setdefault(vi, 0.0)
                vg[grupy[g.group]][vi] += g.weight * wj
            for k in delty:
                sum_d[k][vi] += delty[k][i] * wj
    for gname, ws in vg.items():
        g = o.vertex_groups.new(name=gname)
        for vi, w in ws.items():
            if w > 1e-4:
                g.add([vi], w, "REPLACE")
    if delty:
        o.shape_key_add(name="Basis", from_mix=False)
        for k, d in sum_d.items():
            kb = o.shape_key_add(name=k, from_mix=False)
            kb.data.foreach_set("co", (np.array(loc) + d).astype(np.float32).ravel())
            kb.value = 0.0
    if arm_mod is not None:
        am = o.modifiers.new("Armature", "ARMATURE")
        am.object = arm_mod.object
    return o


def material(nazva, png, znebarvyty):
    t = cv2.imread(png, cv2.IMREAD_UNCHANGED)
    if znebarvyty:
        # сірі волосинки: яскравість відносно середньої — колір дає гра (колір волосся)
        # рівний сірий: напівпрозорі пікселі MPFB чорні — з колором волосинок тонкі брови
        # білого ельфа виходили чорними; форма — лише в прозорості
        t[..., 0] = t[..., 1] = t[..., 2] = 190
        # малюнок MPFB напівпрозорий (у середньому ~40 %) — у грі брови виходили блідими
        t[..., 3] = np.clip(t[..., 3].astype(np.float32) * 1.7, 0, 255).astype(np.uint8)
    f = os.path.join(TEKA, nazva + ".png")
    cv2.imwrite(f, t)
    img = bpy.data.images.load(f, check_existing=False)
    img.name = nazva
    img.pack()
    m = bpy.data.materials.new(nazva)
    m.surface_render_method = "BLENDED"
    nt_ = m.node_tree
    b = nt_.nodes["Principled BSDF"]
    ti = nt_.nodes.new("ShaderNodeTexImage")
    ti.image = img
    nt_.links.new(ti.outputs["Color"], b.inputs["Base Color"])
    nt_.links.new(ti.outputs["Alpha"], b.inputs["Alpha"])
    b.inputs["Roughness"].default_value = 0.8
    return m


# ── 2. брови ────────────────────────────────────────────────────────
def obj_mpfb(typ, nazva):
    v, vt, fs = [], [], []
    for l in open(os.path.join(MPFB, typ, nazva, nazva + ".obj")):
        p = l.split()
        if not p:
            continue
        if p[0] == "v":
            v.append([float(x) for x in p[1:4]])
        elif p[0] == "vt":
            vt.append([float(x) for x in p[1:3]])
        elif p[0] == "f":
            fs.append([tuple(int(x) - 1 for x in q.split("/")[:2]) for q in p[1:]])
    return np.array(v), np.array(vt), fs


def brovy(mitka, nazva):
    v, vt, fs = obj_mpfb("eyebrows", nazva)
    vi = {b: a for f in fs for a, b in f}
    mat = material("Брови-" + nazva, os.path.join(MPFB, "eyebrows", nazva, nazva + ".png"), True)
    verts, faces, uvs = [], [], []
    NU, NV = 24, 6
    for s, (verh, nyz) in BROVY.items():
        ks = [k for k in vi if v[vi[k], 0] * s > 0]
        uv = vt[ks]
        xs = np.abs(v[[vi[k] for k in ks], 0])
        u_in, u_out = uv[xs.argmin(), 0], uv[xs.argmax(), 0]
        v_lo, v_hi = uv[:, 1].min(), uv[:, 1].max()
        ser = (F[verh] + F[nyz]) / 2
        p_in, p_out = ser[0], ser[-1]
        vzd = (p_out - p_in) * 1.18
        L = np.linalg.norm(vzd)
        h = L * (v_hi - v_lo) / abs(u_out - u_in) * 1.5
        vgoru = np.array([vzd[1], -vzd[0]]) / L * h
        if vgoru[1] > 0:
            vgoru = -vgoru
        p0 = ser.mean(0) - vzd / 2 - vgoru / 2
        poch = len(verts)
        for j in range(NV + 1):
            for i in range(NU + 1):
                a_, b_ = i / NU, j / NV
                co, n = na_shkiru(p0 + vzd * a_ + vgoru * b_)
                if co is None:            # за краєм голови — стільки ж, як у сусіда
                    co, n = Vector(verts[-1]) if verts else Vector((0, 0, 0)), Vector((0, -1, 0))
                verts.append(tuple(co + n * 0.0012))
                uvs.append((u_in + (u_out - u_in) * a_, v_lo + (v_hi - v_lo) * b_))
        faces += [(poch + j * (NU + 1) + i, poch + j * (NU + 1) + i + 1,
                   poch + (j + 1) * (NU + 1) + i + 1, poch + (j + 1) * (NU + 1) + i)
                  for j in range(NV) for i in range(NU)]
    return obiekt("Брови-" + mitka, verts, faces, uvs, mat)


# ── 3. вії ──────────────────────────────────────────────────────────
POVIKY = {(+1, "верх"): [362, 398, 384, 385, 386, 387, 388, 466, 263],
          (+1, "низ"): [362, 382, 381, 380, 374, 373, 390, 249, 263],
          (-1, "верх"): [133, 173, 157, 158, 159, 160, 161, 246, 33],
          (-1, "низ"): [133, 155, 154, 153, 145, 144, 163, 7, 33]}
# частка повіки (від внутрішнього кута), яку вкриває корінь вій
PROMIZHOK = {"верх": (0.12, 0.97), "низ": (0.3, 0.95)}


def po_kryvii(pts, t):
    d = np.r_[0, np.cumsum(np.linalg.norm(np.diff(pts, axis=0), axis=1))]
    t = np.clip(t, 0, 1) * d[-1]
    return np.stack([np.interp(t, d, pts[:, 0]), np.interp(t, d, pts[:, 1])], -1)


def sitka(fs, comp):
    """Сітка смужки вій (чотирикутники) → рядки вершин (список списків)."""
    quads = [[a for a, _ in f] for f in fs if f[0][0] in comp]
    from collections import Counter
    fc = Counter(a for q in quads for a in q)
    rebra = Counter()
    for q in quads:
        for i in range(4):
            rebra[frozenset((q[i], q[(i + 1) % 4]))] += 1
    sus = {}
    for e in rebra:
        a, b = tuple(e)
        sus.setdefault(a, set()).add(b)
        sus.setdefault(b, set()).add(a)
    kut = [a for a in comp if fc[a] == 1]
    c0 = kut[0]

    def mezha(start, nxt):
        sh, prev, cur = [start], start, nxt
        while True:
            sh.append(cur)
            if fc[cur] == 1:
                return sh
            dali = [x for x in sus[cur] if x != prev and rebra[frozenset((cur, x))] == 1]
            prev, cur = cur, dali[0]

    a, b = (mezha(c0, x) for x in sus[c0])
    riad, stovp = (a, b) if len(a) > len(b) else (b, a)
    rows = [riad]
    for r in range(1, len(stovp)):
        new = [stovp[r]]
        for c in range(1, len(riad)):
            tr = {rows[r - 1][c - 1], rows[r - 1][c], new[c - 1]}
            q = next(q for q in quads if tr <= set(q))
            new.append(next(x for x in q if x not in tr))
        rows.append(new)
    return rows


def vii(mitka, nazva):
    v, vt, fs = obj_mpfb("eyelashes", nazva)
    uv_v = {a: b for f in fs for a, b in f}
    mat = material("Вії-" + nazva, os.path.join(MPFB, "eyelashes", nazva, nazva + ".png"), False)
    par = list(range(len(v)))

    def kor(x):
        while par[x] != x:
            par[x] = par[par[x]]
            x = par[x]
        return x
    for f in fs:
        for a, _ in f[1:]:
            par[kor(a)] = kor(f[0][0])
    comps = {}
    for i in range(len(v)):
        comps.setdefault(kor(i), []).append(i)
    comps = list(comps.values())
    verts, faces, uvs = [], [], []
    for s in (+1, -1):
        bik = [c for c in comps if v[c, 0].mean() * s > 0]
        bik.sort(key=lambda c: -v[c, 1].mean())          # перша — верхня повіка
        for comp, povika in zip(bik, ("верх", "низ")):
            rows = sitka(fs, set(comp))
            # корінь — крайній рядок ближче до ока (верхні вії ростуть угору, нижні — вниз)
            r0, r1 = v[rows[0], 1].mean(), v[rows[-1], 1].mean()
            if (povika == "верх") == (r0 > r1):
                rows = rows[::-1]
            korin = v[rows[0]]
            ax = np.abs(korin[:, 0])
            t = (ax - ax.min()) / max(ax.max() - ax.min(), 1e-6)
            a0, a1 = PROMIZHOK[povika]
            lid = F[POVIKY[(s, povika)]]
            lid_px = po_kryvii(lid, a0 + t * (a1 - a0))
            # масштаб: довжина кореня MPFB → довжина відповідного шматка повіки в світі
            w_lid = []
            for p in lid_px:
                co, n = na_shkiru(p)
                w_lid.append((co, n))
            ok = [c for c, _ in w_lid if c is not None]
            if len(ok) < len(w_lid) // 2:
                log("‼ вії %s %s %d: повіка не на голові" % (nazva, povika, s))
                continue
            dl_nash = sum((ok[i + 1] - ok[i]).length for i in range(len(ok) - 1))
            dl_mpfb = float(np.sum(np.linalg.norm(np.diff(korin, axis=0), axis=1)))
            k = dl_nash / max(dl_mpfb, 1e-6)
            poch = len(verts)
            idx = {}
            for c in range(len(rows[0])):
                co, n = w_lid[c]
                if co is None:
                    co, n = ok[0] if c < len(w_lid) // 2 else ok[-1], Vector((0, -1, 0))
                root = co + n * 0.0004 + Vector((0, -0.0006, 0))
                for r in range(len(rows)):
                    d = v[rows[r][c]] - v[rows[0][c]]
                    # MPFB: x, y угору, z уперед → тут x, -y уперед, z угору
                    p = root + Vector((d[0], -d[2], d[1])) * k
                    idx[(r, c)] = len(verts)
                    verts.append(tuple(p))
                    uvs.append(tuple(vt[uv_v[rows[r][c]]]))
            for r in range(len(rows) - 1):
                for c in range(len(rows[0]) - 1):
                    faces.append((idx[(r, c)], idx[(r, c + 1)], idx[(r + 1, c + 1)], idx[(r + 1, c)]))
            assert poch < len(verts)
    return obiekt("Вії-" + mitka, verts, faces, uvs, mat)


for mitka, nazva in BROVY_NABIR:
    o = brovy(mitka, nazva)
    log("брови", o.name, len(o.data.vertices))
for mitka, nazva in VII_NABIR:
    o = vii(mitka, nazva)
    log("вії", o.name, len(o.data.vertices))
bpy.ops.wm.save_as_mainfile(filepath=VYHID)
log("збережено", VYHID)
