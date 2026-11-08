"""Пілот Б (П-281), крок 3 — риси обличчя людини MPFB для вибору в грі.

Слово замовника 08.11.2026: «маю на увазі, що вказані моделі мають
декілька типів зачіски, колір зачіски, очі — колір, очі — підводка, форма
очей, вуха, ніс, губи, колір губ, колір шкіри, декілька скінів … вивчи
досконало … запропонуй 3 варіанти, щоб можна було визначити якіснішу».

Ті самі 12 форм-ключів, що в ельфійок (`elf_rysy.py`), — тоді меню,
збереження й набори вигляду (`appearance.gd`) працюють без змін:
  Ніс-кирпатий/-з-горбинкою/-вузький, Губи-повні/-тонкі/-усмішка,
  Очі-мигдалеві/-великі/-вузькі, Вуха-довгі/-короткі/-підняті.

Спосіб:
  гаус — як у ельфійок: гладкі зсуви довкола точок обличчя (точки — з
         груп вершин MPFB замість MediaPipe);
  цілі — суміші анатомічних цілей MakeHuman (`targets/nose|mouth|eyes|ears`).

Очі, брови й вії MPFB — окремі сітки, прив'язані до тіла (.mhclo): для
кожного ключа тіла вони переприлаштовуються (`fit_clothes_to_human`) і
дістають свій ключ з тим самим ім'ям. Помічники MPFB і згладжування
застосовуються в сітку з ключами (експортер glTF не застосовує модифікатори
до сіток із ключами). Поруч пишеться `<вихід>.npz` — UV і ваги для масок
(губи, підводка, скальп; `tools/pilot_maski.py`).

    blender -b <зачіски.blend> -P tools/blender/pilot_rysy.py -- <вихід.blend> --спосіб гаус|цілі
"""
import functools
import os
import sys

import bpy
import numpy as np

from bl_ext.blender_org.mpfb.entities.clothes.mhclo import Mhclo
from bl_ext.blender_org.mpfb.services.clothesservice import ClothesService as CS
from bl_ext.blender_org.mpfb.services.locationservice import LocationService
from bl_ext.blender_org.mpfb.services.targetservice import TargetService as TS

print = functools.partial(print, flush=True)
ARGS = sys.argv[sys.argv.index("--") + 1:]
VYKHID = os.path.abspath(ARGS[0])
SPOSIB = ARGS[ARGS.index("--спосіб") + 1]
DANI = LocationService.get_user_data()

h = bpy.data.objects["Human"]
rig = bpy.data.objects["Human.rig"]
me = h.data
for pb in rig.pose.bones:
    pb.matrix_basis.identity()
if me.shape_keys is None:
    h.shape_key_add(name="Basis", from_mix=False)
co = np.array([v.co[:] for v in me.vertices])      # усі вершини, з помічниками
gi = {g.name: g.index for g in h.vertex_groups}


def hrupa(name, porih=0.0):
    i = gi[name]
    w = np.zeros(len(co))
    for v in me.vertices:
        for g in v.groups:
            if g.group == i:
                w[v.index] = g.weight
    return w if porih <= 0 else (w > porih)


TILO = hrupa("body", 0.5)
VP = np.array([0, -1.0, 0])     # уперед (MPFB дивиться в −Y)
UP = np.array([0, 0, 1.0])

