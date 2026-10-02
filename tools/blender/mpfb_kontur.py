"""Підтягнути сітку MPFB під контури кадрів спереду, збоку й ззаду
(02.10.2026).

Слово замовника: «висоти здається вирівняв але є неспівпадіння осей рук ,
ніг, вигинів тіла, спробуй підтягнути модель щоб співпадала по контурах в 3х
проекціях». Повзунки MakeHuman таких дрібниць не досягають, тож після
підбору повзунків — нежорстке підтягування:

1. для кожного виду модель (у позі цього кадру) проєктується в пікселі
   кадру тим самим правилом, що й текстура (`mpfb_avatar.proektsiia`), і її
   силует малюється трикутниками;
2. кожна точка контуру моделі тягнеться до найближчої точки контуру кадру
   (волосся з кадрів збоку й ззаду знято, `mpfb_pidbir.bez_volossia`),
   не далі ніж на 30 px; поле зсувів розмивається гаусом (σ ≈ 20 px), тож
   кінцівка зсувається цілою, а не лише краєм — так вирівнюються й осі;
3. по горизонталі зсув дають перед і зад (середнє), у глибину — профіль,
   по висоті — усі три; голова (обличчя вже підібране за точками), кисті й
   ступні (на кадрах у інших позах) не тягнуться, і їхні контури не тягнуть
   сусідів;
4. три проходи; зсув із пози кадру переводиться в спокій через кістки
   (обернене лінійне змішування) і лягає ключем форми «контури».
"""
import math

import bpy
import cv2
import numpy as np
from mathutils import Matrix

import mpfb_pidbir as P

import os as _os
MAKS_PX = 30.0       # найдальший зсув точки контуру, px кадру
SIGMA_PX = float(_os.environ.get("KONTURY_SIGMA", "20"))  # розмиття поля
MAKS_M = 0.04        # найдальший зсув вершини за прохід, м
PROKHODY = int(_os.environ.get("KONTURY_PROKHODY", "3"))


def _maska(shliakh):
    img = bpy.data.images.load(shliakh, check_existing=True)
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    return px.reshape(h, w, 4)[..., 0] > 0.5           # рядок 0 — низ


def _vagy_grup(h, imena_poch):
    me = h.data
    v = np.zeros(len(me.vertices))
    idx = {g.index for g in h.vertex_groups
           if g.name.split("_")[0] in imena_poch}
    for vx in me.vertices:
        for g in vx.groups:
            if g.group in idx:
                v[vx.index] += g.weight
    return np.clip(v, 0, 1)


def _matrytsi_kistok(h, arm):
    """Для кожної вершини — 3×3 лінійного змішування кісток (поза → спокій
    для оберненого переходу)."""
    me = h.data
    imena = {g.index: g.name for g in h.vertex_groups}
    Mb = {}
    for pb in arm.pose.bones:
        Mb[pb.name] = np.array((pb.matrix @ pb.bone.matrix_local.inverted())
                               .to_3x3())
    M = np.zeros((len(me.vertices), 3, 3))
    s = np.zeros(len(me.vertices))
    for vx in me.vertices:
        for g in vx.groups:
            n = imena.get(g.group)
            if n in Mb and g.weight > 0:
                M[vx.index] += g.weight * Mb[n]
                s[vx.index] += g.weight
    bez = s < 1e-6
    M[bez] = np.eye(3)
    M[~bez] /= s[~bez, None, None]
    return M


def _syluet(px, py, tris, vidymi, w, hh):
    m = np.zeros((hh, w), np.uint8)
    t = tris[vidymi[tris].all(1)]
    poly = np.stack([px[t], py[t]], -1).round().astype(np.int32)
    # По одному трикутнику: fillPoly зі списком тисяч трикутників, що
    # перекриваються, заливає за парністю — силует виходив дротяною сіткою з
    # дірами (кожна діра — хибний контур).
    for tr in poly:
        cv2.fillConvexPoly(m, tr, 1)
    return m > 0


