"""Крилаті бестіарію (spec/monsters.md, конвеєр «Д») — кажани, птахи,
грифон, виверни й дракони.

Слово замовника 20.09.2026: «почни з крилатих». Це останній конвеєр, що
лишався: без нього порожні зона 2 (яструб, орел, грифон) і зона 4
(виверни й дракони).

Чим відрізняється від інших конвеєрів. Крило тут — не плаский трикутник,
пришитий до спини (так зроблено крила вампіра в `humanoids.py`, і це
записано в «що слабке»), а ТРИ КІСТКИ в лінію — плече, передпліччя,
кисть — із перетинкою між ними. Кожна панель перетинки сидить на своїй
кістці, тож крило справді складається й махає; суглоби прикриті кулями,
як ланки хвоста в `scorpions.py`.

Перевіряється само:
  · `check_legs` — лапи в спокої й ході стоять на землі;
  · `check_wings` — крила симетричні й не провалюються в тулуб;
  · `check_flap` — у польоті/ході кінчик крила справді ходить угору-вниз.

Запуск (з каталогу проєкту):
    blender --background --python tools/blender/winged.py -- \\
        <вид> [тека_для_картинок]
    blender --background --python tools/blender/winged.py -- --список
"""
import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_hare as h  # noqa: E402
import make_template as base  # noqa: E402
from humanoids import solid, fur_material  # noqa: E402

OUT = os.path.join(h.ROOT, "art", "monsters")

# L — довжина тулуба (м). `лап` — 4 (дракони, грифон), 2 (птахи, виверни),
# 0 (кажан висить на крилах). `шия` — довжина шиї в частках L.
# `перо` — крило пір'їсте (птахи), інакше перетинка.
SPECIES = {
    # Зона 1 — з першої хвилі (вид 29 у переліку бестіарію).
    "кажан-кровопивця": dict(
        L=0.5, лап=2, шия=0.12, розмах=1.5, голова="кажан",
        шкіра=(0.22, 0.16, 0.18), перетинка=(0.30, 0.18, 0.20),
        очі=(0.9, 0.2, 0.1), хвіст=0.3, ікла=True),
    # Зона 2 — імена зі списку замовника 20.09.2026.
    "беркут-високогірник": dict(
        L=0.7, лап=2, шия=0.20, розмах=2.2, голова="птах", перо=True,
        шкіра=(0.30, 0.22, 0.15), перетинка=(0.42, 0.33, 0.22),
        очі=(1.0, 0.8, 0.15), хвіст=0.6, дзьоб=(0.9, 0.75, 0.25),
        комір=(0.78, 0.70, 0.5)),
    "двоголовий беркут-громовержець": dict(
        L=1.5, голів=2, лап=2, шия=0.30, розмах=4.4, голова="птах",
        перо=True, шкіра=(0.24, 0.24, 0.30),
        перетинка=(0.40, 0.42, 0.55), очі=(0.6, 0.9, 1.0),
        світяться=True, хвіст=1.0, дзьоб=(0.85, 0.8, 0.4),
        комір=(0.7, 0.72, 0.8)),
    "хребтовий лускокрил": dict(
        L=1.1, лап=2, шия=0.16, розмах=3.2, голова="кажан",
        шкіра=(0.26, 0.22, 0.20), перетинка=(0.34, 0.30, 0.28),
        очі=(0.95, 0.35, 0.1), хвіст=0.8, ікла=True, шипи=True,
        броня=True),
    # Зона 3 — нежить.
    "мертвий дракон": dict(
        L=3.0, лап=4, шия=0.60, розмах=7.5, голова="дракон",
        шкіра=(0.80, 0.78, 0.70), перетинка=(0.52, 0.50, 0.46),
        очі=(0.4, 0.9, 1.0), світяться=True, хвіст=2.4, роги=0.25,
        шипи=True, кістяк=True),
    # Зона 4 — пустеля й дракони.
    "виверна пустелі": dict(
        L=2.0, лап=2, шия=0.45, розмах=5.0, голова="дракон",
        шкіра=(0.72, 0.58, 0.30), перетинка=(0.80, 0.66, 0.38),
        очі=(1.0, 0.5, 0.05), хвіст=1.6, жало=True, роги=0.18),
    "дракон піску": dict(
        L=2.8, лап=4, шия=0.60, розмах=7.0, голова="дракон",
        шкіра=(0.66, 0.52, 0.26), перетинка=(0.74, 0.60, 0.34),
        очі=(1.0, 0.45, 0.05), хвіст=2.2, роги=0.22, шипи=True,
        луска="луска-піщана"),
    "древній дракон": dict(
        L=4.2, лап=4, шия=0.75, розмах=10.0, голова="дракон",
        шкіра=(0.20, 0.14, 0.16), перетинка=(0.34, 0.16, 0.16),
        очі=(1.0, 0.15, 0.05), світяться=True, хвіст=3.4, роги=0.30,
        шипи=True, луска="луска-темна"),
}