# ── Форм-ключі тіла ──────────────────────────────────────────────────────
TSILI = {
    "Ніс-кирпатий": {"nose-point-up": 1.0, "nose-scale-vert-decr": 0.4,
                     "nose-septumangle-decr": 0.5},
    "Ніс-з-горбинкою": {"nose-hump-incr": 1.0, "nose-point-down": 0.5,
                        "nose-scale-depth-incr": 0.3},
    "Ніс-вузький": {"nose-width1-decr": 0.8, "nose-width2-decr": 0.8,
                    "nose-width3-decr": 0.6, "nose-nostrils-width-decr": 0.6,
                    "nose-flaring-decr": 0.5},
    "Губи-повні": {"mouth-upperlip-volume-incr": 1.0, "mouth-lowerlip-volume-incr": 1.0,
                   "mouth-cupidsbow-incr": 0.5},
    "Губи-тонкі": {"mouth-upperlip-volume-decr": 1.0, "mouth-lowerlip-volume-decr": 1.0,
                   "mouth-upperlip-height-decr": 0.5, "mouth-lowerlip-height-decr": 0.5},
    "Губи-усмішка": {"mouth-angles-up": 1.0, "mouth-dimples-in": 0.4},
    "Очі-мигдалеві": {"%s-eye-corner2-up": 1.0, "%s-eye-height2-decr": 0.3,
                      "%s-eye-eyefold-angle-up": 0.5},
    "Очі-великі": {"%s-eye-scale-incr": 0.7, "%s-eye-height1-incr": 0.5,
                   "%s-eye-height2-incr": 0.5, "%s-eye-height3-incr": 0.5},
    "Очі-вузькі": {"%s-eye-height1-decr": 0.8, "%s-eye-height2-decr": 0.8,
                   "%s-eye-height3-decr": 0.8, "%s-eye-eyefold-down": 0.5},
    "Вуха-довгі": {"%s-ear-scale-vert-incr": 1.0, "%s-ear-lobe-incr": 0.6},
    "Вуха-короткі": {"%s-ear-scale-vert-decr": 1.0, "%s-ear-lobe-decr": 0.5},
    "Вуха-підняті": {"%s-ear-trans-up": 0.8, "%s-ear-rot-backward": 0.5,
                     "%s-ear-wing-incr": 0.5},
}


def kliuchi_tsili():
    for imia, sumish in TSILI.items():
        tymchasovi = []
        for t, w in sumish.items():
            for bik in (("l", "r") if "%s" in t else (None,)):
                nt = t % bik if bik else t
                k = TS.load_target(h, TS.target_full_path(nt), weight=w, name="т-" + nt)
                tymchasovi.append(k)
        for k in me.shape_keys.key_blocks:
            if k.name != "Basis" and not k.name.startswith("т-"):
                k.value = 0.0
        k = h.shape_key_add(name=imia, from_mix=True)
        for t in tymchasovi:
            h.shape_key_remove(t)
        k.value = 0.0
        d = np.array([p.co[:] for p in k.data]) - co
        print("[риси] %-16s вершин %5d, найбільший зсув %.1f мм"
              % (imia, int((np.abs(d).sum(1) > 1e-5).sum()), np.abs(d).max() * 1000))


def kliuch(imia, zsuv):
    k = h.shape_key_add(name=imia, from_mix=False)
    k.data.foreach_set("co", (co + zsuv).ravel())
    print("[риси] %-16s вершин %5d, найбільший зсув %.1f мм"
          % (imia, int((np.abs(zsuv).sum(1) > 1e-5).sum()), np.abs(zsuv).max() * 1000))


