#!/usr/bin/env python3
"""Броня на орчисі s1303 — по 2 варіанти кожної речі з її значка (П4, план §3д).

Слово замовника 18.10.2026: «зроби по 2 варіанти кожної моделі з прикладами,
що на іконці, виберу найкращі». 06.11.2026: одяг — ЧАСТИНАМИ (П-277), тож
кожна річ — окремий кадр: орчиха в ОДНІЙ цій речі, решта тіла без змін (з
кадру потім вирізається сама річ на 3D).

Основа — глиняна орчиха `ork2-lysa-s1303-hlyna-c1701.png`: з неї зібрано
3D-аватар у грі, тож річ ляже на ту саму геометрію.

  А · Qwen-Image-Edit 2509 Q4_K_M + Lightning 8 кроків: дві картинки —
      основа й значок («вдягни на неї річ з другої картинки»). Модель бачить
      значок як зразок, а не лише слова (чого не вміли FLUX і Kontext, 13.10).
  Б · FLUX.1 dev + Redux: значок — зразок стилю (`StyleModelApply`), основа —
      i2i лише під маскою зони речі (`ZONY`), опис словами той самий.

    ~/Програми/cv-venv/bin/python -u tools/comfyui/bronia_2var.py перевірити
    ~/Програми/cv-venv/bin/python -u tools/comfyui/bronia_2var.py кадр  [назва …]
    ~/Програми/cv-venv/bin/python -u tools/comfyui/bronia_2var.py аркуш [грейд …]

Без назв — усі 48 речей броні E…B зі значками. Димовий — 2–3 назви:
    … кадр "шолом з кори дуба" "вовча куртка" "сталеві рукавиці"

  перевірити — без GPU і без ComfyUI: файли моделей на місці, кожен вузол
               графів є в коді ComfyUI, усі посилання між вузлами цілі,
               маски зон будуються; друкує план і час.
  кадр       — А і Б на кожну річ → art/bronia/<назва>/{A,B}-s<сід>.png
  аркуш      — значок | А | Б рядками → art/bronia/аркуш-<грейд>.png

ComfyUI має працювати (`--listen 127.0.0.1 --port 8188`), відеокарта вільна
(LM Studio і стенд кодингу — вивантажено; `monster3d.py`). Кадри — лише на
диску (`art/` не в git).
"""
import json
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

KORIN = Path(__file__).resolve().parents[2]
COMFY = Path(os.path.expanduser("~/ComfyUI"))
OSNOVA = KORIN / "wiki/img/test/avatar/ork2-lysa-s1303-hlyna-c1701.png"
ZNACHKY = KORIN / "game/assets/icons/items"
VYHID = KORIN / "art/bronia"
SID = 4401
FON = (128, 128, 128)

# Зони речей на кадрі основи 1024×1024 (розмічено накладкою 06.11.2026:
# шолом з вухами й шиєю, торс із плечима до середини стегна, передпліччя з
# кистями, гомілки зі стопами; мантія — від плечей до п'ят).
ZONY = {
    "голова": [(395, 40, 640, 235)],
    "тіло": [(285, 195, 740, 620)],
    "мантія": [(285, 195, 740, 1000)],
    "рукавиці": [(15, 215, 290, 330), (735, 215, 1010, 330)],
    "взуття": [(330, 800, 700, 1015)],
}

