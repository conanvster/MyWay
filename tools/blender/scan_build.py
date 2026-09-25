"""Універсальний білдер шляху А: `вид` → .blend + .glb + аркуш кадрів +
звіт.json. Замість нового `make_<вид>_scan.py` на кожного звіра (до
24.09.2026 — 11 файлів по 200-400 рядків, ~70% копій).

    blender -b --python tools/blender/scan_build.py -- <вид> [--чернетка]

Що робить (розділ А6 методу, тепер без ручних кроків):
  1. сітка `art/monsters/<source>-3d/pixal3d-01.glb` (або `--сітка шлях`);
  2. орієнтація й нахил за лапами, що стоять (`scan_lib.level_by_inliers`);
  3. спрощення до `faces` профілю, текстури 2048, маска ворсу;
  4. кістки автоматично (`auto_bones_*`), `normalize_roll`, ваги;
  5. рухи (заєць / гуманоїд), корекція землі на ВСІХ ключових кадрах;
  6. аркуш: орто збоку/спереду з кістками + кадри рухів (`<тека>/аркуш/`);
  7. звіт.json: нахил, лапи, % голизни, ваги за відстанню, висота
     найнижчої вершини на кожному ключовому кадрі.

`--чернетка` — усе в `<тека>/чернетка/`, не чіпаючи art/monsters/<вид>.blend
і game/models/own/*.glb (розділ А6: «спершу — чернетка»).
"""
import json
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_template as base  # noqa: E402
import make_hare as hare  # noqa: E402
import scan_lib as L  # noqa: E402
import scan_profiles as P  # noqa: E402

ROOT = L.ROOT


def mob_look(name):
    mobs = json.load(open(os.path.join(ROOT, "game", "data", "mobs.json"), encoding="utf-8"))
    for v in mobs.values():
        if isinstance(v, dict) and v.get("назва") == name:
            return v.get("вигляд", {})
    raise SystemExit("‼ немає виду «%s» у mobs.json" % name)


def model_file(name, look):
    """Шлях А — плаский .glb (розділ 4а.5); у гуманоїдів у mobs.json ще
    шлях Б (humanoids/*.gltf) — фінальне ім'я все одно <вид>.glb."""
    m = look.get("модель", "")
    stem = os.path.splitext(os.path.basename(m))[0] if m.endswith(".glb") else name
    return stem


# ---------------------------------------------------------------- аркуш

def _bone_sticks(skeleton):
    mat = bpy.data.materials.new("Кістка")
    mat.diffuse_color = (1.0, 0.1, 0.6, 1.0)
    objs = []
    for b in skeleton.data.bones:
        h, t = skeleton.matrix_world @ b.head_local, skeleton.matrix_world @ b.tail_local
        d = t - h
        bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=0.006 * max(1, d.length * 4),
                                            depth=d.length, location=(h + t) / 2)
        o = bpy.context.active_object
        o.rotation_mode = "QUATERNION"
        o.rotation_quaternion = d.to_track_quat("Z", "Y")
        o.data.materials.append(mat)
        o.show_in_front = True
        objs.append(o)
    return objs