WING = ("плече", "передпліччя", "кисть")


def geometry(s):
    """Кістки й опорні точки. Перед — −Y, верх — +Z, як в усій грі."""
    L = s["L"]
    лап = s["лап"]
    # Висота тулуба над землею: чотирилапі стоять вище за птахів.
    hb = L * (0.55 if лап == 4 else 0.62)
    w = L * 0.20
    bones = [("body", (0, L * 0.38, hb), (0, -L * 0.30, hb), None)]

    шия = L * s["шия"]
    # Голів може бути дві (двоголовий беркут-громовержець зі списку
    # замовника): тоді шиї розходяться вбік, а кістки називаються
    # `neck`/`neck2`. Проба напряму шукає саме «head», тож перша голова
    # лишається з тим самим іменем.
    for k in range(s.get("голів", 1)):
        вбік = 0.0 if s.get("голів", 1) == 1 else (1 if k == 0 else -1) \
            * L * 0.12
        ім = "neck" if k == 0 else "neck%d" % (k + 1)
        ім_г = "head" if k == 0 else "head%d" % (k + 1)
        bones.append((ім, (0, -L * 0.30, hb),
                      (вбік, -L * 0.30 - шия, hb + шия * 0.55), "body"))
        bones.append((ім_г, (вбік, -L * 0.30 - шия, hb + шия * 0.55),
                      (вбік * 1.4, -L * 0.30 - шия - L * 0.22,
                       hb + шия * 0.55), ім))

    # Хвіст — ланцюг, що звужується й трохи опускається.
    хв = s["хвіст"]
    prev, pts = "body", [Vector((0, L * 0.38, hb))]
    for i in range(4):
        pts.append(Vector((0, L * 0.38 + хв * (i + 1) / 4.0,
                           hb - хв * 0.10 * (i + 1) / 4.0)))
    for i in range(4):
        bones.append(("tail%d" % i, tuple(pts[i]), tuple(pts[i + 1]), prev))
        prev = "tail%d" % i

    # Лапи. Задні є завжди (навіть у кажана — він ними чіпляється),
    # передні — лише в чотирилапих.
    ноги = [("hind", L * 0.28)]
    if лап == 4:
        ноги.append(("front", -L * 0.22))
    for назва, y in ноги:
        for side in ("L", "R"):
            sign = 1 if side == "L" else -1
            # Кінець кістки не в нулі, а трохи вище: нижче за нього
            # звисають стопа й кігті, і саме їх міряє проба. Число
            # заміряне `check_legs` (без нього низ сітки був −0,066 м).
            bones.append(("%s.%s" % (назва, side), (sign * w, y, hb),
                          (sign * (w + L * 0.04), y + L * 0.05,
                           L * 0.016), "body"))

    # Крило: три кістки в лінію вбік і трохи назад.
    розмах = s["розмах"]
    # Від плеча, а не від осі тіла: інакше десятиметровий дракон виходив
    # на 11,35 м (заміряно `check_wings`).
    півкрила = max(розмах * 0.5 - w * 0.8, розмах * 0.3)
    частки = (0.36, 0.34, 0.30)
    for side in ("L", "R"):
        sign = 1 if side == "L" else -1
        at = Vector((sign * w * 0.8, -L * 0.14, hb + L * 0.16))
        батько = "body"
        for i, частка in enumerate(частки):
            крок = Vector((sign * півкрила * частка,
                           L * 0.06 * частка,
                           L * 0.10 * (0.5 - i * 0.35)))
            bones.append(("wing.%s%d" % (side, i), tuple(at),
                          tuple(at + крок), батько))
            батько = "wing.%s%d" % (side, i)
            at = at + крок
    return dict(L=L, h=hb, w=w, bones=bones, tail=pts, півкрила=півкрила)


