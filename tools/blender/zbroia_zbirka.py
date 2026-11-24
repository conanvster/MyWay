"""Сира сітка зброї (Pixal3D) → модель для гри (18.10.2026).

    blender -b -P tools/blender/zbroia_zbirka.py -- [назва …]

Без назв — кожна `art/zbroia/<назва>/pixal3d.glb`, для якої ще немає
`game/models/own/zbroia/<назва>.glb`. Тип речі — з `data/items.json`.

Що робить, у тих самих умовностях, що й `WeaponLook` (у МЕТРАХ гри,
руків'я в нулі, річ уздовж +Y гри, ширина вздовж X, лезо сокири й тятива
лука на +X, лице щита — до −Z гри):
  1. головні осі сітки (PCA): найдовша — угору, найширша — X, найтонша — Y;
  2. котрий кінець руків'я — за найширшим перерізом: у меча й кинджала це
     гарда (руків'я поруч із нею), у сокири, списа й посоха — головка
     (руків'я на протилежному кінці); лук — посередині;
  3. довжина — `DOVZHYNA`, руків'я — `HVAT` (частка довжини від низу);
  4. спрощення до `HRANEI`, текстура до 1024, JPEG — у гру (git).
І рендер `art/zbroia/<назва>/rendr.png` для аркуша.
"""
import json
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

KORIN = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SYRI = os.path.join(KORIN, "art", "zbroia")
GRA = os.path.join(KORIN, "game", "models", "own", "zbroia")
HRANEI = 12000
TEKSTURA = 1024
# Довжина вздовж Y гри, метри (щит — поперечник). Числа виконавця, ті самі
# порядки, що й у `WeaponLook`.
DOVZHYNA = {"меч": 1.0, "кинджал": 0.42, "сокира": 0.85, "спис": 1.95,
            "посох": 1.65, "лук": 1.3, "щит": 0.62}
# Де руків'я: частка довжини від нижнього кінця. Меч і кинджал — окремо,
# за гардою; лук і щит — центр.
HVAT = {"сокира": 0.2, "спис": 0.35, "посох": 0.32, "лук": 0.5, "щит": 0.5}


def typy():
    d = json.load(open(os.path.join(KORIN, "game/data/items.json"),
                       encoding="utf-8"))
    out = {}

    def walk(o):
        if isinstance(o, dict):
            for k, v in o.items():
                if isinstance(v, dict) and v.get("слот") in ("зброя", "щит"):
                    out[k] = v.get("тип", "")
                else:
                    walk(v)
    walk(d)
    # один вигляд на тип (20.11.2026): «тип-меч» … — моделі для всіх речей типу
    for t in ("меч", "кинджал", "сокира", "спис", "посох", "лук", "щит"):
        out["тип-" + t] = t
    return out


def chysto():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def vzhyty(shliakh):
    bpy.ops.import_scene.gltf(filepath=shliakh)
    sitky = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in bpy.context.scene.objects:
        o.select_set(o in sitky)
    bpy.context.view_layer.objects.active = sitky[0]
    if len(sitky) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.parent = None
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in list(bpy.context.scene.objects):
        if o is not ob:
            bpy.data.objects.remove(o, do_unlink=True)
    return ob


def tochky(ob):
    v = np.empty(len(ob.data.vertices) * 3)
    ob.data.vertices.foreach_get("co", v)
    return v.reshape(-1, 3)


def povernuty(ob, tip):
    """Головні осі → Z (довга), X (широка), Y (тонка)."""
    p = tochky(ob)
    c = p.mean(axis=0)
    _, vecs = np.linalg.eigh(np.cov((p - c).T))
    dovga, shyroka, tonka = vecs[:, 2], vecs[:, 1], vecs[:, 0]
    if tip == "щит":
        # Щит: лице — найтонша вісь, «верх» — будь-яка з двох інших.
        dovga, shyroka, tonka = vecs[:, 2], vecs[:, 1], vecs[:, 0]
    r = np.array([shyroka, tonka, dovga])          # рядки — нові X, Y, Z
    if np.linalg.det(r) < 0:
        r[1] = -r[1]
    m = Matrix(((*r[0], 0), (*r[1], 0), (*r[2], 0), (0, 0, 0, 1)))
    ob.data.transform(m @ Matrix.Translation(Vector(-c)))
    ob.data.update()


def perezy(p, n=40):
    """Ширина (по X) у `n` зрізах уздовж Z — від низу до верху."""
    z0, z1 = p[:, 2].min(), p[:, 2].max()
    kr = (z1 - z0) / n
    out = []
    for i in range(n):
        s = p[(p[:, 2] >= z0 + i * kr) & (p[:, 2] < z0 + (i + 1) * kr)]
        out.append(np.ptp(s[:, 0]) if len(s) > 2 else 0.0)
    return np.array(out), z0, z1


