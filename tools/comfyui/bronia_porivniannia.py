#!/usr/bin/env python3
"""Однаковий прогін наявних моделей на прикладах броні (13.10.2026).

Слово замовника (броня частинами, план §3б крок 4), показавши 4 приклади:
«можливо треба змінити модель для генерації» → «зроби однаковий прогін з
наведених прикладів для тих моделей що є — виберемо найкращі».

Однаково для всіх: ельфійка e1903 у Т-позі (`el-lysa-e1903.png`), приклад
з `art/references/bronia/`, ті самі сіди.
  * flux — FLUX.1 dev Q4_K_S + ControlNet Union-Pro 2.0 за скелетом e1903
    (`e1903-cn-poza.png`), обличчя під маскою; приклад лише СЛОВАМИ (модель
    картинки-зразка не бере);
  Без плаща (замовник 13.10.2026: «плащ заважає — і я його по-іншому
  уявляю — роби рендери без плаща»).
  * kontext — FLUX.1 Kontext dev Q5_K_S, дві опорні картинки (e1903 і
    приклад, два вузли ReferenceLatent), полотно — кадр e1903.

    ~/Програми/cv-venv/bin/python -u tools/comfyui/bronia_porivniannia.py [номер…]

Вихід — `art/meshy/2026-10-13/броня-порівняння/<приклад>-<модель>-s<сід>.png`
і аркуш на приклад `<приклад>-аркуш.png`.
"""
import os
import shutil
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import monster3d as m  # noqa: E402
import elf_nabory_cn as cn  # noqa: E402

KORIN = Path(__file__).resolve().parents[2]
D = cn.D
KADR = D / "el-lysa-e1903.png"
PRYKLADY = KORIN / "art/references/bronia"
VYHID = KORIN / "art/meshy/2026-10-13/броня-порівняння"
SIDY = (3101, 3102)
cn.SYLA, cn.KINETS = 1.0, 0.9

TILO = ("a tall, slender young bald elf woman with long pointed elf ears, pale "
        "skin, delicate face, standing in a strict T-pose, arms straight out "
        "to the sides at shoulder height, palms down, front view, feet "
        "slightly apart, very long slim legs, narrow hips")
FON = ("No cloak, no cape, nothing hanging behind her back. Plain light grey studio background, soft even lighting, "
       "photorealistic, realistic materials, the whole body from head to feet "
       "in frame.")

OPYSY = {
    "1-кора-лучник": (
        "an open-faced helmet of carved oak bark with small antlers and "
        "leaves, armour of dark oak bark plates wrapped in twisting roots and "
        "vines with patches of green moss and small leaves, shoulder guards "
        "of overlapping bark shingles, a bark breastplate with root knotwork, "
        "a belt of woven roots with a leather pouch, bark vambraces, "
        "fingerless leather gloves, a skirt of bark strips and leaves, bark "
        "greaves over bare knees"),
    "2-рейнджер-шкіра": (
        "a short olive-green wool hood up over her head ending in a small "
        "cowl on the shoulders (no cloak), a dark brown "
        "riveted leather cuirass with an embossed scale pattern, crossed "
        "leather straps with steel buckles, tan linen shirt sleeves, layered "
        "leather shoulder guards, embossed Celtic-knot leather vambraces, "
        "fingerless leather gloves, wide leather belts with buckles, a long "
        "dark brown tunic with leather tassets, dark trousers, brown leather "
        "boots"),
    "3-зелений-ельф": (
        "a grey-green wool hood up over her head and a soft green scarf, a "
        "long green felted tunic embroidered with real green vine leaves and "
        "twisting copper-red branch patterns, a red-brown leather baldric "
        "diagonally across the chest, two red-brown leather belts with "
        "buckles and a tooled leather pouch, green sleeves with copper "
        "vine-wrapped bracers, branch-wrapped leg guards with leaf medallions "
        "on the knees"),
    "4-кора-речі": (
        "an open-faced antlered helmet of carved oak bark with leaves, a "
        "cuirass of oak bark wrapped in roots and green moss, shoulder guards "
        "of layered bark shingles with leaves, bark vambraces, bark-textured "
        "gloves, a brown leather belt with small pouches, tall bark boots "
        "wrapped with cord"),
}

KONTEXT = ("Dress the bald elf woman from the first image in the complete "
           "armour and outfit shown in the second image, copying its "
           "materials, colours, shapes and details exactly, but WITHOUT any "
           "cloak or cape: leave out the cloak entirely. Keep her exact "
           "strict T-pose, body proportions, face, bald head and pointed ears, "
           "front view, the whole body from head to feet. Plain light grey "
           "studio background.")


