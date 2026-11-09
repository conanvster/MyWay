"""Ваги рук за скелетом, поставленим вручну (09.11.2026).

Замовник ставить суглоби руки й пальців у сітку (`skelet_vruchnu.py` →
`skelet-vruchnu.blend`); тут для вершин руки, кисті й пальців ваги
перераховуються за відстанню до кісток свого боку (найближчі три, ступінь 4),
частка ключиці й хребта на плечі лишається як була; 2 проходи згладжування.

    blender -b <skelet-vruchnu.blend> -P tools/blender/vagy_z_ruchnoho.py -- <вихід.blend>
"""
import sys

import bpy
import numpy as np

VYKHID = sys.argv[sys.argv.index("--") + 1]
rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
rig.data.pose_position = "REST"
tilo = next(o for o in bpy.data.objects if o.type == "MESH" and o.name == "Тіло")
me = tilo.data
mw = rig.matrix_world
ROD = ("upperarm", "lowerarm", "hand", "thumb", "index", "middle", "ring", "pinky")


def log(*a):
    print("[ваги вручну]", *a, flush=True)


vg = {g.index: g.name for g in tilo.vertex_groups}
CO = np.array([(tilo.matrix_world @ v.co)[:] for v in me.vertices])
STARI = [{vg[g.group]: g.weight for g in v.groups} for v in me.vertices]
sus = [[] for _ in range(len(CO))]
for e in me.edges:
    a, b = e.vertices
    sus[a].append(b)
    sus[b].append(a)
NOVI = {}
for bik in ("l", "r"):
    lanc = [b for b in rig.data.bones if b.name.endswith("_" + bik) and b.name.split("_")[0] in ROD]
    # запобіжник: кістка поза сіткою (палець не знайдено) — без ваг, інакше
    # вершини тягнуться до неї шипами (основи орків 09.11)
    from mathutils.kdtree import KDTree as _KD
    _kd = _KD(len(CO))
    for _i, _c in enumerate(CO):
        _kd.insert(_c, _i)
    _kd.balance()
    # лише пальці: середина кістки плеча чи передпліччя в товстій руці лежить
    # глибше 2 см від поверхні — запобіжник прибирав ваги з усієї руки (09.11)
    poza = [b.name for b in lanc if b.name.split("_")[0] in ("thumb", "index", "middle", "ring", "pinky")
            and _kd.find((mw @ ((b.head_local + b.tail_local) / 2)))[2] > 0.02]
    if poza:
        log("бік %s: кістки поза сіткою, без ваг: %s" % (bik, poza))
    lanc = [b for b in lanc if b.name not in poza]
    H = np.array([np.array((mw @ b.head_local)[:]) for b in lanc])
    T = np.array([np.array((mw @ b.tail_local)[:]) for b in lanc])
    imena = [b.name for b in lanc]
    obl = [i for i, w in enumerate(STARI) if sum(x for k, x in w.items() if k in imena) > 0.05]
    for i in obl:
        p = CO[i]
        ab = T - H
        t = np.clip(((p - H) * ab).sum(1) / (ab * ab).sum(1), 0, 1)
        d = np.linalg.norm(p - (H + t[:, None] * ab), axis=1)
        top = np.argsort(d)[:3]
        w = 1.0 / (d[top] + 0.004) ** 4
        w /= w.sum()
        NOVI[i] = {imena[k]: float(x) for k, x in zip(top, w)}
    log("бік %s: кісток %d, вершин руки %d" % (bik, len(lanc), len(obl)))
for _ in range(2):
    N2 = {}
    for i, w in NOVI.items():
        ss = [NOVI[j] for j in sus[i] if j in NOVI]
        acc = {k: 0.6 * x for k, x in w.items()}
        for sw in ss:
            for k, x in sw.items():
                acc[k] = acc.get(k, 0.0) + 0.4 * x / len(ss)
        N2[i] = acc if ss else w
    NOVI = N2
grupy = {g.name: g for g in tilo.vertex_groups}
for i, w in NOVI.items():
    stari = STARI[i]
    chast = sum(x for k, x in stari.items() if k.split("_")[0] in ROD)
    inshi = {k: x for k, x in stari.items() if k.split("_")[0] not in ROD}
    nova = dict(inshi)
    for k, x in w.items():
        nova[k] = nova.get(k, 0.0) + chast * x
    top = sorted(nova.items(), key=lambda kv: -kv[1])[:4]
    sm = sum(x for _, x in top) or 1.0
    for k in stari:
        if k in grupy:
            grupy[k].remove([i])
    for k, x in top:
        if k not in grupy:
            grupy[k] = tilo.vertex_groups.new(name=k)
        grupy[k].add([i], x / sm, "REPLACE")
# шви розгортки: вершини в одній точці — різні вершини; ваги, згладжені по
# ребрах, по різні боки шва розходились, і в ударі шов відкривався наскрізною
# щілиною (замовник 09.11). Тут — однакові ваги для всіх вершин точки.
from mathutils.kdtree import KDTree  # noqa: E402
kd = KDTree(len(CO))
for i, c in enumerate(CO):
    kd.insert(c, i)
kd.balance()
vg = {g.index: g.name for g in tilo.vertex_groups}
POTOCHNI = [{vg[g.group]: g.weight for g in v.groups} for v in me.vertices]
bachyly = np.zeros(len(CO), bool)
zrivniano = 0
for i in range(len(CO)):
    if bachyly[i]:
        continue
    grupa = [j for _, j, _ in kd.find_range(CO[i], 0.0005)]
    bachyly[grupa] = True
    if len(grupa) < 2:
        continue
    acc = {}
    for j in grupa:
        for k, x in POTOCHNI[j].items():
            acc[k] = acc.get(k, 0.0) + x / len(grupa)
    top = sorted(acc.items(), key=lambda kv: -kv[1])[:4]
    sm = sum(x for _, x in top) or 1.0
    for j in grupa:
        if POTOCHNI[j] == dict(top):
            continue
        for k in POTOCHNI[j]:
            grupy[k].remove([j])
        for k, x in top:
            if k not in grupy:
                grupy[k] = tilo.vertex_groups.new(name=k)
            grupy[k].add([j], x / sm, "REPLACE")
        zrivniano += 1
log("шви: вершин зрівняно %d" % zrivniano)
tilo.hide_select = False
rig.data.pose_position = "POSE"
bpy.ops.wm.save_as_mainfile(filepath=VYKHID)
log("→", VYKHID)
