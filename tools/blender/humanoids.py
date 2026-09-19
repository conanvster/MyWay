"""Людиноподібні монстри бестіарію (spec/monsters.md, конвеєр «Л») — з
моделі людини на ТОМУ САМОМУ скелеті, з рухами людини.

Замовник 19.09.2026: «зроби наступні монстри що залишились». Вовкулаки,
звіролюди зі зброєю, зомбі, гуль, упир, вампіри, драконіди — усе це
людина з іншою шкірою (хутро, луска, перефарбована), іншою головою
(звірина з простих фігур на кістці голови), хвостом, кігтями, вбранням і
зброєю в руці. Скелет не чіпається, тож рухи бібліотеки людини (UAL1)
лягають як є; чотири з них вбудовуються в модель під назвами, які шукає
гра для монстрів: Idle, Walk, Attack, Death.

Частини вбрання звуться «Вбрання-…», а не «Одяг-…»: одяг гравця гра
ховає, доки його не вдягнуто (`skinned_model.gd:wear`), а вбрання
монстра на ньому завжди.

Запуск (з каталогу проєкту):
    blender --background --python tools/blender/humanoids.py -- \\
        <вид> [тека_для_картинок]
    blender --background --python tools/blender/humanoids.py -- --список
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_races as races  # noqa: E402
import make_template as base  # noqa: E402

ROOT = races.ROOT
TEX = os.path.join(ROOT, "art", "monsters", "textures")
SKINS = os.path.join(ROOT, "art", "races", "textures")
UAL = os.path.join(ROOT, "game", "models", "player", "animations",
                   "UAL1_Standard.glb")
OUT = os.path.join(ROOT, "game", "models", "own", "humanoids")

# Рухи: (спокій, хода, атака) з бібліотеки людини; смерть — Death01.
MOVES = {
    "звір": ("Idle_Loop", "Jog_Fwd_Loop", "Punch_Cross"),
    "зброя": ("Sword_Idle", "Walk_Loop", "Sword_Attack"),
    "чари": ("Spell_Simple_Idle_Loop", "Walk_Loop", "Spell_Simple_Shoot"),
    "мрець": ("Idle_Loop", "Walk_Loop", "Punch_Jab"),
    "повзе": ("Crouch_Idle_Loop", "Crouch_Fwd_Loop", "Punch_Cross"),
}

# Вид. skin — шкіра: ("хутро"|"луска", картинка) або ("колір", раса з
# skin_texture.py); head — звірина голова або None (людська); outfit —
# [(частина, колір)]; weapon — зброя в правій руці.
SPECIES = {
    "вовкулака-новак": dict(skin=("хутро", "хутро-сиве"), head="вовк",
                            tail=("пухнастий", 0.5), claws=True,
                            outfit=[("лахміття", (0.35, 0.28, 0.2))],
                            moves="звір"),
    "вовкулака": dict(skin=("хутро", "хутро-темне"), head="вовк",
                      tail=("пухнастий", 0.6), claws=True, bulk=0.012,
                      outfit=[("штани-рвані", (0.2, 0.16, 0.12))],
                      moves="звір"),
    "вовкулака-альфа": dict(skin=("хутро", "хутро-сиве"), head="вовк",
                            tail=("пухнастий", 0.7), claws=True, bulk=0.025,
                            outfit=[("штани-рвані", (0.15, 0.12, 0.1))],
                            moves="звір", eyes=(1.0, 0.2, 0.05)),
    "щуролюд-злодій": dict(skin=("хутро", "хутро-сіре"), head="щур",
                           tail=("тонкий", 0.8),
                           outfit=[("каптур", (0.18, 0.16, 0.14)),
                                   ("сорочка", (0.22, 0.2, 0.17)),
                                   ("штани", (0.15, 0.13, 0.11))],
                           weapon="кинджали", moves="зброя"),
    "гнол-мисливець": dict(skin=("хутро", "хутро-рисяче"), head="гієна",
                           outfit=[("сорочка", (0.4, 0.28, 0.16)),
                                   ("пасок", (0.2, 0.13, 0.08)),
                                   ("штани", (0.3, 0.22, 0.14))],
                           weapon="спис", moves="зброя"),
    "гнол-воїн": dict(skin=("хутро", "хутро-рисяче"), head="гієна",
                      bulk=0.01,
                      outfit=[("сорочка", (0.32, 0.22, 0.13)),
                              ("пасок", (0.2, 0.13, 0.08)),
                              ("штани", (0.26, 0.18, 0.11)),
                              ("намисто", (0.85, 0.8, 0.68))],
                      weapon="сокира", shield=True, moves="зброя"),
    "лисолюд-шаман": dict(skin=("хутро", "хутро-руде"), head="лис",
                          tail=("пухнастий", 0.6),
                          outfit=[("мантія", (0.3, 0.16, 0.36)),
                                  ("намисто", (0.9, 0.75, 0.3))],
                          weapon="посох", moves="чари"),
    "кабанолюд-громила": dict(skin=("хутро", "щетина"), head="кабан",
                              bulk=0.025,
                              outfit=[("наплічники", (0.3, 0.3, 0.32)),
                                      ("штани", (0.25, 0.18, 0.12)),
                                      ("пасок", (0.15, 0.1, 0.06))],
                              weapon="молот", moves="зброя"),
    "ведмедолюд-вождь": dict(skin=("хутро", "хутро-буре"), head="ведмідь",
                             bulk=0.035,
                             outfit=[("плащ", (0.3, 0.22, 0.15)),
                                     ("штани", (0.2, 0.15, 0.1)),
                                     ("наплічники", (0.35, 0.3, 0.2))],
                             weapon="дворучна сокира", moves="зброя"),
    "зомбі": dict(skin=("колір", "зомбі"),
                  outfit=[("лахміття", (0.3, 0.3, 0.26))], moves="мрець"),
    "зомбі-громило": dict(skin=("колір", "зомбі"), bulk=0.035,
                          outfit=[("штани-рвані", (0.25, 0.24, 0.2))],
                          moves="мрець"),
    "гуль": dict(skin=("колір", "гуль"), claws=True, fangs=True,
                 outfit=[("штани-рвані", (0.2, 0.18, 0.16))], moves="повзе",
                 eyes=(0.9, 0.9, 0.5)),
    "упир": dict(skin=("колір", "упир"), claws=True, fangs=True,
                 outfit=[("лахміття", (0.12, 0.1, 0.1))], moves="звір",
                 eyes=(1.0, 0.1, 0.05)),
    "вампір": dict(skin=("колір", "вампір"), fangs=True,
                   outfit=[("сорочка", (0.4, 0.05, 0.08)),
                           ("штани", (0.06, 0.05, 0.06)),
                           ("чоботи", (0.05, 0.04, 0.04)),
                           ("плащ", (0.08, 0.02, 0.04))],
                   weapon="рапіра", moves="зброя", eyes=(1.0, 0.15, 0.1)),
    "вампір-лорд": dict(skin=("колір", "вампір"), fangs=True, bulk=0.012,
                        wings=1.2, crown=True,
                        outfit=[("сорочка", (0.3, 0.02, 0.06)),
                                ("штани", (0.05, 0.04, 0.05)),
                                ("чоботи", (0.05, 0.04, 0.04)),
                                ("плащ", (0.1, 0.01, 0.03))],
                        weapon="меч", moves="зброя", eyes=(1.0, 0.1, 0.05)),
    "драконід-воїн": dict(skin=("луска", "луска-зелена"), head="дракон",
                          tail=("товстий", 0.9), claws=True,
                          outfit=[("кіраса", (0.55, 0.5, 0.42)),
                                  ("пасок", (0.2, 0.13, 0.08))],
                          weapon="меч", shield=True, moves="зброя"),
    "драконід-лучник": dict(skin=("луска", "луска-зелена"), head="дракон",
                            tail=("товстий", 0.9), claws=True,
                            outfit=[("сорочка", (0.28, 0.22, 0.14)),
                                    ("пасок", (0.2, 0.13, 0.08))],
                            weapon="лук", moves="чари"),
    "драконід-жрець": dict(skin=("луска", "луска-червона"), head="дракон",
                           horns=0.3, tail=("товстий", 0.9),
                           outfit=[("мантія", (0.55, 0.42, 0.15))],
                           weapon="посох", moves="чари"),
    "драконід-вартовий": dict(skin=("луска", "луска-темна"), head="дракон",
                              horns=0.35, tail=("товстий", 1.1), bulk=0.02,
                              wings=1.4,
                              outfit=[("кіраса", (0.3, 0.3, 0.34)),
                                      ("наплічники", (0.3, 0.3, 0.34))],
                              weapon="алебарда", moves="зброя",
                              eyes=(1.0, 0.6, 0.1)),
    # Наги (Л+З): верх людини на зміїному хвості.
    "наг": dict(skin=("колір", "наг"), naga=("луска-зелена", 2.4),
                outfit=[("пасок", (0.55, 0.45, 0.2))], weapon="спис",
                moves="зброя", eyes=(0.9, 0.8, 0.1)),
    "нагиня-чаклунка": dict(sex="жінка", skin=("колір", "наг"),
                            naga=("луска-піщана", 2.4),
                            outfit=[("сорочка", (0.2, 0.45, 0.4)),
                                    ("намисто", (0.9, 0.75, 0.3))],
                            weapon="посох", crown=True, moves="чари",
                            eyes=(0.3, 1.0, 0.8)),
    # Скелети (конвеєр «К»): тіла немає — кістки з простих фігур уздовж
    # кісток скелета людини (слово «усе своє», не набір KayKit).
    "скелет": dict(bones=True, moves="мрець", eyes=(0.4, 0.8, 1.0)),
    "скелет-воїн": dict(bones=True, weapon="меч", shield=True,
                        outfit=[("шолом-кістяка", (0.45, 0.45, 0.48))],
                        moves="зброя", eyes=(0.4, 0.8, 1.0)),
    "скелет-лучник": dict(bones=True, weapon="лук", moves="чари",
                          outfit=[("каптур-кістяка", (0.2, 0.18, 0.16))],
                          eyes=(0.4, 0.8, 1.0)),
    "скелет-маг": dict(bones=True, weapon="посох", moves="чари",
                       outfit=[("мантія-кістяка", (0.2, 0.12, 0.3))],
                       eyes=(0.7, 0.3, 1.0)),
}

# Частини тіла під вбрання — умова на точку, як одяг гравця.
PIECES = {
    "сорочка": ({"spine_01", "spine_02", "spine_03", "clavicle_l",
                 "clavicle_r", "upperarm_l", "upperarm_r", "pelvis"},
                0.012, lambda p: p.z >= 0.97),
    "кіраса": ({"spine_01", "spine_02", "spine_03", "clavicle_l",
                "clavicle_r", "pelvis"}, 0.02, lambda p: p.z >= 0.93),
    "штани": ({"pelvis", "thigh_l", "thigh_r", "calf_l", "calf_r"},
              0.008, lambda p: 0.3 <= p.z <= 1.0),
    "пасок": ({"pelvis", "spine_01"}, 0.019, lambda p: 0.93 <= p.z <= 1.0),
    "чоботи": ({"calf_l", "calf_r", "foot_l", "foot_r", "ball_l", "ball_r",
                "ball_leaf_l", "ball_leaf_r"}, 0.011, lambda p: p.z <= 0.34),
    "каптур": ({"Head", "neck_01"}, 0.02,
               lambda p: p.y > -0.06 and p.z >= 1.52),
}


def fur_material(name, picture, scale=6.0):
    """Хутро чи луска на все тіло: картинка, повторена `scale` разів по
    розгортці тіла (вузол Mapping — glTF переносить як KHR_texture_
    transform)."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 0.85
    bsdf.inputs["Specular IOR Level"].default_value = 0.2
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(os.path.join(TEX, picture + ".png"))
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (scale, scale, scale)
    coord = nt.nodes.new("ShaderNodeTexCoord")
    nt.links.new(coord.outputs["UV"], mapping.inputs["Vector"])
    nt.links.new(mapping.outputs["Vector"], tex.inputs["Vector"])
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    mat.diffuse_color = (0.4, 0.35, 0.3, 1.0)
    return mat


