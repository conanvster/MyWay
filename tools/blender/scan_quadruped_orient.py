"""Орієнтація + вирівнювання чотирилапої сітки Pixal3D і повний друк
орієнтирів для розстановки кісток — одним викликом, замість купи
одноразових скриптів на кожен вид (крок А6 `spec/
генерація-3d-моделей-монстрів.md`).

Робить те саме, що `orient()`/`level()` у `make_wolf_scan.py`, плюс:
- стійкий до викиду розрахунок нахилу (лапа, недобудована Pixal3D на
  затіненому боці референсу, виключається з розрахунку — знайдено на
  лисиці 24.09.2026, а не патчиться вручну);
- одразу друкує всі орієнтири (лапи, ніс, вуха, шия/груди, стегна,
  хвіст, холка) — не треба окремих скриптів під кожен вид.

Запуск (з каталогу проєкту):
    blender --background --python tools/blender/scan_quadruped_orient.py -- \\
        art/monsters/<назва>-3d/pixal3d-01.glb <HEIGHT> [чернетка.blend]
"""
import math
import sys

import bpy
from mathutils import Matrix, Vector


def load_mesh(source):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=source)
    mesh = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
    for other in list(bpy.context.scene.objects):
        if other is not mesh:
            bpy.data.objects.remove(other)
    bpy.context.view_layer.objects.active = mesh
    mesh.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return mesh


def orient(mesh, height):
    vs = [v.co.copy() for v in mesh.data.vertices]
    top = max(vs, key=lambda v: v.z)
    body = [v for v in vs if v.z < top.z - 0.35]
    cx = sum(v.x for v in body) / len(body)
    cy = sum(v.y for v in body) / len(body)
    sxx = sum((v.x - cx) ** 2 for v in body)
    syy = sum((v.y - cy) ** 2 for v in body)
    sxy = sum((v.x - cx) * (v.y - cy) for v in body)
    angle = 0.5 * math.atan2(2 * sxy, sxx - syy)
    axis = Vector((math.cos(angle), math.sin(angle)))
    if (top.xy - Vector((cx, cy))).dot(axis) < 0:
        axis = -axis
    yaw = math.atan2(axis.y, axis.x)
    mesh.data.transform(Matrix.Translation((-cx, -cy, 0)))
    mesh.data.transform(Matrix.Rotation(-math.pi / 2 - yaw, 4, "Z"))
    zs = [v.co.z for v in mesh.data.vertices]
    scale = height / (max(zs) - min(zs))
    mesh.data.transform(Matrix.Scale(scale, 4)
                        @ Matrix.Translation((0, 0, -min(zs))))


def _solve_tilt(feet, names, exclude):
    def avg(pts, pt_names):
        if exclude:
            pts = [p for p, n in zip(pts, pt_names) if n != exclude]
        return sum(pts, Vector()) / len(pts)

    front_pts = [feet[(False, False)], feet[(True, False)]]
    hind_pts = [feet[(False, True)], feet[(True, True)]]
    right_pts = [feet[(False, False)], feet[(False, True)]]
    left_pts = [feet[(True, False)], feet[(True, True)]]

    f = avg(front_pts, ["перед-права", "перед-ліва"])
    b = avg(hind_pts, ["зад-права", "зад-ліва"])
    pitch = math.atan2(f.z - b.z, b.y - f.y)
    r = avg(right_pts, ["перед-права", "зад-права"])
    l = avg(left_pts, ["перед-ліва", "зад-ліва"])
    roll = math.atan2(l.z - r.z, l.x - r.x)
    return pitch, roll


def _residual(feet, pitch, roll):
    """Наскільки рівно лягли чотири лапи після пробного нахилу (без
    зміни mesh) — менше розкид Z, краще рішення."""
    rx = Matrix.Rotation(pitch, 4, "X")
    ry = Matrix.Rotation(roll, 4, "Y")
    zs = [(ry @ rx @ p.to_4d()).z for p in feet.values()]
    return max(zs) - min(zs)


