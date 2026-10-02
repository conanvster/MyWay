#!/usr/bin/env python3
"""Жінка: три ракурси в T-позі з однаковою зачіскою (02.10.2026).

Слово замовника: «при рендеренгу моделі з боку , з переду, із заду
полусили різні перуки та різні пози, необхідно щов у сих ракурсах було Т.
у 3D моделі збільши груди. Вирівняй вивоту в усіх проекціях щоб вони
збігалися за вимотою 3D моделі, висота поясу, грудей, плечей, голови».

Ланцюжок: перед s622 → той самий перед із волоссям у тугому високому пучку
(одна «перука» на всі ракурси) → від нього профіль і спина, обидва в
T-позі. Висоти вирівнює `tools/avatar_ref_vysoty.py`.

    python3 -u tools/comfyui/avatar_ref_tpoza.py --перед | --бік | --зад
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
SPILNE = ("Keep exactly the same woman, the same face, the same tight high "
          "bun, the same slim body shape and proportions, the same black "
          "two-piece swimsuit; plain uniform light grey studio background, "
          "soft even lighting, the whole body from head to feet in frame "
          "with margin, photorealistic.")
KROKY = {
    "--перед": ("zh-kupalnyk-s622.png", "zh-t-pered", (1111, 1122, 1133),
                "Tie her long hair up into a tight high bun on the top of her "
                "head so that her neck and shoulders are completely bare, no "
                "strands hanging down. Keep everything else exactly the same: "
                "same woman, same strict T-pose with both arms straight out "
                "horizontally, same front view, same black two-piece swimsuit, "
                "same body, same background, same lighting, same "
                "photorealistic style."),
    "--бік": ("zh-t-pered-vybir.png", "zh-t-bik", (1211, 1222, 1233, 1244,
                                                   1255, 1266),
              "Rotate the same woman 90 degrees to an exact side view: she is "
              "seen from her left side in strict profile, her face points to "
              "the left of the frame, only one eye and one ear are visible. "
              "She keeps the same T-pose: both arms are raised straight out "
              "to the sides at shoulder height, so in this side view the near "
              "arm points straight at the camera and looks very short and "
              "foreshortened at her shoulder, the far arm is hidden behind "
              "her body; her arms do NOT point forward. " + SPILNE),
    "--зад": ("zh-t-pered-vybir.png", "zh-t-zad", (1311, 1322),
              "Rotate the same woman 180 degrees so she is seen exactly from "
              "behind: her bare back, the back of her head with the same "
              "tight high bun, the black swimsuit from behind, the backs of "
              "her legs and heels, the same T-pose with both arms straight "
              "out horizontally to the sides. " + SPILNE),
    # Замовник: «вигляд із спини не повний - без ніг, і розвернутими
    # долонями назад - це не правильно» — у T-позі долоні дивляться вперед,
    # тож ззаду видно тильний бік кистей; уся постать із запасом.
    "--зад2": ("zh-t-pered-vybir.png", "zh-t-zad2", (1411, 1422, 1433, 1444),
               "Rotate the same woman 180 degrees so she is seen exactly from "
               "behind: her bare back, the back of her head with the same "
               "tight high bun, the black swimsuit from behind, the backs of "
               "her legs, her heels and the soles of her bare feet standing "
               "flat on the floor. The same strict T-pose with both arms "
               "straight out horizontally to the sides; her palms face "
               "forward, away from the camera, so from behind we see the "
               "backs of her hands and her knuckles, fingers together. The "
               "entire figure from the top of the bun to the floor under her "
               "feet is in frame with empty space above and below. " + SPILNE),
    # Замовник 02.10.2026: «згенероване волосся заважає - пропоную генерувати
    # жінку або без волосся або з дуже коротким волоссям». Від того самого
    # переду s622 (статура й обличчя, які замовник прийняв).
    "--лиса": ("zh-kupalnyk-s622.png", "zh-lysa", (1611, 1622, 1633),
               "Shave her head completely bald: a smooth bare scalp with no "
               "hair at all, bare ears and bare neck. Keep everything else "
               "exactly the same: same woman, same face, same eyebrows, same "
               "strict T-pose with both arms straight out horizontally, same "
               "front view, same black two-piece swimsuit, same body, same "
               "plain light grey background, same lighting, same "
               "photorealistic style."),
    "--коротке": ("zh-kupalnyk-s622.png", "zh-korotke", (1711, 1722, 1733),
                  "Cut her hair into a very short buzz cut, only a few "
                  "millimetres long, close to the scalp, so the shape of her "
                  "head, her ears and her bare neck are fully visible. Keep "
                  "everything else exactly the same: same woman, same face, "
                  "same strict T-pose with both arms straight out "
                  "horizontally, same front view, same black two-piece "
                  "swimsuit, same body, same plain light grey background, "
                  "same lighting, same photorealistic style."),
    # Остання спроба (замовник: «ще раз спробувати згенерувати правильні
    # рендери в позинії Т для вигляду боку (перевір щоб було точно збоку
    # руки в положенні Т) Вигляд із заду без волосся»). Від лисого переду.
    "--лиса-бік1": ("zh-lysa-vybir.png", "zh-lysa-bik1",
                    (1811, 1822, 1833, 1844, 1855, 1866),
                    "Change only the camera position: the camera orbits 90 "
                    "degrees around her to her left side, so we now see her "
                    "from the left side in an exact profile, her face points "
                    "to the left of the frame. She does not move at all: she "
                    "keeps exactly the same T-pose with both arms straight "
                    "out to the sides at shoulder height, so from this side "
                    "view her left arm points straight toward the camera, "
                    "strongly foreshortened, and her right arm points "
                    "straight away from the camera, hidden behind her body. "
                    "Keep the same bald head, the same black two-piece "
                    "swimsuit, the same body, plain light grey background, "
                    "the whole body from head to feet in frame, "
                    "photorealistic."),
    "--лиса-бік2": ("zh-lysa-vybir.png", "zh-lysa-bik2",
                    (1911, 1922, 1933, 1944, 1955, 1966),
                    "Show the same bald woman in a strict side profile view "
                    "facing left, standing upright in a T-pose. In this "
                    "exact side view her arms are extended horizontally to "
                    "her sides, perpendicular to the picture, so at shoulder "
                    "height only her near shoulder, the round foreshortened "
                    "near arm and the hand pointing at the viewer are "
                    "visible; nothing hangs down along her body and nothing "
                    "points forward or backward. Same black two-piece "
                    "swimsuit, same body, plain light grey background, the "
                    "whole body from head to feet in frame, photorealistic."),
    "--лиса-зад": ("zh-lysa-vybir.png", "zh-lysa-zad", (2011, 2022, 2033),
                   "Rotate the same woman 180 degrees so she is seen exactly "
                   "from behind: the back of her smooth bald head, her bare "
                   "back, the black swimsuit from behind, the backs of her "
                   "legs, her heels on the floor. The same strict T-pose "
                   "with both arms straight out horizontally to the sides at "
                   "the same height as in the front view, her palms facing "
                   "forward away from the camera. The entire figure from the "
                   "top of the head to the floor is in frame with margin. "
                   + SPILNE.replace("the same tight high bun, ", "")),
    # Замовник: «спина трохи нерівна - спробуй зробити вигляд із заду
    # заново». Рівна спина: стоїть прямо, хребет вертикальний, плечі на
    # одному рівні.
    "--лиса-зад2": ("zh-lysa-vybir.png", "zh-lysa-zad2",
                    (2111, 2122, 2133, 2144),
                    "Rotate the same woman 180 degrees so she is seen exactly "
                    "from behind, perfectly symmetrical: she stands straight "
                    "and upright, her spine is vertical, her shoulders and "
                    "hips are level, her weight is evenly on both feet, the "
                    "back of her smooth bald head, her smooth bare back, the "
                    "black swimsuit from behind with straight shoulder "
                    "straps, the backs of her legs and her heels on the "
                    "floor. The same strict T-pose with both arms straight "
                    "out horizontally to the sides at shoulder height. The "
                    "entire figure from the top of the head to the floor is "
                    "in frame with margin. "
                    + SPILNE.replace("the same tight high bun, ", "")),
}


def main():
    m.free()
    for kl, (dzh, imia, sidy, promt) in KROKY.items():
        if kl not in sys.argv:
            continue
        rk.PROMT = promt
        image = m.stage(str(A / dzh))
        for seed in sidy:
            kudy = A / ("%s-s%d.png" % (imia, seed))
            if kudy.exists():
                continue
            done = m.run(rk.graf(image, seed, "avatar_%s_s%d" % (imia, seed)))
            out = done["outputs"]["13"]["images"][-1]
            shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"],
                                     out["filename"]), kudy)
            print("готово", imia, seed, flush=True)


if __name__ == "__main__":
    main()
