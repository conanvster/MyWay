#!/usr/bin/env python3
"""Чисті референси під 3D для аватара (01.10.2026): T-поза, сіре тло.

Слово замовника: «нагенерувати чисті референси для 3D моделі для Людина,
чоловік — варіант 1, та зберегти їх в test.html, створи 3D модель людини
з референсу з рухами, які є в переліку `./run.sh --рухи-людини`».

Рухи людини (UAL1) гра пересаджує лише на скелет манекена гравця, а
манекен стоїть у T-позі — тож референс ставиться в ту саму T-позу
(Kontext, розділ 1а спеки референсів), інакше сітку не посадити на
скелет. Сіре однотонне тло — під Pixal3D.

    python3 -u tools/comfyui/avatar_ref.py [--дзеркало ~/гра-lineage]
    python3 -u tools/comfyui/avatar_ref.py --база [--дзеркало …]   без одягу

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


# Крок 2 (слово замовника 01.10.2026): «референси T-поза seed 11
# згенеровані під якийсь тип одягу. Бажано, щоб модель не змінювалась
# незалежно від того, який одяг буде надягнуто, а без одягу повинна
# залишатися пов'язка». Тож база — без одягу, лише пов'язка; одяг ляже
# поверх окремими частинами, як у `make_races.py`. Вхід — T-поза seed 11.
BAZA_Z = VYKHID / "tpoza-s11.png"
BAZA_SIDY = [111, 122, 133, 144]
BAZA_PROMT = (
    "Remove all of his clothing, belt, vest, shirt, trousers and boots, "
    "and dress him only in a simple plain undyed linen loincloth wrapped "
    "around his hips. Show his bare muscular torso, bare arms, bare legs "
    "and bare feet with natural realistic skin. Keep everything else "
    "exactly the same: same face, same hair, same beard, same skin tone, "
    "same body proportions and build, same strict T-pose with both arms "
    "straight out horizontally, same front view, same plain light grey "
    "studio background, same soft even lighting, same photorealistic "
    "style.")


# База 2 (01.10.2026: «поломаний вигляд ніг під накидкою»): широка
# пов'язка-спідниця злилась у Pixal3D зі стегнами в одну брилу — під нею
# немає ніг, і в русі вона рвалась. Тепер — коротка щільна пов'язка, як
# труси, стегна окремі й відкриті.
BAZA2_SIDY = [211, 222, 233, 244]
BAZA2_PROMT = (
    "Remove all of his clothing, belt, vest, shirt, trousers and boots, "
    "and dress him only in a short tight-fitting plain undyed linen "
    "loincloth wrapped snugly around his hips and groin like fitted briefs, "
    "ending high at the top of the thighs, nothing hanging down, so both "
    "thighs are fully bare, clearly separated and visible down to the "
    "knees. Show his bare muscular torso, bare arms, bare legs and bare "
    "feet with natural realistic skin. Keep everything else exactly the "
    "same: same face, same hair, same beard, same skin tone, same body "
    "proportions and build, same strict T-pose with both arms straight out "
    "horizontally, same legs slightly apart, same front view, same plain "
    "light grey studio background, same soft even lighting, same "
    "photorealistic style.")


def baza2(dzerkalo):
    rk.PROMT = BAZA2_PROMT
    image = m.stage(str(BAZA_Z))
    m.free()
    for seed in BAZA2_SIDY:
        done = m.run(rk.graf(image, seed, "avatar1_baza2_s%d" % seed))
        out = done["outputs"]["13"]["images"][-1]
        shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"],
                                 out["filename"]),
                    VYKHID / ("baza2-s%d.png" % seed))
        print("готово база2", seed, flush=True)
        vpysaty(SIDY)
        dzerk(dzerkalo, "baza2-s%d.png" % seed)


# Голова для перуки (01.10.2026, «1 — окрема перука зі скану голови»):
# у кадрі всієї постаті голова — кілька десятків пікселів, і Pixal3D
# пасм не бачить. Великий кадр тієї самої голови дає їх у десятки разів
# більше.
HOLOVA_SIDY = [311, 322]
HOLOVA_PROMT = (
    "Change only the framing and the background: show an extreme close-up "
    "of the same man's head, from the base of his neck to just above the "
    "top of his hair, the head filling the whole frame, facing the camera "
    "directly, front view, eyes open, neutral expression, every strand of "
    "his hair sharply detailed with its volume and shape clearly visible. "
    "Plain uniform light grey studio background, soft even lighting. Keep "
    "exactly the same man: same face, same hairstyle and hair colour, same "
    "beard, same skin tone, same photorealistic style.")


def holova(dzerkalo):
    rk.PROMT = HOLOVA_PROMT
    image = m.stage(str(BAZA_Z))
    # Без m.free(): поруч може йти інший прогін Kontext — та сама модель.
    for seed in HOLOVA_SIDY:
        done = m.run(rk.graf(image, seed, "avatar1_holova_s%d" % seed))
        out = done["outputs"]["13"]["images"][-1]
        shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"],
                                 out["filename"]),
                    VYKHID / ("holova-s%d.png" % seed))
        print("готово голова", seed, flush=True)
        vpysaty(SIDY)
        dzerk(dzerkalo, "holova-s%d.png" % seed)


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
    r.append('</div>')
    bazy = [s for s in BAZA_SIDY
            if (VYKHID / ("baza-s%d.png" % s)).exists()]
    if bazy:
        r += ['<h3>База без одягу — лише пов\'язка</h3>',
              '<p class="note">Модель не залежить від одягу: одяг ляже '
              'поверх окремими частинами. Kontext від T-пози seed 11.</p>',
              '<div class="compare">']
        for seed in bazy:
            r.append('<figure><img src="img/test/avatar/baza-s%d.png" '
                     'alt="база, seed %d"><figcaption><b>база</b>Kontext '
                     'від s11, seed %d</figcaption></figure>'
                     % (seed, seed, seed))
        r.append('</div>')
    for nazva, shablon, sidy in (
            ("Голова для перуки — великий кадр", "holova-s%d.png",
             HOLOVA_SIDY),
            ("База 2 — щільна коротка пов'язка (ноги окремі)",
             "baza2-s%d.png", BAZA2_SIDY),
            ("Людина, жінка — T-поза", "zh-tpoza-s%d.png", SIDY),
            ("Людина, жінка — база: пов'язки на стегнах і на грудях",
             "zh-baza-s%d.png", BAZA_SIDY)):
        ye = [s for s in sidy if (VYKHID / (shablon % s)).exists()]
        if not ye:
            continue
        r += ['<h3>%s</h3>' % nazva, '<div class="compare">']
        for seed in ye:
            r.append('<figure><img src="img/test/avatar/%s" alt="%s"><figcaption>'
                     '<b>%s</b>Kontext, seed %d</figcaption></figure>'
                     % (shablon % seed, nazva, nazva.split(" — ")[1], seed))
        r.append('</div>')
    r.append('<!-- /аватар -->')
    return "\n".join(r)


def vpysaty(kadry):
    t = STORINKA.read_text(encoding="utf-8")
    a = t.index("<!-- аватар -->")
    b = t.index("<!-- /аватар -->") + len("<!-- /аватар -->")
    STORINKA.write_text(t[:a] + rozdil(kadry) + t[b:], encoding="utf-8")


def baza(dzerkalo):
    rk.PROMT = BAZA_PROMT
    image = m.stage(str(BAZA_Z))
    for seed in BAZA_SIDY:
        done = m.run(rk.graf(image, seed, "avatar1_baza_s%d" % seed))
        out = done["outputs"]["13"]["images"][-1]
        kudy = VYKHID / ("baza-s%d.png" % seed)
        shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"],
                                 out["filename"]), kudy)
        vpysaty(SIDY)
        if dzerkalo:
            shutil.copy(kudy, dzerkalo / "wiki/img/test/avatar")
            shutil.copy(STORINKA, dzerkalo / "wiki/test.html")
        print("готово база", seed, flush=True)


# Жінка (слово замовника 01.10.2026: «паралельно згенеруй рендер для
# людини жінки, у двох пов'язках на торсі та на рівні грудей»). Ті самі
# два кроки; T-поза й база — з людини-жінки варіанта 1.
ZHINKA = {
    "dzherelo": KORIN / "wiki/img/rasy/людина-жінка-v1.png",
    "prefix": "zh-",
    "tpoza": PROMT.replace("The same man", "The same woman")
    .replace("his hands or hanging from his belt",
             "her hands or hanging from her belt")
    .replace("Keep exactly the same man: same face, same hair, same "
             "beard,", "Keep exactly the same woman: same face, same hair,"),
    "baza": (
        "Remove all of her clothing, belt, vest, shirt, trousers and boots, "
        "and dress her only in two simple plain undyed linen wraps: a short "
        "tight-fitting loincloth wrapped snugly around her hips and groin "
        "like fitted briefs, ending high at the top of the thighs with "
        "nothing hanging down, and a band wrapped tightly around her chest "
        "covering her breasts. Both thighs fully bare and clearly "
        "separated. Show her bare shoulders, bare arms, bare midriff, bare "
        "legs and bare feet with natural "
        "realistic skin. Keep everything else exactly the same: same face, "
        "same hair, same skin tone, same body proportions and build, same "
        "strict T-pose with both arms straight out horizontally, same front "
        "view, same plain light grey studio background, same soft even "
        "lighting, same photorealistic style."),
}


def zhinka(dzerkalo):
    """Обидва кроки для жінки: 4 T-пози, тоді база з першої."""
    rk.PROMT = ZHINKA["tpoza"]
    image = m.stage(str(ZHINKA["dzherelo"]))
    m.free()
    for seed in SIDY:
        if (VYKHID / ("zh-tpoza-s%d.png" % seed)).exists():
            continue
        done = m.run(rk.graf(image, seed, "avatar1_zh_tpoza_s%d" % seed))
        out = done["outputs"]["13"]["images"][-1]
        shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"],
                                 out["filename"]),
                    VYKHID / ("zh-tpoza-s%d.png" % seed))
        print("готово жінка T-поза", seed, flush=True)
        vpysaty(SIDY)
        dzerk(dzerkalo, "zh-tpoza-s%d.png" % seed)
    rk.PROMT = ZHINKA["baza"]
    image = m.stage(str(VYKHID / "zh-tpoza-s11.png"))
    for seed in BAZA_SIDY:
        done = m.run(rk.graf(image, seed, "avatar1_zh_baza_s%d" % seed))
        out = done["outputs"]["13"]["images"][-1]
        shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"],
                                 out["filename"]),
                    VYKHID / ("zh-baza-s%d.png" % seed))
        print("готово жінка база", seed, flush=True)
        vpysaty(SIDY)
        dzerk(dzerkalo, "zh-baza-s%d.png" % seed)


def dzerk(dzerkalo, fail):
    if dzerkalo:
        (dzerkalo / "wiki/img/test/avatar").mkdir(parents=True, exist_ok=True)
        shutil.copy(VYKHID / fail, dzerkalo / "wiki/img/test/avatar")
        shutil.copy(STORINKA, dzerkalo / "wiki/test.html")


def main():
    if "--голова" in sys.argv:
        dzerkalo = Path(sys.argv[sys.argv.index("--дзеркало") + 1]) \
            if "--дзеркало" in sys.argv else None
        holova(dzerkalo)
        return
    if "--база2" in sys.argv:
        dzerkalo = Path(sys.argv[sys.argv.index("--дзеркало") + 1]) \
            if "--дзеркало" in sys.argv else None
        baza2(dzerkalo)
        return
    if "--жінка" in sys.argv:
        dzerkalo = Path(sys.argv[sys.argv.index("--дзеркало") + 1]) \
            if "--дзеркало" in sys.argv else None
        zhinka(dzerkalo)
        return
    if "--база" in sys.argv:
        dzerkalo = Path(sys.argv[sys.argv.index("--дзеркало") + 1]) \
            if "--дзеркало" in sys.argv else None
        baza(dzerkalo)
        return
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
