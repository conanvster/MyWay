"""Пілот Б (П-281), крок 2 — зачіски на основі MPFB (08.11.2026).

Слово замовника: «почни з зачіски, зроби 3 варіанти різних зачісок,
використовуючи спеціальні текстури для волосся, колір волосся теж можна
змінити, спробуй використати правила з моделей e1903 Mixamo, k1811 Mixamo».

Правила ельфійок (`mixamo_zbirka.py`, П-268/П-269), перенесені на скелет
MPFB `game_engine`:
  * зачіска — пасма-картки `volossia_pasma.py` (тут `--природне`: пучки,
    детальна текстура), окремою сіткою «Волосся-<стиль>»;
  * сім ланцюжків по 4 пружні кістки `hair_<c>_<k>` довкола голови під
    кісткою `spine_03` (верх спини; у ельфійок — голова) (гра хитає їх `SpringBoneSimulator3D`);
  * пасма ближче 4 см до тіла беруть ваги шкіри (не ховаються під неї,
    не рвуться на бігу), 4…10 см — плавна суміш із пружинами;
  * текстура нейтрально-світла: колір — множником у грі; тут кожній
    зачісці свій колір за замовчуванням (каштанове, русяве, руде).

    # 1) тіло для зіткнень пасом (лише шкіра, без помічників MPFB):
    blender -b <основа.blend> -P tools/blender/pilot_volossia.py -- тіло <тіло.blend>
    # 2) пасма: volossia_pasma.py -- <тіло.blend> <волосся-стиль.blend> --стиль … --природне
    # 3) збирання на скелеті:
    blender -b <основа.blend> -P tools/blender/pilot_volossia.py -- зібрати \
        <вихід.blend> <волосся-стиль.blend>[=r,g,b] ...
"""
import functools
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Vector
from mathutils.kdtree import KDTree

print = functools.partial(print, flush=True)
ARGS = sys.argv[sys.argv.index("--") + 1:]
REZHYM = ARGS[0]
h = bpy.data.objects["Human"]
rig = bpy.data.objects["Human.rig"]
for pb in rig.pose.bones:
    pb.matrix_basis.identity()
bpy.context.view_layer.update()

RUKY = ("upperarm", "lowerarm", "hand", "thumb", "index", "middle", "ring", "pinky")


def ruka(v, gi):
    """Вершина, де найбільша вага — на кістці руки (плече й нижче)."""
    kistky = [g for g in v.groups if gi.get(g.group, "") in rig.data.bones]
    if not kistky:            # службові групи MPFB (body, Left, …) — не кістки
        return False
    g = max(kistky, key=lambda g_: g_.weight)
    return gi[g.group].startswith(RUKY)


if REZHYM == "тіло":
    # Шкіра без помічників (маска «Hide helpers»), у спокої, без скелета.
    # Руки геть: в A-позі вони поруч із тулубом, і пасма лягали на них
    # (у ельфійок у T-позі руки відрізала ширина, тут — ваги кісток).
    gi = {g.index: g.name for g in h.vertex_groups}
    ruky = [i for i, v in enumerate(h.data.vertices) if ruka(v, gi)]
    h.vertex_groups.new(name="руки").add(ruky, 1.0, "REPLACE")
    mk = h.modifiers.new("без рук", "MASK")
    mk.vertex_group = "руки"
    mk.invert_vertex_group = True
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(h.evaluated_get(dg))
    print("[волосся] тіло без рук: прибрано вершин %d" % len(ruky))
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    o = bpy.data.objects.new("Тіло", me)
    bpy.context.scene.collection.objects.link(o)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(ARGS[1]))
    print("[волосся] тіло: вершин %d → %s" % (len(me.vertices), ARGS[1]))
    sys.exit(0)

