#!/usr/bin/env python3
"""Текстури й речі для міст і сіл версії 2 — як на мапі (CC0).

Слово замовника 17.10.2026: «пошукай гарні текстури для будинків,
парканів та іншого щоб зібрати міста та села як це зображено на мапі».
На мапі (map-gen, набір v5 seed410): місто — мур неправильної форми з
баштами по кутах і брамами, дві вулиці навхрест, ряди дахів, донжон у
центрі, довкола поля; село — жменя дахів уздовж стежки.

Джерела — лише CC0: Poly Haven (текстури й речі, api.polyhaven.com) і
ambientCG. Будинки — модулі Quaternius Medieval Village MegaKit (CC0,
повний набір на диску, `~/assets/medieval-village`); їм ці текстури —
заміна мультяшних.

    python3 tools/mista_aseti.py          качає те, чого ще нема
    python3 tools/mista_aseti.py --аркуш  ще й аркуш прев'ю
    python3 tools/mista_aseti.py --у-гру  ще й копія в `game/models/town/`

Вихід — `~/асети/місто/` (лише диск, у git не йде). У гру потрібне
копіюється окремо, 1k.
"""
import io
import json
import sys
import urllib.request
import zipfile
from pathlib import Path

KUDY = Path.home() / "асети/місто"
ROZMIR = "1k"

## Текстура Poly Haven → для чого. Порядок — як на аркуші.
TEKSTURY = {
    # мур, башти, брами
    "castle_wall_varriation": "мур міста — бутовий камінь",
    "castle_wall_slates": "мур у горах — сланцевий камінь",
    "castle_brick_07": "башти й брами — тесаний камінь",
    "medieval_blocks_03": "донжон — великі блоки",
    # стіни будинків
    "clay_plaster": "мазанка сільської хати",
    "plastered_wall_02": "біла штукатурка міського дому",
    "worn_mossy_plasterwall": "стара штукатурка, бідні квартали",
    "medieval_red_brick": "цегла — багаті доми, кузня",
    # дерево
    "weathered_planks": "сараї, паркани, тин",
    "dark_wooden_planks": "балки фахверку, двері, віконниці",
    "brown_planks_05": "підлоги, помости, ринкові ятки",
    # дахи
    "thatch_roof_angled": "солом'яна стріха — села",
    "reed_roof_04": "очеретяна стріха — села біля води",
    "clay_roof_tiles_02": "черепиця — міста",
    "roof_slates_03": "сланцевий дах — гори й північ",
    # вулиці
    "cobblestone_floor_08": "бруківка вулиць міста",
    "stone_pathway_02": "площа біля донжону",
}
## ambientCG — запас до тих самих ролей, інший вигляд.
AMBIENTCG = {
    "ThatchedRoof001A": "солом'яна стріха, світліша",
    "RoofingTiles014A": "черепиця, рівніша",
}
## Речі Poly Haven (glTF): двори, ринок, брама.
RECHI = {
    "large_iron_gate": "ковані ворота (садові — для двору, не брама)",
    "wine_barrel_01": "бочка",
    "wooden_crate_01": "ящик",
    "wooden_crate_02": "ящик",
    "wooden_bucket_01": "відро біля криниці",
    "wooden_picnic_table": "стіл корчми надворі",
    "wooden_stool_01": "ослін",
    "stone_fire_pit": "вогнище",
    "wooden_lantern_01": "ліхтар",
    "wooden_ladder": "драбина",
    "spinning_wheel_01": "прядка",
}


