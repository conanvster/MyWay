"""Обгортання: топологія MPFB на форму скульпту (П-285, крок «орк», 11.11.2026).

    blender -b <основа MPFB.blend> -P tools/blender/obhortannia.py -- <скульпт.blend> <вихід.blend>
        [--рендер <тека>]

Вхід — основа MPFB (тіло `Human`, очі, брови, вії, ікла, білизна на скелеті `Human.rig`) і
скульпт із генератора 3D, ригований ТИМ САМИМ скелетом, підігнаним під його пропорції
(`rig_sitky.py`: об'єкти `Тіло` і `Human.rig`).

Що робить:
  1. Скелетне перенесення: кожна вершина всіх сіток основи їде за своїми кістками з пози й
     пропорцій основи в позу й пропорції скульпту (лінійне змішування за вагами шкіри);
     скелет основи отримує суглоби скульпту.
  2. Нежорстке притягування тіла до поверхні скульпту: найближча точка з перевіркою нормалі,
     поле зсувів згладжується по сітці (від грубого до дрібного). Голова, кисті й стопи
     лишаються від MPFB (обличчя, очі, пальці — чисті), шия, зап'ястя й щиколотки — плавний
     перехід.
  3. Білизна їде за найближчою вершиною тіла.
Скульпт у вихідний файл не потрапляє.
"""
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

A = sys.argv[sys.argv.index("--") + 1:]
SKULPT, VYKHID = os.path.abspath(A[0]), os.path.abspath(A[1])
RENDER = A[A.index("--рендер") + 1] if "--рендер" in A else ""
BEZ = ()            # голова теж притягується (обличчя орка — зі скульпту), крім очей і вух
BEZ_POCH = ("hand_", "index_", "middle_", "ring_", "pinky_", "thumb_", "foot_", "ball_", "toe")
NAPIV = {"neck_01": 0.2, "neck_02": 0.2, "neck": 0.2}


def log(*a):
    print("[обгортання]", *a)
    sys.stdout.flush()


arm = bpy.data.objects["Human.rig"]
tilo = bpy.data.objects["Human"]
# Скелет основи MPFB стоїть за пропорціями ДО цілей раси (кисть орка — за 20 см від своєї
# кістки): спершу підігнати його під тіло, інакше перенесення за кістками рве кінцівки.
if "--без-refit" not in A:
    from bl_ext.blender_org.mpfb.services.humanservice import HumanService
    HumanService.refit(tilo)
    log("скелет основи підігнано під тіло (MPFB refit)")
sitky = [o for o in bpy.data.objects if o.type == "MESH" and o.find_armature() == arm]

# `--обличчя-скульпту`: обличчя ЦІЛКОМ зі скульпту, разом із намальованими очима (так у
# моделей із генератора, які замовник назвав кращими). Щоб у сітці MPFB не лишилось прорізів
# очей, повіки спершу заплющуються (вираз MakeHuman) — тоді вони лягають на око скульпту
# суцільною поверхнею. Очні яблука, вії, брови й ікла MPFB ховаються всередину голови.
# Ціна: такий аватар не кліпає й не водить очима.
OBLYCHCHIA = "--обличчя-скульпту" in A
if OBLYCHCHIA:
    from bl_ext.blender_org.mpfb.services.targetservice import TargetService as TS
    bpy.context.view_layer.objects.active = tilo
    if not tilo.data.shape_keys:
        tilo.shape_key_add(name="Basis")
    for nt in ("eye-left-closure", "eye-right-closure"):
        TS.load_target(tilo, TS.target_full_path(nt), weight=1.0, name="т-" + nt)
    kz = tilo.shape_key_add(name="заплющено", from_mix=True)
    nove_ = np.array([p.co[:] for p in kz.data])
    for k in list(tilo.data.shape_keys.key_blocks):
        tilo.shape_key_remove(k)
    tilo.data.vertices.foreach_set("co", nove_.ravel())
    tilo.data.update()
    log("повіки основи заплющено")

