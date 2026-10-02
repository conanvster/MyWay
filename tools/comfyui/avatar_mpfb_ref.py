#!/usr/bin/env python3
"""Референси для аватара на MPFB (02.10.2026): А-поза, плавки, кілька видів.

Слова замовника: «краще пропрацювати референси з деталізацією долонь,
ступень, вигляду збоку та ззаду»; «можливо краще зробити модель без
перуки, брів, бороди та вус і окремо їх додавати»; «генерувати референс у
більш прилягаючому одязі, накшталт плавок». Поза — А-поза, як у спокої
MPFB (руки вниз під ~45°), щоб проєкція й підбір фігури лягли точно.

Ланцюжок Kontext від бази seed 222 (`wiki/img/test/avatar/baza2-s222.png`):
  pered  — спереду, плавки, голена голова, без бороди (шкіра й фігура);
  bik    — та сама людина в профіль (з pered);
  zad    — ззаду (з pered);
  volossia — спереду, плавки, з тією самою зачіскою й бородою (накладки).

    python3 -u tools/comfyui/avatar_mpfb_ref.py [--дзеркало ~/гра-lineage]
"""
import os
import shutil
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster3d as m  # noqa: E402
import rasy_kontext as rk  # noqa: E402
import avatar_ref as ar  # noqa: E402

KORIN = Path(__file__).resolve().parents[2]
VYKHID = KORIN / "wiki/img/test/avatar/mpfb"
BAZA = KORIN / "wiki/img/test/avatar/baza2-s222.png"
SIDY = [411, 422]
SPILNE = (
    "plain uniform light grey studio background, soft even shadowless "
    "lighting, the whole body from head to feet in frame with margin, "
    "photorealistic.")
POZA = (
    "standing in a relaxed A-pose: both arms straight and angled down about "
    "45 degrees away from the body, palms facing the thighs, fingers "
    "relaxed and slightly apart, legs straight with feet shoulder-width "
    "apart and flat on the ground")
KROKY = [
    ("pered", BAZA,
     "Change the pose, clothing, hair and view. The same man is now %s, "
     "seen exactly from the front, facing the camera. He wears only tight "
     "dark navy swim trunks, nothing else, barefoot. His head is completely "
     "shaved bald and smooth, his face clean-shaven with no beard and no "
     "moustache. Keep exactly the same face shape, eyes, nose, mouth, ears, "
     "skin tone, muscular build and body proportions. %s" % (POZA, SPILNE)),
    ("volossia", BAZA,
     "Change the pose, clothing and view. The same man is now %s, seen "
     "exactly from the front, facing the camera. He wears only tight black "
     "swim briefs, nothing else, barefoot. Keep exactly the same face, the "
     "same hairstyle and hair colour, the same beard and moustache, the same "
     "skin tone, muscular build and body proportions. %s" % (POZA, SPILNE)),
    ("bik", "pered",
     "Rotate the same man 90 degrees so he is seen exactly from his left "
     "side in strict profile, his face pointing to the left of the frame, "
     "same A-pose with the arm angled down away from the body, same tight "
     "dark navy swim trunks, same shaved head, same clean-shaven face, same "
     "build and proportions. %s" % SPILNE),
    ("zad", "pered",
     "Rotate the same man 180 degrees so he is seen exactly from behind, "
     "showing his back, the back of his shaved head, his buttocks in the "
     "tight black swim briefs and the backs of his legs and heels, same "
     "A-pose with both arms angled down away from the body, same build and "
     "proportions. %s" % SPILNE),
]


# Правки по одній (замовник: «референс вийшов з бородою та не в плавках» —
# Kontext погано тягне кілька змін за раз).
BEZ_BORODY = (
    "Remove his beard and moustache completely: clean-shaven smooth skin on "
    "the chin, jaw, cheeks and upper lip. Keep everything else exactly the "
    "same: same face, same shaved head, same body, same pose, same "
    "clothing, same background, same lighting, same photorealistic style.")
PLAVKY = (
    "Replace his shorts with small tight-fitting black swim briefs that "
    "hug the hips and groin and end at the top of the thighs, so both "
    "thighs are fully bare. Keep everything else exactly the same: same "
    "face, same head, same body, same pose, same background, same lighting, "
    "same photorealistic style.")
