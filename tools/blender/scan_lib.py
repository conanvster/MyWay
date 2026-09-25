"""Спільне ядро шляху А — те, що до 24.09.2026 було скопійоване в кожен
`make_<вид>_scan.py` (11 копій `simplify/fur_mask/rig/by_distance/export`),
плюс автоматика, яку доти робили руками на кожному звірі:

- `normalize_roll` — вісь X КОЖНОЇ кістки = світовий +X. Саме так стоять
  кістки зайця, під якого написані рухи `make_hare.actions()` (перевірено
  виміром матриць). Без цього авторолл Blender залежить від дрібниць у
  координатах: у рисі `location.z` кістки hips рухав тіло вбік, у зомбі
  той самий кут ліва й права рука відпрацьовували по-різному.
- `level_by_inliers` — нахил за площиною через лапи, що справді стоять:
  перебір усіх трійок і четвірки, обирається площина з найбільшою
  кількістю лап на землі (підняту в кроці лапу не тягнемо на землю).
- `auto_bones_quadruped` / `auto_bones_humanoid` — кістки з орієнтирів
  сітки замість ручних замірів ортовидами.
- `fix_ground` — корекція висоти `hips` на кожному ключовому кадрі
  кожного руху: лапи не нижче землі, а кадри, де звір має стояти/лежати,
  — на землі. Вісь, якою `hips` рухає тіло вертикально, МІРЯЄТЬСЯ, а не
  припускається.

Не чіпає `make_template.py`/`make_hare.py` (розділ 0 методу) — лише
імпортує.
"""
import itertools
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import make_hare as hare  # noqa: E402


def log(msg):
    print("[скан] " + msg, flush=True)


# ---------------------------------------------------------------- сітка

def load_mesh(source):
    bpy.ops.import_scene.gltf(filepath=source)
    mesh = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
    for other in list(bpy.context.scene.objects):
        if other is not mesh:
            bpy.data.objects.remove(other)
    bpy.context.view_layer.objects.active = mesh
    mesh.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return mesh


def verts(mesh):
    n = len(mesh.data.vertices)
    a = np.empty(n * 3, dtype=np.float64)
    mesh.data.vertices.foreach_get("co", a)
    return a.reshape(n, 3)


def transform(mesh, m):
    mesh.data.transform(m)
    mesh.data.update()


def fit_height(mesh, height):
    """На нуль лапами, заввишки `height`, по центру габариту вздовж Y
    (камера `fur_look` дивиться на початок координат)."""
    p = verts(mesh)
    s = height / (p[:, 2].max() - p[:, 2].min())
    transform(mesh, Matrix.Scale(s, 4) @ Matrix.Translation((0, 0, -p[:, 2].min())))
    p = verts(mesh)
    transform(mesh, Matrix.Translation((0, -(p[:, 1].max() + p[:, 1].min()) / 2, 0)))


def orient_quadruped(mesh, height):
    """Мордою на −Y: головна вісь тулуба за PCA точок НИЖЧЕ половини
    висоти (роги, вуха й чубчики не тягнуть вісь), напрям — у бік, де
    вища половина маси (голова з шиєю вищі за круп)."""
    p = verts(mesh)
    z0, z1 = p[:, 2].min(), p[:, 2].max()
    body = p[(p[:, 2] > z0 + 0.25 * (z1 - z0)) & (p[:, 2] < z0 + 0.6 * (z1 - z0))]
    c = body[:, :2].mean(0)
    cov = np.cov((body[:, :2] - c).T)
    w, v = np.linalg.eigh(cov)
    axis = v[:, np.argmax(w)]
    # Де голова: з того кінця осі, де вершини в середньому вищі.
    t = (p[:, :2] - c) @ axis
    hi_pos = p[t > 0, 2].mean() if (t > 0).any() else 0
    hi_neg = p[t < 0, 2].mean() if (t < 0).any() else 0
    if hi_neg > hi_pos:
        axis = -axis
    yaw = math.atan2(axis[1], axis[0])
    transform(mesh, Matrix.Rotation(-math.pi / 2 - yaw, 4, "Z")
              @ Matrix.Translation((-c[0], -c[1], 0)))
    fit_height(mesh, height)


def orient_humanoid(mesh, height, yaw=0.0):
    """На нуль і в зріст. Pixal3D віддає двоногого так, як він стоїть на
    позі відносно камери (−Y). Анфас (імп, паглін, зомбі) — нічого не
    крутити; поза в три чверті (гнол 24.09.2026) — `yaw` виду в градусах
    (перевірка — ортовид «кістки-спереду»: морда до камери). Спроба
    знаходити напрям за писком автоматично хибила (зомбі — розворот на
    156°), тож вручну, а промт пози гуманоїда вимагає анфас."""
    if yaw:
        p = verts(mesh)
        c = p[:, :2].mean(0)
        transform(mesh, Matrix.Translation((c[0], c[1], 0)) @ Matrix.Rotation(math.radians(yaw), 4, "Z")
                  @ Matrix.Translation((-c[0], -c[1], 0)))
    fit_height(mesh, height)


def _components(pts, cell):
    cells = {}
    for i, c in enumerate(map(tuple, np.floor(pts[:, :2] / cell).astype(int))):
        cells.setdefault(c, []).append(i)
    seen, out = set(), []
    for s in cells:
        if s in seen:
            continue
        stack, cur = [s], []
        while stack:
            q = stack.pop()
            if q in seen or q not in cells:
                continue
            seen.add(q)
            cur.append(q)
            stack += [(q[0] + dx, q[1] + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1)]
        idx = [i for c in cur for i in cells[c]]
        out.append((len(cur), pts[idx, :2].mean(0)))
    return out


def _islands(pts, cell):
    """Як `_components`, але ще й розмах острівця (більша з осей X/Y) і
    самі його точки."""
    cells = {}
    for i, c in enumerate(map(tuple, np.floor(pts[:, :2] / cell).astype(int))):
        cells.setdefault(c, []).append(i)
    seen, out = set(), []
    for s in cells:
        if s in seen:
            continue
        stack, cur = [s], []
        while stack:
            q = stack.pop()
            if q in seen or q not in cells:
                continue
            seen.add(q)
            cur.append(q)
            stack += [(q[0] + dx, q[1] + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1)]
        q = pts[[i for c in cur for i in cells[c]]]
        out.append((len(cur), q[:, :2].mean(0), float(np.ptp(q[:, :2], axis=0).max()), q))
    return out