# Річ за слотом і типом броні (П-223: важка, легка, магічна).
RICH = {
    ("голова", "важка"): "a closed-face battle helmet",
    ("голова", "легка"): "a fitted hood covering the head and neck",
    ("голова", "магічна"): "a thin ornate circlet worn on the forehead",
    ("тіло", "важка"): "a heavy breastplate cuirass with shoulder guards",
    ("тіло", "легка"): "a fitted jerkin jacket with short sleeves",
    ("тіло", "магічна"): "a long sleeveless mage robe reaching the ankles",
    ("рукавиці", "важка"): "a pair of heavy armoured gauntlets on both "
                            "hands and forearms",
    ("рукавиці", "легка"): "a pair of fitted gloves on both hands",
    ("рукавиці", "магічна"): "a pair of embroidered bracers on both forearms",
    ("взуття", "важка"): "a pair of heavy armoured boots with greaves up to "
                         "the knees",
    ("взуття", "легка"): "a pair of soft ankle boots",
    ("взуття", "магічна"): "a pair of light strapped sandals",
}
# Матеріал — за словом у назві (як `zbroia_3d.MATERIALY`).
MATERIAL = [
    ("кори дуба", "made of hardened dark oak bark with bronze rivets and "
                  "leather straps, rustic"),
    ("шкури", "made of rough brown hide and fur, leather lacing"),
    ("полотна", "made of plain undyed linen canvas with simple stitching"),
    ("залізн", "made of forged dark iron with hammered texture and rivets"),
    ("вовч", "made of grey wolf fur and dark leather"),
    ("лян", "made of fine bleached linen with blue embroidered trim"),
    ("сталев", "made of polished steel with engraved runes and silver trim"),
    ("ведмеж", "made of thick brown bear fur and heavy leather"),
    ("шовк", "made of shimmering deep red silk with gold embroidery"),
    ("кістян", "made of carved pale bone plates and horn, leather bindings"),
    ("змії", "made of green snake scales and dark leather"),
    ("місяч", "made of silver-blue moon-woven cloth with crescent moon "
              "embroidery, softly glowing"),
]

QWEN_PROMPT = (
    "Dress the bald woman from picture 1 in %s, exactly like the item shown "
    "in picture 2: copy its shape, colours, materials and details, %s. Add "
    "ONLY this one item. Keep everything else in picture 1 exactly the same: "
    "the strict T-pose, body proportions, grey clay skin, bald head, face, "
    "ears, the dark underwear, the grey studio background and framing. "
    "Realistic materials, the whole body from head to feet in frame.")
FLUX_PROMPT = (
    "Full body front view photo of a muscular bald orc woman with grey clay "
    "skin in a strict T-pose, wearing %s, %s, realistic materials, sharp "
    "detail, plain grey studio background.")


# ─── речі ────────────────────────────────────────────────────────────

def rechi():
    d = json.load(open(KORIN / "game/data/items.json", encoding="utf-8"))
    out = {}

    def walk(o):
        if isinstance(o, dict):
            for k, v in o.items():
                if isinstance(v, dict) and v.get("слот") in (
                        "голова", "тіло", "рукавиці", "взуття"):
                    if (ZNACHKY / (k + ".png")).exists():
                        out[k] = v
                else:
                    walk(v)
    walk(d["бази"])
    return out


def opys(nazva, rich):
    shcho = RICH[(rich["слот"], rich["тип"])]
    mat = next((t for k, t in MATERIAL if k in nazva), "")
    return shcho, mat


def zona(rich):
    if rich["слот"] == "тіло" and rich["тип"] == "магічна":
        return "мантія"
    return rich["слот"]


def maska(rich, kudy):
    """Біле — де малювати; краї розмиті, щоб шов не читався."""
    m = Image.new("L", (1024, 1024), 0)
    d = ImageDraw.Draw(m)
    for b in ZONY[zona(rich)]:
        d.rectangle(b, fill=255)
    m.filter(ImageFilter.GaussianBlur(10)).save(kudy)


def znachok_1024(nazva, kudy):
    """Значок 64×64 на сіре тло, 1024 без розмиття піксель-арту."""
    im = Image.open(ZNACHKY / (nazva + ".png")).convert("RGBA")
    tlo = Image.new("RGBA", im.size, FON + (255,))
    tlo.alpha_composite(im)
    tlo.convert("RGB").resize((1024, 1024), Image.NEAREST).save(kudy)


# ─── графи ComfyUI ───────────────────────────────────────────────────

