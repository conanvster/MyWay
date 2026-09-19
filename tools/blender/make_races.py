"""Людина, ельф і орк обох статей — з однієї моделі людини, з одягом.

Замовник 19.09.2026: «маємо модель людини, але не маємо моделей ельфа
та орка — спробуй на базі моделі людини зробити ці моделі із рухами як
у людини, а також необхідно пропрацювати хоча б 1 комплект одягу для
всіх».

Чому з людини, а не з нуля: рухи людини (UAL1, 43 рухи) гра не
перецілює, а пересаджує (`skinned_model.gd:_borrow_player`) — працює це
лише тоді, коли скелет той самий, з тими самими назвами кісток і на тому
самому місці в дереві (`Armature/Skeleton3D`). Тому скелет тут не
чіпається взагалі, міняється тільки те, що на ньому:

  · орк — зелена шкіра, тіло «роздуте» на 1,2 см (масивніший), короткі
    загострені вуха, ікла з нижньої щелепи;
  · ельф — бліда шкіра, тіло стоншене на 0,4 см, довгі загострені вуха;
  · одяг (для всіх однаковий): сорочка з короткими рукавами, пасок,
    штани, чоботи. Кожна річ — копія шматка тіла, трохи відсунута
    назовні: вона має ті самі ваги кісток, що й шкіра під нею, тож
    згинається разом із тілом у будь-якому русі.

Вуха й ікла прив'язані до кістки голови. Вуха фарбуються самою шкірою:
усім їхнім вершинам дано UV тієї точки тіла, біля якої вони ростуть.

Запуск (з каталогу проєкту):
    blender --background --python tools/blender/make_races.py -- \\
        <раса: людина|ельф|орк> <стать: чоловік|жінка> <куди.gltf> \\
        [тека_для_картинок]
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector, kdtree

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PLAYER = os.path.join(ROOT, "game", "models", "player")
SKINS = os.path.join(ROOT, "art", "races", "textures")

SOURCE = {"чоловік": "Superhero_Male_FullBody.gltf",
          "жінка": "Superhero_Female_FullBody.gltf"}

# раса -> (роздути тіло на, м; довжина вуха, м; ікла)
RACES = {
    "людина": (0.0, 0.0, False),
    "ельф": (-0.004, 0.085, False),
    "орк": (0.012, 0.045, True),
}

# Одяг: річ -> (кістки, відступ від шкіри, колір, шорсткість, де).
# «де» — умова на точку (м, T-поза, перед — −Y): межі між речами
# проходять і по висоті (кістка таза спільна для сорочки, паска й
# штанів), і вздовж руки (рукавиця — від середини передпліччя).
# Колір тут — лише для картинок у Blender: у грі частину фарбує річ,
# яку вдягнули (`skinned_model.gd:wear`, `вигляд` у items.json).
FINGERS = {"%s_%02d_%s" % (f, n, s) for f in ("index", "middle", "pinky",
                                                "ring", "thumb")
           for n in (1, 2, 3, 4) for s in ("l", "r")} | \
    {"%s_04_leaf_%s" % (f, s) for f in ("index", "middle", "pinky", "ring",
                                         "thumb") for s in ("l", "r")}
CLOTHES = {
    "Сорочка": ({"spine_01", "spine_02", "spine_03", "clavicle_l",
                 "clavicle_r", "upperarm_l", "upperarm_r", "pelvis"},
                0.012, (0.52, 0.42, 0.28), 0.95, lambda p: p.z >= 0.97),
    "Пасок": ({"pelvis", "spine_01"}, 0.019, (0.1, 0.065, 0.04), 0.55,
              lambda p: 0.93 <= p.z <= 1.0),
    "Штани": ({"pelvis", "thigh_l", "thigh_r", "calf_l", "calf_r"},
              0.008, (0.22, 0.15, 0.09), 0.9, lambda p: 0.3 <= p.z <= 1.0),
    "Чоботи": ({"calf_l", "calf_r", "foot_l", "foot_r", "ball_l",
                "ball_r", "ball_leaf_l", "ball_leaf_r"}, 0.011,
               (0.09, 0.06, 0.04), 0.6, lambda p: p.z <= 0.34),
    "Рукавиці": ({"lowerarm_l", "lowerarm_r", "hand_l", "hand_r"} | FINGERS,
                 0.005, (0.3, 0.2, 0.12), 0.7, lambda p: abs(p.x) >= 0.6),
    # Шолом — верх і потилиця голови: лоб над бровами відкритий, обличчя
    # теж.
    "Шолом": ({"Head"}, 0.013, (0.35, 0.3, 0.25), 0.6,
              lambda p: p.z >= 1.715 or (p.y > 0.035 and p.z >= 1.6)),
}


def load(sex):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(PLAYER, SOURCE[sex]))
    # Форма кістки, яку імпорт кладе окремим об'єктом, — у гру не йде.
    for obj in list(bpy.data.objects):
        if obj.type == "MESH" and obj.parent is None:
            bpy.data.objects.remove(obj)
    rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    body = next(o for o in bpy.data.objects
                if o.type == "MESH" and "hero" in o.name.lower())
    return rig, body


def dominant(obj):
    """Вершина -> ім'я кістки з найбільшою вагою."""
    names = {g.index: g.name for g in obj.vertex_groups}
    out = {}
    for v in obj.data.vertices:
        if v.groups:
            g = max(v.groups, key=lambda x: x.weight)
            out[v.index] = names.get(g.group, "")
    return out