# ─────────────────────────── тіло ───────────────────────────────────

def rod(a, b, radius, mat, bone, сторін=8):
    """Циліндр від a до b на кістці `bone` — як у `scorpions.py`."""
    length = (b - a).length
    bpy.ops.mesh.primitive_cylinder_add(vertices=сторін, radius=radius,
                                        depth=max(length, 1e-4))
    obj = bpy.context.active_object
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = (b - a).normalized().to_track_quat("Z", "Y")
    obj.location = (a + b) * 0.5
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    obj.data.materials.append(mat)
    return obj


def panel(points, товщина, mat, bone, name="Перетинка"):
    """Плоска панель із товщиною — шматок перетинки крила чи пера.

    Своя сітка, а не сплющений конус: конус дає рівнобедрений трикутник,
    а перетинка між двома кістками — це чотирикутник із різною висотою
    країв. Товщина потрібна, бо однобічна грань у glTF зникає, коли
    дивишся на крило з другого боку.
    """
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    bm = bmesh.new()
    вгору = Vector((0, 0, 1)) * (товщина * 0.5)
    низ = [bm.verts.new(tuple(Vector(p) - вгору)) for p in points]
    верх = [bm.verts.new(tuple(Vector(p) + вгору)) for p in points]
    bm.faces.new(низ[::-1])
    bm.faces.new(верх)
    n = len(points)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([низ[i], низ[j], верх[j], верх[i]])
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(mesh.vertices))), 1.0, "REPLACE")
    mesh.materials.append(mat)
    return obj


def wing(rig, s, g, side, шкіра, плівка):
    """Крило: кістки-труби, перетинка панелями по одній на кістку й кулі
    в суглобах. Панель на свою кістку — щоб крило справді складалось."""
    L = g["L"]
    sign = 1 if side == "L" else -1
    out = []
    точки = []
    for i in range(3):
        b = rig.data.bones["wing.%s%d" % (side, i)]
        точки.append((b.head_local.copy(), b.tail_local.copy()))
    # Задній край перетинки: тягнеться назад (+Y) і звужується до кінця.
    глибина = [L * 0.55, L * 0.38, L * 0.16, L * 0.05]
    край = []
    for i, (a, b) in enumerate(точки):
        край.append(a + Vector((0, глибина[i], 0)))
    край.append(точки[-1][1] + Vector((0, глибина[3], 0)))

    for i, (a, b) in enumerate(точки):
        кістка = "wing.%s%d" % (side, i)
        r = L * (0.055 - i * 0.012)
        out.append(rod(a, b, r, шкіра, кістка))
        out.append(base.part("sphere", кістка, tuple(b), (r * 1.2,) * 3,
                             шкіра))
        # Панель — чотирикутник: передній край по кістці, задній зсунуто.
        грані = [a, b, край[i + 1], край[i]]
        if s.get("перо"):
            # Пір'я: сім вузьких пер замість суцільної перетинки —
            # інакше птах виходив із тими самими шкіряними крилами,
            # що й дракон.
            for k in range(7):
                t0 = k / 7.0
                t1 = (k + 0.95) / 7.0
                p0 = a.lerp(b, t0)
                p1 = a.lerp(b, t1)
                d0 = край[i].lerp(край[i + 1], t0)
                d1 = край[i].lerp(край[i + 1], t1)
                out.append(panel([p0, p1, d1, d0], L * 0.012, плівка,
                                 кістка, "Перо"))
        else:
            out.append(panel(грані, L * 0.010, плівка, кістка))
    # Кіготь на згині — по ньому видно, де крило ламається.
    лікоть = точки[1][0]
    out.append(rod(лікоть, лікоть + Vector((sign * L * 0.10, -L * 0.10,
                                            L * 0.05)),
                   L * 0.018, шкіра, "wing.%s1" % side))
    return out


