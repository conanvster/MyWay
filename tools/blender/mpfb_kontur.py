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
    # Груди — не тягнути (замовник 02.10.2026: «вирівняй груди», бажаний
    # профіль — округлий): контур профілю тягнув їх до обрису бюстгальтера
    # кадру, і форма виходила горбатою. Форму дають повзунки (`GRUDY`).
    if "nipple" in h.vertex_groups:
        co0 = np.array([v.co[:] for v in me.vertices])
        gn = h.vertex_groups["nipple"].index
        sosky = np.array([any(g.group == gn for g in v.groups)
                          for v in me.vertices])
        hrudy = np.zeros(len(co0))
        for znak in (1, -1):
            s_ = sosky & (co0[:, 0] * znak > 0)
            if s_.any():
                c_ = co0[s_].mean(0)
                d_ = np.linalg.norm(co0 - c_, axis=1)
                hrudy = np.maximum(hrudy, np.clip(1.6 - d_ / 0.07, 0, 1))
        # уся передня частина грудної клітки — від ключиць до-під груди
        # (зл9: над грудьми контур профілю видавлював западину)
        zs_ = co0[sosky, 2].mean() if sosky.any() else 0
        # Плавно (замовник: «нижче грудей зявився якийсь злам» — різка межа
        # захисту давала сходинку): згасання 8 см униз і вбоки.
        sp = (co0[:, 1] < -0.02) * \
            np.clip(1 - (zs_ - 0.06 - co0[:, 2]) / 0.08, 0, 1) * \
            np.clip(1 - (co0[:, 2] - zs_ - 0.22) / 0.08, 0, 1) * \
            np.clip(1 - (np.abs(co0[:, 0]) - 0.17) / 0.06, 0, 1)
        hrudy = np.maximum(hrudy, sp)
        hrudy = np.clip(hrudy, 0, 1)
        if __import__("os").environ.get("KONTURY_BEZ_SHYI", "") not in ("", "0"):
            # шия й трапеції — не тягнути (форма — повзунками, варіант 1)
            hrudy = np.maximum(hrudy, _vagy_grup(h, ("neck_01", "head")))
        tiahnuty = tiahnuty * (1 - hrudy)
        tiahnuty_x = tiahnuty_x * (1 - hrudy)
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


# Шия, тоді голова — у профіль (замовник 02.10.2026: «побачив некрасиву
# шию та форму голови , спробуй таким же чином змоделювати спочатку шию а
# потівм розмір та форму голови», приклад — профіль s1955). Обрис моделі в
# смузі шиї, потім голови, — під обрис кадру збоку, повзунками MakeHuman.
PARY_SHYIA = [
    ("neck-height", "measure-neck-height-incr", "measure-neck-height-decr"),
    ("neck-circ", "measure-neck-circ-incr", "measure-neck-circ-decr"),
    ("neck-depth", "neck-scale-depth-incr", "neck-scale-depth-decr"),
    ("neck-back", "neck-back-scale-depth-incr", "neck-back-scale-depth-decr"),
    ("neck-trans", "neck-trans-backward", "neck-trans-forward"),
    ("chin-jaw-drop", "chin-jaw-drop-incr", "chin-jaw-drop-decr"),
]
PARY_HOLOVA = [
    ("head-scale", "head-scale-vert-incr", "head-scale-vert-decr"),
    ("head-depth", "head-scale-depth-incr", "head-scale-depth-decr"),
    ("head-back", "head-back-scale-depth-incr", "head-back-scale-depth-decr"),
    ("head-trans-fb", "head-trans-backward", "head-trans-forward"),
    ("head-trans-v", "head-trans-up", "head-trans-down"),
    ("head-angle", "head-angle-in", "head-angle-out"),
]


def _klyuchi(h, pary):
    from bl_ext.blender_org.mpfb.services.targetservice import TargetService
    kb = h.data.shape_keys.key_blocks
    kl = {}
    for imia, plus, minus in pary:
        ok = []
        for zn, f in (("+", plus), ("-", minus)):
            if f not in kb:
                shl = TargetService.target_full_path(f)
                if not shl:
                    continue
                TargetService.load_target(h, shl, weight=0.0, name=f)
            ok.append((zn, f))
        if len(ok) == 2:
            kl[imia] = ok
    return kl


