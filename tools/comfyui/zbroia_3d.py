#!/usr/bin/env python3
"""Зброя й щити — 3D-моделі з наших значків (18.10.2026).

Слово замовника: «вигляд зброї з іконки — згенерувати якісні, оздоблені
моделі зброї … зробити, щоб і зброю, і одяг можна було вдягнути». Це
крок 5 плану `spec/план.md` §3б: процедурні фігури `WeaponLook` — на
моделі з наших значків.

    ~/Програми/cv-venv/bin/python -u tools/comfyui/zbroia_3d.py кадр  [назва …]
    ~/Програми/cv-venv/bin/python -u tools/comfyui/zbroia_3d.py сітка [назва …]
    blender -b -P tools/blender/zbroia_zbirka.py -- [назва …]
    ~/Програми/cv-venv/bin/python -u tools/comfyui/zbroia_3d.py аркуш [назва …]

Без назв — усі 49 речей зі слотами «зброя» і «щит» у `data/items.json`. Назва «типи» — сім
реалістичних моделей «тип-<тип>», по одній на тип (20.11.2026, `TYPY_REAL`).

  кадр  — значок 64×64 (є для E…B) вирізається на сіре тло, збільшується до
          1024 і FLUX перемальовує його з шумом `SHUM`: силует і кольори
          значка лишаються, з'являються оздоблення й чіткість. Без значка
          (A, S, SS) — FLUX з тексту. Опис — з типу й матеріалу (`TYPY`,
          `MATERIALY`). → art/zbroia/<назва>/kadr.png
  сітка — Pixal3D з кадру (вирізаного на сіре) → art/zbroia/<назва>/pixal3d.glb
  аркуш — значок | кадр | рендер моделі з гри поруч для огляду.

Кадри й сирі сітки — лише на диску (`art/` не в git); у гру йде лише
зібране `game/models/own/zbroia/<назва>.glb` (Blender-крок).
ComfyUI має працювати, LM Studio — вивантажено (`monster3d.py` про це).
"""
import json
import os
import shutil
import sys
from pathlib import Path

from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster3d as m  # noqa: E402
import rasy_realizm as rr  # noqa: E402

KORIN = Path(rr.KORIN)
ZNACHKY = KORIN / "game/assets/icons/items"
VYHID = KORIN / "art/zbroia"
SEED = 7301
SHUM = 0.72
FON = (128, 128, 128)

TYPY = {
    "меч": "a single ornate fantasy longsword, straight double-edged blade, "
           "decorated crossguard, wrapped grip and pommel",
    "кинджал": "a single ornate fantasy dagger, short double-edged blade, "
               "small decorated crossguard and pommel",
    "сокира": "a single ornate fantasy battle axe, one broad crescent axe "
              "head on a long haft",
    "спис": "a single ornate fantasy spear, long leaf-shaped spearhead on a "
            "long shaft",
    "лук": "a single ornate fantasy recurve longbow with a taut bowstring",
    "посох": "a single ornate fantasy mage staff, long carved shaft topped "
             "with a set gemstone",
    "щит": "a single ornate fantasy round shield seen from the front, raised "
           "central boss and decorated rim",
}
# Один реалістичний вигляд на тип (20.11.2026, слово замовника: «для кожного типу зброї … більш
# реалістичний вигляд, для початку один вигляд для усих типів»): назви «тип-<тип>», без значка,
# FLUX з тексту; у грі — `models/own/zbroia/тип-<тип>.glb` для всіх речей цього типу.
TYPY_REAL = {
    "меч": "a single realistic medieval arming sword, straight double-edged steel blade with a "
           "shallow fuller, simple steel cross guard, grip wrapped in dark brown leather, round "
           "steel pommel",
    "кинджал": "a single realistic medieval dagger, short double-edged steel blade, small simple "
               "steel cross guard, wooden grip wrapped in leather, round pommel",
    "сокира": "a single realistic medieval battle axe, one forged steel axe head with a curved "
              "cutting edge on a straight ash wood haft, leather grip at the lower end",
    "спис": "a single realistic medieval spear, leaf-shaped forged steel spearhead with a socket "
            "on a long straight ash wood shaft, small iron butt cap",
    "лук": "a single realistic medieval wooden longbow, one piece of yew wood with a leather "
           "wrapped grip in the middle and a taut linen bowstring",
    "посох": "a single realistic wooden quarterstaff walking staff, long straight gnarled oak "
             "shaft with iron bands at both ends and a leather wrapped grip",
    "щит": "a single realistic medieval round wooden shield seen from the front, planks covered "
           "with painted leather, iron rim and central iron boss",
}
OPYS_REAL = ("Product photo of %s. Historically accurate, plain and functional, worn but well "
             "kept, no ornament, no gems, no glow, no magic. The whole object fully visible, "
             "centered and straight, nothing cropped, isolated on a plain uniform light grey "
             "studio background, soft even lighting, no shadow, sharp focus, photorealistic. "
             "Only one object, no hands, no text.")