def reskin(body, skin, sex="чоловік"):
    kind, what = skin
    if kind == "колір":
        races.reskin(body, what, sex)
        return body.data.materials[0]
    mat = fur_material("Шкіра", what, 6.0 if kind == "хутро" else 8.0)
    body.data.materials.clear()
    body.data.materials.append(mat)
    return mat


LEGS = {"thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r",
        "ball_l", "ball_r", "ball_leaf_l", "ball_leaf_r"}


def drop_legs(body):
    """Нага: ніг немає — від таза хвіст."""
    bones = races.dominant(body)
    bm = bmesh.new()
    bm.from_mesh(body.data)
    gone = [v for v in bm.verts if bones.get(v.index) in LEGS]
    bmesh.ops.delete(bm, geom=gone, context="VERTS")
    bm.to_mesh(body.data)
    bm.free()


def snake_tail(picture, length):
    """Хвіст наги від таза вниз до землі й назад по землі, звужується.
    Прив'язаний до таза: повертається з тулубом, сам не звивається."""
    p = base.part
    mat = fur_material("Хвіст", picture, 4.0)
    out = []
    steps = 26  # щільно, щоб хвіст не був намистом (перший огляд)
    for i in range(steps):
        t = i / (steps - 1)
        r = 0.15 * (1.0 - 0.8 * t)
        if t < 0.3:
            k = t / 0.3
            at = (0, 0.05 + 0.25 * k, 0.9 - (0.9 - r) * k)
        else:
            k = (t - 0.3) / 0.7
            at = (0, 0.3 + (length - 0.3) * k, r)
        out.append(p("sphere", "pelvis", at, (r, 0.16, r * 1.15), mat))
    return out