def pidibraty_profil_holovy(h, arm, kut_ruk, bik, m_bik, oko_ref_y):
    me = h.data
    gi = h.vertex_groups["body"].index
    vidymi = np.array([any(g.group == gi and g.weight > 0.5 for g in v.groups)
                       for v in me.vertices])
    mk = P.bez_volossia(_maska(m_bik), bik, "бік")
    hh, w = mk.shape
    ys, xs = np.where(mk)
    y0, y1 = ys.min(), ys.max() + 1
    vys = y1 - y0
    tul = (ys > y1 - 0.45 * vys) & (ys < y1 - 0.30 * vys)
    cx_r = float(np.median(xs[tul]))
    kb = me.shape_keys.key_blocks
    zz = [v.vertex_index for v in []]
    P.postavyty_ruky(arm, P.kut_biku(kut_ruk))
    # лише голова й шия моделі (без рук — у T-позі рука дивиться в камеру
    # на висоті плеча й перекрила б шию знизу)
    vagy = _vagy_grup(h, ("head", "neck_01"))
    ruky = _vagy_grup(h, ("upperarm", "lowerarm", "hand", "clavicle"))

    def proekt():
        co, _ = P.vershyny_bez_masky(h)
        z = co[:, 2]
        zv = z[vidymi]
        z0 = zv.min()
        z1 = zv.max()
        tulm = (zv > z1 - 0.45 * (z1 - z0)) & (zv < z1 - 0.30 * (z1 - z0))
        t_ = math.radians(P.PROFIL_KUT[0])
        hor = co[:, 0] * math.sin(t_) + co[:, 1] * math.cos(t_)
        oz = P.oko_modeli(h)
        k = (oko_ref_y - y0) / (oz - z0)
        cm = float(np.median(hor[vidymi][tulm])) - P.PROFIL_ZSUV[0]
        return cx_r + (hor - cm) * k, y0 + (z - z0) * k, co

    mm = [m for m in h.modifiers if m.type == "MASK"]
    for m in mm:
        m.show_viewport = False
    bpy.context.view_layer.update()
    ev = h.evaluated_get(bpy.context.evaluated_depsgraph_get())
    me_e = ev.to_mesh()
    me_e.calc_loop_triangles()
    tris = np.array([t.vertices[:] for t in me_e.loop_triangles])
    ev.to_mesh_clear()
    for m in mm:
        m.show_viewport = True
    # Усе тіло без рук — як і силует кадру в смузі (перша спроба брала
    # лише голову й шию, а кадр у смузі шиї має й плечі — збіг 0,07, і
    # підбір наробив подвійне підборіддя).
    tris = tris[vidymi[tris].all(1) & (ruky[tris] < 0.3).all(1)]
    # кадр без руки (стерта), але плече лишилось — прибрати й у кадрі все,
    # що за спиною далі за потилицю, не треба: смуги вище плечей

    # Плече: на кадрі збоку — обрубок стертої руки, у моделі в T-позі рука
    # дивиться в камеру. Обидва — поза мірою: слід плеча й ключиці моделі
    # (розширений) і все, що на кадрі позаду переднього краю цього сліду.
    px0, py0, _ = proekt()
    pl = (_vagy_grup(h, ("upperarm", "clavicle")) > 0.3) & vidymi
    poza = np.zeros((hh, w), np.uint8)
    ix = np.clip(px0[pl].astype(int), 0, w - 1)
    iy = np.clip(py0[pl].astype(int), 0, hh - 1)
    poza[iy, ix] = 1
    poza = cv2.dilate(poza, np.ones((31, 31), np.uint8)) > 0

    def otsinka(smuha, dbg=None):
        smuha = smuha & ~poza
        px, py, _ = proekt()
        m = np.zeros((hh, w), np.uint8)
        for tr in np.stack([px[tris], py[tris]], -1).round().astype(np.int32):
            cv2.fillConvexPoly(m, tr, 1)
        m = m > 0
        if dbg:
            o_ = np.zeros((hh, w, 3), np.uint8)
            o_[mk] = (0, 0, 200)
            o_[m] = (0, 200, 0)
            o_[m & mk] = (200, 200, 200)
            o_[smuha & ~(m | mk)] = (60, 60, 0)
            cv2.imwrite(dbg, o_[::-1])
        a, b = m & smuha, mk & smuha
        return (a & b).sum() / max(1, (a | b).sum())

    # Смуги — за кадром (профіль вирівняний за висотами під перед, тож
    # підборіддя — точка 152 обличчя спереду): шия — від підборіддя на
    # 0,45 відстані очі—підборіддя вниз, голова — від підборіддя до маківки.
    # Рядки маски — знизу. (Перша спроба брала межі з сітки — смуга шиї
    # виходила порожня.)
    import os as _o
    L = np.load(_o.path.join(_o.path.dirname(m_bik), "tochky-ref.npy"))
    pidbor = hh - 1 - float(L[152, 1])
    oko = hh - 1 - float((L[33, 1] + L[263, 1]) / 2)
    d = oko - pidbor
    rows = np.arange(hh)[:, None] * np.ones((1, w), bool)
    zona_shyia = (rows > pidbor - 0.9 * d) & (rows < pidbor + 0.15 * d)
    zona_holova = rows >= pidbor - 0.05 * d
    for nazva, pary, zona in (("шия", PARY_SHYIA, zona_shyia),
                              ("голова", PARY_HOLOVA, zona_holova)):
        kl = _klyuchi(h, pary)
        # з поточних значень (ключі могли поставити попередні кроки підбору
        # — перша спроба їх затирала, і обличчя спереду падало до 0,41)
        znach = {k: sum(kb[f].value if zn == "+" else -kb[f].value
                        for zn, f in kl[k]) for k in kl}

        def post(k, v):
            znach[k] = v
            for zn, f in kl[k]:
                kb[f].value = max(0.0, v) if zn == "+" else max(0.0, -v)
        dbg = _o.environ.get("PROFIL_DEBUG")
        naikr = otsinka(zona, dbg and dbg.replace(".png", "-%s-0.png" % nazva))
        print("[профіль голови] %s, початок: %.4f" % (nazva, naikr),
              flush=True)
        for krok in (0.2, 0.2, 0.1, 0.1, 0.05):
            for k in list(kl):
                for znak in (1, -1):
                    v0 = znach[k]
                    v1 = min(0.6, max(-0.6, v0 + znak * krok))
                    if abs(v1 - v0) < 1e-6:
                        continue
                    if v1 == v0:
                        continue
                    post(k, v1)
                    s_ = otsinka(zona)
                    if s_ > naikr + 1e-4:
                        naikr = s_
                        break
                    post(k, v0)
        if dbg:
            otsinka(zona, dbg.replace(".png", "-%s-1.png" % nazva))
        print("[профіль голови] %s: %.4f; %s" % (
            nazva, naikr, {k: round(v, 2) for k, v in znach.items()
                           if abs(v) > 1e-3}), flush=True)
    for pb in arm.pose.bones:
        pb.matrix_basis.identity()
    bpy.context.view_layer.update()


