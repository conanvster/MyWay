#!/usr/bin/env python3
"""Орк з нуля, крок 1: аркуш референсів із кадру вікі (spec/орк-з-нуля.md, 11.11.2026).

Qwen-Image-Edit 2511 (Lightning 8 кроків): той самий орк лисий, без бороди, у плавках —
тіло спереду в Т-позі й окремо голова великим планом.

    ~/Програми/cv-venv/bin/python -u tools/comfyui/ork_znulia_ref.py <тіло|голова|своє> <вхід.png> \
        <вихід-префікс> [сід ...] [--інстр "…"] [--мп 1.0]
→ <префікс>-s<сід>.png
"""
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster3d as m  # noqa: E402
import bronia_2var as b2  # noqa: E402

INSTR = {
    "тіло": (
        "Turn this orc into a clean base body reference for 3D modeling. Strict symmetric "
        "T-pose, front view, arms straight out to the sides at shoulder height, palms down, "
        "fingers spread apart, legs straight and slightly apart. Remove all armor, fur, cloak, "
        "pauldron, bracers, belt, pouches, necklace, trousers and boots: bare muscular body, "
        "barefoot, wearing only plain tight black boxer briefs. Shave his head completely bald, "
        "remove the beard and all braids, clean-shaven jaw. Keep his face, lower tusks, pointed "
        "ears, olive green skin, belly and massive heavy build exactly the same. Plain light "
        "grey studio background, soft even shadowless light, whole body from head to feet in "
        "frame, photorealistic."),
    "голова": (
        "Close-up head and neck reference of this same orc for 3D modeling, strict front view, "
        "head upright and level, looking straight at the camera, mouth closed with the two "
        "lower tusks over the upper lip. Shave his head completely bald, remove the beard, "
        "moustache and all braids: clean-shaven jaw and chin, bare neck and bare shoulders, no "
        "armor, no fur, no necklace. Keep his face, heavy wrinkled brow, eyes, nose, tusks, "
        "pointed ears and olive green skin exactly the same, with sharp skin pores and "
        "wrinkles. Plain light grey studio background, soft even shadowless frontal light, "
        "the whole head with both ears and the neck in frame, photorealistic, sharp focus."),
    # орчиха (12.11.2026, слово замовника: «зроби так само орчиху»); волосся — окремими сітками,
    # тож скульпт лисий; білизна — як у чоловіка, плюс проста смуга на грудях
    "тіло-ж": (
        "Turn this orc woman into a clean base body reference for 3D modeling. Keep the strict "
        "symmetric T-pose, front view, arms straight out to the sides at shoulder height, palms "
        "down, fingers spread apart, legs straight and slightly apart. Remove the bracers, belts, "
        "pouches, loincloth and boots: bare athletic muscular body, barefoot, wearing only plain "
        "tight black briefs and a plain tight black bandeau top. Shave her head completely bald, "
        "remove all hair. Keep her face, pointed ears, olive green skin, muscular arms, abs and "
        "strong build exactly the same. Plain light grey studio background without any grid, "
        "soft even shadowless light, whole body from head to feet in frame, photorealistic."),
    "голова-ж": (
        "Close-up head and neck reference of this same orc woman for 3D modeling, strict front "
        "view, head upright and level, looking straight at the camera, mouth closed. Shave her "
        "head completely bald, remove all hair: bare scalp, bare neck and bare shoulders, no "
        "clothes, no jewelry. Keep her face, stern brow, eyes, nose, lips, pointed ears and olive "
        "green skin exactly the same, with sharp skin pores and fine wrinkles. Plain light grey "
        "studio background, soft even shadowless frontal light, the whole head with both ears "
        "and the neck in frame, photorealistic, sharp focus."),
    # ще два обличчя орчихи для вибору аватара (12.11.2026, «більш суворіші», кадри вікі v3 і v1)
    "голова-ж-сувора": (
        "Close-up head and neck reference of this same orc woman for 3D modeling, strict front "
        "view, head upright and level, looking straight at the camera, mouth closed, harsh stern "
        "menacing expression of a seasoned warrior. Shave her head completely bald, remove all "
        "hair and braids: bare scalp, bare neck and bare shoulders, no armor, no clothes, no "
        "jewelry. Keep her face exactly the same: heavy furrowed brow, deep-set eyes, broad nose, "
        "strong jaw, frowning lips, long pointed ears. Even olive green skin of the same tone on "
        "the face, scalp, neck and shoulders, with sharp skin pores. Plain light grey studio "
        "background, soft even shadowless frontal light, the whole head with both ears and the "
        "neck in frame, photorealistic, sharp focus."),
    # ельфійки (12.11.2026, слово замовника: «зроби ельфійок», кадри вікі ельф-жінка-v1..v3):
    # одне тіло (з v1) і три обличчя; висока тендітна (пам'ятка про пропорції ельфійки)
    "тіло-ельф-ж": (
        "Turn this elf woman into a clean base body reference for 3D modeling. Strict symmetric "
        "T-pose, front view, arms straight out to the sides at shoulder height, palms down, "
        "fingers spread apart, legs straight and slightly apart. Remove the shirt, vest, belts, "
        "bracers, trousers and boots: bare body, barefoot, wearing only plain tight black briefs "
        "and a plain tight black bandeau top. Shave her head completely bald, remove all hair. "
        "She is very tall and slender with long thin legs, narrow hips, narrow shoulders, thin "
        "arms and a long neck; crotch at half of her height. Keep her face, small pointed ears and "
        "pale fair skin exactly the same. Plain light grey studio background, soft even "
        "shadowless light, whole body from head to feet in frame, photorealistic."),
    "голова-ельф-ж": (
        "Close-up head and neck portrait of this same elf woman for 3D modeling, strict front "
        "view, head upright and level, looking straight at the camera, mouth closed, calm serious "
        "expression. She is a young woman: delicate feminine face, smooth pale fair skin, thin "
        "light eyebrows, slender long neck and narrow bare shoulders. Shave her head completely "
        "bald, remove all hair, remove clothes and jewelry. Keep her own facial features, eyes, "
        "nose, lips, cheekbones and small pointed ears exactly the same as in the image. Even "
        "skin tone on face, scalp, neck and shoulders. Plain light grey studio background, soft "
        "even shadowless frontal light, the whole head with both ears and the neck in frame, "
        "photorealistic, sharp focus."),
}