def drop_head(body):
    """Прибрати людську голову (обличчя, череп) — буде звірина."""
    bones = races.dominant(body)
    bm = bmesh.new()
    bm.from_mesh(body.data)
    gone = [v for v in bm.verts if bones.get(v.index) == "Head"]
    bmesh.ops.delete(bm, geom=gone, context="VERTS")
    bm.to_mesh(body.data)
    bm.free()
    for obj in list(bpy.data.objects):
        if obj.name.startswith(("Eyes", "Eyebrows")):
            bpy.data.objects.remove(obj)


def shell(body, name, keep, gap, inside, mat, holes=0.0):
    """Шматок тіла, відсунутий на `gap` — вбрання. `holes` — частка граней,
    що випадають (лахміття)."""
    bones = races.dominant(body)
    piece = body.copy()
    piece.data = body.data.copy()
    piece.name = "Вбрання-" + name
    bpy.context.scene.collection.objects.link(piece)
    mw = body.matrix_world
    bm = bmesh.new()
    bm.from_mesh(piece.data)
    drop = [v for v in bm.verts if bones.get(v.index, "") not in keep
            or not inside(mw @ v.co)]
    bmesh.ops.delete(bm, geom=drop, context="VERTS")
    if holes > 0.0:
        rng = random.Random(hash(name) & 0xffff)
        torn = [f for f in bm.faces if rng.random() < holes]
        bmesh.ops.delete(bm, geom=torn, context="FACES")
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * gap
    bm.to_mesh(piece.data)
    bm.free()
    piece.data.materials.clear()
    piece.data.materials.append(mat)
    return piece