def find_feet(p, height):
    """Лапи — тонкі вертикальні стовпчики крізь кілька горизонтальних
    шарів нижньої третини; хвіст, черево, роги — великі плями або вище.
    Квадранти навколо центру маси (перша версія) ламались: пухнастий
    хвіст лисиці звисав майже до землі й тягнув центр назад — «задньою
    лапою» ставав хвіст, передніх не було. Ім'я лапи — за положенням
    стовпчика відносно середнього з усіх чотирьох."""
    z0 = p[:, 2].min()
    cell = 0.03 * height
    big = int(0.04 * height ** 2 / cell ** 2)
    # Ланцюжки знизу вгору: нога похила, її переріз зсувається від шару
    # до шару — з'єднуємо з найближчим перерізом наступного шару.
    chains, open_ = [], []
    for lo in np.arange(0.02, 0.32, 0.06):
        band = p[(p[:, 2] >= z0 + lo * height) & (p[:, 2] < z0 + (lo + 0.06) * height)]
        comps = _components(band, cell) if len(band) else []
        taken, nxt = set(), []
        for ch in open_:
            d = [np.linalg.norm(xy - ch["xy"]) for _, xy in comps]
            if d and min(d) < 0.12 * height:
                i = int(np.argmin(d))
                ch["xy"] = comps[i][1]
                ch["sizes"].append(comps[i][0])
                taken.add(i)
                nxt.append(ch)
        for i, (n, xy) in enumerate(comps):
            if i not in taken:
                ch = {"start": lo, "first": xy, "xy": xy, "sizes": [n]}
                chains.append(ch)
                nxt.append(ch)
        open_ = nxt
    # Хвіст/черево вже в перших двох шарах — велика пляма; нога — ні.
    legs = [c for c in chains if len(c["sizes"]) >= 2 and max(c["sizes"][:2]) <= big]
    legs.sort(key=lambda c: (-len(c["sizes"]), c["start"]))
    if os.environ.get("SCAN_DEBUG"):
        for c in chains:
            print("ланцюг", round(c["start"], 2), np.round(c["first"] / height, 2), c["sizes"], flush=True)
    legs = legs[:4]
    low = p[p[:, 2] < z0 + 0.35 * height]
    pts = []
    if legs:
        # Кожна вершина — до найближчої ноги (за першим перерізом), лапа
        # шукається лише серед своїх: інакше для ноги, що внизу злилась
        # із сусідньою або піднята в кроці, «найнижчою» ставала гомілка
        # сусідки.
        firsts = np.array([c["first"] for c in legs])
        own = np.argmin(np.linalg.norm(low[:, None, :2] - firsts[None], axis=2), axis=1)
        for i, c in enumerate(legs):
            top = z0 + (c["start"] + 0.06) * height
            near = low[(own == i) & (low[:, 2] < top)
                       & (np.linalg.norm(low[:, :2] - c["first"], axis=1) < 0.15 * height)]
            if len(near):
                pts.append(near[np.argmin(near[:, 2])])
    if os.environ.get("SCAN_DEBUG"):
        print("лапи-сирі", [tuple(np.round(q, 3)) for q in pts], flush=True)
    if not pts:
        return {}
    my, mx = np.mean([q[1] for q in pts]), np.mean([q[0] for q in pts])
    feet = {}
    for q in pts:
        name = ("hind" if q[1] > my else "front") + (".L" if q[0] > mx else ".R")
        if name not in feet or q[2] < feet[name][2]:
            feet[name] = q
    # Лапи, що внизу зійшлись із сусідньою (недобудована Pixal3D, піднята
    # в кроці), геометрією не розділити надійно — віддзеркалити партнера
    # з іншого боку й узяти найнижчу точку поруч, крім ноги самого партнера.
    cx = float(np.mean([q[0] for q in feet.values()]))
    for end in ("front", "hind"):
        for side, other in ((".L", ".R"), (".R", ".L")):
            name, mate = end + side, end + other
            if name in feet or mate not in feet:
                continue
            guess = np.array([2 * cx - feet[mate][0], feet[mate][1]])
            dg = np.linalg.norm(low[:, :2] - guess, axis=1)
            dm = np.linalg.norm(low[:, :2] - feet[mate][:2], axis=1)
            near = low[(dg < 0.1 * height) & (dg < dm)]
            feet[name] = near[np.argmin(near[:, 2])] if len(near) else np.array([*guess, feet[mate][2]])
            if os.environ.get("SCAN_DEBUG"):
                print("лапа %s — з дзеркала %s" % (name, mate), flush=True)
    return feet


def _plane_rot(pts):
    a = np.c_[pts[:, 0], pts[:, 1], np.ones(len(pts))]
    (ax, by, _), *_ = np.linalg.lstsq(a, pts[:, 2], rcond=None)
    n = Vector((-ax, -by, 1.0)).normalized()
    return n.rotation_difference(Vector((0, 0, 1))).to_matrix().to_4x4()


def level_by_inliers(mesh, height, tol=0.03):
    """Кандидати — площина через кожну трійку лап і через усі чотири.
    Для кожної: скільки лап після повороту в межах `tol·height` від
    найнижчої. Перемагає найбільше «лап на землі», при рівності — менший
    поворот. Так і одна недобудована лапа (лисиця), і лапа, піднята в
    кроці (олень), і просто шум (рись) обробляються однаково."""
    p = verts(mesh)
    feet = find_feet(p, height)
    if len(feet) < 3:
        log("лап знайдено %d — нахил не вирівнюю" % len(feet))
        return {"метод": "без вирівнювання", "лапи": {k: list(map(float, v)) for k, v in feet.items()}}
    names = list(feet)
    pts = np.array([feet[n] for n in names])
    best = None
    for k in (4, 3):
        for combo in itertools.combinations(range(len(names)), k):
            if len(combo) < 3:
                continue
            m = _plane_rot(pts[list(combo)])
            r = np.array([(m @ Vector(tuple(q)).to_4d()).z for q in pts])
            inl = int((r - r.min() < tol * height).sum())
            angle = Vector((0, 0, 1)).angle(m.to_3x3() @ Vector((0, 0, 1)))
            spread = float(np.sort(r - r.min())[:inl].max())
            key = (-inl, round(spread / (tol * height), 1), angle)
            if best is None or key < best[0]:
                best = (key, m, [names[i] for i in combo])
    _, m, used = best
    feet_before = {n: (m @ Vector(tuple(q)).to_4d()).xyz for n, q in feet.items()}
    transform(mesh, m)
    p_rot = verts(mesh)
    s = height / (p_rot[:, 2].max() - p_rot[:, 2].min())
    zmin = float(p_rot[:, 2].min())
    y_shift = -s * (p_rot[:, 1].max() + p_rot[:, 1].min()) / 2
    fit_height(mesh, height)
    p = verts(mesh)
    feet_after = find_feet(p, height)
    # Другий прохід find_feet (по вже вирівняній сітці) інколи виро-
    # джується до 1 реальної ноги замість 4 (присадкувата постава,
    # ведмідь 24.09.2026): дзеркало дублює точку, ціла група "hind"
    # чи "front" зникає, downstream (auto_bones_quadruped) лишається
    # без задніх ніг. Перший прохід (до вирівнювання) надійніший — якщо
    # другий гірший за нього (менше груп передня/задня), взяти перший,
    # перенесений у систему координат вирівняної сітки.
    before_groups = {n[:4] for n in feet_before}
    after_groups = {n[:4] for n in feet_after}
    if len(feet_after) < len(feet_before) or before_groups - after_groups:
        feet = {n: (v.x * s, v.y * s + y_shift, (v.z - zmin) * s) for n, v in feet_before.items()}
    else:
        feet = feet_after
    lifted = [n for n, q in feet.items() if q[2] > tol * height]
    ang = math.degrees(Vector((0, 0, 1)).angle(m.to_3x3() @ Vector((0, 0, 1))))
    log("нахил %.1f° за лапами %s; у повітрі: %s" % (ang, ", ".join(used), ", ".join(lifted) or "жодна"))
    return {"метод": "площина за лапами", "кут": round(ang, 1), "опорні": used,
            "у_повітрі": lifted, "лапи": {k: [round(float(c), 3) for c in v] for k, v in feet.items()}}


