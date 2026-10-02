"""Генератор дерев (П-253): випадковий тип, випадкова крона, справжня кора й
листя.

Слово замовника 01.10.2026: «генератор дерев, який на базі реальних гілок
та листя буде збирати рандомні типи дерев із рандомною кроною»; П-253 —
«безкоштовні скани й фото, скрипт Blender».

    blender -b --factory-startup -P tools/blender/derevo.py -- \\
        --seed 7 --тип листяне --кора <diff.jpg> --нормаль <nor.jpg> \\
        --листя <кластери.png> --вихід <тека> [--рендер]

Що робить:
  1. Скелет. Стовбур — ламана з випадковим вигином і звуженням; від нього
     гілки 1-го рівня спіраллю (золотий кут), від них 2-го й 3-го. Довжину
     гілки 1-го рівня задає ФОРМА КРОНИ на тій висоті (куля, яйце,
     парасоля, колона, конус) — так крона виходить формою, а не
     випадковою шапкою.
  2. Кора. Кожна гілка — трубка зі звуженням, UV по колу й довжині, кора
     скану (Poly Haven, CC0) з нормаллю.
  3. Листя. Кінці гілок 2-3 рівня обсаджуються картками-кластерами
     (`tools/derevo_lystia.py` — справжні листки ambientCG, CC0). Нормалі
     карток — від центру крони назовні (як П-181): інакше крона пласка.
  4. Вихід: `<тека>/derevo.glb` (Godot) і, з `--рендер`, `<тека>/kadr.png`.
     Числа (висота, гілки, трикутники) — у `<тека>/derevo.json`.
"""
import json
import math
import os
import random
import sys

import bpy
import bmesh
from mathutils import Vector, Matrix

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def arg(name, default=None):
    return ARGS[ARGS.index(name) + 1] if name in ARGS else default


SEED = int(arg("--seed", "1"))
TYP = arg("--тип", "листяне")
KORA = arg("--кора")
NORMAL = arg("--нормаль")
LYSTIA = arg("--листя")
VYKHID = arg("--вихід", "/tmp/derevo")
RENDER = "--рендер" in ARGS
rng = random.Random(SEED)
GOLD = math.pi * (3 - math.sqrt(5))

# ── параметри типу: діапазони, з яких кидається конкретне дерево ─────────
if TYP == "хвойне":
    P = dict(vysota=(12, 22), stovbur_r=(0.11, 0.18), krona_vid=(0.12, 0.3),
             formy=["конус", "колона"], hilok1=(28, 44), kut1=(70, 100),
             riven=2, hilok2=(4, 7), kut2=(35, 60), opad=0.12,
             lystia_mira=(0.9, 1.4), lystia_na_kinci=(2, 4))
else:
    P = dict(vysota=(7, 14), stovbur_r=(0.16, 0.34), krona_vid=(0.25, 0.5),
             formy=["куля", "яйце", "парасоля", "колона"],
             hilok1=(9, 16), kut1=(35, 70), riven=3, hilok2=(3, 6),
             kut2=(30, 60), opad=0.08, lystia_mira=(1.1, 1.7),
             lystia_na_kinci=(3, 6))


def kyn(pair):
    return rng.uniform(*pair)


H = kyn(P["vysota"])
R0 = kyn(P["stovbur_r"]) * H / 10.0
KRONA_VID = kyn(P["krona_vid"]) * H
FORMA = rng.choice(P["formy"])
SHYR = H * rng.uniform(0.28, 0.45) if FORMA != "колона" else \
    H * rng.uniform(0.16, 0.24)
if FORMA == "парасоля":
    SHYR = H * rng.uniform(0.45, 0.6)


def krona_r(y):
    """Радіус крони на висоті y — сама форма крони."""
    if y < KRONA_VID or y > H:
        return 0.0
    t = (y - KRONA_VID) / max(0.01, H - KRONA_VID)   # 0 низ крони, 1 верх
    if FORMA == "куля":
        f = math.sin(math.pi * t)
    elif FORMA == "яйце":
        f = math.sin(math.pi * t ** 0.75) * (1.0 - 0.25 * t)
    elif FORMA == "парасоля":
        f = math.sin(math.pi * min(1.0, t ** 2.2 * 1.05))
    elif FORMA == "колона":
        f = min(1.0, math.sin(math.pi * t) * 1.8)
    else:  # конус
        f = (1.0 - t) ** 0.9
    return SHYR * max(0.05, f)