def graf_qwen(osnova, znachok, promt, seed, prefix):
    return {
        "1": {"class_type": "UnetLoaderGGUF",
              "inputs": {"unet_name": "Qwen-Image-Edit-2509-Q4_K_M.gguf"}},
        "2": {"class_type": "LoraLoaderModelOnly",
              "inputs": {"model": ["1", 0], "strength_model": 1.0,
                         "lora_name": "Qwen-Image-Edit-2509-Lightning-"
                                      "8steps-V1.0-bf16.safetensors"}},
        "3": {"class_type": "ModelSamplingAuraFlow",
              "inputs": {"model": ["2", 0], "shift": 3.0}},
        "4": {"class_type": "CLIPLoader",
              "inputs": {"clip_name": "qwen_2.5_vl_7b_fp8_scaled.safetensors",
                         "type": "qwen_image"}},
        "5": {"class_type": "VAELoader",
              "inputs": {"vae_name": "qwen_image_vae.safetensors"}},
        "6": {"class_type": "LoadImage", "inputs": {"image": osnova}},
        "7": {"class_type": "ImageScaleToTotalPixels",
              "inputs": {"image": ["6", 0], "upscale_method": "lanczos",
                         "megapixels": 1.0}},
        "8": {"class_type": "LoadImage", "inputs": {"image": znachok}},
        "9": {"class_type": "TextEncodeQwenImageEditPlus",
              "inputs": {"clip": ["4", 0], "prompt": promt, "vae": ["5", 0],
                         "image1": ["7", 0], "image2": ["8", 0]}},
        "10": {"class_type": "TextEncodeQwenImageEditPlus",
               "inputs": {"clip": ["4", 0], "prompt": "", "vae": ["5", 0],
                          "image1": ["7", 0], "image2": ["8", 0]}},
        "11": {"class_type": "VAEEncode",
               "inputs": {"pixels": ["7", 0], "vae": ["5", 0]}},
        "12": {"class_type": "KSampler",
               "inputs": {"model": ["3", 0], "seed": seed, "steps": 8,
                          "cfg": 1.0, "sampler_name": "euler",
                          "scheduler": "simple", "positive": ["9", 0],
                          "negative": ["10", 0], "latent_image": ["11", 0],
                          "denoise": 1.0}},
        "13": {"class_type": "VAEDecode",
               "inputs": {"samples": ["12", 0], "vae": ["5", 0]}},
        "14": {"class_type": "SaveImage",
               "inputs": {"images": ["13", 0], "filename_prefix": prefix}},
    }