def simplify(mesh, faces, weld_after=False):
    """Зварити шви UV (Pixal3D ріже по них — без цього «тепло» не
    знаходить розв'язку), спростити, узгодити нормалі, згладити.

    `weld_after` — спершу спростити, тоді зварити: у скелета-мага
    (25.09.2026) зварювання перед спрощенням, навіть з порогом 0.05 мм,
    розбивало сітку на уламки; без зварювання спрощення ціле."""
    bpy.context.view_layer.objects.active = mesh

    def weld():
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.remove_doubles(threshold=0.0005)
        bpy.ops.object.mode_set(mode="OBJECT")

    if not weld_after:
        weld()
    if len(mesh.data.polygons) > faces:
        mod = mesh.modifiers.new("Спрощення", "DECIMATE")
        mod.ratio = faces / len(mesh.data.polygons)
        bpy.ops.object.modifier_apply(modifier=mod.name)
    if weld_after:
        weld()
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.shade_smooth()


def base_colour(mesh):
    bsdf = mesh.data.materials[0].node_tree.nodes.get("Principled BSDF")
    return bsdf.inputs["Base Color"].links[0].from_node.image


def shrink_textures(mesh, size=2048):
    for node in mesh.data.materials[0].node_tree.nodes:
        if node.type == "TEX_IMAGE" and node.image.size[0] > size:
            node.image.scale(size, size)


def fur_mask(mesh, rule):
    """Друга UV «Голизна» (U: 0 — ворс, 1 — голо). `rule` з профілю:
    `pink` — рожеве (ніс, нутро вух), `dark` — поріг світлості темного
    (очі, кігті; 0 — вимкнено, для звірів із темними ногами/шерстю),
    `cold_only` — ворс лише на холодній темній шерсті (кажан)."""
    image = base_colour(mesh)
    w, h = image.size
    px = np.array(image.pixels[:], dtype=np.float32).reshape(h, w, 4)
    me = mesh.data
    n = len(me.loops)
    uv = np.empty(n * 2, dtype=np.float32)
    me.uv_layers[0].data.foreach_get("uv", uv)
    uv = uv.reshape(n, 2)
    vi = np.empty(n, dtype=np.int32)
    me.loops.foreach_get("vertex_index", vi)
    x = np.clip((uv[:, 0] * w).astype(int), 0, w - 1)
    y = np.clip((uv[:, 1] * h).astype(int), 0, h - 1)
    r, g, b = px[y, x, 0], px[y, x, 1], px[y, x, 2]
    light = 0.3 * r + 0.59 * g + 0.11 * b
    bare = np.zeros(n, dtype=bool)
    if rule.get("pink", True):
        bare |= (r > 0.3) & (r > 1.45 * g) & (b > 0.85 * g)
    if rule.get("dark", 0.06):
        bare |= light < rule.get("dark", 0.06)
    if rule.get("cold_only"):
        cold = (light < 0.3) & ((np.max([r, g, b], 0) - np.min([r, g, b], 0)) < 0.12) & (b >= 0.9 * r)
        bare = ~cold
    per_v = np.bincount(vi, weights=bare.astype(float), minlength=len(me.vertices))
    cnt = np.maximum(np.bincount(vi, minlength=len(me.vertices)), 1)
    val = per_v / cnt
    mask = me.uv_layers.new(name="Голизна")
    out = np.zeros(n * 2, dtype=np.float32)
    out[0::2] = val[vi]
    mask.data.foreach_set("uv", out)
    me.uv_layers.active_index = 0
    share = float((val > 0.5).mean())
    log("голих вершин %.0f%%" % (share * 100))
    return share


# ---------------------------------------------------------------- кістки

def _band(p, axis, lo, hi):
    return p[(p[:, axis] >= lo) & (p[:, axis] <= hi)]


def leg_samples(p, foot, top_z, height, others):
    """Центри перерізу ноги по шарах від лапи вгору (лише точки, ближчі
    до цієї лапи, ніж до інших) — [(z, x, y)]."""
    xy = np.array(foot[:2], dtype=float)
    out = [(float(foot[2]), float(xy[0]), float(xy[1]))]
    others = np.array([o[:2] for o in others]) if others else np.zeros((0, 2))
    z = foot[2] + 0.03 * height
    while z < top_z:
        s = p[(p[:, 2] >= z) & (p[:, 2] < z + 0.03 * height)]
        s = s[np.linalg.norm(s[:, :2] - xy, axis=1) < 0.07 * height]
        if len(others) and len(s):
            own = np.linalg.norm(s[:, :2] - xy, axis=1)[:, None] <= np.linalg.norm(
                s[:, None, :2] - others[None], axis=2)
            s = s[own.all(1)]
        if len(s) < 5:
            break
        xy = s[:, :2].mean(0)
        out.append((float(z + 0.015 * height), float(xy[0]), float(xy[1])))
        z += 0.03 * height
    return out


def _at(samples, z):
    zs = [s[0] for s in samples]
    if len(samples) < 2 or z > zs[-1]:
        return None
    return (float(np.interp(z, zs, [s[1] for s in samples])),
            float(np.interp(z, zs, [s[2] for s in samples])))


def leg_chain(p, name, foot, top_z, height, others):
    """Нога з трьох сегментів, як у псових/котячих/копитних (скелети
    собаки стоячи й сидячи, замовник 24.09.2026):
      передня — плече → лікоть → зап'ясток → лапа;
      задня  — кульшовий → колінний (вперед) → скакальний (назад) → лапа.
    Суглоби — на частках довжини ноги від землі (перед: зап'ясток 0.2,
    лікоть 0.52; зад: скакальний 0.3, колінний 0.6), місце в плані — центр
    перерізу сітки на тій висоті. Де переріз злився з тулубом або вийшов
    не за анатомією — анатомічний зсув: плечовий суглоб попереду ліктя,
    колінний попереду скакального, скакальний позаду лапи, кульшовий
    позаду колінного."""
    s = leg_samples(p, foot, top_z, height, others)
    fz, fx, fy = float(foot[2]), float(foot[0]), float(foot[1])
    L = top_z - fz
    front = name.startswith("front")
    fr = (0.2, 0.52) if front else (0.3, 0.6)
    z1, z2 = fz + fr[0] * L, fz + fr[1] * L
    j1 = _at(s, z1) or (fx, fy)
    j2 = _at(s, z2) or (j1[0], j1[1])
    if front:
        # зап'ясток майже над лапою; лікоть над зап'ястком або трохи позаду;
        # плече попереду ліктя (плечова кістка йде вниз-назад)
        y1 = float(np.clip(j1[1], fy - 0.05 * L, fy + 0.08 * L))
        y2 = float(np.clip(j2[1], y1 - 0.03 * L, y1 + 0.12 * L))
        y3 = y2 - 0.3 * (top_z - z2)
    else:
        # скакальний позаду лапи; колінний попереду скакального;
        # кульшовий позаду колінного (стегно йде вниз-вперед)
        y1 = max(j1[1], fy + 0.08 * L)
        y2 = min(j2[1], y1 - 0.25 * (z2 - z1))
        y3 = y2 + 0.45 * (top_z - z2)
    joints = [
        Vector((j2[0], y3, top_z)),       # плече / кульшовий
        Vector((j2[0], y2, z2)),          # лікоть / колінний
        Vector((j1[0], y1, z1)),          # зап'ясток / скакальний
        Vector((fx, fy, fz)),             # лапа
    ]
    return joints