# ── скульпт у цей файл ──────────────────────────────────────────────────────
with bpy.data.libraries.load(SKULPT) as (src, dst):
    dst.objects = [n for n in src.objects if n in ("Тіло", "Human.rig")]
sk_arm = next(o for o in dst.objects if o.type == "ARMATURE")
sk = next(o for o in dst.objects if o.type == "MESH")
for o in (sk_arm, sk):
    bpy.context.scene.collection.objects.link(o)
sk.name, sk_arm.name = "Скульпт", "Скульпт.rig"
log("скульпт: %d вершин; кісток основи %d, скульпту %d" % (
    len(sk.data.vertices), len(arm.data.bones), len(sk_arm.data.bones)))

# ── 1. скелетне перенесення ─────────────────────────────────────────────────
T = {}
OBERT = {}        # найменший поворот «напрям кістки основи → напрям кістки скульпту»
for b in arm.data.bones:
    s = sk_arm.data.bones.get(b.name)
    if s is None:
        continue
    k = s.length / max(b.length, 1e-6)
    k = min(max(k, 0.6), 1.8)
    # Лише напрям і довжина: поворот кістки навколо власної осі (roll) у двох скелетів
    # різний, і повна матриця кістки скручувала руки й ноги в стрічки.
    hm = arm.matrix_world @ b.head_local
    dm = (arm.matrix_world.to_3x3() @ (b.tail_local - b.head_local)).normalized()
    hs = sk_arm.matrix_world @ s.head_local
    ds = (sk_arm.matrix_world.to_3x3() @ (s.tail_local - s.head_local)).normalized()
    R = dm.rotation_difference(ds).to_matrix().to_4x4()
    OBERT[b.name] = R
    T[b.name] = Matrix.Translation(hs) @ R @ Matrix.Scale(k, 4) @ Matrix.Translation(-hm)
# Голова лишається від MPFB, але розміром — як у скульпту: інакше на товстій шиї сидить
# мала людська голова з коміром-складкою. Міра — ширина голови вище основи кістки голови.
def shyryna_holovy(o, a_, kistka):
    z0 = (a_.matrix_world @ a_.data.bones[kistka].head_local).z + 0.04
    xs = [(o.matrix_world @ v.co).x for v in o.data.vertices if (o.matrix_world @ v.co).z > z0]
    xs = np.array(xs)
    return float(np.percentile(xs, 97) - np.percentile(xs, 3)) if len(xs) else 0.0


if "head" in T:
    b_ = arm.data.bones["head"]
    tilo_holova = [v.co.x for v in tilo.data.vertices
                   if any(tilo.vertex_groups[g.group].name == "head" and g.weight > 0.9 for g in v.groups)]
    sh_m = float(np.percentile(tilo_holova, 97) - np.percentile(tilo_holova, 3))
    sh_s = shyryna_holovy(sk, sk_arm, "head")
    k_h = min(max(sh_s / max(sh_m, 1e-6), 1.0), 1.16)   # ширина скульпту захоплює вуха й трапеції
    hs_ = sk_arm.matrix_world @ sk_arm.data.bones["head"].head_local
    hm_ = arm.matrix_world @ b_.head_local
    T["head"] = Matrix.Translation(hs_) @ OBERT["head"] @ Matrix.Scale(k_h, 4) @ Matrix.Translation(-hm_)
    log("голова: ширина MPFB %.3f м, скульпту %.3f м → масштаб %.2f" % (sh_m, sh_s, k_h))

# Пальці лишаються від MPFB: кістки пальців скульпту стоять у його злиплих пальцях і
# для чистої кисті не годяться. Усі кістки пальців їдуть разом із кистю, жорстко.
PALTSI = ("index_", "middle_", "ring_", "pinky_", "thumb_")
for n in list(T):
    if n.startswith(PALTSI):
        kyst = "hand_" + n[-1]
        if kyst in T:
            T[n], OBERT[n] = T[kyst], OBERT[kyst]
log("кісток зі спільною назвою: %d" % len(T))


