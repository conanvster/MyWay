"""Кажан із сітки, зробленої за референсом (23.09.2026) — перший крилатий
за шляхом А `spec/генерація-3d-моделей-монстрів.md` (пробно, слово
замовника 23.09.2026).

Звідки сітка: референс `wiki/img/monstry/кажан.png` (висить боком на
скелі, видно одне крило) → FLUX Kontext у повітрі з розкритими крилами
(`art/monsters/кажан-3d/поза-s11.png`, вибір замовника — варіант 1 з
чотирьох) → Pixal3D → `art/monsters/кажан-3d/pixal3d-01.glb`.

Відмінності від звірів (`make_wolf_scan.py`):
  · тулуб СТОЇТЬ сторч (кажан завис у повітрі), крила — вздовж ±X;
    розворот — за головною віссю розмаху, а не тулуба;
  · скелет свій, імена — як у `winged.py` (`body`, `neck`, `head`,
    `wing.L0–2`, `hind.L/R`, `tail0–3`), мах — `winged.flap_key`;
  · крила НЕ складаються: перетинка з генератора тонка, і складання
    `winged.fold_key` рвало б її по вагах — Idle теж ширяння;
  · маска ворсу навпаки: хутро лише на темній сіро-синій шерсті,
    перетинка, нутро вух, ніс і кігті — голі.

Запуск (з каталогу проєкту):
    blender --background --python tools/blender/make_bat_scan.py -- \\
        art/monsters/кажан.blend game/models/own/кажан.glb [тека_для_картинок]
"""
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_template as base  # noqa: E402
import make_hare as hare  # noqa: E402
import winged  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
# Спроба 04: поза s661 (`поза-s661.png`: Kontext переставив у три
# чверті, а другим проходом прибрав зайві руки; вибір замовника
# 23.09.2026). На позі 3 (спроба 02) Pixal3D подвоїв вуха — кадр строго
# спереду не дає глибини, — а руки були зайві ще на позах Kontext.
SOURCE = os.path.join(ROOT, "art", "monsters", "кажан-3d", "pixal3d-03.glb")
HEIGHT = 0.9           # від кінчика хвоста до кінчиків крил, як `зріст` у mobs.json
FACES = 40000          # крила забирають більшість граней — тулубу й кігтям лишити запас
TEXTURE = 2048
MASK_BLUR = 3           # проходів розмиття межі голизни
FACE_Y, FACE_Z = -0.2, 0.55   # морда (коротка шерсть): попереду й вище за ці межі

