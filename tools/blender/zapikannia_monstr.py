# Запікання з повної сітки на ігрову (П-297; `spec/якість-аватарів-і-монстрів.md` §6.2 М2): колір
# (проєкція аркуша на повній сітці — proektsiia_4.py) і карта нормалей (дрібний рельєф, що губиться
# при спрощенні). Ігрова сітка — нова розгортка; запікання «з виділеного на активне» (Cycles, CPU).
#   blender -b -P tools/blender/zapikannia_monstr.py -- <повна-з-кольором.glb> <ігрова.glb> <вихід.glb>
#       [--текстура 2048]
import os
import sys

import bpy

A = sys.argv[sys.argv.index("--") + 1:]
HI, LO, VYHID = (os.path.abspath(x) for x in A[:3])
TEX = int(A[A.index("--текстура") + 1]) if "--текстура" in A else 2048
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene


def vziaty(shliakh, imia):
    stari = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=shliakh)
    novi = [o for o in bpy.data.objects if o not in stari]
    ms = [o for o in novi if o.type == "MESH"]
    for o in ms:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    for o in novi:
        if o.type != "MESH":
            bpy.data.objects.remove(o)
    bpy.ops.object.select_all(action="DESELECT")
    for o in ms:
        o.select_set(True)
    bpy.context.view_layer.objects.active = ms[0]
    if len(ms) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    o.name = imia
    return o


hi = vziaty(HI, "повна")
# порожні кольори вершин (TRELLIS, Hunyuan): імпорт glTF множить на них текстуру → чорне
for c_ in list(hi.data.color_attributes):
    hi.data.color_attributes.remove(c_)
# колір повної — як світіння (EMIT): DIFFUSE губив колір, коли текстуру вів альфа-канал чи група
# glTF (у гнола TRELLIS виходила чорна)
for mt in hi.data.materials:
    if not (mt and mt.use_nodes):
        continue
    nt_ = mt.node_tree
    bs = next((n for n in nt_.nodes if n.type == "BSDF_PRINCIPLED"), None)
    out = next((n for n in nt_.nodes if n.type == "OUTPUT_MATERIAL"), None)
    if bs is None or out is None or not bs.inputs["Base Color"].links:
        continue
    dzh = bs.inputs["Base Color"].links[0].from_socket
    em = nt_.nodes.new("ShaderNodeEmission")
    nt_.links.new(dzh, em.inputs["Color"])
    nt_.links.new(em.outputs["Emission"], out.inputs["Surface"])
lo = vziaty(LO, "ігрова")
# glTF приходить незвареним (вершини розщеплені за нормалями) — без зварювання розгортка
# робила острівець на кожну грань
import bmesh
bm = bmesh.new()
bm.from_mesh(lo.data)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
bm.to_mesh(lo.data)
bm.free()
if hasattr(lo.data, "has_custom_normals") and lo.data.has_custom_normals:
    bpy.context.view_layer.objects.active = lo
    bpy.ops.mesh.customdata_custom_splitnormals_clear()
for p in lo.data.polygons:
    p.use_smooth = True
# нова розгортка ігрової
bpy.ops.object.select_all(action="DESELECT")
lo.select_set(True)
bpy.context.view_layer.objects.active = lo
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
# малий відступ між острівцями: на 0,002 відступи з'їдали 90 % текстури
bpy.ops.uv.smart_project(angle_limit=1.4, island_margin=0.0005)
bpy.ops.uv.select_all(action="SELECT")
bpy.ops.uv.pack_islands(rotate=True, margin=0.0005)
bpy.ops.object.mode_set(mode="OBJECT")
kolir = bpy.data.images.new("колір", TEX, TEX)
norm = bpy.data.images.new("нормаль", TEX, TEX, float_buffer=False)
norm.colorspace_settings.name = "Non-Color"
mat = bpy.data.materials.new("тіло")
mat.use_nodes = True
nt = mat.node_tree
bsdf = nt.nodes["Principled BSDF"]
bsdf.inputs["Roughness"].default_value = 0.9
if "Specular IOR Level" in bsdf.inputs:
    bsdf.inputs["Specular IOR Level"].default_value = 0.2
tk = nt.nodes.new("ShaderNodeTexImage")
tk.image = kolir
tn = nt.nodes.new("ShaderNodeTexImage")
tn.image = norm
nm = nt.nodes.new("ShaderNodeNormalMap")
lo.data.materials.clear()
lo.data.materials.append(mat)
# діапазон променів — частка розміру
roz = max(lo.dimensions)
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = 1
b = sc.render.bake
b.use_selected_to_active = True
b.cage_extrusion = 0.012 * roz
b.max_ray_distance = 0.03 * roz
b.margin = 2
bpy.ops.object.select_all(action="DESELECT")
hi.select_set(True)
lo.select_set(True)
bpy.context.view_layer.objects.active = lo
b.use_pass_direct = False
b.use_pass_indirect = False
nt.nodes.active = tk
bpy.ops.object.bake(type="EMIT")
nt.nodes.active = tn
bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT")
nt.links.new(tk.outputs["Color"], bsdf.inputs["Base Color"])
nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
for im, suf in ((kolir, "-колір.png"), (norm, "-нормаль.png")):
    im.filepath_raw = VYHID.replace(".glb", suf)
    im.file_format = "PNG"
    im.save()
bpy.data.objects.remove(hi)
bpy.ops.export_scene.gltf(filepath=VYHID, export_format="GLB", export_texcoords=True,
                          export_normals=True, export_tangents=True)
print("[запікання] %d вершин, текстури %d² → %s" % (len(lo.data.vertices), TEX, VYHID))