def vagy(o):
    """Масив N×K ваг і список кісток K для сітки."""
    imena = [g.name for g in o.vertex_groups]
    kol = [i for i, n in enumerate(imena) if n in T]
    idx = {g: j for j, g in enumerate(kol)}
    W = np.zeros((len(o.data.vertices), len(kol)), np.float32)
    for v in o.data.vertices:
        for g in v.groups:
            j = idx.get(g.group)
            if j is not None:
                W[v.index, j] = g.weight
    return W, [imena[g] for g in kol]


def perenesty(o):
    W, kist = vagy(o)
    suma = W.sum(1, keepdims=True)
    Wn = W / np.maximum(suma, 1e-8)
    M = np.array([np.array(o.matrix_world.inverted() @ T[n] @ o.matrix_world) for n in kist])  # K×4×4
    me = o.data
    bloky = me.shape_keys.key_blocks if me.shape_keys else None
    co0 = np.array([v.co[:] for v in me.vertices], np.float64)
    ch = np.c_[co0, np.ones(len(co0))]
    # змішана матриця на вершину
    Mv = np.einsum("nk,kij->nij", Wn, M)
    maie = suma[:, 0] > 1e-6
    nove = np.einsum("nij,nj->ni", Mv, ch)[:, :3]
    nove[~maie] = co0[~maie]
    if bloky:
        for kb in bloky:
            c = np.array([p.co[:] for p in kb.data], np.float64)
            d = np.einsum("nij,nj->ni", Mv[:, :3, :3], c - co0)
            d[~maie] = (c - co0)[~maie]
            kb.data.foreach_set("co", (nove + d).ravel())
    me.vertices.foreach_set("co", nove.ravel())
    me.update()
    return W, kist


VAGY = {}
for o in sitky:
    VAGY[o.name] = perenesty(o)
    log("перенесено:", o.name, len(o.data.vertices))

# скелет основи → суглоби скульпту
bpy.context.view_layer.objects.active = sk_arm
bpy.ops.object.mode_set(mode="EDIT")
susp = {b.name: (b.head.copy(), b.tail.copy(), b.roll) for b in sk_arm.data.edit_bones}
bpy.ops.object.mode_set(mode="OBJECT")
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
for b in arm.data.edit_bones:
    if b.name.startswith(PALTSI) and b.name in T:
        z_stara = b.z_axis.copy()
        M_ = arm.matrix_world.inverted() @ T[b.name] @ arm.matrix_world
        b.head, b.tail = M_ @ b.head, M_ @ b.tail
        b.align_roll(OBERT[b.name].to_3x3() @ z_stara)
    elif b.name in susp:
        z_stara = b.z_axis.copy()
        b.head, b.tail = susp[b.name][0], susp[b.name][1]
        # вісь Z кістки їде тим самим найменшим поворотом — рухи лишаються правильними
        b.align_roll(OBERT[b.name].to_3x3() @ z_stara)
bpy.ops.object.mode_set(mode="OBJECT")

# ── 2. притягування тіла до скульпту ────────────────────────────────────────
bm_s = bmesh.new()
bm_s.from_mesh(sk.data)
bm_s.transform(sk.matrix_world)
bm_s.normal_update()
# нормалі скульпту мають дивитись назовні; у сітки з генератора буває навпаки
cen_s = sum((f.calc_center_median() for f in bm_s.faces), Vector()) / len(bm_s.faces)
nazovni = sum(1 for f in bm_s.faces[:] [::50] if f.normal.dot(f.calc_center_median() - cen_s) > 0)
if nazovni < len(bm_s.faces) / 50 * 0.5:
    bmesh.ops.reverse_faces(bm_s, faces=bm_s.faces[:])
    bm_s.normal_update()
    log("нормалі скульпту дивились усередину — перевернуто")
tree = BVHTree.FromBMesh(bm_s)

W, kist = VAGY[tilo.name]
suma = np.maximum(W.sum(1), 1e-8)
wf = np.ones(len(tilo.data.vertices))
for j, n in enumerate(kist):
    if n in BEZ or n.startswith(BEZ_POCH):
        wf -= W[:, j] / suma
    elif n in NAPIV:
        wf -= W[:, j] / suma * NAPIV[n]