# Кістки — заміряно на ортовидах розвернутої сітки (1,6 м у кадрі) і
# центроїдами вершин по смугах висоти (спроба 04, сітка з пози s661 —
# без зайвих рук і в три чверті, щоб вуха не двоїлись; вибір замовника).
# Найдальша вперед точка тут — кігті рук (Z ≈ 0,38), а не ніс: ніс
# заміряно на виді збоку (Y −0,2, Z 0,52). Імена — як у `winged.py`:
# `flap_key` крутить `wing.*` навколо X, і це «вгору-вниз» для обох
# боків, лише коли крило йде вздовж ±X. Крила несиметричні (поза 1:
# праве, +X, задерте вище) — кожне за своїм заміром. `wing.?1` кінчається
# на кістяному «зап'ястку» переднього краю, `wing.?2` — до кінчика.
# `body` — сторч, знизу вгору: для нього поворот навколо X (+) —
# нахил уперед, зсув по локальній Y — угору, по локальній Z — уперед.
BONES = [
    ("body", (-0.05, 0.06, 0.28), (-0.02, -0.12, 0.56), None),
    ("neck", (-0.02, -0.12, 0.56), (-0.01, -0.2, 0.64), "body"),
    ("head", (-0.01, -0.2, 0.64), (-0.01, -0.32, 0.61), "neck"),
    # Вуха — свої кістки від голови. Без них «тепло» віддавало пів вуха
    # найближчим кісткам крил (779 з 1650 вершин вух, вага > 0.2), і
    # в махові вухо рвалось на дві пластини — виглядало як чотири вуха.
    ("ear.L", (0.04, -0.2, 0.68), (0.09, -0.23, 0.83), "head"),
    ("ear.R", (-0.08, -0.19, 0.68), (-0.11, -0.21, 0.79), "head"),
    ("wing.L0", (0.07, -0.05, 0.62), (0.15, -0.08, 0.72), "body"),
    ("wing.L1", (0.15, -0.08, 0.72), (0.23, -0.1, 0.8), "wing.L0"),
    ("wing.L2", (0.23, -0.1, 0.8), (0.57, -0.07, 0.79), "wing.L1"),
    ("wing.R0", (-0.1, -0.05, 0.62), (-0.16, -0.08, 0.72), "body"),
    ("wing.R1", (-0.16, -0.08, 0.72), (-0.22, -0.1, 0.82), "wing.R0"),
    ("wing.R2", (-0.22, -0.1, 0.82), (-0.56, -0.1, 0.87), "wing.R1"),
    # Передні лапи під грудьми (поза s661 — колишні «руки» Kontext
    # стали лапами). Рухів не мають: свої кістки лише для того, щоб
    # ваги не тягнули їх за крилами.
    ("front.L", (0.03, -0.15, 0.5), (0.03, -0.22, 0.4), "body"),
    ("front.R", (-0.09, -0.15, 0.5), (-0.09, -0.22, 0.4), "body"),
    ("hind.L", (0.0, -0.02, 0.35), (0.0, -0.08, 0.25), "body"),
    ("hind.R", (-0.13, -0.02, 0.35), (-0.13, -0.08, 0.25), "body"),
    ("tail0", (-0.07, 0.08, 0.28), (-0.11, 0.15, 0.2), "body"),
    ("tail1", (-0.11, 0.15, 0.2), (-0.15, 0.21, 0.13), "tail0"),
    ("tail2", (-0.15, 0.21, 0.13), (-0.19, 0.26, 0.06), "tail1"),
    ("tail3", (-0.19, 0.26, 0.06), (-0.23, 0.3, 0.0), "tail2"),
]


def load_mesh():
    bpy.ops.import_scene.gltf(filepath=SOURCE)
    mesh = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
    for other in list(bpy.context.scene.objects):
        if other is not mesh:
            bpy.data.objects.remove(other)
    bpy.context.view_layer.objects.active = mesh
    mesh.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return mesh


def orient(mesh):
    """Крилами вздовж ±X, мордою на −Y, низом (кінчик хвоста) на нуль,
    заввишки HEIGHT. Pixal3D віддає кажана вже приблизно мордою на −Y,
    але в три чверті (як на позі) — довернути на найменший кут так, щоб
    головна вісь розмаху (PCA по XY усіх точок — крила переважають)
    лягла на X."""
    vs = [v.co.copy() for v in mesh.data.vertices]
    cx = sum(v.x for v in vs) / len(vs)
    cy = sum(v.y for v in vs) / len(vs)
    sxx = sum((v.x - cx) ** 2 for v in vs)
    syy = sum((v.y - cy) ** 2 for v in vs)
    sxy = sum((v.x - cx) * (v.y - cy) for v in vs)
    angle = 0.5 * math.atan2(2 * sxy, sxx - syy)
    # Вісь без напрямку: брати найменший поворот (у межах ±90°).
    if angle > math.pi / 2:
        angle -= math.pi
    if angle < -math.pi / 2:
        angle += math.pi
    mesh.data.transform(Matrix.Rotation(-angle, 4, "Z")
                        @ Matrix.Translation((-cx, -cy, 0)))
    print("[кажан-скан] довернуто на %.1f°" % -math.degrees(angle))
    xs = [v.co.x for v in mesh.data.vertices]
    ys = [v.co.y for v in mesh.data.vertices]
    zs = [v.co.z for v in mesh.data.vertices]
    scale = HEIGHT / (max(zs) - min(zs))
    mesh.data.transform(
        Matrix.Scale(scale, 4)
        @ Matrix.Translation((-(max(xs) + min(xs)) / 2,
                              -(max(ys) + min(ys)) / 2, -min(zs))))