def trace_leg(p, foot, top_z, height, others):
    """Центр ноги по шарах від лапи вгору (лише точки, ближчі до цієї
    лапи, ніж до інших) → пряма xy(z) → точка на висоті плеча/стегна.
    Нога похила: вертикальна кістка над лапою крутила ногу навколо
    точки перед грудьми — у «дибках» Attack лапи розмазувались."""
    xy = np.array(foot[:2], dtype=float)
    zs, cs = [foot[2]], [xy.copy()]
    others = np.array([o[:2] for o in others]) if others else np.zeros((0, 2))
    z = foot[2] + 0.03 * height
    while z < foot[2] + 0.75 * (top_z - foot[2]):
        s = p[(p[:, 2] >= z) & (p[:, 2] < z + 0.03 * height)]
        s = s[np.linalg.norm(s[:, :2] - xy, axis=1) < 0.07 * height]
        if len(others) and len(s):
            own = np.linalg.norm(s[:, :2] - xy, axis=1)[:, None] <= np.linalg.norm(
                s[:, None, :2] - others[None], axis=2)
            s = s[own.all(1)]
        if len(s) < 5:
            break
        xy = s[:, :2].mean(0)
        zs.append(z + 0.015 * height)
        cs.append(xy.copy())
        z += 0.03 * height
    if len(zs) < 3:
        return Vector((foot[0], foot[1], top_z))
    zs, cs = np.array(zs), np.array(cs)
    kx = np.polyfit(zs, cs[:, 0], 1)
    ky = np.polyfit(zs, cs[:, 1], 1)
    # Нахил не більший за 45° — шум верхніх шарів не кладе ногу.
    dz = top_z - foot[2]
    x = foot[0] + float(np.clip(np.polyval(kx, top_z) - foot[0], -dz, dz))
    y = foot[1] + float(np.clip(np.polyval(ky, top_z) - foot[1], -dz, dz))
    return Vector((x, y, top_z))


def auto_bones_quadruped(mesh, height, feet, profile):
    """Кістки з імен і напрямків `make_hare.BONES` (рухи звідти ж) за
    орієнтирами: лапи — з `level_by_inliers`, хребет — середина тулуба
    між передніми й задніми лапами, голова — все попереду передніх лап
    вище спини-мінус, вуха/роги — найвищі точки голови з кожного боку,
    хвіст — найдальша точка ззаду. Для перевірки — аркуш із кістками
    (`contact_sheet`)."""
    p = verts(mesh)
    f = {k: np.array(v) for k, v in feet.items()}
    front_ys = [f[k][1] for k in f if k.startswith("front")]
    hind_ys = [f[k][1] for k in f if k.startswith("hind")]
    # Другий прохід find_feet у level_by_inliers (після вирівнювання) може
    # звестись до єдиної ноги (низька присадкувата постава, ведмідь
    # 24.09.2026) — тоді дзеркало дає дублікат і ціла група "hind"/"front"
    # порожня. Замість NaN → падіння на percentile(порожній) — межа тіла.
    fy = float(np.mean(front_ys)) if front_ys else float(p[:, 1].min())
    hy = float(np.mean(hind_ys)) if hind_ys else float(p[:, 1].max())
    span = hy - fy
    mid = _band(p, 1, fy + 0.3 * span, hy - 0.3 * span)
    mid = mid[mid[:, 2] > 0.12 * height]
    if len(mid) < 5:
        mid = _band(p, 1, min(fy, hy), max(fy, hy))
        mid = mid[mid[:, 2] > 0.05 * height]
    zt, zb = np.percentile(mid[:, 2], 97), np.percentile(mid[:, 2], 3)
    cx = float(np.median(mid[:, 0]))
    spine = zb + 0.6 * (zt - zb)
    leg_top = zb + 0.35 * (zt - zb)

    front = p[(p[:, 1] < fy - 0.1 * span) & (p[:, 2] > zb)]
    if len(front) < 50:
        front = p[(p[:, 1] < fy) & (p[:, 2] > zb)]
    nose = front[np.argmin(front[:, 1])]
    fz = np.percentile(_band(p, 1, fy - 0.05 * span, fy + 0.15 * span)[:, 2], 90)
    neck = Vector((cx, fy - 0.05 * span, min(fz, spine + 0.35 * (zt - zb))))
    # Черепна частина: передня половина від шиї до носа, без рогів/вух
    # (вони вище за 85-й перцентиль голови).
    headp = front[front[:, 1] < (neck.y + nose[1]) / 2]
    zcap = np.percentile(headp[:, 2], 85) if len(headp) else nose[2]
    skull = headp[headp[:, 2] <= zcap].mean(0) if len(headp) else nose
    hips_head = Vector((cx, hy + 0.1 * span, spine))
    centre = Vector((cx, (fy + hy) / 2, spine))
    bones = [
        ("hips", tuple(hips_head), tuple(centre), None),
        ("chest", tuple(centre), tuple(neck), "hips"),
        ("head", tuple(neck), tuple(Vector(skull)), "chest"),
    ]
    if profile.get("ears", True):
        top = front[front[:, 2] > zcap]
        hc = Vector(skull)
        for side, sgn in ((".L", 1), (".R", -1)):
            s = top[(top[:, 0] - hc.x) * sgn > 0.01 * height] if len(top) else top
            if len(s) < 5:
                continue
            tip = Vector(s[np.argmax(s[:, 2])])
            root = hc.lerp(tip, 0.35)
            bones.append(("ear" + side, tuple(root), tuple(tip), "head"))
    tail = p[np.argmax(p[:, 1])]
    if tail[1] - hy > 0.08 * span:
        bones.append(("tail", tuple(hips_head), tuple(tail), "hips"))
    joints = profile.get("joints", True)
    for name, parent in (("front.L", "chest"), ("front.R", "chest"),
                         ("hind.L", "hips"), ("hind.R", "hips")):
        if name not in f:
            continue
        foot = f[name]
        others = [f[k] for k in f if k != name]
        if not joints:
            top = trace_leg(p, foot, leg_top, height, others)
            bones.append((name, tuple(top), tuple(foot), parent))
            continue
        # Верх ноги — плечовий/кульшовий суглоб: вище за черево, нижче
        # за хребет (передній 0.5, задній 0.55 висоти тулуба).
        tz = zb + (0.5 if name.startswith("front") else 0.55) * (zt - zb)
        j = leg_chain(p, name, foot, tz, height, others)
        bones.append((name, tuple(j[0]), tuple(j[1]), parent))
        bones.append((name + ".2", tuple(j[1]), tuple(j[2]), name))
        bones.append((name + ".3", tuple(j[2]), tuple(j[3]), name + ".2"))
    for ov in profile.get("bones_override", []):
        bones = [ov if b[0] == ov[0] else b for b in bones]
    return [(n, tuple(round(c, 4) for c in h), tuple(round(c, 4) for c in t), par)
            for n, h, t, par in bones]