def kliuchi_gaus():
    """Формули `elf_rysy.py`; точки обличчя — з груп і геометрії MPFB."""
    def centr(name):
        w = hrupa(name)
        return (co * w[:, None]).sum(0) / max(w.sum(), 1e-9)

    oko_l, oko_r = centr("joint-l-eye"), centr("joint-r-eye")
    w_g = hrupa("lips", 0.5)
    rot = co[w_g].mean(0)               # середина губ
    x_mid = 0.0
    hd_y = float(np.median(co[TILO & (co[:, 2] > oko_l[2] - 0.12), 1]))
    pered = (co[:, 1] - hd_y) * -1 > -0.01
    sered = TILO & (np.abs(co[:, 0]) < 0.003)

    def napered(m):
        i = np.where(m)[0]
        return co[i[np.argmin(co[i, 1])]]

    kinchyk = napered(sered & (co[:, 2] < oko_l[2] - 0.015) & (co[:, 2] > rot[2] + 0.01))
    pid = napered(sered & (co[:, 2] < kinchyk[2] - 0.008) & (co[:, 2] > kinchyk[2] - 0.02))
    perenis = napered(sered & (np.abs(co[:, 2] - (kinchyk[2] + 0.025)) < 0.003))
    mizh_ochi = napered(sered & (np.abs(co[:, 2] - oko_l[2]) < 0.004))
    print("[риси] точки: кінчик носа z %.3f, рот z %.3f, очі z %.3f"
          % (kinchyk[2], rot[2], oko_l[2]))

    def gaus(c, sigma):
        w = np.exp(-((co - c) ** 2).sum(1) / (2 * sigma ** 2)) * pered
        w[w < 1e-3] = 0
        return w

    def bik(p):
        return np.array([np.sign(p[0] - x_mid), 0, 0])

    z = np.zeros_like(co)
    z += gaus(kinchyk, 0.007)[:, None] * (UP * 0.0030 - VP * 0.0004)
    z += gaus(pid, 0.005)[:, None] * (UP * 0.0020)
    kliuch("Ніс-кирпатий", z * 1.7)
    z = np.zeros_like(co)
    z += gaus(perenis, 0.006)[:, None] * (VP * 0.0026)
    z += gaus(kinchyk, 0.006)[:, None] * (-UP * 0.0025 + VP * 0.0008)
    kliuch("Ніс-з-горбинкою", z * 1.7)
    z = np.zeros_like(co)
    for s in (-1, 1):
        for dz in (-0.006, 0.0, 0.008):
            m = TILO & (np.sign(co[:, 0]) == s) & (np.abs(co[:, 0]) > 0.008) \
                & (np.abs(co[:, 0]) < 0.022) & (np.abs(co[:, 2] - (kinchyk[2] + dz)) < 0.003)
            if m.any():
                p = napered(m)
                z += gaus(p, 0.005)[:, None] * (-bik(p) * 0.0020)
    w_ = gaus(mizh_ochi, 0.009)
    z[:, 0] += -(co[:, 0] - x_mid) * 0.25 * w_
    kliuch("Ніс-вузький", z)

    guby = hrupa("lips", 0.5)
    gv = napered(guby & (np.abs(co[:, 0]) < 0.004) & (co[:, 2] > rot[2]))
    gn = napered(guby & (np.abs(co[:, 0]) < 0.004) & (co[:, 2] < rot[2]))
    z = np.zeros_like(co)
    z += gaus(gv, 0.007)[:, None] * (VP * 0.0018 + UP * 0.0008)
    z += gaus(gn, 0.007)[:, None] * (VP * 0.0018 - UP * 0.0010)
    kliuch("Губи-повні", z * 1.7)
    z = np.zeros_like(co)
    z += gaus(gv, 0.007)[:, None] * (-VP * 0.0012 - UP * 0.0006)
    z += gaus(gn, 0.007)[:, None] * (-VP * 0.0012 + UP * 0.0007)
    kliuch("Губи-тонкі", z * 1.7)
    z = np.zeros_like(co)
    for s in (-1, 1):
        i = np.where(guby & (np.sign(co[:, 0]) == s))[0]
        p = co[i[np.argmax(np.abs(co[i, 0]))]]
        z += gaus(p, 0.006)[:, None] * (bik(p) * 0.0010 - VP * 0.0005 + UP * 0.0022)
    kliuch("Губи-усмішка", z * 1.7)

    # Очі: контур повіки — помічники вій MPFB (дві смуги на око).
    z = np.zeros_like(co)
    z2 = np.zeros_like(co)
    zm = np.zeros_like(co)
    for s in ("l", "r"):
        kontur = co[hrupa("helper-%s-eyelashes-1" % s, 0.5) | hrupa("helper-%s-eyelashes-2" % s, 0.5)]
        zovn = kontur[np.argmax(np.abs(kontur[:, 0]))]
        zm += gaus(zovn, 0.005)[:, None] * (UP * 0.0018 + bik(zovn) * 0.0008)
        c = kontur.mean(0)
        # гаус лише спереду — а очне яблуко MPFB (помічник) — усе разом
        w_ = np.exp(-((co - c) ** 2).sum(1) / (2 * 0.009 ** 2))[:, None]
        r = co - c
        r[:, 1] = 0
        z += w_ * r * 0.16
        z2 += w_ * np.c_[np.zeros(len(co)), np.zeros(len(co)), -(co[:, 2] - c[2]) * 0.28]
    kliuch("Очі-мигдалеві", zm)
    kliuch("Очі-великі", z)
    kliuch("Очі-вузькі", z2)

    # Вуха — група «ears» MPFB (без пошуку за сферою черепа, як у скану).
    vukha = hrupa("ears")
    verkh = co[TILO & (co[:, 2] > co[TILO, 2].max() - 0.07) & (np.abs(co[:, 0]) < 0.07)]
    A = np.c_[2 * verkh, np.ones(len(verkh))]
    c4 = np.linalg.lstsq(A, (verkh ** 2).sum(1), rcond=None)[0]
    C = c4[:3]
    zd, zk, zp = (np.zeros_like(co) for _ in range(3))
    for s in (-1, 1):
        m = (vukha > 0.5) & (np.sign(co[:, 0]) == s)
        d_c = np.linalg.norm(co[m] - C, axis=1)
        korin = co[m][d_c < np.percentile(d_c, 15)].mean(0)
        r = co - korin
        dist = np.linalg.norm(r, axis=1)
        kinets = np.percentile(dist[m], 98)
        t = np.clip((dist - 0.008) / max(kinets - 0.008, 1e-3), 0, 1) ** 1.5
        w_ = (t * vukha * (np.sign(co[:, 0]) == s))[:, None]
        zd += w_ * r * 0.45
        zk += w_ * r * -0.35
        zp += w_ * (UP * 0.018 - VP * 0.004) * (dist / max(kinets, 1e-3))[:, None]
        print("[риси] вухо %+d: вершин %d, довжина %.1f см" % (s, int(m.sum()), kinets * 100))
    kliuch("Вуха-довгі", zd)
    kliuch("Вуха-короткі", zk)
    kliuch("Вуха-підняті", zp)


