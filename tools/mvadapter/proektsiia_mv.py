"""Вигляди MV-Adapter → колір у розгортку MPFB (09.11.2026).

Пілот 2 орка, варіант Б (слово замовника: «спробуй ті нові декілька
інструментів щоб отримати 3 варіанти згенеровані різними інструментами»).
Вигляди `ig2mv.py` намальовані під нашу ж сітку (ті самі камери й
нормування — `kamery.json`), тож колір іде в текстуру повністю, не лише
дрібна деталь, як у `tools/blender/projektsiia.py` для FLUX.

Кожен тексель: точка й нормаль на тілі (UV-трикутник → барицентр) → вага
вигляду max(0, n·(−look))^4, затулене (глибина далі за z-буфер вигляду) —
геть. Непокриті текселі — з базової шкіри, підтягнутої до тону виглядів.

    ~/Програми/mvadapter-venv/bin/python tools/mvadapter/proektsiia_mv.py \
        <сітка.npz> <тека виглядів> <базова шкіра.png> <вихід.png> [--розмір 2048] \
        [--реф <референс.png>] [--без-тону]

`--реф`: MV-Adapter малює світліше й сіріше за референс (студійне світло) —
колір усіх виглядів підганяється під референс: середнє й розкид кожного
каналу по фігурі (без сірого тла) переднього вигляду = референсу.
→ <вихід.png>, <вихід>-покриття.png
"""
import json
import sys

import numpy as np
from PIL import Image, ImageFilter

A = sys.argv[1:]
NPZ, VYDY, BAZA, VYHID = A[:4]
N = int(A[A.index("--розмір") + 1]) if "--розмір" in A else 2048

d = np.load(NPZ)
V, VN, F, UV = d["V"].astype(np.float64), d["VN"].astype(np.float64), d["F"], d["UV"].astype(np.float64)
K = json.load(open(VYDY + "/kamery.json"))
tsentr, masht, RES, PS = np.array(K["tsentr"]), K["masht"], K["res"], K["pivshyryna"]
Vn = (V - tsentr) * masht


def piksel(P, kam):
    look, right, up = (np.array(kam[k]) for k in ("look", "right", "up"))
    px = (P @ right / PS * 0.5 + 0.5) * RES
    py = (0.5 - P @ up / PS * 0.5) * RES
    return px, py, P @ look


def zbufer(kam):
    """Найближча глибина в кожному пікселі вигляду (як у ig2mv.py)."""
    px, py, z = piksel(Vn, kam)
    zb = np.full((RES, RES), np.inf)
    for f in F:
        xs, ys = px[f], py[f]
        x0, x1 = max(int(xs.min()), 0), min(int(xs.max()) + 1, RES - 1)
        y0, y1 = max(int(ys.min()), 0), min(int(ys.max()) + 1, RES - 1)
        if x1 < x0 or y1 < y0:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        (ax, bx, cx), (ay, by, cy) = xs, ys
        det = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(det) < 1e-9:
            continue
        l0 = ((by - cy) * (gx - cx) + (cx - bx) * (gy - cy)) / det
        l1 = ((cy - ay) * (gx - cx) + (ax - cx) * (gy - cy)) / det
        ok = (l0 >= 0) & (l1 >= 0) & (1 - l0 - l1 >= 0)
        if not ok.any():
            continue
        zz = (l0 * z[f[0]] + l1 * z[f[1]] + (1 - l0 - l1) * z[f[2]])[ok]
        iy, ix = (gy[ok] - 0.5).astype(int), (gx[ok] - 0.5).astype(int)
        np.minimum.at(zb, (iy, ix), zz)
    return zb


# ── тексель → точка й нормаль на тілі ──
P = np.zeros((N, N, 3))
NR = np.zeros((N, N, 3))
M = np.zeros((N, N), bool)
for t, f in enumerate(F):
    u, v = UV[t, :, 0] * N, (1 - UV[t, :, 1]) * N
    x0, x1 = max(int(u.min()), 0), min(int(u.max()) + 1, N - 1)
    y0, y1 = max(int(v.min()), 0), min(int(v.max()) + 1, N - 1)
    if x1 < x0 or y1 < y0:
        continue
    gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
    (ax, bx, cx), (ay, by, cy) = u, v
    det = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
    if abs(det) < 1e-12:
        continue
    l0 = ((by - cy) * (gx - cx) + (cx - bx) * (gy - cy)) / det
    l1 = ((cy - ay) * (gx - cx) + (ax - cx) * (gy - cy)) / det
    ok = (l0 >= -1e-4) & (l1 >= -1e-4) & (1 - l0 - l1 >= -1e-4)
    if not ok.any():
        continue
    b = np.stack([l0[ok], l1[ok], 1 - l0[ok] - l1[ok]], -1)
    iy, ix = (gy[ok] - 0.5).astype(int), (gx[ok] - 0.5).astype(int)
    P[iy, ix] = b @ Vn[f]
    n = b @ VN[f]
    NR[iy, ix] = n / (np.linalg.norm(n, axis=1, keepdims=True) + 1e-9)
    M[iy, ix] = True