def inflate(obj, by):
    if by == 0.0:
        return
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * by
    bm.to_mesh(obj.data)
    bm.free()


def material(name, rgb, rough):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Specular IOR Level"].default_value = 0.2
    mat.diffuse_color = (*rgb, 1.0)
    return mat


def reskin(body, race, sex):
    if race == "людина":
        return
    path = os.path.join(SKINS, "шкіра-%s-%s.png" % (race, sex))
    image = bpy.data.images.load(path)
    for mat in body.data.materials:
        for node in mat.node_tree.nodes:
            if node.type == "TEX_IMAGE" and node.image and \
                    "Dark" in node.image.name:
                node.image = image


def clothes(body):
    """Одяг — копії шматків тіла з тими самими вагами кісток."""
    made = []
    bones = dominant(body)
    for name, (keep, gap, rgb, rough, inside) in CLOTHES.items():
        piece = body.copy()
        piece.data = body.data.copy()
        piece.name = "Одяг-" + name
        bpy.context.scene.collection.objects.link(piece)
        mw = body.matrix_world
        bm = bmesh.new()
        bm.from_mesh(piece.data)
        drop = [v for v in bm.verts
                if bones.get(v.index, "") not in keep
                or not inside(mw @ v.co)]
        bmesh.ops.delete(bm, geom=drop, context="VERTS")
        bm.normal_update()
        for v in bm.verts:
            v.co += v.normal * gap
        if name == "Чоботи":
            # Стопу замінить оболонка (`_boot_feet`) — тут лише халява.
            low = [v for v in bm.verts if (mw @ v.co).z < FOOT_TOP]
            bmesh.ops.delete(bm, geom=low, context="VERTS")
        bm.to_mesh(piece.data)
        bm.free()
        piece.data.materials.clear()
        piece.data.materials.append(material(name, rgb, rough))
        if name == "Чоботи":
            feet = _boot_feet(body, gap)
            bpy.ops.object.select_all(action="DESELECT")
            for obj in feet:
                obj.data.materials.append(piece.data.materials[0])
                obj.select_set(True)
            piece.select_set(True)
            bpy.context.view_layer.objects.active = piece
            bpy.ops.object.join()
        made.append(piece)
    return made


FOOT_TOP = 0.1