def body(rig, s, g):
    p = base.part
    L, hb, w = g["L"], g["h"], g["w"]
    якщо_луска = s.get("луска")
    шкіра = (fur_material("Шкіра", якщо_луска, 6.0) if якщо_луска
             else solid("Шкіра", s["шкіра"], 0.45))
    черево = solid("Черево", tuple(min(1.0, c * 1.35 + 0.05)
                                   for c in s["шкіра"]), 0.6)
    плівка = solid("Перетинка", s["перетинка"], 0.55)
    око = solid("Очі", s["очі"], 0.25,
                glow=6.0 if s.get("світяться") else 0.6)
    ріг = solid("Ріг", (0.82, 0.78, 0.66), 0.35)
    parts = []

    # Тулуб — ланцюг еліпсоїдів від таза до грудей.
    for i in range(5):
        t = i / 4.0
        y = L * 0.38 - t * L * 0.68
        товщ = 1.0 - 0.45 * abs(t - 0.45) * 2.0
        parts.append(p("sphere", "body", (0, y, hb),
                       (w * товщ, L * 0.15, hb * 0.62 * товщ), шкіра))
        parts.append(p("sphere", "body", (0, y, hb - hb * 0.30),
                       (w * 0.82 * товщ, L * 0.14, hb * 0.30), черево))
    if s.get("кістяк"):
        # Мертвий дракон: ребра поверх тулуба, а не суцільна шкіра.
        for i in range(7):
            y = L * 0.30 - i * L * 0.11
            for sign in (1, -1):
                parts.append(p("sphere", "body",
                               (sign * w * 0.72, y, hb),
                               (L * 0.012, L * 0.02, hb * 0.55), ріг))

    # Шия й голова — стільки разів, скільки голів.
    for k in range(s.get("голів", 1)):
        ім = "neck" if k == 0 else "neck%d" % (k + 1)
        ім_г = "head" if k == 0 else "head%d" % (k + 1)
        шия = rig.data.bones[ім]
        голова = rig.data.bones[ім_г]
        for j in range(5):
            t = (j + 0.5) / 5.0
            at = шия.head_local.lerp(шия.tail_local, t)
            r = L * (0.11 - 0.03 * t)
            parts.append(p("sphere", ім, tuple(at), (r, r * 1.2, r), шкіра))
        парою = голова.head_local.lerp(голова.tail_local, 0.35)
        if s["голова"] == "птах":
            parts.append(p("sphere", ім_г, tuple(парою),
                           (L * 0.085, L * 0.11, L * 0.09), шкіра))
            дзьоб = solid("Дзьоб", s.get("дзьоб", (0.85, 0.7, 0.2)), 0.3)
            parts.append(rod(парою + Vector((0, -L * 0.05, 0)),
                             голова.tail_local + Vector((0, 0, -L * 0.03)),
                             L * 0.045, дзьоб, ім_г, 6))
            if s.get("комір"):
                комір = solid("Комір", s["комір"], 0.7)
                parts.append(p("sphere", ім,
                               tuple(шия.head_local.lerp(шия.tail_local,
                                                         0.75)),
                               (L * 0.13, L * 0.09, L * 0.13), комір))
        else:
            parts.append(p("sphere", ім_г, tuple(парою),
                           (L * 0.09, L * 0.15, L * 0.10), шкіра))
            # Морда витягнута вперед — по ній проба бачить напрям.
            parts.append(p("sphere", ім_г,
                           tuple(голова.tail_local
                                 + Vector((0, L * 0.02, 0))),
                           (L * 0.055, L * 0.09, L * 0.055), шкіра))
            зуб = solid("Зуби", (0.9, 0.88, 0.8), 0.3)
            for sign in (1, -1):
                parts.append(p("sphere", ім_г,
                               tuple(голова.tail_local
                                     + Vector((sign * L * 0.03, L * 0.02,
                                               -L * 0.03))),
                               (L * 0.012, L * 0.02, L * 0.02), зуб))
        if s.get("роги"):
            довж = L * s["роги"]
            for sign in (1, -1):
                корінь = парою + Vector((sign * L * 0.055, L * 0.02,
                                         L * 0.06))
                # Ріг двома ланками, що тоншають: одна тонка палиця
                # читалась як антена (перший огляд).
                згин = корінь + Vector((sign * довж * 0.22, довж * 0.42,
                                        довж * 0.40))
                кінець = згин + Vector((sign * довж * 0.18, довж * 0.52,
                                        довж * 0.18))
                parts.append(rod(корінь, згин, L * 0.040, ріг, ім_г, 6))
                parts.append(rod(згин, кінець, L * 0.024, ріг, ім_г, 6))
        if s.get("ікла"):
            for sign in (1, -1):
                корінь = голова.tail_local + Vector((sign * L * 0.03, 0, 0))
                parts.append(rod(корінь,
                                 корінь + Vector((0, -L * 0.02, -L * 0.07)),
                                 L * 0.012,
                                 solid("Ікла", (0.95, 0.93, 0.85)), ім_г, 6))
        for sign in (1, -1):
            parts.append(p("sphere", ім_г,
                           (парою.x + sign * L * 0.055, парою.y - L * 0.02,
                            парою.z + L * 0.03),
                           (L * 0.022,) * 3, око))

    # Лапи: стегно й гомілка з коліном угору.
    for назва in ("hind", "front"):
        for side in ("L", "R"):
            ім = "%s.%s" % (назва, side)
            if ім not in rig.data.bones:
                continue
            b = rig.data.bones[ім]
            a, t = b.head_local, b.tail_local
            коліно = a.lerp(t, 0.45) + Vector((0, -L * 0.10, 0))
            parts.append(rod(a, коліно, L * 0.055, шкіра, b.name))
            parts.append(rod(коліно, t, L * 0.040, шкіра, b.name))
            parts.append(p("sphere", b.name, tuple(коліно),
                           (L * 0.06,) * 3, шкіра))
            # Стопа з кігтями — інакше лапа втикається в землю палицею.
            parts.append(p("sphere", b.name,
                           tuple(t + Vector((0, -L * 0.03, L * 0.025))),
                           (L * 0.045, L * 0.075, L * 0.025), шкіра))
            for k in (-1, 0, 1):
                кіготь = t + Vector((k * L * 0.03, -L * 0.09, L * 0.012))
                parts.append(rod(t + Vector((0, -L * 0.03, L * 0.02)),
                                 кіготь, L * 0.012, ріг, b.name, 5))

    # Хвіст.
    pts = g["tail"]
    for i in range(4):
        r = L * (0.10 - i * 0.021)
        parts.append(rod(pts[i], pts[i + 1], r, шкіра, "tail%d" % i))
        parts.append(p("sphere", "tail%d" % i, tuple(pts[i + 1]),
                       (r * 1.15,) * 3, шкіра))
        if s.get("шипи"):
            parts.append(rod(pts[i + 1],
                             pts[i + 1] + Vector((0, 0, r * 2.2)),
                             r * 0.32, ріг, "tail%d" % i, 5))
    if s.get("жало"):
        кінець = pts[4]
        parts.append(p("sphere", "tail3", tuple(кінець), (L * 0.05,) * 3,
                       ріг))
        parts.append(rod(кінець, кінець + Vector((0, L * 0.16, -L * 0.04)),
                         L * 0.018, ріг, "tail3", 6))
    elif s.get("перо"):
        # Пір'я хвоста віялом — птахів без нього не впізнати.
        for k in range(-2, 3):
            кінець = pts[4] + Vector((k * L * 0.05, L * 0.22, L * 0.02))
            parts.append(panel([pts[3], pts[4],
                                кінець, кінець + Vector((0, 0, L * 0.01))],
                               L * 0.012, плівка, "tail3", "Перо"))

    for side in ("L", "R"):
        parts += wing(rig, s, g, side, шкіра, плівка)
    return h.join_parts(rig, parts)