def simplify(mesh):
    # Генератор розрізає сітку по швах UV на острівці — зварити вершини
    # (UV від цього не страждають, вони в кутах граней). Без цього і
    # спрощення рве шви, і ваги «теплом» не знаходять розв'язку.
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0005)
    bpy.ops.object.mode_set(mode="OBJECT")
    mod = mesh.modifiers.new("Спрощення", "DECIMATE")
    mod.ratio = FACES / len(mesh.data.polygons)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    # Шви між клаптями UV після спрощення рвуть нормалі — згладити.
    bpy.ops.object.shade_smooth()


def base_colour(mesh):
    mat = mesh.data.materials[0]
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    return bsdf.inputs["Base Color"].links[0].from_node.image


def shrink_textures(mesh):
    for node in mesh.data.materials[0].node_tree.nodes:
        if node.type == "TEX_IMAGE" and node.image.size[0] > TEXTURE:
            node.image.scale(TEXTURE, TEXTURE)


def fur_mask(mesh):
    """Друга UV: U = голизна (0 — хутро, 1 — голо) за кольором текстури
    під вершиною."""
    image = base_colour(mesh)
    w, h = image.size
    px = np.array(image.pixels[:], dtype=np.float32).reshape(h, w, 4)
    me = mesh.data
    uv = me.uv_layers[0].data
    bare = np.zeros(len(me.vertices), dtype=np.float32)
    seen = np.zeros(len(me.vertices), dtype=np.int32)
    for loop in me.loops:
        u, v = uv[loop.index].uv
        x = min(w - 1, max(0, int(u * w)))
        y = min(h - 1, max(0, int(v * h)))
        r, g, b, _ = px[y, x]
        light = 0.3 * r + 0.59 * g + 0.11 * b
        # Хутро — лише темна несита ХОЛОДНА шерсть (сіро-синя, синій не
        # менший за червоний). Кістки-пальці крил теж темні й неситі, але
        # теплі, бурі — без умови по синьому на них ріс ворс (спроба 01,
        # знімок зблизька). Перетинка, нутро вух, ніс, кігті — насичені
        # або світлі; очі — майже чорні.
        fur = (light < 0.3 and max(r, g, b) - min(r, g, b) < 0.12
               and b >= 0.9 * r)
        dark = light < 0.04
        bare[loop.vertex_index] += 0.0 if (fur and not dark) else 1.0
        seen[loop.vertex_index] += 1
    bare = bare / np.maximum(seen, 1)
    # Розмити межу по сусідах: ворс сходить нанівець (шейдер вкорочує
    # його на fur_amount), а не обривається — різкий край давав чорні
    # зубчасті клапті біля рук і на грудях (спроба 02, зблизька).
    edges = np.array([e.vertices[:] for e in me.edges], dtype=np.int64)
    count = np.bincount(edges.ravel(), minlength=len(bare)).astype(np.float32)
    sharp = bare.copy()
    for _ in range(MASK_BLUR):
        total = np.zeros_like(bare)
        np.add.at(total, edges[:, 0], bare[edges[:, 1]])
        np.add.at(total, edges[:, 1], bare[edges[:, 0]])
        bare = 0.5 * bare + 0.5 * total / np.maximum(count, 1)
    # Розмиття лише ДОДАЄ голизни: інакше ворс заповзав на край очей,
    # носа й перетинки.
    bare = np.maximum(bare, sharp)
    # Морда — коротка шерсть (вдвічі коротша): довгі волосини, що
    # дивляться просто в камеру, читались крапками. Перед голови — усе,
    # що попереду шиї й вище плечей (після `orient`: морда на −Y).
    co = np.array([v.co[:] for v in me.vertices], dtype=np.float32)
    face = (co[:, 1] < FACE_Y) & (co[:, 2] > FACE_Z) & (np.abs(co[:, 0]) < 0.15)
    bare[face] = np.maximum(bare[face], 0.5)
    mask = me.uv_layers.new(name="Голизна")
    for loop in me.loops:
        mask.data[loop.index].uv = (float(bare[loop.vertex_index]), 0.0)
    me.uv_layers.active_index = 0
    print("[кажан-скан] голих вершин: %d із %d"
          % (int((bare > 0.5).sum()), len(bare)))