def solid(name, rgb, rough=0.8, glow=0.0):
    """Кольори тут — як на екрані (sRGB); Blender чекає лінійних. Без
    переводу темно-коричневі штани виходили кремовими (перша збірка
    вовкулаки)."""
    rgb = tuple(races._linear(c) for c in rgb)
    mat = races.material(name, rgb, rough)
    if glow > 0.0:
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Emission Color"].default_value = (*rgb, 1.0)
        bsdf.inputs["Emission Strength"].default_value = glow
    return mat


def outfit(body, items):
    made = []
    for what, rgb in items:
        mat = solid("Вбрання-" + what, rgb)
        if what in PIECES:
            keep, gap, inside = PIECES[what]
            made.append(shell(body, what, keep, gap, inside, mat))
        elif what == "лахміття":
            for part in ("сорочка", "штани"):
                keep, gap, inside = PIECES[part]
                made.append(shell(body, "лахміття-" + part, keep, gap,
                                  inside, mat, holes=0.3))
        elif what == "штани-рвані":
            keep, gap, inside = PIECES["штани"]
            made.append(shell(body, "штани-рвані", keep, gap,
                              lambda p: 0.55 <= p.z <= 1.0, mat, holes=0.2))
        elif what == "мантія":
            keep, gap, inside = PIECES["сорочка"]
            made.append(shell(body, "мантія-верх", keep, gap, inside, mat))
            made.append(skirt(mat))
        elif what == "плащ":
            made.append(cape(mat))
        elif what == "наплічники":
            for sign, bone in ((1, "clavicle_l"), (-1, "clavicle_r")):
                made.append(base.part("sphere", bone,
                                      (sign * 0.22, 0.05, 1.47),
                                      (0.11, 0.1, 0.07), mat))
        elif what == "намисто":
            for i in range(9):
                a = math.radians(-60 + i * 15)
                made.append(base.part("sphere", "spine_03",
                                      (math.sin(a) * 0.12,
                                       -math.cos(a) * 0.1 + 0.02, 1.43),
                                      (0.018, 0.018, 0.022), mat))
    return made


def skirt(mat):
    """Поли мантії — конус від пояса до щиколоток, на тазі."""
    bpy.ops.mesh.primitive_cone_add(vertices=16, radius1=0.34, radius2=0.2,
                                    depth=0.8, location=(0, 0.03, 0.55))
    obj = bpy.context.active_object
    obj.name = "Вбрання-поли"
    bpy.ops.object.shade_smooth()
    group = obj.vertex_groups.new(name="pelvis")
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    obj.data.materials.append(mat)
    return obj