def arg(k, typ, d):
    return typ(sys.argv[sys.argv.index(k) + 1]) if k in sys.argv else d


def main():
    vyd, vhid, pref = sys.argv[1], sys.argv[2], sys.argv[3]
    instr = arg("--інстр", str, INSTR.get(vyd))
    sidy = [int(a) for a in sys.argv[4:] if a.isdigit()] or [5101]
    kadr = m.stage(vhid)
    for sd in sidy:
        kudy = "%s-s%d.png" % (pref, sd)
        if os.path.exists(kudy):
            continue
        g = b2.graf_qwen(kadr, kadr, instr, sd, "ork_znulia")
        g["1"]["inputs"]["unet_name"] = "qwen-image-edit-2511-Q4_K_M.gguf"
        g["2"]["inputs"]["lora_name"] = "Qwen-Image-Edit-2511-Lightning-8steps-V1.0-bf16.safetensors"
        for n in ("9", "10"):
            g[n]["inputs"].pop("image2", None)
        g["7"]["inputs"]["resolution_steps"] = 1
        g["7"]["inputs"]["megapixels"] = arg("--мп", float, 1.0)
        done = m.run(g)
        out = [o for v in done["outputs"].values() for o in v.get("images", [])][-1]
        shutil.copy(os.path.join(m.COMFY, "output", out["subfolder"], out["filename"]), kudy)
        print("готово", kudy, flush=True)
    m.free()


if __name__ == "__main__":
    main()
