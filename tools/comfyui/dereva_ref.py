#!/usr/bin/env python3
"""Референси дерев-велетів: зовні й кожен поверх (план `spec/дерева-референси.md`).

Слово замовника 13.11.2026: «так, генеруй референси дерев, необов'язково вигляд саме
баобаб» + вісім фото (баобаби, секвоя «Генерал Шерман», стара сосна, ялівець). Тож три
дерева — три породи: пузатий баобаб (3 поверхи), сивий ялівець (6), секвоя (10).

Зовні — FLUX.1 dev поверх фото замовника (i2i: тримається силует), поверхи — FLUX текстом
поверх «тунелю з коріння» (тримає настрій, не форму).

    ~/Програми/cv-venv/bin/python -u tools/comfyui/dereva_ref.py [--дерево 1|2|3]
        [--лише зовні|поверхи] [--поверх N] [--сіди 1 2] [--шум-зовні 0.7] [--шум-поверх 1.0]

Кадри → art/дерева-референси-2026-11-13/<дерево>/. Готові кадри не перемальовуються.
ComfyUI має працювати (див. `monster3d.py`).
"""
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster3d as m  # noqa: E402

FOTO = os.path.expanduser("~/Зображення")
KUDY = os.path.join(m.ROOT, "art", "дерева-референси-2026-11-13")
NUTRO = "istockphoto-2206722685-612x612.jpg"

STYL_ZOVNI = ("National Geographic nature photography, photorealistic, sharp real bark "
              "texture, natural daylight, no text, no signs, no fences, no masonry.")
STYL = ("Dark fantasy RPG environment concept art, photorealistic, cinematic natural "
        "lighting, high detail, no text, no signs, no fences.")