def graf_kontext(kadr, pryklad, seed, prefix):
    return {
        "1": {"class_type": "UnetLoaderGGUF",
              "inputs": {"unet_name": "flux1-kontext-dev-Q5_K_S.gguf"}},
        "2": {"class_type": "DualCLIPLoader",
              "inputs": {"clip_name1": "clip_l.safetensors",
                         "clip_name2": "t5xxl_fp8_e4m3fn.safetensors", "type": "flux"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": "ae.safetensors"}},
        "4": {"class_type": "LoadImage", "inputs": {"image": kadr}},
        "5": {"class_type": "FluxKontextImageScale", "inputs": {"image": ["4", 0]}},
        "6": {"class_type": "VAEEncode", "inputs": {"pixels": ["5", 0], "vae": ["3", 0]}},
        "14": {"class_type": "LoadImage", "inputs": {"image": pryklad}},
        "15": {"class_type": "FluxKontextImageScale", "inputs": {"image": ["14", 0]}},
        "16": {"class_type": "VAEEncode", "inputs": {"pixels": ["15", 0], "vae": ["3", 0]}},
        "7": {"class_type": "CLIPTextEncode", "inputs": {"text": KONTEXT, "clip": ["2", 0]}},
        "8": {"class_type": "ReferenceLatent",
              "inputs": {"conditioning": ["7", 0], "latent": ["6", 0]}},
        "18": {"class_type": "ReferenceLatent",
               "inputs": {"conditioning": ["8", 0], "latent": ["16", 0]}},
        "9": {"class_type": "FluxGuidance", "inputs": {"conditioning": ["18", 0], "guidance": 2.5}},
        "10": {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["7", 0]}},
        "11": {"class_type": "KSampler",
               "inputs": {"model": ["1", 0], "seed": seed, "steps": 24, "cfg": 1.0,
                          "sampler_name": "euler", "scheduler": "simple",
                          "positive": ["9", 0], "negative": ["10", 0],
                          "latent_image": ["6", 0], "denoise": 1.0}},
        "12": {"class_type": "VAEDecode", "inputs": {"samples": ["11", 0], "vae": ["3", 0]}},
        "13": {"class_type": "SaveImage", "inputs": {"images": ["12", 0], "filename_prefix": prefix}},
    }


def zberehty(done, kudy):
    out = done["outputs"]["13"]["images"][-1]
    shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"], out["filename"]), kudy)
    print("готово", kudy.name, flush=True)


def arkush(nazva):
    s = 512
    kadry = [("приклад", PRYKLADY / (nazva + ".png"))]
    for model in ("flux", "kontext"):
        for seed in SIDY:
            kadry.append(("%s s%d" % (model, seed), VYHID / ("%s-%s-s%d.png" % (nazva, model, seed))))
    o = Image.new("RGB", (s * len(kadry), s + 36), (24, 24, 24))
    d = ImageDraw.Draw(o)
    try:
        sh = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 22)
    except OSError:
        sh = ImageFont.load_default()
    for i, (pidpys, f) in enumerate(kadry):
        if not f.exists():
            continue
        im = Image.open(f).convert("RGB")
        im.thumbnail((s, s))
        o.paste(im, (i * s + (s - im.width) // 2, (s - im.height) // 2))
        d.text((i * s + 10, s + 6), pidpys, fill=(230, 220, 200), font=sh)
    o.save(VYHID / (nazva + "-аркуш.png"))


def main():
    VYHID.mkdir(parents=True, exist_ok=True)
    vybir = [a for a in sys.argv[1:] if a.isdigit()]
    nazvy = [n for n in OPYSY if not vybir or n.split("-")[0] in vybir]
    kadr = m.stage(str(KADR))
    msk = m.stage(str(D / "e1903-cn-maska.png"))
    poz = m.stage(str(D / "e1903-cn-poza.png"))
    # FLUX dev — усі приклади поспіль (модель у пам'яті одна)
    m.free()
    for n in nazvy:
        promt = "Full body photo of " + TILO + ", wearing " + OPYSY[n] + ". " + FON
        for seed in SIDY:
            kudy = VYHID / ("%s-flux-s%d.png" % (n, seed))
            if not kudy.exists():
                zberehty(m.run(cn.graf(kadr, msk, poz, promt, seed, "bronia_flux")), kudy)
    m.free()
    for n in nazvy:
        pr = m.stage(str(PRYKLADY / (n + ".png")))
        for seed in SIDY:
            kudy = VYHID / ("%s-kontext-s%d.png" % (n, seed))
            if not kudy.exists():
                zberehty(m.run(graf_kontext(kadr, pr, seed, "bronia_kontext")), kudy)
        arkush(n)
    m.free()


if __name__ == "__main__":
    main()