wf = np.clip(wf, 0, 1)
# Очі й повіки лишаються від MPFB (очні яблука — окремі сітки, кліпання — форм-ключ): довкола
# кожного ока — куля без притягування з плавним краєм. Вуха — теж від MPFB (найближча точка
# на гострому вусі скульпту рве сітку).
co_t = np.array([(tilo.matrix_world @ v.co)[:] for v in tilo.data.vertices])
oko = bpy.data.objects.get("Human.high-poly") or bpy.data.objects.get("Human.low-poly")
OCHI = []
if oko is not None and not OBLYCHCHIA:
    co_o = np.array([(oko.matrix_world @ v.co)[:] for v in oko.data.vertices])
    for znak, bik in ((1, co_o[co_o[:, 0] > 0]), (-1, co_o[co_o[:, 0] < 0])):
        if not len(bik):
            continue
        c = bik.mean(0)
        r = float(np.linalg.norm(bik - c, axis=1).max())
        d = np.linalg.norm(co_t - c, axis=1)
        OCHI.append((c, r, d, (co_o[:, 0] > 0) if znak > 0 else (co_o[:, 0] < 0)))
        wf *= np.clip((d - r * 1.12) / (r * 0.5), 0, 1)       # повіки — на поверхні яблука (d ≈ r)
    log("очі: радіус яблука %.1f мм — зона без притягування %.1f…%.1f мм" % (r * 1000, r * 1120, r * 1620))
for ms in tilo.material_slots:
    pass
vukha = set()
for pol in tilo.data.polygons:
    m_ = tilo.data.materials[pol.material_index]
    if m_ is not None and "ears" in m_.name.lower():
        vukha.update(pol.vertices)
if vukha:
    wf[list(vukha)] = 0
    log("вуха без притягування: %d вершин" % len(vukha))
# лише справжнє тіло (помічники MPFB — геть із притягування)
g_body = tilo.vertex_groups.get("body")
if g_body is not None:
    spravzhni = np.zeros(len(wf), bool)
    for v in tilo.data.vertices:
        for g in v.groups:
            if g.group == g_body.index and g.weight > 0.5:
                spravzhni[v.index] = True
    wf[~spravzhni] = 0

bm = bmesh.new()
bm.from_mesh(tilo.data)
bm.verts.ensure_lookup_table()
sus = [[e.other_vert(v).index for e in v.link_edges] for v in bm.verts]
mw = np.array(tilo.matrix_world)
mwi = np.array(tilo.matrix_world.inverted())


def zhladyty(x, kroky):
    for _ in range(kroky):
        y = x.copy()
        for i, s in enumerate(sus):
            if s:
                y[i] = 0.5 * x[i] + 0.5 * x[s].mean(0)
        x = y
    return x


wf = zhladyty(wf[:, None], 8)[:, 0]      # ширший перехід: сходинка на передпліччі
co_do = np.array([v.co[:] for v in bm.verts])
KOLA = () if "--лише-кістки" in A else ((14, 0.12), (10, 0.09), (6, 0.06), (4, 0.04), (2, 0.03), (1, 0.02))
for kolo, (zhl, dal) in enumerate(KOLA):
    bm.normal_update()
    zs = np.zeros((len(bm.verts), 3))
    vluchyv = 0
    for v in bm.verts:
        if wf[v.index] < 0.02:
            continue
        p = tilo.matrix_world @ v.co
        n = (tilo.matrix_world.to_3x3() @ v.normal).normalized()
        # Скульпт із генератора має внутрішню стінку. Спершу — промінь назовні вздовж нормалі
        # до першої поверхні, що дивиться туди ж (зовнішня стінка; внутрішні пропускаємо).
        # Якщо зовні нічого немає (основа товща за скульпт) — найближча точка з тією ж нормаллю.
        loc = None
        poch, proideno = p - n * 0.001, 0.0
        for _ in range(6):
            h = tree.ray_cast(poch, n, dal - proideno)
            if h[0] is None:
                break
            if h[1].dot(n) > 0.25:
                loc = h[0]
                break
            proideno += h[3] + 0.0005
            poch = h[0] + n * 0.0005
        if loc is None:
            l2, nrm, _, dist = tree.find_nearest(p, dal)
            if l2 is None or nrm.dot(n) < 0.25 or (l2 - p).dot(n) > 0.004:
                continue
            loc = l2
        zs[v.index] = np.array(loc - p) * wf[v.index]
        vluchyv += 1
    zs = zhladyty(zs, zhl)
    for v in bm.verts:
        d = zs[v.index]
        if d.any():
            v.co += tilo.matrix_world.inverted().to_3x3() @ Vector(d)
    log("коло %d: згладжувань %d, пошук %.0f см, влучило %d, середній зсув %.1f мм" % (
        kolo + 1, zhl, dal * 100, vluchyv, float(np.linalg.norm(zs, axis=1)[wf > 0.5].mean() * 1000)))