# ── зібрати ─────────────────────────────────────────────────────────────
VYKHID = os.path.abspath(ARGS[1])
# Ваги шкіри: повні ближче 4 см, далі плавна суміш до 10 см (у ельфійок 2…3 см). На
# бігу тулуб нахиляється, і пружини тягли пасма зі спини, а сусідні
# лишались на шкірі — волосся рвалось надвоє (проба 08.11.2026). Довге
# волосся на спині здебільшого йде за спиною, пружини — плавно сильніші далі від тіла.
BLYZKO = (0.04, 0.10)
KUTY = (-135.0, -90.0, -45.0, 0.0, 45.0, 90.0, 135.0)   # 0 — потилиця (+Y)
LANKY = 4
HOLOVA = "head"
KORIN = "spine_03"

zachisky = []
for a in ARGS[2:]:
    shliakh, _, kolir = a.partition("=")
    with bpy.data.libraries.load(os.path.abspath(shliakh)) as (src, dst):
        dst.objects = [n for n in src.objects if n.startswith(("Волосся", "Борода"))]
    for vol in dst.objects:
        bpy.context.scene.collection.objects.link(vol)
        zachisky.append((vol, tuple(float(x) for x in kolir.split(",")) if kolir else None))
bpy.context.view_layer.update()

# Ланцюжки — за найдовшою зачіскою (як у ельфійок 13.10: інакше довгі пасма
# стирчали без кісток).
co_vsi = np.concatenate([np.array([(v_.matrix_world @ v.co)[:] for v in v_.data.vertices])
                         for v_, _ in zachisky])
hw = rig.matrix_world @ rig.data.bones[HOLOVA].head_local
z_t = min(co_vsi[:, 2].max() - 0.01, hw.z + 0.02)      # від потилиці
z_b = co_vsi[:, 2].min() + 0.02
zs = np.linspace(z_t, z_b, LANKY + 1)
cx, cy = hw.x, hw.y
kut_v = np.degrees(np.arctan2(co_vsi[:, 0] - cx, co_vsi[:, 1] - cy))
rad_v = np.hypot(co_vsi[:, 0] - cx, co_vsi[:, 1] - cy)


def tochka(th, z):
    m = (np.abs(((kut_v - th) + 180) % 360 - 180) < 20) & (np.abs(co_vsi[:, 2] - z) < 0.04)
    pas = np.abs(co_vsi[:, 2] - z) < 0.04
    r_ = float(np.median(rad_v[m])) if m.sum() > 10 else (
        float(np.median(rad_v[pas])) if pas.any() else 0.1)
    return Vector((cx + r_ * math.sin(math.radians(th)),
                   cy + r_ * math.cos(math.radians(th)), z))


inv = rig.matrix_world.inverted()
bpy.ops.object.select_all(action="DESELECT")
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
eb = rig.data.edit_bones
for c, th in enumerate(KUTY):
    # Корінь ланцюжка — верх спини, не голова: на бігу голова й тулуб
    # нахиляються вперед, і пасма з ланцюжків під головою під вагою падали
    # крізь тулуб (ззаду волосся «зникало», збоку висіло перед стегном).
    # Маківку тримає голова (ваги `head` угорі, нижче — шкіра й пружини).
    bat = eb[KORIN]
    for k in range(LANKY):
        b = eb.new("hair_%d_%d" % (c, k + 1))
        b.head = inv @ tochka(th, zs[k])
        b.tail = inv @ tochka(th, zs[k + 1])
        b.parent = bat
        b.use_connect = k > 0
        bat = b
bpy.ops.object.mode_set(mode="OBJECT")
print("[волосся] кістки: %d ланцюжків × %d; z %.2f…%.2f" % (len(KUTY), LANKY, z_b, z_t))

# Тіло для «ваг шкіри»: лише вершини групи body (без помічників).
gi_body = h.vertex_groups["body"].index
tv = h.data.vertices
imena_t = {g.index: g.name for g in h.vertex_groups}
# без рук: пасмо біля плеча брало б вагу руки й ходило б за нею
shkira = [i for i, v in enumerate(tv) if any(g.group == gi_body and g.weight > 0.5
                                              for g in v.groups) and not ruka(v, imena_t)]
