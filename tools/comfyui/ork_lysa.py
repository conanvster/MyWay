#!/usr/bin/env python3
"""Орчиха-основа: лиса, у чорних трусиках — тіло пікселями кадру (12.10.2026).

Слово замовника: «згенеруй за тими ж правилами Орк, жінка — варіант 1 …
без зачіски — лиса голова»; «[рендер] — референс орка — використай його».
FLUX з нуля (`ork_osnova.py`) статури референсу не тримав (інші плечі й
стегна), тож як `elf_korotke.py`: перемальовується лише маска —
  * волосся: темне й ненасичене (HSV: S < 45, V < 95) над поясом у межах
    плечей, поза овалом обличчя;
  * пояс і спідниця: не-зелене (відтінок поза 15…45 або S < 40) між поясом
    і низом спідниці в межах стегон;
FLUX dev + ControlNet за скелетом (`ork2-cn-poza.png`), шум 1,0 у масці,
решта — пікселі кадру (зшивка м'якою маскою).

    ~/Програми/cv-venv/bin/python -u tools/comfyui/ork_lysa.py [сід…]

Вихід — `wiki/img/test/avatar/ork2-lysa-s<сід>.png` (+ `ork2-lysa-maska.png`).
"""
import os
import shutil
import sys

import cv2
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import monster3d as m  # noqa: E402
import elf_nabory_cn as cn  # noqa: E402

D = cn.D
OSNOVA = D / "ork-tpoza-v2.png"
POZA = "ork2-cn-poza.png"
SIDY = [int(a) for a in sys.argv[1:] if a.isdigit()] or [1301, 1302, 1303]
OVAL = [10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379,
        378, 400, 377, 152, 148, 176, 149, 150, 136, 172, 58, 132, 93, 234, 127,
        162, 21, 54, 103, 67, 109]
PROMT = (
    "Full body neutral studio reference photo of an adult female orc in a "
    "strict T-pose, front view. Completely bald head: a clean smooth shaved "
    "olive-green scalp with no hair at all, the round shape of her skull "
    "visible, long pointed ears, bare green neck and shoulders with no hair "
    "on them. Topless, wearing only plain simple black briefs, bare "
    "muscular green thighs, no belt, no skirt, no pouch. Olive-green skin, "
    "muscular feminine body. Grey grid studio backdrop, soft even lighting, "
    "photorealistic.")


def oval_oblychchia(a):
    import mediapipe as mpp
    from mediapipe.tasks.python import BaseOptions, vision
    import elf_markery as mk
    det = vision.FaceLandmarker.create_from_options(vision.FaceLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=mk.MODEL), num_faces=1))
    x0, x1, y0, y1, k = 362, 662, 0, 300, 3
    big = np.asarray(Image.fromarray(a[y0:y1, x0:x1]).resize(((x1 - x0) * k, (y1 - y0) * k),
                                                              Image.LANCZOS))
    lm = det.detect(mpp.Image(image_format=mpp.ImageFormat.SRGB,
                              data=np.ascontiguousarray(big))).face_landmarks[0]
    return np.array([(x0 + lm[i].x * (x1 - x0), y0 + lm[i].y * (y1 - y0)) for i in OVAL])


def maska(a):
    h, w = a.shape[:2]
    hsv = cv2.cvtColor(a, cv2.COLOR_RGB2HSV).astype(int)
    H, S, V = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    yy, xx = np.mgrid[0:h, 0:w]
    # лише в межах силуету фігури (birefnet, кеш `<кадр>-маска.png`): сіра
    # сітка тла теж «ненасичена й не зелена» (перша проба маски)
    import elf_markery as mk
    fig = mk.sylyet(OSNOVA)
    fig = cv2.dilate(fig.astype(np.uint8), np.ones((5, 5), np.uint8), iterations=2) > 0
    ov = oval_oblychchia(a)
    c = ov.mean(0)
    obl = np.zeros((h, w), np.uint8)
    cv2.fillPoly(obl, [np.round(c + (ov - c) * 0.92).astype(np.int32)], 1)
    # волосся: від маківки до поясу, між плечима
    pas = int(ov[:, 1].max() + (ov[:, 1].max() - ov[:, 1].min()) * 2.6)
    vol = fig & (S < 45) & (V < 95) & (yy < pas) & (np.abs(xx - c[0]) < 150) & (obl == 0)
    vol = cv2.morphologyEx(vol.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8))
    n, mit, st, _ = cv2.connectedComponentsWithStats(vol)
    vol = np.isin(mit, [i for i in range(1, n) if st[i, cv2.CC_STAT_AREA] > 400]).astype(np.uint8)
    # пояс і спідниця: не-зелене від поясу до низу спідниці
    zelene = (H >= 15) & (H <= 45) & (S >= 40)
    smuga = (yy > pas - 30) & (yy < pas + 340) & (np.abs(xx - c[0]) < 175)
    odiah = (fig & ~zelene & smuga).astype(np.uint8)
    odiah = cv2.morphologyEx(odiah, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    n, mit, st, _ = cv2.connectedComponentsWithStats(odiah)
    odiah = (mit == 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))).astype(np.uint8)
    odiah = cv2.morphologyEx(odiah, cv2.MORPH_CLOSE, np.ones((31, 31), np.uint8))
    mm = np.maximum(vol, odiah)
    mm = cv2.dilate(mm, np.ones((3, 3), np.uint8), iterations=4)
    mm[obl > 0] = 0
    Image.fromarray(mm * 255).save(D / "ork2-lysa-maska.png")
    print("маска: волосся %d px, одяг %d px" % (vol.sum(), odiah.sum()), flush=True)
    return mm


def main():
    a = np.array(Image.open(OSNOVA).convert("RGB"))
    mm = maska(a)
    if "--лише-маска" in sys.argv:
        return
    osn, msk, poz = (m.stage(str(D / f)) for f in (OSNOVA.name, "ork2-lysa-maska.png", POZA))
    m.free()
    soft = cv2.GaussianBlur(mm.astype(np.float32), (0, 0), 2.0)[..., None]
    for seed in SIDY:
        kudy = D / ("ork2-lysa-s%d.png" % seed)
        if kudy.exists():
            print("є", kudy.name, flush=True)
            continue
        done = m.run(cn.graf(osn, msk, poz, PROMT, seed, "ork2_lysa_%d" % seed))
        out = done["outputs"]["13"]["images"][-1]
        nove = np.array(Image.open(os.path.join(m.COMFY, "output", out["subfolder"],
                                                out["filename"])).convert("RGB")).astype(np.float32)
        zsh = a.astype(np.float32) * (1 - soft) + nove * soft
        Image.fromarray(zsh.clip(0, 255).astype(np.uint8)).save(kudy)
        print("готово", kudy.name, flush=True)
    m.free()


if __name__ == "__main__":
    main()
