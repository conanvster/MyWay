"""Пілот гібриду Б+Г (П-281, 07.11.2026): основа MPFB під кадр вікі.

Слово замовника: «роби гібрид Б+Г, почни з пілота». Пілот — людина-жінка,
варіант 1 (`wiki/img/rasy/людина-жінка-v1.png`). Тут частина Б: чиста
людина MPFB (CC0) зі скелетом `game_engine`, шкірою, очима, бровами, віями й
зачіскою окремими сітками; одяг — частина Г (хмарний генератор, окремо
кожна річ), поки не вдягнуто.

Рендер — Cycles на процесорі (GPU зайнятий стендом).

    blender -b -P tools/blender/pilot_b.py -- <тека> [--макро k=v,...]
        [--зачіска long01 | -] [--брови eyebrow010] [--шкіра young_caucasian_female]
        [--колір-волосся 0.2,0.12,0.07] [--без-рендеру]
"""
import functools
import math
import os
import sys

import bpy
from mathutils import Vector

from bl_ext.blender_org.mpfb.services.humanservice import HumanService
from bl_ext.blender_org.mpfb.services.locationservice import LocationService

print = functools.partial(print, flush=True)

ARGS = sys.argv[sys.argv.index("--") + 1:]


def opt(name, default):
    if name in ARGS:
        i = ARGS.index(name)
        v = ARGS[i + 1]
        del ARGS[i:i + 2]
        return v
    return default


def flag(name):
    if name in ARGS:
        ARGS.remove(name)
        return True
    return False


# Статура «під кадр»: молода, струнка, середнього зросту, довгі ноги.
MAKRO = {"gender": 0.0, "age": 0.5, "muscle": 0.5, "weight": 0.42,
         "proportions": 0.75, "height": 0.6, "cupsize": 0.5, "firmness": 0.6,
         "race": {"caucasian": 1.0, "african": 0.0, "asian": 0.0}}
for pair in opt("--макро", "").split(","):
    if "=" in pair:
        k, v = pair.split("=")
        MAKRO[k] = float(v)
ZACHISKA = opt("--зачіска", "long01")
BROVY = opt("--брови", "eyebrow010")
SHKIRA = opt("--шкіра", "young_caucasian_female")
KOLIR = [float(x) for x in opt("--колір-волосся", "0.16,0.09,0.05").split(",")]
BEZ_RENDERU = flag("--без-рендеру")
opt_tsili = opt("--риси", "")
KUDY = os.path.abspath(ARGS[0])
os.makedirs(KUDY, exist_ok=True)
DANI = LocationService.get_user_data()


def asset(*p):
    return os.path.join(DANI, *p)


def mhclo(group, name):
    d = asset(group, name)
    return os.path.join(d, next(f for f in os.listdir(d) if f.endswith(".mhclo")))


def build():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    h = HumanService.create_human(macro_detail_dict=MAKRO)
    HumanService.add_builtin_rig(h, "game_engine")
    for typ, grp, name in (("Eyes", "eyes", "high-poly"),
                           ("Eyelashes", "eyelashes", "eyelashes01"),
                           ("Eyebrows", "eyebrows", BROVY),
                           ("Hair", "hair", ZACHISKA)):
        if name == "-":       # без зачіски: основа під окреме волосся
            continue
        HumanService.add_mhclo_asset(mhclo(grp, name), h, asset_type=typ,
                                     material_type="MAKESKIN")
    # Риси обличчя під кадр: «ціль=вага,…» (імена — як у MPFB targets/).
    tsili = opt_tsili
    if tsili:
        from bl_ext.blender_org.mpfb.services.targetservice import \
            TargetService as TS
        for par in tsili.split(","):
            n, v = par.split("=")
            TS.load_target(h, TS.target_full_path(n), weight=float(v), name=n)
        h.data.update()
    HumanService.set_character_skin(
        asset("skins", SHKIRA, SHKIRA + ".mhmat"), h, skin_type="MAKESKIN")
    # Колір волосся — множником на текстуру зачіски (каштанове, як на кадрі).
    for o in bpy.data.objects:
        if o.type == "MESH" and ZACHISKA != "-" and ZACHISKA in o.name.lower():
            for m in o.data.materials:
                tint(m, KOLIR)
    return h


def tint(m, rgb):
    nt = m.node_tree
    b = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if b is None:
        return
    link = next(iter(b.inputs["Base Color"].links), None)
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    mix.inputs["B"].default_value = (rgb[0] * 4, rgb[1] * 4, rgb[2] * 4, 1)
    if link is not None:
        nt.links.new(link.from_socket, mix.inputs["A"])
    else:
        mix.inputs["A"].default_value = b.inputs["Base Color"].default_value
    nt.links.new(mix.outputs["Result"], b.inputs["Base Color"])


def scene_setup():
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 48
    sc.cycles.use_denoising = True
    sc.render.resolution_x = 640
    sc.render.resolution_y = 1024
    sc.render.film_transparent = False
    w = bpy.data.worlds.new("w") if not sc.world else sc.world
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.42, 0.44, 0.46, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.6
    for name, rot, energy in (("key", (55, 0, 35), 3.5),
                              ("fill", (65, 0, -60), 1.2),
                              ("rim", (70, 0, 170), 2.0)):
        ld = bpy.data.lights.new(name, "SUN")
        ld.energy = energy
        ld.angle = math.radians(8)
        lo = bpy.data.objects.new(name, ld)
        lo.rotation_euler = [math.radians(a) for a in rot]
        sc.collection.objects.link(lo)
    cd = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    return cam


def bounds():
    lo = Vector((1e9, 1e9, 1e9))
    hi = -lo
    for o in bpy.data.objects:
        if o.type != "MESH" or o.hide_render:
            continue
        for c in o.bound_box:
            p = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, p))
            hi = Vector(map(max, hi, p))
    return lo, hi


def shoot(cam, name, yaw, z_mid, dist, lens, target_h=None):
    a = math.radians(yaw)
    tgt = Vector((0, 0, z_mid))
    cam.location = tgt + Vector((math.sin(a) * dist, -math.cos(a) * dist, 0.05))
    d = tgt - cam.location
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = lens
    bpy.context.scene.render.filepath = os.path.join(KUDY, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("[пілот] знімок", name)


def main():
    h = build()
    lo, hi = bounds()
    print("[пілот] зріст %.3f м" % (hi.z - lo.z))
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(KUDY, "pilot.blend"))
    if BEZ_RENDERU:
        return
    cam = scene_setup()
    zh = hi.z - lo.z
    for name, yaw in (("перед", 0), ("три-чверті", 30), ("бік", 90), ("зад", 180)):
        shoot(cam, name, yaw, lo.z + zh * 0.5, 6.0, 36.0 * 6.0 / (zh * 1.12))
    # Обличчя зблизька.
    shoot(cam, "обличчя", 15, hi.z - 0.13, 1.2, 85)


if __name__ == "__main__":
    main()
