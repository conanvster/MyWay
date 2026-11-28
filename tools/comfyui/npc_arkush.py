#!/usr/bin/env python3
"""Аркуші-референси мешканців міст (NPC) — одразу в одязі свого ремесла (27.11.2026).

Слово замовника: «зроби референси для NPC щоб були одразу в одязі відповідно професії». NPC
у грі — модель людини, стать за іменем (П-162); ремесла — з `data/map*.json → міста → мешканці`:
коваль, крамар/крамарка, священик, вартовий, гільдмайстер, завідувач складу, майстер магії.

Рецепт — як аркуші гуманоїдів (`monstr_arkush.py`, «рівне світло 360°»), лише людина:
  А-0   — Qwen-Edit 2511: перша картинка — людина з кадру раси вікі (`wiki/img/rasy/людина-<стать>
          -vN.png`, N різне в ремесел — різні обличчя), друга — каркас А-0 (лише поза й ракурс);
          одяг ремесла — словами (ODIAH), руки порожні;
  Т-0   — лише текстом від А-0 з перевіркою розмаху рук (як у гуманоїдів);
  решта — від свого 0°, друга картинка — каркас потрібного ракурсу, перевірка «не копія 0°»;
  аркуш — 2 ряди (А, Т) × 4 ракурси, назва, опис одягу.

    ~/Програми/cv-venv/bin/python -u tools/comfyui/npc_arkush.py --список
    ~/Програми/cv-venv/bin/python -u tools/comfyui/npc_arkush.py коваль-чоловік [--лише А-0] [--сід N]
    ~/Програми/cv-venv/bin/python -u tools/comfyui/npc_arkush.py --усі
    ~/Програми/cv-venv/bin/python -u tools/comfyui/npc_arkush.py --зібрати [<npc> …]

Вихід — `art/npc/<ремесло>-<стать>/аркуш/<поза>-<кут>.png`, `аркуш.jpg` (лише диск).
"""
import os
import shutil
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monstr_arkush as ma  # noqa: E402

KORIN = ma.KORIN
ODIAH = {
    "коваль": ("village blacksmith", "a thick brown leather apron from chest to knees over a rough "
               "undyed linen shirt with the sleeves rolled up to the elbows, a wide leather belt with "
               "thick leather work gloves tucked into it, dark brown wool trousers, heavy leather work "
               "boots; forearms bare and strong, a little soot on the apron"),
    "крамар": ("town merchant", "a long dark-green wool kaftan with embroidered collar and cuffs "
               "over a white linen shirt, a wide red woven sash belt with a leather coin purse, dark "
               "trousers tucked into soft brown leather boots, a fur-trimmed cap"),
    "крамарка": ("town merchant woman", "a long white linen dress with red embroidered sleeves, a "
                 "dark-green wool sleeveless bodice laced at the front, a woven red sash belt with a "
                 "leather coin purse, a plain linen apron, a patterned headscarf tied at the nape, "
                 "soft brown leather boots"),
    "священик": ("village priest of an old fantasy faith", "a long plain grey-white wool robe to the "
                 "ankles, a wide deep-blue stole embroidered with silver sun patterns over the "
                 "shoulders, a simple rope belt, a small carved wooden sun pendant on a cord, plain "
                 "leather sandals; no real-world religious symbols, no cross"),
    "вартовий": ("town guard", "a steel chainmail hauberk to mid-thigh over a padded gambeson, a "
                 "blue-and-yellow quartered tabard on top, a wide leather belt, steel vambraces and "
                 "greaves, leather gloves, sturdy boots, an open-faced steel helmet with a nasal "
                 "guard; no weapon, no shield"),
    "гільдмайстер": ("head of the adventurers' guild", "a dark burgundy knee-length coat with brass "
                     "buttons over a fine linen shirt and a black leather waistcoat, a heavy gold chain "
                     "of office with a round guild medallion on the chest, dark trousers, polished "
                     "tall black boots, leather gloves"),
    "завідувач складу": ("warehouse keeper", "a grey canvas work apron with many pockets over a "
                         "brown wool vest and a linen shirt with rolled sleeves, leather sleeve guards "
                         "on the forearms, a ring of big iron keys hanging on the belt, sturdy grey "
                         "trousers, practical leather boots"),
    "майстер магії": ("master of magic", "a long deep-blue robe to the ankles with silver runic "
                      "embroidery on the hems, cuffs and collar, a short layered shoulder cape, the wide "
                      "hood lowered on the back, a belt with small leather pouches, a glowing pale-blue "
                      "crystal amulet on the chest, soft grey leather boots"),
}
# ремесло → (назва в даних, чий одяг, кадр вікі чоловіка, кадр жінки): різні N — різні обличчя
NPC = {
    "коваль": ("коваль", "коваль", 1, 1),
    "крамар": ("крамар", "крамар", 2, 2),
    "священик": ("священик", "священик", 3, 3),
    "вартовий": ("вартовий", "вартовий", 1, 2),
    "гільдмайстер": ("гільдмайстер", "гільдмайстер", 2, 3),
    "завідувач складу": ("завідувач складу", "завідувач складу", 3, 1),
    "майстер магії": ("майстер магії", "майстер магії", 1, 3),
}
STAT = {"чоловік": "man", "жінка": "woman"}
ZRIST = {"чоловік": 1.75, "жінка": 1.68}