# ── скелет ────────────────────────────────────────────────────────────
class Hilka:
    def __init__(self, tochky, r0, r1, riven):
        self.tochky, self.r0, self.r1, self.riven = tochky, r0, r1, riven


HILKY = []


def lamana(pochatok, napr, dovzhyna, segm, vyhyn, vgoru):
    tochky = [pochatok.copy()]
    p, d = pochatok.copy(), napr.normalized()
    krok = dovzhyna / segm
    for _ in range(segm):
        d = (d + Vector((rng.uniform(-vyhyn, vyhyn),
                         rng.uniform(-vyhyn, vyhyn),
                         rng.uniform(-vyhyn, vyhyn) + vgoru))).normalized()
        p = p + d * krok
        tochky.append(p.copy())
    return tochky


def tochka_na(tochky, t):
    i = min(len(tochky) - 2, int(t * (len(tochky) - 1)))
    f = t * (len(tochky) - 1) - i
    return tochky[i].lerp(tochky[i + 1], f), \
        (tochky[i + 1] - tochky[i]).normalized()


def obertaty(v, vis, kut):
    return Matrix.Rotation(kut, 3, vis) @ v


def perpendykuliar(d, azymut):
    bazа = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
    x = d.cross(bazа).normalized()
    return obertaty(x, d, azymut)


def vyrostyty():
    stovbur = lamana(Vector((0, 0, 0)), Vector((0, 0, 1)), H, 10, 0.05,
                     0.06)
    HILKY.append(Hilka(stovbur, R0, R0 * 0.08, 0))
    n1 = rng.randint(*P["hilok1"])
    for i in range(n1):
        t = (KRONA_VID / H) + (1 - KRONA_VID / H) * (i + rng.random()) / n1
        t = min(0.97, t)
        pos, d = tochka_na(stovbur, t)
        kraj = krona_r(pos.z)
        if kraj <= 0.1:
            continue
        kut = math.radians(kyn(P["kut1"]))
        bik = perpendykuliar(d, i * GOLD + rng.uniform(-0.3, 0.3))
        napr = (d * math.cos(kut) + bik * math.sin(kut)).normalized()
        napr.z -= P["opad"]
        dov = kraj / max(0.3, math.sin(kut)) * rng.uniform(0.85, 1.1)
        r = R0 * (1 - t) * rng.uniform(0.45, 0.65) + 0.02
        hilka = lamana(pos, napr, dov, 5, 0.12, 0.05 - P["opad"] * 0.3)
        HILKY.append(Hilka(hilka, r, r * 0.15, 1))
        dity(hilka, dov, r, 2)


def dity(batko, dov_batka, r_batka, riven):
    if riven > P["riven"]:
        return
    n = rng.randint(*P["hilok2"])
    for j in range(n):
        t = 0.3 + 0.65 * (j + rng.random()) / n
        pos, d = tochka_na(batko, t)
        kut = math.radians(kyn(P["kut2"]))
        bik = perpendykuliar(d, j * GOLD * 1.7 + rng.uniform(-0.5, 0.5))
        napr = (d * math.cos(kut) + bik * math.sin(kut)).normalized()
        dov = dov_batka * rng.uniform(0.3, 0.5) * (1 - t * 0.4)
        r = r_batka * rng.uniform(0.35, 0.55)
        hilka = lamana(pos, napr, dov, 3, 0.18, 0.04)
        HILKY.append(Hilka(hilka, r, r * 0.3, riven))
        dity(hilka, dov, r, riven + 1)