def _pole(m_mod, m_ref, ne_tiahnuty):
    """Поле зсувів (dx, dy) у пікселях кадру: контур моделі → найближчий
    контур кадру, розмите гаусом."""
    k3 = np.ones((3, 3), np.uint8)
    kr_mod = m_mod & ~cv2.erode(m_mod.astype(np.uint8), k3).astype(bool)
    kr_ref = m_ref & ~cv2.erode(m_ref.astype(np.uint8), k3).astype(bool)
    kr_mod &= ~ne_tiahnuty
    if not kr_ref.any() or not kr_mod.any():
        return np.zeros(m_mod.shape), np.zeros(m_mod.shape)
    # найближча точка контуру кадру для кожного пікселя
    _, lab = cv2.distanceTransformWithLabels(
        (~kr_ref).astype(np.uint8), cv2.DIST_L2, 5,
        labelType=cv2.DIST_LABEL_PIXEL)
    ys_r, xs_r = np.where(kr_ref)
    tsil = np.zeros((lab.max() + 1, 2))
    tsil[lab[ys_r, xs_r]] = np.stack([xs_r, ys_r], 1)
    ys, xs = np.where(kr_mod)
    q = tsil[lab[ys, xs]]
    d = q - np.stack([xs, ys], 1)
    dl = np.linalg.norm(d, axis=1)
    d[dl > MAKS_PX] *= (MAKS_PX / dl[dl > MAKS_PX])[:, None]
    Fx = np.zeros(m_mod.shape)
    Fy = np.zeros(m_mod.shape)
    W = np.zeros(m_mod.shape)
    Fx[ys, xs], Fy[ys, xs], W[ys, xs] = d[:, 0], d[:, 1], 1.0
    s = SIGMA_PX
    Fx, Fy = cv2.GaussianBlur(Fx, (0, 0), s), cv2.GaussianBlur(Fy, (0, 0), s)
    W = cv2.GaussianBlur(W, (0, 0), s)
    ok = W > 1e-3
    Fx[ok] /= W[ok]
    Fy[ok] /= W[ok]
    # далеко від усіх контурів — згасає
    zgas = np.clip(W / 0.02, 0, 1)
    return Fx * zgas, Fy * zgas