PRAVKY = [
    ("pered2", "pered", BEZ_BORODY),
    ("pered3", "pered2", PLAVKY),
    ("bik2", "bik", PLAVKY),
    ("zad2", "zad", PLAVKY),
    ("volossia2", "volossia", PLAVKY),
]


# Друга версія (замовник: «у бази s111 дуже широке тіло, забагато
# м'язів» проти варіанта 1) — від ОДЯГНЕНОЇ T-пози seed 11, по одній зміні
# за крок, із вимогою тієї самої статури.
T_POZA = KORIN / "wiki/img/test/avatar/tpoza-s11.png"
VYKHID2 = KORIN / "wiki/img/test/avatar/mpfb2"
# Заперечень Kontext не розуміє («do NOT make him more muscular» — і далі
# бодібілдер), тож статуру описуємо прямо — словами з прикладу замовника
# (худорлявий плавець у щільних темно-синіх плавках-боксерах).
STATURA = (
    "His body is slim and lean like a young competitive swimmer: thin "
    "toned arms, a narrow chest, narrow shoulders, a flat stomach with only "
    "faint definition, slim thighs and calves, a slender athletic build.")
KROKY2 = [
    ("plavky", T_POZA,
     "Replace all of his clothing (shirt, vest, belt, trousers, boots) with "
     "only tight-fitting dark navy swim trunks in a short boxer-brief cut "
     "ending at the top of the thighs, barefoot. %s Keep exactly "
     "the same face, hair, beard, skin tone, T-pose, front view, plain grey "
     "background, lighting and photorealistic style." % STATURA),
    ("bez-borody", "plavky",
     "Remove his beard and moustache completely: clean-shaven smooth skin on "
     "the chin, jaw, cheeks and upper lip. %s Keep everything else exactly "
     "the same: same face, hair, swim trunks, T-pose, background, lighting." %
     STATURA),
    ("lysyi", "bez-borody",
     "Shave his head completely bald, smooth bare scalp with no hair. %s "
     "Keep everything else exactly the same: same face, clean-shaven, swim "
     "trunks, T-pose, background, lighting." % STATURA),
    ("bik", "lysyi",
     "Rotate the same man 90 degrees so he is seen exactly from his left "
     "side in strict profile, his face pointing to the left of the frame, "
     "both arms still straight out horizontally (one towards the camera "
     "side hidden behind the body), same dark navy swim trunks, same bald head, "
     "same clean-shaven face. %s %s" % (STATURA, SPILNE)),
    ("zad", "lysyi",
     "Rotate the same man 180 degrees so he is seen exactly from behind, "
     "showing his back, the back of his bald head, his buttocks in the "
     "dark navy swim trunks and the backs of his legs and heels, same T-pose "
     "with both arms straight out. %s %s" % (STATURA, SPILNE)),
]


def main():
    global VYKHID
    dzerkalo = Path(sys.argv[sys.argv.index("--дзеркало") + 1]) \
        if "--дзеркало" in sys.argv else None
    VYKHID.mkdir(parents=True, exist_ok=True)
    m.free()
    kroky = PRAVKY if "--правки" in sys.argv else KROKY
    if "--v2" in sys.argv:
        kroky = KROKY2
        VYKHID = VYKHID2
        VYKHID.mkdir(parents=True, exist_ok=True)
    for imia, dzh, promt in kroky:
        if isinstance(dzh, str):
            dzh = VYKHID / ("%s-s%d.png" % (dzh, SIDY[0]))
        rk.PROMT = promt
        image = m.stage(str(dzh))
        for seed in SIDY:
            kudy = VYKHID / ("%s-s%d.png" % (imia, seed))
            if kudy.exists():
                continue
            done = m.run(rk.graf(image, seed, "mpfb_%s_s%d" % (imia, seed)))
            out = done["outputs"]["13"]["images"][-1]
            shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"],
                                     out["filename"]), kudy)
            print("готово", imia, seed, flush=True)
            if dzerkalo:
                d = dzerkalo / "wiki/img/test/avatar" / VYKHID.name
                d.mkdir(parents=True, exist_ok=True)
                shutil.copy(kudy, d)


if __name__ == "__main__":
    main()
