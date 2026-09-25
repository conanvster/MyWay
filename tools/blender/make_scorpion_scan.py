"""Скорпіон із сітки, зробленої за референсом (23.09.2026) — перший
членистоногий за шляхом А `spec/генерація-3d-моделей-монстрів.md`
(пробно, слово замовника 23.09.2026), на заміну скорпіонові з примітивів
(`scorpions.py`).

Звідки сітка: референс `wiki/img/monstry/скорпіон.png` (камера дуже
низько й близько — клешні гігантські) → FLUX Kontext у три чверті трохи
згори на сірому тлі (`art/monsters/скорпіон-3d/поза-s22.png`, вибір
замовника — варіант 2 з чотирьох) → Pixal3D → `pixal3d-01.glb`.

Як `make_wolf_scan.py` (розворот, `level`, центр за габаритом, спрощення,
текстури), але:
  · розворот — найменшим кутом до головної осі тіла (PCA по XY), мордою
    на −Y: Pixal3D віддає звіра вже приблизно мордою до камери;
  · скелет і рухи — `scorpions.py` (ті самі імена кісток: `body`, `head`,
    `leg.L0–R3`, `arm/claw.L/R`, `tail0–4`), дуга хвоста для
    `scorpions.tail_aim` — з точок заміряного хвоста;
  · хутра немає (панцир) — маски ворсу теж.

Запуск (з каталогу проєкту):
    blender --background --python tools/blender/make_scorpion_scan.py -- \\
        art/monsters/скорпіон.blend game/models/own/скорпіон.glb [тека_для_картинок]
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
import scorpions  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SOURCE = os.path.join(ROOT, "art", "monsters", "скорпіон-3d", "pixal3d-01.glb")
HEIGHT = 0.5           # до верху дуги хвоста, як `зріст` у mobs.json
FACES = 20000
TEXTURE = 2048

# Кістки — заміряно на ортовидах (1,4 м у кадрі) розвернутої й
# вирівняної сітки та за кінчиками ніг (найнижчі вершини). Імена й
# напрямки — як у `scorpions.geometry`: `body` від хвоста до голови,
# ноги від боку тулуба вниз до кінчика, `leg.?0` — передня, `.L` — +X.
# Ноги несиметричні (поза в три чверті) — кожна за своїм заміром.
TAIL = [(0.03, 0.16, 0.15), (0.04, 0.27, 0.22), (0.04, 0.30, 0.34),
        (0.04, 0.25, 0.45), (0.04, 0.15, 0.50), (0.04, 0.04, 0.44)]
LEG_TIPS = {
    "L0": (0.22, -0.07), "L1": (0.22, 0.03), "L2": (0.20, 0.13),
    "L3": (0.165, 0.23),
    "R0": (-0.152, -0.164), "R1": (-0.202, -0.05), "R2": (-0.26, 0.03),
    "R3": (-0.29, 0.16),
}
LEG_ROOT_Y = [-0.10, -0.03, 0.04, 0.10]
BONES = [
    ("body", (0.01, 0.16, 0.12), (0.01, -0.14, 0.12), None),
    ("head", (0.016, -0.14, 0.12), (0.016, -0.22, 0.12), "body"),
    ("arm.L", (0.06, -0.16, 0.1), (0.14, -0.22, 0.08), "body"),
    ("claw.L", (0.14, -0.22, 0.08), (0.15, -0.31, 0.05), "arm.L"),
    ("arm.R", (-0.05, -0.16, 0.1), (-0.08, -0.22, 0.1), "body"),
    ("claw.R", (-0.08, -0.22, 0.1), (-0.08, -0.31, 0.06), "arm.R"),
] + [("leg.%s" % key, ((0.07 if key[0] == "L" else -0.07),
                       LEG_ROOT_Y[int(key[1])], 0.12),
      (tip[0], tip[1], 0.02), "body") for key, tip in LEG_TIPS.items()] \
  + [("tail%d" % i, TAIL[i], TAIL[i + 1], "body" if i == 0 else "tail%d" % (i - 1))
     for i in range(5)]
# `scorpions.actions` бере з виду лише L (підйом тулуба в ході).
SPEC = dict(L=0.32)
DEATH_LIFT = 0.25
# Удар хвостом: на скільки градусів дуга йде назад у замаху й уперед.
ATTACK_WIND, ATTACK_HIT = 20.0, 45.0


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
    """Мордою на −Y, заввишки HEIGHT, низом на нуль. Головна вісь тіла —
    PCA по XY усіх точок (хвіст і клешні витягують його вздовж); вісь без
    напрямку, тож довернути найменшим кутом — Pixal3D віддає звіра вже
    приблизно мордою до камери (−Y)."""
    vs = [v.co.copy() for v in mesh.data.vertices]
    cx = sum(v.x for v in vs) / len(vs)
    cy = sum(v.y for v in vs) / len(vs)
    sxx = sum((v.x - cx) ** 2 for v in vs)
    syy = sum((v.y - cy) ** 2 for v in vs)
    sxy = sum((v.x - cx) * (v.y - cy) for v in vs)
    angle = 0.5 * math.atan2(2 * sxy, sxx - syy)
    # Головна вісь має лягти на Y: поворот на (90° − кут), найменший.
    turn = math.pi / 2 - angle
    while turn > math.pi / 2:
        turn -= math.pi
    while turn < -math.pi / 2:
        turn += math.pi
    mesh.data.transform(Matrix.Rotation(turn, 4, "Z")
                        @ Matrix.Translation((-cx, -cy, 0)))
    print("[скорпіон-скан] довернуто на %.1f°" % math.degrees(turn))
    zs = [v.co.z for v in mesh.data.vertices]
    scale = HEIGHT / (max(zs) - min(zs))
    mesh.data.transform(Matrix.Scale(scale, 4)
                        @ Matrix.Translation((0, 0, -min(zs))))


def level(mesh):
    """Pixal3D ставить вовка з нахилом (перспектива арту): після `orient`
    передні лапи висіли ~8 см над землею. Нахилити й покрутити так, щоб
    найнижчі точки чотирьох лап (квадранти навколо центру, без смуги
    хвоста посередині) лягли на одну площину, тоді знов на нуль і в
    HEIGHT."""
    vs = [v.co for v in mesh.data.vertices]
    cx = sum(v.x for v in vs) / len(vs)
    cy = sum(v.y for v in vs) / len(vs)
    feet = {}
    for v in vs:
        if abs(v.x - cx) < 0.03:
            continue
        key = (v.x > cx, v.y > cy)
        if key not in feet or v.z < feet[key].z:
            feet[key] = v.copy()
    front = [feet[(s, False)] for s in (False, True)]
    hind = [feet[(s, True)] for s in (False, True)]
    right = [feet[(False, b)] for b in (False, True)]
    left = [feet[(True, b)] for b in (False, True)]

    def mid(pair):
        return sum(pair, Vector()) / 2

    f, b = mid(front), mid(hind)
    pitch = math.atan2(f.z - b.z, b.y - f.y)
    r, l = mid(right), mid(left)
    roll = math.atan2(l.z - r.z, l.x - r.x)
    mesh.data.transform(Matrix.Rotation(pitch, 4, "X"))
    mesh.data.transform(Matrix.Rotation(roll, 4, "Y"))
    print("[скорпіон-скан] вирівняно: тангаж %.1f°, крен %.1f°"
          % (math.degrees(pitch), math.degrees(roll)))
    zs = [v.co.z for v in mesh.data.vertices]
    scale = HEIGHT / (max(zs) - min(zs))
    mesh.data.transform(Matrix.Scale(scale, 4)
                        @ Matrix.Translation((0, 0, -min(zs))))
    # Центр — посередині габариту від носа до хвоста, а не в центрі
    # тулуба: морда в вовка довга, і `fur_look` (камера на початок
    # координат) обрізав її краєм кадру.
    ys = [v.co.y for v in mesh.data.vertices]
    shift = (max(ys) + min(ys)) / 2
    mesh.data.transform(Matrix.Translation((0, -shift, 0)))
    print("[скорпіон-скан] зсув уздовж тулуба: %.3f м" % shift)
    return shift


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
    """Друга UV: U = голизна. Колір під вершиною з текстури: рожеве
    (нутро вух, ніс) і майже чорне (очі, кігті) — голе, решта в хутрі."""
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
        # Рожеве від бурого — за синім: у рожевого він ~ як зелений,
        # у бурої шерсті помітно менший.
        pink = r > 0.3 and r > 1.45 * g and b > 0.85 * g
        dark = light < 0.06
        bare[loop.vertex_index] += 1.0 if (pink or dark) else 0.0
        seen[loop.vertex_index] += 1
    bare = bare / np.maximum(seen, 1)
    mask = me.uv_layers.new(name="Голизна")
    for loop in me.loops:
        mask.data[loop.index].uv = (float(bare[loop.vertex_index]), 0.0)
    me.uv_layers.active_index = 0
    print("[скорпіон-скан] голих вершин: %d із %d"
          % (int((bare > 0.5).sum()), len(bare)))


def rig(mesh, shift):
    """BONES заміряно до центрування (`level`) — зсунути так само."""
    moved = [(name, (h[0], h[1] - shift, h[2]), (t[0], t[1] - shift, t[2]),
              parent) for name, h, t, parent in BONES]
    skeleton = hare.armature(moved)
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    skeleton.select_set(True)
    bpy.context.view_layer.objects.active = skeleton
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    by_distance(mesh, skeleton)
    return skeleton


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
    print("[скорпіон-скан] ваги за відстанню: %d вершин із %d"
          % (fixed, len(mesh.data.vertices)))


def attack(rig):
    """Удар хвостом — поворотом ВСІЄЇ дуги довкола основи (`tail_aim`
    з straight = 0 крутить лише `tail0`). Процедурний удар розгинав
    ланцюг: на цьому хвості, вже закрученому вперед, замах складав його
    на спину, а удар витягав уперед низько над землею."""
    g = {"tail": [Vector(p) for p in TAIL]}
    rest = math.degrees(math.atan2(TAIL[1][2] - TAIL[0][2],
                                   TAIL[1][1] - TAIL[0][1]))
    wind = scorpions.tail_aim(g, rest - ATTACK_WIND, 0.0)
    wind.update({"arm.L": ((0, 0, 20), (0, 0, 0)),
                 "arm.R": ((0, 0, -20), (0, 0, 0))})
    hit = scorpions.tail_aim(g, rest + ATTACK_HIT, 0.0)
    hit.update({"claw.L": ((0, 0, -15), (0, 0, 0)),
                "claw.R": ((0, 0, 15), (0, 0, 0))})
    back = scorpions.tail_aim(g, rest + ATTACK_HIT * 0.4, 0.0)
    bpy.data.actions.remove(bpy.data.actions["Attack"])
    hare.action(rig, "Attack", 18, {1: {}, 6: wind, 10: hit, 14: back,
                                    18: {}})


def death(rig):
    """Перекид на спину, як у `scorpions.actions`, але з підйомом: хвіст
    цієї сітки — висока дуга, і після перекиду він ішов під землю на
    0,25 м (заміряно найнижчою вершиною). Зсув — у власних осях кістки
    `body` (Z — угору)."""
    # `hare.action` створює нову дію; стара «Death» лишилась би поруч,
    # а нова звалася б «Death.001» — її ні експорт, ні гра не шукають.
    bpy.data.actions.remove(bpy.data.actions["Death"])
    hare.action(rig, "Death", 30, {
        1: {},
        30: {"body": ((0, 175, 0), (0, 0, DEATH_LIFT))},
    })
    rig.animation_data.action = bpy.data.actions["Idle"]


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
    blend = args[0] if args else "art/monsters/скорпіон.blend"
    glb = args[1] if len(args) > 1 else ""
    base.clear()
    bpy.context.scene.render.fps = 24
    mesh = load_mesh()
    orient(mesh)
    shift = level(mesh)
    simplify(mesh)
    shrink_textures(mesh)
    mesh.name = "Тіло"
    if os.environ.get("ONLY_ORIENT"):
        # Для розстановки кісток: лише розвернута сітка, без скелета.
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(blend))
        return
    skeleton = rig(mesh, shift)
    scorpions.actions(skeleton, SPEC, {"tail": [Vector(p) for p in TAIL]})
    attack(skeleton)
    death(skeleton)
    if len(args) > 2:
        hare.previews(skeleton, args[2], zoom=1.6)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(blend))
    print("[скорпіон-скан] збережено", blend)
    if glb:
        export(os.path.abspath(glb))
        print("[скорпіон-скан] експорт", glb)


if __name__ == "__main__":
    main()