def pidtiahnuty(h, arm, kut_ruk, pered, m_pered, bik, m_bik, zad, m_zad,
                oko_ref_y):
    """Ключ форми «контури» — зсуви вершин у спокої (див. опис модуля)."""
    me = h.data
    if me.shape_keys is None:
        h.shape_key_add(name="Basis", from_mix=False)
    kl = h.shape_key_add(name="контури", from_mix=False)
    kl.value = 1.0
    baza = np.array([v.co[:] for v in kl.data])
    zsuv_spokii = np.zeros_like(baza)
    gi = h.vertex_groups["body"].index
    vidymi = np.array([any(g.group == gi and g.weight > 0.5 for g in v.groups)
                       for v in me.vertices])
    ne_ruky_bik = 1 - _vagy_grup(h, ("upperarm", "lowerarm", "hand", "thumb",
                                     "index", "middle", "ring", "pinky"))
    vilni = _vagy_grup(h, ("head", "hand", "thumb", "index", "middle", "ring",
                           "pinky", "foot", "ball"))
    tiahnuty = np.clip(1 - 1.5 * vilni, 0, 1) * vidymi
    # Голова — лише по горизонталі спереду й ззаду (замовник: «трохи
    # витягнув модель облича, щоб воно було схоже на рендер, не таке
    # широке»): обрис щік і щелепи тягнеться до кадру, точки обличчя
    # (підбір за MediaPipe) лежать усередині й не зачіпаються.
    vilni_kraii = _vagy_grup(h, ("hand", "thumb", "index", "middle", "ring",
                                 "pinky", "foot", "ball"))
    holova = _vagy_grup(h, ("head",))
    tiahnuty_x = np.clip(1 - 1.5 * vilni_kraii, 0, 1) * vidymi
    mk_p = _maska(m_pered)
    mk_b = P.bez_volossia(_maska(m_bik), bik, "бік")
    mk_z = P.bez_volossia(_maska(m_zad), zad, "зад")
    hh, w = mk_p.shape
    for prokhid in range(PROKHODY):
        rez = {}
        for vyd in ("перед", "зад", "бік"):
            P.postavyty_ruky(arm, P.kut_biku(kut_ruk) if vyd == "бік"
                             else kut_ruk)
            co, nrm = P.vershyny_bez_masky(h)
            # Трикутники — з сітки без модифікатора MASK (як вершини у
            # `vershyny_bez_masky`): з маскою номери вершин інші, і силует
            # виходив сміттям (перша спроба: збіг 0,47 і гіршав щопроходу).
            mm = [m for m in h.modifiers if m.type == "MASK"]
            for m in mm:
                m.show_viewport = False
            bpy.context.view_layer.update()
            dg = bpy.context.evaluated_depsgraph_get()
            ev = h.evaluated_get(dg)
            me_e = ev.to_mesh()
            me_e.calc_loop_triangles()
            tris = np.array([t.vertices[:] for t in me_e.loop_triangles])
            assert len(me_e.vertices) == len(co), "порядок вершин змінився"
            ev.to_mesh_clear()
            for m in mm:
                m.show_viewport = True
            M = _matrytsi_kistok(h, arm)
            z = co[:, 2]
            zz = z[vidymi]
            z0, z1 = zz.min(), zz.max()
            tulm = (zz > z1 - 0.45 * (z1 - z0)) & (zz < z1 - 0.30 * (z1 - z0))
            if vyd == "бік":
                t_ = math.radians(P.PROFIL_KUT[0])
                os_h = np.array([math.sin(t_), math.cos(t_), 0.0])
                mk = mk_b
            elif vyd == "зад":
                os_h = np.array([-1.0, 0.0, 0.0])
                mk = mk_z
            else:
                os_h = np.array([1.0, 0.0, 0.0])
                mk = mk_p
            hor = co @ os_h
            ys, xs = np.where(mk)
            y0, y1 = ys.min(), ys.max() + 1
            vys = y1 - y0
            tul = (ys > y1 - 0.45 * vys) & (ys < y1 - 0.30 * vys)
            cx_r = float(np.median(xs[tul]))
            # масштаб — від ступень до очей спереду; інші кадри — тієї ж
            # висоти (вирівняні `avatar_ref_vysoty.py`)
            if oko_ref_y is not None:
                oz = P.oko_modeli(h)
                k = (oko_ref_y - y0) / (oz - z0)
            else:
                k = vys / (z1 - z0)
            cm = float(np.median(hor[vidymi][tulm]))
            if vyd == "бік":
                cm -= P.PROFIL_ZSUV[0]
            px = cx_r + (hor - cm) * k
            py = y0 + (z - z0) * k
            m_mod = _syluet(px, py, tris, vidymi, w, hh)
            # контури голови, кистей, ступень — не тягнуть
            ne = np.zeros((hh, w), np.uint8)
            v_ = (vilni_kraii if vyd != "бік" else vilni) > 0.5
            ix = np.clip(px[v_].astype(int), 0, w - 1)
            iy = np.clip(py[v_].astype(int), 0, hh - 1)
            ne[iy, ix] = 1
            ne = cv2.dilate(ne, np.ones((25, 25), np.uint8)) > 0
            Fx, Fy = _pole(m_mod, mk, ne)
            ix = np.clip(px.astype(int), 0, w - 1)
            iy = np.clip(py.astype(int), 0, hh - 1)
            d_h = Fx[iy, ix] / k
            d_z = Fy[iy, ix] / k
            d_p = d_h[:, None] * os_h[None, :]
            d_p[:, 2] = d_z
            # поза → спокій
            Minv = np.linalg.inv(M)
            rez[vyd] = np.einsum("nij,nj->ni", Minv, d_p)
            iou = (m_mod & mk).sum() / max(1, (m_mod | mk).sum())
            import os as _os
            dbg = _os.environ.get("KONTURY_DEBUG")
            if dbg and prokhid == 0:
                o_ = np.zeros((hh, w, 3), np.uint8)
                o_[mk] = (0, 0, 200)
                o_[m_mod] = (0, 200, 0)
                o_[mk & m_mod] = (200, 200, 200)
                cv2.imwrite(_os.path.join(dbg, "kontur-%s.png" % vyd),
                            o_[::-1])
            print("[контури] прохід %d, %s: збіг силуетів %.3f"
                  % (prokhid + 1, vyd, iou), flush=True)
        # Поєднання: горизонталь — перед і зад; глибина — профіль (без рук,
        # вони в профіль у іншій позі); висота — середнє трьох.
        fb = 0.5 * (rez["перед"] + rez["зад"])
        bk = rez["бік"] * ne_ruky_bik[:, None]
        d = fb.copy()
        d[:, 1] = bk[:, 1]
        d[:, 2] = (rez["перед"][:, 2] + rez["зад"][:, 2] +
                   bk[:, 2]) / (2 + ne_ruky_bik)
        d[:, 0] *= tiahnuty_x
        d[:, 1] *= tiahnuty
        d[:, 2] *= tiahnuty
        dl = np.linalg.norm(d, axis=1)
        zaduzhe = dl > MAKS_M
        d[zaduzhe] *= (MAKS_M / dl[zaduzhe])[:, None]
        zsuv_spokii += d
        for i, v in enumerate(kl.data):
            v.co = (baza[i] + zsuv_spokii[i]).tolist()
        h.data.update()
        bpy.context.view_layer.update()
        print("[контури] прохід %d: зсув вершин середній %.1f мм, "
              "найбільший %.1f мм" % (prokhid + 1,
                                      1000 * np.linalg.norm(zsuv_spokii, axis=1)
                                      [vidymi].mean(),
                                      1000 * np.linalg.norm(zsuv_spokii, axis=1)
                                      .max()), flush=True)
    for pb in arm.pose.bones:
        pb.matrix_basis.identity()
    bpy.context.view_layer.update()
