"""Заміри сирої сітки Pixal3D для розстановки кісток на гуманоїдах —
швидша заміна ортографічних видів (`ortho_grid.py`, для чотирилапих)
на двоногих: Z-гістограма густини вершин (тіло проти рідких рогів/
кінцівок/зброї) і центроїди лівого/правого боку в потрібних Z-смугах.
Перевірено на імпі/паглін/зомбі (усі — з першого разу без ортовидів).

Крок А6 `spec/генерація-3d-моделей-монстрів.md`, підготовка `BONES` для
`make_<вид>_scan.py`.

Завжди друкує Z-гістограму (60 кошиків, разом із розмахом X у кожному —
рідкі стовпці зі зсувом лише в один бік по X зазвичай зброя/хвіст, не
тіло). За потреби — іменовані смуги для центроїдів лівого/правого боку
(вершина Z вже присунута до 0 = ступні):

Запуск (з каталогу проєкту):
    blender --background --python tools/blender/scan_landmarks.py -- \\
        art/monsters/<назва>-3d/pixal3d-01.glb \\
        --band hand:0.44:0.58 --band foot:0.0:0.05
"""
import sys

import bpy
from mathutils import Vector


def histogram(vs, nbins=60):
    zmin = min(v.z for v in vs)
    zmax = max(v.z for v in vs)
    size = (zmax - zmin) / nbins
    counts = [0] * nbins
    xs_by_bin = [[] for _ in range(nbins)]
    for v in vs:
        b = min(nbins - 1, int((v.z - zmin) / size))
        counts[b] += 1
        xs_by_bin[b].append(v.x)
    maxc = max(counts)
    print("[заміри] Z-гістограма густини (зсунуто: ступні = 0)")
    for i, c in enumerate(counts):
        z = (i + 0.5) * size
        bar = "#" * int(60 * c / max(maxc, 1))
        xs = xs_by_bin[i]
        span = "minx=%6.3f maxx=%6.3f" % (min(xs), max(xs)) if xs else ""
        print("%6.3f  %5d  %-60s %s" % (z, c, bar, span))


def band(vs, lo, hi):
    return [v for v in vs if lo <= v.z <= hi]


def side(pts, positive):
    return [v for v in pts if (v.x > 0) == positive]


def centroid(pts):
    return sum(pts, Vector()) / len(pts) if pts else None


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    path = argv[0]
    bands = []
    i = 1
    while i < len(argv):
        if argv[i] == "--band":
            name, lo, hi = argv[i + 1].split(":")
            bands.append((name, float(lo), float(hi)))
            i += 2
        else:
            i += 1

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    mesh = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
    bpy.context.view_layer.objects.active = mesh
    mesh.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    vs = [v.co.copy() for v in mesh.data.vertices]
    zmin = min(v.z for v in vs)
    vs = [Vector((v.x, v.y, v.z - zmin)) for v in vs]

    histogram(vs)

    for name, lo, hi in bands:
        b = band(vs, lo, hi)
        print("\n[заміри] смуга %s (%.3f–%.3f), %d вершин" % (name, lo, hi, len(b)))
        for pos in (False, True):
            s = side(b, pos)
            if not s:
                continue
            s.sort(key=lambda v: abs(v.x), reverse=True)
            top = s[:max(1, int(len(s) * 0.1))]
            trimmed = sorted(s, key=lambda v: abs(v.x))[:max(1, int(len(s) * 0.85))]
            print("  %s: центр-крайні=%s (n=%d) · центр-урізаний=%s"
                  % ("R" if pos else "L", tuple(round(c, 4) for c in centroid(top)),
                     len(s), tuple(round(c, 4) for c in centroid(trimmed))))


if __name__ == "__main__":
    main()
