#!/usr/bin/env python3
"""Референси збоку й ззаду для аватарів MPFB (02.10.2026).

Слово замовника про модель чоловіка: «я оціюю модель чоловіка на 65-70% ,
можливо через те що ненадали вигляду з боку та з заду і не порівняли
модель залишилась без плавок, та голова зміщена вперед - треба її трохи
вирівняти … підчас збирання моделі зінки врахуй це». Тож для обох — та сама
людина, що на кадрі спереду, у профіль і ззаду (Kontext від кадру
спереду): для підбору фігури й голови за профілем, проєкції текстури на
спину й боки і оцінки з трьох боків.

    python3 -u tools/comfyui/avatar_ref_vydy.py [--чоловік] [--жінка] [--бік2]
"""
import os
import shutil
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster3d as m  # noqa: E402
import rasy_kontext as rk  # noqa: E402

KORIN = Path(__file__).resolve().parents[2]
A = KORIN / "wiki/img/test/avatar"
SPILNE = (
    "Keep exactly the same person, the same face, the same hair, the same "
    "body shape and proportions, the same skin tone; plain uniform light "
    "grey studio background, soft even lighting, the whole body from head "
    "to feet in frame with margin, photorealistic.")
LYUDY = {
    "чоловік": (A / "mpfb2/plavky-sym-s411.png", A / "mpfb2", "",
                "man", "his", "him", "the same dark navy swim shorts, the "
                "same short dark hair and beard"),
    "жінка": (A / "zh-kupalnyk-s622.png", A, "zh-", "woman", "her", "her",
              "the same black two-piece swimsuit, the same long dark hair"),
}
SIDY = (911, 922)
# Профіль у T-позі Kontext малює на три чверті (чоловік s911, s922) або
# руками вперед (жінка) — тому профіль руками вниз уздовж тіла, як модель
# у `mpfb_pidbir.KUT_BIK`.
SIDY_BIK2 = (931, 942, 953, 964)


def promty(khto, yoho, yoho2, odiah):
    bik = (
        "Rotate the same %s 90 degrees so %s is seen exactly from %s left "
        "side in strict profile, %s face pointing to the left of the frame, "
        "standing upright with a straight neck and the head held level "
        "above the shoulders, both arms still straight out horizontally in "
        "the same T-pose (the far arm hidden behind the body), %s. %s"
        % (khto, "he" if khto == "man" else "she", yoho, yoho, odiah, SPILNE))
    zad = (
        "Rotate the same %s 180 degrees so %s is seen exactly from behind: "
        "%s back, the back of %s head and hair, %s from behind, the backs of "
        "%s legs and heels, the same T-pose with both arms straight out "
        "horizontally. %s" % (khto, "he" if khto == "man" else "she", yoho,
                              yoho, odiah, yoho, SPILNE))
    return {"bik": bik, "zad": zad}


def promt_bik2(khto, vin, yoho, odiah):
    return (
        "Rotate the same %s so %s is seen in an exact 90-degree side view "
        "from %s left side, a strict profile: %s face points to the left of "
        "the frame, only one eye, one ear and one shoulder are visible, the "
        "nose is at the left edge of the face, both feet are side by side "
        "and overlap, %s arms hang relaxed straight down along the sides of "
        "%s body with the near arm covering the far one, standing upright "
        "with a straight neck and the head held level above the shoulders, "
        "%s. %s" % (khto, vin, yoho, yoho, yoho, yoho, odiah, SPILNE))


# Жінка: довге розпущене волосся ззаду й збоку закривало спину й плечі, і
# проєкція клала його чорне на лису модель (MPFB-ж1). Волосся — окрема
# перука, тож для спини й профілю — те саме, але з волоссям у тугому
# високому пучку.
PUCHOK = ("Tie her long hair up into a tight high bun on the top of her "
          "head so that her neck, shoulders and whole back are completely "
          "bare and visible. Keep everything else exactly the same: same "
          "woman, same pose, same view, same black two-piece swimsuit, same "
          "body, same background, same lighting, same photorealistic style.")
SIDY_PUCHOK = (971, 982)


def puchok():
    for dzh, imia in (("zh-zad-sym-s911", "zh-zad-puchok"),
                      ("zh-bik2-sym-s931", "zh-bik-puchok")):
        rk.PROMT = PUCHOK
        image = m.stage(str(A / (dzh + ".png")))
        for seed in SIDY_PUCHOK:
            kudy = A / ("%s-s%d.png" % (imia, seed))
            if kudy.exists():
                continue
            done = m.run(rk.graf(image, seed, "avatar_%s_s%d" % (imia, seed)))
            out = done["outputs"]["13"]["images"][-1]
            shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"],
                                     out["filename"]), kudy)
            print("готово", imia, seed, flush=True)


