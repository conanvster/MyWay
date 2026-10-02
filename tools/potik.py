#!/usr/bin/env python3
"""Щільний оптичний потік «рендер скану → референс» (02.10.2026).

Для проєкції референсу на аватар (`tools/blender/avatar_build.py`): рендер
сирого скану з його власною текстурою Pixal3D лежить на сітці точно, тож
потік від нього до референсу каже, з якого пікселя кадру брати колір для
кожної точки сітки — і там, де лінійна прив'язка хибила (перспектива
MoGe: обличчя, груди, коліна).

    ~/Програми/cv-venv/bin/python tools/potik.py <реф.png> <маска.png> \\
        <рендер.png> <потік.npy>

Потік — (H, W, 2) у пікселях: рендер (y, x) ≈ реф (y + fy, x + fx).
"""
import sys

import cv2
import numpy as np


def sira(rgb, maska):
    g = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY).astype(np.float32)
    m = maska > 0
    # Яскравість і контраст — однакові всередині фігури (текстура Pixal3D
    # темніша за кадр); тло — середнє.
    mu, sd = g[m].mean(), g[m].std() + 1e-3
    g = (g - mu) / sd * 40 + 128
    g[~m] = 128
    return np.clip(g, 0, 255).astype(np.uint8)


def main():
    ref = cv2.cvtColor(cv2.imread(sys.argv[1]), cv2.COLOR_BGR2RGB)
    m_ref = cv2.imread(sys.argv[2], cv2.IMREAD_GRAYSCALE)
    rnd = cv2.imread(sys.argv[3], cv2.IMREAD_UNCHANGED)
    m_rnd = (rnd[..., 3] > 127).astype(np.uint8) * 255
    rnd = cv2.cvtColor(rnd[..., :3], cv2.COLOR_BGR2RGB)
    h, w = m_ref.shape
    if rnd.shape[:2] != (h, w):
        rnd = cv2.resize(rnd, (w, h), interpolation=cv2.INTER_AREA)
        m_rnd = cv2.resize(m_rnd, (w, h), interpolation=cv2.INTER_NEAREST)
    a, b = sira(rnd, m_rnd), sira(ref, m_ref)
    dis = cv2.DISOpticalFlow_create(cv2.DISOPTICAL_FLOW_PRESET_ULTRAFAST + 2)
    dis.setFinestScale(0)
    potik = dis.calc(a, b, None)
    # Лише плавна складова: текстура Pixal3D розмита, і дрібний потік — шум
    # (перша спроба: середній 9 px, 95% до 27 px — гірше, ніж без потоку).
    # Перспектива MoGe зсуває плавно — σ 12 px, не більше 6 px.
    potik = cv2.GaussianBlur(potik, (0, 0), 12)
    dov = np.linalg.norm(potik, axis=2, keepdims=True)
    potik = potik * np.minimum(1.0, 6.0 / np.maximum(dov, 1e-6))
    np.save(sys.argv[4], potik.astype(np.float32))
    m = m_rnd > 0
    print("[потік] середній %.2f px, 95%% до %.2f px"
          % (dov[m].mean(), np.percentile(dov[m], 95)))


if __name__ == "__main__":
    main()