def auto_bones_humanoid(mesh, height, profile):
    """Той самий набір, що в імпа/пагліна/зомбі (розділ 4а.2): hips,
    chest, head, arm.L/R, leg.L/R, [tail]. Промежина — найнижча точка
    сітки на осі між ногами; плечі — ширина тулуба на 70% від промежини
    до маківки; кисть — найдальша від плеча точка з кожного боку нижче
    плеча. `.L` — −X, як у готових гуманоїдів."""
    p = verts(mesh)
    low = p[p[:, 2] < 0.12 * height]
    cx = float(np.median(low[:, 0]))
    cy = float(np.median(p[:, 1]))
    # Ступні — два острівці біля землі (не «ліворуч/праворуч від центру»:
    # у кроці вони стоять одна за одною). Лівий — з меншим X.
    # Ступня — острівець ПІД тулубом: поділ плаща до землі лежить нижче
    # за ступні й тягнеться позаду, і «двома найбільшими» ставав саме він
    # (скелет, скелет-воїн 25.09.2026 — кістки ніг ішли в край плаща,
    # меч і щит рвались на рухах). Заміри: ступні — до 0.13 зросту від
    # осі тулуба по Y, поділ — від 0.19; кільце плаща ще й ширше за 0.6
    # зросту. Розміром самим не відрізнити: ступні пагліна й зомбі
    # (0.25-0.28) ширші за шматки плаща воїна. Ступні над поділом
    # (воїн: 8-9 см) — смуга росте, доки не знайде дві. Острівець із 1-2
    # клітинок — не ступня: кінчик меча воїна на −0.64 м ставав «лівою».
    body_y = float(np.median(_band(p, 2, 0.4 * height, 0.8 * height)[:, 1]))
    isl = []
    for band in (0.05, 0.08, 0.11, 0.14):
        sole = p[p[:, 2] < p[:, 2].min() + band * height]
        isl = sorted([t for t in _islands(sole, 0.025 * height)
                      if t[0] >= 3 and t[2] < 0.4 * height
                      and abs(t[1][1] - body_y) < 0.15 * height],
                     key=lambda t: -t[0])[:2]
        if len(isl) == 2 and abs(isl[0][1][0] - isl[1][1][0]) > 0.05 * height:
            break
        isl = []
    feet = {}
    if len(isl) == 2:
        for (n, xy, span, q), side in zip(sorted(isl, key=lambda t: t[1][0]), ("leg.L", "leg.R")):
            # Найнижча — біля медіани острівця: посох мага стоїть поруч
            # зі ступнею й зливається з нею в один острівець.
            q = q[np.linalg.norm(q[:, :2] - np.median(q[:, :2], axis=0), axis=1) < 0.08 * height]
            feet[side] = q[np.argmin(q[:, 2])]
        cx = float((feet["leg.L"][0] + feet["leg.R"][0]) / 2)
    else:
        for side, sgn in (("leg.L", -1), ("leg.R", 1)):
            q = low[(low[:, 0] - cx) * sgn > 0]
            if len(q):
                feet[side] = q[np.argmin(q[:, 2])]
    col = p[np.abs(p[:, 0] - cx) < 0.03 * height]
    zs = np.sort(col[:, 2])
    gaps = np.where(np.diff(zs) > 0.02 * height)[0]
    crotch = float(zs[gaps[-1] + 1]) if len(gaps) and zs[gaps[-1] + 1] < 0.7 * height else 0.45 * height
    top = float(np.percentile(col[:, 2], 99.5))
    zs_sh = crotch + 0.7 * (top - crotch)
    neck = crotch + 0.8 * (top - crotch)
    band = _band(p, 2, zs_sh - 0.04 * height, zs_sh + 0.02 * height)
    half = float(np.percentile(np.abs(band[:, 0] - cx), 60)) if len(band) else 0.12 * height
    ty = float(np.median(_band(p, 2, crotch, neck)[:, 1]))
    bones = [
        ("hips", (cx, ty, crotch), (cx, ty, crotch + 0.35 * (neck - crotch)), None),
        ("chest", (cx, ty, crotch + 0.35 * (neck - crotch)), (cx, ty, neck), "hips"),
        ("head", (cx, ty, neck), (cx, ty, top), "chest"),
    ]
    for side, sgn in (("arm.L", -1), ("arm.R", 1)):
        sh = Vector((cx + sgn * half * 0.9, ty, zs_sh))
        # Кисть — найнижча точка ЗА шириною плечей (не «найдальша від
        # плеча»: нею ставало товсте стегно зомбі, рука йшла до коліна).
        # Діапазон — від трохи нижче промежини до плеча (нижче — широко
        # розставлені ноги); спершу найдальша вбік точка (рука), тоді
        # найнижча точка поруч із нею (кисть; зброя в руці — теж сюди).
        q = p[((p[:, 0] - cx) * sgn > half * 1.05) & (p[:, 2] < zs_sh - 0.05 * height)
              & (p[:, 2] > crotch - 0.12 * height)
              # у межах досяжності руки: кінці списа/посоха далі — не кисть
              & (np.linalg.norm(p - np.array(sh), axis=1) < 0.42 * height)
              & (np.abs(p[:, 0] - cx) < half + 0.22 * height)
              # не позаду тулуба: там плащ — кисть скелета йшла в нього
              # (y +0.31 проти руків'я меча на −0.15, 25.09.2026)
              & (p[:, 1] < ty + 0.05 * height)]
        if len(q):
            q0 = q[np.argmax((q[:, 0] - cx) * sgn)]
            arm = q[np.linalg.norm(q[:, :2] - q0[:2], axis=1) < 0.12 * height]
            hand = Vector(arm[np.argmin(arm[:, 2])])
            if not profile.get("joints", True):
                bones.append((side, tuple(sh), tuple(hand), "chest"))
                continue
            # Лікоть — посередині, трохи позаду (рука згинається вперед).
            elbow = sh.lerp(hand, 0.5) + Vector((0, 0.03 * height, 0))
            bones.append((side, tuple(sh), tuple(elbow), "chest"))
            bones.append((side + ".2", tuple(elbow), tuple(hand), side))
    for side in ("leg.L", "leg.R"):
        if side not in feet:
            continue
        ft = feet[side]
        hip = Vector((ft[0] * 0.6 + cx * 0.4, ty, crotch))
        if not profile.get("joints", True):
            bones.append((side, tuple(hip), tuple(ft), "hips"))
            continue
        # Коліно й щиколотка — центр перерізу ноги на висоті (0.5 і 0.12
        # від стегна до землі); коліно не позаду лінії стегно-стопа
        # (вперед згинається), щиколотка над стопою чи трохи позаду.
        other = [feet[k] for k in feet if k != side]
        smp = leg_samples(p, ft, crotch, height, other)
        L = crotch - float(ft[2])
        kz, az = float(ft[2]) + 0.5 * L, float(ft[2]) + 0.12 * L
        k_xy = _at(smp, kz) or (float(hip.x + ft[0]) / 2, float(hip.y + ft[1]) / 2)
        a_xy = _at(smp, az) or (float(ft[0]), float(ft[1]))
        line_y = float(hip.y + (ft[1] - hip.y) * (crotch - kz) / max(L, 1e-6))
        knee = Vector((k_xy[0], min(k_xy[1], line_y - 0.01 * height), kz))
        ankle = Vector((a_xy[0], max(a_xy[1], float(ft[1])), az))
        bones.append((side, tuple(hip), tuple(knee), "hips"))
        bones.append((side + ".2", tuple(knee), tuple(ankle), side))
        bones.append((side + ".3", tuple(ankle), tuple(ft), side + ".2"))
    if profile.get("tail"):
        # Хвіст росте від куприка й висить нижче за нього — не найдальша
        # точка ззаду взагалі (у гнола нею була гілка за спиною на 1.5 м).
        q = p[(p[:, 2] > 0.1 * height) & (p[:, 2] < crotch + 0.15 * height)
              & (np.abs(p[:, 0] - cx) < 0.3 * height)]
        if len(q):
            t = q[np.argmax(q[:, 1])]
            if t[1] - ty > 0.1 * height:
                bones.append(("tail", (cx, ty, crotch), tuple(t), "hips"))
    for ov in profile.get("bones_override", []):
        bones = [ov if b[0] == ov[0] else b for b in bones]
    return [(n, tuple(round(float(c), 4) for c in h), tuple(round(float(c), 4) for c in t), par)
            for n, h, t, par in bones]