# ─────────────────────────── рухи ───────────────────────────────────

# Розмах кроку. Лапа тут одна кістка без коліна, тож повернута вперед
# вона дістає до землі КОРОТШЕ на ℓ·(1−cos θ) — звір ішов би, не
# торкаючись землі. Заміряно: при 22° низ сітки висів на 1,5…2,1 %
# довжини тулуба, при 15° — удвічі менше. Просідання тулуба цього не
# лікує: `location` пози йде вздовж осей кістки, і до світового Z з
# нього доходить менш як п'ята частина (заміряно на древньому драконі).
КРОК = 15.0


def legs_key(g, назви, фаза):
    out = {}
    for назва in назви:
        for side in ("L", "R"):
            ім = "%s.%s" % (назва, side)
            уперед = (side == "L") == фаза
            if назва == "front":
                уперед = not уперед
            # Та лапа, що не крокує, стоїть РІВНО (0°), а не відхилена
            # назад: пряма лапа дістає до землі, відхилена — ні, і при
            # двох відхилених звір ішов, висячи на 1,5 % довжини тулуба
            # (заміряно `check_legs`).
            out[ім] = ((КРОК if уперед else 0.0, 0, 0), (0, 0, 0))
    return out


# Осі крила ЗАМІРЯНО, а не вгадано (вісь Y кістки йде вздовж неї самої,
# тож обертання навколо Y — це скрутка, і крило нею майже не ворушиться:
# перший мах дав хід кінчика 0,14 м на десятиметровий розмах):
#   X  +30° → кінчик угору на 3,89 м, ОДНАКОВО для лівого й правого;
#   Z  +30° → лівий кінчик назад, правий уперед — тож складати треба з
#      різними знаками.
ВГОРУ, НАЗАД = 0, 2