def _boot_feet(body, gap):
    """Стопа чобота — опукла оболонка довкола стопи (19.09.2026). Копія
    шкіри повторювала пальці, і здалеку нога виглядала босою; згладжена
    копія западала під шкіру. Оболонка гладка й гарантовано накриває
    стопу. Ваги кісток кожна її вершина бере в найближчої точки шкіри —
    тож чобіт згинається разом зі стопою."""
    skin = body.data
    mw = body.matrix_world
    tree = kdtree.KDTree(len(skin.vertices))
    for v in skin.vertices:
        tree.insert(v.co, v.index)
    tree.balance()
    names = {g.index: g.name for g in body.vertex_groups}
    made = []
    for sign in (1.0, -1.0):
        points = [v.co + v.normal * gap for v in skin.vertices
                  if (mw @ v.co).z < FOOT_TOP + 0.02 and v.co.x * sign > 0]
        bm = bmesh.new()
        for p in points:
            bm.verts.new(p)
        bmesh.ops.convex_hull(bm, input=bm.verts)
        loose = [v for v in bm.verts if not v.link_faces]
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
        mesh = bpy.data.meshes.new("Чобіт")
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new("Чобіт", mesh)
        bpy.context.scene.collection.objects.link(obj)
        groups = {}
        for v in mesh.vertices:
            _, at, _ = tree.find(v.co)
            for g in skin.vertices[at].groups:
                name = names[g.group]
                if name not in groups:
                    groups[name] = obj.vertex_groups.new(name=name)
                groups[name].add([v.index], g.weight, "REPLACE")
        for poly in mesh.polygons:
            poly.use_smooth = True
        made.append(obj)
    return made


def uv_of_nearest(body, point):
    """UV тієї точки тіла, що найближча до `point`."""
    mw = body.matrix_world
    best, dist = None, 1e9
    for v in body.data.vertices:
        d = ((mw @ v.co) - point).length
        if d < dist:
            best, dist = v.index, d
    uv = body.data.uv_layers.active.data
    for loop in body.data.loops:
        if loop.vertex_index == best:
            return uv[loop.index].uv.copy()
    return None


def spike(name, base, tip, radius, flat, head_group, uv=None, mat=None):
    """Конус від `base` до `tip`, приплюснутий (`flat` — товщина
    відносно ширини), увесь на кістці голови."""
    length = (tip - base).length
    bpy.ops.mesh.primitive_cone_add(vertices=10, radius1=radius,
                                    radius2=0.0, depth=length)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (1.0, flat, 1.0)
    direction = (tip - base).normalized()
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    obj.location = base + direction * (length * 0.5)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    group = obj.vertex_groups.new(name=head_group)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    if uv is not None:
        # Шар UV — з тим самим ім'ям, що в тіла: інакше при з'єднанні UV
        # вуха підуть в окремий шар, а в шарі тіла стануть нулями —
        # кутом текстури, тобто чорним (другий знімок орка).
        # У тіла людини шарів UV два, і текстуру шкіри малює не
        # обов'язково активний — тож заповнюємо всі з тими самими
        # іменами (третій знімок орка: вухо й далі чорне).
        # І не в ОДНУ точку: з однаковим UV у всіх вершин дотичні для
        # карти нормалей нульові, і освітлення дає чорне (заміряно на
        # вусі 19.09.2026). Власна розгортка конуса, стиснута до плями
        # 2×2 % довкола точки щоки, лишає колір тим самим.
        uv, layer_names = uv
        own = [loop.uv.copy() for loop in obj.data.uv_layers[0].data] \
            if obj.data.uv_layers else None
        while len(obj.data.uv_layers) < len(layer_names):
            obj.data.uv_layers.new()
        for layer, layer_name in zip(obj.data.uv_layers, layer_names):
            layer.name = layer_name
            for i, loop in enumerate(layer.data):
                spread = (own[i] - Vector((0.5, 0.5))) * 0.02 if own \
                    else Vector((0.0, 0.0))
                loop.uv = uv + spread
    if mat is not None:
        obj.data.materials.clear()
        obj.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return obj


def skin_colour(body, uv):
    """Колір шкіри з текстури тіла (уже перефарбованої під расу) у
    точці `uv`. Вуха мають свій простий матеріал цього кольору: спроби
    фарбувати їх самою текстурою давали чорне (19.09.2026)."""
    for node in body.data.materials[0].node_tree.nodes:
        # Текстуру шкіри знаходимо так само, як `reskin`: у набору вона
        # йде до кольору через проміжний вузол, тож за зв'язком не
        # знайти, а за назвою — так («Dark» у людини, «шкіра-» у раси).
        name = node.image.name if node.type == "TEX_IMAGE" and node.image \
            else ""
        if "Dark" in name or name.startswith("шкіра-"):
            img = node.image
            w, h = img.size
            px = img.pixels
            total = [0.0, 0.0, 0.0]
            n = 0
            for dx in range(-3, 4):
                for dy in range(-3, 4):
                    x = int(uv.x * w + dx) % w
                    y = int(uv.y * h + dy) % h
                    i = (y * w + x) * 4
                    for k in range(3):
                        total[k] += px[i + k]
                    n += 1
            # Пікселі — у sRGB, а колір матеріалу Blender чекає лінійним.
            return tuple(_linear(c / n) for c in total)
    print("[раси] ‼ текстуру шкіри не знайдено — вуха запасного кольору")
    return (0.3, 0.2, 0.12)