def obernuty_z(ob):
    ob.data.transform(Matrix.Rotation(math.pi, 4, "X"))
    ob.data.update()


def obernuty_x(ob):
    ob.data.transform(Matrix.Rotation(math.pi, 4, "Z"))
    ob.data.update()


def rozstavyty(ob, tip):
    """Руків'я в нуль, кінці — за умовностями `WeaponLook`."""
    p = tochky(ob)
    shyr, z0, z1 = perezy(p)
    n = len(shyr)
    naishyrshyi = int(np.argmax(shyr))
    if tip in ("меч", "кинджал"):
        # Клинок довгий від гарди, руків'я коротке: гарда ближче до низу.
        if naishyrshyi > n / 2:
            obernuty_z(ob)
    elif tip in ("сокира", "спис", "посох"):
        # Головка вгорі.
        if naishyrshyi < n / 2:
            obernuty_z(ob)
    p = tochky(ob)
    shyr, z0, z1 = perezy(p)
    dov = z1 - z0
    if tip in ("меч", "кинджал"):
        garda = z0 + (int(np.argmax(shyr[: n // 2])) + 0.5) * dov / n
        hvat = (z0 + garda) / 2.0
    else:
        hvat = z0 + HVAT[tip] * dov
    # Лезо сокири — на +X: верхня чверть важча з того боку.
    if tip == "сокира":
        verh = p[p[:, 2] > z0 + 0.7 * dov]
        if verh[:, 0].mean() < np.median(p[:, 0]):
            obernuty_x(ob)
    # Лук: тятива — на +X, руків'я (середина) — на −X.
    if tip == "лук":
        seredyna = p[np.abs(p[:, 2] - (z0 + z1) / 2) < 0.08 * dov]
        if seredyna[:, 0].mean() > p[:, 0].mean():
            obernuty_x(ob)
    # Щит: опукле лице — до +Y Blender (−Z гри), як умбон у `WeaponLook`.
    if tip == "щит":
        if p[:, 1].max() - p[:, 1].mean() < p[:, 1].mean() - p[:, 1].min():
            ob.data.transform(Matrix.Rotation(math.pi, 4, "Z"))
            ob.data.update()
    p = tochky(ob)
    x_mid = 0.0 if tip in ("щит",) else np.median(p[:, 0])
    if tip == "лук":
        seredyna = p[np.abs(p[:, 2] - hvat) < 0.05 * dov]
        x_mid = seredyna[:, 0].mean()
    ob.data.transform(Matrix.Translation(Vector((-x_mid, -np.median(p[:, 1]),
                                                -hvat))))
    k = DOVZHYNA[tip] / dov
    ob.data.transform(Matrix.Scale(k, 4))
    ob.data.update()


## Відірвані шматки, що стирчать убік від древка далі за VIDROSTOK м (24.11.2026: у посоха
## генератор приліпив окремий тонкий шип поперек древка) — геть. Лише древкова зброя: у меча
## гарда й у щита умбон теж бувають окремими шматками, але вони на своєму місці.
VIDROSTOK = 0.06


def bez_vidrostkiv(ob, tip):
    if tip not in ("посох", "спис"):
        return
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.verts.ensure_lookup_table()
    bach, shmatky = set(), []
    for v in bm.verts:
        if v in bach:
            continue
        st, sh = [v], []
        bach.add(v)
        while st:
            u = st.pop()
            sh.append(u)
            for e in u.link_edges:
                w = e.other_vert(u)
                if w not in bach:
                    bach.add(w)
                    st.append(w)
        shmatky.append(sh)
    geth = []
    for sh in shmatky:
        c = sum((u.co for u in sh), Vector()) / len(sh)
        bik = max(math.hypot(u.co.x, u.co.y) for u in sh)
        if math.hypot(c.x, c.y) > VIDROSTOK or bik > VIDROSTOK * 2.5:
            geth.extend(sh)
    # …і обрубки, що лишились на самому древку: вершина далі за 3,5 см від середини древка на
    # своїй висоті (древко буває хвилясте), окрім головки — верхніх 12 % довжини
    gs = set(geth)
    zs = [v.co.z for v in bm.verts]
    z0, z1 = min(zs), max(zs)
    koshyky = {}
    for v in bm.verts:
        if v not in gs:
            koshyky.setdefault(int((v.co.z - z0) / 0.03), []).append(v.co)
    serediny = {k: (sorted(c.x for c in cs)[len(cs) // 2], sorted(c.y for c in cs)[len(cs) // 2])
                for k, cs in koshyky.items()}
    obrubky = []
    for v in bm.verts:
        if v in gs or v.co.z > z1 - 0.12 * (z1 - z0):
            continue
        mx, my = serediny[int((v.co.z - z0) / 0.03)]
        if math.hypot(v.co.x - mx, v.co.y - my) > 0.035:
            obrubky.append(v)
    geth.extend(obrubky)
    if geth:
        bmesh.ops.delete(bm, geom=geth, context="VERTS")
        bm.to_mesh(ob.data)
        ob.data.update()
    # після зрізання — крихти (острівці до 60 вершин; головка й наконечник — теж окремі шматки, більші)
    bm.verts.ensure_lookup_table()
    bach, krykhty = set(), []
    for v in bm.verts:
        if v in bach:
            continue
        st, sh = [v], []
        bach.add(v)
        while st:
            u = st.pop()
            sh.append(u)
            for e in u.link_edges:
                w = e.other_vert(u)
                if w not in bach:
                    bach.add(w)
                    st.append(w)
        if len(sh) < 60:
            krykhty.extend(sh)
    if krykhty:
        bmesh.ops.delete(bm, geom=krykhty, context="VERTS")
        bm.to_mesh(ob.data)
        ob.data.update()
    print("[зброя] відростки: шматків %d, прибрано вершин %d (з них обрубків %d), крихт %d"
          % (len(shmatky), len(geth), len(obrubky), len(krykhty)), flush=True)
    bm.free()


def sproshchennia(ob):
    bpy.context.view_layer.objects.active = ob
    if len(ob.data.polygons) > HRANEI:
        mod = ob.modifiers.new("Спрощення", "DECIMATE")
        mod.ratio = HRANEI / len(ob.data.polygons)
        bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.ops.object.shade_smooth()
    for img in bpy.data.images:
        if img.size[0] > TEKSTURA:
            img.scale(TEKSTURA, TEKSTURA)


def vyvesty(ob, kudy):
    os.makedirs(os.path.dirname(kudy), exist_ok=True)
    for o in bpy.context.scene.objects:
        o.select_set(o is ob)
    bpy.ops.export_scene.gltf(
        filepath=kudy, export_format="GLB", export_yup=True,
        use_selection=True, export_apply=True, export_animations=False,
        export_texcoords=True, export_image_format="JPEG",
        export_jpeg_quality=88)


def rendr(ob, kudy):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.resolution_x = sc.render.resolution_y = 600
    sc.render.film_transparent = False
    w = bpy.data.worlds.new("тло")
    w.color = (0.12, 0.12, 0.13)
    sc.world = w
    lo = Vector(ob.bound_box[0])
    hi = Vector(ob.bound_box[6])
    seredyna = (lo + hi) / 2
    rozmir = max(hi - lo)
    cam = bpy.data.objects.new("камера", bpy.data.cameras.new("камера"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = rozmir * 1.15
    sc.collection.objects.link(cam)
    # Спереду-збоку, як на значку: −Y Blender — «спереду» (лице щита
    # дивиться на +Y, тож для нього — навпаки).
    bik = 1.0 if ob.get("tip") == "щит" else -1.0
    cam.location = seredyna + Vector((rozmir * 0.6, bik * rozmir * 1.5,
                                      rozmir * 0.25))
    cam.rotation_euler = (seredyna - cam.location).to_track_quat(
        "-Z", "Y").to_euler()
    sc.camera = cam
    sc.render.filepath = kudy
    bpy.ops.render.render(write_still=True)


def zibraty(nazva, tip):
    chysto()
    ob = vzhyty(os.path.join(SYRI, nazva, "pixal3d.glb"))
    ob.name = nazva
    ob["tip"] = tip
    povernuty(ob, tip)
    rozstavyty(ob, tip)
    bez_vidrostkiv(ob, tip)
    sproshchennia(ob)
    kudy = os.path.join(GRA, nazva + ".glb")
    vyvesty(ob, kudy)
    rendr(ob, os.path.join(SYRI, nazva, "rendr.png"))
    lo, hi = Vector(ob.bound_box[0]), Vector(ob.bound_box[6])
    print("[зброя] %s (%s): граней %d, розмір %.2f×%.2f×%.2f м, → %s, %d КБ"
          % (nazva, tip, len(ob.data.polygons), *(hi - lo), kudy,
             os.path.getsize(kudy) // 1024), flush=True)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    vsi = typy()
    nazvy = args or [n for n in vsi
                     if os.path.exists(os.path.join(SYRI, n, "pixal3d.glb"))
                     and not os.path.exists(os.path.join(GRA, n + ".glb"))]
    for n in nazvy:
        zibraty(n, vsi[n])


main()