# ── сітки ─────────────────────────────────────────────────────────────
def trubky():
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    for h in HILKY:
        bokiv = {0: 10, 1: 7, 2: 5}.get(h.riven, 4)
        kilcia = []
        n = len(h.tochky)
        dov = 0.0
        for i, p in enumerate(h.tochky):
            if i:
                dov += (p - h.tochky[i - 1]).length
            d = (h.tochky[min(i + 1, n - 1)] - h.tochky[max(i - 1, 0)]) \
                .normalized()
            r = h.r0 + (h.r1 - h.r0) * (i / (n - 1))
            # Корені: низ стовбура ширший.
            if h.riven == 0 and i == 0:
                r *= 1.35
            x = perpendykuliar(d, 0.0)
            kilce = []
            for k in range(bokiv + 1):
                v = obertaty(x, d, 2 * math.pi * k / bokiv) * r + p
                kilce.append((bm.verts.new(v), k / bokiv, dov))
            kilcia.append(kilce)
        obvid = 2 * math.pi * max(h.r0, 0.05)
        for a, b in zip(kilcia, kilcia[1:]):
            for k in range(bokiv):
                f = bm.faces.new((a[k][0], a[k + 1][0], b[k + 1][0],
                                  b[k][0]))
                for loop, (u, vv) in zip(f.loops, (
                        (a[k][1], a[k][2]), (a[k + 1][1], a[k + 1][2]),
                        (b[k + 1][1], b[k + 1][2]), (b[k][1], b[k][2]))):
                    # Кора не розтягується: по довжині — стільки ж
                    # повторів, скільки по колу.
                    loop[uv].uv = (u * max(1.0, obvid), vv)
    me = bpy.data.meshes.new("кора")
    bm.to_mesh(me)
    bm.free()
    return me


