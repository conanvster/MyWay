#!/usr/bin/env python3
"""Маски кольорів для людини MPFB (П-281, крок 3) — у розгортці MPFB.

Канали — як у ельфійок (`avatar_skin.gdshader`, `maski_oblychchia.py`):
R райдужка, G підводка, B губи, A скальп. У MPFB райдужка — на окремій
сітці очей, тож для тіла R порожній, а для очей пишеться окрема маска
(`<вихід-очі>`: R — райдужка й зіниця за текстурою очей MPFB; розкладка в
усіх текстурах очей MPFB однакова).

Ваги губ, підводки й скальпу — з груп вершин MPFB (`pilot_rysy.py` пише
`<…>.npz`: UV трикутників і ваги в їхніх вершинах) — растр із
барицентричним змішуванням і м'яким краєм.

    ~/Програми/cv-venv/bin/python tools/pilot_maski.py <риси.npz> \\
        <текстура-очей.png> <маски.png> <маски-очі.png> [розмір 2048]
"""
import sys

import cv2
import numpy as np

NPZ, OCHI, VYKHID, VYKHID_OCHI = sys.argv[1:5]
N = int(sys.argv[5]) if len(sys.argv) > 5 else 2048

d = np.load(NPZ)
uv, w = d["uv"], d["w"]             # (T, 3, 2), (T, 3, 3): підводка, губи, скальп
kanaly = np.zeros((N, N, 3), np.float32)
for t in np.where(w.max(axis=(1, 2)) > 0)[0]:
    p = np.c_[uv[t, :, 0] * N, (1 - uv[t, :, 1]) * N]
    x0, y0 = np.floor(p.min(0)).astype(int)
    x1, y1 = np.ceil(p.max(0)).astype(int)
    x0, y0 = max(x0, 0), max(y0, 0)
    x1, y1 = min(x1, N - 1), min(y1, N - 1)
    if x1 < x0 or y1 < y0:
        continue
    yy, xx = np.mgrid[y0:y1 + 1, x0:x1 + 1] + 0.5
    a, b, c = p
    den = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
    if abs(den) < 1e-12:
        continue
    l1 = ((b[1] - c[1]) * (xx - c[0]) + (c[0] - b[0]) * (yy - c[1])) / den
    l2 = ((c[1] - a[1]) * (xx - c[0]) + (a[0] - c[0]) * (yy - c[1])) / den
    l3 = 1 - l1 - l2
    vseredyni = (l1 >= -0.02) & (l2 >= -0.02) & (l3 >= -0.02)
    val = l1[..., None] * w[t, 0] + l2[..., None] * w[t, 1] + l3[..., None] * w[t, 2]
    oblast = kanaly[y0:y1 + 1, x0:x1 + 1]
    oblast[vseredyni] = np.maximum(oblast[vseredyni], val[vseredyni])
k = max(3, N // 512) | 1
kanaly = cv2.GaussianBlur(kanaly, (k, k), 0)
pidv, guby, skalp = (np.clip(kanaly[..., i], 0, 1) for i in range(3))
# губи: м'якший край усередину (група MPFB захоплює й шкіру біля губ)
guby = np.clip((guby - 0.25) / 0.6, 0, 1)
rgba = np.zeros((N, N, 4), np.uint8)
rgba[..., 1] = pidv * 255
rgba[..., 2] = guby * 255
rgba[..., 3] = skalp * 255
# cv2 пише BGRA
cv2.imwrite(VYKHID, rgba[..., [2, 1, 0, 3]])
print("[маски] тіло %s: підводка %d px, губи %d px, скальп %d px"
      % (VYKHID, (pidv > 0.1).sum(), (guby > 0.1).sum(), (skalp > 0.1).sum()))

# ── Очі: райдужка й зіниця — насичене або темне всередині білка ─────────
img = cv2.imread(OCHI)
hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV).astype(np.float32) / 255
s, v = hsv[..., 1], hsv[..., 2]
rai = ((s > 0.35) | (v < 0.3)).astype(np.uint8)
# найбільші два круглі плями (два ока на текстурі)
n, lab, st, cen = cv2.connectedComponentsWithStats(rai)
poriadok = np.argsort(-st[1:, cv2.CC_STAT_AREA])[:2] + 1
m = np.zeros(rai.shape, np.float32)
for i in poriadok:
    r = np.sqrt(st[i, cv2.CC_STAT_AREA] / np.pi) * 1.04
    cv2.circle(m, tuple(int(x) for x in cen[i]), int(r), 1.0, -1, cv2.LINE_AA)
m = cv2.GaussianBlur(m, (0, 0), img.shape[0] / 300)
oc = np.zeros(img.shape[:2] + (4,), np.uint8)
oc[..., 2] = np.clip(m, 0, 1) * 255          # R (у BGRA — індекс 2)
cv2.imwrite(VYKHID_OCHI, oc)
print("[маски] очі %s: райдужок %d, радіуси %s px" % (
    VYKHID_OCHI, len(poriadok),
    [int(np.sqrt(st[i, cv2.CC_STAT_AREA] / np.pi)) for i in poriadok]))
