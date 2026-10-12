import bpy, bmesh, sys, numpy as np
from mathutils import Vector
a=sys.argv[sys.argv.index("--")+1:]; src,out=a[0],a[1]
bpy.ops.wm.open_mainfile(filepath=src)
tilo=max([o for o in bpy.context.scene.objects if o.type=='MESH'], key=lambda o: len(o.data.vertices))
# картинка кольору
img=None
for m in tilo.data.materials:
    for n in (m.node_tree.nodes if m and m.node_tree else []):
        if n.type=='TEX_IMAGE' and n.image and n.image.name.startswith('аватар-колір'): img=n.image
print("IMG", img and img.name, img and tuple(img.size))
w,h=img.size; px=np.empty(w*h*4,dtype=np.float32); img.pixels.foreach_get(px); px=px.reshape(h,w,4)
me=tilo.data; uv=me.uv_layers.active.data
nv=len(me.vertices); col=np.zeros((nv,3)); cnt=np.zeros(nv)
for poly in me.polygons:
    for li in poly.loop_indices:
        vi=me.loops[li].vertex_index; u,v=uv[li].uv
        col[vi]+=px[min(h-1,int(v*h)),min(w-1,int(u*w)),:3]; cnt[vi]+=1
col/=np.maximum(cnt,1)[:,None]
co=np.array([v.co[:] for v in me.vertices])
mx=col.max(1); mn=col.min(1); sat=(mx-mn)/np.maximum(mx,1e-3)
bile=(mx>0.55)&(sat<0.18)
# тулуб позаду: за заміром на кожній висоті — найзадніша шкіра тулуба (не білого кольору)
print("Z range", co[:,2].min(), co[:,2].max())
# Геометрія: пластина волосся — найзадніший шар. Промінь назад (+Y) з
# вершини: нічого або лише товща самої пластини (< TOVSHCHA) — волосся;
# шкіра спини бачить пластину через щілину — ні.
from mathutils.bvhtree import BVHTree
TOVSHCHA = float(a[2]) if len(a) > 2 else 0.015
tree = BVHTree.FromObject(tilo, bpy.context.evaluated_depsgraph_get())
oblast = (co[:,1] > 0.0) & (co[:,2] > 1.0) & (co[:,2] < 1.62) & (np.abs(co[:,0]) < 0.25)
vybir = np.zeros(nv, bool)
for i in np.where(oblast)[0]:
    p0 = Vector(co[i]) + Vector((0, 0.0005, 0))
    hit = tree.ray_cast(p0, Vector((0, 1, 0)), 1.0)
    if hit[0] is None or hit[3] < TOVSHCHA:
        vybir[i] = True
# найбільший зв'язний шматок — сама пластина, без дрібних островів
import collections
sus=[[] for _ in range(nv)]
for e in me.edges:
    a_,b_=e.vertices; sus[a_].append(b_); sus[b_].append(a_)
mitka=np.full(nv,-1); shmatky=[]
for s0 in np.where(vybir)[0]:
    if mitka[s0]>=0: continue
    q=collections.deque([s0]); mitka[s0]=len(shmatky); n=0
    while q:
        i=q.popleft(); n+=1
        for j in sus[i]:
            if vybir[j] and mitka[j]<0:
                mitka[j]=mitka[s0]; q.append(j)
    shmatky.append(n)
naib=int(np.argmax(shmatky)); vybir=(mitka==naib)
print("кандидатів", int(oblast.sum()), "шматків", len(shmatky), "найбільший", max(shmatky))
bm=bmesh.new(); bm.from_mesh(me); bm.verts.ensure_lookup_table()
sel=set(i for i in np.where(vybir)[0])
faces=[f for f in bm.faces if all(v.index in sel for v in f.verts)]
print("граней волосся", len(faces))
for f in bm.faces: f.select=False
for f in faces: f.select=True
bm.to_mesh(me); bm.free()
bpy.context.view_layer.objects.active=tilo; tilo.select_set(True)
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_mode(type='FACE'); bpy.ops.object.mode_set(mode='OBJECT')
for p in me.polygons: p.select = False
bm=bmesh.new(); bm.from_mesh(me)
for f in bm.faces: f.select = all(v.index in sel for v in f.verts)
bm.to_mesh(me); bm.free()
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.separate(type='SELECTED'); bpy.ops.object.mode_set(mode='OBJECT')
vol=[o for o in bpy.context.scene.objects if o.type=='MESH' and o!=tilo][0]; vol.name="Волосся"
print("ВОЛОССЯ вершин", len(vol.data.vertices), "тіло", len(tilo.data.vertices))
bpy.ops.wm.save_as_mainfile(filepath=out)