def lystia():
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    tsentr = Vector((0, 0, KRONA_VID + (H - KRONA_VID) * 0.55))
    normali = []
    kartok = 0
    for h in HILKY:
        if h.riven < (1 if TYP == "хвойне" else 2):
            continue
        # Хвоя — по всій гілці (ялина не голе віття), листя — до кінців.
        if TYP == "хвойне":
            mistsia = (0.25, 0.45, 0.65, 0.85, 1.0)
        elif h.riven >= 3:
            mistsia = (0.7, 1.0)
        else:
            mistsia = (0.55, 0.8, 1.0)
        for t in mistsia:
            pos, d = tochka_na(h.tochky, min(t, 0.999))
            for _ in range(rng.randint(*P["lystia_na_kinci"]) // 2 + 1):
                mira = kyn(P["lystia_mira"]) * (0.8 if h.riven >= 3 else 1)
                # Картка росте з гілки вбік і трохи вниз, повернута
                # випадково навколо гілки.
                vbik = perpendykuliar(d, rng.uniform(0, 2 * math.pi))
                vgoru = (d * 0.6 + vbik * 0.6 + Vector((0, 0, -0.15))) \
                    .normalized()
                shyr = vgoru.cross(vbik).normalized()
                klitynka = rng.randrange(4)
                u0, v0 = (klitynka % 2) * 0.5, (1 - klitynka // 2) * 0.5
                kuty = [pos - shyr * mira * 0.5,
                        pos + shyr * mira * 0.5,
                        pos + shyr * mira * 0.5 + vgoru * mira,
                        pos - shyr * mira * 0.5 + vgoru * mira]
                verts = [bm.verts.new(c) for c in kuty]
                f = bm.faces.new(verts)
                for loop, (u, vv) in zip(f.loops, ((0, 0), (1, 0), (1, 1),
                                                   (0, 1))):
                    loop[uv].uv = (u0 + u * 0.5, v0 + vv * 0.5)
                n = (pos + vgoru * mira * 0.5 - tsentr)
                n = (n.normalized() + Vector((0, 0, 0.3))).normalized()
                normali.extend([n] * 4)
                kartok += 1
    me = bpy.data.meshes.new("листя")
    bm.to_mesh(me)
    bm.free()
    me.normals_split_custom_set([normali[l.vertex_index] for l in me.loops])
    return me, kartok


# ── матеріали ─────────────────────────────────────────────────────────
def kartynka(path):
    return bpy.data.images.load(os.path.abspath(path)) if path else None


def material_kory():
    m = bpy.data.materials.new("кора")
    m.use_nodes = True
    n = m.node_tree.nodes
    bsdf = n["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.9
    if KORA:
        t = n.new("ShaderNodeTexImage")
        t.image = kartynka(KORA)
        m.node_tree.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
    if NORMAL:
        t = n.new("ShaderNodeTexImage")
        t.image = kartynka(NORMAL)
        t.image.colorspace_settings.name = "Non-Color"
        nm = n.new("ShaderNodeNormalMap")
        m.node_tree.links.new(t.outputs["Color"], nm.inputs["Color"])
        m.node_tree.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    return m


def material_lystia():
    m = bpy.data.materials.new("листя")
    m.use_nodes = True
    n = m.node_tree.nodes
    bsdf = n["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.7
    t = n.new("ShaderNodeTexImage")
    t.image = kartynka(LYSTIA)
    m.node_tree.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
    m.node_tree.links.new(t.outputs["Alpha"], bsdf.inputs["Alpha"])
    # glTF: alpha clip → у Godot ALPHA_SCISSOR, двобічне.
    m.blend_method = "CLIP" if hasattr(m, "blend_method") else None
    m.use_backface_culling = False
    try:
        m.surface_render_method = "DITHERED"
    except AttributeError:
        pass
    return m


# ── збірка ────────────────────────────────────────────────────────────
def zibraty():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    vyrostyty()
    kora = bpy.data.objects.new("кора", trubky())
    kora.data.materials.append(material_kory())
    me, kartok = lystia()
    lyst = bpy.data.objects.new("листя", me)
    lyst.data.materials.append(material_lystia())
    derevo = bpy.data.objects.new("дерево", None)
    for o in (kora, lyst):
        bpy.context.scene.collection.objects.link(o)
        o.parent = derevo
    bpy.context.scene.collection.objects.link(derevo)
    os.makedirs(VYKHID, exist_ok=True)
    tri = sum(len(p.vertices) - 2 for o in (kora, lyst)
              for p in o.data.polygons)
    chysla = {"seed": SEED, "тип": TYP, "форма крони": FORMA,
              "висота": round(H, 2), "ширина крони": round(SHYR * 2, 2),
              "гілок": len(HILKY), "карток листя": kartok,
              "трикутників": tri, "кора": os.path.basename(KORA or ""),
              "листя": os.path.basename(LYSTIA or "")}
    bpy.ops.export_scene.gltf(filepath=os.path.join(VYKHID, "derevo.glb"),
                              export_format="GLB", export_yup=True)
    with open(os.path.join(VYKHID, "derevo.json"), "w") as f:
        json.dump(chysla, f, ensure_ascii=False, indent=1)
    print("[дерево]", json.dumps(chysla, ensure_ascii=False))
    if RENDER:
        rendeR(derevo)


def rendeR(derevo):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in \
        [e.identifier for e in bpy.types.RenderSettings.bl_rna
         .properties["engine"].enum_items] else "BLENDER_EEVEE"
    sc.render.resolution_x = sc.render.resolution_y = 768
    sc.render.film_transparent = False
    svit = bpy.data.worlds.new("небо")
    svit.use_nodes = True
    svit.node_tree.nodes["Background"].inputs["Color"].default_value = \
        (0.55, 0.62, 0.7, 1)
    svit.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
    sc.world = svit
    # Земля, щоб дерево стояло, а не висіло.
    bpy.ops.mesh.primitive_plane_add(size=60)
    zemlia = bpy.context.object
    mz = bpy.data.materials.new("земля")
    mz.use_nodes = True
    mz.node_tree.nodes["Principled BSDF"].inputs["Base Color"] \
        .default_value = (0.18, 0.2, 0.12, 1)
    zemlia.data.materials.append(mz)
    sontse = bpy.data.objects.new("сонце", bpy.data.lights.new("сонце",
                                                                "SUN"))
    sontse.data.energy = 3.5
    sontse.rotation_euler = (math.radians(50), 0, math.radians(35))
    sc.collection.objects.link(sontse)
    kam = bpy.data.objects.new("камера", bpy.data.cameras.new("камера"))
    sc.collection.objects.link(kam)
    sc.camera = kam
    # Кадр — за справжніми межами сітки: гілки 2-3 рівня виходять за
    # розрахункову крону, і за нею камера різала верх.
    tochky = [o.matrix_world @ v.co for o in derevo.children
              for v in o.data.vertices]
    lo = Vector((min(p.x for p in tochky), min(p.y for p in tochky), 0))
    hi = Vector((max(p.x for p in tochky), max(p.y for p in tochky),
                 max(p.z for p in tochky)))
    tsil = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, hi.z * 0.5))
    rozmir = max(hi.z, hi.x - lo.x, hi.y - lo.y) * 1.12
    # 50-мм об'єктив бачить ~39° — відстань, щоб розмір улазив у кадр.
    vidstan = rozmir / (2 * math.tan(math.radians(19.5)))
    kam.location = tsil + Vector((0.62, -0.78, 0.08)).normalized() * vidstan
    napr = tsil - Vector(kam.location)
    kam.rotation_euler = napr.to_track_quat("-Z", "Y").to_euler()
    kam.data.lens = 50
    sc.render.filepath = os.path.join(VYKHID, "kadr.png")
    bpy.ops.render.render(write_still=True)
    print("[кадр]", sc.render.filepath)


zibraty()