# Статура — з профілю s922 (замовник 02.10.2026: «у жінки статури не схожі
# і дефекти скіна», як приклад — zh-bik-sym-s922: струнка, плаский живіт).
# Профіль у пучку s971 вийшов повнішим, і підбір надув живіт і сідниці.
# Тепер від s922: руки вниз (як модель у профіль) і волосся в пучок, тіло те
# саме.
STRUNKA = ("Lower both of her arms so they hang relaxed straight down along "
           "the sides of her body, the near arm covering the far one, and tie "
           "her long hair up into a tight high bun on the top of her head so "
           "her neck and upper back are bare. Keep exactly the same slim "
           "body, the same flat stomach, the same waist, hips and legs, the "
           "same strict side view facing left, the same black two-piece "
           "swimsuit, the same face, background, lighting and photorealistic "
           "style.")
SIDY_STRUNKA = (1011, 1022, 1033, 1044)


def strunka():
    rk.PROMT = STRUNKA
    image = m.stage(str(A / "zh-bik-sym-s922.png"))
    for seed in SIDY_STRUNKA:
        kudy = A / ("zh-bik-strunka-s%d.png" % seed)
        if kudy.exists():
            continue
        done = m.run(rk.graf(image, seed, "avatar_zh_bik_strunka_s%d" % seed))
        out = done["outputs"]["13"]["images"][-1]
        shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"],
                                 out["filename"]), kudy)
        print("готово strunka", seed, flush=True)


def strunka_puchok():
    """s1022 (струнка, руки вниз) — волосся ще звисає по спині; весь пучок."""
    rk.PROMT = PUCHOK.replace("Tie her long hair", "Gather all of her hair, "
                              "with no strands hanging down her back, and tie it")
    image = m.stage(str(A / "zh-bik-strunka-s1022.png"))
    for seed in (1051, 1062, 1073):
        kudy = A / ("zh-bik-strunka2-s%d.png" % seed)
        if kudy.exists():
            continue
        done = m.run(rk.graf(image, seed, "avatar_zh_bik_strunka2_s%d" % seed))
        out = done["outputs"]["13"]["images"][-1]
        shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"],
                                 out["filename"]), kudy)
        print("готово strunka2", seed, flush=True)


def main():
    if "--струнка2" in sys.argv:
        m.free()
        return strunka_puchok()
    if "--струнка" in sys.argv:
        m.free()
        return strunka()
    if "--пучок" in sys.argv:
        m.free()
        return puchok()
    m.free()
    khto_vsi = [k for k, f in (("чоловік", "--чоловік"), ("жінка", "--жінка"))
                if f in sys.argv] or list(LYUDY)
    for khto in khto_vsi:
        dzh, teka, pref, en, yoho, yoho2, odiah = LYUDY[khto]
        image = m.stage(str(dzh))
        if "--бік2" in sys.argv:
            rk.PROMT = promt_bik2(en, "he" if en == "man" else "she", yoho,
                                  odiah)
            for seed in SIDY_BIK2:
                kudy = teka / ("%sbik2-sym-s%d.png" % (pref, seed))
                if kudy.exists():
                    continue
                done = m.run(rk.graf(image, seed, "avatar_vyd_%sbik2_s%d"
                                     % (pref or "ch-", seed)))
                out = done["outputs"]["13"]["images"][-1]
                shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"],
                                         out["filename"]), kudy)
                print("готово", khto, "профіль", seed, kudy.name, flush=True)
            continue
        for vyd, promt in promty(en, yoho, yoho2, odiah).items():
            rk.PROMT = promt
            for seed in SIDY:
                kudy = teka / ("%s%s-sym-s%d.png" % (pref, vyd, seed))
                if kudy.exists():
                    continue
                done = m.run(rk.graf(image, seed, "avatar_vyd_%s_%s_s%d"
                                     % (pref or "ch-", vyd, seed)))
                out = done["outputs"]["13"]["images"][-1]
                shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"],
                                         out["filename"]), kudy)
                print("готово", khto, vyd, seed, kudy.name, flush=True)


if __name__ == "__main__":
    main()