co_pislia = np.array([v.co[:] for v in bm.verts])
zsuv = co_pislia - co_do
# Очниці їдуть за обличчям: брови й вилиці скульпту зсунулись, а зона ока стояла на місці —
# око тонуло під надбрів'ям. Кільце вершин одразу за зоною ока дає середній зсув; на нього
# жорстко зсуваються повіки (вершини зони) і саме очне яблуко.
if oko is not None and not OBLYCHCHIA:
    for c, r, d, m_oka in OCHI:
        kiltse = (d > r * 1.62) & (d < r * 2.3) & (wf > 0.8)
        if kiltse.sum() < 8:
            continue
        t = zsuv[kiltse].mean(0)
        zona = d < r * 1.62
        co_pislia[zona] += t[None, :] * (1.0 - wf[zona])[:, None]
        mwo = np.array(oko.matrix_world.inverted().to_3x3()) @ (np.array(tilo.matrix_world.to_3x3()) @ t)
        for i in np.where(m_oka)[0]:
            oko.data.vertices[int(i)].co += Vector(mwo)
        log("око: зсув за обличчям %.1f мм (кільце %d вершин)" % (np.linalg.norm(t) * 1000, int(kiltse.sum())))
    oko.data.update()
    zsuv = co_pislia - co_do
# форм-ключі тіла (якщо є) їдуть разом
if tilo.data.shape_keys:
    for kb in tilo.data.shape_keys.key_blocks:
        c = np.array([p.co[:] for p in kb.data]) + zsuv
        kb.data.foreach_set("co", c.ravel())
tilo.data.vertices.foreach_set("co", co_pislia.ravel())
tilo.data.update()

# відстань до скульпту після притягування
vid = []
for i in np.where(wf > 0.9)[0][::5]:
    p = tilo.matrix_world @ Vector(co_pislia[i])
    loc = tree.find_nearest(p, 0.2)[0]
    if loc is not None:
        vid.append((loc - p).length)
vid = np.array(vid) * 1000
log("залишкова відстань до скульпту: медіана %.1f мм, 95-й процентиль %.1f мм, найбільша %.1f мм" % (
    np.median(vid), np.percentile(vid, 95), vid.max()))

# ── 3. білизна — за найближчою вершиною тіла ────────────────────────────────
kd = KDTree(len(co_do))
for i, c in enumerate(co_do):
    kd.insert(tilo.matrix_world @ Vector(c), i)
kd.balance()
for o in sitky:
    if o is tilo or "poly" in o.name:          # очі не чіпаємо: їхня зона не притягувалась
        continue
    for v in o.data.vertices:
        _, i, _ = kd.find(o.matrix_world @ v.co)
        v.co += o.matrix_world.inverted().to_3x3() @ (tilo.matrix_world.to_3x3() @ Vector(zsuv[i]))
    if not o.name.startswith("білизна"):
        o.data.update()
        log("за тілом:", o.name)
        continue
    # і не нижче шкіри: тіло стало товщим, ніж було під білизною (діри на стегнах)
    bm_t2 = bmesh.new()
    bm_t2.from_mesh(tilo.data)
    bm_t2.transform(tilo.matrix_world)
    bm_t2.normal_update()
    tr2 = BVHTree.FromBMesh(bm_t2)
    pidniato = 0
    for v in o.data.vertices:
        p = o.matrix_world @ v.co
        loc, nrm, _, _ = tr2.find_nearest(p, 0.1)
        if loc is not None and (p - loc).dot(nrm) < 0.013:
            v.co = o.matrix_world.inverted() @ (loc + nrm * 0.013)
            pidniato += 1
    bm_t2.free()
    o.data.update()
    log("білизна за тілом:", o.name, "· піднято над шкірою вершин:", pidniato)