def _linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def ears_and_tusks(body, race):
    _, ear_len, tusks = RACES[race]
    mw = body.matrix_world
    bones = dominant(body)
    head = [mw @ v.co for v in body.data.vertices
            if bones.get(v.index) == "Head"]
    side = max(head, key=lambda p: p.x)
    nose = min(head, key=lambda p: p.y)
    # Колір вуха — зі щоки: біля самого вуха на розгортці шов, і звідти
    # бралась чорна точка (перший знімок орка 19.09.2026).
    cheek = Vector((side.x * 0.8, nose.y + 0.07, nose.z - 0.01))
    ear_mat = material("Вуха", skin_colour(body, uv_of_nearest(body, cheek)),
                       0.6)
    added = []
    if ear_len > 0.0:
        for sign in (1.0, -1.0):
            base = Vector((side.x * sign * 0.95, side.y - 0.008,
                           side.z - 0.005))
            # Вістря — угору, трохи назад і вбік, як на ельфійських
            # малюнках; в орка коротше й більше вбік.
            out = 0.55 if race == "орк" else 0.38
            aim = Vector((out * sign, 0.3, 0.85)).normalized()
            added.append(spike("Вухо", base, base + aim * ear_len, 0.026,
                               0.32, "Head", mat=ear_mat))
    if tusks:
        bone = material("Ікла", (0.86, 0.82, 0.68), 0.5)
        for sign in (1.0, -1.0):
            base = Vector((0.027 * sign, nose.y + 0.045, nose.z - 0.058))
            tip = base + Vector((0.006 * sign, -0.008, 0.03))
            added.append(spike("Ікло", base, tip, 0.008, 1.0, "Head",
                               mat=bone))
    if added:
        bpy.ops.object.select_all(action="DESELECT")
        for obj in added:
            obj.select_set(True)
        body.select_set(True)
        bpy.context.view_layer.objects.active = body
        bpy.ops.object.join()


def attach(rig, objs):
    for obj in objs:
        obj.parent = rig
        if not any(m.type == "ARMATURE" for m in obj.modifiers):
            mod = obj.modifiers.new("Armature", "ARMATURE")
            mod.object = rig


def previews(folder, tag):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 360
    scene.render.resolution_y = 540
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
    shots = {"весь": ((1.6, -3.2, 1.1), (88, 0, 26), 50),
             "голова": ((0.35, -0.75, 1.68), (90, 0, 25), 60)}
    for view, (at, rot, lens) in shots.items():
        cam.location = at
        cam.rotation_euler = [math.radians(a) for a in rot]
        cam.data.lens = lens
        scene.render.filepath = os.path.join(folder, "%s-%s.png" % (tag, view))
        bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)
    bpy.data.objects.remove(sun)


def export(out):
    """`.gltf` з текстурами ОКРЕМИМИ файлами поруч, не `.glb`: шість
    моделей ділять ті самі текстури людини, і в теці вони лежать одним
    файлом на всіх (з вбудованими — 179 МБ, бо Godot ще й витягує кожну
    копію в окрему картинку)."""
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLTF_SEPARATE",
                              export_yup=True, export_apply=False,
                              export_animations=False, export_skins=True,
                              export_def_bones=False)


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    race, sex, out = args[0], args[1], args[2]
    rig, body = load(sex)
    inflate(body, RACES[race][0])
    reskin(body, race, sex)
    made = clothes(body)
    ears_and_tusks(body, race)
    attach(rig, made)
    if len(args) > 3:
        previews(args[3], "%s-%s" % (race, sex))
    export(os.path.abspath(out))
    print("[раси] %s, %s → %s" % (race, sex, out))


if __name__ == "__main__":
    main()
