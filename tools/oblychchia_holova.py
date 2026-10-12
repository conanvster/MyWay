#!/usr/bin/env python3
"""Точки обличчя на рендері голови (MediaPipe FaceLandmarker, 478 точок).

Для `avatar_build.py --обличчя`: голова скану рендериться спереду на весь
кадр, тут — точки в пікселях цього рендера (на відміну від
`oblychchia.py`, що шукає голову в кадрі всієї постаті).

    ~/Програми/cv-venv/bin/python tools/oblychchia_holova.py <рендер.png> <точки.npy>
"""
import sys

import cv2
import mediapipe as mp
import numpy as np
from mediapipe.tasks.python import BaseOptions, vision

MODEL = "/home/alex/Програми/mediapipe-models/face_landmarker.task"


def main():
    im = cv2.imread(sys.argv[1], cv2.IMREAD_UNCHANGED)
    if im.shape[2] == 4:            # прозоре тло → сіре
        a = im[..., 3:4].astype(float) / 255
        im = (im[..., :3] * a + 128 * (1 - a)).astype(np.uint8)
    rgb = cv2.cvtColor(im, cv2.COLOR_BGR2RGB)
    det = vision.FaceLandmarker.create_from_options(vision.FaceLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=MODEL), num_faces=1))
    r = det.detect(mp.Image(image_format=mp.ImageFormat.SRGB,
                            data=np.ascontiguousarray(rgb)))
    if not r.face_landmarks:
        sys.exit("‼ обличчя на рендері не знайдено")
    h, w = rgb.shape[:2]
    L = np.array([(p.x * w, p.y * h) for p in r.face_landmarks[0]], dtype=np.float32)
    np.save(sys.argv[2], L)
    print("[обличчя-рендер] точок %d, очі %s / %s, рот %s" % (
        len(L), L[33].round(1), L[263].round(1), L[13].round(1)))


if __name__ == "__main__":
    main()