def spysok():
    """[(ключ, ремесло, стать)] — 7 ремесел × 2 статі."""
    return [("%s-%s" % (r, s), r, s) for r in NPC for s in STAT]


def odiah(r, s):
    if r == "крамар" and s == "жінка":
        return ODIAH["крамарка"]
    return ODIAH[NPC[r][1]]


def teka(kl):
    return os.path.join(KORIN, "art/npc", kl, "аркуш")


def ref(r, s):
    n = NPC[r][2] if s == "чоловік" else NPC[r][3]
    return os.path.join(KORIN, "wiki/img/rasy", "людина-%s-v%d.png" % (s, n))


def instr(r, s, poza, kut, pershyi):
    rol, od = odiah(r, s)
    if s == "жінка":
        od = od.replace("trousers tucked into", "a long skirt and").replace(" trousers,", " a long skirt,")
    khto = ("the person from the first image" if pershyi else
            "exactly the same person, in exactly the same clothes, as in the first image")
    tekst = ("Show " + khto + " as a clean full-body character turnaround reference for 3D modeling "
             "of a non-player character: a " + STAT[s] + ", a " + rol + " of a medieval fantasy town "
             "in an Eastern European style. ")
    if pershyi:
        tekst += ("Keep the face, hair, skin tone and body build of the person, but REPLACE all of "
                  "their clothing with the working clothes of a " + rol + ": " + od + ". ")
    else:
        tekst += ("Keep the face, hair, skin tone, body build and every piece of clothing exactly the "
                  "same: " + od + ". ")
    tekst += ("Change only the pose, camera and lighting: they stand upright in the same pose as the "
              "grey mannequin in the second image — " + ma.POZA_OPYS[poza] + ", legs straight — seen "
              "from the same camera angle as the second image: " + ma.KUT_OPYS[kut] + "; show the "
              "parts visible from this side. The mannequin is only a pose guide: do not copy its "
              "body, face or shorts. Empty open hands: no tools, no weapon, nothing held. ")
    if kut == 180:
        # 28.11.2026, слово замовника: «деякі NPC із заду мають вигляд такий самий як спереду» —
        # Qwen копіював перед (фартух, кишені, пряжку) на спину
        tekst += ("This is the BACK of the person: nothing that is worn on the front may appear — "
                  "no apron bib, no front pockets or pouches, no buckles, no amulets or pendants, "
                  "no chest emblems; from behind an apron shows only its thin neck strap and the "
                  "waist ties over the plain back of the shirt or dress. Show the back of the head "
                  "and hair, the back of the garments and the heels of the boots. ")
    return tekst + ma.SVITLO


def instr_t0(r, s):
    p = instr(r, s, "Т", 0, False)
    p = p.replace("in the same pose as the grey mannequin in the second image — ", "in ")
    p = p.replace("seen from the same camera angle as the second image: ", "seen from ")
    p = p.replace("The mannequin is only a pose guide: do not copy its body, face or shorts. ", "")
    return ma.T_SYLNO + p