def cape(mat):
    """Плащ — вигнута пластина за спиною, від плечей до литок."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.26, depth=1.0,
                                        location=(0, 0.1, 0.95))
    obj = bpy.context.active_object
    obj.name = "Вбрання-плащ"
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    front = [v for v in bm.verts if v.co.y < 0.02]
    bmesh.ops.delete(bm, geom=front, context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    obj.scale = (1.15, 0.6, 1.0)
    bpy.ops.object.transform_apply(scale=True)
    bpy.ops.object.shade_smooth()
    group = obj.vertex_groups.new(name="spine_03")
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    obj.data.materials.append(mat)
    return obj


# --- голови ---------------------------------------------------------------

# Центр голови людини (кістка Head: 1,60…1,68 м), перед — −Y.
C = Vector((0.0, 0.0, 1.66))
HEADS = {
    # skull (x,y,z радіуси), snout (довжина, товщина), вуха (вид, розмір)
    "вовк": dict(skull=(0.1, 0.12, 0.1), snout=(0.14, 0.05),
                 ears=("гострі", 0.07)),
    "гієна": dict(skull=(0.11, 0.12, 0.11), snout=(0.12, 0.055),
                  ears=("круглі", 0.05), mane=True),
    "лис": dict(skull=(0.09, 0.1, 0.09), snout=(0.13, 0.04),
                ears=("гострі", 0.09)),
    "щур": dict(skull=(0.08, 0.1, 0.08), snout=(0.14, 0.035),
                ears=("круглі", 0.06)),
    "кабан": dict(skull=(0.13, 0.13, 0.12), snout=(0.13, 0.07),
                  ears=("гострі", 0.05), tusks=True),
    "ведмідь": dict(skull=(0.13, 0.13, 0.12), snout=(0.08, 0.07),
                    ears=("круглі", 0.05)),
    "дракон": dict(skull=(0.1, 0.13, 0.09), snout=(0.17, 0.05),
                   ears=None, horns=0.18, ridge=True),
}


def animal_head(kind, fur, s):
    p = base.part
    h = HEADS[kind]
    sx, sy, sz = h["skull"]
    length, thick = h["snout"]
    dark = solid("Ніс", (0.02, 0.02, 0.02), 0.4)
    eye = solid("Очі", s.get("eyes", (0.85, 0.65, 0.1)), 0.3,
                glow=4.0 if "eyes" in s else 1.5)
    bone = solid("Кістка", (0.82, 0.78, 0.66), 0.5)
    parts = [
        p("sphere", "Head", tuple(C), (sx, sy, sz), fur),
        p("sphere", "Head", tuple(C + Vector((0, -sy - length * 0.4,
                                               -sz * 0.35))),
          (thick * 1.1, length * 0.65, thick), fur),
        p("sphere", "Head", tuple(C + Vector((0, -sy - length * 0.95,
                                               -sz * 0.25))),
          (thick * 0.45, thick * 0.3, thick * 0.35), dark),
        p("sphere", "Head", tuple(C + Vector((0, -sy - length * 0.3,
                                               -sz * 0.75))),
          (thick * 0.9, length * 0.55, thick * 0.4), fur),
    ]
    # Шия під звіриною головою: людську голову вирізано, і без цього
    # між головою й плечима видно діру (перша збірка вовкулаки).
    parts.append(p("sphere", "neck_01", (0, 0.02, 1.55),
                   (sx * 0.8, sy * 0.75, 0.1), fur))
    for sign in (1, -1):
        parts.append(p("sphere", "Head",
                       tuple(C + Vector((sign * sx * 0.5, -sy * 0.8,
                                         sz * 0.25))),
                       (0.016, 0.01, 0.014), eye))
    if h.get("ears"):
        kind_e, size = h["ears"]
        for sign in (1, -1):
            at = C + Vector((sign * sx * 0.6, sy * 0.1, sz * 0.8))
            if kind_e == "круглі":
                parts.append(p("sphere", "Head", tuple(at),
                               (size, size * 0.4, size), fur))
            else:
                parts.append(p("cone", "Head",
                               tuple(at + Vector((0, 0, size * 0.4))),
                               (size * 0.5, size * 0.2, size * 0.6), fur))
    if h.get("tusks"):
        for sign in (1, -1):
            parts.append(p("cone", "Head",
                           tuple(C + Vector((sign * thick * 0.9,
                                             -sy - length * 0.6,
                                             -sz * 0.5))),
                           (0.012, 0.012, 0.05), bone,
                           (math.radians(-25), math.radians(sign * 20), 0)))
    horns = s.get("horns", h.get("horns", 0.0))
    if horns:
        for sign in (1, -1):
            parts.append(p("cone", "Head",
                           tuple(C + Vector((sign * sx * 0.6, sy * 0.5,
                                             sz * 0.6))),
                           (0.03, 0.03, horns * 0.5), bone,
                           (math.radians(55), math.radians(sign * 20), 0)))
    if h.get("ridge"):
        for i in range(5):
            parts.append(p("cone", "Head",
                           tuple(C + Vector((0, -sy * 0.3 + i * 0.05,
                                             sz * 0.9 - i * 0.02))),
                           (0.012, 0.02, 0.04), bone,
                           (math.radians(30), 0, 0)))
    if h.get("mane"):
        parts.append(p("sphere", "neck_01", (0, 0.07, 1.55),
                       (0.1, 0.07, 0.12), fur))
    return parts


# --- додатки -------------------------------------------------------------

def tail(kind, length, fur):
    p = base.part
    out = []
    # Сім сегментів, що налягають: п'ять розрізнених читались як диски
    # (перший огляд).
    steps = 7
    for i in range(steps):
        t = (i + 0.5) / steps
        at = (0, 0.1 + length * 0.9 * t, 0.95 - length * 0.55 * t)
        if kind == "тонкий":
            r = 0.022 * (1 - t * 0.6)
        elif kind == "товстий":
            r = 0.09 * (1 - t * 0.75)
        else:
            r = 0.05 + 0.04 * math.sin(t * math.pi)
        out.append(p("sphere", "pelvis", at,
                     (r, length / steps * 1.5, r), fur,
                     (math.radians(-30), 0, 0)))
    return out


def claws():
    p = base.part
    bone = solid("Кігті", (0.9, 0.87, 0.8), 0.4)
    out = []
    for sign, hand in ((1, "hand_l"), (-1, "hand_r")):
        for i in range(3):
            out.append(p("cone", hand,
                         (sign * 0.83, 0.03 + i * 0.025, 1.43),
                         (0.008, 0.008, 0.035), bone,
                         (0, math.radians(sign * 90), 0)))
    return out


def fangs():
    p = base.part
    bone = solid("Ікла", (0.95, 0.93, 0.88), 0.3)
    return [p("cone", "Head", (sign * 0.018, -0.1, 1.595),
              (0.005, 0.005, 0.014), bone, (math.radians(180), 0, 0))
            for sign in (1, -1)]


def wings(span, mat):
    """Крила-перетинки на спині (нерухомі): сплющений конус — трикутна
    перетинка вбік і вгору, з кісткою по верхньому краю. Сплющені
    еліпсоїди читались як чорні парасольки (перший огляд)."""
    p = base.part
    out = []
    for sign in (1, -1):
        bpy.ops.mesh.primitive_cone_add(vertices=3, radius1=span * 0.45,
                                        depth=span)
        obj = bpy.context.active_object
        obj.scale = (1.0, 0.04, 1.0)
        obj.rotation_euler = (0, math.radians(sign * -60), 0)
        obj.location = (sign * span * 0.42, 0.18, 1.62)
        bpy.ops.object.transform_apply(location=True, rotation=True,
                                       scale=True)
        group = obj.vertex_groups.new(name="spine_03")
        group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
        obj.data.materials.append(mat)
        obj.name = "Крило"
        out.append(obj)
        out.append(p("cyl", "spine_03", (sign * span * 0.42, 0.17, 1.8),
                     (0.025, 0.025, span * 0.5), mat,
                     (0, math.radians(sign * 60), 0)))
    return out


def crown():
    p = base.part
    gold = solid("Корона", (0.85, 0.65, 0.15), 0.3)
    out = [p("cyl", "Head", (0, 0.0, 1.75), (0.1, 0.1, 0.02), gold)]
    for i in range(6):
        a = i * math.tau / 6
        out.append(p("cone", "Head", (math.sin(a) * 0.09, math.cos(a) * 0.09,
                                      1.79), (0.015, 0.015, 0.035), gold))
    return out


# --- зброя ----------------------------------------------------------------

# Руки в Т-позі: права долоня ~(−0,74; 0,065; 1,44). Лезо — уперед (−Y) і
# трохи вгору, як тримають у Sword_Attack.
GRIP_R = Vector((-0.74, 0.06, 1.44))
GRIP_L = Vector((0.74, 0.06, 1.44))


def blade_obj(name, at, size, rot, mat, bone="hand_r", kind="cube"):
    if kind == "cube":
        bpy.ops.mesh.primitive_cube_add(size=1.0)
    elif kind == "cyl":
        bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=0.5,
                                            depth=1.0)
    elif kind == "cone":
        bpy.ops.mesh.primitive_cone_add(vertices=10, radius1=0.5,
                                        depth=1.0)
    else:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8,
                                             radius=0.5)
    obj = bpy.context.active_object
    obj.name = "Зброя-" + name
    obj.scale = size
    obj.rotation_euler = rot
    obj.location = at
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    obj.data.materials.append(mat)
    return obj


# Куди в Т-позі дивиться лезо з кулака правої руки — підібрано рендером
# у Sword_Idle і Sword_Attack.
BLADE_AXIS = Vector((0, -1, 0))


def weapon(kind):
    steel = solid("Сталь", (0.62, 0.64, 0.68), 0.35)
    wood = solid("Держак", (0.3, 0.2, 0.11), 0.8)
    glow = solid("Самоцвіт", (0.3, 0.8, 1.0), 0.2, glow=5.0)
    fwd = BLADE_AXIS
    g = GRIP_R
    x90 = (math.radians(90), 0, 0)
    out = []

    def along(length, offset=0.0):
        """Точка на осі зброї: вперед від кулака."""
        return g + fwd * (offset + length * 0.5)

    if kind in ("меч", "рапіра"):
        wide = 0.05 if kind == "меч" else 0.018
        long = 0.85 if kind == "меч" else 0.95
        out.append(blade_obj("лезо", along(long, 0.08), (wide, long, 0.012),
                             (0, 0, 0), steel))
        out.append(blade_obj("гарда", g + fwd * 0.07, (0.18, 0.03, 0.03),
                             (0, 0, 0), steel))
        out.append(blade_obj("руків'я", g + fwd * 0.0, (0.03, 0.03, 0.14),
                             x90, wood, kind="cyl"))
    elif kind == "кинджали":
        for grip, hand in ((GRIP_R, "hand_r"), (GRIP_L, "hand_l")):
            out.append(blade_obj("кинджал", grip + fwd * 0.2,
                                 (0.03, 0.28, 0.01), (0, 0, 0), steel, hand))
    elif kind in ("сокира", "дворучна сокира", "молот", "алебарда", "спис",
                  "посох"):
        long = {"сокира": 0.8, "дворучна сокира": 1.3, "молот": 0.9,
                "алебарда": 2.0, "спис": 1.9, "посох": 1.7}[kind]
        out.append(blade_obj("держак", along(long, -long * 0.25),
                             (0.035, 0.035, long), x90, wood, kind="cyl"))
        tip = g + fwd * (long * 0.75)
        if kind in ("сокира", "дворучна сокира", "алебарда"):
            big = 0.35 if kind == "дворучна сокира" else 0.22
            out.append(blade_obj("лезо", tip + Vector((0, 0, big * 0.4)),
                                 (0.02, big * 0.6, big), (0, 0, 0), steel))
            if kind != "сокира":
                out.append(blade_obj("лезо2", tip - Vector((0, 0, big * 0.4)),
                                     (0.02, big * 0.6, big), (0, 0, 0),
                                     steel))
        if kind == "молот":
            out.append(blade_obj("било", tip, (0.28, 0.16, 0.16), (0, 0, 0),
                                 steel))
        if kind in ("спис", "алебарда"):
            out.append(blade_obj("вістря", tip + fwd * 0.18,
                                 (0.06, 0.06, 0.3), (math.radians(-90), 0, 0),
                                 steel, kind="cone"))
        if kind == "посох":
            out.append(blade_obj("самоцвіт", tip + fwd * 0.08,
                                 (0.1, 0.1, 0.1), (0, 0, 0), glow,
                                 kind="sphere"))
    elif kind == "лук":
        bow = solid("Лук", (0.35, 0.22, 0.1), 0.6)
        bpy.ops.mesh.primitive_torus_add(major_radius=0.55, minor_radius=0.02,
                                         location=tuple(GRIP_L))
        obj = bpy.context.active_object
        obj.name = "Зброя-лук"
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        half = [v for v in bm.verts if v.co.x < 0.15]
        bmesh.ops.delete(bm, geom=half, context="VERTS")
        bm.to_mesh(obj.data)
        bm.free()
        obj.rotation_euler = (math.radians(90), 0, math.radians(90))
        bpy.ops.object.transform_apply(rotation=True)
        group = obj.vertex_groups.new(name="hand_l")
        group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
        obj.data.materials.append(bow)
        out.append(obj)
    return out


def shield():
    wood = solid("Щит", (0.35, 0.24, 0.13), 0.7)
    rim = solid("Оковка", (0.5, 0.5, 0.52), 0.4)
    return [blade_obj("щит", (0.5, 0.0, 1.45), (0.5, 0.5, 0.05),
                      (math.radians(90), 0, 0), wood, "lowerarm_l", "cyl"),
            blade_obj("умбон", (0.5, -0.04, 1.45), (0.12, 0.12, 0.08),
                      (0, 0, 0), rim, "lowerarm_l", "sphere")]


# --- рухи -----------------------------------------------------------------

def moves(rig, which):
    """Взяти з бібліотеки людини чотири рухи й назвати так, як їх шукає
    гра для монстрів. Решта рухів бібліотеки — геть."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=UAL)
    for obj in set(bpy.data.objects) - before:
        bpy.data.objects.remove(obj, do_unlink=True)
    idle, walk, attack = MOVES[which]
    wanted = {"Idle": idle, "Walk": walk, "Attack": attack,
              "Death": "Death01"}
    keep = {}
    for new, old in wanted.items():
        src = bpy.data.actions.get(old)
        if src is None:
            raise SystemExit("‼ у бібліотеці немає руху %s" % old)
        copy = src.copy()
        copy.name = new
        copy.use_fake_user = True
        keep[new] = copy
    for act in list(bpy.data.actions):
        if act.name not in keep:
            bpy.data.actions.remove(act)
    rig.animation_data_create()
    rig.animation_data.action = keep["Idle"]
    if keep["Idle"].slots:
        rig.animation_data.action_slot = keep["Idle"].slots[0]
    return keep