def flap_key(кут, злам=0.0):
    """Мах: плече піднімає все крило, кисть трохи відстає — так змах
    читається живим, а не як обертання дошки."""
    out = {}
    for side in ("L", "R"):
        out["wing.%s0" % side] = ((кут, 0, 0), (0, 0, 0))
        out["wing.%s1" % side] = ((кут * 0.55, 0, 0), (0, 0, 0))
        out["wing.%s2" % side] = ((кут * 0.30 + злам, 0, 0), (0, 0, 0))
    return out


def fold_key(частка):
    """Скласти крило вздовж тіла: плече опустити й відвести назад, а
    передпліччя зламати назад майже вдвоє — тоді крило лягає на спину,
    а не стирчить дошкою вбік (перший огляд: у спокої всі крилаті
    виглядали як тулуб із полицею)."""
    out = {}
    for side in ("L", "R"):
        назад = (1 if side == "L" else -1) * частка
        out["wing.%s0" % side] = ((-42 * частка, 0, 38 * назад),
                                  (0, 0, 0))
        out["wing.%s1" % side] = ((-20 * частка, 0, 135 * назад),
                                  (0, 0, 0))
        out["wing.%s2" % side] = ((-10 * частка, 0, 60 * назад),
                                  (0, 0, 0))
    return out


