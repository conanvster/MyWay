#!/usr/bin/env python3
"""Текстури для дерев Tree3D (план §3в): гілочки з листям і кора.

Слово замовника 12.10.2026: «використай для дерев asset 3141» — це
Tree3D, процедурні дерева в самій грі. Текстури двох родів:

- демо пакета (слово замовника 17.10.2026: «візьми демо текстури») —
  гілочки `twig.png`, `Branches1–3.png` і кора `bark.jpg` просто з
  архіву пакета, без змін, лише перейменовані;
- наші, CC0 (клен, дуб, берест):

- гілочки — з кластерів `tools/derevo_lystia.py` (листя ambientCG,
  П-253): кожен атлас 2×2 → одна картка, де три кластери розходяться
  віялом із лівого нижнього кута. Так лежить і гілочка в демо Tree3D:
  картка кріпиться до гілки лівим нижнім кутом, а в UV це u=0, v=1;
- кора — Poly Haven, як і в Blender-дерев (`tools/dereva_test.py`),
  зменшена до 512 px: дерево на екрані дрібне, а текстур стоїть кілька.

    python3 tools/tree3d_hilochky.py

Вихід — `game/models/nature/tree3d/`. Після нових PNG обов'язково
`godot --headless --import`, інакше гра їх не бачить.
"""
import io
import random
import zipfile
from pathlib import Path

from PIL import Image

KORIN = Path(__file__).resolve().parents[1]
ASETY = Path.home() / "асети/дерева"
VYHID = KORIN / "game/models/nature/tree3d"
ARHIV = KORIN / "art/asset-library/tree3d-3141/gdTree3D-17b98cf.zip"
## Файл демо пакета → назва в грі.
DEMO = {
    "twig.png": "lystia_demo.png",
    "Branches1.png": "lystia_demo1.png",
    "Branches2.png": "lystia_demo2.png",
    "Branches3.png": "lystia_demo3.png",
    "bark.jpg": "kora_demo.jpg",
    "bark_normal.png": "kora_demo_n.jpg",
}

KARTKA = 1024
## Набір листя → назва в грі. Лише листяні: ялину Tree3D відкинуто
## (стос куль, 16 тис. трикутників — план §3в), хвоя світу 2 — фото.
HILOCHKY = {
    "LeafSet010": "lystia_klen",
    "LeafSet005": "lystia_dub",
    "LeafSet023": "lystia_berest",
}
KORA = {
    "jolcham_oak_bark_01": "kora_dub",
    "bark_brown_01": "kora_brunatna",
}


def kartka(atlas, rng):
    """Три кластери віялом з лівого нижнього кута картки."""
    pol = KARTKA // 2
    klastery = [atlas.crop((x, y, x + pol * 2, y + pol * 2))
                for y in (0, pol * 2) for x in (0, pol * 2)
                if atlas.width >= pol * 4]
    out = Image.new("RGBA", (KARTKA, KARTKA), (0, 0, 0, 0))
    # Кути від осі x угору; 90° — кластер стоїть, як намальований.
    for kut in (68, 45, 22):
        k = rng.choice(klastery)
        dovzhyna = int(KARTKA * rng.uniform(0.92, 1.05))
        k = k.resize((dovzhyna, dovzhyna), Image.LANCZOS)
        # Стебло кластера — посередині нижнього краю. Обертаємо навколо
        # нього: полотно вдвічі більше, стебло в центрі.
        polotno = Image.new("RGBA", (dovzhyna * 2, dovzhyna * 2))
        polotno.alpha_composite(k, (dovzhyna // 2, 0))
        polotno = polotno.rotate(kut - 90 + rng.uniform(-5, 5),
                                 resample=Image.BICUBIC)
        # Центр полотна — у лівий нижній кут картки, трохи всередину.
        x = int(KARTKA * 0.04) - dovzhyna
        y = int(KARTKA * 0.96) - dovzhyna
        sloi = Image.new("RGBA", (KARTKA, KARTKA))
        sloi.paste(polotno, (x, y), polotno)
        out = Image.alpha_composite(out, sloi)
    return out


def main():
    VYHID.mkdir(parents=True, exist_ok=True)
    rng = random.Random(3141)
    for nabir, imia in HILOCHKY.items():
        atlas = Image.open(ASETY / "klastery" / (nabir + ".png")) \
            .convert("RGBA")
        kartka(atlas, rng).save(VYHID / (imia + ".png"), optimize=True)
        print("гілочка", imia, "←", nabir)
    for dzherelo, imia in KORA.items():
        for chastyna, sufiks in (("diff", ""), ("nor_gl", "_n")):
            src = ASETY / "polyhaven" / ("%s_%s_1k.jpg" % (dzherelo,
                                                         chastyna))
            Image.open(src).convert("RGB").resize((512, 512), Image.LANCZOS) \
                .save(VYHID / (imia + sufiks + ".jpg"), quality=88)
        print("кора", imia, "←", dzherelo)
    with zipfile.ZipFile(ARHIV) as arhiv:
        for nazva in arhiv.namelist():
            fail = nazva.rsplit("/", 1)[-1]
            if "/demo/" in nazva and fail in DEMO:
                kartynka = Image.open(io.BytesIO(arhiv.read(nazva)))
                ciel = VYHID / DEMO[fail]
                if ciel.suffix == ".jpg":
                    kartynka.convert("RGB").save(ciel, quality=90)
                else:
                    kartynka.save(ciel, optimize=True)
                print("демо", ciel.name, "←", fail)


if __name__ == "__main__":
    main()