def zheneruvaty(spys, lyshe=None):
    import monster3d as m  # noqa: E402
    import bronia_2var as b2  # noqa: E402
    for kl, r, s in spys:
        t = teka(kl)
        os.makedirs(t, exist_ok=True)
        dzherelo = ref(r, s)
        for poza, kut in ma.PORIADOK:
            nazva = "%s-%d" % (poza, kut)
            if lyshe and nazva not in lyshe:
                continue
            kudy = os.path.join(t, nazva + ".png")
            if os.path.exists(kudy):
                continue
            if (poza, kut) == ("Т", 0):
                a0 = os.path.join(t, "А-0.png")
                najkr = None
                for i in range(ma.SPROB):
                    tm = os.path.join(t, "Т-0-спроба.png")
                    ma.zapustyty(m, b2, a0, None, instr_t0(r, s), tm, ma.SID + i)
                    k = ma.rozmakh(tm) / max(1, ma.rozmakh(a0))
                    if najkr is None or k > najkr:
                        najkr = k
                        shutil.copy(tm, kudy)
                    os.remove(tm)
                    if k >= ma.ROZMAKH_T:
                        break
                    print("  ↻ %s Т-0 s%d розмах ×%.2f" % (kl, ma.SID + i, k), flush=True)
                print("готово", kl, nazva, "(розмах ×%.2f)" % najkr, flush=True)
                continue
            pershyi = (poza, kut) == ("А", 0)
            persha = (dzherelo if pershyi else
                      os.path.join(t, "Т-0.png") if poza == "Т" else os.path.join(t, "А-0.png"))
            druha = os.path.join(ma.KARKAS, "%s-%d.png" % (poza, kut))
            nul = os.path.join(t, "%s-0.png" % poza)
            for i in range(1 if kut == 0 else ma.SPROB):
                ma.zapustyty(m, b2, persha, druha, instr(r, s, poza, kut, pershyi), kudy, ma.SID + i)
                if kut == 0 or not ma.povtor(kudy, nul):
                    break
                print("  ↻ %s %s s%d ≈ свій 0° — не повернуто" % (kl, nazva, ma.SID + i), flush=True)
            print("готово", kl, nazva, flush=True)
        zibraty(kl, r, s)
    m.free()


def zibraty(kl, r, s):
    t = teka(kl)
    kadry = [os.path.join(t, "%s-%d.png" % pk) for pk in ma.KADRY]
    if not all(os.path.exists(k) for k in kadry):
        print("… ще не всі кадри", kl, flush=True)
        return
    C, LIV, HDR = 480, 30, 120
    W = LIV * 2 + 4 * C
    rows = []
    for poza in "АТ":
        for k in (0, 45, 90, 180):
            im = Image.open(os.path.join(t, "%s-%d.png" % (poza, k))).convert("RGB")
            im.thumbnail((C, int(C * 1.5)))
            rows.append(im)
    H = max(im.height for im in rows)
    out = Image.new("RGB", (W, HDR + 2 * (H + 40)), ma.FON)
    d = ImageDraw.Draw(out)
    rol, od = odiah(r, s)
    d.text((LIV, 14), "%s — %s (NPC, зріст %.2f м)" % (r.capitalize(), s, ZRIST[s]),
           font=ma.shryft(34, True), fill=(30, 30, 40))
    d.text((LIV, 62), od[:150] + ("…" if len(od) > 150 else ""), font=ma.shryft(18), fill=(60, 60, 70))
    for i, im in enumerate(rows):
        x = LIV + (i % 4) * C + (C - im.width) // 2
        y = HDR + (i // 4) * (H + 40) + 30
        out.paste(im, (x, y))
        if i % 4 == 0:
            d.text((LIV, y - 28), "А-поза" if i < 4 else "Т-поза", font=ma.shryft(22, True),
                   fill=(30, 30, 40))
    out.save(os.path.join(os.path.dirname(t), "аркуш.jpg"), quality=90)
    print("аркуш", os.path.join(os.path.dirname(t), "аркуш.jpg"), flush=True)


if __name__ == "__main__":
    A = sys.argv[1:]
    sp = spysok()
    if "--список" in A:
        for kl, r, s in sp:
            print(kl, "←", os.path.basename(ref(r, s)))
        sys.exit(0)
    lyshe = None
    if "--лише" in A:
        i = A.index("--лише")
        lyshe = set(A[i + 1].split(","))
        del A[i:i + 2]
    if "--сід" in A:   # перезйомка поганого кадру: інший сід, ніж у першому прогоні
        i = A.index("--сід")
        ma.SID = int(A[i + 1])
        del A[i:i + 2]
    if "--зібрати" in A:
        for kl, r, s in sp:
            if not A[1:] or kl in A:
                zibraty(kl, r, s)
        sys.exit(0)
    vybir = sp if "--усі" in A else [x for x in sp if x[0] in A]
    if not vybir:
        print("нічого не вибрано — див. --список")
        sys.exit(1)
    zheneruvaty(vybir, lyshe)