def actions(rig, s, g):
    лапи = ["hind"] + (["front"] if s["лап"] == 4 else [])
    складені = fold_key(1.0)

    def з(основа, **іще):
        k = dict(основа)
        for назва, rot in іще.items():
            k[назва.replace("_", ".")] = (rot, (0, 0, 0))
        return k

    # Спокій: крила складені, шия дихає.
    h.action(rig, "Idle", 60, {
        1: складені,
        20: з(складені, neck=(-5, 0, 0), tail1=(0, 0, 6)),
        40: з(складені, neck=(4, 0, 0), tail1=(0, 0, -6)),
        60: складені,
    })

    # Хода: лапи крокують, крила напівскладені й поводять.
    півскладені = fold_key(0.62)

    def крок(фаза, кут):
        k = dict(півскладені)
        k.update(legs_key(g, лапи, фаза))
        for назва, значення in flap_key(кут).items():
            старе = k.get(назва, ((0, 0, 0), (0, 0, 0)))
            k[назва] = ((старе[0][0] + значення[0][0],
                         старе[0][1] + значення[0][1],
                         старе[0][2] + значення[0][2]), (0, 0, 0))
        return k
    h.action(rig, "Walk", 20, {1: крок(True, 8), 10: крок(False, -8),
                               20: крок(True, 8)})

    # Політ: крила навстіж, широкий мах. Гра шукає «Flying», коли немає
    # «Walk» (`skinned_model.gd`), тож рух є, хоч і не грається зараз.
    h.action(rig, "Flying", 24, {
        1: flap_key(-38, 10),
        8: flap_key(6),
        16: flap_key(42, -14),
        24: flap_key(-38, 10),
    })

    # Удар: крила розкрити, шию назад і кинути голову вперед.
    h.action(rig, "Attack", 22, {
        1: складені,
        6: з(flap_key(-26), neck=(-30, 0, 0), head=(-18, 0, 0)),
        11: з(flap_key(14), neck=(34, 0, 0), head=(26, 0, 0)),
        16: з(flap_key(-4), neck=(10, 0, 0)),
        22: складені,
    })

    h.action(rig, "Death", 36, {
        1: складені,
        14: з(fold_key(0.5), body=(0, 0, 0), neck=(-20, 0, 0)),
        36: з(fold_key(0.3), body=(0, 118, 0), neck=(30, 0, 0)),
    })
    rig.animation_data.action = bpy.data.actions["Idle"]


# ───────────────────────── перевірки ────────────────────────────────

WARN = []


def _tip(rig, кістка):
    return rig.matrix_world @ rig.pose.bones[кістка].tail


def _lowest(mesh):
    """Найнижча точка СІТКИ з урахуванням пози — саме її міряє проба
    `own_models`. По кінцях кісток виходила брехня: стопа й кігті
    звисають нижче за кістку."""
    dg = bpy.context.evaluated_depsgraph_get()
    готове = mesh.evaluated_get(dg)
    сітка = готове.to_mesh()
    низ = min((готове.matrix_world @ v.co).z for v in сітка.vertices)
    готове.to_mesh_clear()
    return низ


def check_legs(rig, mesh, s, g):
    """Низ СІТКИ в спокої й ході — на землі. Той самий захід, що зловив
    ходулі в зайця й перевернутий знак у скорпіона."""
    scene = bpy.context.scene
    звіт = []
    for назва in ("Idle", "Walk"):
        act = bpy.data.actions[назва]
        rig.animation_data.action = act
        низи = []
        for f in sorted({int(kp.co.x) for fc in h.curves(act)
                         for kp in fc.keyframe_points}):
            scene.frame_set(f)
            низ = _lowest(mesh)
            низи.append(низ)
            if abs(низ) > 0.012 * max(1.0, g["L"]):
                WARN.append("%s кадр %d: низ сітки %+.3f м" % (назва, f,
                                                               низ))
        звіт.append("%s %+.3f…%+.3f" % (назва, min(низи), max(низи)))
    rig.animation_data.action = bpy.data.actions["Idle"]
    scene.frame_set(1)
    return ", ".join(звіт)