def normalize_roll(skeleton):
    """Вісь X кожної кістки — світовий +X (конвенція зайця, під яку
    написані рухи; див. докстрінг модуля). Кістка, що сама лежить уздовж
    X (крило, розведена рука), — лишається як є."""
    bpy.context.view_layer.objects.active = skeleton
    bpy.ops.object.mode_set(mode="EDIT")
    X = Vector((1, 0, 0))
    for eb in skeleton.data.edit_bones:
        y = (eb.tail - eb.head).normalized()
        if abs(y.dot(X)) > 0.9:
            continue
        eb.align_roll(X.cross(y).normalized())
    bpy.ops.object.mode_set(mode="OBJECT")


def rig(mesh, bones):
    skeleton = hare.armature(bones)
    normalize_roll(skeleton)
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    skeleton.select_set(True)
    bpy.context.view_layer.objects.active = skeleton
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    fixed = by_distance(mesh, skeleton)
    add_hands(skeleton)
    return skeleton, fixed


def rigid(mesh, bone, a, b, radius):
    """Зброя не гнеться: вершини ближче `radius` до відрізка a→b (руків'я
    → вістря) — лише на `bone` з вагою 1. Довге лезо скелета між рукою й
    ногами брало ваги стегон і на рухах гнулось та двоїлось (25.09.2026).
    Повертає, скільки вершин переписано."""
    a, b = Vector(a), Vector(b)
    ab = b - a
    g = mesh.vertex_groups.get(bone) or mesh.vertex_groups.new(name=bone)
    n = 0
    for v in mesh.data.vertices:
        co = mesh.matrix_world @ v.co
        t = max(0.0, min(1.0, (co - a).dot(ab) / ab.length_squared))
        if (co - (a + ab * t)).length >= radius:
            continue
        for e in list(v.groups):
            mesh.vertex_groups[e.group].remove([v.index])
        g.add([v.index], 1.0, "REPLACE")
        n += 1
    return n


def cut_rigid(mesh, skeleton, bone, keep=0.08):
    """Відрізати жорстку зброю від решти сітки: Pixal3D зшиває посох із
    плащем і череп на посоху з каптуром там, де вони торкались, — на
    рухах ці грані тягнуться полотном (скелет-маг, 25.09.2026). Грань із
    вершинами і «лише на `bone`», і інших — видаляється, крім тих, що
    ближче `keep` до кінця кістки (кисть тримає зброю). Скільки видалено."""
    import bmesh
    g = mesh.vertex_groups[bone].index
    hand = skeleton.matrix_world @ skeleton.data.bones[bone].tail_local
    only = set()
    for v in mesh.data.vertices:
        if len(v.groups) == 1 and v.groups[0].group == g and v.groups[0].weight > 0.999:
            only.add(v.index)
    bm = bmesh.new()
    bm.from_mesh(mesh.data)
    bad = [f for f in bm.faces
           if 0 < sum(v.index in only for v in f.verts) < len(f.verts)
           and ((mesh.matrix_world @ f.calc_center_median()) - hand).length > keep]
    bmesh.ops.delete(bm, geom=bad, context="FACES_ONLY")
    bm.to_mesh(mesh.data)
    bm.free()
    return len(bad)


def add_hands(skeleton):
    """Кисть — кістка-точка на кінці передпліччя (`arm.L.2` → `hand.L`),
    щоб гра чіпляла до неї окрему річ: лук скелета-лучника (25.09.2026).
    У glTF кінця кістки немає — лише початок, тому потрібна своя кістка.
    Не деформує (групи вершин немає, `use_deform` вимкнено) — ваги й
    рухи ті самі. Додається після ваг: інакше «тепло» роздало б їй
    вершини."""
    arms = [b.name for b in skeleton.data.bones if b.name in ("arm.L.2", "arm.R.2")]
    if not arms:
        return
    bpy.context.view_layer.objects.active = skeleton
    bpy.ops.object.mode_set(mode="EDIT")
    eb = skeleton.data.edit_bones
    for name in arms:
        arm = eb[name]
        hand = eb.new(name.replace("arm", "hand").replace(".2", ""))
        hand.head = arm.tail
        hand.tail = arm.tail + (arm.tail - arm.head).normalized() * 0.08 * arm.length
        hand.roll = arm.roll
        hand.parent = arm
        hand.use_connect = True
        hand.use_deform = False
    bpy.ops.object.mode_set(mode="OBJECT")


def by_distance(mesh, skeleton):
    """Вершинам без ваг («тепло» не впоралось) — 1/d⁴ до двох найближчих
    кісток."""
    bones = [(b.name, Vector(b.head_local), Vector(b.tail_local)) for b in skeleton.data.bones]
    groups = {n: mesh.vertex_groups.get(n) or mesh.vertex_groups.new(name=n) for n, _, _ in bones}
    fixed = 0
    for v in mesh.data.vertices:
        if sum(e.weight for e in v.groups) > 0.01:
            continue
        near = []
        for n, a, b in bones:
            ab = b - a
            t = max(0.0, min(1.0, (v.co - a).dot(ab) / ab.length_squared))
            near.append(((v.co - (a + ab * t)).length, n))
        near.sort()
        ws = [(1.0 / max(d, 0.005) ** 4, n) for d, n in near[:2]]
        tot = sum(w for w, _ in ws)
        for w, n in ws:
            groups[n].add([v.index], w / tot, "REPLACE")
        fixed += 1
    log("ваги за відстанню: %d з %d" % (fixed, len(mesh.data.vertices)))
    return fixed


