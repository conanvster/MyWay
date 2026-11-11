"""Кулаки скульпту: пальці злиті — усі ваги пальців віддати кістці кисті."""
import bpy, sys
out = sys.argv[sys.argv.index("--") + 1]
o = bpy.data.objects["Тіло"]
for bik in "lr":
    hand = o.vertex_groups.get("hand_" + bik)
    pal = [g for g in o.vertex_groups if g.name.endswith("_" + bik) and g.name.split("_")[0] in ("index", "middle", "ring", "pinky", "thumb")]
    idx = {g.index for g in pal}
    n = 0
    for v in o.data.vertices:
        s = sum(g.weight for g in v.groups if g.group in idx)
        if s > 0:
            hand.add([v.index], s, "ADD")
            n += 1
    for g in pal:
        o.vertex_groups.remove(g)
    print("[кулак]", bik, "вершин", n)
print("[кулак] об'єкти", [(x.name, x.type) for x in bpy.data.objects], [m.name for m in o.data.materials])
bpy.ops.wm.save_as_mainfile(filepath=out)