def rig(mesh):
    skeleton = hare.armature(BONES)
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    skeleton.select_set(True)
    bpy.context.view_layer.objects.active = skeleton
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    by_distance(mesh, skeleton)
    keep_head(mesh)
    return skeleton


def keep_head(mesh):
    """Вуха стоять упритул до основ крил, і на межі «тепло» дає змішану
    вагу: край вуха тягнувся за махом. Де голова (вухо, голова, шия)
    тягне вершину не слабше за крило — вагу крила зняти зовсім."""
    groups = {g.index: g.name for g in mesh.vertex_groups}
    wing = [g for g in mesh.vertex_groups if g.name.startswith("wing")]
    head = ("ear.L", "ear.R", "head", "neck")
    fixed = 0
    for v in mesh.data.vertices:
        w_head = sum(e.weight for e in v.groups if groups[e.group] in head)
        w_wing = sum(e.weight for e in v.groups
                     if groups[e.group].startswith("wing"))
        if w_wing > 0 and w_head >= w_wing:
            for g in wing:
                g.remove([v.index])
            fixed += 1
    print("[кажан-скан] вуха без ваги крил: %d вершин" % fixed)


def by_distance(mesh, skeleton):
    """Вершинам, яким «тепло» не дало ваги (окремі клапті: вуса, кігті),
    — ваги за відстанню до кісток: 1/d⁴, дві найближчі кістки."""
    bones = [(b.name, Vector(b.head_local), Vector(b.tail_local))
             for b in skeleton.data.bones]
    groups = {name: mesh.vertex_groups.get(name)
              or mesh.vertex_groups.new(name=name) for name, _, _ in bones}
    fixed = 0
    for v in mesh.data.vertices:
        if sum(e.weight for e in v.groups) > 0.01:
            continue
        near = []
        for name, a, b in bones:
            ab = b - a
            t = max(0.0, min(1.0, (v.co - a).dot(ab) / ab.length_squared))
            d = (v.co - (a + ab * t)).length
            near.append((d, name))
        near.sort()
        weights = [(1.0 / max(d, 0.005) ** 4, n) for d, n in near[:2]]
        total = sum(w for w, _ in weights)
        for w, n in weights:
            groups[n].add([v.index], w / total, "REPLACE")
        fixed += 1
    print("[кажан-скан] ваги за відстанню: %d вершин із %d"
          % (fixed, len(mesh.data.vertices)))


def k(flap, злам=0.0, **bones):
    """Кадр: мах крил (`winged.flap_key`) + інші кістки
    (`кістка=((x, y, z) кути, (x, y, z) зсув)`, `wing_L0` → `wing.L0`)."""
    out = winged.flap_key(flap, злам)
    for name, value in bones.items():
        out[name.replace("_", ".")] = value
    return out


def actions(rig):
    """Кажан весь час у повітрі — крила не складаються (див. докстрінг):
    Idle — повільне ширяння, Walk/Flying — частий мах, Attack — замах і
    кидок уперед з укусом, Death — крила обвисають, падає грудкою."""
    up = ((0, 0, 0), (0, 0.02, 0))
    h = hare
    h.action(rig, "Idle", 40, {
        1: k(-28, 8),
        20: k(26, -10, body=up, tail1=((6, 0, 0), (0, 0, 0))),
        40: k(-28, 8),
    })
    for name in ("Walk", "Flying"):
        h.action(rig, name, 16, {
            1: k(-40, 10, body=((12, 0, 0), (0, 0, 0))),
            8: k(38, -14, body=((12, 0, 0), (0, 0.025, 0))),
            16: k(-40, 10, body=((12, 0, 0), (0, 0, 0))),
        })
    h.action(rig, "Attack", 20, {
        1: k(0),
        6: k(-45, 12, body=((-12, 0, 0), (0, 0.03, -0.04)),
             head=((-15, 0, 0), (0, 0, 0))),
        11: k(40, -16, body=((30, 0, 0), (0, -0.02, 0.18)),
              neck=((12, 0, 0), (0, 0, 0)), head=((20, 0, 0), (0, 0, 0))),
        15: k(10, body=((12, 0, 0), (0, 0, 0.08))),
        20: k(0),
    })
    h.action(rig, "Death", 30, {
        1: k(0),
        10: k(-20, 20, body=((-20, 0, 25), (0, 0.04, 0))),
        # Лягає черевом донизу з розпластаними крилами: опущені крила
        # (мах +55) простромлювали землю на 0,2 м — заміряно низом сітки.
        30: k(-5, 20, body=((80, 0, 0), (0, 0.02, 0)),
              head=((25, 0, 0), (0, 0, 0)),
              hind_L=((40, 0, 0), (0, 0, 0)),
              hind_R=((40, 0, 0), (0, 0, 0))),
    })
    rig.animation_data.action = bpy.data.actions["Idle"]