# ---------------------------------------------------------------- земля

def min_z(mesh, rig_obj, action, frame):
    rig_obj.animation_data.action = bpy.data.actions[action]
    bpy.context.scene.frame_set(frame)
    dg = bpy.context.evaluated_depsgraph_get()
    ev = mesh.evaluated_get(dg)
    me = ev.to_mesh()
    n = len(me.vertices)
    a = np.empty(n * 3)
    me.vertices.foreach_get("co", a)
    ev.to_mesh_clear()
    return float((a.reshape(n, 3) @ np.array(mesh.matrix_world.to_3x3()).T)[:, 2].min()
                 + mesh.matrix_world.translation.z)


def _hips_vertical(rig_obj):
    """Яка локальна вісь `location` кістки hips рухає тіло по світовому Z
    і з яким знаком — міряємо, не припускаємо."""
    pb = rig_obj.pose.bones["hips"]
    best = None
    for i in range(3):
        pb.location = (0, 0, 0)
        bpy.context.view_layer.update()
        z0 = (rig_obj.matrix_world @ pb.head).z
        v = [0, 0, 0]
        v[i] = 0.1
        pb.location = v
        bpy.context.view_layer.update()
        dz = ((rig_obj.matrix_world @ pb.head).z - z0) / 0.1
        if best is None or abs(dz) > abs(best[1]):
            best = (i, dz)
    pb.location = (0, 0, 0)
    return best


def fix_ground(mesh, rig_obj, grounded, tol=0.006):
    """Для кожного ключового кадру кожного руху: якщо найнижча вершина
    під землею — підняти `hips`; якщо кадр у `grounded` (звір має
    стояти/лежати, не стрибати) і висить — опустити. Два проходи
    (інтерполяція між ключами трохи зсуває сусідів)."""
    axis, k = _hips_vertical(rig_obj)
    report = {}
    for _ in range(2):
        for act in bpy.data.actions:
            name = act.name
            fcu = next((c for c in hare.curves(act)
                        if c.data_path == 'pose.bones["hips"].location' and c.array_index == axis), None)
            if fcu is None:
                continue
            for kp in fcu.keyframe_points:
                fr = int(round(kp.co.x))
                z = min_z(mesh, rig_obj, name, fr)
                g = grounded.get(name, ())
                must = g == "all" or fr in g
                if z < -tol or (must and z > tol):
                    d = -z / k
                    kp.co.y += d
                    kp.handle_left.y += d
                    kp.handle_right.y += d
            fcu.update()
    for act in bpy.data.actions:
        fcu = next((c for c in hare.curves(act)
                    if c.data_path == 'pose.bones["hips"].location' and c.array_index == axis), None)
        frames = sorted({int(round(kp.co.x)) for kp in fcu.keyframe_points}) if fcu else [1]
        report[act.name] = {fr: round(min_z(mesh, rig_obj, act.name, fr), 4) for fr in frames}
    rig_obj.animation_data.action = bpy.data.actions["Idle"]
    bpy.context.scene.frame_set(1)
    bad = {a: {f: z for f, z in fr.items() if z < -0.01} for a, fr in report.items()}
    bad = {a: v for a, v in bad.items() if v}
    log("земля: %s" % ("усі ключові кадри в нормі" if not bad else "ПІД ЗЕМЛЕЮ %s" % bad))
    return report


# ---------------------------------------------------------------- рухи чотирилапого з суглобами

def _legs(d):
    """d: {"F": (плече, лікоть, зап'ясток), "H": (стегно, коліно, скакальний)}
    для однієї ноги → ключі кісток. Кути в градусах навколо X кістки
    (після normalize_roll): + — кінець кістки назад, − — вперед."""
    return d


def _pose(front_l, front_r, hind_l, hind_r, extra=None):
    k = {}
    for side, (a, b, c) in (("front.L", front_l), ("front.R", front_r),
                            ("hind.L", hind_l), ("hind.R", hind_r)):
        k[side] = ((a, 0, 0), (0, 0, 0))
        k[side + ".2"] = ((b, 0, 0), (0, 0, 0))
        k[side + ".3"] = ((c, 0, 0), (0, 0, 0))
    if extra:
        k.update(extra)
    return k


# Фази кроку для однієї ноги (плече/стегно, лікоть/коліно, зап'ясток/скакальний).
F_REACH, F_MID, F_PUSH, F_SWING = (-18, 4, -4), (0, 0, 0), (18, -4, 14), (-6, 38, 46)
H_REACH, H_MID, H_PUSH, H_SWING = (-18, 10, -8), (0, 0, 0), (14, -8, 16), (-26, 44, -36)
STAND = (0, 0, 0)


def quadruped_actions(rig_obj, has_ears=True):
    """Рухи для ніг із суглобами (`leg_chain`). Хода — рись: діагональні
    пари (передня ліва + задня права) рухаються разом. Атака — кидок з
    укусом (присів → стрибок уперед із простягнутими лапами → укус →
    назад); Death — падає набік, лапи обм'якають і підгинаються."""
    rest = {}
    ears = has_ears and "ear.L" in rig_obj.pose.bones
    idle_ear = {"ear.L": ((-15, 0, 0), (0, 0, 0))} if ears else {}
    hare.action(rig_obj, "Idle", 48, {
        1: rest,
        12: {"chest": ((-2, 0, 0), (0, 0, 0)), "head": ((0, 0, 8), (0, 0, 0)), **idle_ear},
        24: {"chest": ((0, 0, 0), (0, 0, 0)), "head": ((-3, 0, 0), (0, 0, 0))},
        36: {"chest": ((-2, 0, 0), (0, 0, 0)), "head": ((0, 0, -8), (0, 0, 0))},
        48: rest})
    hare.action(rig_obj, "Walk", 24, {
        1: _pose(F_REACH, F_PUSH, H_PUSH, H_REACH),
        7: _pose(F_MID, F_SWING, H_SWING, H_MID, {"head": ((3, 0, 0), (0, 0, 0))}),
        13: _pose(F_PUSH, F_REACH, H_REACH, H_PUSH),
        19: _pose(F_SWING, F_MID, H_MID, H_SWING, {"head": ((3, 0, 0), (0, 0, 0))}),
        25: _pose(F_REACH, F_PUSH, H_PUSH, H_REACH)})
    crouch = _pose((-8, 30, 26), (-8, 30, 26), (-22, 40, -30), (-22, 40, -30),
                   {"head": ((12, 0, 0), (0, 0, 0)), "hips": ((-6, 0, 0), (0, 0, 0))})
    leap = _pose((-55, -10, -25), (-45, -5, -20), (30, -20, 30), (35, -20, 30),
                 {"head": ((-18, 0, 0), (0, 0, 0)), "chest": ((-6, 0, 0), (0, 0, 0))})
    bite = _pose((-30, 10, 0), (-25, 10, 0), (10, -5, 10), (12, -5, 10),
                 {"head": ((22, 0, 0), (0, 0, 0)), "chest": ((6, 0, 0), (0, 0, 0))})
    hare.action(rig_obj, "Attack", 20, {1: rest, 5: crouch, 10: leap, 13: bite, 20: rest})
    limp = _pose((-20, 25, 30), (-10, 15, 20), (-25, 35, -25), (-15, 20, -15),
                 {"hips": ((0, 85, 0), (0, 0, 0)), "head": ((20, 0, 0), (0, 0, 0)),
                  "chest": ((0, 0, 0), (0, 0, 0))})
    hare.action(rig_obj, "Death", 30, {1: rest, 30: limp})
    rig_obj.animation_data.action = bpy.data.actions["Idle"]