if SPOSIB == "цілі":
    kliuchi_tsili()
elif SPOSIB == "гаус":
    kliuchi_gaus()
else:
    raise SystemExit("--спосіб гаус|цілі")
IMENA = list(TSILI)

# ── Підводка: смуга вздовж повік (помічники вій), верхня ширша ───────────
pv = np.zeros(len(co))
for s in ("l", "r"):
    for n, shyr in (("helper-%s-eyelashes-1" % s, 0.0045), ("helper-%s-eyelashes-2" % s, 0.0025)):
        p = co[hrupa(n, 0.5)]
        d =np.min(np.linalg.norm(co[:, None, :] - p[None, ::3, :], axis=2), axis=1) \
            if len(p) else np.full(len(co), 9.0)
        pv = np.maximum(pv, np.clip(1 - d / shyr, 0, 1) * TILO)
hp = h.vertex_groups.new(name="маска-підводка")
for i in np.where(pv > 0)[0]:
    hp.add([int(i)], float(pv[i]), "REPLACE")
print("[риси] підводка: вершин %d" % int((pv > 0).sum()))

# ── Очі, брови, вії — переприлаштувати під кожен ключ ────────────────────
PROKSI = []
for o in bpy.data.objects:
    if o.type != "MESH" or o.parent != rig or o == h:
        continue
    for grp, pref in (("eyes", "high-poly"), ("eyes", "low-poly"),
                      ("eyebrows", "eyebrow"), ("eyelashes", "eyelashes")):
        n = o.name.split(".", 1)[-1]
        if n.startswith(pref):
            d = os.path.join(DANI, grp, n)
            m = Mhclo()
            m.load(os.path.join(d, next(f for f in os.listdir(d) if f.endswith(".mhclo"))))
            m.clothes = o
            PROKSI.append((o, m))
