"""Маски шейдера шкіри для моделей «з нуля» (19.11.2026, план 15.11 крок 1; слово замовника
14.11: «необхідно зробити таку ж кількість налаштувань для усих як у жінки людини»).

У людини-жінки (MPFB) колір очей, губ, підводка й скальп у тон зачіски діють через
`<модель>_маски.png` (R — райдужка, G — підводка, B — губи, A — скальп;
`game/shaders/avatar_skin.gdshader`). У моделей «з нуля» (`ork_zbirka.py`) очі й губи
запечені в текстуру голови — масок не було, і ці вибори не діяли. Тут:

  1. рендер обличчя спереду (ортографічно, лише текстура, без волосся);
  2. точки обличчя MediaPipe (`tools/oblychchia_holova.py`) → маски R, G, B у кадрі
     (`tools/maski_oblychchia.py`);
  3. запікання масок у розгортку матеріалу «шкіра-голова» проєкцією з камери — лише на
     передній бік голови (інакше райдужка проступала б на потилиці);
  4. A (скальп) — з геометрії: вище лінії чола (точка 10) і потилиця вище вух, без вух.

Пише `<модель>_маски-шкіра-голова.png` поруч із моделлю; проміжне (рендер, точки, маски
кадру, перевірка) — у `art/маски-з-нуля-2026-11-19/<модель>/`.

    blender -b --factory-startup -P tools/blender/maski_z_nulia.py -- <модель.glb> [--розмір 2048]
"""
import os
import subprocess
import sys

import bpy
import numpy as np
from mathutils import Vector

A = sys.argv[sys.argv.index("--") + 1:]
MODEL = os.path.abspath(A[0])
ROZMIR = int(A[A.index("--розмір") + 1]) if "--розмір" in A else 2048
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
STEM = os.path.splitext(os.path.basename(MODEL))[0]
TEKA = os.path.join(ROOT, "art", "маски-з-нуля-2026-11-19",
                    os.path.basename(os.path.dirname(MODEL)) + "-" + STEM)
os.makedirs(TEKA, exist_ok=True)
PY = os.path.expanduser("~/Програми/cv-venv/bin/python")
KADR = 1024


def log(*a):
    print("[маски з нуля]", *a, flush=True)


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=MODEL)
tilo = next(o for o in bpy.context.scene.objects if o.type == "MESH"
            and any(m and m.name == "шкіра-голова" for m in o.data.materials))
for o in bpy.context.scene.objects:
    if o.type == "MESH" and o is not tilo:
        o.hide_render = True
# сітка в спокої (без поз скелета) — ті самі координати, що й у розгортці
for m in list(tilo.modifiers):
    if m.type == "ARMATURE":
        tilo.modifiers.remove(m)
me = tilo.data
mw = tilo.matrix_world
hi = next(i for i, m in enumerate(me.materials) if m and m.name == "шкіра-голова")
V = np.array([mw @ v.co for v in me.vertices])
N = np.array([(mw.to_3x3() @ v.normal).normalized() for v in me.vertices])
hol_v = np.zeros(len(V), bool)
for p in me.polygons:
    if p.material_index == hi:
        hol_v[list(p.vertices)] = True
H = V[hol_v]
# кадр — обличчя: від підборіддя-шиї до маківки, по центру голови
top = H[:, 2].max()
cz = top - 0.13
cx = float(np.median(H[:, 0]))
S = 0.30                       # ширина й висота кадру, м
log("голова: вершин %d, маківка %.3f м" % (len(H), top))