def get(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "MyWay-tools"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def polyhaven_tekstura(imia: str) -> None:
    ciel = KUDY / "polyhaven" / imia
    if (ciel / f"{imia}_diff_{ROZMIR}.jpg").exists():
        return
    ciel.mkdir(parents=True, exist_ok=True)
    fajly = json.loads(get(f"https://api.polyhaven.com/files/{imia}"))
    for chastyna, sufiks in (("Diffuse", "diff"), ("nor_gl", "nor_gl"),
                             ("arm", "arm")):
        url = fajly[chastyna][ROZMIR]["jpg"]["url"]
        (ciel / f"{imia}_{sufiks}_{ROZMIR}.jpg").write_bytes(get(url))
    print("текстура", imia)


def polyhaven_rich(imia: str) -> None:
    ciel = KUDY / "rechi" / imia
    if (ciel / f"{imia}_{ROZMIR}.gltf").exists():
        return
    fajly = json.loads(get(f"https://api.polyhaven.com/files/{imia}"))
    gltf = fajly["gltf"][ROZMIR]["gltf"]
    ciel.mkdir(parents=True, exist_ok=True)
    (ciel / f"{imia}_{ROZMIR}.gltf").write_bytes(get(gltf["url"]))
    for shliakh, dani in gltf["include"].items():
        fajl = ciel / shliakh
        fajl.parent.mkdir(parents=True, exist_ok=True)
        fajl.write_bytes(get(dani["url"]))
    print("річ", imia)


def ambientcg(imia: str) -> None:
    ciel = KUDY / "ambientcg" / imia
    if ciel.exists():
        return
    ciel.mkdir(parents=True)
    arhiv = get(f"https://ambientcg.com/get?file={imia}_1K-JPG.zip")
    with zipfile.ZipFile(io.BytesIO(arhiv)) as z:
        for nazva in z.namelist():
            if any(s in nazva for s in ("_Color", "_NormalGL", "_Roughness",
                                        "_AmbientOcclusion")):
                (ciel / Path(nazva).name).write_bytes(z.read(nazva))
    print("ambientCG", imia)


def arkush() -> None:
    """Аркуш кульок-прев'ю з підписами — вибирати очима."""
    from PIL import Image, ImageDraw, ImageFont
    shryft = ImageFont.truetype(
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 12)
    vsi = [("ph", i, r) for i, r in TEKSTURY.items()] \
        + [("ac", i, r) for i, r in AMBIENTCG.items()] \
        + [("rich", i, r) for i, r in RECHI.items()]
    stovp, bik = 8, 220
    riadkiv = (len(vsi) + stovp - 1) // stovp
    out = Image.new("RGB", (stovp * bik, riadkiv * (bik + 34)), "white")
    pero = ImageDraw.Draw(out)
    for n, (dzherelo, imia, rol) in enumerate(vsi):
        if dzherelo == "ac":
            url = ("https://acg-media.struffelproductions.com/file/"
                   f"ambientCG-Web/media/thumbnail/256-PNG/{imia}.png")
        else:
            url = (f"https://cdn.polyhaven.com/asset_img/thumbs/{imia}.png"
                   "?height=256&width=256")
        kartka = Image.open(io.BytesIO(get(url))).convert("RGB") \
            .resize((bik, bik))
        x, y = n % stovp * bik, n // stovp * (bik + 34)
        out.paste(kartka, (x, y))
        pero.text((x + 3, y + bik + 2), imia[:34], fill="black", font=shryft)
        pero.text((x + 3, y + bik + 17), rol[:34], fill="#555555",
                  font=shryft)
    out.save(KUDY / "аркуш.png")
    print("аркуш", KUDY / "аркуш.png")


def u_hru() -> None:
    """Копія в гру: текстури (diff, nor_gl, arm) і речі, 1k."""
    import shutil
    gra = Path(__file__).resolve().parents[1] / "game/models/town"
    gra.mkdir(parents=True, exist_ok=True)
    for imia in TEKSTURY:
        for sufiks in ("diff", "nor_gl", "arm"):
            shutil.copy(KUDY / "polyhaven" / imia
                        / f"{imia}_{sufiks}_{ROZMIR}.jpg",
                        gra / f"{imia}_{sufiks}.jpg")
    for imia in RECHI:
        shutil.copytree(KUDY / "rechi" / imia, gra / "rechi" / imia,
                        dirs_exist_ok=True)
    print("у гру:", gra)


def main() -> None:
    KUDY.mkdir(parents=True, exist_ok=True)
    for imia in TEKSTURY:
        polyhaven_tekstura(imia)
    for imia in AMBIENTCG:
        ambientcg(imia)
    for imia in RECHI:
        polyhaven_rich(imia)
    (KUDY / "ЛІЦЕНЗІЯ.txt").write_text(
        "Усе тут — CC0: Poly Haven (polyhaven.com/license) і ambientCG "
        "(ambientcg.com/license). Завантажено tools/mista_aseti.py.\n")
    if "--аркуш" in sys.argv:
        arkush()
    if "--у-гру" in sys.argv:
        u_hru()


if __name__ == "__main__":
    main()
