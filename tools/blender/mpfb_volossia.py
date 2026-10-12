"""Зачіска MakeHuman на голову скан-аватара (12.10.2026).

Слово замовника: «перука потрібно зробити окремим із волоссям, яке на
вітру або під час руху хоч трохи рухається». Сканова пластина волосся
(Pixal3D) рухалась, але виглядала білим аркушем — тут справжні пасма
MakeHuman (CC0) з прозорою текстурою.

  1. MPFB: жінка + зачіска (`--зачіска long01`) — сітка зачіски з UV;
  2. голова MPFB (лиса) → голова скану: масштаб за висотою «підборіддя —
     маківка», центр за перерізом голови на висоті очей без вух;
  3. текстура пасом перефарбована (яскравість × колір, альфа та сама);
  4. → `<вихід.blend>` з одним об'єктом «Волосся».

    blender -b -P tools/blender/mpfb_volossia.py -- <основа.blend> <вихід.blend>
        [--зачіска long01] [--колір 0.92,0.91,0.88] [--підборіддя 1.596]
"""
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

ARGS = sys.argv[sys.argv.index("--") + 1:]
OSNOVA, VYKHID = ARGS[0], ARGS[1]


def arg(k, typ, default):
    return typ(ARGS[ARGS.index(k) + 1]) if k in ARGS else default


ZACHISKA = arg("--зачіска", str, "long01")
KOLIR = [float(c) for c in arg("--колір", str, "0.92,0.91,0.88").split(",")]
PIDBORIDDIA = arg("--підборіддя", float, 1.596)

from bl_ext.blender_org.mpfb.services.humanservice import HumanService  # noqa: E402

DANI = os.path.expanduser(
    "~/.config/blender/5.2/extensions/.user/blender_org/mpfb/data")


def holova(pts, z_chin):
    """(висота голови від підборіддя, точка: центр x/y, маківка z)."""
    top = pts[:, 2].max()
    zo = z_chin + (top - z_chin) * 0.45
    m = np.abs(pts[:, 2] - zo) < 0.01
    cx = float(np.median(pts[m, 0]))
    m2 = m & (np.abs(pts[:, 0] - cx) < 0.07)
    cy = float((pts[m2, 1].min() + pts[m2, 1].max()) / 2)
    return top - z_chin, Vector((cx, cy, top))


# Голова скану — вершини тіла з основи.
with bpy.data.libraries.load(OSNOVA) as (src, dst):
    dst.meshes = list(src.meshes)
tilo_me = max(dst.meshes, key=lambda m: len(m.vertices))
sp = np.array([v.co[:] for v in tilo_me.vertices])
vys_s, verkh_s = holova(sp[sp[:, 2] > PIDBORIDDIA - 0.05], PIDBORIDDIA)
for m in list(dst.meshes):
    bpy.data.meshes.remove(m)

# 1. MPFB: жінка + зачіска.
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)
h = HumanService.create_human(macro_detail_dict={
    "gender": 0.0, "age": 0.45, "muscle": 0.4, "weight": 0.4,
    "proportions": 0.6, "height": 0.6, "cupsize": 0.4, "firmness": 0.5,
    "race": {"caucasian": 1.0, "african": 0.0, "asian": 0.0}})
pered = set(bpy.data.objects)
HumanService.add_mhclo_asset(os.path.join(DANI, "hair", ZACHISKA, ZACHISKA + ".mhclo"),
                             h, asset_type="Hair", material_type="GAMEENGINE")
bpy.context.view_layer.update()
nove = [o for o in bpy.data.objects if o not in pered and o.type == "MESH"]
vol = max(nove, key=lambda o: len(o.data.vertices))
dg = bpy.context.evaluated_depsgraph_get()
hm = h.evaluated_get(dg).to_mesh()
hp = np.array([(h.matrix_world @ v.co)[:] for v in hm.vertices])
z0 = hp[:, 2].min()
H = hp[:, 2].max() - z0
vys_m, verkh_m = holova(hp[hp[:, 2] > z0 + H * 0.84], z0 + H * 0.877)
print("[зачіска] MPFB зріст %.3f, голова %.3f; скан голова %.3f" % (H, vys_m, vys_s))

# 2. Зачіску — з MPFB на голову скану (застосувати форму, зняти зв'язки).
e = vol.evaluated_get(dg)
me = bpy.data.meshes.new_from_object(e)
me.transform(vol.matrix_world)
k = vys_s / vys_m
T = Matrix.Translation(verkh_s) @ Matrix.Scale(k, 4) @ Matrix.Translation(-verkh_m)
me.transform(T)
novyi = bpy.data.objects.new("Волосся", me)
bpy.context.scene.collection.objects.link(novyi)
for o in list(bpy.data.objects):
    if o is not novyi:
        bpy.data.objects.remove(o)
pts = np.array([v.co[:] for v in me.vertices])
print("[зачіска] масштаб ×%.3f; волосся z %.3f…%.3f, вершин %d"
      % (k, pts[:, 2].min(), pts[:, 2].max(), len(pts)))

# 3. Колір пасом: яскравість × KOLIR, альфа та сама.
for mat in me.materials:
    if not mat or not mat.node_tree:
        continue
    for n in mat.node_tree.nodes:
        if n.type == "TEX_IMAGE" and n.image and n.image.size[0] > 0:
            im = n.image
            w, hh = im.size
            px = np.empty(w * hh * 4, dtype=np.float32)
            im.pixels.foreach_get(px)
            px = px.reshape(-1, 4)
            jas = px[:, :3].mean(1, keepdims=True)
            jas = 0.55 + 0.45 * jas / max(float(jas.max()), 1e-3)
            px[:, :3] = jas * np.array(KOLIR)
            nove_im = bpy.data.images.new("волосся-" + ZACHISKA, w, hh, alpha=True)
            nove_im.pixels.foreach_set(px.ravel())
            nove_im.pack()
            n.image = nove_im
    mat.blend_method = "HASHED" if hasattr(mat, "blend_method") else None
    mat.use_backface_culling = False
bpy.ops.wm.save_as_mainfile(filepath=VYKHID)
print("[зачіска] →", VYKHID)
