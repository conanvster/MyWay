#!/usr/bin/env python3
"""Опорні точки обличчя на кадрі (MediaPipe FaceLandmarker, 478 точок).

На кадрі всієї постаті обличчя ~90 px і детектор його не бачить — тож
голова вирізається за маскою (верх 15% фігури), збільшується вчетверо,
точки — назад у координати кадру.

    ~/Програми/cv-venv/bin/python tools/oblychchia.py <кадр.png> <маска.png> \\
        <точки.npy> [<перевірка.png>]
"""
import sys

import cv2
import mediapipe as mp
import numpy as np
from mediapipe.tasks.python import BaseOptions, vision

MODEL = "/home/alex/Програми/mediapipe-models/face_landmarker.task"


def main():
    kadr = cv2.cvtColor(cv2.imread(sys.argv[1]), cv2.COLOR_BGR2RGB)
    maska = cv2.imread(sys.argv[2], cv2.IMREAD_GRAYSCALE) > 127
    ys, xs = np.where(maska)
    y0, y1 = ys.min(), ys.max()
    vys = y1 - y0
    holova = (ys < y0 + 0.15 * vys)
    cx = int(np.median(xs[holova]))
    pol = int(0.11 * vys)
    x0, x1 = max(0, cx - pol), min(kadr.shape[1], cx + pol)
    yy0, yy1 = max(0, y0 - int(0.02 * vys)), min(kadr.shape[0], y0 + int(0.2 * vys))
    vyriz = kadr[yy0:yy1, x0:x1]
    k = 4
    vel = cv2.resize(vyriz, None, fx=k, fy=k, interpolation=cv2.INTER_CUBIC)
    det = vision.FaceLandmarker.create_from_options(vision.FaceLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=MODEL), num_faces=1))
    r = det.detect(mp.Image(image_format=mp.ImageFormat.SRGB,
                            data=np.ascontiguousarray(vel)))
    if not r.face_landmarks:
        sys.exit("‼ обличчя не знайдено")
    L = np.array([(p.x * vel.shape[1] / k + x0, p.y * vel.shape[0] / k + yy0)
                  for p in r.face_landmarks[0]], dtype=np.float32)
    np.save(sys.argv[3], L)
    print("[обличчя] точок %d, очі %s / %s" % (len(L), L[33].round(1),
                                               L[263].round(1)))
    if len(sys.argv) > 4:
        v = cv2.cvtColor(vyriz, cv2.COLOR_RGB2BGR).copy()
        v = cv2.resize(v, None, fx=3, fy=3)
        for x, y in L:
            cv2.circle(v, (int((x - x0) * 3), int((y - yy0) * 3)), 1, (0, 255, 0), -1)
        cv2.imwrite(sys.argv[4], v)


if __name__ == "__main__":
    main()
