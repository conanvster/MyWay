"""Швидкий шлях (≤4 хв): готова модель споріднененого виду як шаблон —
сітка, скелет, ваги, рухи беруться як є; зовнішній вигляд — перенесенням
кольорів референсу на текстуру шаблону (зсув і масштаб у Lab).
Форма лишається шаблонною: риси, яких у шаблона нема (шипи, другий хвіст,
зброя), не з'являться.

    blender -b --python tools/blender/scan_reskin.py -- <вид> <шаблон> <референс.png> <маска.png>

<маска.png> — ч/б маска звіра на референсі (birefnet, біле — звір).
"""
import json
import os
import shutil
import sys

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_hare as hare  # noqa: E402
import scan_lib as L  # noqa: E402
import scan_profiles as P  # noqa: E402

ROOT = L.ROOT


def look(name):
    mobs = json.load(open(os.path.join(ROOT, "game", "data", "mobs.json"), encoding="utf-8"))
    for v in mobs.values():
        if isinstance(v, dict) and v.get("назва") == name:
            return v.get("вигляд", {})
    raise SystemExit("‼ немає виду «%s» у mobs.json" % name)


def stem(name):
    m = look(name).get("модель", "")
    return os.path.splitext(os.path.basename(m))[0] if m.endswith(".glb") else name


# ---------------------------------------------------------------- колір

def _to_lin(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def _to_srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


_M = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
_W = np.array([0.95047, 1.0, 1.08883])


def rgb2lab(rgb):
    xyz = _to_lin(rgb) @ _M.T / _W
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[:, 1] - 16, 500 * (f[:, 0] - f[:, 1]), 200 * (f[:, 1] - f[:, 2])], 1)


def lab2rgb(lab):
    fy = (lab[:, 0] + 16) / 116
    f = np.stack([fy + lab[:, 1] / 500, fy, fy - lab[:, 2] / 200], 1)
    xyz = np.where(f ** 3 > 0.008856, f ** 3, (f - 16 / 116) / 7.787) * _W
    return _to_srgb(xyz @ np.linalg.inv(_M).T)


def base_image(mesh):
    for mat in mesh.data.materials:
        bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf and bsdf.inputs["Base Color"].links:
            node = bsdf.inputs["Base Color"].links[0].from_node
            if node.type == "TEX_IMAGE":
                return node.image
    raise SystemExit("‼ у шаблона нема текстури кольору")


def used_texels(mesh, img, n=300000):
    """Тексели під випадковими точками поверхні, рівномірно за площею:
    точки UV вершин густі в дрібних темних місцях (суглоби, щілини) і
    занижували тон великих видимих поверхонь."""
    me = mesh.data
    me.calc_loop_triangles()
    tris = np.zeros(len(me.loop_triangles) * 3, dtype=np.int64)
    me.loop_triangles.foreach_get("loops", tris)
    area = np.zeros(len(me.loop_triangles))
    me.loop_triangles.foreach_get("area", area)
    uv = np.zeros(len(me.loops) * 2)
    me.uv_layers["UVMap"].data.foreach_get("uv", uv)
    tri_uv = uv.reshape(-1, 2)[tris.reshape(-1, 3)]
    rng = np.random.default_rng(0)
    pick = rng.choice(len(area), n, p=area / area.sum())
    r1, r2 = rng.random(n), rng.random(n)
    flip = r1 + r2 > 1
    r1[flip], r2[flip] = 1 - r1[flip], 1 - r2[flip]
    t = tri_uv[pick]
    p = t[:, 0] + r1[:, None] * (t[:, 1] - t[:, 0]) + r2[:, None] * (t[:, 2] - t[:, 0])
    w, h = img.size
    x = np.clip((p[:, 0] * w).astype(int), 0, w - 1)
    y = np.clip((p[:, 1] * h).astype(int), 0, h - 1)
    return y * w + x


def _pixels(path):
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h * w, 4)
    bpy.data.images.remove(img)
    return px


def reference_pixels(ref_path, mask_path):
    px, m = _pixels(ref_path), _pixels(mask_path)
    return px[m[:, 0] > 0.9, :3]  # лише сам звір, без тла й м'якого краю


