"""Розділити злиплі ступні основи (13.10.2026).

Слово замовника про людину l2002 у перегляді Mixamo: «знову ступні злиплись».
Скан Pixal3D зліпив стопи (нижче 15 см 201 ребро через середину, щілина
1,4 мм) — авто-скелет тягне перемичку між ногами. Грані внизу, що
перетинають середину, геть; дірки латаються; стопи розводяться на `ROZVID`
кожна (повністю нижче 10 см, до нуля на 20 см). Форм-ключі (риси) лишаються:
bmesh тримає шари ключів.

    blender -b <основа.blend> -P tools/blender/stopy_rozdilyty.py
"""
import bmesh
import bpy

VYSOTA = 0.13     # нижче — шукаємо перемичку
ROZVID = 0.01     # кожна стопа вбік, м

o = max([o for o in bpy.context.scene.objects if o.type == "MESH"],
        key=lambda o: len(o.data.vertices))
bm = bmesh.new()
bm.from_mesh(o.data)
# Розріз площиною x = 0 у нижній частині, ребра розрізу — навпіл: у кожної
# стопи своя дірка. Без цього латка спільної дірки знову з'єднувала стопи
# (перша спроба: 108 ребер через середину, стопи з'єднані).
nyz = [f for f in bm.faces if max(v.co.z for v in f.verts) < VYSOTA]
geom = list(nyz) + list({e for f in nyz for e in f.edges}) + list({v for f in nyz for v in f.verts})
rez = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, 0), plane_no=(1, 0, 0))
riz = [e for e in rez["geom_cut"] if isinstance(e, bmesh.types.BMEdge)
       and all(abs(v.co.x) < 1e-5 for v in e.verts)]
bmesh.ops.split_edges(bm, edges=riz)
geti = riz
# Без латок: holes_fill на тонкостінній сітці скану латав і чужі дірки —
# рвані клапті на підйомі стопи (перевірено рендером). Зріз лишається
# відкритим з внутрішнього боку стопи, де його не видно.
zalatano = []
shary = [bm.verts.layers.shape[k] for k in bm.verts.layers.shape.keys()]
for v in bm.verts:
    if v.co.z >= 0.20:
        continue
    # бік вершини на площині розрізу — за сусідами
    x_ = v.co.x if abs(v.co.x) > 1e-5 else sum(e.other_vert(v).co.x for e in v.link_edges)
    k = 1.0 if v.co.z <= 0.10 else (0.20 - v.co.z) / 0.10
    dx = ROZVID * k * (1 if x_ > 0 else -1)
    v.co.x += dx
    for s in shary:
        v[s].x += dx
cherez = sum(1 for e in bm.edges if max(v.co.z for v in e.verts) < 0.15
             and e.verts[0].co.x * e.verts[1].co.x < 0)
print("[стопи] ребер розрізу %d, латок %d, ребер через середину лишилось %d"
      % (len(geti), len(zalatano), cherez))
bm.to_mesh(o.data)
o.data.update()
bpy.ops.wm.save_mainfile()