QUAD_GROUNDED = {"Idle": "all", "Walk": "all", "Attack": (1, 5, 20), "Death": (1, 30)}


# ---------------------------------------------------------------- рухи гуманоїда

def humanoid_actions(rig_obj):
    """Рухи двоногого з суглобами (коліно, щиколотка, лікоть), на
    `normalize_roll`: для кістки донизу + — кінець назад, − — вперед;
    для кістки вгору (hips, chest) + — нахил уперед. Атака — укол
    правою рукою й удар держаком (гнол-мисливець; для кулачних бійців
    той самий рух читається як удар); смерть — на коліна, тоді ниць
    (бестіарій гнола; для решти теж природніше за падіння навзнак).
    Скелет без суглобів — старі рухи однією кісткою."""
    rest = {}
    pb = rig_obj.pose.bones
    if "leg.L.2" not in pb:
        return _humanoid_actions_simple(rig_obj)

    def k(**b):
        return {n.replace("_", "."): ((a, 0, c), (0, 0, 0)) for n, (a, c) in
                {n: (v if isinstance(v, tuple) else (v, 0)) for n, v in b.items()}.items()
                if n.replace("_", ".") in pb}

    hare.action(rig_obj, "Idle", 40, {
        1: rest,
        20: k(chest=-2, head=3, arm_L=3, arm_R=3, leg_L_2=4, leg_R_2=4, leg_L=-2, leg_R=-2),
        40: rest})
    swing = dict(thigh=-28, shin=45, foot=-15)
    plant = dict(thigh=14, shin=4, foot=0)

    def step(l, r, al, ar):
        return k(leg_L=l["thigh"], leg_L_2=l["shin"], leg_L_3=l["foot"],
                 leg_R=r["thigh"], leg_R_2=r["shin"], leg_R_3=r["foot"],
                 arm_L=al, arm_L_2=-10, arm_R=ar, arm_R_2=-10)
    mid = dict(thigh=-4, shin=8, foot=0)
    hare.action(rig_obj, "Walk", 24, {
        1: step(swing, plant, 12, -12),
        7: step(mid, mid, 0, 0),
        13: step(plant, swing, -12, 12),
        19: step(mid, mid, 0, 0),
        25: step(swing, plant, 12, -12)})
    hare.action(rig_obj, "Attack", 20, {
        1: rest,
        6: k(arm_R=25, arm_R_2=-70, chest=(-6, -10), leg_L=-10, leg_L_2=15, leg_R=10, leg_R_2=10),
        10: k(arm_R=-60, arm_R_2=-5, arm_L=-35, arm_L_2=-30, chest=(12, 12),
              leg_L=-25, leg_L_2=25, leg_R=15, leg_R_2=5),
        14: k(arm_R=-25, arm_R_2=-45, arm_L=-20, arm_L_2=-50, chest=(8, -8),
              leg_L=-18, leg_L_2=20, leg_R=12, leg_R_2=5),
        20: rest})
    kneel = k(leg_L=-35, leg_L_2=100, leg_L_3=-10, leg_R=-35, leg_R_2=100, leg_R_3=-10,
              chest=10, head=10, arm_L=10, arm_R=10, arm_L_2=-20, arm_R_2=-20)
    down = dict(kneel)
    down.update(k(hips=75, chest=10, head=-20, arm_L=-60, arm_R=-60))
    hare.action(rig_obj, "Death", 24, {1: rest, 12: kneel, 24: down})
    rig_obj.animation_data.action = bpy.data.actions["Idle"]


def _humanoid_actions_simple(rig_obj):
    rest = {}
    hare.action(rig_obj, "Idle", 40, {
        1: rest,
        20: {"chest": ((3, 0, 0), (0, 0, 0)), "head": ((-4, 0, 0), (0, 0, 0)),
             "arm.L": ((3, 0, 0), (0, 0, 0)), "arm.R": ((3, 0, 0), (0, 0, 0))},
        40: rest})
    hare.action(rig_obj, "Walk", 24, {
        1: {"leg.L": ((20, 0, 0), (0, 0, 0)), "leg.R": ((-20, 0, 0), (0, 0, 0)),
            "arm.L": ((-15, 0, 0), (0, 0, 0)), "arm.R": ((15, 0, 0), (0, 0, 0))},
        7: rest,
        13: {"leg.L": ((-20, 0, 0), (0, 0, 0)), "leg.R": ((20, 0, 0), (0, 0, 0)),
             "arm.L": ((15, 0, 0), (0, 0, 0)), "arm.R": ((-15, 0, 0), (0, 0, 0))},
        19: rest,
        24: {"leg.L": ((20, 0, 0), (0, 0, 0)), "leg.R": ((-20, 0, 0), (0, 0, 0)),
             "arm.L": ((-15, 0, 0), (0, 0, 0)), "arm.R": ((15, 0, 0), (0, 0, 0))}})
    hare.action(rig_obj, "Attack", 20, {
        1: rest,
        7: {"arm.R": ((35, 0, 0), (0, 0, 0)), "chest": ((-8, 0, 0), (0, 0, 0))},
        11: {"arm.R": ((-35, 0, 0), (0, 0, 0)), "chest": ((12, 0, 0), (0, 0, 0)),
             "arm.L": ((-10, 0, 0), (0, 0, 0))},
        20: rest})
    hare.action(rig_obj, "Death", 24, {
        1: rest,
        24: {"hips": ((-80, 0, 0), (0, 0, 0)), "chest": ((-10, 0, 0), (0, 0, 0)),
             "head": ((-15, 0, 0), (0, 0, 0)),
             "arm.L": ((20, 0, 0), (0, 0, 0)), "arm.R": ((20, 0, 0), (0, 0, 0))}})
    rig_obj.animation_data.action = bpy.data.actions["Idle"]


HARE_GROUNDED = {"Idle": "all", "Walk": (1, 13, 16), "Attack": (1, 20), "Death": (1, 30)}
HUMANOID_GROUNDED = {"Idle": "all", "Walk": "all", "Attack": "all", "Death": (1, 12, 24)}


# ---------------------------------------------------------------- вихід

def export(out):
    bpy.ops.export_scene.gltf(
        filepath=out, export_format="GLB", export_yup=True,
        export_apply=True, export_animations=True,
        export_animation_mode="ACTIONS", export_force_sampling=True,
        export_def_bones=False, export_skins=True,
        export_texcoords=True, export_image_format="JPEG",
        export_jpeg_quality=90)