def check_wings(rig, s, g):
    """Крила симетричні, розмах той, що замовлено, і кінчик не всередині
    тулуба."""
    scene = bpy.context.scene
    rig.animation_data.action = bpy.data.actions["Flying"]
    scene.frame_set(8)          # кадр, де крила найрівніші
    лів, прав = _tip(rig, "wing.L2"), _tip(rig, "wing.R2")
    розмах = abs(лів.x) + abs(прав.x)
    перекіс = abs(abs(лів.x) - abs(прав.x))
    if перекіс > g["L"] * 0.02:
        WARN.append("крила несиметричні: %+.3f проти %+.3f" % (лів.x,
                                                               прав.x))
    if розмах < s["розмах"] * 0.7:
        WARN.append("розмах %.2f м замість %.2f" % (розмах, s["розмах"]))
    if abs(лів.x) < g["w"] * 1.5:
        WARN.append("кінчик крила в тулубі: x %+.3f" % лів.x)
    rig.animation_data.action = bpy.data.actions["Idle"]
    scene.frame_set(1)
    return "розмах %.2f м, перекіс %.3f" % (розмах, перекіс)


def check_folded(rig, s, g):
    """У спокої крило складене НА ТІЛО, а не стирчить убік: кінчик має
    бути ближче за чверть розмаху від осі."""
    scene = bpy.context.scene
    rig.animation_data.action = bpy.data.actions["Idle"]
    scene.frame_set(1)
    вбік = max(abs(_tip(rig, "wing.%s2" % side).x) for side in ("L", "R"))
    межа = s["розмах"] * 0.25
    if вбік > межа:
        WARN.append("складене крило стирчить: кінчик за %.2f м від осі "
                    "(межа %.2f)" % (вбік, межа))
    return "складене — кінчик за %.2f м від осі" % вбік


def check_flap(rig):
    """Крило справді махає: за політ кінчик має пройти вгору-вниз, а не
    стояти. Пласкі крила вампіра саме цим і були погані."""
    scene = bpy.context.scene
    rig.animation_data.action = bpy.data.actions["Flying"]
    висоти = []
    for f in range(1, 25):
        scene.frame_set(f)
        висоти.append(_tip(rig, "wing.L2").z)
    хід = max(висоти) - min(висоти)
    if хід < 0.05:
        WARN.append("крило не махає: хід кінчика %.3f м" % хід)
    rig.animation_data.action = bpy.data.actions["Idle"]
    scene.frame_set(1)
    return "хід кінчика %.2f м" % хід


def build(назва, shots=None):
    s = SPECIES[назва]
    base.clear()
    bpy.context.scene.render.fps = 24
    g = geometry(s)
    rig = h.armature(g["bones"])
    mesh = body(rig, s, g)
    actions(rig, s, g)
    лапи = check_legs(rig, mesh, s, g)
    крила = check_wings(rig, s, g)
    складене = check_folded(rig, s, g)
    мах = check_flap(rig)
    if shots:
        h.previews(rig, shots, zoom=max(1.0, s["розмах"] * 1.1 / 0.6))
    out = os.path.join(OUT, назва + ".blend")
    bpy.ops.wm.save_as_mainfile(filepath=out)
    print("[крилаті] %s → %s" % (назва, out))
    print("[крилаті]   лапи: %s · %s" % (лапи, крила))
    print("[крилаті]   %s · %s" % (складене, мах))
    for рядок in WARN:
        print("[крилаті] ‼ %s: %s" % (назва, рядок))


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if not args or args[0] == "--список":
        print("[крилаті] види: " + ", ".join(SPECIES))
        return
    build(args[0], args[1] if len(args) > 1 else None)


if __name__ == "__main__":
    main()