def level(mesh, height):
    vs = [v.co for v in mesh.data.vertices]
    cx = sum(v.x for v in vs) / len(vs)
    cy = sum(v.y for v in vs) / len(vs)
    feet = {}
    for v in vs:
        if abs(v.x - cx) < 0.03:
            continue
        key = (v.x > cx, v.y > cy)
        if key not in feet or v.z < feet[key].z:
            feet[key] = v.copy()
    if len(feet) < 4:
        print("[орієнтація] УВАГА: не всі 4 квадранти лап знайдено —", feet.keys())
        return 0.0

    names = {(False, False): "перед-права", (True, False): "перед-ліва",
             (False, True): "зад-права", (True, True): "зад-ліва"}
    zs = {names[k]: p.z for k, p in feet.items()}
    med = sorted(zs.values())[1:3]
    med_val = sum(med) / 2
    suspect = max(zs, key=lambda n: abs(zs[n] - med_val))

    # Пробуємо і без виключення, і з виключенням підозрілої лапи —
    # обираємо, що дає менший розкид Z по всіх чотирьох лапах ПІСЛЯ
    # нахилу (не з ким гірше на око, а міряти). На лисиці підозріла
    # лапа справді була недобудована (виключення дало кращий
    # результат); на рисі різниця виявилась дрібним шумом і виключення
    # тільки погіршило нахил — самоперевірка ловить обидва випадки.
    pitch0, roll0 = _solve_tilt(feet, names, None)
    res0 = _residual(feet, pitch0, roll0)
    pitch1, roll1 = _solve_tilt(feet, names, suspect)
    res1 = _residual(feet, pitch1, roll1)

    if res1 < res0 - 0.01:
        pitch, roll = pitch1, roll1
        print("[орієнтація] лапа %s не торкається землі в сирій сітці "
              "(z=%.3f, інші ~%.3f) — виключено з розрахунку нахилу "
              "(розкид %.3f м → %.3f м)" % (suspect, zs[suspect], med_val, res0, res1))
    else:
        pitch, roll = pitch0, roll0
        if abs(zs[suspect] - med_val) > 0.04:
            print("[орієнтація] лапа %s відхиляється (z=%.3f, інші ~%.3f), "
                  "але виключення не покращує розкид (%.3f м → %.3f м) — "
                  "рахувати по всіх чотирьох" % (suspect, zs[suspect], med_val, res0, res1))

    mesh.data.transform(Matrix.Rotation(pitch, 4, "X"))
    mesh.data.transform(Matrix.Rotation(roll, 4, "Y"))
    print("[орієнтація] вирівняно: тангаж %.1f°, крен %.1f°"
          % (math.degrees(pitch), math.degrees(roll)))
    zs2 = [v.co.z for v in mesh.data.vertices]
    scale = height / (max(zs2) - min(zs2))
    mesh.data.transform(Matrix.Scale(scale, 4)
                        @ Matrix.Translation((0, 0, -min(zs2))))
    ys = [v.co.y for v in mesh.data.vertices]
    shift = (max(ys) + min(ys)) / 2
    mesh.data.transform(Matrix.Translation((0, -shift, 0)))
    print("[орієнтація] зсув уздовж тулуба: %.3f м" % shift)
    return shift


def report(mesh):
    vs = [v.co.copy() for v in mesh.data.vertices]
    cx = sum(v.x for v in vs) / len(vs)
    cy = sum(v.y for v in vs) / len(vs)
    feet = {}
    for v in vs:
        if abs(v.x - cx) < 0.03:
            continue
        key = (v.x > cx, v.y > cy)
        if key not in feet or v.z < feet[key].z:
            feet[key] = v.copy()
    names = {(False, False): "front.R (перед-права)", (True, False): "front.L (перед-ліва)",
             (False, True): "hind.R (зад-права)", (True, True): "hind.L (зад-ліва)"}
    print("\n[орієнтири] --- лапи (кінчик кістки, torkannya zemli) ---")
    for k, name in names.items():
        p = feet.get(k)
        if p:
            print("  %-22s %s" % (name, tuple(round(c, 3) for c in p)))

    zmax = max(v.z for v in vs)
    hb = [v for v in vs if v.z > zmax * 0.55 and v.y < cy]
    if hb:
        nose = min(hb, key=lambda v: v.y)
        print("[орієнтири] ніс (мін Y, верхня половина z, y<cy)", tuple(round(c, 3) for c in nose))

    top_band = [v for v in vs if v.z > zmax * 0.8 and v.y < cy]
    if top_band:
        right_top = [v for v in top_band if v.x < cx]
        left_top = [v for v in top_band if v.x >= cx]
        if right_top:
            print("[орієнтири] вухо/маківка права (max z)", tuple(round(c, 3) for c in max(right_top, key=lambda v: v.z)))
        if left_top:
            print("[орієнтири] вухо/маківка ліва (max z)", tuple(round(c, 3) for c in max(left_top, key=lambda v: v.z)))

    tail_pts = [v for v in vs if v.y > cy + 0.1]
    if tail_pts:
        tail_tip = max(tail_pts, key=lambda v: v.y)
        print("[орієнтири] хвіст кінчик (max Y)", tuple(round(c, 3) for c in tail_tip))

    print("[орієнтири] bbox x", round(min(v.x for v in vs), 3), round(max(v.x for v in vs), 3))
    print("[орієнтири] bbox y", round(min(v.y for v in vs), 3), round(max(v.y for v in vs), 3))
    print("[орієнтири] bbox z", round(min(v.z for v in vs), 3), round(max(v.z for v in vs), 3))
    print("[орієнтири] центр x", round(cx, 3))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    source, height = argv[0], float(argv[1])
    mesh = load_mesh(source)
    orient(mesh, height)
    level(mesh, height)
    report(mesh)
    if len(argv) > 2:
        bpy.ops.wm.save_as_mainfile(filepath=argv[2])
        print("[орієнтація] збережено", argv[2])


if __name__ == "__main__":
    main()
