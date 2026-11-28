"""Спрощення кольорової сітки NPC до ігрової (28.11.2026): Hunyuan3D-2mv + проєкція дають ~360 тис.
граней і тисячі дрібних UV-островів — колапс по них ламає текстуру (перевірено на ковалі). Тож:
копія → колапс до ~40 тис. → нова розгортка (Smart UV) → колір запікається з повної сітки
(Cycles, selected-to-active, лише колір).
    blender -b -P tools/blender/npc_sproshchennia.py -- <вхід.glb> <вихід.glb> [грані 40000] [текстура 2048]
"""
import os
import sys
import bpy
A = sys.argv[sys.argv.index("--") + 1:]
CIL = int(A[2]) if len(A) > 2 else 40000
TEX = int(A[3]) if len(A) > 3 else 2048
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=A[0])
ms = [o for o in bpy.context.scene.objects if o.type == "MESH"]
for o in bpy.context.scene.objects:
    o.select_set(o in ms)
bpy.context.view_layer.objects.active = ms[0]
if len(ms) > 1:
    bpy.ops.object.join()
vys = bpy.context.view_layer.objects.active
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
n = len(vys.data.polygons)
nyz = vys.copy()
nyz.data = vys.data.copy()
nyz.name = "NPC"
bpy.context.collection.objects.link(nyz)
# імпорт glTF розщеплює вершини за UV/пласкими нормалями — без зварювання копія = окремі
# трикутники, колапс їх не зливає, а Smart UV дає по острову на трикутник
import bmesh
bm = bmesh.new()
bm.from_mesh(nyz.data)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
# дрібні відірвані шматки (< 0,5 % граней) — сміття Hunyuan; на них колапс застрягав
# (майстер магії: 682 тис. → лише 271 тис.)
bm.faces.ensure_lookup_table()
bachyv, smittia = set(), []
for f in bm.faces:
    if f.index in bachyv:
        continue
    st, chast = [f], []
    bachyv.add(f.index)
    while st:
        x = st.pop()
        chast.append(x)
        for e in x.edges:
            for g in e.link_faces:
                if g.index not in bachyv:
                    bachyv.add(g.index)
                    st.append(g)
    if len(chast) < len(bm.faces) * 0.005:
        smittia += chast
bmesh.ops.delete(bm, geom=smittia, context="FACES")
print("[спрощення] прибрано дрібних шматків: %d граней" % len(smittia), flush=True)
bm.to_mesh(nyz.data)
bm.free()
for p_ in nyz.data.polygons:
    p_.use_smooth = True
# стара розгортка й кольори вершин — геть до колапсу: він береже їхні шви і на дрібних
# островах застрягав (майстер магії: 682 тис. → лише 271 тис.); розгортка все одно нова
while nyz.data.uv_layers:
    nyz.data.uv_layers.remove(nyz.data.uv_layers[0])
for a_ in list(nyz.data.color_attributes):
    nyz.data.color_attributes.remove(a_)
bpy.context.view_layer.objects.active = nyz
# колапс за прохід інколи застрягає (тонкий подвійний каптур майстра магії: 682 тис. → 271 тис.) —
# повторювати, доки сходиться до цілі
for prokhid in range(6):
    zaraz = len(nyz.data.polygons)
    if zaraz <= CIL * 1.05:
        break
    m = nyz.modifiers.new("d", "DECIMATE")
    m.ratio = CIL / zaraz
    m.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier="d")
    print("[спрощення] прохід %d: %d → %d" % (prokhid + 1, zaraz, len(nyz.data.polygons)), flush=True)
    if len(nyz.data.polygons) > zaraz * 0.97:
        break
# не зійшлось — воксельний ремеш (крок = зріст/250) і колапс по ньому; колір усе одно
# запікається з повної сітки
if len(nyz.data.polygons) > CIL * 1.5:
    zr = nyz.dimensions.z
    r_ = nyz.modifiers.new("r", "REMESH")
    r_.mode = "VOXEL"
    r_.voxel_size = zr / 250
    bpy.ops.object.modifier_apply(modifier="r")
    zaraz = len(nyz.data.polygons)
    m = nyz.modifiers.new("d", "DECIMATE")
    m.ratio = min(1.0, CIL / zaraz)
    m.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier="d")
    for p_ in nyz.data.polygons:
        p_.use_smooth = True
    print("[спрощення] ремеш %.4f: %d → колапс %d" % (zr / 250, zaraz, len(nyz.data.polygons)), flush=True)
nyz.data.uv_layers.new(name="UV")
for o in bpy.context.scene.objects:
    o.select_set(o is nyz)
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.003)
bpy.ops.object.mode_set(mode="OBJECT")
img = bpy.data.images.new("npc-kolir", TEX, TEX)
mat = bpy.data.materials.new("NPC")
mat.use_nodes = True
nt = mat.node_tree
bsdf = nt.nodes["Principled BSDF"]
bsdf.inputs["Roughness"].default_value = 0.85
tx = nt.nodes.new("ShaderNodeTexImage")
tx.image = img
nt.links.new(tx.outputs["Color"], bsdf.inputs["Base Color"])
nyz.data.materials.clear()
nyz.data.materials.append(mat)
nt.nodes.active = tx
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = 1
sc.render.bake.use_pass_direct = False
sc.render.bake.use_pass_indirect = False
sc.render.bake.use_selected_to_active = True
sc.render.bake.cage_extrusion = 0.02
sc.render.bake.max_ray_distance = 0.05
sc.render.bake.margin = 6
vys.select_set(True)
nyz.select_set(True)
bpy.context.view_layer.objects.active = nyz
bpy.ops.object.bake(type="DIFFUSE")
img.filepath_raw = os.path.splitext(A[1])[0] + "-колір.png"
img.file_format = "PNG"
img.save()
bpy.data.objects.remove(vys)
print("[спрощення] %d → %d граней, текстура %d запечена" % (n, len(nyz.data.polygons), TEX), flush=True)
bpy.ops.export_scene.gltf(filepath=A[1], export_format="GLB")
