#!/usr/bin/env python3
"""Лінії пропорцій ельфійки: підборіддя, пояс, промежина, ступні (12.10.2026).

Слово замовника: «бачу червону горизонтальну лінію … але пропорції не
витримались, також для наглядності додай до цієї лінії — лінію
підборіддя, лінію поясу, промежини не дотягнуті». Kontext за текстом
пропорцій не тримає, ControlNet для FLUX не встановлено — тож лінії
міряються на кожному кадрі, а `--вирівняти` розтягує кадр по висоті
кусками так, щоб вони лягли на лінії основи.

Мірки (кадр 1024², тло однотонне світло-сіре):
  * підборіддя — точка 152 MediaPipe FaceLandmarker (немає обличчя — ‼);
  * ступні — низ силуету;
  * промежина — знизу вгору перший рядок, де ноги ще одна смуга (у
    штанах); під спідницею чи мантією не видно → ‼ і лінійно між
    поясом і ступнями в пропорції основи;
  * пояс — найвужчий рядок тулуба між підборіддям+25% і промежиною
    (центральна смуга — без рук).

    ~/Програми/cv-venv/bin/python tools/elf_markery.py аркуш <вихід.png> <кадр…>
    ~/Програми/cv-venv/bin/python tools/elf_markery.py вирівняти <кадр…>
        → поруч `<кадр>-рівно.png`
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

KORIN = Path(__file__).resolve().parents[1]
D = KORIN / "wiki/img/test/avatar"
OSNOVA = D / "el-dovha-chernetka.png"
MODEL = "/home/alex/Програми/mediapipe-models/face_landmarker.task"
KOLIR = {"підборіддя": (40, 140, 255), "пояс": (40, 190, 60),
         "промежина": (230, 40, 40), "ступні": (240, 170, 0)}

_det = None


def pidboriddia(im):
    global _det
    import mediapipe as mp
    from mediapipe.tasks.python import BaseOptions, vision
    if _det is None:
        _det = vision.FaceLandmarker.create_from_options(
            vision.FaceLandmarkerOptions(
                base_options=BaseOptions(model_asset_path=MODEL), num_faces=1))
    a = np.asarray(im.convert("RGB"))
    # Обличчя на кадрі всього тіла дрібне — виріз навколо голови ×3
    # (уся верхня чверть ×4 обличчя не давала).
    x0, x1, y0, y1, k = 362, 662, 0, 300, 3
    big = np.asarray(Image.fromarray(a[y0:y1, x0:x1])
                     .resize(((x1 - x0) * k, (y1 - y0) * k), Image.LANCZOS))
    r = _det.detect(mp.Image(image_format=mp.ImageFormat.SRGB,
                             data=np.ascontiguousarray(big)))
    if not r.face_landmarks:
        return None
    return y0 + r.face_landmarks[0][152].y * (y1 - y0)


def sylyet(shliakh):
    """Маска birefnet (ComfyUI має працювати), кеш `<кадр>-маска.png`
    у scratch-теці поруч. Різниця з тлом не годилась: підлога темніша за
    стіну, і «ступні» впирались у низ кадру."""
    kesh = Path(str(shliakh)[:-4] + "-маска.png")
    if not kesh.exists():
        sys.path.insert(0, str(KORIN / "tools" / "comfyui"))
        import monster3d as m3
        m3.cutout(str(shliakh), str(kesh))
    return np.asarray(Image.open(kesh).convert("L")) > 127


def smugy(r):
    d = np.diff(np.concatenate([[0], r.astype(int), [0]]))
    return np.where(d == 1)[0], np.where(d == -1)[0]


def mirky(shliakh):
    im = Image.open(shliakh).convert("RGB")
    m = sylyet(shliakh)
    h, w = m.shape
    out = {"ступні": None, "промежина": None, "пояс": None,
           "підборіддя": pidboriddia(im)}
    ryadky = np.where(m.sum(1) > 6)[0]
    out["ступні"] = float(ryadky.max())
    # промежина: від колін (60% висоти) вгору — поки рядок у центральній
    # смузі має дві смуги (ноги), він під промежиною
    cx = w // 2
    smuga = m[:, cx - 110: cx + 110]
    start = int(h * 0.62)
    if len(smugy(smuga[start])[0]) >= 2:
        y = start
        while y > h * 0.3 and len(smugy(smuga[y])[0]) >= 2:
            y -= 1
        out["промежина"] = float(y)
    ch = out["підборіддя"]
    if ch is not None:
        niz = out["промежина"] or h * 0.55
        y0, y1 = int(ch + (niz - ch) * 0.25), int(niz - 10)
        shyr = []
        for y in range(y0, y1):
            s, e = smugy(m[y, cx - 140: cx + 140])
            # смуга, що містить центр (тулуб без рук)
            c = 140
            hit = [(b - a_) for a_, b in zip(s, e) if a_ <= c < b]
            shyr.append(hit[0] if hit else 999)
        out["пояс"] = float(y0 + int(np.argmin(shyr)))
    return out


def lini(o, x0, y0, s, mk, tovsto=1, dash=False):
    d = ImageDraw.Draw(o)
    for k, y in mk.items():
        if y is None:
            continue
        yy = y0 + y * s / 1024
        if dash:
            for x in range(x0, x0 + s, 12):
                d.line((x, yy, x + 6, yy), fill=KOLIR[k], width=tovsto)
        else:
            d.line((x0, yy, x0 + s, yy), fill=KOLIR[k], width=tovsto)


def vyrivniaty(shliakh, osn):
    mk = mirky(shliakh)
    im = Image.open(shliakh).convert("RGB")
    a = np.asarray(im).astype(float)
    h = a.shape[0]
    # опорні пари (кадр → основа); промежину під одягом не видно —
    # її місце в кадрі виводимо з пропорції основи між поясом і ступнями
    if mk["промежина"] is None and mk["пояс"] is not None:
        t = (osn["промежина"] - osn["пояс"]) / (osn["ступні"] - osn["пояс"])
        mk["промежина"] = mk["пояс"] + t * (mk["ступні"] - mk["пояс"])
    pary = [(0.0, 0.0)]
    for k in ("підборіддя", "пояс", "промежина", "ступні"):
        if mk[k] is not None:
            pary.append((mk[k], osn[k]))
    pary.append((float(h - 1), float(h - 1)))
    pary.sort(key=lambda p: p[1])
    src = np.interp(np.arange(h), [p[1] for p in pary], [p[0] for p in pary])
    y0 = np.clip(np.floor(src).astype(int), 0, h - 1)
    y1 = np.clip(y0 + 1, 0, h - 1)
    t = (src - y0)[:, None, None]
    nove = a[y0] * (1 - t) + a[y1] * t
    kudy = Path(str(shliakh)[:-4] + "-рівно.png")
    Image.fromarray(nove.clip(0, 255).astype(np.uint8)).save(kudy)
    print("%s: %s → %s" % (Path(shliakh).name,
                            {k: (None if v is None else round(v)) for k, v in mk.items()},
                            kudy.name), flush=True)
    return kudy


def arkush(vykhid, kadry):
    FB = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
    F = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
    f1, f2 = ImageFont.truetype(FB, 20), ImageFont.truetype(F, 15)
    osn = mirky(OSNOVA)
    S, kol = 330, 7
    rows = (len(kadry) + 1 + kol - 1) // kol
    o = Image.new("RGB", (S * kol, 70 + rows * (S + 28)), (30, 28, 26))
    d = ImageDraw.Draw(o)
    d.text((10, 8), "Лінії основи — суцільні, лінії кадру — пунктир:", font=f2,
           fill=(230, 200, 120))
    x = 420
    for k, c in KOLIR.items():
        d.line((x, 18, x + 30, 18), fill=c, width=3)
        d.text((x + 36, 9), k, font=f2, fill=c)
        x += 160
    vsi = [(OSNOVA, "основа")] + [(Path(k), Path(k).stem.replace("el-dovha-nabir-", ""))
                                   for k in kadry]
    for i, (p, nazva) in enumerate(vsi):
        x0, y0 = (i % kol) * S, 40 + (i // kol) * (S + 28)
        o.paste(Image.open(p).convert("RGB").resize((S, S)), (x0, y0))
        mk = osn if i == 0 else mirky(p)
        lini(o, x0, y0, S, osn)
        if i:
            lini(o, x0, y0, S, mk, tovsto=2, dash=True)
        bez = [k for k, v in mk.items() if v is None]
        d.text((x0 + 6, y0 + S + 4), nazva + (("  ‼ " + ", ".join(bez)) if bez else ""),
               font=f2, fill=(220, 210, 190))
    o.save(vykhid)
    print("аркуш →", vykhid, flush=True)


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    if sys.argv[1] == "аркуш":
        arkush(sys.argv[2], sys.argv[3:])
    elif sys.argv[1] == "вирівняти":
        osn = mirky(OSNOVA)
        print("основа:", {k: round(v) for k, v in osn.items()})
        for p in sys.argv[2:]:
            vyrivniaty(p, osn)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