kd = KDTree(len(shkira))
for i in shkira:
    kd.insert(h.matrix_world @ tv[i].co, i)
kd.balance()
imena_t = {g.index: g.name for g in h.vertex_groups}


def vazhi(vol):
    co = np.array([(vol.matrix_world @ v.co)[:] for v in vol.data.vertices])
    for g in list(vol.vertex_groups):
        vol.vertex_groups.remove(g)
    grupy = {"hair_%d_%d" % (c, k + 1): vol.vertex_groups.new(name="hair_%d_%d" % (c, k + 1))
             for c in range(len(KUTY)) for k in range(LANKY)}
    grupy[HOLOVA] = vol.vertex_groups.new(name=HOLOVA)
    kut = np.degrees(np.arctan2(co[:, 0] - cx, co[:, 1] - cy))
    ku = np.array(KUTY)
    blyzko = 0
    for i, p in enumerate(co):
        # біля тіла — ваги найближчої вершини шкіри (П-269)
        _, j, d = kd.find(Vector(p))
        s_ = 0.0 if d >= BLYZKO[1] else (1.0 if d <= BLYZKO[0] else
                                          (BLYZKO[1] - d) / (BLYZKO[1] - BLYZKO[0]))
        if s_ > 0:
            blyzko += 1
            for ge in tv[j].groups:
                im = imena_t[ge.group]
                if im not in rig.data.bones:
                    continue
                if im not in grupy:
                    grupy[im] = vol.vertex_groups.new(name=im)
                grupy[im].add([i], ge.weight * s_, "ADD")
        if s_ >= 1.0:
            continue
        z = p[2]
        f_ = min(max(kut[i], ku[0]), ku[-1])
        j_ = min(int(np.searchsorted(ku, f_, side="right")) - 1, len(ku) - 2)
        f = (f_ - ku[j_]) / (ku[j_ + 1] - ku[j_])
        t = min(max((z_t - z) / (z_t - z_b), 0.0), 0.999) * LANKY
        k = int(t)
        fk = t - k
        hol = 1.0 if z >= z_t else (max(0.0, 1.0 - (z_t - z) / 0.03) if z > z_t - 0.03 else 0.0)
        for c_i, wc in ((j_, 1 - f), (j_ + 1, f)):
            w = wc * (1 - hol) * (1 - s_)
            if w <= 0:
                continue
            grupy["hair_%d_%d" % (c_i, k + 1)].add([i], w * (1 - 0.5 * fk), "ADD")
            if k + 1 < LANKY:
                grupy["hair_%d_%d" % (c_i, k + 2)].add([i], w * 0.5 * fk, "ADD")
        if hol > 0:
            grupy[HOLOVA].add([i], hol * (1 - s_), "ADD")
    return blyzko


def kolir_za_zamovchuvanniam(vol, rgb):
    """Множник у матеріалі пасом (експортер → baseColorFactor); гра
    повертає його, коли колір у меню не вибрано."""
    m = vol.data.materials[0]
    nt = m.node_tree
    b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    tex = next(n for n in nt.nodes if n.type == "TEX_IMAGE")
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type, mix.blend_type = "RGBA", "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    nt.links.new(tex.outputs["Color"], mix.inputs[6])
    mix.inputs[7].default_value = (*rgb, 1.0)
    nt.links.new(mix.outputs[2], b.inputs["Base Color"])
    m.name = vol.name


for vol, rgb in zachisky:
    mw = vol.matrix_world.copy()
    vol.parent = rig
    vol.matrix_parent_inverse = rig.matrix_world.inverted()
    vol.matrix_world = mw
    am = vol.modifiers.new("Armature", "ARMATURE")
    am.object = rig
    n = vazhi(vol)
    if rgb:
        kolir_za_zamovchuvanniam(vol, rgb)
    print("[волосся] %s: вершин %d, біля тіла %d; колір %s"
          % (vol.name, len(vol.data.vertices), n, rgb))
bpy.ops.wm.save_as_mainfile(filepath=VYKHID)
print("[волосся] →", VYKHID)