def graf_redux(osnova, maska_png, znachok, promt, seed, prefix,
               syla=0.35, shum=0.85):
    """FLUX i2i лише під маскою; значок — зразок через Redux.

    `syla` Redux мала навмисно: на 1,0 Redux перемальовує весь кадр у
    значок (піксель-арт), а треба лише матеріал і колір."""
    return {
        "1": {"class_type": "UnetLoaderGGUF",
              "inputs": {"unet_name": "flux1-dev-Q4_K_S.gguf"}},
        "2": {"class_type": "DualCLIPLoader",
              "inputs": {"clip_name1": "clip_l.safetensors",
                         "clip_name2": "t5xxl_fp8_e4m3fn.safetensors",
                         "type": "flux"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": "ae.safetensors"}},
        "4": {"class_type": "LoadImage", "inputs": {"image": osnova}},
        "5": {"class_type": "VAEEncode",
              "inputs": {"pixels": ["4", 0], "vae": ["3", 0]}},
        "6": {"class_type": "LoadImageMask",
              "inputs": {"image": maska_png, "channel": "red"}},
        "7": {"class_type": "SetLatentNoiseMask",
              "inputs": {"samples": ["5", 0], "mask": ["6", 0]}},
        "8": {"class_type": "CLIPTextEncode",
              "inputs": {"text": promt, "clip": ["2", 0]}},
        "9": {"class_type": "StyleModelLoader",
              "inputs": {"style_model_name": "flux1-redux-dev.safetensors"}},
        "10": {"class_type": "CLIPVisionLoader",
               "inputs": {"clip_name": "sigclip_vision_patch14_384.safetensors"}},
        "11": {"class_type": "LoadImage", "inputs": {"image": znachok}},
        "12": {"class_type": "CLIPVisionEncode",
               "inputs": {"clip_vision": ["10", 0], "image": ["11", 0],
                          "crop": "center"}},
        "13": {"class_type": "StyleModelApply",
               "inputs": {"conditioning": ["8", 0], "style_model": ["9", 0],
                          "clip_vision_output": ["12", 0], "strength": syla,
                          "strength_type": "multiply"}},
        "14": {"class_type": "FluxGuidance",
               "inputs": {"conditioning": ["13", 0], "guidance": 3.0}},
        "15": {"class_type": "ConditioningZeroOut",
               "inputs": {"conditioning": ["8", 0]}},
        "16": {"class_type": "KSampler",
               "inputs": {"model": ["1", 0], "seed": seed, "steps": 24,
                          "cfg": 1.0, "sampler_name": "euler",
                          "scheduler": "simple", "positive": ["14", 0],
                          "negative": ["15", 0], "latent_image": ["7", 0],
                          "denoise": shum}},
        "17": {"class_type": "VAEDecode",
               "inputs": {"samples": ["16", 0], "vae": ["3", 0]}},
        "18": {"class_type": "SaveImage",
               "inputs": {"images": ["17", 0], "filename_prefix": prefix}},
    }


# ─── перевірка без GPU ───────────────────────────────────────────────

def vuzly_comfy():
    """Імена всіх вузлів, оголошених у коді ComfyUI (без запуску)."""
    imena = set()
    for teka in [COMFY / "nodes.py", COMFY / "comfy_extras",
                 COMFY / "custom_nodes"]:
        faily = [teka] if teka.is_file() else teka.rglob("*.py")
        for f in faily:
            try:
                t = f.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            imena.update(re.findall(r"^class (\w+)\b", t, re.M))
            imena.update(re.findall(r'"(\w+)"\s*:\s*\w+', t))
            imena.update(re.findall(r'node_id="(\w+)"', t))
    return imena


def znaity_model(nazva):
    """Файл моделі в будь-якій теці `models/` (controlnet,
    geometry_estimation, background_removal… — у кожного вузла своя)."""
    return any(True for _ in (COMFY / "models").rglob(nazva))


def perevirka(graf, imena):
    bidy = []
    for nid, v in graf.items():
        if v["class_type"] not in imena:
            bidy.append("вузла %s немає в ComfyUI" % v["class_type"])
        for k, x in v["inputs"].items():
            if isinstance(x, list) and len(x) == 2 and x[0] not in graf:
                bidy.append("%s.%s посилається на відсутній %s"
                            % (nid, k, x[0]))
            if (isinstance(x, str) and x.endswith((".gguf", ".safetensors"))
                    and not znaity_model(x)):
                bidy.append("немає файла моделі %s" % x)
    return bidy


def perevirity():
    imena = vuzly_comfy()
    vsi = rechi()
    print("речей броні зі значками: %d" % len(vsi))
    bidy = []
    for nazva, rich in list(vsi.items())[:1]:
        shcho, mat = opys(nazva, rich)
        bidy += perevirka(graf_qwen("a.png", "b.png",
                                    QWEN_PROMPT % (shcho, mat), SID, "t"),
                          imena)
        bidy += perevirka(graf_redux("a.png", "m.png", "b.png",
                                     FLUX_PROMPT % (shcho, mat), SID, "t"),
                          imena)
    for nazva, rich in vsi.items():
        if (rich["слот"], rich["тип"]) not in RICH:
            bidy.append("немає опису для %s/%s (%s)"
                        % (rich["слот"], rich["тип"], nazva))
        if not any(k in nazva for k, _ in MATERIAL):
            bidy.append("немає матеріалу для «%s»" % nazva)
    if not OSNOVA.exists():
        bidy.append("немає основи %s" % OSNOVA)
    tmp = Path(tempfile.gettempdir())
    for z in ZONY:
        maska({"слот": "тіло" if z == "мантія" else z,
               "тип": "магічна" if z == "мантія" else "легка"},
              tmp / "bronia-maska-test.png")
    for b in sorted(set(bidy)):
        print("  ‼", b)
    # Час: Qwen Lightning 8 кроків ≈ 25–40 с, FLUX 24 кроки ≈ 60 с на
    # 1024² (RTX 5060 Ti; FLUX заміряно на наборах ельфійки 12.10).
    print("план: %d речей × (А + Б) = %d кадрів, ≈ %.0f хв GPU "
          "(+ завантаження моделей ~2 хв на зміну)"
          % (len(vsi), len(vsi) * 2, len(vsi) * (35 + 60) / 60.0))
    print("перевірка: %s" % ("гаразд" if not bidy else "%d вад" % len(set(bidy))))
    return 0 if not bidy else 1


# ─── запуск ──────────────────────────────────────────────────────────

def zberehty(m, done, vuzol, kudy):
    out = done["outputs"][vuzol]["images"][-1]
    shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"],
                             out["filename"]), kudy)
    print("готово", kudy.parent.name, kudy.name, flush=True)


