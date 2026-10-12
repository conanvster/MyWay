#!/usr/bin/env python3
"""Маски рис обличчя на кадрі-референсі (12.10.2026) — для вибору кольору
очей, підводки, губ і зачіски в грі (слово замовника: «Очі різного кольору
та контурів … Колір зачіски … Колір скіна»).

Точки — MediaPipe з `tools/oblychchia.py` (478, у пікселях кадру). Канали:
  R — райдужка (коло за точками 468…477, лише в межах ока);
  G — підводка (смуга вздовж контуру ока, верхня повіка ширша);
  B — губи (зовнішній контур, м'який край);
  A — волосся на голові (світле й ненасичене в межах фігури над шиєю,
      без обличчя й вух) — у грі фарбується кольором зачіски.

R, G, B — у `<маски.png>`, A — окремою сірою `<маска-волосся.png>`
(запікання Blender пише лише колір, без альфи). Викликає
`avatar_build.py`, коли поруч із кадром їх ще немає.

    ~/Програми/cv-venv/bin/python tools/maski_oblychchia.py <кадр.png> \\
        <маска-фігури.png> <точки.npy> <маски.png> <маска-волосся.png>
"""
import sys

import cv2
import numpy as np

OKO = ([33, 7, 163, 144, 145, 153, 154, 155, 133, 173, 157, 158, 159, 160, 161, 246],
       [263, 249, 390, 373, 374, 380, 381, 382, 362, 398, 384, 385, 386, 387, 388, 466])
GUBY = [61, 146, 91, 181, 84, 17, 314, 405, 321, 375, 291, 409, 270, 269, 267, 0,
        37, 39, 40, 185]
OVAL = [10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379,
        378, 400, 377, 152, 148, 176, 149, 150, 136, 172, 58, 132, 93, 234, 127,
        162, 21, 54, 103, 67, 109]


def poly(shape, pts, rozmyty=0.0):
    m = np.zeros(shape, np.float32)
    cv2.fillPoly(m, [np.round(pts).astype(np.int32)], 1.0)
    if rozmyty > 0:
        m = cv2.GaussianBlur(m, (0, 0), rozmyty)
    return m


def main():
    kadr = cv2.imread(sys.argv[1])
    figura = cv2.imread(sys.argv[2], cv2.IMREAD_GRAYSCALE) > 127
    F = np.load(sys.argv[3])
    h, w = kadr.shape[:2]
    shyr_oka = np.linalg.norm(F[133] - F[33])
    maski = np.zeros((h, w, 4), np.float32)
    for k, kontur in enumerate(OKO):
        oko = poly((h, w), F[kontur])
        c = F[468 + 5 * k]
        r = np.mean([np.linalg.norm(F[468 + 5 * k + j] - c) for j in range(1, 5)])
        kolo = np.zeros((h, w), np.float32)
        cv2.circle(kolo, tuple(np.round(c).astype(int)), int(round(r * 1.05)), 1.0, -1)
        kolo = cv2.GaussianBlur(kolo, (0, 0), max(1.0, r * 0.12))
        maski[..., 0] = np.maximum(maski[..., 0], kolo * oko)
        # підводка: смуга навколо контуру, зверху ширша (вії), знизу тонка
        zovn = cv2.dilate(oko, np.ones((3, 3), np.uint8),
                          iterations=max(2, int(shyr_oka * 0.09)))
        smuga = np.clip(zovn - oko, 0, 1)
        verkh = np.zeros((h, w), np.float32)
        yy = np.arange(h)[:, None]
        cz = F[kontur][:, 1].mean()
        verkh[:] = np.where(yy < cz, 1.0, 0.45)
        maski[..., 1] = np.maximum(maski[..., 1],
                                   cv2.GaussianBlur(smuga * verkh, (0, 0), 1.2))
    maski[..., 2] = poly((h, w), F[GUBY], rozmyty=max(1.5, shyr_oka * 0.04))
    # волосся: ненасичене в межах фігури, вище підборіддя (+ шия
    # до плечей — пасма), поза овалом обличчя (вуха — насичені, шкіра)
    # Колірність Lab: сиве волосся 3…6, бліда шкіра ельфійки 10…18 (чоло й
    # груди за насиченістю HSV від волосся не відрізнялись).
    lab = cv2.cvtColor(kadr, cv2.COLOR_BGR2LAB).astype(np.float32)
    nenas = np.hypot(lab[..., 1] - 128, lab[..., 2] - 128) < 7.5
    oval = cv2.dilate(poly((h, w), F[OVAL]), np.ones((5, 5), np.uint8), iterations=2) > 0.5
    pidboriddia = F[152, 1]
    vys_oblychchia = F[152, 1] - F[10, 1]
    nad_plechyma = np.arange(h)[:, None] < pidboriddia + vys_oblychchia * 0.9
    shyr = np.abs(np.arange(w)[None, :] - F[1, 0]) < vys_oblychchia * 0.9
    volossia = (nenas & figura & nad_plechyma & shyr & ~oval).astype(np.float32)
    volossia = cv2.morphologyEx(volossia, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    volossia = cv2.GaussianBlur(volossia, (0, 0), 2.0)
    # нижче мочок вух спереду — пасма на шиї й плечах, не скальп
    mochky = max(F[234, 1], F[454, 1]) + vys_oblychchia * 0.12
    volossia[np.arange(h) > mochky] = 0
    maski[..., 3] = volossia
    out = (np.clip(maski, 0, 1) * 255).astype(np.uint8)
    cv2.imwrite(sys.argv[4], cv2.cvtColor(out[..., :3], cv2.COLOR_RGB2BGR))
    cv2.imwrite(sys.argv[5], out[..., 3])
    print("[маски] райдужка %d px, підводка %d, губи %d, волосся %d"
          % tuple((maski[..., k] > 0.5).sum() for k in range(4)))


if __name__ == "__main__":
    main()
