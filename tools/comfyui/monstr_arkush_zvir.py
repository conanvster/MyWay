#!/usr/bin/env python3
"""Аркуш-референс НЕгуманоїда для 3D-моделювання (27.11.2026, слово замовника «давай почнемо
робити по типам» → «так» на пробу типу вовк-сіромаха).

Той самий рецепт, що monstr_arkush.py (Qwen-Edit 2511 + Lightning, рівне світло, чисте тло
birefnet), але каркас — модель-зразок типу (`tools/blender/karkas_zvir.py` →
`_аркуш-каркас/звірі/<тип>/{0,45,90,180,згори}.png`) у природній стійці, без поз А/Т і без
кадру зброї. Ланцюжок: референс вікі + каркас 0° → 0°; від 0° + каркас кута → 45/90/180/згори;
ракурс, що лишився ≈ своїм 0°, перезнімається (до 3 сідів), інакше позначка `<кадр>.‼`.

    ~/Програми/cv-venv/bin/python -u tools/comfyui/monstr_arkush_zvir.py --список [<тип>]
    ~/Програми/cv-venv/bin/python -u tools/comfyui/monstr_arkush_zvir.py --тип вовк-сіромаха
    ~/Програми/cv-venv/bin/python -u tools/comfyui/monstr_arkush_zvir.py <вид> [<вид> …]
    ~/Програми/cv-venv/bin/python -u tools/comfyui/monstr_arkush_zvir.py --зібрати [<вид> …]

Вихід — `art/monsters/<вид>-3d/аркуш/{0,45,90,180,згори}.png` і `аркуш.jpg` (лише диск).
ComfyUI — через gpu-broker (:8189, monster3d.py).
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

TUT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TUT)
import monstr_arkush as ma  # noqa: E402

km = ma.km
ZVIRI = os.path.join(ma.KARKAS, "звірі")
KADRY = ["0", "45", "90", "180", "згори"]
KUT_OPYS = {"0": "strict front view, the head facing the camera",
            "45": "three-quarter view, the body turned 45 degrees to the side",
            "90": "exact side view in profile",
            "180": "strict back view from behind",
            "згори": "top-down view from directly above, the head towards the top of the image"}
PIDPYSY = {"0": "СПЕРЕДУ", "45": "3/4 · 45°", "90": "ЗБОКУ · 90°", "180": "ЗЗАДУ · 180°",
           "згори": "ЗГОРИ"}


def vydy_typu(typ=None):
    """[(вид, тип)] — види з моделлю-копією негуманоїда (тип = зразок, що копіюють)."""
    mobs = json.load(open(km.MOBS))
    svoia = {v["назва"] for k, v in mobs.items() if not k.startswith("_")
             and v["вигляд"].get("модель", "").endswith("/" + v["назва"] + ".glb")}
    rez = []
    for b in json.load(open(km.BEST)):
        n = b["назва"]
        if n in km.GOOD or n in ma.SHABLONY or n in svoia:
            continue
        s, _ = km.pick(n, b.get("конвеєр", ""))
        if s in ma.SHABLONY or (typ and s != typ):
            continue
        if os.path.isdir(os.path.join(ZVIRI, s)):
            rez.append((b.get("рівень", 999), n, s))
    return [(v, s) for _, v, s in sorted(rez)]


def instr(kut, pershyi, b):
    khto = ("the creature from the first image" if pershyi else
            "exactly the same creature as in the first image")
    return ("Show " + khto + " as a clean full-body creature turnaround reference for 3D "
            "modeling. Keep its identity exactly: the same head, skull and muzzle shape, mouth "
            "and teeth, eyes, horns, ears, the same number of heads, legs, eyes and tails, the "
            "same skin, fur, scales, chitin or bone, the same colours and markings, spikes, "
            "crystals and ornaments, the same body build and proportions. Change only its pose, "
            "camera and lighting: it stands in a calm natural neutral stance like the grey model "
            "in the second image, seen from the same camera angle as the second image: "
            + KUT_OPYS[kut] + "; show the parts visible from this side. The grey model is only a "
            "pose and camera guide: do not copy its body, fur or shape, and do not turn the "
            "creature into the grey model. No rider, no saddle, no weapon, nothing held. "
            + ma.opys(b) + ma.SVITLO)


def zheneruvaty(vydy):
    import monster3d as m  # noqa: E402
    import bronia_2var as b2  # noqa: E402
    best = ma.bestiarii()
    typy = dict(vydy_typu())
    for vyd in vydy:
        ref = os.path.join(ma.KORIN, "wiki/img/monstry", vyd + ".png")
        if not os.path.exists(ref):
            print("‼ немає референсу", ref, flush=True)
            continue
        karkas = os.path.join(ZVIRI, typy[vyd])
        t = ma.teka(vyd)
        os.makedirs(t, exist_ok=True)
        nul = os.path.join(t, "0.png")
        for kut in KADRY:
            kudy = os.path.join(t, kut + ".png")
            if os.path.exists(kudy):
                continue
            pershyi = kut == "0"
            persha = ref if pershyi else nul
            druha = os.path.join(karkas, kut + ".png")
            if not pershyi and os.path.exists(kudy[:-4] + ".‼"):
                continue
            for i in range(1 if pershyi else ma.SPROB):
                ma.zapustyty(m, b2, persha, druha, instr(kut, pershyi, best[vyd]), kudy,
                             ma.SID + i)
                if pershyi or not ma.povtor(kudy, nul):
                    break
                print("  ↻ %s s%d ≈ свій 0° — не повернуто" % (kut, ma.SID + i), flush=True)
            else:
                print("‼ %s %s не повернувся за %d спроби — перевір очима" % (
                    vyd, kut, ma.SPROB), flush=True)
                open(kudy[:-4] + ".‼", "w").write("не повернувся за %d спроби\n" % ma.SPROB)
            print("готово", vyd, kut, flush=True)
        zibraty(vyd)
    m.free()


# ---------- аркуш (лише CPU) ----------

def mezhi(a):
    mk = ma.maska(a)
    ys, xs = np.where(mk.any(1))[0], np.where(mk.any(0))[0]
    if not len(ys):
        return 0, 0, a.shape[1] - 1, a.shape[0] - 1
    return xs[0], ys[0], xs[-1], ys[-1]


def holova_zvira(shliakh, zboku=False):
    """Голова звіра — приблизно: спереду — верхня середина постаті; збоку — край постаті з боку
    морди (той, де постать вища в передній третині)."""
    im = Image.open(shliakh).convert("RGB")
    a = np.asarray(im)
    x0, y0, x1, y1 = mezhi(a)
    h, w = y1 - y0, x1 - x0
    st = int(max(h, w) * (0.45 if zboku else 0.6))
    if zboku:
        mk = ma.maska(a)
        tret = max(1, w // 3)
        def vys(xa, xb):
            r = np.where(mk[:, xa:xb].any(1))[0]
            return r[0] if len(r) else y1
        livo = vys(x0, x0 + tret) <= vys(x1 - tret, x1)
        cx = x0 + st // 2 if livo else x1 - st // 2
    else:
        cx = (x0 + x1) // 2
    top = max(0, y0 - int(0.03 * h))
    return im.crop((cx - st // 2, top, cx + st // 2, top + st))


def zibraty(vyd):
    t = ma.teka(vyd)
    kadry = {k: os.path.join(t, k + ".png") for k in KADRY}
    if not all(os.path.exists(f) for f in kadry.values()):
        print("… ще не всі кадри", vyd, flush=True)
        return
    b = ma.bestiarii()[vyd]
    om = b.get("опис моделі", {})
    zrist = float(b.get("вигляд", {}).get("розмір") or 0)
    typ = dict(vydy_typu()).get(vyd, "—")
    C, LIV, POLE = 470, 110, 30
    W = LIV + 4 * C + POLE
    dd = ImageDraw.Draw(Image.new("RGB", (10, 10)))
    oznaky = [(nz, om[kl]) for kl, nz in (("голова", "Голова"), ("тулуб", "Тулуб"),
                                          ("кінцівки", "Кінцівки"), ("хвіст", "Хвіст"),
                                          ("амуніція", "Амуніція"), ("зброя", "Зброя"))
              if om.get(kl) and om[kl].strip().rstrip(".").lower() not in ("немає", "нема")]
    ryadky = [(nz, ma.rozbyty(tx, ma.shryft(17), W - 2 * POLE - 150, dd)) for nz, tx in oznaky]
    vys_oznak = 50 + sum(len(r) * 24 + 8 for _, r in ryadky)
    Y_RIAD = 120
    RIAD = C + 46
    Y_DRUH = Y_RIAD + RIAD
    NYZ = 34 + 2 * (230 + 26) + 20
    Y_NYZ = Y_DRUH + 20
    H = Y_NYZ + NYZ + vys_oznak + POLE
    ark = Image.new("RGB", (W, H), ma.TLO)
    d = ImageDraw.Draw(ark)
    d.text((POLE, 22), vyd.upper(), font=ma.shryft(42, True), fill=ma.CHORNYI)
    sub = "референс для 3D · рівень %s · зріст у холці/висота %.2f м · модель зараз: копія «%s»" % (
        b.get("рівень", "?"), zrist, typ)
    d.text((POLE + 2, 76), sub, font=ma.shryft(19), fill=ma.SIRYI)
    d.line((POLE, Y_RIAD - 12, W - POLE, Y_RIAD - 12), fill=(200, 198, 192), width=2)
    # ряд: спереду, 45, збоку, ззаду
    dovzh = None
    for i, k in enumerate(KADRY[:4]):
        im = Image.open(kadry[k]).convert("RGB").resize((C, C))
        x, y = LIV + i * C, Y_RIAD
        ark.paste(im, (x, y + 34))
        pd = PIDPYSY[k]
        d.text((x + (C - d.textlength(pd, font=ma.shryft(20, True))) / 2, y + 4), pd,
               font=ma.shryft(20, True), fill=ma.CHORNYI)
        if i:
            d.line((x, y + 40, x, y + 34 + C - 6), fill=(214, 212, 206), width=1)
        if k == "90" and zrist:
            x0, y0, x1, y1 = mezhi(np.asarray(im))
            if y1 > y0:
                dovzh = zrist * (x1 - x0) / (y1 - y0)
                yy = y + 34 + y1 + 10
                d.line((x + x0, yy, x + x1, yy), fill=ma.CHORNYI, width=3)
                for xx in (x + x0, x + x1):
                    d.line((xx, yy - 6, xx, yy + 6), fill=ma.CHORNYI, width=2)
                tx = "довжина ≈ %.2f м" % dovzh
                d.text((x + (x0 + x1) / 2 - d.textlength(tx, font=ma.shryft(15)) / 2, yy + 8),
                       tx, font=ma.shryft(15, True), fill=(150, 40, 40))
        if i == 0 and zrist:
            x0, y0, x1, y1 = mezhi(np.asarray(im))
            y0 += y + 34
            y1 += y + 34
            xl = LIV - 22
            d.line((xl, y0, xl, y1), fill=ma.CHORNYI, width=3)
            krok = 0.5 if zrist > 1.5 else 0.25 if zrist > 0.6 else 0.1
            v = 0.0
            while v <= zrist + 1e-6:
                yy = y1 - (y1 - y0) * v / zrist
                d.line((xl - 10, yy, xl, yy), fill=ma.CHORNYI, width=2)
                d.text((POLE - 4, yy - 9), "%.2f" % v, font=ma.shryft(15), fill=ma.CHORNYI)
                v += krok
            if zrist - (v - krok) > krok * 0.3:
                d.line((xl - 10, y0, xl, y0), fill=(150, 40, 40), width=3)
                d.text((POLE - 4, y0 - 9), "%.2f" % zrist, font=ma.shryft(15, True),
                       fill=(150, 40, 40))
            for xx in range(LIV, LIV + 4 * C, 14):
                d.line((xx, y0, xx + 6, y0), fill=(170, 168, 160))
                d.line((xx, y1, xx + 6, y1), fill=(170, 168, 160))
    # нижня смуга: згори | голова | кольори
    y = Y_NYZ
    d.line((POLE, y - 10, W - POLE, y - 10), fill=(200, 198, 192), width=2)
    ZG = NYZ - 40
    d.text((POLE, y), "ЗГОРИ", font=ma.shryft(20, True), fill=ma.CHORNYI)
    ark.paste(Image.open(kadry["згори"]).convert("RGB").resize((ZG, ZG)), (POLE, y + 34))
    xh = POLE + ZG + 30
    d.text((xh, y), "ГОЛОВА", font=ma.shryft(20, True), fill=ma.CHORNYI)
    HS = 230
    for j, (k, zb) in enumerate((("0", False), ("90", True))):
        ark.paste(holova_zvira(kadry[k], zb).resize((HS, HS)), (xh, y + 34 + j * (HS + 26)))
        d.text((xh + 4, y + 34 + j * (HS + 26) + HS + 2), PIDPYSY[k], font=ma.shryft(14),
               fill=ma.SIRYI)
    xm = xh + HS + 40
    d.text((xm, y), "МАТЕРІАЛИ Й ОСНОВНІ КОЛЬОРИ (частка поверхні)", font=ma.shryft(20, True),
           fill=ma.CHORNYI)
    LT = 120
    for j, (rgb, ch, latka) in enumerate(ma.latky(kadry["0"])[:6]):
        xx, yy = xm + (j % 3) * 270, y + 34 + (j // 3) * (LT + 44)
        ark.paste(latka.resize((LT, LT)), (xx, yy))
        d.rectangle((xx + LT + 6, yy, xx + LT + 70, yy + LT), fill=rgb, outline=(80, 80, 80))
        d.text((xx, yy + LT + 6), "#%02x%02x%02x · %d%%" % (*rgb, round(ch * 100)),
               font=ma.shryft(15), fill=ma.CHORNYI)
    y = Y_NYZ + NYZ
    d.line((POLE, y - 10, W - POLE, y - 10), fill=(200, 198, 192), width=2)
    d.text((POLE, y), "ГОЛОВНІ ОЗНАКИ (бестіарій)", font=ma.shryft(20, True), fill=ma.CHORNYI)
    y += 38
    for nazva, ry in ryadky:
        d.text((POLE, y), "• " + nazva, font=ma.shryft(17, True), fill=(150, 40, 40))
        for r in ry:
            d.text((POLE + 150, y), r, font=ma.shryft(17), fill=(50, 50, 56))
            y += 24
        y += 8
    kudy = os.path.join(t, "аркуш.jpg")
    ark.save(kudy, quality=92)
    print("аркуш", kudy, flush=True)


def main():
    a = sys.argv[1:]
    vilni = [x for x in a if not x.startswith("--")]
    if "--список" in a:
        sp = vydy_typu(vilni[0] if vilni else None)
        for v, s in sp:
            print("%-45s ← %s" % (v, s))
        print(len(sp), "видів")
        return
    if "--зібрати" in a:
        for v in vilni:
            zibraty(v)
        return
    if "--тип" in a:
        # кілька типів — через кому, у заданому порядку
        vydy = [v for typ in a[a.index("--тип") + 1].split(",") for v, _ in vydy_typu(typ)]
    else:
        vydy = vilni
    zheneruvaty(vydy)


if __name__ == "__main__":
    main()