yy, xx = np.nonzero(M)
Pt, Nt = P[yy, xx], NR[yy, xx]
print("текселів тіла", len(yy), flush=True)



def fihura(img):
    """Пікселі фігури: без рівного сірого тла (насиченість і відхід від сірого)."""
    tlo = np.median(np.concatenate([img[:8].reshape(-1, 3), img[:, :8].reshape(-1, 3)]), 0)
    return img[np.abs(img - tlo).sum(-1) > 0.08]


KOR = None
if "--реф" in A:
    ref = np.asarray(Image.open(A[A.index("--реф") + 1]).convert("RGB"), np.float64) / 255
    pered = np.asarray(Image.open(VYDY + "/mv-0.png").convert("RGB"), np.float64) / 255
    fr, fp = fihura(ref), fihura(pered)
    KOR = (fp.mean(0), fp.std(0), fr.mean(0), fr.std(0))
    print("колір: вигляди", np.round(fp.mean(0) * 255), "→ референс", np.round(fr.mean(0) * 255), flush=True)

SUMA = np.zeros((len(yy), 3))
VAGA = np.zeros(len(yy))
for i, kam in enumerate(K["kamery"]):
    img = np.asarray(Image.open("%s/mv-%d.png" % (VYDY, i)).convert("RGB"), np.float64) / 255
    if KOR is not None:
        img = np.clip((img - KOR[0]) / np.maximum(KOR[1], 1e-3) * KOR[3] + KOR[2], 0, 1)
    if img.shape[0] != RES:
        img = np.asarray(Image.fromarray((img * 255).astype(np.uint8)).resize((RES, RES), Image.LANCZOS), np.float64) / 255
    zb = zbufer(kam)
    px, py, z = piksel(Pt, kam)
    ix, iy = np.clip(px.astype(int), 0, RES - 1), np.clip(py.astype(int), 0, RES - 1)
    vydno = z <= zb[iy, ix] + 0.004          # не затулене іншою частиною тіла
    w = np.clip(-(Nt @ np.array(kam["look"])), 0, 1) ** 4 * vydno
    if i >= 4:
        # верх і низ — лише латка, де бічні не бачать: MV-Adapter малює їх
        # вицвілими майже до білого, і на плечах, голові й грудях вони
        # перебивали оливкову шкіру (09.11)
        w *= 0.01
    # білінійна вибірка
    fx, fy = np.clip(px - 0.5, 0, RES - 1.001), np.clip(py - 0.5, 0, RES - 1.001)
    x0, y0 = fx.astype(int), fy.astype(int)
    ax_, ay_ = (fx - x0)[:, None], (fy - y0)[:, None]
    c = (img[y0, x0] * (1 - ax_) * (1 - ay_) + img[y0, x0 + 1] * ax_ * (1 - ay_)
         + img[y0 + 1, x0] * (1 - ax_) * ay_ + img[y0 + 1, x0 + 1] * ax_ * ay_)
    SUMA += c * w[:, None]
    VAGA += w
    print("вигляд", i, "видно текселів", int(vydno.sum()), flush=True)

pokr = np.clip(VAGA / 0.15, 0, 1)
kol = SUMA / np.maximum(VAGA, 1e-6)[:, None]

baza = np.asarray(Image.open(BAZA).convert("RGB").resize((N, N), Image.LANCZOS), np.float64) / 255
dobri = pokr > 0.9
# тон: MV-Adapter малює шкіру світлішою й сірішою за референс — у грі орк
# виходив блідо-сірим (09.11). Світлі текселі (шкіра; пояс і штани темні)
# зводяться до середнього базової шкіри на тих самих місцях, решта —
# тим самим множником.
if "--без-тону" not in A:
    lum = kol @ np.array([0.299, 0.587, 0.114])
    sv = dobri & (lum > np.quantile(lum[dobri], 0.5))
    # корінь — пів поправки: повна давала в грі кислотно-зелений (09.11)
    g = np.sqrt(baza[yy[sv], xx[sv]].mean(0) / np.maximum(kol[sv].mean(0), 1e-3))
    kol = np.clip(kol * g, 0, 1)
    print("тон: множник", np.round(g, 2), flush=True)
baza_t = np.clip(baza * (kol[dobri].mean(0) / np.maximum(baza[yy[dobri], xx[dobri]].mean(0), 1e-3)), 0, 1)
ALB = baza_t.copy()
ALB[yy, xx] = kol * pokr[:, None] + baza_t[yy, xx] * (1 - pokr[:, None])
# шви: краї островів розтягнути на тло
im = Image.fromarray((ALB * 255).astype(np.uint8))
maska = Image.fromarray((M * 255).astype(np.uint8))
for _ in range(8):
    roz = im.filter(ImageFilter.MaxFilter(3))
    im = Image.composite(im, roz, maska)
    maska = maska.filter(ImageFilter.MaxFilter(3))
im.save(VYHID)
pk = np.zeros((N, N))
pk[yy, xx] = pokr
Image.fromarray((pk * 255).astype(np.uint8)).save(VYHID.rsplit(".", 1)[0] + "-покриття.png")
print("покрито %.0f %% текселів тіла → %s" % (100 * (pokr > 0.5).mean(), VYHID), flush=True)