def previews(rig, folder):
    """Кадри для перевірки — спереду в три чверті, як на позі (замовник
    23.09.2026: «3D рендер теж схожим профілем, а не зі спини»), і збоку
    для кидка в атаці. Камери `make_hare.previews` стоять під зайця на
    землі й бачили кажана ззаду-збоку."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 600
    scene.render.resolution_y = 600
    world = bpy.data.worlds.new("Тло")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = \
        (0.55, 0.57, 0.6, 1)
    scene.world = world
    sun = bpy.data.objects.new("Сонце", bpy.data.lights.new("Сонце", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(-30))
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("Камера", bpy.data.cameras.new("Камера"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 1.5
    scene.collection.objects.link(cam)
    scene.camera = cam
    aim = Vector((0, 0, 0.45))
    views = {"три-чверті": Vector((-0.45, -1.0, 0.2)),
             "збоку": Vector((1.0, 0.0, 0.05))}
    shots = [("Idle", 1, "три-чверті"), ("Idle", 20, "три-чверті"),
             ("Walk", 8, "три-чверті"), ("Death", 30, "три-чверті"),
             ("Attack", 6, "збоку"), ("Attack", 11, "збоку"),
             ("Attack", 15, "збоку"), ("Idle", 1, "збоку")]
    for name, frame, view in shots:
        d = views[view].normalized()
        cam.location = aim + d * 3
        cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
        rig.animation_data.action = bpy.data.actions[name]
        scene.frame_set(frame)
        scene.render.filepath = os.path.join(
            folder, "%s-%02d-%s.png" % (name, frame, view))
        bpy.ops.render.render(write_still=True)
    rig.animation_data.action = bpy.data.actions["Idle"]
    scene.frame_set(1)
    for obj in (cam, sun):
        bpy.data.objects.remove(obj)


def export(out):
    bpy.ops.export_scene.gltf(
        filepath=out, export_format="GLB", export_yup=True,
        export_apply=True, export_animations=True,
        export_animation_mode="ACTIONS", export_force_sampling=True,
        export_def_bones=False, export_skins=True,
        export_texcoords=True, export_image_format="JPEG",
        export_jpeg_quality=90)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    blend = args[0] if args else "art/monsters/кажан.blend"
    glb = args[1] if len(args) > 1 else ""
    base.clear()
    bpy.context.scene.render.fps = 24
    mesh = load_mesh()
    orient(mesh)
    simplify(mesh)
    shrink_textures(mesh)
    fur_mask(mesh)
    mesh.name = "Тіло"
    if os.environ.get("ONLY_ORIENT") or not BONES:
        # Для розстановки кісток: лише розвернута сітка, без скелета.
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(blend))
        print("[кажан-скан] лише сітка (без кісток)", blend)
        return
    skeleton = rig(mesh)
    actions(skeleton)
    if len(args) > 2:
        previews(skeleton, args[2])
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(blend))
    print("[кажан-скан] збережено", blend)
    if glb:
        export(os.path.abspath(glb))
        print("[кажан-скан] експорт", glb)


if __name__ == "__main__":
    main()