DEREVA = [
    {
        "тека": "1-пузатий-баобаб", "фото": "images.jpeg", "розмір": (896, 1152),
        "зовні": (
            "A real photograph taken with a DSLR camera of an enormous ancient bottle-shaped "
            "baobab tree, a huge swollen smooth ochre trunk with real rough bark, short thick "
            "branches and a flat green crown on top. At the very bottom of the trunk a small "
            "dark natural cavity in the bark, an irregular rotten hollow only slightly taller "
            "than a man, black inside, a few small dark natural knot-holes higher up the "
            "trunk, a narrow trampled dirt path leads to the cavity. One very small distant "
            "person stands beside the black cavity, not hiding it, the trunk is fifty times "
            "wider than the person. Green savanna meadow, blue sky with clouds, sunny day."),
        "нутро": (
            "Inside a colossal hollow baobab tree, a vast round chamber of living wood fifty "
            "metres across, walls of pale ochre spongy fibrous wood with moss and lichen, "
            "thick roots running across the floor, soft warm daylight through oval hollow "
            "openings in the trunk wall, a tiny human figure for scale."),
        "поверхи": [
            "Ground floor: soft moss carpet, ferns, big arching roots forming gateways, bright "
            "daylight pouring in from the arched entrance doorway, a rough wooden ladder "
            "leaning up to a hole in the wooden ceiling.",
            "Second floor: shelves of giant bracket fungi growing up the walls like steps, "
            "thick cobwebs between them, warm dusty sunbeams from oval hollows, a stair of "
            "fungus shelves leading up.",
            "Top floor: the open neck of the hollow trunk, open sky straight overhead, thick "
            "branches and green leaves hanging down inside, birds, bright light from above.",
        ],
    },
    {
        "тека": "2-сивий-ялівець", "фото": "мафус.jpeg", "розмір": (1344, 768),
        "зовні": (
            "A colossal ancient juniper tree one hundred and fifty metres wide at the base, "
            "several enormous twisted trunks fused together, silver-grey and honey-gold "
            "weathered spiralling deadwood, dead bleached spikes at the top, patches of dark "
            "green foliage. At ground level a natural tall hollow doorway between the fused "
            "trunks, a few dark oval hollows higher up, a worn path over the rock leads to the "
            "doorway. A tiny human traveller stands by the doorway, dwarfed by the tree, for "
            "scale. Bare granite mountain plateau with boulders, a small ordinary pine far "
            "away, dramatic clouds."),
        "нутро": (
            "Inside a colossal hollow ancient juniper tree, a vast round chamber of old wood "
            "a hundred metres across, walls of twisted spiralling silver-grey and honey-gold "
            "weathered dry wood, gnarled roots across the floor, cold pale daylight through "
            "narrow cracks and oval hollows in the trunk wall, a tiny human figure for scale."),
        "поверхи": [
            "Ground floor: dry grey dust and stones, bare grey roots, almost no green, light "
            "from the tall entrance crack, a spiral ramp of root climbing the wall.",
            "Second floor: roots and wood fibres twisted together into huge spiral columns "
            "from floor to ceiling, like a pillared hall.",
            "Third floor: long curtains of grey-green beard lichen and shredded bark strips "
            "hanging from the ceiling, green shadows, a hanging rope ladder.",
            "Fourth floor: flooded floor with shallow still pools reflecting the walls, "
            "clusters of pale softly glowing mushrooms, dim light.",
            "Fifth floor: huge old abandoned nests of sticks, scattered bones and skulls of "
            "animals, drifts of dry needles, dusty light.",
            "Top floor: open to the sky, bare dead bleached branches and spikes overhead, "
            "cold windy light, clouds rushing past, snow dust on the wood.",
        ],
    },
    {
        "тека": "3-праматір-секвоя", "фото": "234279-700-0.webp", "розмір": (896, 1120),
        "зовні": (
            "A real photograph taken with a DSLR camera of the base of an enormous giant "
            "sequoia tree in a conifer forest, an immense column of deep red-brown furrowed "
            "fibrous bark with huge flared buttress roots, the trunk continues out of frame "
            "above. At the very bottom, between two buttress roots, a small black charred "
            "fire-scar cavity, an irregular natural hollow only slightly taller than a man, "
            "black inside, a few small dark knot-holes higher up the trunk, a narrow trampled "
            "forest path leads to the cavity. One very small distant person stands next to "
            "the cavity, the trunk is a hundred times wider than the person. The whole base "
            "of the trunk is in plain view, no trees in front of it. Wild untouched "
            "old-growth forest, bare forest floor with needles and ferns, no benches, no "
            "pavement, no vehicles, ordinary tall firs look small next to it, soft light."),
        "нутро": (
            "Inside a colossal hollow giant sequoia tree, a vast round cathedral-like chamber "
            "of living wood two hundred metres across, walls of deep red-brown fibrous "
            "furrowed wood with black charred fire scars, massive roots across the floor, "
            "shafts of daylight through tall fire-scar openings in the trunk wall, a tiny "
            "human figure for scale."),
        "поверхи": [
            "Ground floor: several fused trunks inside form separate halls between huge "
            "fluted wooden buttresses, charred black walls, light from the tall entrance, a "
            "broad stair cut into a root.",
            "Second floor: a dense jungle growing inside the hollow, ferns taller than a man, "
            "a small stream running between mossy roots, mist.",
            "Third floor: the floor is broken by deep black chasms, several long natural "
            "bridges made of giant roots span the chasms, a tiny figure walks across a root "
            "bridge, dizzying depth below.",
            "Fourth floor: countless glowing mushrooms on walls and floor, blue-green "
            "twilight, no daylight.",
            "Fifth floor: walls flowing with golden resin, huge amber drips and stalactites "
            "with giant insects frozen inside, warm amber glow.",
            "Sixth floor: dozens of huge pale silk cocoons, torn open and empty, hang from "
            "the ceiling on threads, thick white spider webs stretched everywhere between "
            "the roots and the walls, gloomy grey light.",
            "Seventh floor: the trunk wall is cracked open, long vertical fissures showing "
            "bright sky and clouds outside, strong light blades across the floor.",
            "Eighth floor: carpet of blood-red moss, withered dried flowers, dead vines, "
            "uneasy red-tinted gloom.",
            "Ninth floor: a ring of tall totem poles built of giant bones, skulls and antlers "
            "stands in the middle of the hall, crude carvings on the wood walls, cold fire "
            "pits, a faintly glowing stone portal arch.",
            "Top floor: open broken top of the trunk, huge sequoia branches with green "
            "needles spreading overhead, sunlight through the crown, clouds below the rim.",
        ],
    },
]


