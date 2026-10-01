#!/usr/bin/env python3
"""Чисті референси під 3D для аватара (01.10.2026): T-поза, сіре тло.

Слово замовника: «нагенерувати чисті референси для 3D моделі для Людина,
чоловік — варіант 1, та зберегти їх в test.html, створи 3D модель людини
з референсу з рухами, які є в переліку `./run.sh --рухи-людини`».

Рухи людини (UAL1) гра пересаджує лише на скелет манекена гравця, а
манекен стоїть у T-позі — тож референс ставиться в ту саму T-позу
(Kontext, розділ 1а спеки референсів), інакше сітку не посадити на
скелет. Сіре однотонне тло — під Pixal3D.

    python3 -u tools/comfyui/avatar_ref.py [--дзеркало ~/гра-лineage]

Вхід — `wiki/img/rasy/людина-чоловік-v1.png`; вихід —
`wiki/img/test/avatar/tpoza-s<seed>.png` і розділ «Аватар» на test.html
між мітками `<!-- аватар -->`.
"""
import os
import shutil
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster3d as m  # noqa: E402
import rasy_kontext as rk  # noqa: E402

KORIN = Path(__file__).resolve().parents[2]
DZHERELO = KORIN / "wiki/img/rasy/людина-чоловік-v1.png"
VYKHID = KORIN / "wiki/img/test/avatar"
STORINKA = KORIN / "wiki/test.html"
SIDY = [11, 22, 33, 44]
PROMT = (
    "Change only the pose, the view and the background. The same man now "
    "stands in a strict T-pose facing the camera directly: both arms "
    "stretched straight out to the sides horizontally at shoulder height, "
    "palms facing down, fingers together, legs straight and slightly "
    "apart, feet flat on the ground, head level looking straight forward, "
    "front orthographic view, the whole body from head to feet in frame "
    "with margin around it. Remove the knife and anything held in his "
    "hands or hanging from his belt. Replace the forest with a plain "
    "uniform light grey studio background, soft even shadowless lighting. "
    "Keep exactly the same man: same face, same hair, same beard, same "
    "skin, same clothing (linen shirt, brown leather vest, belt, wool "
    "trousers, leather boots), same colours, same photorealistic style.")


def rozdil(kadry):
    r = ['<!-- аватар -->',
         '<h2>Аватар 3D — людина, чоловік, варіант 1</h2>',
         '<p class="note">Чисті референси під 3D-модель: та сама людина '
         'з <a href="rasy.html">варіанта 1</a>, Kontext ставить її в '
         'T-позу манекена (на його скелет лягають рухи '
         '<code>./run.sh --рухи-людини</code>), сіре тло — під Pixal3D. '
         'Вибери, з якого будувати.</p>', '<div class="compare">',
         '<figure class="ref"><img src="img/rasy/людина-чоловік-v1.png" '
         'alt="вихідний варіант 1"><figcaption><b>вихідний</b>варіант 1, '
         'seed 7001</figcaption></figure>']
    for seed in kadry:
        r.append('<figure><img src="img/test/avatar/tpoza-s%d.png" '
                 'alt="T-поза, seed %d"><figcaption><b>T-поза</b>Kontext, '
                 'seed %d</figcaption></figure>' % (seed, seed, seed))
    r += ['</div>', '<!-- /аватар -->']
    return "\n".join(r)


def vpysaty(kadry):
    t = STORINKA.read_text(encoding="utf-8")
    a = t.index("<!-- аватар -->")
    b = t.index("<!-- /аватар -->") + len("<!-- /аватар -->")
    STORINKA.write_text(t[:a] + rozdil(kadry) + t[b:], encoding="utf-8")


def main():
    dzerkalo = Path(sys.argv[sys.argv.index("--дзеркало") + 1]) \
        if "--дзеркало" in sys.argv else None
    VYKHID.mkdir(parents=True, exist_ok=True)
    rk.PROMT = PROMT
    image = m.stage(str(DZHERELO))
    m.free()
    gotovi = []
    for seed in SIDY:
        done = m.run(rk.graf(image, seed, "avatar1_tpoza_s%d" % seed))
        out = done["outputs"]["13"]["images"][-1]
        kudy = VYKHID / ("tpoza-s%d.png" % seed)
        shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"],
                                 out["filename"]), kudy)
        gotovi.append(seed)
        vpysaty(gotovi)
        if dzerkalo:
            (dzerkalo / "wiki/img/test/avatar").mkdir(parents=True,
                                                      exist_ok=True)
            shutil.copy(kudy, dzerkalo / "wiki/img/test/avatar")
            shutil.copy(STORINKA, dzerkalo / "wiki/test.html")
        print("готово", seed, flush=True)


if __name__ == "__main__":
    main()
