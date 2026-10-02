#!/usr/bin/env python3
"""Вирівнювання проєкції обличчя за опорними точками (02.10.2026).

Рендер моделі MPFB у тій самій прив'язці, що й проєкція, і кадр — на обох
шукаються 478 точок обличчя (`tools/oblychchia.py`). Сплайн тонкої пластини
переводить точки моделі в точки кадру; ним зсуваються координати проєкції
вершин обличчя (з плавним згасанням до країв голови), — і намальовані очі,
брови, губи лягають точно на очні ямки, брови й губи сітки.

    ~/Програми/cv-venv/bin/python tools/oblychchia_warp.py <кадр.png> \\
        <маска.png> <рендер_моделі.png> <точки_в.npy> <точки_з.npy>

Точки — пікселі кадру (x, y зверху), (n, 2).
"""
import os
import subprocess
import sys
import tempfile

import cv2
import numpy as np
from scipy.interpolate import RBFInterpolator

TUT = os.path.dirname(os.path.abspath(__file__))


def tochky(kadr, maska):
    out = tempfile.mktemp(suffix=".npy")
    r = subprocess.run([sys.executable, os.path.join(TUT, "oblychchia.py"),
                        kadr, maska, out], capture_output=True, text=True)
    if r.returncode != 0 or not os.path.exists(out):
        sys.exit("‼ точки обличчя: %s" % (r.stdout + r.stderr)[-300:])
    return np.load(out)


def main():
    kadr, maska, rnd, p_in, p_out = sys.argv[1:6]
    # Маска рендеру — з його альфи.
    rgba = cv2.imread(rnd, cv2.IMREAD_UNCHANGED)
    m_rnd = tempfile.mktemp(suffix=".png")
    cv2.imwrite(m_rnd, ((rgba[..., 3] > 127) * 255).astype(np.uint8))
    rgb = tempfile.mktemp(suffix=".png")
    bg = np.full_like(rgba[..., :3], 200)
    a = (rgba[..., 3:4] / 255.0)
    cv2.imwrite(rgb, (rgba[..., :3] * a + bg * (1 - a)).astype(np.uint8))
    L_ref = tochky(kadr, maska)
    L_mod = tochky(rgb, m_rnd)
    d = L_ref - L_mod
    # Якорі нульового зсуву по колу довкола обличчя — поле не розповзається.
    c = L_mod.mean(0)
    r = np.linalg.norm(L_mod - c, axis=1).max()
    kut = np.linspace(0, 2 * np.pi, 24, endpoint=False)
    yak = c + np.stack([np.cos(kut), np.sin(kut)], 1) * r * 1.6
    src = np.concatenate([L_mod, yak])
    dst = np.concatenate([d, np.zeros_like(yak)])
    rbf = RBFInterpolator(src, dst, kernel="thin_plate_spline", smoothing=1.0)
    P = np.load(p_in)
    vidst = np.linalg.norm(P - c, axis=1)
    vaga = np.clip((r * 1.6 - vidst) / (r * 0.6), 0, 1)[:, None]
    zsuv = np.zeros_like(P)
    blyz = vaga[:, 0] > 0
    zsuv[blyz] = rbf(P[blyz])
    np.save(p_out, (P + zsuv * vaga).astype(np.float32))
    print("[обличчя] зсув точок модель→кадр: середній %.2f px, найбільший "
          "%.2f px" % (np.linalg.norm(d, axis=1).mean(),
                       np.linalg.norm(d, axis=1).max()))


if __name__ == "__main__":
    main()
