"""Рендер аватара для оцінки схожості з референсом (02.10.2026).

Спокій (T-поза скелета), ортокамера спереду, плоске світло Workbench —
лише колір текстури, як на референсі; тло прозоре.

    blender -b --factory-startup -P tools/blender/avatar_render.py -- \\
        <модель.gltf> <кадр.png> [перед|бік|зад]
"""
import math
import sys

import bpy
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:]
MODEL, KUDY = ARGS[0], ARGS[1]
T_POZA = "--т-поза" in ARGS
ARGS = [a for a in ARGS if a != "--т-поза"]
VYD = ARGS[2] if len(ARGS) > 2 else "перед"

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=MODEL)
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
# Модель із рухами: імпорт вішає першу дію на скелет, і вона перекривала
# позу оцінки (m30: 64,9% замість ~86%).
for _o in bpy.data.objects:
    _o.animation_data_clear()
for _pb in arm.pose.bones:
    _pb.matrix_basis.identity()
bpy.context.view_layer.update()
KUT, KUT_NIH, KUT_LIKTIA, STOPY = 90.0, 0.0, 0.0, 18.0
KLIUCH = KOLINO = PROFIL = 0.0
BIK_T = False
try:
    import json as _j
    _p = _j.load(open(MODEL + ".підбір.json"))
    KUT = float(_p.get("кут рук", 90.0))
    KUT_NIH = float(_p.get("кут ніг", 0.0))
    KUT_LIKTIA = float(_p.get("кут ліктя", 0.0))
    STOPY = float(_p.get("стопи", 18.0))
    KLIUCH = float(_p.get("ключиці", 0.0))
    KOLINO = float(_p.get("коліна", 0.0))
    PROFIL = float(_p.get("кут профілю", 0.0))
    BIK_T = float(_p.get("бік у T-позі", 0.0)) > 0.5
except Exception:
    pass
if T_POZA:
    # Та сама постановка, що й при підборі та проєкції (`mpfb_pidbir`).
    import os as _os
    sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
    import mpfb_pidbir as _P
    _P.KUT_NIH[0] = KUT_NIH
    _P.KUT_LIKTIA[0] = KUT_LIKTIA
    _P.STOPY[0] = STOPY
    _P.KLIUCH[0] = KLIUCH
    _P.KOLINO[0] = KOLINO
    # Профіль Kontext малює руками вниз — модель так само (MPFB, KUT_BIK).
    _P.postavyty_ruky(arm, _P.KUT_BIK if VYD == "бік" and not BIK_T
                      else KUT)
# Центр очних яблук (сітка з текстурою «…_eye») — до того, як рогівку
# приберуть: за ним оцінка збоку й ззаду дорівнює масштаб (точок обличчя
# там немає).
_dg = bpy.context.evaluated_depsgraph_get()
_ochi = []
for _o in [x for x in bpy.data.objects if x.type == "MESH"]:
    _t = [n.image.name.lower() for m in _o.data.materials if m and m.use_nodes
          for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and n.image]
    if any("_eye" in t for t in _t):
        _e = _o.evaluated_get(_dg)
        _me = _e.to_mesh()
        _ochi += [_o.matrix_world @ v.co for v in _me.vertices]
        _e.to_mesh_clear()
OKO_SVIT = sum(_ochi, Vector()) / len(_ochi) if _ochi else None
sitky = [o for o in bpy.data.objects if o.type == "MESH"]
dg = bpy.context.evaluated_depsgraph_get()
tochky = []
for o in sitky:
    ev = o.evaluated_get(dg)
    me_ = ev.to_mesh()
    tochky += [o.matrix_world @ v.co for v in me_.vertices]
    ev.to_mesh_clear()
lo = Vector([min(p[i] for p in tochky) for i in range(3)])
hi = Vector([max(p[i] for p in tochky) for i in range(3)])
# Перед — за ступнями скелета (як у avatar_build): пальці попереду кісточки.
b = arm.data.bones
pered = 1 if (arm.matrix_world @ b["ball_l"].head_local).y > \
    (arm.matrix_world @ b["foot_l"].head_local).y else -1
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.light = "FLAT"
sc.display.shading.color_type = "TEXTURE"
# Workbench передає пікселі точно (EEVEE розмивав: тіло 0,79 → 0,62), але
# прозорості не знає — рогівка очей MPFB (прозорий шар) затуляла райдужку.
# Лише для оцінки: грані очей з прозорою текстурою геть.
import bmesh
import numpy as _np
for o in [x for x in bpy.data.objects if x.type == "MESH"]:
    mats = [m for m in o.data.materials if m and m.use_nodes]
    tex = [n.image for m in mats for n in m.node_tree.nodes
           if n.type == "TEX_IMAGE" and n.image]
    if not tex or not tex[0].name.lower().endswith(("_eye", "eye.png", "brown_eye")) and "_eye" not in tex[0].name.lower():
        continue
    im = tex[0]
    w_, h_ = im.size
    px = _np.empty(w_ * h_ * 4, dtype=_np.float32)
    im.pixels.foreach_get(px)
    alfa = px.reshape(h_, w_, 4)[..., 3]
    bm = bmesh.new()
    bm.from_mesh(o.data)
    uvl = bm.loops.layers.uv.active
    geth = []
    for f in bm.faces:
        u = sum(l[uvl].uv[0] for l in f.loops) / len(f.loops)
        v = sum(l[uvl].uv[1] for l in f.loops) / len(f.loops)
        if alfa[min(h_ - 1, int(v * h_)) % h_, min(w_ - 1, int(u * w_)) % w_] < 0.5:
            geth.append(f)
    bmesh.ops.delete(bm, geom=geth, context="FACES")
    bm.to_mesh(o.data)
    bm.free()
    print("[рендер] рогівка геть: %d граней" % len(geth))
sc.render.film_transparent = True
sc.render.resolution_x = sc.render.resolution_y = int(__import__("os").environ.get("ROZDIL", "1024"))
sc.view_settings.view_transform = "Standard"
kam = bpy.data.objects.new("камера", bpy.data.cameras.new("камера"))
sc.collection.objects.link(kam)
sc.camera = kam
kam.data.type = "ORTHO"
kam.data.ortho_scale = max(hi.x - lo.x, hi.z - lo.z) * 1.06
c = (lo + hi) / 2
kut = {"перед": 0.0, "бік": math.pi / 2, "зад": math.pi}[VYD]
if VYD == "бік":
    # Профіль кадру повернутий на «кут профілю» (підбір, `mpfb_pidbir`).
    kut += pered * math.radians(PROFIL)
napr = Vector((math.sin(kut), pered * math.cos(kut), 0)) * 6
kam.location = c + napr
kam.rotation_euler = (c - kam.location).to_track_quat("-Z", "Y").to_euler()
sc.render.filepath = KUDY
bpy.ops.render.render(write_still=True)
if OKO_SVIT is not None:
    from bpy_extras.object_utils import world_to_camera_view
    import json as _js
    _p = world_to_camera_view(sc, kam, OKO_SVIT)
    R_ = sc.render.resolution_x
    with open(KUDY + ".json", "w") as _f:
        _js.dump({"око": [_p.x * R_, (1 - _p.y) * R_]}, _f)
print("[рендер] →", KUDY)