def sheet(mesh, skeleton, folder, actions):
    """Кадри з камерою під габарит звіра (не під зайця, як `previews`):
    орто збоку/спереду з кістками + по 2 кадри кожного руху в 3/4."""
    os.makedirs(folder, exist_ok=True)
    for old in os.listdir(folder):          # кадри попередньої збірки не змішувати
        if old.endswith(".png"):
            os.remove(os.path.join(folder, old))
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.resolution_x = sc.render.resolution_y = 512
    p = L.verts(mesh)
    lo, hi = p.min(0), p.max(0)
    c = Vector(((lo + hi) / 2).tolist())
    size = float(max(hi - lo))
    cam = bpy.data.objects.new("К", bpy.data.cameras.new("К"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    out = []

    def shot(fname, loc, ortho):
        cam.data.type = "ORTHO" if ortho else "PERSP"
        cam.data.ortho_scale = size * 1.15
        cam.data.lens = 40
        cam.location = loc
        cam.rotation_euler = (c - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(folder, fname)
        bpy.ops.render.render(write_still=True)
        out.append(fname)

    sticks = _bone_sticks(skeleton)
    sc.display.shading.color_type = "TEXTURE"
    sc.display.shading.show_xray = True
    sc.display.shading.xray_alpha = 0.55
    shot("00-кістки-збоку.png", (c.x + size * 2, c.y, c.z), True)
    shot("01-кістки-спереду.png", (c.x, c.y - size * 2, c.z), True)
    sc.display.shading.show_xray = False
    for o in sticks:
        bpy.data.objects.remove(o)
    i = 2
    d = size * 1.7
    for act, frames in actions:
        for fr in frames:
            skeleton.animation_data.action = bpy.data.actions[act]
            sc.frame_set(fr)
            shot("%02d-%s-%02d.png" % (i, act, fr), (c.x + d * 0.75, c.y - d * 0.75, c.z + size * 0.25), False)
            i += 1
    # Ті самі кадри збоку (ортографічно): згин суглобів видно лише так.
    for act, frames in actions:
        for fr in frames:
            skeleton.animation_data.action = bpy.data.actions[act]
            sc.frame_set(fr)
            shot("%02d-збоку-%s-%02d.png" % (i, act, fr), (c.x + size * 2, c.y, c.z), True)
            i += 1
    skeleton.animation_data.action = bpy.data.actions["Idle"]
    sc.frame_set(1)
    bpy.data.objects.remove(cam)
    return out


# ---------------------------------------------------------------- main

def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    name = argv[0]
    draft = "--чернетка" in argv
    cfg = P.config(name)
    if cfg["body"] == "legacy":
        raise SystemExit("‼ %s — тип «%s»: окремий білдер %s (ще не узагальнено)"
                         % (name, cfg["profile"], cfg.get("script")))
    look = mob_look(name)
    height = float(look.get("зріст", 1.0))
    stem = model_file(name, look)
    folder = os.path.join(ROOT, "art", "monsters", cfg["source"] + "-3d")
    src = argv[argv.index("--сітка") + 1] if "--сітка" in argv else os.path.join(folder, "pixal3d-01.glb")
    work = os.path.join(folder, "чернетка") if draft else folder
    os.makedirs(work, exist_ok=True)
    blend = os.path.join(work, stem + ".blend") if draft else os.path.join(ROOT, "art", "monsters", stem + ".blend")
    glb = os.path.join(work, stem + ".glb") if draft else os.path.join(ROOT, "game", "models", "own", stem + ".glb")

    base.clear()
    bpy.context.scene.render.fps = 24
    rep = {"вид": name, "профіль": cfg["profile"], "зріст": height, "сітка": os.path.relpath(src, ROOT)}
    mesh = L.load_mesh(src)
    if cfg["body"] == "quadruped":
        L.orient_quadruped(mesh, height)
        rep["нахил"] = L.level_by_inliers(mesh, height)
    else:
        L.orient_humanoid(mesh, height, cfg.get("yaw", 0.0))
    # Кістки — на ПОВНІЙ сітці: після спрощення в тонкому шарі ноги
    # лишається 0-6 вершин, і пошук лап/нахилу ніг стає випадковим.
    if cfg["body"] == "quadruped":
        feet = {k: tuple(v) for k, v in rep["нахил"]["лапи"].items()}
        bones = L.auto_bones_quadruped(mesh, height, feet, cfg)
    else:
        bones = L.auto_bones_humanoid(mesh, height, cfg)
    rep["кістки"] = bones
    L.simplify(mesh, cfg["faces"], cfg.get("weld_after", False))
    L.shrink_textures(mesh)
    rep["голих_частка"] = round(L.fur_mask(mesh, cfg["fur_rule"]), 3)
    mesh.name = "Тіло"
    skeleton, fixed = L.rig(mesh, bones)
    rep["ваги_за_відстанню"] = fixed
    for bone, a, b, r in cfg.get("rigid", []):
        rep.setdefault("жорстка_зброя", {})[bone] = L.rigid(mesh, bone, a, b, r)
        say_n = rep["жорстка_зброя"][bone]
        print("[скан] жорстка зброя на %s: %d вершин" % (bone, say_n))
    for bone in sorted({r[0] for r in cfg.get("rigid", [])}):
        n = L.cut_rigid(mesh, skeleton, bone)
        rep.setdefault("відрізано_граней", {})[bone] = n
        print("[скан] зброю на %s відрізано: %d граней" % (bone, n))
    if cfg["body"] == "quadruped" and cfg.get("joints", True):
        L.quadruped_actions(skeleton, cfg.get("ears", True))
        grounded = L.QUAD_GROUNDED
        frames = [("Idle", [1]), ("Walk", [7, 19]), ("Attack", [5, 10, 13]), ("Death", [30])]
    elif cfg["body"] == "quadruped":
        hare.actions(skeleton)
        grounded = L.HARE_GROUNDED
        frames = [("Idle", [1]), ("Walk", [5, 9]), ("Attack", [9, 16]), ("Death", [30])]
    else:
        L.humanoid_actions(skeleton)
        grounded = L.HUMANOID_GROUNDED
        frames = [("Idle", [1]), ("Walk", [1, 13]), ("Attack", [6, 10, 14]), ("Death", [12, 24])]
    rep["земля"] = L.fix_ground(mesh, skeleton, grounded)
    rep["аркуш"] = [os.path.join(os.path.relpath(work, ROOT), "аркуш", f)
                    for f in sheet(mesh, skeleton, os.path.join(work, "аркуш"), frames)]
    bpy.ops.wm.save_as_mainfile(filepath=blend)
    L.export(glb)
    rep["blend"] = os.path.relpath(blend, ROOT)
    rep["glb"] = os.path.relpath(glb, ROOT)
    rep["glb_МБ"] = round(os.path.getsize(glb) / 1e6, 1)
    with open(os.path.join(work, "звіт.json"), "w", encoding="utf-8") as fh:
        json.dump(rep, fh, ensure_ascii=False, indent=1)
    L.log("готово: %s (%.1f МБ), звіт %s" % (rep["glb"], rep["glb_МБ"], os.path.join(work, "звіт.json")))


if __name__ == "__main__":
    main()