# Матеріал — за першим словом назви (кора дуба, залізо, сталь …).
MATERIALY = [
    ("кори дуба", "made of hardened dark oak wood and bark, bronze rivets and "
                  "leather bindings, rustic"),
    ("залізн", "forged dark iron with hammered texture, leather grip"),
    ("ясенов", "made of pale ash wood with iron fittings and leather wraps"),
    ("сталев", "polished steel with fine engraved runes and silver trim"),
    ("тисов", "made of dark reddish yew wood with steel fittings and "
              "engraved runes"),
    ("кістян", "carved from pale bone and horn, faint glowing blue runes"),
    ("обсидіан", "made of black volcanic obsidian with glowing orange "
                 "cracks and gold trim"),
    ("кристалі", "made of translucent icy blue crystal with silver "
                 "filigree, softly glowing"),
    ("зорян", "made of dark blue star metal with inlaid gold star "
              "constellations, softly glowing"),
]
OPYS = ("Product photo of %s, %s. The whole object fully visible and "
        "centered, nothing cropped, isolated on a plain uniform light grey "
        "studio background, soft even lighting, no shadow, sharp focus, "
        "highly detailed realistic game asset, intricate ornament. Only one "
        "object, no hands, no text.")


def rechi():
    d = json.load(open(KORIN / "game/data/items.json", encoding="utf-8"))
    out = {}

    def walk(o):
        if isinstance(o, dict):
            for k, v in o.items():
                if isinstance(v, dict) and v.get("слот") in ("зброя", "щит"):
                    out[k] = v
                else:
                    walk(v)
    walk(d)
    return out


def promt(nazva, rich):
    if nazva.startswith("тип-"):
        return OPYS_REAL % TYPY_REAL[rich["тип"]]
    mat = next((t for k, t in MATERIALY if k in nazva), "")
    return OPYS % (TYPY[rich["тип"]], mat)


def na_sire(dzherelo, kudy, rozmir=1024):
    """Річ на рівному сірому тлі (маска birefnet), збільшена до `rozmir`."""
    maska = kudy.with_name(kudy.stem + "-maska.png")
    m.cutout(str(dzherelo), str(maska))
    im = Image.open(dzherelo).convert("RGB")
    mk = Image.open(maska).convert("L").resize(im.size)
    tlo = Image.new("RGB", im.size, FON)
    im = Image.composite(im, tlo, mk.filter(ImageFilter.GaussianBlur(0.8)))
    if max(im.size) != rozmir:
        im = im.resize((rozmir, rozmir), Image.LANCZOS)
    im.save(kudy)
    maska.unlink()


def kadr(nazva, rich):
    teka = VYHID / nazva
    teka.mkdir(parents=True, exist_ok=True)
    gotovo = teka / "kadr.png"
    if gotovo.exists():
        return
    znachok = ZNACHKY / (nazva + ".png")
    if znachok.exists():
        vhid = teka / "znachok-sire.png"
        na_sire(znachok, vhid)
        graf = rr.graf_flux(m.stage(str(vhid)), promt(nazva, rich), SEED,
                            True, 3.0, SHUM, 0.3, 0.3)
    else:
        vhid = teka / "porozhnio.png"
        Image.new("RGB", (1024, 1024), FON).save(vhid)
        # Контури порожнього кадру — нуль ліній; сила 0, щоб ControlNet
        # не тягнув до порожнечі.
        graf = rr.graf_flux(m.stage(str(vhid)), promt(nazva, rich), SEED,
                            False, 3.5, syla=0.0, kinets=0.0)
    done = m.run(graf)
    out = done["outputs"]["13"]["images"][-1]
    syre = teka / "kadr-syryi.png"
    shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"],
                             out["filename"]), syre)
    na_sire(syre, gotovo)
    print("кадр", nazva, flush=True)


def sitka(nazva):
    teka = VYHID / nazva
    gotovo = teka / "pixal3d.glb"
    if gotovo.exists() or not (teka / "kadr.png").exists():
        return
    imia = "zbroia-%s" % nazva.replace(" ", "-")
    m.mesh(str(teka / "kadr.png"), imia, 60000)
    shutil.move(str(KORIN / "art/monsters" / (imia + "-3d") / "pixal3d.glb"),
                gotovo)
    shutil.rmtree(KORIN / "art/monsters" / (imia + "-3d"), ignore_errors=True)
    print("сітка", nazva, flush=True)


def arkush(nazvy):
    s = 300
    o = Image.new("RGB", (s * 3, s * len(nazvy)), (24, 24, 24))
    for r, n in enumerate(nazvy):
        for i, f in enumerate([ZNACHKY / (n + ".png"),
                               VYHID / n / "kadr.png",
                               VYHID / n / "rendr.png"]):
            if f.exists():
                im = Image.open(f).convert("RGB")
                im = im.resize((s, s), Image.NEAREST if im.width < 100
                               else Image.LANCZOS)
                o.paste(im, (i * s, r * s))
    o.save(VYHID / "аркуш.png")
    print("аркуш", VYHID / "аркуш.png", flush=True)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    krok, nazvy = sys.argv[1], sys.argv[2:]
    vsi = rechi()
    vsi.update({"тип-" + t: {"тип": t} for t in TYPY_REAL})
    if nazvy == ["типи"]:
        nazvy = ["тип-" + t for t in TYPY_REAL]
    nazvy = nazvy or list(vsi)
    VYHID.mkdir(parents=True, exist_ok=True)
    if krok == "кадр":
        m.free()
        for n in nazvy:
            kadr(n, vsi[n])
        m.free()
    elif krok == "сітка":
        for n in nazvy:
            sitka(n)
    elif krok == "аркуш":
        arkush(nazvy)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