def trykutnyky(h):
    """Трикутники базової сітки (без модифікатора MASK — номери вершин як у
    `vershyny_bez_masky`)."""
    mm = [m for m in h.modifiers if m.type == "MASK"]
    for m in mm:
        m.show_viewport = False
    bpy.context.view_layer.update()
    ev = h.evaluated_get(bpy.context.evaluated_depsgraph_get())
    me = ev.to_mesh()
    me.calc_loop_triangles()
    t = np.array([x.vertices[:] for x in me.loop_triangles])
    ev.to_mesh_clear()
    for m in mm:
        m.show_viewport = True
    return t


def pidtiahnuty_uv(u, v, tris, vidymi, mk, prokhody=3):
    """Текстура під форму моделі (замовник 03.10.2026: «гарно і
    пропорціонально розфарбувати з рендеру модель 100-8»): не модель під
    кадр, а розгортка під модель — контур моделі в пікселях кадру
    тягнеться до контуру кадру, розмите поле зсувів зсуває UV. Маска `mk` —
    рядки знизу, як u, v."""
    hh, w = mk.shape
    for _ in range(prokhody):
        px, py = u * w, v * hh
        m_mod = _syluet(px, py, tris, vidymi, w, hh)
        Fx, Fy = _pole(m_mod, mk, np.zeros((hh, w), bool))
        ix = np.clip(px.astype(int), 0, w - 1)
        iy = np.clip(py.astype(int), 0, hh - 1)
        u = u + Fx[iy, ix] / w
        v = v + Fy[iy, ix] / hh
        iou = (m_mod & mk).sum() / max(1, (m_mod | mk).sum())
    print("[uv] збіг силуету розгортки з кадром: %.3f" % iou, flush=True)
    return u, v
