# Кадр голого тіла моделі для сету по зонах (20.11.2026, людина-жінка пілот Б — MPFB, без
# референсу, з якого її ліпили): рендер спереду в позі спокою, у білизні, без волосся, тло
# світло-сіре, кадр як у референсах «з нуля» — маківка на 0,035 висоти кадру, підошви на 0,965,
# тож висоту зони рахує та сама формула: z = зріст·(0,965 − y)/0,93.
#   blender -b <модель.blend> -P tools/blender/kadr_tila.py -- <кадр.png> [--тіло Human] [--розмір 1024]
import sys
import bpy
from mathutils import Vector

A = sys.argv[sys.argv.index("--") + 1:]
VYHID = A[0]
def arg(k, d):
    return type(d)(A[A.index(k) + 1]) if k in A else d
TILO = arg("--тіло", "Human")
R = arg("--розмір", 1024)

sc = bpy.context.scene
rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
for pb in rig.pose.bones:
    pb.matrix_basis.identity()
for o in bpy.data.objects:
    if o.type == "MESH" and (o.name.startswith(("Волосся", "Борода", "Одяг-")) or o.hide_render):
        o.hide_render = True
    if o.type == "MESH" and o.name.startswith(("Брови-", "Вії-")):
        # лише перший набір, як у грі за замовчуванням
        o.hide_render = not o.name.split("-")[1].startswith("1")
bpy.context.view_layer.update()
tilo = bpy.data.objects[TILO]
dg = bpy.context.evaluated_depsgraph_get()
ev = tilo.evaluated_get(dg)
zs = [(ev.matrix_world @ v.co) for v in ev.data.vertices]
zmin, zmax = min(p.z for p in zs), max(p.z for p in zs)
cx = (min(p.x for p in zs) + max(p.x for p in zs)) / 2
H = zmax - zmin
print("[кадр] зріст %.3f м" % H)
cam = bpy.data.objects.new("tmp-кадр", bpy.data.cameras.new("tmp-кадр"))
sc.collection.objects.link(cam)
cam.data.type = "ORTHO"
cam.data.ortho_scale = H / 0.93
cam.location = Vector((cx, -5.0, zmin + H / 2))
cam.rotation_euler = (1.5707963, 0, 0)
sc.camera = cam
sc.render.engine = "BLENDER_EEVEE"
sc.render.resolution_x = sc.render.resolution_y = R
sc.render.film_transparent = False
sc.view_settings.view_transform = "AgX" if "AgX" in [i.identifier for i in
    sc.view_settings.bl_rna.properties["view_transform"].enum_items] else "Standard"
if sc.world is None:
    sc.world = bpy.data.worlds.new("світ")
sc.world.use_nodes = True
bg = sc.world.node_tree.nodes.get("Background")
bg.inputs[0].default_value = (0.78, 0.78, 0.8, 1)
bg.inputs[1].default_value = 1.0
for o in list(bpy.data.objects):
    if o.type == "LIGHT":
        o.hide_render = True
for nm, rot, e in (("tmp-ключ", (0.9, 0, 0.5), 2.5), ("tmp-заповн", (1.1, 0, -0.6), 1.2)):
    lt = bpy.data.objects.new(nm, bpy.data.lights.new(nm, "SUN"))
    lt.data.energy = e
    lt.data.angle = 0.5
    lt.rotation_euler = rot
    sc.collection.objects.link(lt)
sc.render.filepath = VYHID
bpy.ops.render.render(write_still=True)
print("[кадр] →", VYHID, "низ %.3f верх %.3f" % (zmin, zmax))