for o, m in PROKSI:
    o.shape_key_add(name="Basis", from_mix=False)
for imia in IMENA:
    for k in me.shape_keys.key_blocks:
        k.value = 1.0 if k.name == imia else 0.0
    for o, m in PROKSI:
        base = np.array([v.co[:] for v in o.data.shape_keys.key_blocks["Basis"].data])
        CS.fit_clothes_to_human(o, h, m, set_parent=False)
        fit = np.array([v.co[:] for v in o.data.vertices])
        # ключ = база + зсув підбору (база — підбір без ключів, звірено 0 мм)
        k = o.shape_key_add(name=imia, from_mix=False)
        k.data.foreach_set("co", fit.ravel())
        o.data.vertices.foreach_set("co", base.ravel())
for k in me.shape_keys.key_blocks:
    k.value = 0.0
for o, m in PROKSI:
    for k in o.data.shape_keys.key_blocks:
        k.value = 0.0
print("[риси] прилаштовано:", [o.name for o, _ in PROKSI])


def zastosuvaty(o):
    """Модифікатори (крім скелета) — у сітку, зберігши форм-ключі."""
    mody = [md for md in o.modifiers if md.type != "ARMATURE"]
    if not mody:
        return
    for md in o.modifiers:
        if md.type == "ARMATURE":
            md.show_viewport = False
    kb = o.data.shape_keys.key_blocks
    imena = [k.name for k in kb]
    stany = {}
    for imia in imena:
        for k in kb:
            k.value = 1.0 if (k.name == imia and imia != "Basis") else 0.0
        dg = bpy.context.evaluated_depsgraph_get()
        ev = o.evaluated_get(dg)
        stany[imia] = np.array([v.co[:] for v in ev.data.vertices])
    for k in kb:
        k.value = 0.0
    dg = bpy.context.evaluated_depsgraph_get()
    nova = bpy.data.meshes.new_from_object(o.evaluated_get(dg), preserve_all_data_layers=True,
                                           depsgraph=dg)
    stara = o.data
    o.data = nova
    for md in mody:
        o.modifiers.remove(md)
    for md in o.modifiers:
        md.show_viewport = True
    if nova.shape_keys is not None:
        o.shape_key_clear()
    o.shape_key_add(name="Basis", from_mix=False)
    for imia in imena[1:]:
        k = o.shape_key_add(name=imia, from_mix=False)
        k.data.foreach_set("co", stany[imia].ravel())
    nova.name = stara.name
    print("[риси] %s: модифікатори %s застосовано, вершин %d, ключів %d"
          % (o.name, [md.name for md in mody] if False else len(mody), len(nova.vertices), len(imena) - 1))


for o in [h] + [o for o, _ in PROKSI]:
    zastosuvaty(o)

# ── Дані масок: UV трикутників і ваги (губи, підводка, скальп) ───────────
me = h.data
me.calc_loop_triangles()
gi = {g.name: g.index for g in h.vertex_groups}
vazhi = np.zeros((len(me.vertices), 3))
for v in me.vertices:
    for g in v.groups:
        for j, n in enumerate(("маска-підводка", "lips", "scalp")):
            if g.group == gi[n]:
                vazhi[v.index, j] = g.weight
uv = me.uv_layers.active.data
tri_uv = np.array([[uv[li].uv[:] for li in t.loops] for t in me.loop_triangles])
tri_v = np.array([t.vertices[:] for t in me.loop_triangles])
np.savez(os.path.splitext(VYKHID)[0] + ".npz", uv=tri_uv, w=vazhi[tri_v])
print("[риси] маски: трикутників %d, підводка %d, губи %d, скальп %d вершин"
      % (len(tri_v), *(int((vazhi[:, j] > 0).sum()) for j in range(3))))
bpy.ops.wm.save_as_mainfile(filepath=VYKHID)
print("[риси] →", VYKHID)