def arg(k, typ, d):
    return typ(sys.argv[sys.argv.index(k) + 1]) if k in sys.argv else d


def graf(foto, promt, seed, shum, rozmir):
    return {
        "1": {"class_type": "UnetLoaderGGUF", "inputs": {"unet_name": "flux1-dev-Q4_K_S.gguf"}},
        "2": {"class_type": "DualCLIPLoader",
              "inputs": {"clip_name1": "clip_l.safetensors",
                         "clip_name2": "t5xxl_fp8_e4m3fn.safetensors", "type": "flux"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": "ae.safetensors"}},
        "4": {"class_type": "LoadImage", "inputs": {"image": foto}},
        "5": {"class_type": "ImageScale",
              "inputs": {"image": ["4", 0], "upscale_method": "lanczos",
                         "width": rozmir[0], "height": rozmir[1], "crop": "center"}},
        "6": {"class_type": "VAEEncode", "inputs": {"pixels": ["5", 0], "vae": ["3", 0]}},
        "8": {"class_type": "CLIPTextEncode", "inputs": {"text": promt, "clip": ["2", 0]}},
        "9": {"class_type": "FluxGuidance", "inputs": {"conditioning": ["8", 0], "guidance": 3.5}},
        "10": {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["8", 0]}},
        "11": {"class_type": "KSampler",
               "inputs": {"model": ["1", 0], "seed": seed, "steps": 28, "cfg": 1.0,
                          "sampler_name": "euler", "scheduler": "simple",
                          "positive": ["9", 0], "negative": ["10", 0],
                          "latent_image": ["6", 0], "denoise": shum}},
        "12": {"class_type": "VAEDecode", "inputs": {"samples": ["11", 0], "vae": ["3", 0]}},
        "13": {"class_type": "SaveImage", "inputs": {"images": ["12", 0],
                                                     "filename_prefix": "dereva_ref"}},
    }


def kadr(foto, promt, seed, shum, rozmir, kudy):
    if os.path.exists(kudy):
        print("є", kudy, flush=True)
        return
    done = m.run(graf(foto, promt, seed, shum, rozmir))
    out = done["outputs"]["13"]["images"][-1]
    shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"], out["filename"]), kudy)
    print("готово", kudy, flush=True)


def main():
    lyshe = arg("--лише", str, "")
    odne = arg("--дерево", int, 0)
    odyn_poverh = arg("--поверх", int, 0)
    sidy = [1, 2]
    if "--сіди" in sys.argv:
        sidy = []
        for s in sys.argv[sys.argv.index("--сіди") + 1:]:
            if s.startswith("--"):
                break
            sidy.append(int(s))
    shum_z = arg("--шум-зовні", float, 0.7)
    shum_p = arg("--шум-поверх", float, 1.0)
    nutro = m.stage(os.path.join(FOTO, NUTRO))
    for n, d in enumerate(DEREVA, 1):
        if odne and odne != n:
            continue
        teka = os.path.join(KUDY, d["тека"])
        os.makedirs(teka, exist_ok=True)
        if lyshe != "поверхи":
            foto = m.stage(os.path.join(FOTO, d["фото"]))
            for s in sidy:
                kadr(foto, d["зовні"] + " " + STYL_ZOVNI, 1000 * n + s, shum_z, d["розмір"],
                     os.path.join(teka, "зовні-в%d.png" % s))
        if lyshe != "зовні":
            for p, opys in enumerate(d["поверхи"], 1):
                if odyn_poverh and odyn_poverh != p:
                    continue
                for s in sidy:
                    kadr(nutro, opys + " " + d["нутро"] + " " + STYL,
                         1000 * n + 10 * p + s, shum_p, (1344, 768),
                         os.path.join(teka, "поверх-%02d-в%d.png" % (p, s)))


if __name__ == "__main__":
    main()