def previews(rig, folder, tag, keep):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 360
    scene.render.resolution_y = 480
    world = bpy.data.worlds.new("Небо")
    world.color = (0.45, 0.5, 0.55)
    scene.world = world
    sun = bpy.data.objects.new("Сонце", bpy.data.lights.new("Сонце", "SUN"))
    sun.rotation_euler = (math.radians(50), 0, math.radians(-30))
    sun.data.energy = 3.5
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("Камера", bpy.data.cameras.new("Камера"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.data.lens = 40
    shots = [("Idle", 0.3, (2.2, -3.0, 1.2), (86, 0, 36)),
             ("Walk", 0.4, (2.2, -3.0, 1.2), (86, 0, 36)),
             ("Attack", 0.45, (3.4, -0.4, 1.1), (88, 0, 83)),
             ("Idle", 0.3, (0.6, -1.1, 1.7), (88, 0, 28))]
    for i, (name, t, at, rot) in enumerate(shots):
        act = keep[name]
        rig.animation_data.action = act
        if act.slots:
            rig.animation_data.action_slot = act.slots[0]
        frame = int(act.frame_range[0] + (act.frame_range[1]
                                          - act.frame_range[0]) * t)
        scene.frame_set(frame)
        cam.location = at
        cam.rotation_euler = [math.radians(a) for a in rot]
        scene.render.filepath = os.path.join(folder, "%s-%d-%s.png"
                                             % (tag, i, name))
        bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)
    bpy.data.objects.remove(sun)
    rig.animation_data.action = keep["Idle"]


# Кістки скелета, уздовж яких ставиться кістка з фігур (товщина, м).
LIMBS = {"upperarm_l": 0.024, "upperarm_r": 0.024, "lowerarm_l": 0.019,
         "lowerarm_r": 0.019, "thigh_l": 0.03, "thigh_r": 0.03,
         "calf_l": 0.024, "calf_r": 0.024, "clavicle_l": 0.014,
         "clavicle_r": 0.014, "neck_01": 0.02, "spine_01": 0.022,
         "spine_02": 0.022, "spine_03": 0.022, "foot_l": 0.02,
         "foot_r": 0.02, "hand_l": 0.02, "hand_r": 0.02}


def bone_body(rig, eyes_rgb):
    """Кістяк: тіло людини геть, кістки з фігур на кістках скелета —
    рухи людини лягають так само."""
    for obj in list(bpy.data.objects):
        if obj.type == "MESH":
            bpy.data.objects.remove(obj)
    ivory = solid("Кістка", (0.86, 0.82, 0.7), 0.6)
    dark = solid("Очниці", (0.02, 0.02, 0.02), 0.9)
    glow = solid("Вогник", eyes_rgb, 0.3, glow=6.0)
    p = base.part
    mw = rig.matrix_world
    made = []
    for name, r in LIMBS.items():
        b = rig.data.bones[name]
        a, t = mw @ b.head_local, mw @ b.tail_local
        made.append(bar(a, t, r, ivory, name))
        made.append(p("sphere", name, tuple(a), (r * 1.3,) * 3, ivory))
    head = mw @ rig.data.bones["Head"].head_local
    c = head + Vector((0, -0.01, 0.07))
    made += [p("sphere", "Head", tuple(c), (0.085, 0.1, 0.1), ivory),
             p("sphere", "Head", tuple(c + Vector((0, -0.05, -0.08))),
               (0.06, 0.05, 0.035), ivory)]
    for sign in (1, -1):
        made.append(p("sphere", "Head",
                      tuple(c + Vector((sign * 0.035, -0.08, 0.0))),
                      (0.024, 0.02, 0.022), dark))
        spark = p("sphere", "Head",
                  tuple(c + Vector((sign * 0.035, -0.092, 0.0))),
                  (0.009, 0.006, 0.009), glow)
        # «Eyes», як очі людини: по них проба бачить, куди дивиться череп.
        spark.name = "Eyes"
        made.append(spark)
    # Ребра — кільця на хребті, таз — сплющена куля.
    for i, z in enumerate((1.4, 1.34, 1.28, 1.22, 1.16)):
        bpy.ops.mesh.primitive_torus_add(major_radius=0.14 - i * 0.008,
                                         minor_radius=0.012,
                                         location=(0, 0.01, z))
        ring = bpy.context.active_object
        ring.scale = (1.0, 0.75, 1.0)
        bpy.ops.object.transform_apply(scale=True)
        group = ring.vertex_groups.new(name="spine_03" if z > 1.3
                                       else "spine_02")
        group.add(list(range(len(ring.data.vertices))), 1.0, "REPLACE")
        ring.data.materials.append(ivory)
        made.append(ring)
    made.append(p("sphere", "pelvis", (0, 0.03, 0.97), (0.15, 0.09, 0.07),
                  ivory))
    return made


def bar(a, b, radius, mat, bone):
    obj = blade_obj("кістка", (a + b) * 0.5, (radius * 2, radius * 2,
                                               (b - a).length),
                    (0, 0, 0), mat, bone, "cyl")
    obj.rotation_mode = "QUATERNION"
    return _aim(obj, a, b)


def _aim(obj, a, b):
    """Повернути вже застосований циліндр уздовж a→b (він стоїть по Z)."""
    q = (b - a).normalized().to_track_quat("Z", "Y")
    for v in obj.data.vertices:
        v.co = q @ (v.co - ((a + b) * 0.5)) + (a + b) * 0.5
    return obj


def build(name, shots=None):
    s = SPECIES[name]
    rig, body = races.load(s.get("sex", "чоловік"))
    if s.get("bones"):
        made = bone_body(rig, s.get("eyes", (0.4, 0.8, 1.0)))
        made += skeleton_outfit(s.get("outfit", []))
        if s.get("weapon"):
            made += weapon(s["weapon"])
        if s.get("shield"):
            made += shield()
        return finish(name, rig, made, s, shots)
    races.inflate(body, s.get("bulk", 0.0))
    fur = reskin(body, s["skin"], s.get("sex", "чоловік"))
    if s.get("naga"):
        drop_legs(body)
    made = outfit(body, s.get("outfit", []))
    if s.get("head"):
        drop_head(body)
        made += animal_head(s["head"], fur, s)
    if s.get("tail"):
        made += tail(s["tail"][0], s["tail"][1], fur)
    if s.get("naga"):
        made += snake_tail(*s["naga"])
    if s.get("claws"):
        made += claws()
    if s.get("fangs") and not s.get("head"):
        made += fangs()
    if s.get("wings"):
        made += wings(s["wings"], solid("Крила", (0.12, 0.08, 0.1), 0.7)
                      if "вампір" in name else fur)
    if s.get("crown"):
        made += crown()
    if s.get("weapon"):
        made += weapon(s["weapon"])
    if s.get("shield"):
        made += shield()
    return finish(name, rig, made, s, shots)


def skeleton_outfit(items):
    """Вбрання кістяка: тіла немає, тож не шкаралупа з тіла, а фігури."""
    p = base.part
    out = []
    for what, rgb in items:
        mat = solid("Вбрання-" + what, rgb)
        if what == "шолом-кістяка":
            out.append(p("sphere", "Head", (0, -0.005, 1.75),
                         (0.105, 0.12, 0.08), mat))
        elif what == "каптур-кістяка":
            out.append(p("sphere", "Head", (0, 0.02, 1.73),
                         (0.12, 0.13, 0.13), mat))
            out.append(cape(mat))
        elif what == "мантія-кістяка":
            out.append(skirt(mat))
            out.append(p("sphere", "spine_03", (0, 0.02, 1.3),
                         (0.18, 0.12, 0.2), mat))
    return out


def finish(name, rig, made, s, shots):
    races.attach(rig, made)
    keep = moves(rig, s.get("moves", "звір"))
    if shots:
        previews(rig, shots, name, keep)
    os.makedirs(OUT, exist_ok=True)
    out = os.path.join(OUT, name + ".gltf")
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLTF_SEPARATE",
                              export_yup=True, export_apply=False,
                              export_animations=True,
                              export_animation_mode="ACTIONS",
                              export_force_sampling=True, export_skins=True,
                              export_def_bones=False)
    print("[людиноподібні] %s → %s" % (name, out))


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if not args or args[0] == "--список":
        print("[людиноподібні] види: " + ", ".join(SPECIES))
        return
    build(args[0], args[1] if len(args) > 1 else None)


if __name__ == "__main__":
    main()