def recolor(mesh, ref_path, mask_path):
    img = base_image(mesh)
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h * w, 4)
    ref = rgb2lab(reference_pixels(ref_path, mask_path))
    idx = used_texels(mesh, img)  # без unique: повтори = вага площі
    body = rgb2lab(px[idx, :3])
    lab = rgb2lab(px[:, :3])
    # Медіана + міжквартильний розмах, а не квантилі: у масці референсу до
    # чверті пікселів — відблиски, світіння очей/клешень, не колір тіла
    # (чорний скорпіон після квантилів лишався червоним).
    # Світлість — за освітленою частиною (65-й перцентиль): медіана на
    # арті з печери падає в тіні черева й лап (сивий печерний ведмідь
    # виходив бурим).
    for c, (lo, mid, hi) in enumerate([(40, 65, 90), (25, 50, 75), (25, 50, 75)]):
        t_lo, t_mid, t_hi = np.percentile(body[:, c], [lo, mid, hi])
        r_lo, r_mid, r_hi = np.percentile(ref[:, c], [lo, mid, hi])
        k = np.clip((r_hi - r_lo) / max(t_hi - t_lo, 1e-3), 0.5, 1.5)
        lab[:, c] = (lab[:, c] - t_mid) * k + r_mid
    px[:, :3] = lab2rgb(lab)
    new = bpy.data.images.new(img.name + "_reskin", w, h)
    new.pixels.foreach_set(px.ravel())
    new.pack()
    for mat in mesh.data.materials:
        for n in mat.node_tree.nodes:
            if n.type == "TEX_IMAGE" and n.image == img:
                n.image = new
    return float(np.median(ref[:, 0])), float(np.median(body[:, 0]))


def height(mesh):
    z = L.verts(mesh.evaluated_get(bpy.context.evaluated_depsgraph_get()))[:, 2]
    return float(z.max() - z.min())


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    name, template, ref_png, mask_png = argv[0], argv[1], argv[2], argv[3]
    cfg = P.config(name)
    folder = os.path.join(ROOT, "art", "monsters", cfg["source"] + "-3d")
    os.makedirs(folder, exist_ok=True)
    src_blend = os.path.join(ROOT, "art", "monsters", stem(template) + ".blend")
    bpy.ops.wm.open_mainfile(filepath=src_blend)
    mesh = next(o for o in bpy.data.objects if o.type == "MESH" and o.name == "Тіло")
    skel = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    for o in list(bpy.data.objects):          # кістки-палички аркуша тощо
        if o not in (mesh, skel):
            bpy.data.objects.remove(o)
    l_ref, l_tpl = recolor(mesh, ref_png, mask_png)
    h_new = float(look(name).get("зріст", 1.0))
    # Висота шаблону — виміряна, не з mobs.json: старі збірки (зомбі 0.89 м
    # при «1.8») і кажан (розмах крил) з паспортом не збігаються.
    skel.animation_data.action = bpy.data.actions["Idle"]
    bpy.context.scene.frame_set(1)
    h_tpl = height(mesh)
    # Масштаб запікається в сітку й кістки; зсуви кісток у ключах — у
    # метрах, тож × s.
    s = h_new / h_tpl
    skel.scale = tuple(v * s for v in skel.scale)
    bpy.context.view_layer.objects.active = skel
    for o in bpy.data.objects:
        o.select_set(o in (skel, mesh))
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for act in bpy.data.actions:
        for fcu in hare.curves(act):
            if fcu.data_path.endswith(".location"):
                for kp in fcu.keyframe_points:
                    kp.co.y *= s
                    kp.handle_left.y *= s
                    kp.handle_right.y *= s
                fcu.update()
    bpy.context.scene.frame_set(1)
    if abs(height(mesh) - h_new) > 0.02 * h_new:
        raise SystemExit("‼ зріст після масштабу %.2f м замість %.2f" % (height(mesh), h_new))
    st = stem(name)
    blend = os.path.join(ROOT, "art", "monsters", st + ".blend")
    glb = os.path.join(ROOT, "game", "models", "own", st + ".glb")
    keep = os.path.join(ROOT, "art", "monsters", "_до-шаблону")
    os.makedirs(keep, exist_ok=True)
    for old in (blend, glb):                 # стара модель — убік, один раз
        dst = os.path.join(keep, os.path.basename(old))
        if os.path.exists(old) and not os.path.exists(dst):
            shutil.copy(old, dst)
    bpy.ops.wm.save_as_mainfile(filepath=blend)
    L.export(glb)
    rep = {"вид": name, "метод": "шаблон", "шаблон": template, "зріст": h_new,
           "масштаб": round(s, 3), "L_референс": round(l_ref, 1), "L_шаблон": round(l_tpl, 1),
           "blend": os.path.relpath(blend, ROOT), "glb": os.path.relpath(glb, ROOT),
           "glb_МБ": round(os.path.getsize(glb) / 1e6, 1)}
    json.dump(rep, open(os.path.join(folder, "звіт.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    L.log("шаблон %s → %s: масштаб %.2f, L %.0f→%.0f, %s (%.1f МБ)"
          % (template, name, s, l_tpl, l_ref, rep["glb"], rep["glb_МБ"]))


if __name__ == "__main__":
    main()
