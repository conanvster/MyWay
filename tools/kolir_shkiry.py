#!/usr/bin/env python3
"""Тон шкіри — як на вхідному кадрі (09.11.2026).

Kontext, прибравши бороду й волосся зі словами «green orc skin», робив
шкіру кислотно-зеленою, а без слова «orc» — людиною без вух та ікол
(раунди 2–3 `lysyi_pidbir.py`). Тут форма — з результату Kontext, колір —
з вхідного кадру: середнє й розкид каналів Lab по шкірі (силует без темних
плавок і тла) переносяться на весь силует результату.

    ~/Програми/cv-venv/bin/python tools/kolir_shkiry.py <результат.png> <вхід.png> <вихід.png>
"""
import sys

import cv2
import numpy as np

rez_f, vkh_f, out_f = sys.argv[1:4]
rez = cv2.imread(rez_f)
vkh = cv2.resize(cv2.imread(vkh_f), (rez.shape[1], rez.shape[0]))


def shkira(im):
    """Шкіра: не сіре тло й не чорні плавки — за насиченістю (обоє сірі).
    Поріг яскравості відсікав затінену шкіру — у тінях лишались зелені плями
    (09.11)."""
    hsv = cv2.cvtColor(im, cv2.COLOR_BGR2HSV)
    return (hsv[..., 1] > 28) & (hsv[..., 2] > 25)


lr = cv2.cvtColor(rez, cv2.COLOR_BGR2LAB).astype(np.float32)
lv = cv2.cvtColor(vkh, cv2.COLOR_BGR2LAB).astype(np.float32)
mr, mv = shkira(rez), shkira(vkh)
out = lr.copy()
for c in range(3):
    a, b = lr[..., c][mr], lv[..., c][mv]
    nove = (lr[..., c] - a.mean()) / max(a.std(), 1e-3) * b.std() + b.mean()
    out[..., c] = np.where(mr, nove, lr[..., c])
# м'який край маски, щоб на межі шкіри не було сходинки
alfa = cv2.GaussianBlur(mr.astype(np.float32), (0, 0), 2)[..., None]
res = cv2.cvtColor(np.clip(out, 0, 255).astype(np.uint8), cv2.COLOR_LAB2BGR).astype(np.float32)
res = res * alfa + rez.astype(np.float32) * (1 - alfa)
cv2.imwrite(out_f, res.astype(np.uint8))
print("тон →", out_f)