# ── 4. рельєф скульпту → карта нормалей у розгортці тіла ────────────────────
# Низькополігональне тіло повторює маси, але не жили й борозни між м'язами: їх несе карта
# нормалей, запечена зі скульпту (Cycles, «вибране → активне»). У каналі A — де рельєф
# дійсний (там, де тіло притягувалось): голова, кисті й стопи — від MPFB, їм він чужий.
RELIEF = A[A.index("--рельєф") + 1] if "--рельєф" in A else ""
if RELIEF:
    import cv2
    ROZMIR = 2048
    img = bpy.data.images.new("рельєф", ROZMIR, ROZMIR, alpha=False, float_buffer=False)
    img.colorspace_settings.name = "Non-Color"
    img.generated_color = (0.5, 0.5, 1.0, 1.0)
    for m in tilo.data.materials:
        if m is None:
            continue
        m.use_nodes = True
        n = m.node_tree.nodes.new("ShaderNodeTexImage")
        n.image = img
        m.node_tree.nodes.active = n
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 1
    sc.render.bake.use_selected_to_active = True
    sc.render.bake.cage_extrusion = 0.03
    sc.render.bake.max_ray_distance = 0.06
    sc.render.bake.margin = 8
    sc.render.bake.normal_space = "TANGENT"
    for o in bpy.context.scene.objects:
        o.select_set(False)
    sk.select_set(True)
    tilo.select_set(True)
    bpy.context.view_layer.objects.active = tilo
    bpy.ops.object.bake(type="NORMAL")
    px = np.array(img.pixels[:], np.float32).reshape(ROZMIR, ROZMIR, 4)[::-1]      # верх угорі
    # маска дійсності: вага притягування по трикутниках розгортки
    maska = np.zeros((ROZMIR, ROZMIR), np.float32)
    uvd = tilo.data.uv_layers.active.data
    tilo.data.calc_loop_triangles()
    for t in tilo.data.loop_triangles:
        w3 = [wf[tilo.data.loops[l].vertex_index] for l in t.loops]
        if max(w3) < 0.02:
            continue
        pts = np.array([[uvd[l].uv[0] * ROZMIR, (1.0 - uvd[l].uv[1]) * ROZMIR] for l in t.loops], np.int32)
        cv2.fillConvexPoly(maska, pts, float(sum(w3) / 3.0))
    maska = cv2.GaussianBlur(maska, (0, 0), 3.0)
    out = np.dstack([px[:, :, 2], px[:, :, 1], px[:, :, 0], maska])                # BGRA
    ok, buf = cv2.imencode(".png", (np.clip(out, 0, 1) * 255).astype(np.uint8))
    with open(RELIEF, "wb") as f:
        f.write(buf.tobytes())
    log("рельєф →", RELIEF)
    # ── колір шкіри зі скульпту ─────────────────────────────────────────────
    # Той самий прохід, тип «розсіяний колір» без світла. Де рельєф недійсний (кисті, стопи,
    # очі, вуха) — шкіра MakeHuman, перефарбована в середній тон скульпту; межа — плавна.
    img.colorspace_settings.name = "sRGB"
    sc.render.bake.use_pass_direct = False
    sc.render.bake.use_pass_indirect = False
    sc.render.bake.use_pass_color = True
    bpy.ops.object.bake(type="DIFFUSE")
    kol = np.array(img.pixels[:], np.float32).reshape(ROZMIR, ROZMIR, 4)[::-1][:, :, :3]
    mh = None
    for im_ in bpy.data.images:
        if "diffuse" in im_.name and im_.size[0] > 0 and im_ is not img:
            mh = np.array(im_.pixels[:], np.float32).reshape(im_.size[1], im_.size[0], 4)[::-1][:, :, :3]
            mh = cv2.resize(mh, (ROZMIR, ROZMIR), interpolation=cv2.INTER_AREA)
            break
    m3 = maska[:, :, None]
    pevni = maska > 0.9
    ton_s = kol[pevni].mean(0)
    if mh is not None:
        # тон MakeHuman → тон скульпту: множник за середнім по шкірі (не по тлу розгортки)
        shk = mh[pevni].mean(0)
        mh_t = np.clip(mh * (ton_s / np.maximum(shk, 1e-3)), 0, 1)
        sumish = kol * m3 + mh_t * (1.0 - m3)
    else:
        sumish = kol
    ok, buf = cv2.imencode(".png", (np.clip(sumish[:, :, ::-1], 0, 1) * 255).astype(np.uint8))
    with open(RELIEF.replace("_рельєф.png", "_шкіра-0-скульпт.png"), "wb") as f:
        f.write(buf.tobytes())
    log("колір зі скульпту →", RELIEF.replace("_рельєф.png", "_шкіра-0-скульпт.png"),
        "· середній тон", tuple(round(float(x), 3) for x in ton_s))
    for m in tilo.data.materials:            # вузол запікання — геть, матеріал як був
        if m is None:
            continue
        for n in [n for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and n.image == img]:
            m.node_tree.nodes.remove(n)
    bpy.data.images.remove(img)

