# Кістяк OpenPose (COCO-18) манекена для аркушів монстрів (26.11.2026): ті самі камера й
# кадр, що в karkas_at.py (орто, масштаб за Т-позою), поза А (скульпт тіло-4) або Т (руки 90°).
# Пише 2D-точки суглобів у JSON; малює їх tools/comfyui/kistiak_malyunok.py. Кістяк замість
# фото людини другою картинкою Qwen-Edit — щоб не просвічувало тіло манекена (нога в Т-45
# базальтового некро-охоронця, людина у скорпіонолюді).
#   blender -b <людина-авто.blend> -P tools/blender/kistiak_openpose.py -- <вихід.json> [--розмір 1024]
import json
import math
import sys

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Matrix, Vector

A = sys.argv[sys.argv.index("--") + 1:]
VYKHID = A[0]
R = int(A[A.index("--розмір") + 1]) if "--розмір" in A else 1024
sc = bpy.context.scene
rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
rig.animation_data_clear()
POZA_SKULPTU = {k: [list(r) for r in v] for k, v in json.loads(rig["поза_основи"]).items()}


def vyrivniaty(pb, tsil):
    mw = rig.matrix_world
    dir_svit = ((mw @ pb.tail) - (mw @ pb.head)).normalized()
    q = dir_svit.rotation_difference(tsil)
    m = mw.to_3x3() @ pb.matrix.to_3x3()
    d = (m.inverted() @ q.to_matrix() @ m).to_quaternion()
    pb.rotation_mode = "QUATERNION"
    pb.rotation_quaternion = pb.rotation_quaternion @ d
    bpy.context.view_layer.update()


def postav(poza):
    for pb in rig.pose.bones:
        pb.matrix_basis.identity()
    bpy.context.view_layer.update()
    if poza == "А":
        for pb in rig.pose.bones:
            pb.matrix_basis = Matrix(POZA_SKULPTU.get(pb.name, Matrix.Identity(4)))
        bpy.context.view_layer.update()
        return
    seredyna = rig.matrix_world.translation.x
    for pl, lk in (("upperarm_l", "lowerarm_l"), ("upperarm_r", "lowerarm_r")):
        pb = rig.pose.bones[pl]
        storona = 1 if (rig.matrix_world @ pb.tail).x > seredyna else -1
        tsil = Vector((storona, 0, 0))
        vyrivniaty(pb, tsil)
        vyrivniaty(rig.pose.bones[lk], tsil)
        vyrivniaty(rig.pose.bones[lk.replace("lowerarm", "hand")], tsil)


def mezhi():
    dg = bpy.context.evaluated_depsgraph_get()
    P = []
    for o in bpy.data.objects:
        if o.type == "MESH" and not o.hide_render:
            ev = o.evaluated_get(dg)
            P += [ev.matrix_world @ v.co for v in ev.to_mesh().vertices]
            ev.to_mesh_clear()
    return P


def tochky():
    mw = rig.matrix_world
    g = lambda n, kin=False: mw @ (rig.pose.bones[n].tail if kin else rig.pose.bones[n].head)
    h0, h1 = g("head"), g("head", True)
    c = h0 + (h1 - h0) * 0.45
    # обличчя дивиться в −Y (камера 0° стоїть на −Y)
    return {
        0: c + Vector((0, -0.10, -0.02)), 1: g("neck_01"),
        2: g("upperarm_r"), 3: g("lowerarm_r"), 4: g("hand_r"),
        5: g("upperarm_l"), 6: g("lowerarm_l"), 7: g("hand_l"),
        8: g("thigh_r"), 9: g("calf_r"), 10: g("foot_r"),
        11: g("thigh_l"), 12: g("calf_l"), 13: g("foot_l"),
        14: c + Vector((-0.035, -0.08, 0.02)), 15: c + Vector((0.035, -0.08, 0.02)),
        16: c + Vector((-0.075, 0, 0)), 17: c + Vector((0.075, 0, 0)),
    }


cam = bpy.data.objects.new("tmp-кадр", bpy.data.cameras.new("tmp-кадр"))
sc.collection.objects.link(cam)
cam.data.type = "ORTHO"
sc.camera = cam
sc.render.resolution_x = sc.render.resolution_y = R
postav("Т")
bpy.context.view_layer.update()
P = mezhi()
zmin, zmax = min(p.z for p in P), max(p.z for p in P)
H = zmax - zmin
shyr = max(max(abs(p.x) for p in P), max(abs(p.y) for p in P)) * 2
cx = (min(p.x for p in P) + max(p.x for p in P)) / 2
cy = (min(p.y for p in P) + max(p.y for p in P)) / 2
cam.data.ortho_scale = max(H / 0.93, shyr * 1.08)
rez = {}
for poza in "АТ":
    postav(poza)
    t = tochky()
    for kut in (0, 45, 90, 180):
        a = math.radians(kut)
        d = Vector((math.sin(a), -math.cos(a), 0))
        cam.location = Vector((cx, cy, zmin + H / 2)) + d * 8
        cam.rotation_euler = (math.pi / 2, 0, a)
        bpy.context.view_layer.update()
        pr = {}
        for i, p in t.items():
            v = world_to_camera_view(sc, cam, p)
            pr[i] = (v.x * R, (1 - v.y) * R, v.z)
        # обличчя ззаду не видно; збоку — лише ближче око й вухо
        if kut == 180:
            for i in (0, 14, 15):
                pr.pop(i)
        elif kut == 90:
            for para in ((14, 15), (16, 17)):
                pr.pop(max(para, key=lambda i: pr[i][2]))
        rez["%s-%d" % (poza, kut)] = {str(i): [round(x, 1), round(y, 1)] for i, (x, y, _) in pr.items()}
json.dump(rez, open(VYKHID, "w"), ensure_ascii=False, indent=1)
print("[кістяк] →", VYKHID)