# ── 1. рендер спереду ───────────────────────────────────────────────
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.light = "FLAT"
sc.display.shading.color_type = "TEXTURE"
sc.render.resolution_x = sc.render.resolution_y = KADR
sc.render.film_transparent = False
sc.world = bpy.data.worlds.new("тло")
sc.display.shading.background_type = "VIEWPORT"
sc.display.shading.background_color = (0.5, 0.5, 0.5)
cam = bpy.data.objects.new("камера", bpy.data.cameras.new("камера"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.type = "ORTHO"
cam.data.ortho_scale = S
cam.location = Vector((cx, H[:, 1].min() - 1.0, cz))
cam.rotation_euler = (1.5707963, 0, 0)          # дивиться вздовж +Y
render = os.path.join(TEKA, "обличчя.png")
sc.render.filepath = render
bpy.ops.render.render(write_still=True)


def u_svit(px):
    """Піксель кадру (x вправо, y вниз) → (x, z) у світі."""
    return cx + (px[..., 0] / KADR - 0.5) * S, cz - (px[..., 1] / KADR - 0.5) * S


# ── 2. точки й маски кадру ──────────────────────────────────────────
tochky = os.path.join(TEKA, "точки.npy")
r = subprocess.run([PY, os.path.join(ROOT, "tools", "oblychchia_holova.py"), render, tochky],
                   capture_output=True, text=True)
log(r.stdout.strip() or r.stderr[-400:])
if not os.path.exists(tochky):
    raise SystemExit("[маски з нуля] ‼ обличчя на рендері не знайдено — масок немає")
figura = os.path.join(TEKA, "фігура.png")
import cv2  # noqa: E402  (cv2 у Blender є — для запису маски фігури)
cv2.imwrite(figura, np.full((KADR, KADR), 255, np.uint8))
mk, mv = os.path.join(TEKA, "маски-кадру.png"), os.path.join(TEKA, "волосся-кадру.png")
r = subprocess.run([PY, os.path.join(ROOT, "tools", "maski_oblychchia.py"), render, figura,
                    tochky, mk, mv], capture_output=True, text=True)
log(r.stdout.strip() or r.stderr[-400:])
F = np.load(tochky)
Fx, Fz = u_svit(F)
# ікла орків (19.11.2026): маска губ — увесь контур рота, а ікла стоять поверх губ і фарбувались
# кольором губ. Ікло — світліше й менш насичене за губи: такі пікселі з маски губ прибрати.
_kadr = cv2.imread(render)
_mk = cv2.imread(mk)
_hsv = cv2.cvtColor(_kadr, cv2.COLOR_BGR2HSV).astype(np.float32)
_guby = _mk[..., 0] > 128                          # BGR: B — губи
if _guby.sum() > 50:
    v0, s0 = np.median(_hsv[..., 2][_guby]), np.median(_hsv[..., 1][_guby])
    ikla = _guby & (_hsv[..., 2] > v0 - 15) & (_hsv[..., 1] < s0 * 0.6)
    if ikla.sum() > 0.04 * _guby.sum():
        ikla = cv2.dilate(ikla.astype(np.uint8), np.ones((5, 5), np.uint8)) > 0
        _mk[..., 0] = np.where(ikla, 0, _mk[..., 0])
        cv2.imwrite(mk, _mk)
        log("ікла: прибрано з маски губ %d пікселів кадру" % int(ikla.sum()))

# ── 3. перед голови й скальп — атрибути вершин ──────────────────────
yc = float(np.median(H[:, 1]))
# лише поверхні, що дивляться в камеру: на крутій стінці під бровою смужка кадру
# розтягувалась у довгий «гачок» підводки
pered = np.clip((-N[:, 1] - 0.35) / 0.25, 0, 1) * (V[:, 1] < yc + 0.01)
# видно з камери: складка повіки під бровою дивиться вперед, але схована — проєкція
# лягала й на неї («гачок» підводки над оком)
from mathutils.bvhtree import BVHTree  # noqa: E402
dg = bpy.context.evaluated_depsgraph_get()
bvh = BVHTree.FromObject(tilo, dg)
for i in np.nonzero(pered > 0)[0]:
    p0 = Vector(V[i]) + Vector((0, -0.0015, 0))
    hit = bvh.ray_cast(mw.inverted() @ p0, mw.inverted().to_3x3() @ Vector((0, -1, 0)), 2.0)
    if hit[0] is not None:
        pered[i] = 0.0
z_cholo = float(Fz[10])                                   # верх овалу обличчя
z_vukha = float(max(Fz[234], Fz[454]))                    # край обличчя на рівні очей
x_skron = 1.04 * max(abs(Fx[234] - cx), abs(Fx[454] - cx))
nad_cholom = np.clip((V[:, 2] - (z_cholo - 0.012)) / 0.02, 0, 1)
potylytsia = np.clip((V[:, 2] - (z_vukha + 0.01)) / 0.03, 0, 1) * np.clip((V[:, 1] - yc) / 0.02, 0, 1)
bez_vukh = np.clip(1 - (np.abs(V[:, 0] - cx) - x_skron) / 0.01, 0, 1)
skalp = np.maximum(nad_cholom, potylytsia) * bez_vukh * hol_v
log("чоло %.3f м, вуха %.3f м, скроні ±%.3f м; скальп вершин %d" %
    (z_cholo, z_vukha, x_skron, int((skalp > 0.5).sum())))
for nazva, zn in (("Перед", pered), ("Скальп", skalp)):
    at = me.color_attributes.new(nazva, "FLOAT_COLOR", "POINT")
    at.data.foreach_set("color", np.repeat(zn[:, None], 4, 1).astype(np.float32).ravel())

# розгортка-проєкція з камери (така сама, як рендер)
uv0 = me.uv_layers.active.name
pr = me.uv_layers.new(name="Проєкція")
pr_d = np.zeros((len(me.loops), 2), np.float32)
lv = np.array([l.vertex_index for l in me.loops])
pr_d[:, 0] = (V[lv, 0] - cx) / S + 0.5
pr_d[:, 1] = (V[lv, 2] - cz) / S + 0.5
pr.data.foreach_set("uv", pr_d.ravel())
me.uv_layers.active = me.uv_layers[uv0]
for l_ in me.uv_layers:
    l_.active_render = l_.name == uv0

# ── 4. запікання: голова окремим матеріалом ─────────────────────────
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = 1
mat = me.materials[hi]
mat.use_nodes = True
nt = mat.node_tree
for n in list(nt.nodes):
    nt.nodes.remove(n)
out = nt.nodes.new("ShaderNodeOutputMaterial")
em = nt.nodes.new("ShaderNodeEmission")
nt.links.new(em.outputs[0], out.inputs[0])
uvn = nt.nodes.new("ShaderNodeUVMap")
uvn.uv_map = "Проєкція"
tex = nt.nodes.new("ShaderNodeTexImage")
tex.extension = "CLIP"
img_k = bpy.data.images.load(mk)
img_k.colorspace_settings.name = "Non-Color"
tex.image = img_k
nt.links.new(uvn.outputs[0], tex.inputs[0])
atp = nt.nodes.new("ShaderNodeVertexColor")
atp.layer_name = "Перед"
mul = nt.nodes.new("ShaderNodeMixRGB")
mul.blend_type = "MULTIPLY"
mul.inputs[0].default_value = 1.0
nt.links.new(tex.outputs[0], mul.inputs[1])
nt.links.new(atp.outputs[0], mul.inputs[2])
nt.links.new(mul.outputs[0], em.inputs[0])
tsil = nt.nodes.new("ShaderNodeTexImage")
# інші матеріали тіла теж мусять мати активний вузол-ціль — інакше запікання відмовляє
smittia = bpy.data.images.new("смітник", 8, 8)
for i, m in enumerate(me.materials):
    if i == hi or m is None:
        continue
    m.use_nodes = True
    t_ = m.node_tree.nodes.new("ShaderNodeTexImage")
    t_.image = smittia
    m.node_tree.nodes.active = t_
bpy.ops.object.select_all(action="DESELECT")
tilo.select_set(True)
bpy.context.view_layer.objects.active = tilo
sc.render.bake.margin = 8
rez = []
for dzherelo in ("маски", "скальп"):
    im = bpy.data.images.new(dzherelo, ROZMIR, ROZMIR)
    im.colorspace_settings.name = "Non-Color"
    tsil.image = im
    nt.nodes.active = tsil
    if dzherelo == "скальп":
        ats = nt.nodes.new("ShaderNodeVertexColor")
        ats.layer_name = "Скальп"
        nt.links.new(ats.outputs[0], em.inputs[0])
    bpy.ops.object.bake(type="EMIT")
    px = np.empty(ROZMIR * ROZMIR * 4, np.float32)
    im.pixels.foreach_get(px)
    rez.append(px.reshape(ROZMIR, ROZMIR, 4))
    log("запечено:", dzherelo)
kin = np.concatenate([rez[0][..., :3], rez[1][..., :1]], -1).clip(0, 1)
vyhid = os.path.splitext(MODEL)[0] + "_маски-шкіра-голова.png"
# Blender пише знизу вгору — у файл (cv2) перевернути
cv2.imwrite(vyhid, cv2.cvtColor((kin[::-1] * 255).astype(np.uint8), cv2.COLOR_RGBA2BGRA))
log("райдужка %d, підводка %d, губи %d, скальп %d пікселів → %s" % (
    *(int((kin[..., k] > 0.5).sum()) for k in range(4)), vyhid))