sk.hide_render = True
sk.hide_viewport = True
sk_arm.hide_render = True
sk_arm.hide_viewport = True

# ── перевірочний рендер: скульпт | обгорнута основа, перед і бік ────────────
if RENDER:
    os.makedirs(RENDER, exist_ok=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "SINGLE"
    sc.display.shading.single_color = (0.72, 0.72, 0.72)
    sc.display.shading.show_cavity = True
    sc.render.resolution_x, sc.render.resolution_y = 700, 1000
    sc.render.film_transparent = False
    cam_d = bpy.data.cameras.new("к")
    cam_d.type = "ORTHO"
    cam_d.ortho_scale = 2.1
    cam = bpy.data.objects.new("к", cam_d)
    sc.collection.objects.link(cam)
    sc.camera = cam
    for nazva, loc, rot in (("pered", (0, -4, 0.93), (1.5708, 0, 0)), ("bik", (4, 0, 0.93), (1.5708, 0, 1.5708)),
                            ("zad", (0, 4, 0.93), (1.5708, 0, 3.14159))):
        cam.location, cam.rotation_euler = loc, rot
        for hto, pokaz in (("skulpt", True), ("osnova", False)):
            sk.hide_render = not pokaz
            for o in sitky:
                o.hide_render = pokaz
            sc.render.filepath = os.path.join(RENDER, "%s-%s.png" % (nazva, hto))
            bpy.ops.render.render(write_still=True)
    sk.hide_render = True
    for o in sitky:
        o.hide_render = False
    bpy.data.objects.remove(cam)

if OBLYCHCHIA:
    hb = arm.data.bones["head"]
    cen_h = arm.matrix_world @ ((hb.head_local + hb.tail_local) / 2)
    for o in sitky:
        if o is tilo or o.name.startswith("білизна"):
            continue
        for v in o.data.vertices:
            p = o.matrix_world @ v.co
            v.co = o.matrix_world.inverted() @ (cen_h + (p - cen_h) * 0.2)
        if o.data.shape_keys:
            for kb in o.data.shape_keys.key_blocks:
                for i_, pt in enumerate(kb.data):
                    pt.co = o.data.vertices[i_].co
        o.data.update()
        log("сховано всередину голови:", o.name)

# Скульпт у вихід не йде: експорт забирає й приховані об'єкти (у грі стояло два тіла).
for o in (sk, sk_arm):
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.wm.save_as_mainfile(filepath=VYKHID)
log("→", VYKHID)