def kadry(nazvy):
    import monster3d as m  # лише тут: модуль стукає в ComfyUI
    vsi = rechi()
    vybir = {n: vsi[n] for n in (nazvy or vsi) if n in vsi}
    for n in nazvy:
        if n not in vsi:
            print("‼ немає речі броні зі значком: %s" % n)
    osnova = m.stage(str(OSNOVA))
    # Спершу всі А (Qwen у пам'яті один раз), тоді всі Б (FLUX).
    m.free()
    for nazva, rich in vybir.items():
        teka = VYHID / nazva
        teka.mkdir(parents=True, exist_ok=True)
        z = teka / "znachok-1024.png"
        if not z.exists():
            znachok_1024(nazva, z)
        kudy = teka / ("A-s%d.png" % SID)
        if kudy.exists():
            continue
        shcho, mat = opys(nazva, rich)
        zberehty(m, m.run(graf_qwen(osnova, m.stage(str(z)),
                                    QWEN_PROMPT % (shcho, mat), SID,
                                    "bronia_A")), "14", kudy)
    m.free()
    for nazva, rich in vybir.items():
        teka = VYHID / nazva
        kudy = teka / ("B-s%d.png" % SID)
        if kudy.exists():
            continue
        mk = teka / "maska.png"
        maska(rich, mk)
        shcho, mat = opys(nazva, rich)
        zberehty(m, m.run(graf_redux(osnova, m.stage(str(mk)),
                                     m.stage(str(teka / "znachok-1024.png")),
                                     FLUX_PROMPT % (shcho, mat), SID,
                                     "bronia_B")), "18", kudy)
    m.free()


def arkush(hreidy):
    vsi = rechi()
    s = 320
    try:
        sh = ImageFont.truetype(
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 18)
    except OSError:
        sh = ImageFont.load_default()
    for g in hreidy or ["E", "D", "C", "B"]:
        nazvy = [n for n, r in vsi.items() if r.get("грейд") == g]
        nazvy = [n for n in nazvy if (VYHID / n).exists()]
        if not nazvy:
            continue
        o = Image.new("RGB", (s * 3, (s + 30) * len(nazvy)), (24, 24, 24))
        d = ImageDraw.Draw(o)
        for r, n in enumerate(nazvy):
            y = r * (s + 30)
            kadry_ = [ZNACHKY / (n + ".png"), VYHID / n / ("A-s%d.png" % SID),
                      VYHID / n / ("B-s%d.png" % SID)]
            for c, f in enumerate(kadry_):
                if not f.exists():
                    continue
                im = Image.open(f).convert("RGB")
                im = im.resize((s, s), Image.NEAREST if c == 0
                               else Image.LANCZOS)
                o.paste(im, (c * s, y))
            d.text((8, y + s + 4), "%s   |   А: Qwen-Edit   |   Б: FLUX+Redux"
                   % n, fill=(230, 220, 200), font=sh)
        kudy = VYHID / ("аркуш-%s.png" % g)
        o.save(kudy)
        print("аркуш", kudy)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    dia, rest = sys.argv[1], sys.argv[2:]
    if dia == "перевірити":
        return perevirity()
    VYHID.mkdir(parents=True, exist_ok=True)
    if dia == "кадр":
        kadry(rest)
    elif dia == "аркуш":
        arkush(rest)
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
